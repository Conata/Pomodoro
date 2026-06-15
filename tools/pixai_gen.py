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
# main
# ──────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(
        description="PixAI model-comparison harness",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--prompt",  required=True, help="生成プロンプト")
    ap.add_argument("--neg",     default="lowres, bad anatomy, worst quality, blurry",
                    help="ネガティブプロンプト")
    ap.add_argument("--seed",    type=int, default=42)
    ap.add_argument("--width",   type=int, default=512)
    ap.add_argument("--height",  type=int, default=768)
    ap.add_argument("--out",     default="tools/_out/model_test",
                    help="出力ディレクトリ")
    group = ap.add_mutually_exclusive_group(required=True)
    group.add_argument("--models-file", metavar="FILE",
                       help="モデルリストファイル (pixai_models.txt)")
    group.add_argument("--model", metavar="ID[:NAME]",
                       help="単体モデル指定")
    args = ap.parse_args()

    api_key = load_api_key()

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
    for name, dest, ok in results:
        mark = "✓" if ok else "✗"
        print(f"  {mark} {name}: {dest if ok else 'FAILED'}")


if __name__ == "__main__":
    main()
