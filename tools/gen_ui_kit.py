#!/usr/bin/env python3
"""依存ゼロ（Python 標準ライブラリのみ）で 9-patch UI キットを生成する。

この実行環境は egress 制限で Kenney/itch から UI 原本を DL できないため、暫定の
ナインスライス・テクスチャをここで合成する。後で Kenney「UI Pack: Sci-Fi / RPG
Expansion」(CC0) 等へ差し替え可能なように、同じスロット名・同じ余白で出力する。

    python3 tools/gen_ui_kit.py            # 全テクスチャ + プレビュー
    python3 tools/gen_ui_kit.py --preview  # プレビューだけ再生成

出力：
    assets/generated/ui/<name>.png         # 9-patch テクスチャ（StyleBoxTexture 用）
    assets/generated/ui/preview.png        # 組み上がりイメージ（実機の代わりに目視用）

ナインスライス余白（src/ui/ui_theme.gd と一致させること）：
    panel/button/bubble/row = 角丸 + 枠。texture_margin は MARGINS を参照。
"""
import os
import sys
import math
import zlib
import struct

ROOT = os.path.join(os.path.dirname(__file__), "..", "assets", "generated", "ui")

# 黒猫飯店パレット（指定値：深夜喫茶×オカルト×温かい居場所）。
# 3軸＝オレンジ(店)/ミント(ポモドーロ)/紫(キリコ・精神世界)。src/ui/ui_theme.gd と一致。
COL = {
    "bg":        (0x15, 0x15, 0x15),  # Background 深夜の黒
    "panel_top": (0x26, 0x26, 0x26),  # Panel 店内の影
    "panel_bot": (0x1d, 0x1d, 0x1d),
    "inset_top": (0x1a, 0x1a, 0x1a),
    "inset_bot": (0x12, 0x12, 0x12),
    "border":    (0x3a, 0x2a, 0x20),  # Border 木製家具
    "border_hi": (0x55, 0x3e, 0x2d),
    "amber":     (0xe6, 0xa1, 0x5a),  # Primary 暖炉オレンジ（店/選択中/焚き火）
    "amber_dk":  (0xc4, 0x84, 0x42),
    "mint":      (0x69, 0xd2, 0xb0),  # Secondary ミント（ポモドーロ/回復/成功）
    "mint_dk":   (0x46, 0x9d, 0x84),
    "purple":    (0x8e, 0x6b, 0xc7),  # Accent 紫（オカルト/精神世界/キリコ）
    "purple_dk": (0x5a, 0x18, 0x9a),
    "red":       (0xe0, 0x5a, 0x5a),  # Danger
    "red_dk":    (0xa8, 0x3c, 0x3c),
    "btn":       (0x2f, 0x2f, 0x2f),  # ボタン通常
    "btn_hi":    (0x3d, 0x3d, 0x3d),  # ホバー
    "ink":       (0xf5, 0xf3, 0xee),  # Text（真っ白を避ける）
    "ep":        (0x69, 0xd2, 0xb0),  # （ミント）
}

# StyleBoxTexture の texture_margin（px）。ui_theme.gd と必ず一致させる。
MARGINS = {
    "panel": 22, "panel_inset": 22, "row": 14,
    "button": 18, "button_hover": 18, "button_press": 18, "button_disabled": 18,
    "bubble": 20, "topbar": 20,
}


# ---- PNG 出力（RGBA8） ---------------------------------------------------

def save_png(path, w, h, buf):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)  # filter type 0
        raw += buf[y * stride:(y + 1) * stride]
    out = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
           + chunk(b"IEND", b""))
    open(path, "wb").write(out)


def new_buf(w, h):
    return bytearray(w * h * 4)


def blend(buf, w, x, y, r, g, b, a):
    """src-over 合成（a は 0..1）。"""
    if a <= 0:
        return
    i = (y * w + x) * 4
    da = buf[i + 3] / 255.0
    oa = a + da * (1 - a)
    if oa <= 0:
        return
    for k, sc in enumerate((r, g, b)):
        dc = buf[i + k]
        buf[i + k] = int((sc * a + dc * da * (1 - a)) / oa + 0.5)
    buf[i + 3] = int(oa * 255 + 0.5)


def lerp(a, b, t):
    return tuple(a[k] + (b[k] - a[k]) * t for k in range(3))


def _sdf_round_rect(px, py, cx, cy, hw, hh, r):
    qx = abs(px - cx) - (hw - r)
    qy = abs(py - cy) - (hh - r)
    ax, ay = max(qx, 0.0), max(qy, 0.0)
    return math.hypot(ax, ay) + min(max(qx, qy), 0.0) - r


def render_box(w, h, radius, border, top, bot, bcol, bhi=None, accent=False):
    """角丸パネル/ボタンを 1 枚合成して返す。"""
    buf = new_buf(w, h)
    cx, cy = w / 2.0, h / 2.0
    hw, hh = w / 2.0 - 0.5, h / 2.0 - 0.5
    for y in range(h):
        t = y / (h - 1) if h > 1 else 0.0
        fill = lerp(top, bot, t)
        for x in range(w):
            d = _sdf_round_rect(x + 0.5, y + 0.5, cx, cy, hw, hh, radius)
            interior = min(max(0.5 - d, 0.0), 1.0)
            if interior <= 0.0:
                continue
            inner = min(max(0.5 - (d + border), 0.0), 1.0)
            bcov = max(interior - inner, 0.0)
            # 枠は上側を border_hi、下側を border で陰影
            bc = bcol
            if bhi is not None:
                bc = lerp(bhi, bcol, min(1.0, t * 1.3))
            fr = (fill[0] * inner + bc[0] * bcov)
            fg = (fill[1] * inner + bc[1] * bcov)
            fb = (fill[2] * inner + bc[2] * bcov)
            denom = inner + bcov
            if denom > 0:
                fr, fg, fb = fr / denom, fg / denom, fb / denom
            # 上端内側のハイライト（艶）
            if inner > 0 and y < border + 3:
                hl = (1.0 - (y - border) / 3.0) if y >= border else 1.0
                hl = max(0.0, min(1.0, hl)) * 0.18
                fr = fr + (255 - fr) * hl
                fg = fg + (255 - fg) * hl
                fb = fb + (255 - fb) * hl
            blend(buf, w, x, y, int(fr), int(fg), int(fb), interior)
    return buf


def paste(dst, dw, src, sw, sh, ox, oy):
    for y in range(sh):
        for x in range(sw):
            i = (y * sw + x) * 4
            a = src[i + 3] / 255.0
            if a > 0:
                blend(dst, dw, ox + x, oy + y, src[i], src[i + 1], src[i + 2], a)


def stretch9(src, sw, sh, m, dw, dh):
    """9-patch を任意サイズに伸長（プレビュー用の簡易実装）。"""
    dst = new_buf(dw, dh)
    def smap(d, dlen, slen, m0, m1):
        if d < m0:
            return d
        if d >= dlen - m1:
            return slen - (dlen - d)
        # 中央：ソース中央 1px をストレッチ
        return m0 + ( (d - m0) / max(1, (dlen - m0 - m1)) ) * max(1, (slen - m0 - m1))
    for y in range(dh):
        sy = int(smap(y, dh, sh, m, m))
        sy = min(max(sy, 0), sh - 1)
        for x in range(dw):
            sx = int(smap(x, dw, sw, m, m))
            sx = min(max(sx, 0), sw - 1)
            i = (sy * sw + sx) * 4
            a = src[i + 3] / 255.0
            if a > 0:
                blend(dst, dw, x, y, src[i], src[i + 1], src[i + 2], a)
    return dst


# ---- テクスチャ定義 ------------------------------------------------------

def gen_textures():
    specs = {
        # name: (w,h,radius,border,top,bot,border,border_hi)
        "panel":           (64, 64, 18, 2, COL["panel_top"], COL["panel_bot"], COL["border"], COL["border_hi"]),
        "panel_inset":     (64, 64, 14, 2, COL["inset_top"], COL["inset_bot"], COL["border"], None),
        "row":             (44, 44, 10, 1, COL["panel_top"], COL["panel_bot"], COL["border"], None),
        "bubble":          (60, 60, 16, 2, (0x24, 0x22, 0x1e), (0x1a, 0x18, 0x15), COL["border_hi"], COL["border_hi"]),
        "topbar":          (60, 60, 4, 2, COL["panel_top"], COL["panel_bot"], COL["border"], COL["border_hi"]),
        # 既定ボタンはダークグレー（UIは控えめ＝額縁）。Primary だけ暖炉オレンジ。
        "button":          (56, 56, 14, 2, (0x37, 0x37, 0x37), COL["btn"], COL["border"], (0x4a, 0x4a, 0x4a)),
        "button_hover":    (56, 56, 14, 2, (0x47, 0x47, 0x47), COL["btn_hi"], COL["border"], (0x5a, 0x5a, 0x5a)),
        "button_press":    (56, 56, 14, 2, (0x24, 0x24, 0x24), (0x1d, 0x1d, 0x1d), COL["border"], None),
        "button_primary":  (56, 56, 14, 2, (0xee, 0xae, 0x6a), COL["amber"], (0x9a, 0x6a, 0x2e), (0xff, 0xcf, 0x8a)),
        "button_disabled": (56, 56, 14, 2, (0x26, 0x26, 0x26), (0x20, 0x20, 0x20), (0x33, 0x2a, 0x24), None),
    }
    for name, (w, h, r, bw, top, bot, bc, bhi) in specs.items():
        buf = render_box(w, h, r, bw, top, bot, bc, bhi)
        save_png(os.path.join(ROOT, name + ".png"), w, h, buf)
        print("  UI  %-16s %dx%d" % (name, w, h))
    # バー（横 9-patch）：bg ＋ オレンジ/ミント/紫/朱の fill
    for name, top, bot in (("bar_bg", COL["inset_top"], COL["inset_bot"]),
                           ("bar_danger", COL["red"], COL["red_dk"]),
                           ("bar_mint", COL["mint"], COL["mint_dk"]),
                           ("bar_primary", COL["amber"], COL["amber_dk"]),
                           ("bar_purple", COL["purple"], COL["purple_dk"])):
        buf = render_box(24, 16, 7, 1, top, bot, COL["border"], None)
        save_png(os.path.join(ROOT, name + ".png"), 24, 16, buf)
        print("  UI  %-16s %dx%d" % (name, 24, 16))


# ---- プレビュー（組み上がりイメージ） ------------------------------------

def _text_blocks(dst, dw, x, y, n, col, cell=4, gap=2):
    """簡易プレースホルダ文字（ドット帯）。実フォントは Godot 側。"""
    for k in range(n):
        for yy in range(cell):
            for xx in range(cell - 1):
                blend(dst, dw, x + k * (cell + gap) + xx, y + yy, col[0], col[1], col[2], 0.55)


def gen_preview():
    W, H = 380, 720
    bg = new_buf(W, H)
    # 背景グラデ
    for y in range(H):
        t = y / (H - 1)
        c = lerp((0x0d, 0x0b, 0x09), (0x05, 0x04, 0x03), t)
        for x in range(W):
            blend(bg, W, x, y, int(c[0]), int(c[1]), int(c[2]), 1.0)

    tex = {}
    def T(name):
        if name not in tex:
            p = os.path.join(ROOT, name + ".png")
            import_png(p, tex, name)
        return tex[name]

    def panel(name, x, y, w, h, m):
        s = T(name)
        d = stretch9(s["buf"], s["w"], s["h"], m, w, h)
        paste(bg, W, d, w, h, x, y)

    # トップバー
    panel("topbar", 10, 10, W - 20, 46, MARGINS["topbar"])
    _text_blocks(bg, W, 26, 30, 10, COL["ink"])      # 🌙 22:30 黒猫飯店・営業中
    _text_blocks(bg, W, W - 110, 30, 8, COL["amber"])  # ¥23,450
    # 大パネル（お店モード内観の枠）
    panel("panel", 10, 66, W - 20, 220, MARGINS["panel"])
    _text_blocks(bg, W, 26, 80, 6, COL["amber"])
    # HP(朱) / ポモドーロ(ミント) バー
    panel("bar_bg", 26, 110, 150, 14, 7); panel("bar_danger", 26, 110, 110, 14, 7)
    panel("bar_bg", 26, 130, 150, 14, 7); panel("bar_mint", 26, 130, 80, 14, 7)
    # 吹き出し（注文/会話）
    panel("bubble", 30, 170, 220, 70, MARGINS["bubble"])
    _text_blocks(bg, W, 44, 188, 9, COL["ink"])
    _text_blocks(bg, W, 44, 200, 7, COL["ink"])
    # 献立カード（row を 3 枚）
    for k in range(3):
        panel("row", 14 + k * 120, 300, 110, 96, MARGINS["row"])
        _text_blocks(bg, W, 24 + k * 120, 372, 5, COL["amber"])
    # リスト（アイテム/依頼）
    for k in range(3):
        panel("row", 10, 410 + k * 52, W - 20, 46, MARGINS["row"])
        _text_blocks(bg, W, 24, 426 + k * 52, 10, COL["ink"])
    # ボタン群（既定＝ダークグレー、無効）
    panel("button", 10, 580, (W - 30) // 2, 56, MARGINS["button"])
    _text_blocks(bg, W, 60, 602, 5, COL["ink"])
    panel("button_disabled", 20 + (W - 30) // 2, 580, (W - 30) // 2, 56, MARGINS["button"])
    # 大 CTA（暖簾を出す）＝Primary オレンジ
    panel("button_primary", 10, 648, W - 20, 56, MARGINS["button"])
    _text_blocks(bg, W, 150, 670, 6, (0x20, 0x16, 0x08))
    # モード3軸カラーの見本（オレンジ=店 / ミント=ポモドーロ / 紫=キリコ）
    for k, name in enumerate(("bar_primary", "bar_mint", "bar_purple")):
        panel(name, 14 + k * 118, 300 - 14, 100, 8, 7)

    save_png(os.path.join(ROOT, "preview.png"), W, H, bg)
    print("  preview.png %dx%d" % (W, H))


def import_png(path, store, name):
    """生成済み PNG を読み戻して 9-patch 伸長に使う（プレビュー用）。"""
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos = 8
    w = h = 0
    idat = bytearray()
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
        if tag == b"IHDR":
            w, h = struct.unpack(">II", body[:8])
        elif tag == b"IDAT":
            idat += body
        pos += 12 + ln
    raw = zlib.decompress(bytes(idat))
    buf = new_buf(w, h)
    stride = w * 4
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        ft = raw[p]; p += 1
        row = bytearray(raw[p:p + stride]); p += stride
        if ft == 1:
            for i in range(4, stride):
                row[i] = (row[i] + row[i - 4]) & 0xff
        elif ft == 2:
            for i in range(stride):
                row[i] = (row[i] + prev[i]) & 0xff
        elif ft == 3:
            for i in range(stride):
                a = row[i - 4] if i >= 4 else 0
                row[i] = (row[i] + ((a + prev[i]) >> 1)) & 0xff
        elif ft == 4:
            for i in range(stride):
                a = row[i - 4] if i >= 4 else 0
                b = prev[i]
                c = prev[i - 4] if i >= 4 else 0
                pp = a + b - c
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                row[i] = (row[i] + pr) & 0xff
        buf[y * stride:(y + 1) * stride] = row
        prev = row
    store[name] = {"w": w, "h": h, "buf": buf}


def main():
    if "--preview" in sys.argv:
        gen_preview()
    else:
        print("9-patch UI キット生成（依存ゼロ）")
        gen_textures()
        gen_preview()
    print("完了。ui_theme.gd で StyleBoxTexture 化 → godot --import で反映。")


if __name__ == "__main__":
    main()
