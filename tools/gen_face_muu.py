#!/usr/bin/env python3
"""
ムュウの表情シートを PixAI (Tsubaki.2) で一括生成する。
assets/generated/face/muu/ に直接配置。

使い方:
    export PIXAI_API_KEY=sk_...  # または .env に記入
    python3 tools/gen_face_muu.py [--force]   # --force で既存ファイルも上書き

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

OUT_DIR   = Path(__file__).parent.parent / "assets/generated/face/muu"
TMP_DIR   = Path(__file__).parent / "_out/face_muu_raw"
REF_IMAGE = Path(__file__).parent.parent / "docs/Refs/Chara/myu.png"

# ── プロンプト定義 ───────────────────────────────────────────────
# ムュウ：手数・歌担当のストリーマー系少女。
# 明るいピンクのツインテール、ピンクの瞳、パープルがかったかわいい魔法少女風衣装。
# 元気で表情豊か、でも時々寂しそう。
BASE = (
    "1girl, chibi, super deformed, 2 head tall, thick black outline, "
    "flat color shading, front facing bust portrait, "
    "cute fox girl, long blonde hair, fox ears, blue eyes, "
    "white oversized jacket, blue futuristic dress, "
    "energetic idol streamer, cyber explorer, Arknights style, "
    "anime style, simple shading, "
    "flat single color background #1a1030"
)
NEG = (
    "lowres, bad anatomy, bad hands, extra fingers, extra limbs, "
    "worst quality, low quality, blurry, deformed face, "
    "multiple girls, side view, back view, 3d, cold colors, dark"
)

# (ファイル名, プロンプト追加, シード)
VARIANTS = [
    # ── neutral ──────────────────────────────────────────────────
    ("neutral_closed", "neutral expression, mouth closed, eyes open, relaxed", 3101),
    ("neutral_half",   "neutral expression, mouth slightly open, chatting casually, eyes open", 3102),
    ("neutral_open",   "neutral expression, mouth open wide, talking excitedly, eyes open", 3103),
    ("neutral_blink",  "neutral expression, mouth closed, eyes closed blinking cutely", 3104),
    # ── smile ────────────────────────────────────────────────────
    ("smile_closed",   "big cheerful smile, happy expression, mouth closed, eyes curved", 3201),
    ("smile_half",     "big cheerful smile, mouth slightly open laughing, eyes sparkling", 3202),
    ("smile_open",     "big cheerful smile, mouth open laughing happily, eyes closed happy", 3203),
    ("smile_blink",    "big cheerful smile, eyes closed laughing, so happy expression", 3204),
    # ── surprise ──────────────────────────────────────────────────
    ("surprise_closed","surprised expression, wide sparkly eyes, mouth closed, uwaa face", 3301),
    ("surprise_half",  "surprised expression, wide eyes, mouth slightly open, startled cute", 3302),
    ("surprise_open",  "surprised expression, wide eyes, mouth open wide, shocked and cute", 3303),
    ("surprise_blink", "surprised expression, eyes shut tight suddenly, squealing", 3304),
    # ── calm ──────────────────────────────────────────────────────
    ("calm_closed",    "calm slightly pouty expression, thinking face, mouth closed", 3401),
    ("calm_half",      "calm slightly pouty expression, mouth slightly open, hmm thinking", 3402),
    ("calm_open",      "calm expression, mouth open, saying something thoughtful", 3403),
    ("calm_blink",     "calm expression, eyes closed gently, slightly lonely, wistful", 3404),
    # ── eat ───────────────────────────────────────────────────────
    ("eat_closed",     "eating sweets, chewing happily, mouth closed, cheeks puffed", 3501),
    ("eat_half",       "eating sweets, mouth slightly open, savoring the sweetness", 3502),
    ("eat_open",       "eating sweets, mouth open taking a big happy bite", 3503),
    ("eat_blink",      "eating sweets, eyes closed in pure delight, so yummy face", 3504),
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
    req = urllib.request.Request(url, headers={"User-Agent": "gen_face_muu/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        dest.write_bytes(r.read())


def key_background(src: Path, dst: Path, bg_hex: str = "", tol: int = 28):
    """縁から塗りつぶして単色背景を透過に抜く。bg_hex が空なら境界ピクセルの平均色を自動検出。"""
    from PIL import Image
    try:
        import numpy as np
        from scipy import ndimage
        img = Image.open(src).convert("RGBA")
        a = np.array(img)
        if bg_hex:
            r0, g0, b0 = int(bg_hex[0:2], 16), int(bg_hex[2:4], 16), int(bg_hex[4:6], 16)
        else:
            bp = np.concatenate([a[0, :, :3], a[-1, :, :3], a[:, 0, :3], a[:, -1, :3]])
            r0, g0, b0 = int(bp[:, 0].mean()), int(bp[:, 1].mean()), int(bp[:, 2].mean())
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
