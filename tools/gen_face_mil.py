#!/usr/bin/env python3
"""
ミルの表情シートを PixAI (Tsubaki.2) で一括生成する。
assets/generated/face/mil/ に直接配置。

使い方:
    export PIXAI_API_KEY=sk_...  # または .env に記入
    python3 tools/gen_face_mil.py [--force]   # --force で既存ファイルも上書き

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

OUT_DIR   = Path(__file__).parent.parent / "assets/generated/face/mil"
TMP_DIR   = Path(__file__).parent / "_out/face_mil_raw"
REF_IMAGE = Path(__file__).parent.parent / "docs/Refs/Chara/Milu.png"

# ── プロンプト定義 ───────────────────────────────────────────────
# ミル：ネットランナー・ハッカー。ショートシルバー髪＋ピンクインナーカラー、
#        琥珀色の瞳、黒レザージャケット＋ピンククロップトップ。サイバーパンク。
BASE = (
    "1girl, chibi, super deformed, 2 head tall, thick black outline, "
    "flat color shading, front facing bust portrait, "
    "short silver hair, pink inner hair, amber eyes, "
    "oversized black leather jacket, pink crop top, "
    "cyberpunk hacker girl, street fashion, Arknights style, "
    "anime style, simple shading, "
    "flat single color background #1a1030"
)
NEG = (
    "lowres, bad anatomy, bad hands, extra fingers, extra limbs, "
    "worst quality, low quality, blurry, deformed face, "
    "multiple girls, side view, back view, 3d, warm colors"
)

# (ファイル名, プロンプト追加, シード)
VARIANTS = [
    # ── neutral ──────────────────────────────────────────────────
    ("neutral_closed", "neutral calm expression, mouth closed, eyes open, composed", 2101),
    ("neutral_half",   "neutral calm expression, mouth slightly open, speaking softly, eyes open", 2102),
    ("neutral_open",   "neutral calm expression, mouth open, talking, vowel sound, eyes open", 2103),
    ("neutral_blink",  "neutral calm expression, mouth closed, eyes closed blinking gently", 2104),
    # ── smile ────────────────────────────────────────────────────
    ("smile_closed",   "rare gentle smile, softly curved lips closed, warm eyes", 2201),
    ("smile_half",     "rare gentle smile, mouth slightly open, quiet laugh", 2202),
    ("smile_open",     "rare genuine smile, mouth open with soft laugh", 2203),
    ("smile_blink",    "rare gentle smile, eyes closed softly, content expression", 2204),
    # ── surprise ──────────────────────────────────────────────────
    ("surprise_closed","surprised expression, wide glowing ice blue eyes, mouth closed, shocked", 2301),
    ("surprise_half",  "surprised expression, wide eyes, mouth slightly open, startled", 2302),
    ("surprise_open",  "surprised expression, wide eyes, mouth open wide, gasping", 2303),
    ("surprise_blink", "surprised expression, eyes shut tight suddenly, flinching", 2304),
    # ── calm ──────────────────────────────────────────────────────
    ("calm_closed",    "focused determined expression, sharp eyes, mouth closed, resolute", 2401),
    ("calm_half",      "focused determined expression, mouth slightly open, ready", 2402),
    ("calm_open",      "focused determined expression, mouth open speaking precisely", 2403),
    ("calm_blink",     "focused calm expression, eyes closed briefly, centered", 2404),
    # ── eat ───────────────────────────────────────────────────────
    ("eat_closed",     "eating food, chewing carefully, mouth closed, slight satisfaction", 2501),
    ("eat_half",       "eating food, mouth slightly open, savoring flavor", 2502),
    ("eat_open",       "eating food, mouth open taking a precise bite", 2503),
    ("eat_blink",      "eating food, eyes closed in quiet delight, almost smiling", 2511),
]

# ── リファレンス画像 ──────────────────────────────────────────────
def load_ref_base64(path: Path, max_px: int = 512) -> str | None:
    """参照画像を JPEG base64 に変換して返す。PIL がなければ None。"""
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


# ── API helpers（gen_face_yuzuki.py と同じ）──────────────────────
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
    req = urllib.request.Request(url, headers={"User-Agent": "gen_face_mil/1.0"})
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
