#!/usr/bin/env python3
"""AI動画クリップ（Seedance2 等）→ ゲーム用のクリーンなスプライト/アニメ素材に変換する。

狙いは「できる限りクリーンな仕上がり」。AI動画は等速・縁ノイズ・コマ間ブレが乗るので、
ゲームに載せる前にこの工程で潰す：

    1. 取り込み : 動画(mp4/webm/mov) / GIF / フレーム画像フォルダ のどれからでも読む
    2. 間引き   : 等間隔で N コマに削る（ループ前提なら最後の重複コマは落とす）
    3. 背景抜き : 四隅から背景色を自動推定 → 縁からの連結成分だけ透過
                  （服や髪に同色があっても内側は残る。numpy/scipy で高品質）
    4. 仕上げ   : 小さなゴミ(孤立アルファ)除去 ＋ 縁を数px収縮してフリンジ除去
    5. パレット : 全コマ共通の K 色パレットに量子化（コマ間で色がブレない＝「ゲーム画面」化）
    6. 整列     : 全コマの union bbox で同寸クロップ（キャラがガタつかない）
                  ＋任意でニアレストネイバー縮小してドットに寄せる
    7. 出力     : 連番PNG ＋ 横1列の連結シート ＋ meta.json

依存:
    pip install Pillow            # 任意で numpy scipy（背景抜き・ゴミ取りが高品質に）
    # 動画入力には ffmpeg が要る。システムの ffmpeg があればそれを、無ければ
    # `pip install imageio-ffmpeg` の同梱バイナリを自動で使う。

使い方:
    # mp4 を 12コマの待機ループ素材に。主人公 id=reika 想定。
    python3 tools/sprite_from_video.py reika in/idle.mp4 --anim idle --frames 12 --fps 12

    # 背景色を明示（四隅推定が外れる時）＋ 32色パレット＋高さ96pxのドットに縮小
    python3 tools/sprite_from_video.py reika in/walk.gif --anim walk \
        --bg 1a1030 --colors 32 --height 96

    # 既に抜き出した連番PNGのフォルダから（ffmpeg不要）
    python3 tools/sprite_from_video.py reika frames_dir/ --anim cast --no-quantize

出力:
    assets/generated/sprites/<id>/<anim>/frame_000.png ...   （透過PNG・全コマ同寸）
    assets/generated/sprites/<id>/<anim>/<id>_<anim>_sheet.png（横1列の連結シート）
    assets/generated/sprites/<id>/<anim>/meta.json
    取り込んだ生フレームは tools/_out/<id>_<anim>/raw/ に置く（.gitignore 済み）。

キャラ id は mil / yuzuki / muu / kiriko(=レイカ) / reika など、プロジェクトの命名に合わせる。
"""
import os
import sys
import json
import glob
import shutil
import argparse
import subprocess
from datetime import datetime, timezone

from PIL import Image, ImageSequence

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT_RAW = os.path.join(ROOT, "tools", "_out")
SPRITES = os.path.join(ROOT, "assets", "generated", "sprites")

VIDEO_EXT = {".mp4", ".webm", ".mov", ".mkv", ".avi", ".m4v"}
SEQ_EXT = {".gif", ".webp", ".apng"}
IMG_EXT = {".png", ".jpg", ".jpeg", ".bmp"}


def _ffmpeg_bin():
    """システムの ffmpeg → 無ければ imageio-ffmpeg 同梱バイナリ。"""
    p = shutil.which("ffmpeg")
    if p:
        return p
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return None


def extract_frames(src, work_dir, fps):
    """入力（動画 / GIF等 / フォルダ）を RGBA フレームの list にして返す。"""
    ext = os.path.splitext(src)[1].lower()

    # フォルダ：連番画像をそのまま読む
    if os.path.isdir(src):
        files = sorted(
            f for f in glob.glob(os.path.join(src, "*"))
            if os.path.splitext(f)[1].lower() in IMG_EXT
        )
        if not files:
            sys.exit("画像が見つからない: %s" % src)
        return [Image.open(f).convert("RGBA") for f in files]

    # GIF / アニメWebP / APNG：PILで分解
    if ext in SEQ_EXT:
        im = Image.open(src)
        return [fr.convert("RGBA") for fr in ImageSequence.Iterator(im)]

    # 動画：ffmpeg で fps サンプリング → PNG
    if ext in VIDEO_EXT:
        ff = _ffmpeg_bin()
        if not ff:
            sys.exit("動画入力には ffmpeg が必要（pip install imageio-ffmpeg でも可）")
        raw = os.path.join(work_dir, "raw")
        if os.path.isdir(raw):
            shutil.rmtree(raw)
        os.makedirs(raw, exist_ok=True)
        cmd = [ff, "-y", "-i", src, "-vf", "fps=%g" % fps,
               os.path.join(raw, "f_%04d.png")]
        subprocess.run(cmd, check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        files = sorted(glob.glob(os.path.join(raw, "f_*.png")))
        if not files:
            sys.exit("ffmpeg がフレームを出せなかった: %s" % src)
        return [Image.open(f).convert("RGBA") for f in files]

    sys.exit("対応していない入力: %s" % src)


def thin(frames, n, drop_last_dupe):
    """等間隔で n コマに間引く。ループ素材なら末尾の重複コマを落とす。"""
    if drop_last_dupe and len(frames) > 2:
        frames = frames[:-1]
    if n <= 0 or n >= len(frames):
        return frames
    idx = [round(i * (len(frames) - 1) / (n - 1)) for i in range(n)] if n > 1 else [0]
    return [frames[i] for i in idx]


def _auto_bg(frames):
    """四隅の色の中央値から背景色 hex を推定。"""
    import numpy as np
    corners = []
    for im in frames:
        a = np.array(im.convert("RGB"))
        h, w = a.shape[:2]
        for y, x in ((0, 0), (0, w - 1), (h - 1, 0), (h - 1, w - 1)):
            corners.append(a[y, x])
    med = np.median(np.array(corners), axis=0).astype(int)
    return "%02x%02x%02x" % (med[0], med[1], med[2])


def key_bg(im, hex_color, tol, despeckle, shrink):
    """単色背景を縁からの連結成分で透過化。内側の同色は残す。

    numpy/scipy があれば：縁フラッドフィル＋小ゴミ除去＋アルファ収縮。
    無ければ：近い色を全部抜く簡易版（内側の同色も抜ける）。
    """
    r0 = int(hex_color[0:2], 16); g0 = int(hex_color[2:4], 16); b0 = int(hex_color[4:6], 16)
    try:
        import numpy as np
        from scipy import ndimage
        a = np.array(im.convert("RGBA"))
        rgb = a[:, :, :3].astype(int)
        near = ((abs(rgb[:, :, 0] - r0) <= tol)
                & (abs(rgb[:, :, 1] - g0) <= tol)
                & (abs(rgb[:, :, 2] - b0) <= tol))
        lbl, _ = ndimage.label(near)
        border = set(lbl[0, :]) | set(lbl[-1, :]) | set(lbl[:, 0]) | set(lbl[:, -1])
        border.discard(0)
        bg = np.isin(lbl, list(border))
        a[bg, 3] = 0

        fg = a[:, :, 3] > 0
        if despeckle > 0:
            flbl, fn = ndimage.label(fg)
            if fn > 0:
                sizes = ndimage.sum(np.ones_like(flbl), flbl, range(1, fn + 1))
                small = {i + 1 for i, s in enumerate(sizes) if s < despeckle}
                if small:
                    a[np.isin(flbl, list(small)), 3] = 0
                    fg = a[:, :, 3] > 0
        if shrink > 0:
            fg = ndimage.binary_erosion(fg, iterations=shrink)
            a[~fg, 3] = 0
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


def union_crop(frames):
    """全コマの不透明領域の和集合 bbox で全コマを同寸クロップ。"""
    box = None
    for im in frames:
        bb = im.getbbox()  # アルファ>0 の bbox
        if bb is None:
            continue
        if box is None:
            box = list(bb)
        else:
            box[0] = min(box[0], bb[0]); box[1] = min(box[1], bb[1])
            box[2] = max(box[2], bb[2]); box[3] = max(box[3], bb[3])
    if box is None:
        return frames
    return [im.crop(box) for im in frames]


def shared_palette(frames, k):
    """全コマの不透明画素から共通 K 色パレットを作り、各コマに適用（コマ間で色を固定）。"""
    import numpy as np
    samples = []
    for im in frames:
        a = np.array(im)
        op = a[a[:, :, 3] > 0][:, :3]
        if len(op):
            samples.append(op)
    if not samples:
        return frames
    allpix = np.concatenate(samples, axis=0)
    if len(allpix) > 200000:  # 量子化が重くならないよう間引いてパレット推定
        allpix = allpix[np.random.RandomState(0).choice(len(allpix), 200000, replace=False)]
    strip = Image.fromarray(allpix.reshape(1, -1, 3).astype("uint8"), "RGB")
    pal = strip.quantize(colors=k, method=Image.Quantize.MEDIANCUT)

    out = []
    for im in frames:
        rgb = im.convert("RGB").quantize(palette=pal, dither=Image.Dither.NONE).convert("RGB")
        r, g, b = rgb.split()
        out.append(Image.merge("RGBA", (r, g, b, im.split()[3])))
    return out


def downscale_h(frames, height):
    """高さ basis でニアレストネイバー縮小（ドットの輪郭を保つ）。"""
    out = []
    for im in frames:
        w, h = im.size
        if h <= height:
            out.append(im); continue
        nw = max(1, round(w * height / h))
        out.append(im.resize((nw, height), Image.Resampling.NEAREST))
    return out


def pad_even(frames):
    """シート連結が崩れないよう全コマを最大寸の中央に揃える（同寸化の保険）。"""
    w = max(im.size[0] for im in frames)
    h = max(im.size[1] for im in frames)
    out = []
    for im in frames:
        canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        canvas.paste(im, ((w - im.size[0]) // 2, (h - im.size[1]) // 2))
        out.append(canvas)
    return out


def make_sheet(frames):
    """横1列の連結シートを作る。"""
    w, h = frames[0].size
    sheet = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, im in enumerate(frames):
        sheet.paste(im, (i * w, 0))
    return sheet


def main():
    ap = argparse.ArgumentParser(description="AI動画 → クリーンなスプライト素材")
    ap.add_argument("char_id", help="キャラID（出力フォルダ名）")
    ap.add_argument("src", help="動画 / GIF / 連番画像フォルダ")
    ap.add_argument("--anim", default="idle", help="モーション名（idle/walk/cast 等）")
    ap.add_argument("--frames", type=int, default=12, help="最終コマ数（既定12, 0で間引かない）")
    ap.add_argument("--fps", type=float, default=12, help="動画入力のサンプリングfps")
    ap.add_argument("--bg", default="auto", help="背景色hex（既定autoで四隅推定）")
    ap.add_argument("--tol", type=int, default=24, help="背景色の許容差±")
    ap.add_argument("--despeckle", type=int, default=12, help="この画素数未満の孤立アルファを除去")
    ap.add_argument("--shrink", type=int, default=1, help="縁をNpx収縮してフリンジ除去")
    ap.add_argument("--colors", type=int, default=48, help="共通パレットの色数")
    ap.add_argument("--no-quantize", action="store_true", help="パレット量子化をしない")
    ap.add_argument("--height", type=int, default=0, help="この高さにニアレスト縮小（0で原寸）")
    ap.add_argument("--keep-last", action="store_true", help="ループ末尾の重複コマを落とさない")
    args = ap.parse_args()

    work = os.path.join(OUT_RAW, "%s_%s" % (args.char_id, args.anim))
    os.makedirs(work, exist_ok=True)
    outdir = os.path.join(SPRITES, args.char_id, args.anim)
    os.makedirs(outdir, exist_ok=True)

    frames = extract_frames(args.src, work, args.fps)
    print("取り込み: %d コマ" % len(frames))

    frames = thin(frames, args.frames, drop_last_dupe=not args.keep_last)
    print("間引き後: %d コマ" % len(frames))

    bg = _auto_bg(frames) if args.bg == "auto" else args.bg.lstrip("#")
    print("背景色: #%s (tol±%d)" % (bg, args.tol))
    frames = [key_bg(im, bg, args.tol, args.despeckle, args.shrink) for im in frames]

    frames = union_crop(frames)

    if args.height > 0:
        frames = downscale_h(frames, args.height)

    if not args.no_quantize and args.colors > 0:
        frames = shared_palette(frames, args.colors)
        print("パレット: %d 色（全コマ共通）" % args.colors)

    frames = pad_even(frames)
    fw, fh = frames[0].size

    for i, im in enumerate(frames):
        im.save(os.path.join(outdir, "frame_%03d.png" % i))
    sheet = make_sheet(frames)
    sheet_name = "%s_%s_sheet.png" % (args.char_id, args.anim)
    sheet.save(os.path.join(outdir, sheet_name))

    meta = {
        "id": args.char_id,
        "anim": args.anim,
        "source": os.path.basename(args.src),
        "fps": args.fps,
        "frame_count": len(frames),
        "frame_w": fw,
        "frame_h": fh,
        "sheet": sheet_name,
        "cols": len(frames),
        "rows": 1,
        "bg_keyed": bg,
        "colors": 0 if args.no_quantize else args.colors,
        "created": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    with open(os.path.join(outdir, "meta.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)

    print("出力 → %s  （%dコマ %dx%d ＋ %s）" % (outdir, len(frames), fw, fh, sheet_name))


if __name__ == "__main__":
    main()
