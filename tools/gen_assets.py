#!/usr/bin/env python3
"""黒猫飯店 — 手続き生成のゲーム素材（ピクセルアート）。
立ち絵(フユキ等)は別途AI生成で assets/portraits/ へ。これは料理・箱・素材の
小アイコンを生成する。Godot の nearest 拡大でドット感を保つ前提で 32px native。
"""
from PIL import Image, ImageDraw
import os, math

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "generated")
S = 32  # native pixel canvas

# パレット
INK = (14, 18, 28, 255)        # 輪郭
BOWL = (38, 52, 74, 255)       # 碗（藍の陶器）
BOWL_HI = (70, 92, 120, 255)
RICE = (236, 222, 170, 255)
WHITE = (232, 240, 248, 255)
STEAM = (180, 210, 235, 130)
NOODLE = (240, 226, 150, 255)

TASTE = {
    "辛": (190, 60, 52, 255),
    "甘": (224, 150, 180, 255),
    "旨": (210, 150, 70, 255),
    "淡": (150, 195, 220, 255),
}


def new():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def px(d, x, y, c):
    if 0 <= x < S and 0 <= y < S:
        d.point((x, y), fill=c)


def fill_ellipse(d, x0, y0, x1, y1, c):
    d.ellipse([x0, y0, x1, y1], fill=c)


def outline_from_alpha(img):
    """不透明ピクセルの外周に1pxの暗い輪郭を足す（ドット絵らしさ）。"""
    px_in = img.load()
    out = img.copy()
    po = out.load()
    for y in range(S):
        for x in range(S):
            if px_in[x, y][3] == 0:
                near = False
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < S and 0 <= ny < S and px_in[nx, ny][3] > 80:
                        near = True
                        break
                if near:
                    po[x, y] = INK
    return out


def steam(d, cx, t=0):
    for i, x in enumerate((cx - 4, cx, cx + 4)):
        for k in range(3):
            yy = 3 + k * 2
            xx = x + (1 if (k + i) % 2 else -1)
            px(d, xx, yy, STEAM)


def bowl(d, broth):
    # 碗本体（下半分の楕円）＋ 中身
    fill_ellipse(d, 5, 13, 27, 29, BOWL)
    fill_ellipse(d, 6, 12, 26, 20, broth)       # スープ面
    d.line([6, 16, 26, 16], fill=BOWL_HI)         # 碗の縁ハイライト
    fill_ellipse(d, 9, 13, 23, 17, tuple(min(255, c + 22) for c in broth[:3]) + (255,))


def food_tantan():  # 担々麺 辛
    img = new(); d = ImageDraw.Draw(img)
    bowl(d, TASTE["辛"])
    for x in range(9, 24, 2):  # 麺
        px(d, x, 14, NOODLE); px(d, x + 1, 15, NOODLE)
    px(d, 12, 13, (90, 170, 90, 255)); px(d, 18, 14, (90, 170, 90, 255))  # ねぎ
    px(d, 15, 13, (220, 90, 70, 255))  # 辣油
    steam(d, 16)
    return img


def food_mabo():  # 麻婆豆腐 辛
    img = new(); d = ImageDraw.Draw(img)
    bowl(d, (170, 70, 50, 255))
    for (x, y) in ((11, 13), (15, 14), (19, 13), (13, 15), (17, 15)):  # 豆腐
        d.rectangle([x, y, x + 2, y + 2], fill=(238, 232, 210, 255))
    px(d, 12, 12, (90, 160, 80, 255)); px(d, 20, 13, (90, 160, 80, 255))
    steam(d, 16)
    return img


def food_suanla():  # 酸辣湯 辛/海
    img = new(); d = ImageDraw.Draw(img)
    bowl(d, (150, 84, 58, 255))
    for x in range(9, 24, 3):  # 卵リボン
        px(d, x, 14, (240, 220, 120, 255)); px(d, x + 1, 13, (240, 220, 120, 255))
    steam(d, 16)
    return img


def food_chashu():  # 叉焼麺 旨/肉
    img = new(); d = ImageDraw.Draw(img)
    bowl(d, TASTE["旨"])
    for x in range(9, 24, 2):
        px(d, x, 15, NOODLE)
    d.ellipse([11, 12, 16, 15], fill=(210, 150, 150, 255))  # 叉焼
    d.ellipse([12, 12, 15, 14], fill=(180, 110, 110, 255))
    px(d, 19, 13, (90, 160, 80, 255))
    steam(d, 16)
    return img


def food_chahan():  # 炒飯 旨/乾（皿に山盛り）
    img = new(); d = ImageDraw.Draw(img)
    d.ellipse([4, 20, 28, 27], fill=BOWL)  # 皿
    d.polygon([(8, 21), (16, 11), (24, 21)], fill=RICE)  # ご飯の山
    for (x, y) in ((12, 18), (16, 15), (19, 18), (14, 16)):
        px(d, x, y, (235, 180, 90, 255))
    px(d, 13, 17, (90, 170, 90, 255)); px(d, 18, 16, (200, 80, 70, 255))  # 具
    steam(d, 16)
    return img


def food_wantan():  # 雲呑湯 淡/海
    img = new(); d = ImageDraw.Draw(img)
    bowl(d, TASTE["淡"])
    for (x, y) in ((11, 13), (16, 14), (20, 13)):  # 雲呑
        d.polygon([(x, y + 2), (x + 2, y), (x + 4, y + 2), (x + 2, y + 3)], fill=WHITE)
    px(d, 14, 13, (90, 160, 80, 255))
    steam(d, 16)
    return img


def food_okayu():  # 翡翠粥 淡/乾
    img = new(); d = ImageDraw.Draw(img)
    bowl(d, (170, 200, 160, 255))
    for x in range(10, 23, 3):
        px(d, x, 14, (210, 230, 200, 255))
    px(d, 16, 13, (90, 160, 80, 255))
    steam(d, 16)
    return img


def food_annin():  # 杏仁豆腐 甘
    img = new(); d = ImageDraw.Draw(img)
    d.ellipse([5, 14, 27, 28], fill=BOWL)
    for (x, y) in ((11, 16), (16, 15), (20, 17), (14, 18)):  # 白い角切り
        d.rectangle([x, y, x + 3, y + 3], fill=WHITE)
    px(d, 18, 14, (210, 70, 70, 255))  # クコの実
    return img


def food_goma():  # 胡麻団子 甘
    img = new(); d = ImageDraw.Draw(img)
    d.ellipse([5, 16, 27, 28], fill=BOWL)
    for cx in (12, 18, 15):
        cy = 18 if cx != 15 else 15
        d.ellipse([cx - 3, cy - 3, cx + 3, cy + 3], fill=(150, 110, 70, 255))
        px(d, cx, cy, (60, 44, 30, 255)); px(d, cx - 1, cy + 1, (60, 44, 30, 255))
    return img


def food_yakuzen():  # タオ爺の薬膳火鍋 辛/肉 特注
    img = new(); d = ImageDraw.Draw(img)
    d.ellipse([3, 12, 29, 30], fill=(70, 50, 44, 255))  # 鍋
    fill_ellipse(d, 5, 12, 27, 19, (150, 50, 44, 255))
    for (x, y) in ((10, 13), (16, 14), (21, 13)):
        px(d, x, y, (210, 160, 70, 255)); px(d, x, y + 1, (120, 70, 40, 255))  # 薬膳
    px(d, 13, 13, (90, 150, 80, 255)); px(d, 19, 14, (90, 150, 80, 255))
    steam(d, 16)
    return img


def food_parfait():  # ノノの電脳パフェ 甘 特注
    img = new(); d = ImageDraw.Draw(img)
    d.polygon([(11, 28), (21, 28), (19, 16), (13, 16)], fill=(120, 150, 180, 120))  # グラス
    d.rectangle([13, 14, 19, 17], fill=(232, 180, 200, 255))  # クリーム
    d.rectangle([13, 11, 19, 14], fill=(180, 220, 230, 255))
    d.ellipse([14, 7, 18, 11], fill=(232, 120, 150, 255))   # トップ
    px(d, 16, 6, (120, 220, 160, 255))  # ミント
    return img


def food_wasure():  # 404さんの忘れ麺 淡/海 特注
    img = new(); d = ImageDraw.Draw(img)
    bowl(d, (150, 185, 205, 255))
    for x in range(9, 24, 2):
        px(d, x, 14, (220, 232, 240, 255))
    d.text((13, 11), "?", fill=(90, 200, 230, 255))  # 謎
    steam(d, 16)
    return img


FOODS = {
    "tantan": food_tantan, "mabo": food_mabo, "suanla": food_suanla,
    "chashu": food_chashu, "chahan": food_chahan, "wantan": food_wantan,
    "okayu": food_okayu, "annin": food_annin, "goma": food_goma,
    "yakuzen": food_yakuzen, "parfait": food_parfait, "wasure": food_wasure,
}

BOX_COLORS = [  # 木/鉄/銀/金
    ((120, 84, 50), (150, 110, 70)),
    ((110, 120, 130), (160, 172, 184)),
    ((180, 190, 205), (225, 232, 240)),
    ((210, 170, 70), (245, 215, 120)),
]


def box(grade):
    img = new(); d = ImageDraw.Draw(img)
    dark, lite = BOX_COLORS[grade]
    d.rectangle([7, 14, 25, 26], fill=dark + (255,))
    d.rectangle([7, 14, 25, 18], fill=lite + (255,))   # 蓋
    d.rectangle([7, 18, 25, 19], fill=(40, 30, 24, 255))
    d.rectangle([15, 19, 17, 24], fill=(230, 200, 90, 255))  # 留め金
    d.rectangle([15, 20, 17, 22], fill=(120, 90, 30, 255))
    return img


def ingredient(kind):
    img = new(); d = ImageDraw.Draw(img)
    if kind == "dry":   # 乾物（米俵）
        d.ellipse([8, 12, 24, 26], fill=(200, 180, 120, 255))
        for y in (15, 19, 23):
            d.line([9, y, 23, y], fill=(150, 130, 80, 255))
    elif kind == "meat":  # 肉
        d.ellipse([7, 13, 25, 26], fill=(190, 110, 110, 255))
        d.ellipse([10, 15, 22, 23], fill=(220, 160, 160, 255))
        d.rectangle([15, 11, 17, 15], fill=(230, 230, 220, 255))  # 骨
    else:  # sea 海鮮（魚）
        d.ellipse([6, 15, 22, 23], fill=(150, 190, 215, 255))
        d.polygon([(22, 19), (27, 15), (27, 23)], fill=(120, 170, 200, 255))  # 尾
        px(d, 10, 18, INK)  # 目
    return img


def save(img, sub, name):
    img = outline_from_alpha(img)
    folder = os.path.join(OUT, sub)
    os.makedirs(folder, exist_ok=True)
    img.save(os.path.join(folder, name + ".png"))


def main():
    for k, fn in FOODS.items():
        save(fn(), "food", k)
    for g in range(4):
        save(box(g), "box", str(g))
    for k in ("dry", "meat", "sea"):
        save(ingredient(k), "ing", k)
    print("generated %d food, 4 box, 3 ing -> %s" % (len(FOODS), OUT))


if __name__ == "__main__":
    main()
