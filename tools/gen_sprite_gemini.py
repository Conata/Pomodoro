#!/usr/bin/env python3
"""
Gemini API でキャラクターの全身ドット絵スプライトを生成する。

パイプライン:
  1. Gemini に「ドット絵スタイル参照画像」＋「キャラクターデザイン画像」を2枚渡す
  2. 指定ポーズで参照スタイルに合わせたドット絵スプライトを生成
  3. マゼンタ背景を透過キー
  4. ドット絵変換（32×48px にダウンスケール → 4× nearest-neighbor でアップスケール）
  5. 個別フレームファイルとして保存
     assets/generated/sprites/<char>/<anim>_f<n>.png

スタイル参照画像:
  docs/Refs/sprite_style_ref.png  （GBA/16-bitスタイルのドット絵サンプル）
  ※ 別途この画像をファイルに保存しておく必要があります

ドット絵サイズ（変更可）:
  DOT_W × DOT_H = 32 × 48   … 1フレームの実ドット数
  SCALE         = 4          … 表示用スケール倍率
  → 出力 PNG: 128 × 192 px (表示時の実サイズ)

アニメーション一覧:
  idle / walk / run / attack / hurt / die / jump / dash / skill

使い方:
    python3 tools/gen_sprite_gemini.py --char mil --anim idle --force
    python3 tools/gen_sprite_gemini.py --char mil               # 全アニメ差分
    python3 tools/gen_sprite_gemini.py --list-anims             # アニメ一覧
    python3 tools/gen_sprite_gemini.py --dotconv path/to/img.png  # 既存画像だけドット化
    python3 tools/gen_sprite_gemini.py --style-ref path/to/ref.png --char mil --anim idle
"""

import argparse
import io
import os
import sys
import time
from pathlib import Path

# ── 設定 ──────────────────────────────────────────────────────────────────
MODEL   = "gemini-3-pro-image-preview"
OUT_BASE = Path(__file__).parent.parent / "assets/generated/sprites"
TMP_BASE = Path(__file__).parent / "_out/sprite_gemini_raw"
KEY_TOL  = 40   # マゼンタキー許容差

# スタイル参照画像のデフォルトパス
STYLE_REF_DEFAULT = Path(__file__).parent.parent / "docs/Refs/sprite_style_ref.png"

# ドット絵サイズ設定
DOT_W   = 32    # 1フレームの実ドット幅
DOT_H   = 48    # 1フレームの実ドット高さ
SCALE   = 4     # 表示用スケール（nearest-neighbor）
OUT_W   = DOT_W * SCALE   # 128
OUT_H   = DOT_H * SCALE   # 192


# ── キャラクター定義（公式キャラデザイン画像を使用）────────────────────
CHARA_REF = Path(__file__).parent.parent / "docs/Refs/Chara"

CHARS = {
    "mil": {
        "appearance": (
            "chibi super deformed anime girl, 2 head tall, full body, "
            "short silver hair with pink inner, amber eyes, "
            "oversized black leather jacket, pink crop top, "
            "cyberpunk hacker style, thick black outlines"
        ),
        "base": CHARA_REF / "Milu.png",
    },
    "yuzuki": {
        "appearance": (
            "chibi super deformed anime girl, 2 head tall, full body, "
            "orange twin tails, orange eyes, "
            "oversized black sweatshirt, urban street fashion, "
            "thick black outlines"
        ),
        "base": CHARA_REF / "yuzuki.png",
    },
    "muu": {
        "appearance": (
            "chibi super deformed anime fox girl, 2 head tall, full body, "
            "long blonde hair, fox ears, blue eyes, "
            "white oversized jacket, idol streamer style, "
            "thick black outlines"
        ),
        "base": CHARA_REF / "myu.png",
    },
    "kiriko": {
        "appearance": (
            "chibi super deformed anime girl, 2 head tall, full body, "
            "long blue hair, gold eyes, "
            "white ceremonial dress, cold elegant expression, "
            "thick black outlines"
        ),
        "base": CHARA_REF / "reika.png",
    },
}

# ── アニメーション定義（ドット絵イメージに合わせた横向きポーズ）──────
# 参考: https://zenn.dev/kenji966/articles/70609b387152d0
ANIMS = {
    "idle": [
        "standing upright, facing right, relaxed arms at sides, weight on both feet",
        "standing upright, facing right, slight upward body sway, relaxed",
    ],
    "walk": [
        "walking right, right foot forward, left arm swinging, side view",
        "walking right, both feet together, upright, side view",
        "walking right, left foot forward, right arm swinging, side view",
        "walking right, feet together, arms lowering, side view",
    ],
    "run": [
        "running right fast, right leg extended, left arm pumped, leaning forward, side view",
        "running right, airborne both feet off ground, side view",
        "running right, left leg extended, right arm pumped, leaning forward, side view",
        "running right, pushing off ground, feet close, side view",
    ],
    "attack": [
        "attack wind-up, facing right, arm drawn back ready to strike, side view",
        "attack strike, arm fully extended punching forward, action pose, side view",
        "attack follow-through, arm extended, momentum continuing, side view",
        "attack recovery, returning to guard, alert, side view",
    ],
    "hurt": [
        "taking hit, body thrown backward, arms flung back, pain face, side view",
        "flinching, crouching, arms raised defensively, side view",
    ],
    "die": [
        "falling, knees buckling, side view",
        "collapsing, lying down, body going limp, side view",
        "lying on ground, defeated, side view",
    ],
    "jump": [
        "jumping up, knees bent, arms raised, side view",
        "peak of jump, body extended, side view",
    ],
    "dash": [
        "dashing right, body nearly horizontal, one leg extended, cape/hair streaming back, side view",
        "dash recovery, sliding to stop, low crouching stance, side view",
    ],
    "skill": [
        "skill charge, glowing energy around hands, dramatic pose, front view",
        "skill release, energy burst forward, action pose, front view",
    ],
}


# ── プロンプト ────────────────────────────────────────────────────────────
def build_prompt(appearance: str, pose: str, has_style_ref: bool = False) -> str:
    if has_style_ref:
        return (
            f"You are given TWO reference images:\n"
            f"  Image 1 = pixel art style guide (shows the exact art style, pixel size, and proportions to use)\n"
            f"  Image 2 = the character design to recreate (hair, eyes, clothing colors and style)\n\n"
            f"Task: Create a pixel art sprite of the character from Image 2, "
            f"rendered in the exact pixel art style shown in Image 1.\n\n"
            f"Pose: {pose}.\n\n"
            f"Requirements:\n"
            f"- Match Image 1's pixel art style EXACTLY: chunky visible pixels, limited flat color palette, "
            f"thick black outlines, GBA/16-bit RPG sprite proportions\n"
            f"- Preserve the character's exact hair color, eye color, and outfit design from Image 2\n"
            f"- FULL BODY from head to feet — do NOT crop at waist\n"
            f"- Same scale and sprite size as the characters shown in Image 1\n"
            f"- Character centered in frame\n"
            f"- BACKGROUND: solid bright MAGENTA (#FF00FF), no gradients, no floor, no shadow\n"
            f"Output a single sprite frame on magenta background."
        )
    else:
        return (
            f"Create a pixel art game character sprite. "
            f"Character: {appearance}. "
            f"Pose: {pose}. "
            f"CRITICAL style requirements: "
            f"retro pixel art style, visible chunky pixels, no anti-aliasing, "
            f"GBA / 16-bit RPG sprite style, "
            f"FULL BODY visible from head to feet (do NOT crop at waist), "
            f"2-head-tall chibi proportions, "
            f"clear thick black outlines around every body part, "
            f"limited flat color palette, "
            f"character centered in frame, takes up most of the vertical space. "
            f"BACKGROUND: solid bright MAGENTA (#FF00FF) — no gradients, no floor, no shadow. "
            f"Output a single pixel art sprite on magenta background."
        )


# ── API キー ──────────────────────────────────────────────────────────────
def load_api_key() -> str:
    key = os.getenv("GEMINI_API_KEY", "")
    if not key:
        env = Path(__file__).parent.parent / ".env"
        if env.exists():
            for line in env.read_text().splitlines():
                line = line.strip()
                if line.startswith("GEMINI_API_KEY="):
                    key = line.split("=", 1)[1].strip().strip('"').strip("'")
    if not key:
        sys.exit("ERROR: GEMINI_API_KEY が見つかりません (.env または環境変数に設定)")
    return key


# ── Gemini 呼び出し ───────────────────────────────────────────────────────
def call_gemini(client, model: str, base_bytes: bytes, prompt: str,
                style_ref_bytes: bytes | None = None,
                retries: int = 2) -> bytes | None:
    from google.genai import types
    if style_ref_bytes is not None:
        # 2枚入力: スタイル参照 → キャラ画像 → プロンプト
        parts = [
            types.Part.from_bytes(data=style_ref_bytes, mime_type="image/png"),
            types.Part.from_bytes(data=base_bytes, mime_type="image/png"),
            types.Part.from_text(text=prompt),
        ]
    else:
        parts = [
            types.Part.from_bytes(data=base_bytes, mime_type="image/png"),
            types.Part.from_text(text=prompt),
        ]
    for attempt in range(retries + 1):
        try:
            resp = client.models.generate_content(
                model=model, contents=parts,
                config=types.GenerateContentConfig(response_modalities=["IMAGE"]),
            )
            if not resp.candidates:
                time.sleep(3); continue
            for p in resp.candidates[0].content.parts:
                if hasattr(p, "inline_data") and p.inline_data:
                    return p.inline_data.data
            texts = [p.text for p in resp.candidates[0].content.parts
                     if hasattr(p, "text") and p.text]
            print(f"[text:{texts[0][:50]!r}]" if texts else f"[no-img #{attempt+1}]",
                  end=" ")
            time.sleep(3)
        except Exception as e:
            msg = str(e)
            if "429" in msg or "RESOURCE_EXHAUSTED" in msg:
                w = 60 * (attempt + 1)
                print(f"[rate-limit wait {w}s]", end=" ", flush=True)
                time.sleep(w)
            else:
                print(f"[err:{msg[:60]}]", end=" ")
                if attempt == retries: return None
                time.sleep(5)
    return None


# ── マゼンタキー ──────────────────────────────────────────────────────────
def key_magenta(img_bytes: bytes, tol: int = KEY_TOL):
    """マゼンタ背景を透過にして PIL Image (RGBA) を返す。"""
    from PIL import Image
    import numpy as np
    from scipy import ndimage

    img = Image.open(io.BytesIO(img_bytes)).convert("RGBA")
    a = np.array(img)
    h, w = a.shape[:2]
    mask = np.zeros((h, w), dtype=bool)
    for (r, c) in [(0, 0), (0, w-1), (h-1, 0), (h-1, w-1)]:
        r0, g0, b0 = int(a[r, c, 0]), int(a[r, c, 1]), int(a[r, c, 2])
        rgb = a[:, :, :3].astype(int)
        near = ((abs(rgb[:,:,0]-r0)<=tol) & (abs(rgb[:,:,1]-g0)<=tol)
                & (abs(rgb[:,:,2]-b0)<=tol))
        lbl, _ = ndimage.label(near)
        bids = (set(lbl[0,:]) | set(lbl[-1,:]) | set(lbl[:,0]) | set(lbl[:,-1])) - {0}
        mask |= np.isin(lbl, list(bids))
    a[mask, 3] = 0
    pct = round(100 * mask.sum() / (h * w))
    return Image.fromarray(a), pct


# ── ドット絵変換 ──────────────────────────────────────────────────────────
def to_pixel_art(img_rgba, dot_w: int = DOT_W, dot_h: int = DOT_H,
                 scale: int = SCALE):
    """
    高解像度 RGBA Image をドット絵サイズに縮小後、
    nearest-neighbor で拡大して「ドット感」を出す。
    """
    from PIL import Image
    small = img_rgba.resize((dot_w, dot_h), Image.LANCZOS)
    big   = small.resize((dot_w * scale, dot_h * scale), Image.NEAREST)
    return big


# ── 単画像のドット絵変換（--dotconv 用）──────────────────────────────────
def dotconv_file(src: Path, dst: Path,
                 dot_w: int = DOT_W, dot_h: int = DOT_H, scale: int = SCALE):
    from PIL import Image
    img = Image.open(src).convert("RGBA")
    result = to_pixel_art(img, dot_w, dot_h, scale)
    dst.parent.mkdir(parents=True, exist_ok=True)
    result.save(dst)
    print(f"{src.name} → {dst.name}  ({result.size[0]}×{result.size[1]})")


# ── メイン ────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--char",  default="all",
                        help="キャラ名 (mil/yuzuki/muu/kiriko/all)")
    parser.add_argument("--anim",  default=None,
                        help="アニメーション名")
    parser.add_argument("--force", action="store_true", help="既存ファイルも上書き")
    parser.add_argument("--model", default=MODEL)
    parser.add_argument("--base",  default=None, help="ベース画像パスを上書き")
    parser.add_argument("--style-ref", default=None,
                        help=f"ドット絵スタイル参照画像 (default: {STYLE_REF_DEFAULT})")
    parser.add_argument("--dot-w", type=int, default=DOT_W,
                        help=f"ドット幅 (default: {DOT_W})")
    parser.add_argument("--dot-h", type=int, default=DOT_H,
                        help=f"ドット高さ (default: {DOT_H})")
    parser.add_argument("--scale", type=int, default=SCALE,
                        help=f"拡大倍率 (default: {SCALE})")
    parser.add_argument("--list-anims",  action="store_true")
    parser.add_argument("--list-models", action="store_true")
    parser.add_argument("--dotconv", default=None,
                        help="既存画像をドット絵変換するだけ（パス指定）")
    args = parser.parse_args()

    dw, dh, sc = args.dot_w, args.dot_h, args.scale

    # ─ ドット変換のみ ─
    if args.dotconv:
        src = Path(args.dotconv)
        dst = src.parent / f"{src.stem}_dot{src.suffix}"
        dotconv_file(src, dst, dw, dh, sc)
        return

    if args.list_anims:
        print("── アニメーション一覧 ──")
        for name, frames in ANIMS.items():
            out_w = dw * sc * len(frames)
            print(f"  {name:8s} {len(frames)}F  個別ファイル: {name}_f0〜f{len(frames)-1}.png  ({dw*sc}×{dh*sc}px each)")
        return

    api_key = load_api_key()
    from google import genai
    client = genai.Client(api_key=api_key)

    if args.list_models:
        for m in client.models.list():
            if "image" in m.name.lower() or "flash" in m.name.lower():
                print(f"  {m.name}")
        return

    # 対象キャラ
    char_list = list(CHARS.keys()) if args.char == "all" else [args.char]
    if args.char != "all" and args.char not in CHARS:
        sys.exit(f"ERROR: unknown char '{args.char}'")

    # 対象アニメ
    if args.anim:
        if args.anim not in ANIMS:
            sys.exit(f"ERROR: unknown anim '{args.anim}'")
        target_anims = {args.anim: ANIMS[args.anim]}
    else:
        target_anims = ANIMS

    # スタイル参照画像を読み込む
    style_ref_path = Path(args.style_ref) if args.style_ref else STYLE_REF_DEFAULT
    style_ref_bytes = None
    if style_ref_path.exists():
        style_ref_bytes = style_ref_path.read_bytes()
        print(f"スタイル参照: {style_ref_path.name} ✓")
    else:
        print(f"スタイル参照: なし (単体入力モード) — {style_ref_path} が見つかりません")
        print(f"  ヒント: 参照画像を {STYLE_REF_DEFAULT} に保存してください")

    print(f"モデル: {args.model}")
    print(f"キャラ: {char_list}")
    print(f"アニメ: {list(target_anims.keys())}")
    print(f"ドット: {dw}×{dh} → {dw*sc}×{dh*sc}px (×{sc})")
    print()

    for char in char_list:
        cfg = CHARS[char]
        out_dir = OUT_BASE / char
        tmp_dir = TMP_BASE / char
        tmp_dir.mkdir(parents=True, exist_ok=True)

        base_path = Path(args.base) if args.base else cfg["base"]
        if not base_path.exists():
            print(f"[{char}] ⚠ ベース画像が見つかりません: {base_path}\n")
            continue

        base_bytes = base_path.read_bytes()
        print(f"── {char}  (base: {base_path.name}) ──")

        for anim_name, frame_descs in target_anims.items():
            for fi, pose in enumerate(frame_descs):
                name = f"{anim_name}_f{fi}"
                dst  = out_dir / f"{name}.png"

                if dst.exists() and not args.force:
                    print(f"  {name:18s} → skip")
                    continue

                prompt = build_prompt(cfg["appearance"], pose, has_style_ref=(style_ref_bytes is not None))
                print(f"  {name:18s} ...", end=" ", flush=True)

                raw = call_gemini(client, args.model, base_bytes, prompt, style_ref_bytes=style_ref_bytes)
                if raw is None:
                    print("FAILED")
                    continue

                # raw 保存
                (tmp_dir / f"{name}_raw.png").write_bytes(raw)

                # マゼンタキー
                try:
                    keyed, pct = key_magenta(raw)
                    print(f"key({pct}%)", end=" ", flush=True)
                except ImportError:
                    from PIL import Image
                    keyed = Image.open(io.BytesIO(raw)).convert("RGBA")
                    print("(no-key)", end=" ", flush=True)

                # ドット絵変換
                pixel_art = to_pixel_art(keyed, dw, dh, sc)
                dst.parent.mkdir(parents=True, exist_ok=True)
                pixel_art.save(dst)
                print(f"→ {dst.name} ({pixel_art.size[0]}×{pixel_art.size[1]})")

        print()

    print("完了。Godot で再インポートしてください:")
    print("  /Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .")


if __name__ == "__main__":
    main()
