#!/usr/bin/env python3
"""
pixellab_anim_gen.py
PixelLab animate-with-text-v3 で既存 Gemini idle_f0 スプライトから
多フレームアニメーションを生成する。

パイプライン:
  1. assets/generated/sprites/<char>/idle_f0.png を読み込む
  2. 48×64 にリサイズして first_frame として送信
  3. PixelLab が N フレームのアニメを返す
  4. NEAREST ×3 で 144×192 に拡大して保存

使い方:
    python3 tools/pixellab_anim_gen.py --char mil --anims run
    python3 tools/pixellab_anim_gen.py --char mil
    python3 tools/pixellab_anim_gen.py --char all --frames 16
    python3 tools/pixellab_anim_gen.py --char mil --force
"""

import argparse, base64, io, json, os, sys, time, urllib.request
from pathlib import Path
from PIL import Image

ROOT     = Path(__file__).parent.parent
OUT_BASE = ROOT / "assets/generated/sprites"
BASE_URL = "https://api.pixellab.ai/v2"
POLL_INTERVAL = 4
POLL_TIMEOUT  = 300

IN_W, IN_H  = 48, 64   # PixelLab に渡すサイズ
OUT_SCALE   = 3        # → 144×192

ANIM_DEFS = {
    "idle": {
        "frames": 8,
        "action": "idle breathing loop, character standing still with subtle up-and-down body movement, blinking eyes",
    },
    "run": {
        "frames": 8,
        "action": "run cycle side view moving right, legs and arms pumping alternately, full running animation loop",
    },
    "attack": {
        "frames": 8,
        "action": "melee attack animation, wind up then strike forward with fist or weapon, then recover",
    },
    "hurt": {
        "frames": 4,
        "action": "hit reaction, character flinches backwards from an impact",
    },
    "die": {
        "frames": 8,
        "action": "death animation, character staggers and falls to the ground",
    },
}

CHARS = ["mil", "yuzuki", "muu", "kiriko", "doctor", "nurse"]


def load_api_key() -> str:
    key = os.environ.get("PIXELLAB_API_KEY", "")
    if not key:
        env = ROOT / ".env"
        if env.exists():
            for line in env.read_text().splitlines():
                if line.startswith("PIXELLAB_API_KEY="):
                    key = line.split("=", 1)[1].strip().strip('"\'')
                    break
    if not key:
        sys.exit("ERROR: PIXELLAB_API_KEY not found")
    return key


def api_post(key: str, path: str, body: dict) -> dict:
    req = urllib.request.Request(
        BASE_URL + path,
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code}: {e.read().decode()[:400]}") from e


def api_get(key: str, path: str) -> dict:
    req = urllib.request.Request(
        BASE_URL + path,
        headers={"Authorization": f"Bearer {key}"},
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


def poll_job(key: str, job_id: str) -> dict:
    deadline = time.time() + POLL_TIMEOUT
    while time.time() < deadline:
        result = api_get(key, f"/background-jobs/{job_id}")
        status = result.get("status", "?")
        print(f"    [{job_id[:8]}] {status}", flush=True)
        if status == "completed":
            return result.get("last_response", {})
        if status in ("failed", "canceled", "error"):
            raise RuntimeError(f"Job failed: {result}")
        time.sleep(POLL_INTERVAL)
    raise TimeoutError(f"Job {job_id} timed out")


def img_to_b64(img: Image.Image) -> str:
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return base64.b64encode(buf.getvalue()).decode()


def b64_to_img(b64: str) -> Image.Image:
    if b64.startswith("data:"):
        b64 = b64.split(",", 1)[1]
    return Image.open(io.BytesIO(base64.b64decode(b64))).convert("RGBA")


def load_first_frame(char_id: str) -> Image.Image:
    """idle_f0.png を読み込んで IN_W×IN_H にリサイズ"""
    p = OUT_BASE / char_id / "idle_f0.png"
    if not p.exists():
        raise FileNotFoundError(f"first frame not found: {p}")
    img = Image.open(p).convert("RGBA")
    # NEAREST で縮小（ピクセルアートはNEARESTが最適）
    img = img.resize((IN_W, IN_H), Image.NEAREST)
    return img


def generate_anim(key: str, first_frame: Image.Image, action: str, frame_count: int) -> list[Image.Image]:
    print(f"  animate-with-text-v3: {frame_count}f  '{action[:55]}'", flush=True)
    body = {
        "first_frame": {"type": "base64", "base64": img_to_b64(first_frame)},
        "action":      action,
        "frame_count": frame_count,
    }
    result = api_post(key, "/animate-with-text-v3", body)
    job_id = result.get("background_job_id") or result.get("id")
    if not job_id:
        raise RuntimeError(f"No job_id: {result}")
    response = poll_job(key, job_id)
    images = response.get("images", [])
    if not images:
        raise RuntimeError(f"No images in response: {response}")
    return [b64_to_img(img.get("base64", "")) for img in images]


def save_frames(frames: list[Image.Image], char_id: str, anim_name: str):
    out_dir = OUT_BASE / char_id
    out_dir.mkdir(parents=True, exist_ok=True)
    for i, frame in enumerate(frames):
        # NEAREST で 144×192 にスケールアップ
        frame = frame.resize((IN_W * OUT_SCALE, IN_H * OUT_SCALE), Image.NEAREST)
        p = out_dir / f"{anim_name}_f{i}.png"
        frame.save(p)
        print(f"    saved {p.name}: {frame.size}")


def process_char(char_id: str, anim_names: list[str], frames_override: int | None, force: bool, key: str):
    print(f"\n[{char_id}]")
    try:
        first_frame = load_first_frame(char_id)
        print(f"  first_frame: {first_frame.size} (from idle_f0.png)")
    except FileNotFoundError as e:
        print(f"  SKIP: {e}")
        return

    for anim_name in anim_names:
        defn = ANIM_DEFS.get(anim_name)
        if defn is None:
            print(f"  unknown anim: {anim_name}")
            continue

        n = frames_override or defn["frames"]
        out_dir = OUT_BASE / char_id

        # 既存チェック
        if not force and all((out_dir / f"{anim_name}_f{i}.png").exists() for i in range(n)):
            print(f"  skip {anim_name} ({n} frames already exist)")
            continue

        try:
            frames = generate_anim(key, first_frame, defn["action"], n)
            save_frames(frames, char_id, anim_name)
        except Exception as e:
            print(f"  ERROR {anim_name}: {e}")
        time.sleep(2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--char",   default="all")
    ap.add_argument("--anims",  nargs="+", default=list(ANIM_DEFS.keys()))
    ap.add_argument("--frames", type=int, default=None, help="フレーム数上書き")
    ap.add_argument("--force",  action="store_true")
    args = ap.parse_args()

    key   = load_api_key()
    chars = CHARS if args.char == "all" else [args.char]

    for cid in chars:
        process_char(cid, args.anims, args.frames, args.force, key)

    print("\nDone. Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .")


if __name__ == "__main__":
    main()
