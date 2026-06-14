#!/usr/bin/env python3
"""提供キャラGIF（アニメ別）を Godot 用の横スプライトシートPNGに変換する。

GIFはGodotがそのままアニメ化できないため、各アニメGIFを
「全フレーム＝同一フレーム寸法で横並び」のPNGシートに変換する。
キャラ単位で全アニメ・全フレームの union bbox に切り詰める（足元/位置がブレない）。

    pip install Pillow
    python3 tools/gen_sprites.py <char_id> <anim1.gif> <anim2.gif> ...
        例: python3 tools/gen_sprites.py reika jump.gif attack.gif walk_front.gif walk_back.gif

出力:
    assets/generated/sprites/<char_id>/<anim>.png   … 横並びシート（frame_w*N × frame_h）
    assets/generated/sprites/<char_id>/meta.json     … frame_w/frame_h/各アニメのコマ数
アニメ名は GIF ファイル名から先頭の "ハッシュ-" を除いた stem。
"""
import os
import sys
import json
import re
from PIL import Image, ImageSequence

ROOT = os.path.join(os.path.dirname(__file__), "..", "assets", "generated", "sprites")
PAD = 2  # 切り詰め後に少し余白


def _frames(path):
    im = Image.open(path)
    out = []
    for fr in ImageSequence.Iterator(im):
        out.append(fr.convert("RGBA"))
    return out


def _anim_name(path):
    stem = os.path.splitext(os.path.basename(path))[0]
    return re.sub(r"^[0-9a-f]{6,}-", "", stem)  # 先頭のアップロードハッシュを除去


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: gen_sprites.py <char_id> <anim1.gif> [anim2.gif ...]")
    char = sys.argv[1]
    gifs = sys.argv[2:]
    out_dir = os.path.join(ROOT, char)
    os.makedirs(out_dir, exist_ok=True)

    # 1) 全アニメ・全フレームを読み、union bbox を求める
    loaded = {}
    union = None
    for g in gifs:
        frs = _frames(g)
        loaded[g] = frs
        for fr in frs:
            bb = fr.getbbox()
            if bb is None:
                continue
            union = bb if union is None else (
                min(union[0], bb[0]), min(union[1], bb[1]),
                max(union[2], bb[2]), max(union[3], bb[3]))
    if union is None:
        sys.exit("透明フレームしか無い")
    x0, y0, x1, y1 = union
    # 余白
    sample = next(iter(loaded.values()))[0]
    W, H = sample.size
    x0 = max(0, x0 - PAD); y0 = max(0, y0 - PAD)
    x1 = min(W, x1 + PAD); y1 = min(H, y1 + PAD)
    fw, fh = x1 - x0, y1 - y0

    meta = {"frame_w": fw, "frame_h": fh, "anims": {}}
    for g in gifs:
        frs = loaded[g]
        name = _anim_name(g)
        sheet = Image.new("RGBA", (fw * len(frs), fh), (0, 0, 0, 0))
        for i, fr in enumerate(frs):
            sheet.paste(fr.crop((x0, y0, x1, y1)), (i * fw, 0))
        sheet.save(os.path.join(out_dir, name + ".png"))
        meta["anims"][name] = len(frs)
        print("  %s/%s.png  %dx%d x%dコマ" % (char, name, fw, fh, len(frs)))
    json.dump(meta, open(os.path.join(out_dir, "meta.json"), "w"), ensure_ascii=False, indent=1)
    print("frame=%dx%d  → %s" % (fw, fh, out_dir))


if __name__ == "__main__":
    main()
