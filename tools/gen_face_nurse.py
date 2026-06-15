#!/usr/bin/env python3
"""
ナースの表情シートを PixAI で一括生成する。
assets/generated/face/nurse/ に配置する。

使い方:
    export PIXAI_API_KEY=sk_...  # または .env に記入
    python3 tools/gen_face_nurse.py
    python3 tools/gen_face_nurse.py --force   # 全枚上書き

生成後は Godot --headless --import --path . で .import を更新してください。
"""

import argparse
import base64
import io
import json
import os
import sys
import time
import urllib.request
from pathlib import Path

# ── 設定 ──────────────────────────────────────────────────────────
MODEL_ID  = "1983308862240288769"   # Tsubaki.2
WIDTH     = 512
HEIGHT    = 512
STEPS     = 22
CFG       = 7
API_URL   = "https://api.pixai.art/graphql"
POLL_SEC  = 5
TIMEOUT   = 420

OUT_DIR   = Path(__file__).parent.parent / "assets/generated/face/nurse"
TMP_DIR   = Path(__file__).parent / "_out/face_nurse_raw"
REF_IMAGE = Path(__file__).parent.parent / "assets/portraits/nurse.png"

# ── プロンプト定義 ───────────────────────────────────────────────
BASE = (
    "1girl, chibi, super deformed, 2 head tall, thick black outline, "
    "flat color shading, front facing bust portrait, "
    "female android nurse, mint green hair, green eyes, "
    "white nurse dress with green accents, medical cross emblem, "
    "gentle expression, cybernetic nurse, Arknights style, "
    "anime style, simple shading, "
    "flat single color background #1a1030"
)
NEG = (
    "lowres, bad anatomy, bad hands, extra fingers, extra limbs, "
    "worst quality, low quality, blurry, deformed face, "
    "multiple girls, side view, back view, 3d, male"
)

# (ファイル名, プロンプト追加, シード)
VARIANTS = [
    # ── neutral ──────────────────────────────────────────────────
    ("neutral_closed", "neutral gentle expression, mouth closed, eyes open", 7101),
    ("neutral_half",   "neutral gentle expression, mouth slightly open, speaking", 7102),
    ("neutral_open",   "neutral gentle expression, mouth open wide, talking", 7103),
    ("neutral_blink",  "neutral gentle expression, mouth closed, eyes closed blinking", 7104),
    # ── smile ────────────────────────────────────────────────────
    ("smile_closed",   "warm caring smile, mouth closed, eyes soft and kind", 7201),
    ("smile_half",     "warm caring smile, mouth slightly open, gentle laugh", 7202),
    ("smile_open",     "warm caring smile, mouth open laughing happily", 7203),
    ("smile_blink",    "warm caring smile, eyes closed happily", 7204),
    # ── surprise ──────────────────────────────────────────────────
    ("surprise_closed","surprised expression, wide eyes, mouth closed", 7301),
    ("surprise_half",  "surprised expression, wide eyes, mouth slightly open", 7302),
    ("surprise_open",  "surprised expression, wide eyes, mouth open wide", 7303),
    ("surprise_blink", "startled expression, eyes shut tight, cute shock", 7304),
    # ── calm ──────────────────────────────────────────────────────
    ("calm_closed",    "professional focused expression, caring determined eyes, mouth closed", 7401),
    ("calm_half",      "professional focused expression, mouth slightly open", 7402),
    ("calm_open",      "professional focused expression, mouth open giving instructions", 7403),
    ("calm_blink",     "calm caring expression, eyes closed peacefully", 7404),
    # ── eat ───────────────────────────────────────────────────────
    ("eat_closed",     "eating food, chewing, mouth closed, cheeks puffed, happy", 7501),
    ("eat_half",       "eating food, mouth slightly open, delighted", 7502),
    ("eat_open",       "eating food, mouth open taking a bite, eyes wide happy", 7503),
    ("eat_blink",      "eating food, eyes closed in delight, delicious expression", 7504),
]

# ── リファレンス画像 ──────────────────────────────────────────────
def load_ref_base64(path: Path, max_px: int = 512) -> str | None:
    try:
        from PIL import Image
        with Image.open(path) as im:
            w, h = im.size
            if max(w, h) > max_px:
                scale = max_px / max(w, h)
                im = im.resize((int(w * scale), int(h * scale)), Image.LANCZOS)
            buf = io.BytesIO()
            im.convert("RGB").save(buf, "JPEG", quality=85)
            return base64.b64encode(buf.getvalue()).decode("ascii")
    except Exception as e:
        print(f"[ref skip: {e}]", end=" ")
        return None


# ── API helpers ──────────────────────────────────────────────────
MUTATION_CREATE = """
mutation CreateTask($parameters: JSONObject!) {
  createGenerationTask(parameters: $parameters) { id }
}
"""
QUERY_TASK = """
query GetTask($id: ID!) {
  task(id: $id) {
    status
    media { urls { variant url } }
  }
}
"""


def load_api_key() -> str:
    key = os.getenv("PIXAI_API_KEY", "")
    if not key:
        env_path = Path(__file__).parent.parent / ".env"
        if env_path.exists():
            for line in env_path.read_text().splitlines():
                line = line.strip()
                if line.startswith("PIXAI_API_KEY="):
                    key = line.split("=", 1)[1].strip().strip('"').strip("'")
    if not key:
        sys.exit("ERROR: PIXAI_API_KEY が見つかりません")
    return key


def gql(api_key, query, variables):
    payload = json.dumps({"query": query, "variables": variables}).encode()
    req = urllib.request.Request(
        API_URL, data=payload,
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.loads(r.read())
    if "errors" in data:
        raise RuntimeError(f"GraphQL: {data['errors']}")
    return data["data"]


def create_task(api_key, prompt, seed, ref_b64: str | None = None):
    params = {
        "modelId": MODEL_ID, "prompts": f"{BASE}, {prompt}",
        "negativePrompts": NEG, "samplingSteps": STEPS,
        "samplingMethod": "dpmpp_2m_karras", "cfgScale": CFG,
        "width": WIDTH, "height": HEIGHT, "seed": seed,
    }
    if ref_b64:
        params["referenceImage"] = ref_b64
    return gql(api_key, MUTATION_CREATE, {"parameters": params})["createGenerationTask"]["id"]


def poll_task(api_key, task_id):
    deadline = time.time() + TIMEOUT
    while time.time() < deadline:
        task = gql(api_key, QUERY_TASK, {"id": task_id}).get("task")
        if task is None:
            time.sleep(POLL_SEC)
            continue
        status = task.get("status", "?")
        print(f"    {status}", end=" ", flush=True)
        if status in ("succeeded", "completed"):
            urls = (task.get("media") or {}).get("urls") or []
            for e in urls:
                if e.get("variant") == "full":
                    return e["url"]
            return urls[0]["url"] if urls else None
        if status in ("failed", "cancelled", "error"):
            return None
        time.sleep(POLL_SEC)
    return None


def download(url, dest: Path):
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "gen_face_nurse/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        dest.write_bytes(r.read())


def key_background(src: Path, dst: Path, bg_hex: str = "1a1030", tol: int = 28):
    """縁から塗りつぶして単色背景を透過に抜く。"""
    from PIL import Image
    try:
        import numpy as np
        from scipy import ndimage
        img = Image.open(src).convert("RGBA")
        a = np.array(img)
        r0, g0, b0 = int(bg_hex[0:2], 16), int(bg_hex[2:4], 16), int(bg_hex[4:6], 16)
        rgb = a[:, :, :3].astype(int)
        near = ((abs(rgb[:, :, 0] - r0) <= tol) &
                (abs(rgb[:, :, 1] - g0) <= tol) &
                (abs(rgb[:, :, 2] - b0) <= tol))
        lbl, _ = ndimage.label(near)
        border = (set(lbl[0, :]) | set(lbl[-1, :]) | set(lbl[:, 0]) | set(lbl[:, -1])) - {0}
        mask = np.isin(lbl, list(border))
        a[mask, 3] = 0
        Image.fromarray(a).save(dst)
        print("keyed", end=" ")
    except ImportError:
        img = Image.open(src).convert("RGBA")
        img.save(dst)
        print("saved(no-key)", end=" ")


# ── main ─────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--force",  action="store_true", help="既存ファイルも上書き")
    parser.add_argument("--no-ref", action="store_true", help="リファレンス画像を使わない")
    args = parser.parse_args()

    api_key = load_api_key()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    TMP_DIR.mkdir(parents=True, exist_ok=True)

    ref_b64 = None
    if not args.no_ref and REF_IMAGE.exists():
        ref_b64 = load_ref_base64(REF_IMAGE)
        if ref_b64:
            print(f"[ref] {REF_IMAGE.name} 使用\n")

    total = len(VARIANTS)
    for idx, (name, extra_prompt, seed) in enumerate(VARIANTS, 1):
        dst = OUT_DIR / f"{name}.png"
        if dst.exists() and not args.force:
            print(f"[{idx}/{total}] {name} → skip (already exists)")
            continue

        print(f"[{idx}/{total}] {name} ... ", end="", flush=True)
        tmp = TMP_DIR / f"{name}_raw.png"
        try:
            task_id = create_task(api_key, extra_prompt, seed, ref_b64=ref_b64)
            url = poll_task(api_key, task_id)
            if not url:
                print("FAILED")
                continue
            print()
            download(url, tmp)
            key_background(tmp, dst)
            print(f"→ {dst.name}")
        except Exception as e:
            print(f"ERROR: {e}")

    print("\n完了。Godot で再インポートしてください:")
    print("  /Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .")


if __name__ == "__main__":
    main()
