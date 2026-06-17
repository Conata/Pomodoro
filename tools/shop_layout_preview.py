#!/usr/bin/env python3
"""
tools/shop_layout_preview.py — お店経営画面レイアウトプレビュー生成

Usage:
  python3 tools/shop_layout_preview.py

出力: assets/generated/scene/shop_layout_preview.png
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).parent.parent

# ── 定数 ────────────────────────────────────────
SCREEN_W, SCREEN_H = 390, 844
BG_COLOR   = (18, 14, 28, 255)       # #120e1c 暗い紫
SURFACE    = (32, 26, 48, 255)
SURFACE2   = (46, 38, 66, 255)
ACCENT     = (142, 107, 199, 255)    # 紫
WARM       = (255, 190, 100, 255)    # 琥珀
TEXT       = (220, 210, 235, 255)
TEXT_MUTE  = (120, 110, 140, 255)
GREEN      = (100, 220, 160, 255)
MINT       = (72, 209, 190, 255)

# ── ヘルパー ────────────────────────────────────
def rect(draw, x, y, w, h, fill, radius=8):
    draw.rounded_rectangle([x, y, x+w, y+h], radius=radius, fill=fill)

def text_center(draw, txt, x, y, w, font, fill):
    bbox = draw.textbbox((0, 0), txt, font=font)
    tw = bbox[2] - bbox[0]
    draw.text((x + (w - tw) // 2, y), txt, fill=fill, font=font)

def get_font(size=14):
    for path in [
        "assets/fonts/DotGothic16-Regular.ttf",
        "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc",
        "/System/Library/Fonts/Hiragino Sans GB.ttc",
    ]:
        fp = REPO / path if not path.startswith("/") else Path(path)
        if fp.exists():
            return ImageFont.truetype(str(fp), size)
    return ImageFont.load_default()

def extract_frame(sprite_path: Path, frame_cols=4, frame_idx=0) -> Image.Image:
    """スプライトシートから1フレームを切り出す"""
    sheet = Image.open(sprite_path).convert("RGBA")
    fw = sheet.width // frame_cols
    fh = sheet.height
    frame = sheet.crop((fw * frame_idx, 0, fw * (frame_idx + 1), fh))
    return frame

def remove_bg(img: Image.Image, threshold=30) -> Image.Image:
    """
    四隅の平均色を背景色とみなしてアルファ抜き。
    """
    img = img.convert("RGBA")
    w, h = img.size
    corners = [img.getpixel((0,0)), img.getpixel((w-1,0)),
               img.getpixel((0,h-1)), img.getpixel((w-1,h-1))]
    br = sum(c[0] for c in corners) // 4
    bg = sum(c[1] for c in corners) // 4
    bb = sum(c[2] for c in corners) // 4

    pixels = img.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            dist = ((r-br)**2 + (g-bg)**2 + (b-bb)**2) ** 0.5
            if dist < threshold:
                pixels[x, y] = (r, g, b, 0)
    return img


# ── メイン ──────────────────────────────────────
def main():
    canvas = Image.new("RGBA", (SCREEN_W, SCREEN_H), BG_COLOR)
    draw = ImageDraw.Draw(canvas)
    font_sm = get_font(13)
    font_md = get_font(16)
    font_lg = get_font(20)

    y = 0

    # ── (1) TopBar ────────────────────────────── 0~56px
    BAR_H = 56
    rect(draw, 0, 0, SCREEN_W, BAR_H, SURFACE2, radius=0)
    draw.text((16, 18), "黒猫飯店", fill=WARM, font=font_md)
    draw.text((200, 12), "💰 1,240G", fill=WARM, font=font_sm)
    draw.text((200, 30), "👥 客 8/10", fill=TEXT, font=font_sm)
    draw.text((320, 18), "月曜", fill=MINT, font=font_md)
    y = BAR_H

    # ── (2) 内観 背景 ───────────────────────────── 56~316px
    INTERIOR_H = 260
    interior_path = REPO / "assets/generated/scene/shop_interior.png"
    if interior_path.exists():
        interior = Image.open(interior_path).convert("RGBA")
        interior = interior.resize((SCREEN_W, INTERIOR_H), Image.LANCZOS)
        canvas.paste(interior, (0, y))
    else:
        rect(draw, 0, y, SCREEN_W, INTERIOR_H, (30, 20, 45, 255), radius=0)
        draw.text((160, y + 120), "[内観なし]", fill=TEXT_MUTE, font=font_md)

    # ── キャラ配置（カウンター後ろ）─────────────
    CHARS = ["mil", "muu", "kiriko", "yuzuki"]
    # カウンタートップのY座標（内観画像の下から約30%）
    COUNTER_Y = y + INTERIOR_H - 55   # スプライトの足元をここに合わせる
    CHAR_SCALE = 2.8                  # 倍率
    CHAR_SPACING = SCREEN_W // len(CHARS)

    for i, cid in enumerate(CHARS):
        sp_path = REPO / f"assets/generated/sprites/{cid}/walk_front.png"
        if not sp_path.exists():
            continue
        frame = extract_frame(sp_path, frame_cols=4, frame_idx=0)
        frame = remove_bg(frame, threshold=60)
        fw, fh = frame.size
        nw = int(fw * CHAR_SCALE)
        nh = int(fh * CHAR_SCALE)
        frame = frame.resize((nw, nh), Image.NEAREST)
        # 足元をカウンタートップに揃える
        cx = CHAR_SPACING * i + (CHAR_SPACING - nw) // 2
        cy = COUNTER_Y - nh
        canvas.paste(frame, (cx, cy), frame)

    y += INTERIOR_H   # y = 316

    # ── (2.5) 客席ストリップ ──────────────────────── 316~364px
    # カウンター前・お客さんの頭だけ見える帯
    CUST_H = 48
    # カウンター天板（木材色）
    COUNTER_TOP_COLOR = (60, 40, 25, 255)
    COUNTER_EDGE_COLOR = (40, 28, 15, 255)
    rect(draw, 0, y, SCREEN_W, CUST_H, (22, 16, 32, 255), radius=0)
    # カウンター天板ライン（帯の上端）
    draw.rectangle([0, y, SCREEN_W, y + 12], fill=COUNTER_TOP_COLOR)
    draw.rectangle([0, y + 10, SCREEN_W, y + 13], fill=COUNTER_EDGE_COLOR)

    # お客さんシルエット（後ろ姿、頭+肩がカウンター越しに見える）
    CUSTOMERS = [
        (55,  20, 14, (38, 28, 55, 230)),   # x, head_top_offset, r, color
        (135, 16, 16, (30, 22, 48, 230)),
        (215, 22, 13, (42, 30, 58, 230)),
        (300, 18, 15, (34, 25, 52, 230)),
    ]
    for cx, head_top, r, color in CUSTOMERS:
        head_y = y + 13 + head_top        # カウンター天板の上に頭
        # 肩ライン（横長の楕円）
        draw.ellipse([cx - r*2, head_y + r*2 - 4,
                      cx + r*2, head_y + r*2 + 12], fill=color)
        # 頭（円）
        draw.ellipse([cx - r, head_y, cx + r, head_y + r*2], fill=color)
        # 髪のハイライト（薄い線）
        draw.arc([cx - r + 3, head_y + 2, cx + r - 3, head_y + r], 200, 340,
                 fill=(80, 60, 100, 160), width=2)

    y += CUST_H   # y = 364

    # ── (3) 店番選択 ────────────────────────────── 364~444px
    KEEPER_H = 80
    rect(draw, 0, y, SCREEN_W, KEEPER_H, SURFACE, radius=0)
    draw.text((16, y + 8), "店番", fill=TEXT_MUTE, font=font_sm)
    KEEPER_NAMES = [("ミル", MINT), ("ムュウ", (255,140,200,255)),
                    ("レイカ", ACCENT), ("ユズキ", WARM)]
    kw = SCREEN_W // 4
    for i, (name, color) in enumerate(KEEPER_NAMES):
        kx = kw * i + 8
        rect(draw, kx, y + 24, kw - 16, 46, SURFACE2, radius=8)
        # 枠（選択中は色付き）
        if i == 0:
            draw.rounded_rectangle([kx, y+24, kx+kw-16, y+70], radius=8,
                                   outline=color, width=2)
        text_center(draw, name, kx, y + 40, kw - 16, font_sm, color)
    y += KEEPER_H   # y = 396

    # ── (4) 今日の献立 ──────────────────────────── 396~556px
    MENU_H = 160
    rect(draw, 0, y, SCREEN_W, MENU_H, BG_COLOR, radius=0)
    draw.text((16, y + 10), "◆ 今日の献立", fill=ACCENT, font=font_md)

    DISHES = [
        ("担々麺", "辛", "dry+meat", "tantan"),
        ("炒飯", "旨", "meat+sea", "chahan"),
        ("雲呑湯", "淡", "sea+dry", "wantan"),
    ]
    CW = (SCREEN_W - 24) // 3
    for i, (name, taste, ing, icon_id) in enumerate(DISHES):
        cx = 8 + CW * i
        cy = y + 36
        rect(draw, cx, cy, CW - 8, 112, SURFACE2, radius=10)
        # 料理アイコン
        icon_path = REPO / f"assets/generated/food/{icon_id}.png"
        if icon_path.exists():
            icon = Image.open(icon_path).convert("RGBA").resize((60, 60), Image.LANCZOS)
            canvas.paste(icon, (cx + (CW - 8 - 60) // 2, cy + 6), icon)
        else:
            rect(draw, cx + 14, cy + 8, 60, 60, SURFACE, radius=6)
        draw.text((cx + 8, cy + 72), name, fill=TEXT, font=font_sm)
        taste_color = {"辛": (255,120,120,255), "旨": WARM, "淡": (160,220,255,255)}.get(taste, TEXT)
        draw.text((cx + 8, cy + 90), taste, fill=taste_color, font=font_sm)
        draw.text((cx + 8, cy + 94), ing, fill=TEXT_MUTE, font=ImageFont.load_default())
    y += MENU_H   # y = 556

    # ── (5) 食材在庫 ────────────────────────────── 556~632px
    STOCK_H = 76
    rect(draw, 0, y, SCREEN_W, STOCK_H, SURFACE, radius=0)
    draw.text((16, y + 8), "◆ 食材在庫", fill=ACCENT, font=font_sm)
    INGS = [("乾物", 3, 5, (200,180,140,255)),
            ("肉", 1, 5, (220,120,120,255)),
            ("海鮮", 4, 5, (120,180,255,255))]
    IW = SCREEN_W // 3
    for i, (label, cur, cap, color) in enumerate(INGS):
        ix = IW * i + 12
        iy = y + 30
        draw.text((ix, iy - 16), label, fill=TEXT, font=font_sm)
        # バーゲージ
        bw = IW - 24
        bh = 10
        rect(draw, ix, iy, bw, bh, SURFACE2, radius=5)
        filled = int(bw * cur / cap)
        if filled > 0:
            rect(draw, ix, iy, filled, bh, color, radius=5)
        draw.text((ix + bw + 4, iy - 2), f"{cur}/{cap}", fill=TEXT_MUTE, font=font_sm)
    y += STOCK_H   # y = 632

    # ── (6) 開店ボタン ──────────────────────────── 632~700px
    BTN_H = 68
    rect(draw, 0, y, SCREEN_W, BTN_H, BG_COLOR, radius=0)
    rect(draw, 24, y + 10, SCREEN_W - 48, 48, ACCENT, radius=12)
    text_center(draw, "開 店 す る", 24, y + 22, SCREEN_W - 48, font_lg, (255,255,255,255))
    y += BTN_H   # y = 700

    # ── 余白 ────────────────────────────────────── 700~844px
    rect(draw, 0, y, SCREEN_W, SCREEN_H - y, BG_COLOR, radius=0)

    # ── 保存 ────────────────────────────────────────────
    out = REPO / "assets/generated/scene/shop_layout_preview.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(str(out))
    print(f"✓ saved → {out.relative_to(REPO)}")


if __name__ == "__main__":
    main()
