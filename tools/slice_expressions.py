#!/usr/bin/env python3
"""表情シート（1枚のグリッド画像）を顔カメラ用の個別フレームPNGに切り出す。

PixAI / ComfyUI(Qwen) 等で「R行×C列の同一キャラ顔グリッド」を1枚生成し、
これで個別フレームに割る。リップシンク用に各セルの位置ズレを防ぐため、
全セル共通の union bbox で切り詰める（＝口/目だけ動いて頭は動かない）。

既定テンプレ（4行×4列＝16コマ）:
    行 = 表情: neutral / smile / surprise / calm
    列 = 口/目: closed / half / open / blink(目閉じ)
列 closed/half/open でリップシンク、blink でまばたき。

使い方:
    pip install Pillow            # 任意で numpy scipy（背景キーイング高品質化）
    python3 tools/slice_expressions.py <char_id> <sheet.png> \
        [--rows 4 --cols 4] \
        [--exprs neutral,smile,surprise,calm] \
        [--states closed,half,open,blink] \
        [--bg 1a1030]            # 透過でなく単色背景の時、その色を抜く(±tol)
        [--tol 36]

出力:
    assets/generated/face/<char_id>/<expr>_<state>.png  （透過PNG・全コマ同寸）
    assets/generated/face/<char_id>/meta.json

char_id は mil / yuzuki / muu / kiriko(=レイカ) / kiriko_npc。
"""
import os
import sys
import json
import argparse
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..", "assets", "generated", "face")


def _key_bg(im, hex_color, tol):
    """単色背景を縁からの塗りつぶしで透過化（内側の同色は残す）。numpy/scipy があれば高品質。"""
    r0 = int(hex_color[0:2], 16); g0 = int(hex_color[2:4], 16); b0 = int(hex_color[4:6], 16)
    try:
        import numpy as np
        from scipy import ndimage
        a = np.array(im.convert("RGBA"))
        rgb = a[:, :, :3].astype(int)
        near = (abs(rgb[:, :, 0] - r0) <= tol) & (abs(rgb[:, :, 1] - g0) <= tol) & (abs(rgb[:, :, 2] - b0) <= tol)
        lbl, n = ndimage.label(near)
        border = set(lbl[0, :]) | set(lbl[-1, :]) | set(lbl[:, 0]) | set(lbl[:, -1])
        border.discard(0)
        bg = np.isin(lbl, list(border))
        a[bg, 3] = 0
        return Image.fromarray(a, "RGBA")
    except Exception:
        # フォールバック：近い色を全部抜く（内側の同色も抜けてしまう簡易版）
        im = im.convert("RGBA")
        px = im.load()
        w, h = im.size
        for y in range(h):
            for x in range(w):
                r, g, b, a = px[x, y]
                if abs(r - r0) <= tol and abs(g - g0) <= tol and abs(b - b0) <= tol:
                    px[x, y] = (r, g, b, 0)
        return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("char_id")
    ap.add_argument("sheet")
    ap.add_argument("--rows", type=int, default=4)
    ap.add_argument("--cols", type=int, default=4)
    ap.add_argument("--exprs", default="neutral,smile,surprise,calm")
    ap.add_argument("--states", default="closed,half,open,blink")
    ap.add_argument("--bg", default="")
    ap.add_argument("--tol", type=int, default=36)
    args = ap.parse_args()

    exprs = [s for s in args.exprs.split(",") if s]
    states = [s for s in args.states.split(",") if s]
    if len(exprs) != args.rows or len(states) != args.cols:
        sys.exit("行/列の数と exprs/states の数が一致しません（rows=%d cols=%d）" % (args.rows, args.cols))

    im = Image.open(args.sheet).convert("RGBA")
    if args.bg:
        im = _key_bg(im, args.bg.lstrip("#"), args.tol)
    W, H = im.size
    cw, ch = W // args.cols, H // args.rows

    # 全セルを等分割で切り、共通 union bbox を求める（位置ズレ防止＝リップシンクの肝）
    cells = {}
    union = None
    for r, expr in enumerate(exprs):
        for c, st in enumerate(states):
            cell = im.crop((c * cw, r * ch, c * cw + cw, r * ch + ch))
            cells[(expr, st)] = cell
            bb = cell.getbbox()
            if bb is not None:
                union = bb if union is None else (
                    min(union[0], bb[0]), min(union[1], bb[1]),
                    max(union[2], bb[2]), max(union[3], bb[3]))
    if union is None:
        sys.exit("透明なセルしかありません（--bg を指定し忘れていませんか）")

    out_dir = os.path.join(ROOT, args.char_id)
    os.makedirs(out_dir, exist_ok=True)
    for (expr, st), cell in cells.items():
        cell.crop(union).save(os.path.join(out_dir, "%s_%s.png" % (expr, st)))
    fw, fh = union[2] - union[0], union[3] - union[1]
    json.dump({"rows": args.rows, "cols": args.cols, "exprs": exprs, "states": states,
               "frame_w": fw, "frame_h": fh},
              open(os.path.join(out_dir, "meta.json"), "w"), ensure_ascii=False, indent=1)
    print("%s: %d表情 × %d状態 = %dコマ  frame=%dx%d → %s" %
          (args.char_id, len(exprs), len(states), len(cells), fw, fh, out_dir))


if __name__ == "__main__":
    main()
