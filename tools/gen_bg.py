#!/usr/bin/env python3
"""電脳深層の視差背景（パララックス）を手続き生成。
遠景＝ネオンの摩天楼シルエット、中景＝近いビル群。横タイル可能。
DiveView がバイオーム色で modulate して使う前提なので青系のグレーで描く。
"""
from PIL import Image, ImageDraw
import os, random

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "generated", "bg")
os.makedirs(OUT, exist_ok=True)
W = 720


def building_layer(h, base, win_color, density, seed, win_chance):
    rng = random.Random(seed)
    img = Image.new("RGBA", (W, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    x = -10
    while x < W + 10:
        bw = rng.randint(34, 80)
        bh = rng.randint(int(h * 0.35), int(h * 0.92))
        top = h - bh
        col = tuple(int(c * rng.uniform(0.8, 1.15)) for c in base)
        d.rectangle([x, top, x + bw, h], fill=col + (255,))
        # アンテナ
        if rng.random() < 0.4:
            ax = x + rng.randint(6, bw - 6)
            d.line([ax, top, ax, top - rng.randint(6, 18)], fill=col + (255,))
            d.point((ax, top - rng.randint(6, 18)), fill=(255, 90, 90, 255))  # 赤灯
        # 窓（ネオン）
        for wy in range(top + 6, h - 4, 9):
            for wx in range(x + 5, x + bw - 4, 7):
                if rng.random() < win_chance:
                    c = win_color if rng.random() < 0.7 else (255, 170, 90)  # たまに暖色
                    a = rng.randint(120, 235)
                    d.rectangle([wx, wy, wx + 2, wy + 3], fill=c + (a,))
        x += bw + rng.randint(-6, 6)
    return img


def main():
    # 遠景（小さく密、薄い）
    far = building_layer(300, (28, 40, 66), (120, 200, 255), 0.6, 7, 0.30)
    far.putalpha(far.getchannel("A").point(lambda a: int(a * 0.85)))
    far.save(os.path.join(OUT, "city_far.png"))
    # 中景（大きく、濃い）
    mid = building_layer(260, (16, 24, 44), (140, 210, 255), 0.5, 42, 0.22)
    mid.save(os.path.join(OUT, "city_mid.png"))
    print("bg generated ->", OUT)


if __name__ == "__main__":
    main()
