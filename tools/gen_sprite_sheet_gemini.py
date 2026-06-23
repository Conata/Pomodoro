#!/usr/bin/env python3
"""
Gemini API でキャラクターのアニメーションシートを一括生成し、
個別スプライトフレームに自動スライスする。

パイプライン:
  1. Gemini に「スタイル参照シート」＋「キャラデザイン画像」を2枚渡す
  2. 参照と同じ形式の Animation Content シートを生成（1キャラ = 1回の API 呼び出し）
  3. スプライト領域を自動検出（bounding-box 解析）してスライス
  4. 個別フレームを保存
     assets/generated/sprites/<char>/<anim>_f<n>.png

スタイル参照画像:
  docs/Refs/sprite_style_ref.png

アニメーション順（参照シートと同じ並び順）:
  Row1 basic : idle  run  jump  acquire  climb
  Row2 basic : attack  jump_attack  hurt  die  dash
  Row3 basic : wall_slide  double_jump
  Row4 special: skill1  skill2  skill3

使い方:
    python3 tools/gen_sprite_sheet_gemini.py --char mil
    python3 tools/gen_sprite_sheet_gemini.py --char mil --force
    python3 tools/gen_sprite_sheet_gemini.py --char all
    python3 tools/gen_sprite_sheet_gemini.py --slice-only docs/Refs/Chara/mil_sheet.png --char mil
"""

import argparse
import io
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

# ── 設定 ──────────────────────────────────────────────────────────────────
MODEL            = "gemini-3-pro-image-preview"
OUT_BASE         = Path(__file__).parent.parent / "assets/generated/sprites"
TMP_BASE         = Path(__file__).parent / "_out/sprite_sheet_raw"
STYLE_REF_DEFAULT = Path(__file__).parent.parent / "docs/chara-template/Eris Esra's Character Template 4.1/16x32/16x32 All Animations-Sheet.png"
CHARA_REF        = Path(__file__).parent.parent / "docs/Refs/Chara"

# スプライト出力サイズ（ドット絵変換後）
DOT_W  = 48   # 1フレームの実ドット幅（スプライトはやや大きめ）
DOT_H  = 64   # 1フレームの実ドット高さ
SCALE  = 3    # nearest-neighbor 拡大倍率 → 144×192px

# 自動スライス: スプライトと判定する最小面積（px²）
MIN_SPRITE_AREA = 800

# ── アニメーション定義（参照シートの出現順 = スライス後の名前割り当て順）──
# 参照シートは 4 段構成:
#   basic move  : [idle, run, jump, acquire, climb]
#                 [attack, jump_attack, hurt, die, dash]
#                 [wall_slide, double_jump]
#   special move: [skill1, skill2, skill3]
ANIM_ORDER = [
    "idle", "run", "jump", "acquire", "climb",
    "attack", "jump_attack", "hurt", "die", "dash",
    "wall_slide", "double_jump",
    "skill1", "skill2", "skill3",
]

# 方向歩行シート用（walk_front / walk_back）
WALK_DIR_ANIM_ORDER = ["walk_front", "walk_back"]

# アニメごとのループ設定
ANIM_LOOP = {
    "idle":        True,
    "run":         True,
    "climb":       True,
    "wall_slide":  True,
    "walk_front":  True,
    "walk_back":   True,
    "jump":        False,
    "acquire":     False,
    "attack":      False,
    "jump_attack": False,
    "hurt":        False,
    "die":         False,
    "dash":        False,
    "double_jump": False,
    "skill1":      False,
    "skill2":      False,
    "skill3":      False,
}

DEFAULT_FPS = 12


# ── 共通ユーティリティ ────────────────────────────────────────────────────
def _magenta_key(img: "Image.Image") -> "Image.Image":
    """マゼンタ背景 (#FF00FF ±60) を透過に変換する（scipy 不要）。"""
    import numpy as np
    from PIL import Image
    a = np.array(img.convert("RGBA"))
    r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    mask = (r > 150) & (b > 150) & (g < 80)
    a[mask, 3] = 0
    return Image.fromarray(a)


def _pixelate_sprite(img: "Image.Image", dot_w: int, dot_h: int, scale: int) -> "Image.Image":
    """
    バウンディングボックス検出＋底辺アンカーでドット絵化する。
    - 不透明ピクセルの範囲を検出してクロップ（+2px パディング）
    - アスペクト比を保ちながら dot_w × dot_h に収まるようリサイズ
    - キャンバス下端に貼り付け（足元を揃える）
    - NEAREST で scale 倍に拡大
    """
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
    bot   = min(img.height - 1, int(rows[-1]) + pad)
    left  = max(0, int(cols[0])  - pad)
    right = min(img.width  - 1,  int(cols[-1]) + pad)
    content = img.crop((left, top, right + 1, bot + 1))
    cw, ch  = content.size

    sc    = min(dot_w / cw, dot_h / ch)
    new_w = max(1, int(cw * sc))
    new_h = max(1, int(ch * sc))
    content = content.resize((new_w, new_h), Image.LANCZOS)

    canvas = Image.new("RGBA", (dot_w, dot_h), (0, 0, 0, 0))
    x_off  = (dot_w - new_w) // 2
    y_off  = dot_h - new_h        # 足元を下端に
    canvas.paste(content, (x_off, y_off))

    return canvas.resize((dot_w * scale, dot_h * scale), Image.NEAREST)


# Godot 探索ビューで使う主要アニメーション（スライス後にフレーム数を確認）
GAME_ANIMS = {"idle", "run", "attack", "hurt", "die", "dash", "jump", "skill1"}


# ── キャラクター定義 ───────────────────────────────────────────────────────
CHARS = {
    "mil": {
        "appearance": (
            "chibi super deformed anime girl, 2 head tall, full body, "
            "short silver hair with pink inner, amber eyes, "
            "oversized black leather jacket, pink crop top, "
            "cyberpunk hacker style"
        ),
        "base": CHARA_REF / "Milu.png",
    },
    "yuzuki": {
        "appearance": (
            "chibi super deformed anime girl, 2 head tall, full body, "
            "orange twin tails, orange eyes, "
            "oversized black sweatshirt, urban street fashion"
        ),
        "base": CHARA_REF / "yuzuki.png",
    },
    "muu": {
        "appearance": (
            "chibi super deformed anime fox girl, 2 head tall, full body, "
            "long blonde hair, fox ears, blue eyes, "
            "white oversized jacket, idol streamer style"
        ),
        "base": CHARA_REF / "myu.png",
    },
    "kiriko": {
        "appearance": (
            "chibi super deformed anime girl, 2 head tall, full body, "
            "long blue hair, gold eyes, "
            "white ceremonial dress, cold elegant expression"
        ),
        "base": CHARA_REF / "reika.png",
    },
    "doctor": {
        "appearance": (
            "chibi super deformed anime woman, 2 head tall, full body, "
            "short dark hair, sharp intelligent eyes, "
            "white lab coat, teal scrubs underneath, "
            "doctor style, calm professional expression"
        ),
        "base": CHARA_REF / "doc.png",
    },
    "nurse": {
        "appearance": (
            "chibi super deformed anime woman, 2 head tall, full body, "
            "light hair, gentle kind eyes, "
            "white nurse uniform, nurse cap, "
            "caring healing expression"
        ),
        "base": CHARA_REF / "nurse.png",
    },
}


# ── プロンプト ────────────────────────────────────────────────────────────
def build_walk_dir_prompt() -> str:
    return (
        "You are given TWO reference images:\n"
        "  Image 1 = pixel art character sprite sheet (style and proportions to replicate)\n"
        "  Image 2 = the character design (hair color, eye color, outfit, accessories)\n\n"
        "Task: Create a TWO-ROW pixel art sprite sheet for directional walking:\n"
        "  Row 1 label 'walk_front': 4 frames — character walks TOWARD the viewer (front-facing walk cycle)\n"
        "  Row 2 label 'walk_back':  4 frames — character walks AWAY from the viewer (back-facing walk cycle)\n\n"
        "STRICT requirements:\n"
        "- Match Image 1's pixel art style: chunky pixels, thick black outlines, GBA/16-bit RPG proportions\n"
        "- Chibi super-deformed proportions: large head (~50% of body height), small body\n"
        "- Use the character's design from Image 2 for ALL sprites "
        "(same hair color, eye color, outfit, accessories)\n"
        "- Each sprite must show the FULL BODY from head to feet\n"
        "- walk_front (Row 1): character faces the viewer, legs/arms animate a walk cycle (4 frames)\n"
        "- walk_back (Row 2): character faces away, back of head/outfit visible, walk cycle (4 frames)\n"
        "- Arrange sprites as exactly 2 rows × 4 columns (8 sprites total)\n"
        "- Even spacing between sprites, each sprite in its own clear cell\n"
        "- BACKGROUND: solid bright MAGENTA (#FF00FF) everywhere\n"
        "- Add small white text labels 'walk_front' and 'walk_back' above each row\n\n"
        "Output the 2-row × 4-column directional walk sprite sheet with magenta background."
    )


def build_sheet_prompt() -> str:
    return (
        "You are given TWO reference images:\n"
        "  Image 1 = animation content sprite sheet (the EXACT layout, format, and pixel art style to replicate)\n"
        "  Image 2 = the character design to use (hair color, eye color, outfit, accessories)\n\n"
        "Task: Create a complete animation content sprite sheet for the character from Image 2,\n"
        "      following the EXACT same layout and format as Image 1.\n\n"
        "STRICT requirements:\n"
        "- Replicate Image 1's sheet layout EXACTLY: same section titles, same animation names, "
        "  same arrangement (basic move section + special move section)\n"
        "- Include ALL animations shown in Image 1: "
        "  idle, run, jump, acquire, climb, attack, jump attack, hurt, die, dash, "
        "  wall slide, double jump, skill1, skill2, skill3\n"
        "- Match Image 1's pixel art style EXACTLY: chunky pixels, thick black outlines, "
        "  limited flat color palette, GBA/16-bit RPG proportions\n"
        "- Use the character's design from Image 2 for ALL sprites "
        "  (keep exact hair color, eye color, and outfit)\n"
        "- Each sprite must show the FULL BODY from head to feet\n"
        "- BACKGROUND: solid bright MAGENTA (#FF00FF) — replace Image 1's beige/tan background with MAGENTA\n"
        "- Keep text labels in white or black (readable on magenta background)\n\n"
        "Output the complete animation content sprite sheet with magenta background."
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
        sys.exit("ERROR: GEMINI_API_KEY が見つかりません")
    return key


# ── Gemini 呼び出し ───────────────────────────────────────────────────────
def call_gemini(client, model: str, style_bytes: bytes,
                char_bytes: bytes, prompt: str, retries: int = 2) -> bytes | None:
    from google.genai import types
    parts = [
        types.Part.from_bytes(data=style_bytes, mime_type="image/png"),
        types.Part.from_bytes(data=char_bytes,  mime_type="image/png"),
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
            print(f"[text:{texts[0][:60]!r}]" if texts else f"[no-img #{attempt+1}]",
                  end=" ")
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


# ── スプライト自動スライス ─────────────────────────────────────────────────
def auto_slice(sheet_bytes: bytes, char: str, out_dir: Path,
               min_area: int = MIN_SPRITE_AREA,
               dot_w: int = DOT_W, dot_h: int = DOT_H, scale: int = SCALE,
               anim_order: list | None = None):
    """
    シート画像からスプライト領域を自動検出し、
    anim_order の順番で <anim>_f<n>.png として保存する。
    anim_order が None の場合はグローバルの ANIM_ORDER を使う。
    """
    if anim_order is None:
        anim_order = ANIM_ORDER
    from PIL import Image
    import numpy as np
    from scipy import ndimage

    img = Image.open(io.BytesIO(sheet_bytes)).convert("RGBA")
    a   = np.array(img)
    h, w = a.shape[:2]

    # ── 背景を検出（4 隅の色 → フラッドフィルで背景マスク）──
    bg_mask = np.zeros((h, w), dtype=bool)
    corners = [(0, 0), (0, w-1), (h-1, 0), (h-1, w-1)]
    for (r, c) in corners:
        r0, g0, b0 = int(a[r,c,0]), int(a[r,c,1]), int(a[r,c,2])
        rgb = a[:,:,:3].astype(int)
        tol = 50
        near = ((abs(rgb[:,:,0]-r0)<=tol) &
                (abs(rgb[:,:,1]-g0)<=tol) &
                (abs(rgb[:,:,2]-b0)<=tol))
        lbl, _ = ndimage.label(near)
        bids = (set(lbl[0,:]) | set(lbl[-1,:]) |
                set(lbl[:,0]) | set(lbl[:,-1])) - {0}
        bg_mask |= np.isin(lbl, list(bids))

    # ── 前景（非背景）のラベリング ──
    fg = ~bg_mask
    lbl, n_objects = ndimage.label(fg)
    print(f"  検出オブジェクト数: {n_objects}", end=" ")

    # ── バウンディングボックスを収集 ──
    boxes = []
    for obj_id in range(1, n_objects + 1):
        ys, xs = np.where(lbl == obj_id)
        area = len(ys)
        if area < min_area:
            continue  # テキストラベルや小さなノイズは除外
        y1, y2 = int(ys.min()), int(ys.max())
        x1, x2 = int(xs.min()), int(xs.max())
        cx = (x1 + x2) // 2
        cy = (y1 + y2) // 2
        boxes.append((cy, cx, y1, y2, x1, x2))

    # ── 小さすぎるもの（テキストラベル・エフェクト断片）を除外 ──
    MIN_HEIGHT = 60  # スプライトの最小高さ（ソース px）
    MIN_WIDTH  = 40
    boxes = [b for b in boxes if (b[3]-b[2]) >= MIN_HEIGHT and (b[5]-b[4]) >= MIN_WIDTH]

    # ── 位置で並び替え（上→下、左→右）──
    if not boxes:
        print("スプライトが検出できませんでした")
        return []

    boxes.sort(key=lambda b: (b[0], b[1]))

    # y 座標でクラスタ化して行を分ける
    rows = []
    cur_row = [boxes[0]]
    row_height_tol = (img.size[1] / 8)  # 縦の 1/8 を行の許容幅とする
    for box in boxes[1:]:
        if abs(box[0] - cur_row[0][0]) < row_height_tol:
            cur_row.append(box)
        else:
            rows.append(sorted(cur_row, key=lambda b: b[1]))  # 行内は x 順
            cur_row = [box]
    rows.append(sorted(cur_row, key=lambda b: b[1]))

    # ── 順番に anim_order を割り当て ──
    saved = []
    sprite_idx = 0
    anim_frame_count: dict[str, int] = {}

    out_dir.mkdir(parents=True, exist_ok=True)

    for row in rows:
        for (cy, cx, y1, y2, x1, x2) in row:
            if sprite_idx >= len(anim_order):
                break
            anim_name = anim_order[sprite_idx]
            fi = anim_frame_count.get(anim_name, 0)

            # クロップ
            crop = img.crop((x1, y1, x2+1, y2+1)).convert("RGBA")

            # マゼンタキー（背景透過）
            crop = _magenta_key(crop)

            # ドット絵変換（バウンディングボックス＋底辺アンカー）
            big = _pixelate_sprite(crop, dot_w, dot_h, scale)

            fname = f"{anim_name}_f{fi}.png"
            dst   = out_dir / fname
            big.save(dst)
            saved.append(fname)
            print(f"\n    [{sprite_idx:2d}] {anim_name}_f{fi} ({x2-x1}×{y2-y1}px) → {dst.name}",
                  end="")

            anim_frame_count[anim_name] = fi + 1
            sprite_idx += 1

    # ── manifest.json 書き出し（既存エントリとマージ）──
    manifest_path = out_dir / "manifest.json"
    existing_anims: dict = {}
    if manifest_path.exists():
        try:
            existing_anims = json.loads(manifest_path.read_text()).get("animations", {})
        except Exception:
            pass
    existing_anims.update({
        anim: {"frames": count, "loop": ANIM_LOOP.get(anim, False)}
        for anim, count in anim_frame_count.items()
    })
    # 全アニメをグローバル ANIM_ORDER + WALK_DIR_ANIM_ORDER の順で並べる
    all_order = ANIM_ORDER + [a for a in WALK_DIR_ANIM_ORDER if a not in ANIM_ORDER]
    manifest = {
        "char": char,
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "frame_size": [dot_w * scale, dot_h * scale],
        "fps": DEFAULT_FPS,
        "animations": {
            anim: existing_anims[anim]
            for anim in all_order if anim in existing_anims
        },
    }
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    print(f"  → manifest.json 書き出し ({len(existing_anims)} アニメ)")

    print()
    return saved


# ── スプライト品質チェック ─────────────────────────────────────────────────
def check_quality(char_list: list[str]) -> None:
    """
    生成済みスプライトの品質を簡易チェックし、崩れたものを報告する。
    問題: コンテンツ高さが小さい（等身が低い）・上に寄っている・ほぼ空透明
    """
    import numpy as np
    from PIL import Image

    CANVAS_H = DOT_H * SCALE  # 192
    MIN_CONTENT_H = int(CANVAS_H * 0.45)   # 86px 未満なら警告（全身の半分以下）
    MAX_CENTROID_Y = 0.80  # 重心が下 20% に偏っている → 足だけの可能性
    # 横向きポーズは高さが低くなるため除外
    SKIP_HEIGHT_CHECK = {"die", "wall_slide", "double_jump", "dash"}

    all_anims = ANIM_ORDER + WALK_DIR_ANIM_ORDER
    suspects: list[str] = []

    for char in char_list:
        for anim in all_anims:
            for fi in range(4):  # f0 だけチェック（f0 が無ければ終了）
                path = OUT_BASE / char / f"{anim}_f{fi}.png"
                if not path.exists():
                    break
                try:
                    img = Image.open(path).convert("RGBA")
                    arr = np.array(img)
                    alpha = arr[:, :, 3]
                    rows = np.where((alpha > 30).any(axis=1))[0]
                    cols = np.where((alpha > 30).any(axis=0))[0]
                    if len(rows) == 0:
                        suspects.append(f"  ⚠ {char}/{anim}_f{fi}: 空（透明ピクセルのみ）")
                        continue
                    h = int(rows[-1] - rows[0])
                    w = int(cols[-1] - cols[0])
                    cy = float((rows[0] + rows[-1])) / 2 / CANVAS_H
                    if h < MIN_CONTENT_H and anim not in SKIP_HEIGHT_CHECK:
                        suspects.append(
                            f"  ⚠ {char}/{anim}_f{fi}: 高さ{h}px（閾値{MIN_CONTENT_H}px）→ 等身低い可能性")
                    elif cy > MAX_CENTROID_Y:
                        suspects.append(
                            f"  ⚠ {char}/{anim}_f{fi}: 重心{cy:.2f}（{cy*CANVAS_H:.0f}/{CANVAS_H}px）→ 足だけ?")
                except Exception as e:
                    suspects.append(f"  ⚠ {char}/{anim}_f{fi}: 読み込みエラー {e}")

    if suspects:
        print(f"品質チェック: {len(suspects)} 件の要注意スプライト")
        for s in suspects:
            print(s)
        print()
        print("対処: python3 tools/gen_sprite_sheet_gemini.py --char <char> --force")
        print("      (walk_dir の場合は --walk-dir --force を追加)")
    else:
        print(f"品質チェック: 全スプライト OK ✓")


# ── ドット絵変換のみ ──────────────────────────────────────────────────────
def dotconv_file(src: Path, dst: Path, dot_w=DOT_W, dot_h=DOT_H, scale=SCALE):
    from PIL import Image
    img = Image.open(src).convert("RGBA")
    img = _magenta_key(img)
    big = _pixelate_sprite(img, dot_w, dot_h, scale)
    dst.parent.mkdir(parents=True, exist_ok=True)
    big.save(dst)
    print(f"{src.name} → {dst.name}")


# ── メイン ────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--char",       default="all",
                        help="キャラ名 (mil/yuzuki/muu/kiriko/all)")
    parser.add_argument("--force",      action="store_true", help="既存シートも上書き")
    parser.add_argument("--model",      default=MODEL)
    parser.add_argument("--style-ref",  default=None,
                        help=f"スタイル参照画像 (default: {STYLE_REF_DEFAULT})")
    parser.add_argument("--slice-only", default=None,
                        help="既存シート画像をスライスするだけ（パス指定）")
    parser.add_argument("--walk-dir",   action="store_true",
                        help="walk_front / walk_back の方向歩行スプライトを生成する")
    parser.add_argument("--check",      action="store_true",
                        help="スプライト品質チェック（崩れ・等身低いものを検出して表示）")
    parser.add_argument("--dot-w",  type=int, default=DOT_W)
    parser.add_argument("--dot-h",  type=int, default=DOT_H)
    parser.add_argument("--scale",  type=int, default=SCALE)
    parser.add_argument("--min-area", type=int, default=MIN_SPRITE_AREA,
                        help=f"スプライト最小面積px² (default: {MIN_SPRITE_AREA})")
    args = parser.parse_args()

    dw, dh, sc = args.dot_w, args.dot_h, args.scale

    # ── スライスのみ ──
    if args.slice_only:
        char = args.char if args.char != "all" else "mil"
        out_dir = OUT_BASE / char
        sheet_bytes = Path(args.slice_only).read_bytes()
        print(f"スライス: {args.slice_only} → {out_dir}/")
        saved = auto_slice(sheet_bytes, char, out_dir, args.min_area, dw, dh, sc)
        print(f"\n保存: {len(saved)} スプライト")
        return

    # 対象キャラ
    char_list = list(CHARS.keys()) if args.char == "all" else [args.char]
    if args.char != "all" and args.char not in CHARS:
        sys.exit(f"ERROR: unknown char '{args.char}'")

    # ── 品質チェックのみ ──
    if args.check:
        check_quality(char_list)
        return

    # スタイル参照画像
    style_path = Path(args.style_ref) if args.style_ref else STYLE_REF_DEFAULT
    if not style_path.exists():
        sys.exit(f"ERROR: スタイル参照画像が見つかりません: {style_path}")
    style_bytes = style_path.read_bytes()
    print(f"スタイル参照: {style_path.name} ✓")

    api_key = load_api_key()
    from google import genai
    client = genai.Client(api_key=api_key)

    print(f"モデル: {args.model}")
    print(f"キャラ: {char_list}")
    print(f"ドット: {dw}×{dh} → {dw*sc}×{dh*sc}px (×{sc})")
    print()

    if args.walk_dir:
        # ── 方向歩行スプライト生成（walk_front / walk_back）──
        walk_prompt = build_walk_dir_prompt()
        print("=== walk_front / walk_back 生成モード ===\n")
        for char in char_list:
            cfg     = CHARS[char]
            out_dir = OUT_BASE / char
            tmp_dir = TMP_BASE / char
            tmp_dir.mkdir(parents=True, exist_ok=True)

            if not cfg["base"].exists():
                print(f"[{char}] ⚠ キャラ画像が見つかりません: {cfg['base']}\n")
                continue

            char_bytes = cfg["base"].read_bytes()
            print(f"── {char}  (base: {cfg['base'].name}) ──")

            raw_path = tmp_dir / "walk_dir_raw.png"
            if raw_path.exists() and not args.force:
                print(f"  シート既存 → スライスのみ ({raw_path.name})")
                sheet_bytes = raw_path.read_bytes()
            else:
                print(f"  walk_dir シート生成中 ...", end=" ", flush=True)
                sheet_bytes = call_gemini(client, args.model, style_bytes, char_bytes, walk_prompt)
                if sheet_bytes is None:
                    print("FAILED")
                    continue
                raw_path.write_bytes(sheet_bytes)
                print(f"→ {raw_path.name}")

            print(f"  自動スライス ...", end=" ")
            saved = auto_slice(sheet_bytes, char, out_dir, args.min_area, dw, dh, sc,
                               anim_order=WALK_DIR_ANIM_ORDER)
            print(f"  合計 {len(saved)} スプライト保存")
            print()
    else:
        # ── 通常の全アニメシート生成 ──
        prompt = build_sheet_prompt()

        for char in char_list:
            cfg     = CHARS[char]
            out_dir = OUT_BASE / char
            tmp_dir = TMP_BASE / char
            tmp_dir.mkdir(parents=True, exist_ok=True)

            raw_path = tmp_dir / "sheet_raw.png"

            if not cfg["base"].exists():
                print(f"[{char}] ⚠ キャラ画像が見つかりません: {cfg['base']}\n")
                continue

            char_bytes = cfg["base"].read_bytes()
            print(f"── {char}  (base: {cfg['base'].name}) ──")

            # シート生成
            if raw_path.exists() and not args.force:
                print(f"  シート既存 → スライスのみ ({raw_path.name})")
                sheet_bytes = raw_path.read_bytes()
            else:
                print(f"  シート生成中 ...", end=" ", flush=True)
                sheet_bytes = call_gemini(client, args.model, style_bytes, char_bytes, prompt)
                if sheet_bytes is None:
                    print("FAILED")
                    continue
                raw_path.write_bytes(sheet_bytes)
                print(f"→ {raw_path.name}")

            # 自動スライス
            print(f"  自動スライス ...", end=" ")
            saved = auto_slice(sheet_bytes, char, out_dir, args.min_area, dw, dh, sc)
            print(f"  合計 {len(saved)} スプライト保存")
            print()

    print("完了。Godot で再インポートしてください:")
    print("  /Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .")


if __name__ == "__main__":
    main()
