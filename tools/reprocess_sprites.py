#!/usr/bin/env python3
"""
reprocess_sprites.py
既存の raw strip から全スプライトフレームを再スライス（Gemini API 不要）。
gen_anim_frames_gemini.py の pixelate() をバウンディングボックス版に更新した後に実行する。

使い方:
    python3 tools/reprocess_sprites.py
    python3 tools/reprocess_sprites.py --char mil --anims run
"""

import argparse, io, sys
from pathlib import Path

ROOT    = Path(__file__).parent.parent
RAW_DIR = Path(__file__).parent / "_out/anim_frames_raw"
sys.path.insert(0, str(Path(__file__).parent))

# gen_anim_frames_gemini から処理関数を直接インポート
from gen_anim_frames_gemini import (
    slice_strip, CHARS, ANIM_DEFS, OUT_BASE
)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--char",   default="all", help="キャラID or 'all'")
    ap.add_argument("--anims",  nargs="+", default=list(ANIM_DEFS.keys()))
    ap.add_argument("--frames", type=int, default=12,
                    help="生成時に使ったフレーム数（--frames 12 で生成した場合は 12）")
    args = ap.parse_args()

    chars = list(CHARS.keys()) if args.char == "all" else [args.char]

    for cid in chars:
        for anim in args.anims:
            raw_path = RAW_DIR / f"{cid}_{anim}_strip.png"
            if not raw_path.exists():
                print(f"[{cid}] {anim}: raw strip not found — skip")
                continue

            frame_count = args.frames
            # force=True で既存ファイルを上書き
            strip_bytes = raw_path.read_bytes()
            print(f"[{cid}] {anim}: reprocessing {frame_count} frames from {raw_path.name}")
            slice_strip(strip_bytes, cid, anim, frame_count, force=True)

    print("\nDone. Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .")


if __name__ == "__main__":
    main()
