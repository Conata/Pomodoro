#!/usr/bin/env python3
"""
tools/gen_sprite.py — 探索チビスプライト生成（PixAI Tsubaki.2）

4 フレーム横並びシート（256×96 px）を生成し
assets/generated/sprites/<id>/<anim>.png に配置する。
Godot の _draw_chibi() が  シート幅 / CHIBI_FRAMES(4) をフレーム幅として自動読み込み。

使い方:
    python3 tools/gen_sprite.py yuzuki              # ユズキの全アニメ
    python3 tools/gen_sprite.py all                 # 全キャラ全アニメ
    python3 tools/gen_sprite.py mil --anim walk_front
    python3 tools/gen_sprite.py all --force         # 既存シートも上書き
    python3 tools/gen_sprite.py yuzuki --dry-run    # プロンプト確認のみ

APIキー設定:
    export PIXAI_API_KEY=sk_...   または .env に PIXAI_API_KEY=...

必要パッケージ:
    pip install Pillow
    pip install numpy scipy     # 背景キーイングの精度が上がる（任意）

出力:
    assets/generated/sprites/<id>/<anim>.png
        256 × 96 px, RGBA, 横並び 4 コマ
    tools/_out/sprite_raw/<id>/<anim>_f<n>_raw.png
        中間ファイル（512 × 768 の生成元）

キャラクタープロンプト定義:
    docs/design/characters.md / .claude/commands/gen-char.md を正とする。
    BASE に含めるタグ: chibi, pixel art, thick outline, flat color
    NEG : blurry, 3d, realistic, extra limbs
"""

import argparse
import json
import os
import sys
import time
import urllib.request
from pathlib import Path

try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    sys.exit("ERROR: Pillow が必要です:  pip install Pillow")

# ── 生成パラメータ ─────────────────────────────────────────────────
MODEL_ID   = "1983308862240288769"   # Tsubaki.2
GEN_W      = 512
GEN_H      = 768
FRAME_W    = 64    # 出力フレーム幅
FRAME_H    = 96    # 出力フレーム高さ（64×4 : 96 = 2.67頭身スプライトに最適）
FRAMES     = 4     # 1シート内フレーム数（CHIBI_FRAMES と一致させる）
STEPS      = 22
CFG        = 7
API_URL    = "https://api.pixai.art/graphql"
POLL_SEC   = 5
TIMEOUT    = 420
BG_HEX     = "1a1030"  # キーイング対象の背景色

REPO_ROOT  = Path(__file__).parent.parent
TMP_DIR    = Path(__file__).parent / "_out/sprite_raw"

# ── キャラクター定義 ───────────────────────────────────────────────
# BASE に世界観タグを含める（gen-char.md の Arknights / GFL スタイル）
CHARS = {
    "yuzuki": {
        "base": (
            "1girl, chibi, super deformed, 2.5 head height, pixel art style, "
            "thick black outline, flat color shading, vivid saturated colors, "
            "cute girl, orange twin tails, orange eyes, "
            "oversized black sweatshirt, plaid skirt, black boots, crossbody bag, "
            "Arknights style, near future cyberpunk, full body, front facing, "
            "masterpiece, best quality, "
            "flat single color background #1a1030"
        ),
        "neg": (
            "lowres, bad anatomy, extra limbs, deformed face, "
            "worst quality, blurry, cropped, multiple girls, 3d, realistic, "
            "text, watermark, gradient background"
        ),
        "seed_base": 1000,
    },
    "mil": {
        "base": (
            "1girl, chibi, super deformed, 2.5 head height, pixel art style, "
            "thick black outline, flat color shading, vivid saturated colors, "
            "short silver hair with pink inner highlights, amber eyes, "
            "oversized black leather jacket, pink crop top, black shorts, "
            "asymmetrical stockings, cyberpunk hacker girl, street fashion, Arknights style, "
            "near future cyberpunk, full body, front facing, "
            "masterpiece, best quality, "
            "flat single color background #1a1030"
        ),
        "neg": (
            "lowres, bad anatomy, extra limbs, deformed face, "
            "worst quality, blurry, cropped, multiple girls, 3d, realistic, "
            "warm background, gradient background, text, watermark"
        ),
        "seed_base": 2000,
    },
    "muu": {
        "base": (
            "1girl, chibi, super deformed, 2.5 head height, pixel art style, "
            "thick black outline, flat color shading, vivid saturated colors, "
            "cute fox girl, long blonde hair, fox ears, blue eyes, "
            "white oversized jacket, blue futuristic dress, yellow belt, "
            "idol streamer, cyber explorer, Arknights style, "
            "near future cyberpunk, full body, front facing, "
            "masterpiece, best quality, "
            "flat single color background #1a1030"
        ),
        "neg": (
            "lowres, bad anatomy, extra limbs, deformed face, "
            "worst quality, blurry, cropped, multiple girls, 3d, realistic, "
            "text, watermark, gradient background"
        ),
        "seed_base": 3000,
    },
    "kiriko": {
        "base": (
            "1girl, chibi, super deformed, 2.5 head height, pixel art style, "
            "thick black outline, flat color shading, vivid saturated colors, "
            "long blue hair, gold eyes, white ceremonial dress, "
            "cybernetic prosthetic leg, elegant cold expression, "
            "mental world administrator, Arknights style, "
            "near future cyberpunk, full body, front facing, "
            "masterpiece, best quality, "
            "flat single color background #1a1030"
        ),
        "neg": (
            "lowres, bad anatomy, extra limbs, deformed face, "
            "worst quality, blurry, cropped, multiple girls, 3d, realistic, "
            "text, watermark, gradient background"
        ),
        "seed_base": 4000,
    },
    "doctor": {
        "base": (
            "1man, chibi, super deformed, 2.5 head height, pixel art style, "
            "thick black outline, flat color shading, vivid saturated colors, "
            "handsome male doctor, long dark green hair, gray eyes, "
            "white oversized lab coat, black turtleneck, neck tattoo, "
            "futuristic psychiatrist, cyberpunk medical researcher, Arknights style, "
            "near future cyberpunk, full body, front facing, "
            "masterpiece, best quality, "
            "flat single color background #1a1030"
        ),
        "neg": (
            "lowres, bad anatomy, extra limbs, deformed face, "
            "worst quality, blurry, cropped, multiple people, 3d, realistic, "
            "text, watermark, gradient background"
        ),
        "seed_base": 6000,
    },
    "nurse": {
        "base": (
            "1girl, chibi, super deformed, 2.5 head height, pixel art style, "
            "thick black outline, flat color shading, vivid saturated colors, "
            "female android nurse, mint green hair, green eyes, "
            "white nurse dress with green accents, mechanical legs, "
            "medical support android, gentle expression, Arknights style, "
            "near future cyberpunk, full body, front facing, "
            "masterpiece, best quality, "
            "flat single color background #1a1030"
        ),
        "neg": (
            "lowres, bad anatomy, extra limbs, deformed face, "
            "worst quality, blurry, cropped, multiple people, 3d, realistic, "
            "text, watermark, gradient background"
        ),
        "seed_base": 7000,
    },
}

# ── アニメーション定義 ─────────────────────────────────────────────
# 各アニメ: [(name_suffix, 追加ポーズプロンプト, seed_offset)]
# seed = CHARS[id]["seed_base"] + offset
ANIMS = {
    "walk_front": [
        ("f0", "standing neutral pose, arms relaxed at sides, feet together, facing viewer", 0),
        ("f1", "mid-walk step, left foot forward, right arm slightly raised, light lean", 1),
        ("f2", "walking stride upright, arms mid-swing, slight bounce",                   2),
        ("f3", "mid-walk step, right foot forward, left arm slightly raised, light lean", 3),
    ],
    "attack": [
        ("f0", "combat ready stance, feet apart, fists raised, determined fierce expression", 10),
        ("f1", "launching attack, arm thrusting forward powerfully, body twisting",           11),
        ("f2", "attack fully extended, arm outstretched, impact moment, dynamic pose",        12),
        ("f3", "recovering from attack, returning to guard stance, confident ready",          13),
    ],
}

# ── GraphQL ────────────────────────────────────────────────────────
MUTATION_CREATE = """
mutation CreateTask($parameters: JSONObject!) {
  createGenerationTask(parameters: $parameters) { id }
}
"""
QUERY_TASK = """
query GetTask($id: ID!) {
  task(id: $id) {
    status
    media { urls { variant url } }
  }
}
"""


def load_api_key() -> str:
    key = os.getenv("PIXAI_API_KEY", "")
    if not key:
        env_path = REPO_ROOT / ".env"
        if env_path.exists():
            for line in env_path.read_text().splitlines():
                line = line.strip()
                if line.startswith("PIXAI_API_KEY="):
                    key = line.split("=", 1)[1].strip().strip('"').strip("'")
    if not key:
        sys.exit("ERROR: PIXAI_API_KEY が見つかりません。export または .env に設定してください。")
    return key


def gql(api_key: str, query: str, variables: dict) -> dict:
    payload = json.dumps({"query": query, "variables": variables}).encode()
    req = urllib.request.Request(
        API_URL, data=payload,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.loads(r.read())
    if "errors" in data:
        raise RuntimeError(f"GraphQL error: {data['errors']}")
    return data["data"]


def create_task(api_key: str, base_prompt: str, neg_prompt: str,
                pose_prompt: str, seed: int) -> str:
    full_prompt = f"{base_prompt}, {pose_prompt}"
    params = {
        "modelId":        MODEL_ID,
        "prompts":        full_prompt,
        "negativePrompts": neg_prompt,
        "samplingSteps":  STEPS,
        "samplingMethod": "dpmpp_2m_karras",
        "cfgScale":       CFG,
        "width":          GEN_W,
        "height":         GEN_H,
        "seed":           seed,
    }
    return gql(api_key, MUTATION_CREATE, {"parameters": params})["createGenerationTask"]["id"]


def poll_task(api_key: str, task_id: str) -> str | None:
    deadline = time.time() + TIMEOUT
    while time.time() < deadline:
        task = gql(api_key, QUERY_TASK, {"id": task_id})["task"]
        status = task.get("status", "?")
        print(f"    {status}", end=" ", flush=True)
        if status in ("succeeded", "completed"):
            urls = (task.get("media") or {}).get("urls") or []
            for e in urls:
                if e.get("variant") == "full":
                    return e["url"]
            return urls[0]["url"] if urls else None
        if status in ("failed", "cancelled", "error"):
            return None
        time.sleep(POLL_SEC)
    return None


def download(url: str, dest: Path):
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "gen_sprite/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        dest.write_bytes(r.read())


def key_background(src: Path, tol: int = 22) -> Image.Image:
    """
    単色背景 (BG_HEX) を縁のフラッドフィルで透過に抜く。
    numpy/scipy がある場合は連結成分ラベリングで精度アップ。
    戻り値: RGBA Image
    """
    img = Image.open(src).convert("RGBA")
    r0 = int(BG_HEX[0:2], 16)
    g0 = int(BG_HEX[2:4], 16)
    b0 = int(BG_HEX[4:6], 16)

    try:
        import numpy as np
        from scipy import ndimage
        a = np.array(img)
        rgb = a[:, :, :3].astype(int)
        near = (
            (abs(rgb[:, :, 0] - r0) <= tol) &
            (abs(rgb[:, :, 1] - g0) <= tol) &
            (abs(rgb[:, :, 2] - b0) <= tol)
        )
        lbl, _ = ndimage.label(near)
        border_labels = (
            set(lbl[0, :]) | set(lbl[-1, :]) |
            set(lbl[:, 0]) | set(lbl[:, -1])
        ) - {0}
        mask = np.isin(lbl, list(border_labels))
        a[mask, 3] = 0
        return Image.fromarray(a)
    except ImportError:
        # scipy なし: 単純フラッドフィル（Pillow の floodfill は使えないため角ピクセルで代用）
        return img


def downscale_nearest(img: Image.Image, w: int, h: int) -> Image.Image:
    """NEAREST で縮小（ドット感を保つ）"""
    return img.resize((w, h), Image.NEAREST)


def assemble_sheet(frames: list[Image.Image]) -> Image.Image:
    """4 フレームを横並びに結合 → 256×96"""
    assert len(frames) == FRAMES
    sheet = Image.new("RGBA", (FRAME_W * FRAMES, FRAME_H), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        sheet.paste(f, (i * FRAME_W, 0), f)
    return sheet


# ── 生成ロジック ───────────────────────────────────────────────────

def generate_sprite_sheet(
    api_key: str,
    char_id: str,
    anim_name: str,
    force: bool = False,
) -> bool:
    dest = REPO_ROOT / f"assets/generated/sprites/{char_id}/{anim_name}.png"
    if dest.exists() and not force:
        print(f"  skip (exists): {dest.relative_to(REPO_ROOT)}")
        return True

    char  = CHARS[char_id]
    anim  = ANIMS[anim_name]
    tmp_d = TMP_DIR / char_id
    tmp_d.mkdir(parents=True, exist_ok=True)

    frames: list[Image.Image] = []
    total = len(anim)

    for i, (suffix, pose_prompt, seed_off) in enumerate(anim, 1):
        seed = char["seed_base"] + seed_off
        tmp  = tmp_d / f"{anim_name}_{suffix}_raw.png"

        print(f"  [{i}/{total}] {anim_name}/{suffix} (seed={seed}) ", end="", flush=True)

        if tmp.exists() and not force:
            print("(cached raw) ", end="", flush=True)
        else:
            task_id = create_task(
                api_key, char["base"], char["neg"], pose_prompt, seed
            )
            url = poll_task(api_key, task_id)
            print()
            if not url:
                print(f"    ✗ FAILED (no URL)")
                return False
            download(url, tmp)

        # キーイング → NEAREST ダウンスケール → フレームリストに追加
        keyed = key_background(tmp)
        frame = downscale_nearest(keyed, FRAME_W, FRAME_H)
        frames.append(frame)
        print(f"    → {FRAME_W}×{FRAME_H} keyed", flush=True)

    sheet = assemble_sheet(frames)
    dest.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(str(dest), "PNG")
    print(f"  ✓ saved → {dest.relative_to(REPO_ROOT)}  ({FRAME_W*FRAMES}×{FRAME_H})")
    return True


# ── main ──────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(
        description="探索チビスプライト生成（PixAI Tsubaki.2）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    ap.add_argument(
        "char_id",
        choices=list(CHARS) + ["all"],
        help="キャラID (yuzuki / mil / muu / kiriko / all)",
    )
    ap.add_argument(
        "--anim",
        help="カンマ区切りアニメ名 (例: walk_front,attack)。省略時は全アニメ",
    )
    ap.add_argument("--force",   action="store_true", help="既存シートも上書き")
    ap.add_argument("--dry-run", action="store_true", help="プロンプトを表示するだけで生成しない")
    args = ap.parse_args()

    char_ids = list(CHARS) if args.char_id == "all" else [args.char_id]
    anim_keys = args.anim.split(",") if args.anim else list(ANIMS)

    # 不正なアニメ名チェック
    for a in anim_keys:
        if a not in ANIMS:
            ap.error(f"不明なアニメ名: {a}  (選択肢: {list(ANIMS)})")

    if args.dry_run:
        print("=== dry-run: プロンプト確認 ===\n")
        for cid in char_ids:
            char = CHARS[cid]
            for anim_name in anim_keys:
                anim = ANIMS[anim_name]
                print(f"▶ {cid} / {anim_name}")
                for suffix, pose_prompt, seed_off in anim:
                    seed = char["seed_base"] + seed_off
                    full = f"{char['base']}, {pose_prompt}"
                    print(f"  {suffix} (seed={seed}): {full[:100]}…")
                print()
        return

    api_key = load_api_key()
    ok = fail = 0

    for char_id in char_ids:
        print(f"\n▶ {char_id}")
        for anim_name in anim_keys:
            print(f"\n  アニメ: {anim_name}")
            try:
                if generate_sprite_sheet(api_key, char_id, anim_name, args.force):
                    ok += 1
                else:
                    fail += 1
            except Exception as e:
                print(f"  ✗ ERROR ({char_id}/{anim_name}): {e}", flush=True)
                fail += 1

    total = len(char_ids) * len(anim_keys)
    print(f"\n── 完了: {ok}/{total} 成功, {fail} 失敗 ──")
    if ok:
        print("\nGodot で再インポート:")
        print("  /Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .")


if __name__ == "__main__":
    main()
