#!/usr/bin/env python3
"""単色背景の1枚絵を透過PNGに抜く（立ち絵→assets/portraits/<id>.png 用）。

縁からの塗りつぶしで背景だけを抜くので、服や髪に同色があっても内側は残る
（numpy+scipy があれば高品質。無ければ簡易の全画素しきい値）。

使い方:
    pip install Pillow              # 任意で numpy scipy
    # 例：白背景の立ち絵を keying して レイカ(id=kiriko) の立ち絵に
    python3 tools/key_bg.py in.png assets/portraits/kiriko.png --bg ffffff --tol 18
    # 既に透過PNGなら keying 不要（そのまま配置でOK）

立ち絵ID: mil / yuzuki / muu / kiriko(=レイカ) / kiriko_npc
"""
import sys
import argparse
from PIL import Image


def key_bg(im, hex_color, tol):
    r0 = int(hex_color[0:2], 16); g0 = int(hex_color[2:4], 16); b0 = int(hex_color[4:6], 16)
    try:
        import numpy as np
        from scipy import ndimage
        a = np.array(im.convert("RGBA"))
        rgb = a[:, :, :3].astype(int)
        near = (abs(rgb[:, :, 0] - r0) <= tol) & (abs(rgb[:, :, 1] - g0) <= tol) & (abs(rgb[:, :, 2] - b0) <= tol)
        lbl, _ = ndimage.label(near)
        border = set(lbl[0, :]) | set(lbl[-1, :]) | set(lbl[:, 0]) | set(lbl[:, -1])
        border.discard(0)
        a[np.isin(lbl, list(border)), 3] = 0
        return Image.fromarray(a, "RGBA")
    except Exception:
        im = im.convert("RGBA")
        px = im.load()
        w, h = im.size
        for y in range(h):
            for x in range(w):
                r, g, b, _a = px[x, y]
                if abs(r - r0) <= tol and abs(g - g0) <= tol and abs(b - b0) <= tol:
                    px[x, y] = (r, g, b, 0)
        return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--bg", default="ffffff")
    ap.add_argument("--tol", type=int, default=18)
    args = ap.parse_args()
    im = key_bg(Image.open(args.src), args.bg.lstrip("#"), args.tol)
    bb = im.getbbox()
    if bb:
        im = im.crop(bb)  # 余白トリム
    im.save(args.dst)
    print("keyed → %s  %dx%d" % (args.dst, im.size[0], im.size[1]))


if __name__ == "__main__":
    main()
