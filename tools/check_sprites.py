#!/usr/bin/env python3
"""
check_sprites.py — 生成スプライトの機械検査。

生成AIが吐いたコマには、静止画1枚では気づけない破綻が混ざる。実際に混入していたもの：

  * 複数ポーズの横ストリップを1コマとして保存（再生時にキャラが2〜5体に分身する）
  * 中身が空のコマ（再生時にキャラが消える）
  * 画角の中で極端に小さく描かれたコマ（そのコマだけ縮む）
  * クロマキーの地が抜かれていないコマ（キャラの後ろに色板が出る）

いずれも連番で再生して初めて見える。人間の目視レビューは通ってしまうので、
機械で落とすのが唯一の防波堤。CI とテストから呼ぶ前提。

使い方:
    python3 tools/check_sprites.py            # 全キャラを検査。破綻があれば exit 1
    python3 tools/check_sprites.py --json     # 機械可読出力
"""

import argparse
import glob
import json
import os
import sys
from collections import deque

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPRITE_DIR = os.path.join(ROOT, "assets/generated/sprites")

# 検査の敷居。実測に基づく値で、絵の作り直しでここを緩めないこと。
ALPHA = 40           # 不透明とみなす alpha
MIN_FILL = 0.02      # 画面占有率がこれ未満＝空コマ
BLOB_MIN = 0.02      # 連結成分をひとつの「体」とみなす最小面積
MIN_BBOX_H = 0.55    # 縦の占有率がこれ未満＝そのコマだけ縮んでいる
MATTE_MAX = 0.12     # bbox 四隅が同色で占める率がこれを超える＝地が残っている

# 意図的に複数コマを1枚へ並べたシート（モブは 256x96 の4コマ）。分身判定から除外する。
SHEET_FILES = ("walk_front.png", "walk_back.png")

# 縦の占有率で「縮み」を見るのは、直立しているはずのアニメだけ。
# die は倒れ、jump/wall_slide は屈み、attack は踏み込むので、短くて正しい。
UPRIGHT_ANIMS = ("idle", "walk", "run", "walk_front", "walk_back")

# 等身の許容帯。「頭幅 ÷ 全高」で測る（首の検出は髪に阻まれて安定しないが、
# 頭頂から30%帯の最大幅なら安定して取れる）。実測 0.266〜0.391 で 1.47倍ばらついており、
# ドクターだけ頭が他の 2/3。スケールでは直せない＝絵の作り直しでしか揃わない。
# 再生成したら必ずこの帯に入れること。
HEAD_RATIO_MIN = 0.33
HEAD_RATIO_MAX = 0.40


def _mask(im, step=4):
    w, h = im.size
    px = im.load()
    W, H = w // step, h // step
    return [[1 if px[x * step, y * step][3] > ALPHA else 0 for x in range(W)] for y in range(H)], W, H


def _blobs(grid, W, H):
    seen = [[0] * W for _ in range(H)]
    out = []
    for y in range(H):
        for x in range(W):
            if not grid[y][x] or seen[y][x]:
                continue
            q = deque([(x, y)])
            seen[y][x] = 1
            cells = []
            while q:
                cx, cy = q.popleft()
                cells.append((cx, cy))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < W and 0 <= ny < H and grid[ny][nx] and not seen[ny][nx]:
                        seen[ny][nx] = 1
                        q.append((nx, ny))
            a = len(cells) / (W * H)
            if a >= BLOB_MIN:
                xs = [c[0] for c in cells]
                ys = [c[1] for c in cells]
                out.append({"a": a, "x0": min(xs) / W, "x1": max(xs) / W,
                            "y0": min(ys) / H, "y1": max(ys) / H})
    return out


def check_frame(path):
    """1コマを検査して、見つかった問題のリストを返す（空なら健全）。"""
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    px = im.load()
    grid, W, H = _mask(im)
    fill = sum(sum(r) for r in grid) / (W * H)
    problems = []

    if fill < MIN_FILL:
        problems.append("空コマ（占有率 %.3f）" % fill)
        return problems   # 空なら他の判定は意味がない

    name = os.path.basename(path)
    anim = name.split("_f")[0] if "_f" in name else name[:-4]

    blobs = _blobs(grid, W, H)
    if len(blobs) >= 2 and name not in SHEET_FILES:
        blobs.sort(key=lambda b: -b["a"])
        a, b = blobs[0], blobs[1]
        # 横に離れた大きな塊が2つ＝別個体が1コマに焼き込まれている
        if b["a"] > BLOB_MIN and (b["x0"] > a["x1"] or a["x0"] > b["x1"]):
            problems.append("複数体が焼き込まれている（%d塊）" % len(blobs))

    ys = [y for y in range(H) for x in range(W) if grid[y][x]]
    if ys:
        bbox_h = (max(ys) - min(ys) + 1) / H
        if bbox_h < MIN_BBOX_H and anim in UPRIGHT_ANIMS:
            problems.append("縦に極端に小さい（占有率 %.2f）" % bbox_h)

    # クロマキーの地：bbox の四隅が同色で不透明なら、地が抜かれていない
    xs = [x for y in range(H) for x in range(W) if grid[y][x]]
    if xs and ys:
        x0, x1 = min(xs) * 4, min(max(xs) * 4, w - 1)
        y0, y1 = min(ys) * 4, min(max(ys) * 4, h - 1)
        corners = [px[x0, y0], px[x1, y0], px[x0, y1], px[x1, y1]]
        opaque = [c for c in corners if c[3] > 200]
        if len(opaque) >= 3:
            base = opaque[0]
            if all(sum(abs(p - q) for p, q in zip(c[:3], base[:3])) < 40 for c in opaque):
                n = sum(1 for y in range(0, h, 4) for x in range(0, w, 4)
                        if px[x, y][3] > 200
                        and sum(abs(p - q) for p, q in zip(px[x, y][:3], base[:3])) < 40)
                r = n / ((h // 4) * (w // 4))
                if r > MATTE_MAX:
                    problems.append("地が抜かれていない（%s が %.0f%%）" % (base[:3], r * 100))
    return problems


def head_ratio(path):
    """頭幅 ÷ 全高。等身の代理指標。頭頂から30%帯の最大幅を頭幅とみなす。"""
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    px = im.load()
    rows = [[x for x in range(w) if px[x, y][3] > ALPHA] for y in range(h)]
    ys = [y for y, r in enumerate(rows) if r]
    if not ys:
        return None
    top, bot = min(ys), max(ys)
    height = bot - top + 1
    band = rows[top:top + max(int(height * 0.30), 4)]
    hw = max((len(r) for r in band), default=0)
    return hw / height if height else None


def report_proportions():
    """キャラごとの等身を測って表示する。帯から外れていれば指摘する（失敗にはしない）。"""
    import statistics
    out = []
    for d in sorted(glob.glob(os.path.join(SPRITE_DIR, "*"))):
        cid = os.path.basename(d)
        fs = sorted(glob.glob(os.path.join(d, "idle_f*.png")))[:8]
        vals = [r for r in (head_ratio(f) for f in fs) if r]
        if not vals:
            continue
        m = statistics.median(vals)
        ok = HEAD_RATIO_MIN <= m <= HEAD_RATIO_MAX
        out.append((cid, m, ok))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--proportions", action="store_true", help="等身の実測を表示する")
    args = ap.parse_args()

    if args.proportions:
        print("キャラ    頭幅/全高  判定（許容 %.2f〜%.2f）" % (HEAD_RATIO_MIN, HEAD_RATIO_MAX))
        for cid, m, ok in report_proportions():
            print("  %-10s %.3f    %s" % (cid, m, "OK" if ok else "帯の外"))
        return 0

    found = {}
    for f in sorted(glob.glob(os.path.join(SPRITE_DIR, "*/*.png"))):
        probs = check_frame(f)
        if probs:
            found[os.path.relpath(f, ROOT)] = probs

    if args.json:
        print(json.dumps(found, ensure_ascii=False, indent=2))
    else:
        if not found:
            print("スプライト検査: 破綻なし")
        else:
            print("スプライト検査: %d コマに問題" % len(found))
            for f, probs in found.items():
                print("  %s" % f)
                for p in probs:
                    print("     - %s" % p)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
