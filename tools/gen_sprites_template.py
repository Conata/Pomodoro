#!/usr/bin/env python3
"""
gen_sprites_template.py
Eris Esra の 16x32 テンプレートシートをベースに Gemini でキャラ改変スプライトを生成する。

アプローチ:
  1. テンプレートシートの row 0（ポーズ列）を 4倍スケールアップして Gemini に渡す
  2. キャラ参照画像と共に送信
  3. 「同じポーズ・同じ pixel art スタイル、別キャラカラー」のストリップを生成
  4. 16px グリッドでスライス → バウンディングボックス＋底辺アンカーで出力フレームに変換

現在対応アニメーション（テンプレートあり）:
  idle(8f)  run(12f)  walk(8f)  attack(14f)  jump(10f)  acquire(8f)

使い方:
    python3 tools/gen_sprites_template.py --char mil
    python3 tools/gen_sprites_template.py --char all
    python3 tools/gen_sprites_template.py --char mil --anims idle run --force
    python3 tools/gen_sprites_template.py --slice-only tools/_out/template_raw/mil_run_strip.png \\
        --char mil --anim run
"""

import argparse
import io
import os
import sys
import time
from pathlib import Path

# ── パス ──────────────────────────────────────────────────────────────────
ROOT         = Path(__file__).parent.parent
TEMPLATE_DIR = ROOT / "docs/chara-template/Eris Esra's Character Template 4.1/16x32"
CHARA_REF    = ROOT / "docs/Refs/Chara"
OUT_BASE     = ROOT / "assets/generated/sprites"
RAW_DIR      = Path(__file__).parent / "_out/template_raw"

# ── モデル ────────────────────────────────────────────────────────────────
MODEL = "gemini-3-pro-image-preview"

# ── テンプレートサイズ ────────────────────────────────────────────────────
TMPL_W       = 16   # テンプレート 1 フレームの幅
TMPL_H       = 32   # テンプレート 1 フレームの高さ
TMPL_UPSCALE = 8    # Gemini へ渡す際の拡大倍率 → 128×256px/frame

# ── 出力サイズ ────────────────────────────────────────────────────────────
DOT_W  = 48   # 中間ドットサイズ
DOT_H  = 64
SCALE  = 3    # NEAREST 拡大 → 最終 144×192px

# ── アニメ定義: name → (シートファイル名, 1行のフレーム数) ────────────────
ANIM_SHEET_MAP: dict[str, tuple[str, int]] = {
    "idle":    ("16x32 Idle-Sheet.png",     8),
    "run":     ("16x32 Run-Sheet.png",      12),
    "walk":    ("16x32 Walk-Sheet.png",     8),
    "attack":  ("16x32 Attack-Sheet.png",   14),
    "jump":    ("16x32 Jump-Sheet.png",     10),
    "acquire": ("16x32 Interact-Sheet.png", 8),
}

# ── キャラクター定義 ───────────────────────────────────────────────────────
CHARS: dict[str, Path] = {
    "mil":    CHARA_REF / "Milu.png",
    "yuzuki": CHARA_REF / "yuzuki.png",
    "muu":    CHARA_REF / "myu.png",
    "kiriko": CHARA_REF / "reika.png",
    "doctor": CHARA_REF / "doc.png",
    "nurse":  CHARA_REF / "nurse.png",
}

CHAR_DESC: dict[str, str] = {
    "mil":    "short silver hair with pink inner color, amber eyes, oversized black leather jacket, pink crop top",
    "yuzuki": "long orange twin tails, orange eyes, oversized black sweatshirt, street fashion",
    "muu":    "long blonde hair, fox ears, blue eyes, white oversized jacket, blue futurist dress",
    "kiriko": "long blue hair, gold eyes, white ceremonial dress, elegant expression",
    "doctor": "short dark hair, white lab coat over teal scrubs, calm professional look",
    "nurse":  "light wavy hair, white nurse uniform with nurse cap, gentle kind expression",
}


# ── API キー ──────────────────────────────────────────────────────────────
def load_api_key() -> str:
    key = os.getenv("GEMINI_API_KEY", "")
    if not key:
        env = ROOT / ".env"
        if env.exists():
            for line in env.read_text().splitlines():
                if line.strip().startswith("GEMINI_API_KEY="):
                    key = line.split("=", 1)[1].strip().strip('"').strip("'")
    if not key:
        sys.exit("ERROR: GEMINI_API_KEY が見つかりません")
    return key


# ── テンプレート抽出 ──────────────────────────────────────────────────────
def extract_row0(sheet_path: Path, frame_count: int) -> bytes:
    """
    テンプレートシートの row 0（y=0..TMPL_H-1）を抽出し、
    TMPL_UPSCALE 倍に NEAREST 拡大して PNG bytes を返す。
    """
    from PIL import Image
    img   = Image.open(sheet_path).convert("RGBA")
    strip = img.crop((0, 0, frame_count * TMPL_W, TMPL_H))
    big   = strip.resize(
        (strip.width * TMPL_UPSCALE, strip.height * TMPL_UPSCALE),
        Image.NEAREST,
    )
    buf = io.BytesIO()
    big.save(buf, format="PNG")
    return buf.getvalue()


# ── プロンプト ────────────────────────────────────────────────────────────
import math

GAP_PX   = 16   # フレーム間マゼンタギャップ幅
GRID_COLS = 7   # グリッド形式の列数（攻撃等フレームが多いアニメ向け）


def _grid_dims(frame_count: int) -> tuple[int, int]:
    """フレーム数からグリッドの (cols, rows) を決める。"""
    cols = min(frame_count, GRID_COLS)
    rows = math.ceil(frame_count / cols)
    return cols, rows


def build_prompt(anim: str, frame_count: int, char_desc: str) -> str:
    fw   = TMPL_W * TMPL_UPSCALE   # 128  (1フレーム幅)
    fh   = TMPL_H * TMPL_UPSCALE   # 256  (高さ)
    cols, rows = _grid_dims(frame_count)
    total_w = cols * fw
    total_h = rows * fh
    return (
        f"You are given TWO images:\n"
        f"  Image 1 = a pixel art sprite sheet template: "
        f"{frame_count} frames of a '{anim}' animation cycle, "
        f"each frame is {fw}x{fh}px, laid out as a {cols}-column × {rows}-row grid "
        f"(left to right, top to bottom).\n"
        f"  Image 2 = the character design to use (colors and outfit)\n\n"
        f"Your task: RECOLOR / RESTYLE Image 1 using the character from Image 2.\n\n"
        f"CRITICAL — what you MUST do:\n"
        f"  1. Use Image 1 as an exact POSE TEMPLATE. For every cell, "
        f"reproduce the EXACT same body pose: head tilt, arm/leg positions, "
        f"foot placement. Poses must match Image 1 frame-for-frame.\n"
        f"  2. Apply the character design from Image 2: {char_desc}\n"
        f"  3. Keep the same pixel art style: blocky pixels, thick black outlines, "
        f"flat limited color palette.\n\n"
        f"CRITICAL — grid layout:\n"
        f"  - Output EXACTLY {cols} columns × {rows} rows of frames\n"
        f"  - Each cell is EXACTLY {fw}×{fh}px — no partial cells\n"
        f"  - Each cell has a solid MAGENTA (#FF00FF) background\n"
        f"  - NO content bleeds outside its cell boundary\n\n"
        f"Output specifications:\n"
        f"  - Total image: {total_w}×{total_h}px\n"
        f"  - {cols}×{rows} grid, each cell {fw}×{fh}px, MAGENTA background\n"
        f"  - No text, no labels, no borders between cells\n\n"
        f"Output the {total_w}×{total_h}px sprite sheet now."
    )


# ── Gemini 呼び出し ───────────────────────────────────────────────────────
def call_gemini(
    client, model: str,
    tmpl_bytes: bytes, char_bytes: bytes,
    prompt: str, retries: int = 5,
) -> bytes | None:
    from google.genai import types
    parts = [
        types.Part.from_bytes(data=tmpl_bytes, mime_type="image/png"),
        types.Part.from_bytes(data=char_bytes,  mime_type="image/png"),
        types.Part.from_text(text=prompt),
    ]
    for attempt in range(retries + 1):
        try:
            resp = client.models.generate_content(
                model=model,
                contents=parts,
                config=types.GenerateContentConfig(response_modalities=["IMAGE"]),
            )
            if not resp.candidates:
                time.sleep(3)
                continue
            for p in resp.candidates[0].content.parts:
                if hasattr(p, "inline_data") and p.inline_data:
                    return p.inline_data.data
            texts = [
                p.text for p in resp.candidates[0].content.parts
                if hasattr(p, "text") and p.text
            ]
            print(f"[text:{texts[0][:60]!r}]" if texts else f"[no-img #{attempt+1}]", end=" ")
            time.sleep(3)
        except Exception as e:
            msg = str(e)
            if "429" in msg or "RESOURCE_EXHAUSTED" in msg:
                w = 60 * (attempt + 1)
                print(f"[rate-limit {w}s]", end=" ", flush=True)
                time.sleep(w)
            else:
                print(f"[err:{msg[:60]}]", end=" ")
                if attempt == retries:
                    return None
                time.sleep(5)
    return None


# ── ユーティリティ ────────────────────────────────────────────────────────
def _magenta_key(img: "Image.Image") -> "Image.Image":
    """マゼンタ背景 (#FF00FF ±60) を透過に変換する。"""
    import numpy as np
    from PIL import Image
    a = np.array(img.convert("RGBA"))
    r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    mask = (r > 150) & (b > 150) & (g < 80)
    a[mask, 3] = 0
    return Image.fromarray(a)


def _pixelate_sprite(img: "Image.Image", dot_w: int, dot_h: int, scale: int) -> "Image.Image":
    """バウンディングボックス検出＋底辺アンカーでドット絵化する。"""
    import numpy as np
    from PIL import Image
    arr   = np.array(img)
    alpha = arr[:, :, 3]
    rows  = np.where((alpha > 30).any(axis=1))[0]
    cols  = np.where((alpha > 30).any(axis=0))[0]
    if len(rows) == 0 or len(cols) == 0:
        return Image.new("RGBA", (dot_w * scale, dot_h * scale), (0, 0, 0, 0))
    pad   = 2
    top   = max(0, int(rows[0])  - pad)
    bot   = min(img.height - 1,  int(rows[-1]) + pad)
    left  = max(0, int(cols[0])  - pad)
    right = min(img.width  - 1,  int(cols[-1]) + pad)
    content = img.crop((left, top, right + 1, bot + 1))
    cw, ch  = content.size
    sc      = min(dot_w / cw, dot_h / ch)
    new_w   = max(1, int(cw * sc))
    new_h   = max(1, int(ch * sc))
    content = content.resize((new_w, new_h), Image.LANCZOS)
    canvas  = Image.new("RGBA", (dot_w, dot_h), (0, 0, 0, 0))
    x_off   = (dot_w - new_w) // 2
    y_off   = dot_h - new_h        # 足元を下端に
    canvas.paste(content, (x_off, y_off))
    return canvas.resize((dot_w * scale, dot_h * scale), Image.NEAREST)


# ── スライス ──────────────────────────────────────────────────────────────
def slice_strip(
    strip_bytes: bytes, char: str, anim: str,
    frame_count: int, out_dir: Path, force: bool = False,
) -> list[str]:
    """
    生成されたストリップを frame_count 等分してフレームとして保存する。
    マゼンタキー＋底辺アンカーを適用。
    """
    import numpy as np
    from PIL import Image
    img = Image.open(io.BytesIO(strip_bytes)).convert("RGBA")
    sw, sh = img.size

    # ── フレーム境界の自動検出 ──────────────────────────────────────────────
    # マゼンタキー後の alpha を使って「全列がほぼ透明」な x 列を区切りと見なす
    keyed = _magenta_key(img)
    arr   = np.array(keyed)
    alpha = arr[:, :, 3]
    # 各列の不透明ピクセル数
    col_opaque = (alpha > 30).sum(axis=0)   # shape: (sw,)

    # 境界候補: 不透明ピクセルが 0 の列（マゼンタ縦ライン）
    is_bg_col = col_opaque == 0

    # 最小ギャップ幅 = GAP_PX の半分（キャラ内部の小さな透明部分を誤検出しないため）
    MIN_GAP_W = max(4, GAP_PX // 2)

    # 連続するゼロ範囲のうち MIN_GAP_W 以上のものだけをフレーム境界とする
    starts = []
    ends   = []
    in_sprite = False
    gap_start = None
    for x in range(sw):
        if not in_sprite:
            if not is_bg_col[x]:
                starts.append(x)
                in_sprite = True
                gap_start = None
        else:
            if is_bg_col[x]:
                if gap_start is None:
                    gap_start = x
            else:
                if gap_start is not None:
                    gap_w = x - gap_start
                    if gap_w >= MIN_GAP_W:
                        # 十分広いギャップ → フレーム境界
                        ends.append(gap_start - 1)
                        starts.append(x)
                    # 狭いギャップはキャラ内部の透明部分として無視
                    gap_start = None
    if in_sprite:
        ends.append(sw - 1)

    segs = list(zip(starts, ends))
    n    = len(segs)

    if n >= max(1, frame_count - 2):
        # 検出数が期待値に近い → バウンディングボックス境界をそのまま使用
        bounds = [(max(0, s - 4), min(sw, e + 5)) for s, e in segs]
        actual = len(bounds)
        label  = f"  → 自動検出 {actual}f" if actual == frame_count else f"  → 検出 {actual}f (要求 {frame_count}f)"
        print(label, end=" ")
    elif n > 0:
        # 検出数が少ない（キャラが接触してブロブ化）→ 検出数で等分割
        # 期待数ではなく実際の検出数で割る（期待数で割るとキャラの中を切断する）
        fw     = sw // n
        bounds = [(i * fw, min(sw, (i + 1) * fw)) for i in range(n)]
        print(f"  → 等分割 {n}f/{sw}px×{fw} (接触検出、要求 {frame_count}f)", end=" ")
    else:
        # 何も検出できなかった → 期待数で等分割（最終手段）
        fw     = sw // frame_count
        bounds = [(i * fw, (i + 1) * fw) for i in range(frame_count)]
        print(f"  → 等分割フォールバック {frame_count}f (検出0)", end=" ")

    # ── グリッド形式を自動検出（strip が 1行より背が高い場合） ──────────────
    # グリッドの場合: 等分割で cols × rows を決める
    cols, rows = _grid_dims(frame_count)
    fw_grid = sw // cols
    fh_grid = sh // rows if rows > 1 else sh

    if rows > 1 and abs(sh - fh_grid * rows) < 4:
        # グリッド形式が検出された
        bounds_grid = [
            (c * fw_grid, r * fh_grid, (c + 1) * fw_grid, (r + 1) * fh_grid)
            for r in range(rows) for c in range(cols)
        ]
        # 最後の不完全セル（frame_count が cols×rows に満たない）を除外
        bounds_grid = bounds_grid[:frame_count]
        print(f"  → グリッド {cols}×{rows} ({fw_grid}×{fh_grid}px/cell)", end=" ")
        out_dir.mkdir(parents=True, exist_ok=True)
        saved = []
        for fi, (x0, y0, x1, y1) in enumerate(bounds_grid):
            dst = out_dir / f"{anim}_f{fi}.png"
            if dst.exists() and not force:
                continue
            cell = img.crop((x0, y0, x1, y1)).convert("RGBA")
            cell = _magenta_key(cell)
            cell = _pixelate_sprite(cell, DOT_W, DOT_H, SCALE)
            cell.save(dst)
            saved.append(dst.name)
        return saved

    # ── 1行ストリップ ────────────────────────────────────────────────────────
    out_dir.mkdir(parents=True, exist_ok=True)
    saved = []
    for fi, (x0, x1) in enumerate(bounds):
        dst = out_dir / f"{anim}_f{fi}.png"
        if dst.exists() and not force:
            continue
        frame = img.crop((x0, 0, x1, sh)).convert("RGBA")
        frame = _magenta_key(frame)
        frame = _pixelate_sprite(frame, DOT_W, DOT_H, SCALE)
        frame.save(dst)
        saved.append(dst.name)

    return saved


# ── メイン ────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--char",       default="all",
                    help="キャラ名 (mil/yuzuki/muu/kiriko/doctor/nurse/all)")
    ap.add_argument("--anims",      nargs="+", default=list(ANIM_SHEET_MAP.keys()),
                    help=f"アニメ名 (default: {list(ANIM_SHEET_MAP.keys())})")
    ap.add_argument("--force",      action="store_true", help="既存ファイルを上書き")
    ap.add_argument("--model",      default=MODEL)
    ap.add_argument("--slice-only", default=None, metavar="PATH",
                    help="既存ストリップ画像をスライスするだけ（Gemini 不要）")
    ap.add_argument("--anim",       default="idle",
                    help="--slice-only 時のアニメ名")
    args = ap.parse_args()

    # ── スライスのみモード ──
    if args.slice_only:
        char = args.char if args.char != "all" else "mil"
        anim = args.anim
        if anim not in ANIM_SHEET_MAP:
            sys.exit(f"ERROR: unknown anim '{anim}'")
        _, frame_count = ANIM_SHEET_MAP[anim]
        out_dir = OUT_BASE / char
        strip_bytes = Path(args.slice_only).read_bytes()
        print(f"スライス: {args.slice_only} ({frame_count}f) → {out_dir}/")
        saved = slice_strip(strip_bytes, char, anim, frame_count, out_dir, force=True)
        print(f"保存: {len(saved)} フレーム")
        return

    # ── 通常モード ──
    chars = list(CHARS.keys()) if args.char == "all" else [args.char]
    if args.char != "all" and args.char not in CHARS:
        sys.exit(f"ERROR: unknown char '{args.char}'")

    api_key = load_api_key()
    from google import genai
    client = genai.Client(api_key=api_key)

    RAW_DIR.mkdir(parents=True, exist_ok=True)

    print(f"モデル  : {args.model}")
    print(f"キャラ  : {chars}")
    print(f"アニメ  : {args.anims}")
    print(f"出力    : {DOT_W}×{DOT_H} → {DOT_W*SCALE}×{DOT_H*SCALE}px (×{SCALE})")
    print()

    for char in chars:
        char_img = CHARS[char]
        if not char_img.exists():
            print(f"[{char}] ⚠ キャラ画像なし: {char_img}\n")
            continue
        char_bytes = char_img.read_bytes()
        out_dir    = OUT_BASE / char
        out_dir.mkdir(parents=True, exist_ok=True)
        print(f"── {char}  ({char_img.name}) ──")

        for anim in args.anims:
            if anim not in ANIM_SHEET_MAP:
                print(f"  [{anim}] テンプレートなし — スキップ")
                continue
            sheet_name, frame_count = ANIM_SHEET_MAP[anim]
            sheet_path = TEMPLATE_DIR / sheet_name
            if not sheet_path.exists():
                print(f"  [{anim}] テンプレートシートなし: {sheet_name} — スキップ")
                continue

            raw_path = RAW_DIR / f"{char}_{anim}_strip.png"

            if raw_path.exists() and not args.force:
                print(f"  [{anim}] キャッシュ使用 → スライスのみ")
                strip_bytes = raw_path.read_bytes()
            else:
                fw      = TMPL_W * TMPL_UPSCALE
                fh      = TMPL_H * TMPL_UPSCALE
                print(f"  [{anim}] 生成中 ({frame_count}f × {fw}×{fh}px)...", end=" ", flush=True)
                tmpl_bytes  = extract_row0(sheet_path, frame_count)
                prompt      = build_prompt(anim, frame_count, CHAR_DESC[char])
                strip_bytes = call_gemini(client, args.model, tmpl_bytes, char_bytes, prompt)
                if strip_bytes is None:
                    print("FAILED")
                    continue
                raw_path.write_bytes(strip_bytes)
                print(f"→ {raw_path.name}")

            saved = slice_strip(strip_bytes, char, anim, frame_count, out_dir, args.force)
            print(f"  [{anim}] {len(saved)} フレーム保存")

        print()

    print("完了。Godot で再インポートしてください:")
    print("  /Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .")


if __name__ == "__main__":
    main()
