#!/usr/bin/env python3
"""
import_kenney_sfx.py — Kenney の CC0 効果音パックから、この作品で使う分だけを取り込む。

なぜスクリプトにするか：どのファイルがどの音源から来たのかを後から辿れるようにするため。
アセットを手で置くと、半年後に「この音はどこから来たのか」が分からなくなる。

出どころ（どちらも CC0 1.0 / Kenney）:
  - https://github.com/Calinou/kenney-ui-audio        （Kenney UI Audio を Godot 向けに wav 化）
  - https://github.com/Calinou/kenney-interface-sounds（Kenney Interface Sounds、同上）

変換は `assets/third_party/CREDITS.md` の既存ルールに合わせる：
  16bit / 22.05kHz / モノラル。標準ライブラリだけで完結させる（audioop は 3.13 で消えるので使わない）。

使い方:
    python3 tools/import_kenney_sfx.py            # 一時ディレクトリへ clone して取り込む
    python3 tools/import_kenney_sfx.py --keep     # clone を消さずに残す（音を聴き比べたい時）
"""

import argparse
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets/third_party/sfx")

REPOS = {
    "ui": "https://github.com/Calinou/kenney-ui-audio.git",
    "iface": "https://github.com/Calinou/kenney-interface-sounds.git",
}

# 出力名 → [(元ファイル, 開始オフセット秒, 音量倍率), ...]
# 複数指定した場合は重ねる（CC0 なので加工・派生は自由）。
# 選定は波形の実測（長さ・ピーク・ゼロ交差率＝明るさ）に基づく。
#   例：bong_001 は ZCR 0.2 で最も暗く重い → 格の高い箱の芯に。
#       glass_004 は 0.71秒 ZCR 14.6 で最も明るく長い → その上に散らす飾りに。
RECIPES = {
    # 箱開封：等級が上がるほど「重い芯」と「明るい飾り」が増える
    "box_wood":     [("drop_001.wav", 0.0, 0.85)],
    "box_iron":     [("confirmation_001.wav", 0.0, 0.9)],
    "box_silver":   [("glass_002.wav", 0.0, 0.9), ("confirmation_001.wav", 0.06, 0.45)],
    "box_gold":     [("bong_001.wav", 0.0, 1.0), ("glass_004.wav", 0.05, 0.7)],
    # 潜航
    "boss_appear":  [("bong_001.wav", 0.0, 1.0), ("glitch_001.wav", 0.0, 0.6)],
    "wipe_out":     [("error_002.wav", 0.0, 0.9)],
    "pickup":       [("pluck_001.wav", 0.0, 0.85)],
    "memory_get":   [("glass_004.wav", 0.0, 0.85)],
    # 経営
    "renov_unlock": [("confirmation_002.wav", 0.0, 0.95)],
    "craft_great":  [("confirmation_002.wav", 0.0, 0.9), ("glass_004.wav", 0.10, 0.65)],
    "daily_done":   [("confirmation_003.wav", 0.0, 0.9)],
    "streak_up":    [("pluck_002.wav", 0.0, 0.8), ("pluck_001.wav", 0.09, 0.8)],
    # 夜営業
    "serve_dish":   [("drop_002.wav", 0.0, 0.8)],
    "guest_leave":  [("back_002.wav", 0.0, 0.75)],
    "ticket":       [("tick_001.wav", 0.0, 0.7)],
    "night_close":  [("close_002.wav", 0.0, 0.9)],
    # 横断
    "focus_start":  [("switch_001.wav", 0.0, 0.9)],
    "sheet_open":   [("open_002.wav", 0.0, 0.7)],
    "talk_next":    [("select_002.wav", 0.0, 0.6)],
}

TARGET_RATE = 22050


def read_wav(path):
    """wav を読み、(モノラルの float リスト, サンプリングレート) にする。"""
    with wave.open(path, "rb") as w:
        ch, sw, fr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    if sw != 2:
        raise SystemExit("想定外のビット深度: %s (%dbit)" % (path, sw * 8))
    vals = struct.unpack("<%dh" % (len(raw) // 2), raw)
    if ch == 2:
        vals = [(vals[i] + vals[i + 1]) * 0.5 for i in range(0, len(vals) - 1, 2)]
    return [v / 32768.0 for v in vals], fr


def resample(samples, src_rate, dst_rate):
    """線形補間のリサンプル。UI用の短い音なので、これで十分な品質が出る。"""
    if src_rate == dst_rate:
        return list(samples)
    ratio = dst_rate / src_rate
    out_n = int(len(samples) * ratio)
    out = []
    for i in range(out_n):
        pos = i / ratio
        i0 = int(pos)
        i1 = min(i0 + 1, len(samples) - 1)
        frac = pos - i0
        out.append(samples[i0] * (1.0 - frac) + samples[i1] * frac)
    return out


def mix(layers):
    """[(サンプル列, 開始オフセット秒, 音量), ...] を1本に重ねる。"""
    length = max(int(off * TARGET_RATE) + len(s) for s, off, _ in layers)
    buf = [0.0] * length
    for s, off, gain in layers:
        start = int(off * TARGET_RATE)
        for i, v in enumerate(s):
            buf[start + i] += v * gain
    return buf


def normalize(buf, peak=0.92):
    """ピークを揃える。歪ませないよう素直に定数倍だけ（ソフトクリップは掛けない）。"""
    m = max((abs(v) for v in buf), default=0.0)
    if m <= 1e-9:
        return buf
    k = peak / m
    return [v * k for v in buf]


def write_wav(path, buf):
    data = b"".join(struct.pack("<h", max(-32768, min(32767, int(v * 32767)))) for v in buf)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(TARGET_RATE)
        w.writeframes(data)


def find(dirs, name):
    for d in dirs:
        for root, _, files in os.walk(d):
            if name in files:
                return os.path.join(root, name)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep", action="store_true", help="clone を残す")
    args = ap.parse_args()

    tmp = tempfile.mkdtemp(prefix="kenney_sfx_")
    dirs = []
    try:
        for key, url in REPOS.items():
            dst = os.path.join(tmp, key)
            print("clone: %s" % url)
            r = subprocess.run(["git", "clone", "--depth", "1", "-q", url, dst],
                               capture_output=True, text=True)
            if r.returncode != 0:
                raise SystemExit("clone に失敗: %s\n%s" % (url, r.stderr))
            dirs.append(dst)

        os.makedirs(OUT_DIR, exist_ok=True)
        for out_name, recipe in RECIPES.items():
            layers = []
            for src_name, off, gain in recipe:
                p = find(dirs, src_name)
                if p is None:
                    raise SystemExit("音源が見つからない: %s" % src_name)
                s, fr = read_wav(p)
                layers.append((resample(s, fr, TARGET_RATE), off, gain))
            buf = normalize(mix(layers))
            out = os.path.join(OUT_DIR, out_name + ".wav")
            write_wav(out, buf)
            print("  %-14s <- %s  (%.2f秒)" % (
                out_name, " + ".join(r[0] for r in recipe), len(buf) / TARGET_RATE))
    finally:
        if args.keep:
            print("clone を残した: %s" % tmp)
        else:
            shutil.rmtree(tmp, ignore_errors=True)
    print("完了: %d 本を %s へ" % (len(RECIPES), os.path.relpath(OUT_DIR, ROOT)))


if __name__ == "__main__":
    sys.exit(main() or 0)
