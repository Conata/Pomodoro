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


STRIP_MAX_FRAMES = 12   # これ以下のフレーム数は1行ストリップ、超えるとグリッド


def build_prompt(anim: str, frame_count: int, char_desc: str) -> str:
    fw = TMPL_W * TMPL_UPSCALE   # 128
    fh = TMPL_H * TMPL_UPSCALE   # 256

    use_grid = frame_count > STRIP_MAX_FRAMES
    if use_grid:
        cols, rows = _grid_dims(frame_count)
        total_w    = cols * fw
        total_h    = rows * fh
        layout_desc = (
            f"arranged as a {cols}-column × {rows}-row grid "
            f"(left-to-right, top-to-bottom), each cell {fw}×{fh}px"
        )
        output_spec = (
            f"  - Total image: {total_w}×{total_h}px\n"
            f"  - {cols}×{rows} grid, each cell {fw}×{fh}px, MAGENTA background\n"
        )
        size_line = f"{total_w}×{total_h}px"
    else:
        cols, rows = frame_count, 1
        total_w    = frame_count * fw
        total_h    = fh
        layout_desc = (
            f"laid out as a single horizontal row of {frame_count} frames, "
            f"each frame {fw}×{fh}px, left to right"
        )
        output_spec = (
            f"  - Total image: {total_w}×{total_h}px\n"
            f"  - Single row of {frame_count} frames, each {fw}×{fh}px, MAGENTA background\n"
        )
        size_line = f"{total_w}×{total_h}px"

    return (
        f"You are given TWO images:\n"
        f"  Image 1 = a pixel art sprite sheet with {frame_count} frames "
        f"of '{anim}' animation, {layout_desc}.\n"
        f"  Image 2 = a character design reference.\n\n"
        f"Your task: TRACE Image 1 exactly — repaint each sprite cell with the character "
        f"from Image 2, keeping every pose and silhouette IDENTICAL to Image 1.\n\n"
        f"Think of it as a PALETTE SWAP + outfit redraw:\n"
        f"  - Keep every pixel POSITION identical to Image 1\n"
        f"  - Change ONLY: skin tone, hair, eye color, outfit colors → {char_desc}\n"
        f"  - Do NOT move any body part, change any pose, or alter expressions\n"
        f"  - Do NOT add or remove limbs, accessories, or effects\n"
        f"  - Preserve the EXACT pixel art style: same outline thickness, same color count\n\n"
        f"Layout (must match Image 1 exactly):\n"
        f"{output_spec}"
        f"  - MAGENTA (#FF00FF) background everywhere\n"
        f"  - No text, no labels, no borders\n\n"
        f"Output the {size_line} traced sprite sheet now."
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
def _find_col_boundaries(
    img_arr: "np.ndarray",
    sw: int,
    frame_count: int,
    min_gap_ratio: float = 0.5,
    min_gap_w: int = 3,
    merge_dist: int = 10,
) -> list[tuple[int, int]]:
    """
    マゼンタ背景の画像からフレーム列境界を検出する。
    1. マゼンタ率が高い列をセパレータとして検出
    2. 近接セパレータをマージ
    3. コンテンツブロブを取得
    4. ブロブを width 比でフレームに分割
    Returns: [(x0, x1), ...] の長さ frame_count のリスト
    """
    import numpy as np

    r = img_arr[..., 0].astype(int)
    g = img_arr[..., 1].astype(int)
    b = img_arr[..., 2].astype(int)
    is_mg   = (r > 150) & (b > 150) & (g < 80)
    col_mg  = is_mg.mean(axis=0)  # マゼンタ率 per column

    is_sep = col_mg >= min_gap_ratio

    # セパレータ区間の収集
    sep_ranges: list[tuple[int, int]] = []
    in_sep = False
    ss = 0
    for x in range(sw):
        if is_sep[x]:
            if not in_sep:
                ss = x
                in_sep = True
        else:
            if in_sep:
                if x - ss >= min_gap_w:
                    sep_ranges.append((ss, x - 1))
                in_sep = False
    if in_sep and sw - ss >= min_gap_w:
        sep_ranges.append((ss, sw - 1))

    # 近接セパレータをマージ
    if sep_ranges:
        merged: list[tuple[int, int]] = [sep_ranges[0]]
        for s, e in sep_ranges[1:]:
            if s - merged[-1][1] <= merge_dist:
                merged[-1] = (merged[-1][0], e)
            else:
                merged.append((s, e))
    else:
        merged = []

    # コンテンツ領域の抽出（10px 未満は除外）
    content_regions: list[tuple[int, int]] = []
    prev_end = 0
    for ss, se in merged:
        if ss - prev_end >= 10:
            content_regions.append((prev_end, ss - 1))
        prev_end = se + 1
    if sw - prev_end >= 10:
        content_regions.append((prev_end, sw - 1))

    n_blobs = len(content_regions)

    if n_blobs == 0:
        # セパレータなし → 等分割
        fw = sw // frame_count
        return [(i * fw, min(sw - 1, (i + 1) * fw - 1)) for i in range(frame_count)]

    # ブロブ数 > frame_count → 最小ギャップで隣接ブロブをマージ
    while len(content_regions) > frame_count:
        min_gap = float("inf")
        min_i   = 0
        for i in range(len(content_regions) - 1):
            gap = content_regions[i + 1][0] - content_regions[i][1] - 1
            if gap < min_gap:
                min_gap = gap
                min_i   = i
        content_regions[min_i] = (content_regions[min_i][0], content_regions[min_i + 1][1])
        content_regions.pop(min_i + 1)
    n_blobs = len(content_regions)

    # ブロブごとの期待フレーム数を幅比で計算
    total_content = sum(e - s + 1 for s, e in content_regions)
    avg_fw = total_content / frame_count

    frames_per_blob = [max(1, round((e - s + 1) / avg_fw)) for s, e in content_regions]

    # 合計が frame_count になるよう補正
    diff = sum(frames_per_blob) - frame_count
    while diff > 0:
        # 割り当て過剰なブロブから削る（正規化残差が最大のもの）
        candidates = [
            ((frames_per_blob[i] - (content_regions[i][1] - content_regions[i][0] + 1) / avg_fw), i)
            for i in range(n_blobs)
            if frames_per_blob[i] > 1
        ]
        if not candidates:
            break
        _, idx = max(candidates)
        frames_per_blob[idx] -= 1
        diff -= 1
    while diff < 0:
        # 割り当て不足なブロブに追加（正規化不足が最大のもの）
        candidates = [
            ((content_regions[i][1] - content_regions[i][0] + 1) / avg_fw - frames_per_blob[i], i)
            for i in range(n_blobs)
        ]
        _, idx = max(candidates)
        frames_per_blob[idx] += 1
        diff += 1

    # 各ブロブを frames_per_blob[i] 等分
    boundaries: list[tuple[int, int]] = []
    for blob_idx, (bs, be) in enumerate(content_regions):
        n  = frames_per_blob[blob_idx]
        bw = be - bs + 1
        for i in range(n):
            x0 = bs + int(i * bw / n)
            x1 = bs + int((i + 1) * bw / n) - 1 if i < n - 1 else be
            boundaries.append((x0, x1))

    return boundaries


def slice_strip(
    strip_bytes: bytes, char: str, anim: str,
    frame_count: int, out_dir: Path, force: bool = False,
    use_grid: bool | None = None,   # None = 自動判定, True/False = 強制
) -> list[str]:
    """
    生成されたストリップを frame_count フレームに分割して保存する。
    マゼンタキー＋底辺アンカーを適用。
    ブロブ検出によりキャラが密着していても正確に分割する。
    """
    import numpy as np
    from PIL import Image
    img = Image.open(io.BytesIO(strip_bytes)).convert("RGBA")
    sw, sh = img.size

    # ── グリッド形式判定 ────────────────────────────────────────────────────
    cols, rows = _grid_dims(frame_count)
    fh_grid = sh // rows if rows > 1 else sh
    fw_grid = sw // cols

    if use_grid is None:
        use_grid = frame_count > STRIP_MAX_FRAMES

    portrait_cell = (fh_grid > fw_grid * 0.8)
    is_grid = use_grid and (rows > 1) and portrait_cell

    if is_grid:
        # グリッド: 行0のみで列境界を検出（全行合算だとmagneta率が下がり誤検出する）
        arr      = np.array(img)
        row0_arr = arr[:fh_grid, :, :]   # 行0のみ
        col_bounds = _find_col_boundaries(row0_arr, sw, cols)
        print(f"  → グリッド {cols}×{rows} blob検出(row0)", end=" ")

        out_dir.mkdir(parents=True, exist_ok=True)
        saved = []
        for r in range(rows):
            y0 = r * fh_grid
            y1 = (r + 1) * fh_grid if r < rows - 1 else sh
            for c, (x0, x1) in enumerate(col_bounds[:cols]):   # cols でキャップ
                fi = r * cols + c
                if fi >= frame_count:
                    break
                dst = out_dir / f"{anim}_f{fi}.png"
                if dst.exists() and not force:
                    continue
                cell = img.crop((x0, y0, x1 + 1, y1)).convert("RGBA")
                cell = _magenta_key(cell)
                cell = _pixelate_sprite(cell, DOT_W, DOT_H, SCALE)
                cell.save(dst)
                saved.append(dst.name)
        return saved

    # ── 1行ストリップ ────────────────────────────────────────────────────────
    arr    = np.array(img)
    bounds = _find_col_boundaries(arr, sw, frame_count)
    print(f"  → ストリップ{frame_count}f blob検出({len(bounds)})", end=" ")

    out_dir.mkdir(parents=True, exist_ok=True)
    saved = []
    for fi, (x0, x1) in enumerate(bounds[:frame_count]):
        dst = out_dir / f"{anim}_f{fi}.png"
        if dst.exists() and not force:
            continue
        frame = img.crop((x0, 0, x1 + 1, sh)).convert("RGBA")
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
        saved = slice_strip(strip_bytes, char, anim, frame_count, out_dir, force=True,
                            use_grid=(frame_count > STRIP_MAX_FRAMES))
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

            saved = slice_strip(strip_bytes, char, anim, frame_count, out_dir, args.force,
                                use_grid=(frame_count > STRIP_MAX_FRAMES))
            print(f"  [{anim}] {len(saved)} フレーム保存")

        print()

    print("完了。Godot で再インポートしてください:")
    print("  /Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .")


if __name__ == "__main__":
    main()
