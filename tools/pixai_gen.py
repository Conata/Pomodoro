#!/usr/bin/env python3
"""
tools/pixai_gen.py — PixAI model-comparison harness

Usage:
  python3 tools/pixai_gen.py \\
    --models-file tools/pixai_models.txt \\
    --prompt "1girl, occult scientist, long purple hair, bust, flat #1a1030 bg, anime" \\
    --seed 12345 \\
    --out tools/_out/model_test
  # → tools/_out/model_test/<id>_<name>.png  (1枚/モデル)

  # 単体モデルで試す
  python3 tools/pixai_gen.py \\
    --model 1983308862240288769:Tsubaki2 \\
    --prompt "..." --seed 1

API key（コミット厳禁）:
  export PIXAI_API_KEY=sk_...
  または repo直下の .env に  PIXAI_API_KEY=sk_...
"""

import argparse
import json
import os
import sys
import time
import urllib.request
from pathlib import Path

# ──────────────────────────────────────────────────────────────
# GraphQL 定数（フィールド名が違ったら HERE を直すだけ）
# ──────────────────────────────────────────────────────────────
API_URL = "https://api.pixai.art/graphql"

# タスク生成 — parameters は JSONObject
MUTATION_CREATE = """
mutation CreateTask($parameters: JSONObject!) {
  createGenerationTask(parameters: $parameters) {
    id
    status
  }
}
"""

# タスクポーリング
# ★ media.urls[].url が実際と違う場合は FIELD_* 定数を調整
QUERY_TASK = """
query GetTask($id: ID!) {
  task(id: $id) {
    id
    status
    media {
      id
      urls {
        variant
        url
      }
    }
  }
}
"""

# media.urls の "full" に相当する variant 名（なければ先頭を使う）
FIELD_VARIANT_FULL = "full"

POLL_INTERVAL_SEC = 5
POLL_TIMEOUT_SEC  = 360   # 6分


# ──────────────────────────────────────────────────────────────
# helpers
# ──────────────────────────────────────────────────────────────

def load_api_key() -> str:
    key = os.getenv("PIXAI_API_KEY", "")
    if not key:
        env_path = Path(__file__).parent.parent / ".env"
        if env_path.exists():
            for raw in env_path.read_text(encoding="utf-8").splitlines():
                line = raw.strip()
                if line.startswith("PIXAI_API_KEY="):
                    key = line.split("=", 1)[1].strip().strip('"').strip("'")
                    break
    if not key:
        sys.exit(
            "ERROR: PIXAI_API_KEY が見つかりません。\n"
            "  export PIXAI_API_KEY=sk_...  または .env に記入"
        )
    return key


def gql(api_key: str, query: str, variables: dict) -> dict:
    payload = json.dumps({"query": query, "variables": variables}).encode("utf-8")
    req = urllib.request.Request(
        API_URL,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {e.code}: {body[:400]}") from e

    if "errors" in data:
        raise RuntimeError(f"GraphQL errors: {json.dumps(data['errors'], ensure_ascii=False)}")
    return data["data"]


# ──────────────────────────────────────────────────────────────
# generation
# ──────────────────────────────────────────────────────────────

def create_task(api_key: str, model_id: str, prompt: str, neg: str,
                seed: int, width: int, height: int) -> str:
    params = {
        "modelId": model_id,
        "prompts": prompt,
        "negativePrompts": neg,
        "samplingSteps": 20,
        "samplingMethod": "dpmpp_2m_karras",
        "cfgScale": 7,
        "width": width,
        "height": height,
        "seed": seed,
    }
    data = gql(api_key, MUTATION_CREATE, {"parameters": params})
    return data["createGenerationTask"]["id"]


def extract_url(task: dict) -> str | None:
    """task dict から画像 URL を取り出す。フィールドが違ったらここを修正。"""
    media = task.get("media")
    if not media:
        return None
    urls = media.get("urls") or []
    if not urls:
        return None
    # FIELD_VARIANT_FULL が見つかればそれを、なければ先頭
    for entry in urls:
        if entry.get("variant") == FIELD_VARIANT_FULL:
            return entry.get("url")
    return urls[0].get("url")


def poll_task(api_key: str, task_id: str) -> str | None:
    deadline = time.time() + POLL_TIMEOUT_SEC
    while time.time() < deadline:
        data = gql(api_key, QUERY_TASK, {"id": task_id})
        task   = data["task"]
        status = task.get("status", "?")
        print(f"    status={status}", flush=True)
        if status in ("succeeded", "completed"):
            return extract_url(task)
        if status in ("failed", "cancelled", "error"):
            return None
        time.sleep(POLL_INTERVAL_SEC)
    print("    TIMEOUT", flush=True)
    return None


def download_image(url: str, dest: Path):
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "pixai_gen/1.0"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        dest.write_bytes(resp.read())


# ──────────────────────────────────────────────────────────────
# models file
# ──────────────────────────────────────────────────────────────

def load_models_file(path: str) -> list[tuple[str, str]]:
    """
    各行: <model_id>  <display_name>
    display_name 省略時は model_id をそのまま使う。
    # 始まりの行はコメント。
    """
    result = []
    for raw in Path(path).read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(None, 1)
        mid  = parts[0]
        name = parts[1].strip() if len(parts) > 1 else mid
        result.append((mid, name))
    return result


# ──────────────────────────────────────────────────────────────
# 顔表情フレーム生成（FaceCam SDキャラ専用）
# ──────────────────────────────────────────────────────────────

REPO_ROOT = Path(__file__).parent.parent

# 顔生成モデル固定: Tsubaki.2  ← SDキャラはこれで作る（★ルール）
FACE_MODEL_ID = "1983308862240288769"

FACE_CHARACTERS = {
    "mil": (
        "masterpiece, best quality, chibi, SD, 1girl, "
        "short white silver hair, pink inner color, "
        "oversized black jacket, pink crop top, no glasses, "
        "stoic dark heroine, pink reddish eyes"
    ),
    "yuzuki": (
        "masterpiece, best quality, chibi, SD, 1girl, "
        "short brown hair orange highlights, white chef uniform apron, "
        "cheerful ramen cook"
    ),
    "muu": (
        "masterpiece, best quality, chibi, SD, 1girl, "
        "pink magenta twin tails, idol streamer outfit, "
        "bright energetic vtuber"
    ),
    "kiriko": (
        "masterpiece, best quality, chibi, SD, 1girl, "
        "long purple hair, white lab coat, "
        "occult scientist, mysterious"
    ),
    "kiriko_npc": (
        "masterpiece, best quality, chibi, SD, 1girl, "
        "short light purple hair, casual outfit, friendly soft expression"
    ),
}

FACE_EXPR_PROMPTS = {
    "neutral":  "neutral relaxed expression",
    "smile":    "smiling happily, confident bright smile",
    "surprise": "surprised shocked, wide eyes open mouth",
    "calm":     "serene focused, half-lidded calm eyes",
    "eat":      "eating food, satisfied chewing, cheeks puffed",
}

FACE_STATE_PROMPTS = {
    "closed": "mouth closed, eyes open",
    "half":   "mouth slightly open, eyes open",
    "open":   "mouth wide open, eyes open",
    "blink":  "eyes fully closed, mouth closed",
}

FACE_NEG = (
    "lowres, bad anatomy, worst quality, blurry, "
    "realistic proportions, tall body, long legs, "
    "glasses, megane, eyewear"
)


def cmd_face(api_key: str, args) -> None:
    char_id = args.char_id
    exprs   = args.exprs.split(",")  if getattr(args, "exprs",  None) else list(FACE_EXPR_PROMPTS)
    states  = args.states.split(",") if getattr(args, "states", None) else list(FACE_STATE_PROMPTS)
    seed    = getattr(args, "seed",  42)
    force   = getattr(args, "force", False)

    if char_id not in FACE_CHARACTERS:
        sys.exit(f"ERROR: 未知のキャラID '{char_id}'  選択肢: {list(FACE_CHARACTERS)}")

    base_desc = FACE_CHARACTERS[char_id]
    out_dir   = REPO_ROOT / "assets" / "generated" / "face" / char_id
    out_dir.mkdir(parents=True, exist_ok=True)

    total = len(exprs) * len(states)
    ok = fail = 0

    print(f"\n▶ 顔表情フレーム生成: {char_id}  model=Tsubaki.2")
    print(f"  表情: {exprs}  状態: {states}  合計: {total} フレーム\n")

    for expr in exprs:
        for state in states:
            dest = out_dir / f"{expr}_{state}.png"
            if dest.exists() and not force:
                print(f"  skip (exists): {dest.name}")
                ok += 1
                continue

            prompt = (
                f"{base_desc}, "
                f"{FACE_EXPR_PROMPTS[expr]}, {FACE_STATE_PROMPTS[state]}, "
                "bust shot, flat solid background #1a1030, "
                "centered head, anime illustration"
            )

            print(f"  {expr}_{state} …", flush=True)
            try:
                task_id = create_task(api_key, FACE_MODEL_ID, prompt, FACE_NEG,
                                      seed, 512, 512)
                url = poll_task(api_key, task_id)
                if url:
                    download_image(url, dest)
                    print(f"    ✓ {dest.name}", flush=True)
                    ok += 1
                else:
                    print(f"    ✗ FAILED", flush=True)
                    fail += 1
            except Exception as e:
                print(f"    ✗ ERROR: {e}", flush=True)
                fail += 1

    print(f"\n  完了: {ok}/{total} 成功, {fail} 失敗")


# ──────────────────────────────────────────────────────────────
# モデル比較（旧来の動作）
# ──────────────────────────────────────────────────────────────

def cmd_compare(api_key: str, args) -> None:
    if args.models_file:
        models = load_models_file(args.models_file)
    else:
        parts = args.model.split(":", 1)
        models = [(parts[0], parts[1] if len(parts) > 1 else parts[0])]

    if not models:
        sys.exit("ERROR: モデルが1件もありません")

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"出力先: {out_dir.resolve()}", flush=True)
    print(f"プロンプト: {args.prompt[:80]}{'...' if len(args.prompt)>80 else ''}", flush=True)
    print(f"seed={args.seed}  {args.width}x{args.height}  {len(models)}モデル\n", flush=True)

    results = []
    for mid, name in models:
        safe = name.replace(" ", "_").replace("/", "-")
        dest = out_dir / f"{mid}_{safe}.png"
        print(f"▶ [{name}]  id={mid}", flush=True)
        try:
            task_id = create_task(api_key, mid, args.prompt, args.neg,
                                  args.seed, args.width, args.height)
            print(f"  task_id={task_id}", flush=True)
            url = poll_task(api_key, task_id)
            if url:
                download_image(url, dest)
                print(f"  ✓ saved → {dest}", flush=True)
                results.append((name, dest, True))
            else:
                print(f"  ✗ FAILED (no URL)", flush=True)
                results.append((name, dest, False))
        except Exception as e:
            print(f"  ✗ ERROR: {e}", flush=True)
            results.append((name, dest, False))

    print("\n── 結果 ──")
    for name, dest, ok_flag in results:
        mark = "✓" if ok_flag else "✗"
        print(f"  {mark} {name}: {dest if ok_flag else 'FAILED'}")


# ──────────────────────────────────────────────────────────────
# main
# ──────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(
        description="PixAI 生成ツール",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = ap.add_subparsers(dest="cmd")

    # face — SDキャラ顔表情フレーム生成（Tsubaki.2 固定）
    p_face = sub.add_parser("face", help="顔表情フレームを生成（Tsubaki.2 固定・SDキャラ）")
    p_face.add_argument("char_id", choices=list(FACE_CHARACTERS))
    p_face.add_argument("--exprs",  help="カンマ区切り表情 (例: neutral,smile)")
    p_face.add_argument("--states", help="カンマ区切り状態 (例: closed,half,open,blink)")
    p_face.add_argument("--seed",   type=int, default=42)
    p_face.add_argument("--force",  action="store_true", help="既存を上書き")

    # compare — モデル比較・単体生成（旧来の動作）
    p_cmp = sub.add_parser("compare", help="モデル比較・単体生成")
    p_cmp.add_argument("--prompt",  required=True)
    p_cmp.add_argument("--neg",     default="lowres, bad anatomy, worst quality, blurry")
    p_cmp.add_argument("--seed",    type=int, default=42)
    p_cmp.add_argument("--width",   type=int, default=512)
    p_cmp.add_argument("--height",  type=int, default=768)
    p_cmp.add_argument("--out",     default="tools/_out/model_test")
    grp = p_cmp.add_mutually_exclusive_group(required=True)
    grp.add_argument("--models-file", metavar="FILE")
    grp.add_argument("--model",       metavar="ID[:NAME]")

    args = ap.parse_args()
    if args.cmd is None:
        ap.print_help()
        sys.exit(1)

    api_key = load_api_key()

    if args.cmd == "face":
        cmd_face(api_key, args)
    elif args.cmd == "compare":
        cmd_compare(api_key, args)


if __name__ == "__main__":
    main()
