#!/usr/bin/env python3
"""
gen_anim_frames_gemini.py
キーアニメーション（run/idle/attack/hurt）の複数フレームストリップを生成。

Gemini に「水平ストリップ (N フレーム横並び)」を生成させ、
等幅スライスで _f0.png / _f1.png ... として保存する。

使い方:
    python3 tools/gen_anim_frames_gemini.py --char mil
    python3 tools/gen_anim_frames_gemini.py --char all
    python3 tools/gen_anim_frames_gemini.py --char mil --anims run idle
    python3 tools/gen_anim_frames_gemini.py --char mil --force
"""

import argparse, base64, io, json, os, sys, time, urllib.request
from pathlib import Path
from PIL import Image
import numpy as np

ROOT       = Path(__file__).parent.parent
STYLE_REF  = ROOT / "docs/Refs/sprite_style_ref.png"
CHARA_REF  = ROOT / "docs/Refs/Chara"
OUT_BASE   = ROOT / "assets/generated/sprites"
RAW_DIR    = Path(__file__).parent / "_out/anim_frames_raw"
RAW_DIR.mkdir(parents=True, exist_ok=True)

MODEL   = "gemini-3-pro-image-preview"
API_URL = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent"

DOT_W = 48
DOT_H = 64
SCALE = 3

# ── アニメーション定義（フレーム数 + 内容説明）────────────────────────────
ANIM_DEFS = {
    "idle": {
        "frames": 4,
        "desc": (
            "idle breathing loop: "
            "f0=normal standing neutral, "
            "f1=slight exhale body shifts down 1-2px, "
            "f2=inhale body shifts back up, "
            "f3=peak inhale slightly tallest"
        ),
    },
    "run": {
        "frames": 6,
        "desc": (
            "run cycle (side view, running right): "
            "f0=left leg forward right leg back arms opposite, "
            "f1=both feet near ground passing mid stride, "
            "f2=right leg forward left leg back, "
            "f3=airborne both feet off ground, "
            "f4=left leg forward again landing, "
            "f5=mid stride returning"
        ),
    },
    "attack": {
        "frames": 4,
        "desc": (
            "attack animation: "
            "f0=wind-up arm pulled back, "
            "f1=strike arm fully extended forward, "
            "f2=follow-through leaning forward, "
            "f3=recovery returning to stance"
        ),
    },
    "hurt": {
        "frames": 3,
        "desc": (
            "hurt/hit reaction: "
            "f0=impact body jolts back, "
            "f1=recoil fully flinched backward, "
            "f2=recovering leaning forward slightly"
        ),
    },
    "die": {
        "frames": 4,
        "desc": (
            "death animation: "
            "f0=hit stagger, "
            "f1=knees buckling, "
            "f2=falling sideways, "
            "f3=lying flat on ground"
        ),
    },
}

CHARS = {
    "mil": {
        "appearance": "chibi anime girl, 2 head tall, full body, short white hair with pink inner color, black leather jacket, pink crop top, black pants",
        "base": CHARA_REF / "Milu.png",
    },
    "yuzuki": {
        "appearance": "chibi anime girl, 2 head tall, full body, orange twin tails hair, black sweatshirt, street fashion",
        "base": CHARA_REF / "yuzuki.png",
    },
    "muu": {
        "appearance": "chibi anime girl, 2 head tall, full body, blonde hair, fox ears, white jacket, blue futuristic dress",
        "base": CHARA_REF / "myu.png",
    },
    "kiriko": {
        "appearance": "chibi anime girl, 2 head tall, full body, long blue hair, golden eyes, white ceremonial dress",
        "base": CHARA_REF / "reika.png",
    },
    "doctor": {
        "appearance": "chibi anime woman, 2 head tall, full body, short dark hair, white lab coat, teal scrubs underneath",
        "base": CHARA_REF / "doc.png",
    },
    "nurse": {
        "appearance": "chibi anime woman, 2 head tall, full body, light hair, white nurse uniform, nurse cap",
        "base": CHARA_REF / "nurse.png",
    },
}


def load_b64(path: Path) -> str:
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode()


def build_prompt(appearance: str, anim_name: str, frame_count: int, desc: str) -> str:
    total_w = DOT_W * frame_count
    return (
        f"You are given TWO reference images:\n"
        f"  Image 1 = pixel art style guide (GBA/16-bit RPG chibi sprite style)\n"
        f"  Image 2 = the character design to recreate\n\n"
        f"Task: Generate a pixel art ANIMATION STRIP for '{anim_name}'.\n\n"
        f"Animation description:\n{desc}\n\n"
        f"OUTPUT REQUIREMENTS:\n"
        f"- Exactly {frame_count} frames arranged HORIZONTALLY, left to right\n"
        f"- Each frame: {DOT_W}×{DOT_H} pixels  (total strip: {total_w}×{DOT_H})\n"
        f"- ENTIRE IMAGE background: solid bright MAGENTA #FF00FF — top to bottom, edge to edge\n"
        f"- No borders between frames, NO text, NO labels, NO extra drawings\n"
        f"- DO NOT add anything below the sprite row. The output must be a single row of sprites only.\n"
        f"- Pixel art style matching Image 1: limited palette, black outlines\n"
        f"- Character: {appearance}\n"
        f"- Chibi: head ≈ half total height, full body visible (head/torso/legs/feet)\n"
        f"- Consistent character identity across ALL {frame_count} frames\n"
        f"- Output ONLY the strip image, nothing else. ONLY magenta background, no other backgrounds."
    )


def call_gemini(style_b64: str, char_b64: str, prompt: str, api_key: str) -> bytes | None:
    payload = {
        "contents": [{
            "parts": [
                {"inline_data": {"mime_type": "image/png", "data": style_b64}},
                {"inline_data": {"mime_type": "image/png", "data": char_b64}},
                {"text": prompt},
            ]
        }],
        "generationConfig": {
            "temperature": 0.4,
            "topP": 0.95,
            "maxOutputTokens": 8192,
        },
    }
    req = urllib.request.Request(
        f"{API_URL}?key={api_key}",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        print(f"  HTTP {e.code}: {e.read().decode()[:300]}")
        return None

    for part in data.get("candidates", [{}])[0].get("content", {}).get("parts", []):
        if "inlineData" in part:
            return base64.b64decode(part["inlineData"]["data"])
    print("  WARNING: no image in response")
    return None


def magenta_key(img: Image.Image) -> Image.Image:
    img = img.convert("RGBA")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if r > 180 and g < 80 and b > 180:
                px[x, y] = (0, 0, 0, 0)
    return img


def pixelate(img: Image.Image) -> Image.Image:
    """バウンディングボックスを検出して足元を下端に揃えてからスケールする。
    Gemini がセル内の端にキャラクターを生成した場合でも正しく配置される。"""
    arr = np.array(img)
    alpha = arr[:, :, 3]
    rows = np.where((alpha > 30).any(axis=1))[0]
    cols = np.where((alpha > 30).any(axis=0))[0]

    if len(rows) == 0 or len(cols) == 0:
        # 透明フレーム: 空のキャンバスを返す
        return Image.new("RGBA", (DOT_W * SCALE, DOT_H * SCALE), (0, 0, 0, 0))

    # コンテンツの実際の境界（2px パディング付き）
    pad = 2
    top  = max(0, rows[0] - pad)
    bot  = min(img.height - 1, rows[-1] + pad)
    left = max(0, cols[0] - pad)
    right = min(img.width - 1, cols[-1] + pad)
    content = img.crop((left, top, right + 1, bot + 1))
    cw, ch = content.size

    # DOT_W × DOT_H に収まるようにアスペクト比を維持してリサイズ
    scale = min(DOT_W / cw, DOT_H / ch)
    new_w = max(1, int(cw * scale))
    new_h = max(1, int(ch * scale))
    content = content.resize((new_w, new_h), Image.LANCZOS)

    # DOT_W × DOT_H キャンバスに「水平中央・足元下端」で配置
    canvas = Image.new("RGBA", (DOT_W, DOT_H), (0, 0, 0, 0))
    x_off = (DOT_W - new_w) // 2
    y_off = DOT_H - new_h          # 足元を下端に
    canvas.paste(content, (x_off, y_off))

    # NEAREST × SCALE でピクセルアートを拡大
    return canvas.resize((DOT_W * SCALE, DOT_H * SCALE), Image.NEAREST)


def detect_strip_height(img: Image.Image) -> int:
    """マゼンタ背景行の末端を検出して返す (Geminiが余計なコンテンツを追加した場合に対応)"""
    arr = np.array(img.convert("RGB"))
    # マゼンタ: R>160, G<100, B>160
    is_magenta = (arr[:, :, 0] > 160) & (arr[:, :, 1] < 100) & (arr[:, :, 2] > 160)
    row_ratio = is_magenta.mean(axis=1)  # 各行のマゼンタ率
    # マゼンタが5%以上ある最後の行を探す
    strip_rows = np.where(row_ratio > 0.05)[0]
    if len(strip_rows) == 0:
        return img.height  # マゼンタなし → 全高使用
    return int(strip_rows[-1]) + 1


def slice_strip(strip_bytes: bytes, char_id: str, anim_name: str, frame_count: int, force: bool):
    out_dir = OUT_BASE / char_id
    out_dir.mkdir(parents=True, exist_ok=True)

    # 既存チェック
    if not force:
        if all((out_dir / f"{anim_name}_f{i}.png").exists() for i in range(frame_count)):
            print(f"  skip {anim_name} (already {frame_count} frames exist, use --force to regenerate)")
            return

    # raw保存
    raw_path = RAW_DIR / f"{char_id}_{anim_name}_strip.png"
    with open(raw_path, "wb") as f:
        f.write(strip_bytes)
    print(f"  raw strip saved: {raw_path.name}")

    img = Image.open(io.BytesIO(strip_bytes)).convert("RGBA")
    w, h = img.size

    # マゼンタ領域のみに限定（Geminiが余分なコンテンツを追加した場合の対策）
    strip_h = detect_strip_height(img)
    if strip_h < h:
        print(f"  detected strip height: {strip_h}px (full: {h}px) — trimming extra content")
        img = img.crop((0, 0, w, strip_h))
        h = strip_h

    # グリッド vs 横ストリップを自動判定
    # 横1列なら frame_w >= h*0.8 のはず。それより縦長なら グリッド
    frame_w_single = w // frame_count
    if frame_w_single >= h * 0.8:
        # 横1列ストリップ
        cols, rows = frame_count, 1
        print(f"  strip {w}×{h} → {frame_count} frames × {frame_w_single}px each (single row)")
    else:
        # グリッド: 最適な列数を探す（4→3→6→2→1 の優先順）
        cols = next((c for c in [4, 3, 6, 2, 1] if frame_count % c == 0), frame_count)
        rows = frame_count // cols
        print(f"  grid {w}×{h} → {cols}cols × {rows}rows = {frame_count} frames")

    fw = w // cols
    fh = h // rows

    for i in range(frame_count):
        row, col = divmod(i, cols)
        frame = img.crop((col * fw, row * fh, (col + 1) * fw, (row + 1) * fh))
        frame = magenta_key(frame)
        frame = pixelate(frame)
        out_path = out_dir / f"{anim_name}_f{i}.png"
        frame.save(out_path)
        print(f"    {out_path.name}: {frame.size}")


def generate_char_anims(char_id: str, anim_names: list[str], force: bool, api_key: str, frames_override: int | None = None):
    char = CHARS[char_id]
    style_b64 = load_b64(STYLE_REF)
    char_b64  = load_b64(char["base"])

    for anim_name in anim_names:
        if anim_name not in ANIM_DEFS:
            print(f"  unknown anim: {anim_name}")
            continue

        defn        = ANIM_DEFS[anim_name]
        frame_count = frames_override or defn["frames"]
        out_dir     = OUT_BASE / char_id

        # スキップチェック
        if not force and all((out_dir / f"{anim_name}_f{i}.png").exists() for i in range(frame_count)):
            print(f"[{char_id}] {anim_name}: skip (done)")
            continue

        print(f"[{char_id}] {anim_name}: generating {frame_count} frames...")
        prompt = build_prompt(char["appearance"], anim_name, frame_count, defn["desc"])
        strip  = call_gemini(style_b64, char_b64, prompt, api_key)

        if strip is None:
            print(f"  FAILED: no image returned")
            time.sleep(3)
            continue

        slice_strip(strip, char_id, anim_name, frame_count, force)
        time.sleep(2)  # API レート制限


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--char",  default="all", help="キャラID or 'all'")
    ap.add_argument("--anims", nargs="+", default=list(ANIM_DEFS.keys()),
                    help="生成するアニメーション名 (デフォルト: 全部)")
    ap.add_argument("--frames", type=int, default=None, help="フレーム数上書き")
    ap.add_argument("--force", action="store_true", help="既存ファイルを上書き")
    args = ap.parse_args()

    api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if not api_key:
        env_file = ROOT / ".env"
        if env_file.exists():
            for line in env_file.read_text().splitlines():
                if line.startswith("GEMINI_API_KEY=") or line.startswith("GOOGLE_API_KEY="):
                    api_key = line.split("=", 1)[1].strip().strip('"')
                    break
    if not api_key:
        sys.exit("ERROR: GEMINI_API_KEY not found")

    chars = list(CHARS.keys()) if args.char == "all" else [args.char]
    for cid in chars:
        if cid not in CHARS:
            print(f"Unknown char: {cid}")
            continue
        generate_char_anims(cid, args.anims, args.force, api_key, frames_override=args.frames)

    print("\nDone. Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .")


if __name__ == "__main__":
    main()
