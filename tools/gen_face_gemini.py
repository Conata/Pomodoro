#!/usr/bin/env python3
"""
Gemini API を使ってキャラクター表情差分を生成する。
各キャラの neutral_closed.png を入力画像として渡し、
表情（smile/surprise/calm/eat）×口状態（closed/half/open/blink）の差分を生成。

使い方:
    pip install google-genai pillow numpy scipy
    export GEMINI_API_KEY=AIza...   # または .env に記入
    python3 tools/gen_face_gemini.py                         # 全キャラ差分のみ
    python3 tools/gen_face_gemini.py --char mil              # ミルのみ
    python3 tools/gen_face_gemini.py --char muu --force      # ムュウ全上書き
    python3 tools/gen_face_gemini.py --variant smile_open    # 全キャラの smile_open のみ
    python3 tools/gen_face_gemini.py --list-models           # 利用可能モデル確認

生成後:
    /Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .
"""

import argparse
import base64
import io
import os
import sys
import time
from pathlib import Path

# ── 設定 ──────────────────────────────────────────────────────────────────
MODEL      = "gemini-3-pro-image-preview"
# 他の候補（--model で切り替え可）:
# MODEL = "gemini-3.1-flash-image"
# MODEL = "gemini-3.1-flash-image-preview"
# MODEL = "gemini-2.5-flash-image"

OUT_BASE   = Path(__file__).parent.parent / "assets/generated/face"
TMP_BASE   = Path(__file__).parent / "_out/face_gemini_raw"
KEY_TOL    = 30   # 背景キー許容差（ピクセル値）


# ── キャラクター定義 ──────────────────────────────────────────────────────
# appearance: 見た目の説明（一致性を保つために毎回添付）
# bg_color:   背景色（キーイング用）。None=自動検出
CHARS = {
    "mil": {
        "appearance": (
            "chibi super deformed anime girl, 2 head tall, thick black outline, "
            "short silver hair with pink inner color, amber eyes, "
            "oversized black leather jacket, pink crop top, cyberpunk hacker style"
        ),
        "bg_color": None,
    },
    "yuzuki": {
        "appearance": (
            "chibi super deformed anime girl, 2 head tall, thick black outline, "
            "orange twin tails, orange eyes, "
            "oversized black sweatshirt, urban street fashion"
        ),
        "bg_color": None,
    },
    "muu": {
        "appearance": (
            "chibi super deformed anime fox girl, 2 head tall, thick black outline, "
            "long blonde hair, fox ears, blue eyes, "
            "white oversized jacket, idol streamer style"
        ),
        "bg_color": None,
    },
    "kiriko": {
        "appearance": (
            "chibi super deformed anime girl, 2 head tall, thick black outline, "
            "long blue hair, gold eyes, "
            "white ceremonial dress, cold elegant expression"
        ),
        "bg_color": None,
    },
}

# ── バリアント定義 ─────────────────────────────────────────────────────────
# (名前, 口の状態, 感情/目の状態)
# edit_instruction はあとで BASE_IMAGE + appearance から動的に作る
VARIANTS = [
    # ── neutral ──────────────────────────────────────────────────────────
    ("neutral_closed",  "mouth closed",           "neutral calm face, eyes open and relaxed"),
    ("neutral_half",    "mouth slightly open",    "neutral calm face, eyes open and relaxed"),
    ("neutral_open",    "mouth open wide",        "neutral calm face, eyes open and relaxed"),
    ("neutral_blink",   "mouth closed",           "neutral calm face, eyes gently closed blinking"),
    # ── smile ─────────────────────────────────────────────────────────────
    ("smile_closed",    "lips gently curved closed smile",  "warm gentle smile, eyes softly curved happy"),
    ("smile_half",      "mouth slightly open smiling",      "warm gentle smile, eyes curved happy"),
    ("smile_open",      "mouth open laughing",              "joyful smile, eyes curved happy"),
    ("smile_blink",     "lips curved in smile mouth closed","content smile, eyes closed blissfully"),
    # ── surprise ──────────────────────────────────────────────────────────
    ("surprise_closed", "mouth closed",           "surprised wide open eyes, raised eyebrows, shocked look"),
    ("surprise_half",   "mouth slightly open",    "surprised wide open eyes, raised eyebrows, startled"),
    ("surprise_open",   "mouth open wide gasping","surprised wide open eyes, raised eyebrows, alarmed"),
    ("surprise_blink",  "eyes shut tight",        "eyes squeezed shut, flinching in surprise"),
    # ── calm ──────────────────────────────────────────────────────────────
    ("calm_closed",     "mouth closed firmly",    "focused determined eyes, serious resolute expression"),
    ("calm_half",       "mouth slightly open",    "focused determined eyes, concentrated look"),
    ("calm_open",       "mouth open speaking",    "focused determined eyes, speaking precisely"),
    ("calm_blink",      "mouth closed",           "eyes closed briefly, calm centered expression"),
    # ── eat ───────────────────────────────────────────────────────────────
    ("eat_closed",      "mouth closed chewing",   "content eating expression, satisfied eyes"),
    ("eat_half",        "mouth slightly open",    "enjoying food, savoring expression, half-closed eyes"),
    ("eat_open",        "mouth open taking bite", "eager to eat expression, eyes open"),
    ("eat_blink",       "mouth closed",           "eyes closed in delight, blissful eating expression"),
]

VARIANTS_BY_NAME = {v[0]: v for v in VARIANTS}


# ── プロンプト構築 ─────────────────────────────────────────────────────────
def build_instruction(appearance: str, mouth: str, emotion: str) -> str:
    return (
        f"This is a chibi anime character. "
        f"Edit the image MINIMALLY: ONLY change the facial expression. "
        f"The character should now have: {emotion}, {mouth}. "
        f"Do NOT change: hair color or style, eye color, clothing, head angle, "
        f"head position, body pose, or any other detail. "
        f"Keep the exact same thick black outline art style and flat color shading. "
        f"IMPORTANT: Replace the background with a pure solid black (#000000) background. "
        f"Character description to maintain: {appearance}. "
        f"Output only the edited image, same 512x512 size."
    )


# ── .env 読み込み ─────────────────────────────────────────────────────────
def load_api_key() -> str:
    key = os.getenv("GEMINI_API_KEY", "")
    if not key:
        env_path = Path(__file__).parent.parent / ".env"
        if env_path.exists():
            for line in env_path.read_text().splitlines():
                line = line.strip()
                if line.startswith("GEMINI_API_KEY="):
                    key = line.split("=", 1)[1].strip().strip('"').strip("'")
    if not key:
        sys.exit(
            "ERROR: GEMINI_API_KEY が見つかりません。\n"
            "  export GEMINI_API_KEY=AIza...\n"
            "  または .env に GEMINI_API_KEY=AIza... を追記してください。"
        )
    return key


# ── Gemini API 呼び出し ───────────────────────────────────────────────────
def generate_variant(client, model_name: str, base_img_bytes: bytes,
                     instruction: str, retries: int = 2) -> bytes | None:
    """base_img_bytes を入力画像として instruction で編集した画像を返す（PNG bytes）。"""
    from google.genai import types

    parts = [
        types.Part.from_bytes(data=base_img_bytes, mime_type="image/png"),
        types.Part.from_text(text=instruction),
    ]
    for attempt in range(retries + 1):
        try:
            response = client.models.generate_content(
                model=model_name,
                contents=parts,
                config=types.GenerateContentConfig(
                    response_modalities=["IMAGE"],
                ),
            )
            if not response.candidates:
                print(f"[no candidates, attempt {attempt+1}]", end=" ")
                time.sleep(3)
                continue
            for part in response.candidates[0].content.parts:
                if hasattr(part, "inline_data") and part.inline_data:
                    return part.inline_data.data  # bytes
            # IMAGE が返らなかった（TEXT のみ）→ モデルが応答拒否の可能性
            text_parts = [
                p.text for p in response.candidates[0].content.parts
                if hasattr(p, "text") and p.text
            ]
            if text_parts:
                print(f"[model returned text only: {text_parts[0][:80]!r}]", end=" ")
            else:
                print(f"[no image in response, attempt {attempt+1}]", end=" ")
            time.sleep(3)
        except Exception as e:
            msg = str(e)
            if "429" in msg or "RESOURCE_EXHAUSTED" in msg:
                wait = 60 * (attempt + 1)
                print(f"[rate limit, wait {wait}s]", end=" ", flush=True)
                time.sleep(wait)
            elif "500" in msg or "503" in msg:
                print(f"[server error {attempt+1}: {msg[:60]}]", end=" ")
                time.sleep(10)
            else:
                print(f"[error: {msg[:80]}]", end=" ")
                if attempt == retries:
                    return None
                time.sleep(5)
    return None


# ── 背景キーイング ────────────────────────────────────────────────────────
def key_background(src_bytes: bytes, dst: Path, tol: int = KEY_TOL):
    """4 隅それぞれ独立フラッドフィルで背景を透過に抜く。"""
    from PIL import Image
    try:
        import numpy as np
        from scipy import ndimage

        img = Image.open(io.BytesIO(src_bytes)).convert("RGBA")
        a = np.array(img)
        h, w = a.shape[:2]
        combined_mask = np.zeros((h, w), dtype=bool)

        corners = [(0, 0), (0, w - 1), (h - 1, 0), (h - 1, w - 1)]
        for (cr, cc) in corners:
            r0, g0, b0 = int(a[cr, cc, 0]), int(a[cr, cc, 1]), int(a[cr, cc, 2])
            rgb = a[:, :, :3].astype(int)
            near = (
                (abs(rgb[:, :, 0] - r0) <= tol) &
                (abs(rgb[:, :, 1] - g0) <= tol) &
                (abs(rgb[:, :, 2] - b0) <= tol)
            )
            lbl, _ = ndimage.label(near)
            border_ids = (
                set(lbl[0, :]) | set(lbl[-1, :]) |
                set(lbl[:, 0]) | set(lbl[:, -1])
            ) - {0}
            combined_mask |= np.isin(lbl, list(border_ids))

        a[combined_mask, 3] = 0
        result = Image.fromarray(a)
        # 512×512 にリサイズ（Gemini は 1024px で出力する場合がある）
        if result.size != (512, 512):
            result = result.resize((512, 512), Image.LANCZOS)
        dst.parent.mkdir(parents=True, exist_ok=True)
        result.save(dst)
        transparent_pct = 100 * combined_mask.sum() / (h * w)
        print(f"keyed({transparent_pct:.0f}%)", end=" ")
    except ImportError:
        img = Image.open(io.BytesIO(src_bytes)).convert("RGBA")
        if img.size != (512, 512):
            img = img.resize((512, 512), Image.LANCZOS)
        dst.parent.mkdir(parents=True, exist_ok=True)
        img.save(dst)
        print("saved(no-key)", end=" ")


# ── メイン ────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--char",    default="all",
                        help="キャラ名 (mil/yuzuki/muu/kiriko/all)")
    parser.add_argument("--variant", default=None,
                        help="特定バリアントのみ生成 (例: smile_open)")
    parser.add_argument("--force",   action="store_true",
                        help="既存ファイルも上書き")
    parser.add_argument("--model",   default=MODEL,
                        help=f"Gemini モデル名 (default: {MODEL})")
    parser.add_argument("--list-models", action="store_true",
                        help="利用可能なモデル一覧を表示して終了")
    parser.add_argument("--base", default=None,
                        help="ベース画像を上書き指定（パス）。省略時は neutral_closed.png を使用")
    args = parser.parse_args()

    api_key = load_api_key()

    from google import genai
    client = genai.Client(api_key=api_key)

    if args.list_models:
        print("── 利用可能モデル（image generation 候補）──")
        for m in client.models.list():
            if "image" in m.name.lower() or "flash" in m.name.lower():
                print(f"  {m.name}")
        return

    model_name = args.model

    # 対象キャラ
    if args.char == "all":
        char_list = list(CHARS.keys())
    elif args.char in CHARS:
        char_list = [args.char]
    else:
        sys.exit(f"ERROR: unknown char '{args.char}'. Choose from: {list(CHARS.keys())}")

    # 対象バリアント
    if args.variant:
        if args.variant not in VARIANTS_BY_NAME:
            sys.exit(f"ERROR: unknown variant '{args.variant}'")
        target_variants = [VARIANTS_BY_NAME[args.variant]]
    else:
        target_variants = VARIANTS

    # neutral_closed は生成しない（元画像として使う）
    # ただし --force で neutral_closed を明示した場合は再生成
    if not args.variant:
        # デフォルト実行時は neutral_closed をスキップ（既存を使う）
        target_variants = [v for v in target_variants if v[0] != "neutral_closed"]

    print(f"モデル: {model_name}")
    print(f"キャラ: {char_list}")
    print(f"バリアント数/キャラ: {len(target_variants)}")
    print()

    for char in char_list:
        cfg = CHARS[char]
        out_dir = OUT_BASE / char
        tmp_dir = TMP_BASE / char
        tmp_dir.mkdir(parents=True, exist_ok=True)

        # ベース画像を読み込む（--base で上書き可、デフォルトは neutral_closed.png）
        if args.base:
            base_path = Path(args.base)
        else:
            base_path = out_dir / "neutral_closed.png"
        if not base_path.exists():
            print(f"[{char}] ⚠ ベース画像が見つかりません: {base_path}")
            if not args.base:
                print(f"  先に PixAI スクリプト (gen_face_{char}.py --no-ref) で")
                print(f"  neutral_closed.png を生成してください。")
            print()
            continue

        print(f"  base: {base_path.name}")
        base_bytes = base_path.read_bytes()
        print(f"── {char} ({'%d' % len(target_variants)} variants) ──")

        for name, mouth, emotion in target_variants:
            dst = out_dir / f"{name}.png"
            if dst.exists() and not args.force:
                print(f"  {name:20s} → skip")
                continue

            instruction = build_instruction(cfg["appearance"], mouth, emotion)
            print(f"  {name:20s} ... ", end="", flush=True)

            img_bytes = generate_variant(client, model_name, base_bytes, instruction)
            if img_bytes is None:
                print("FAILED")
                continue

            # 生ファイルを tmp に保存（デバッグ用）
            tmp_raw = tmp_dir / f"{name}_raw.png"
            tmp_raw.write_bytes(img_bytes)

            key_background(img_bytes, dst)
            print(f"→ {dst.name}")

        print()

    print("完了。Godot で再インポートしてください:")
    print("  /Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .")


if __name__ == "__main__":
    main()
