#!/usr/bin/env python3
"""
黒猫飯店 常連客・NPC の立ち絵を PixAI (Tsubaki.2) で生成する。
assets/portraits/ に配置。talk_view の立ち絵として使用。

使い方:
    export PIXAI_API_KEY=sk_...
    python3 tools/gen_portraits.py          # 差分のみ生成
    python3 tools/gen_portraits.py --force  # 全枚上書き
    python3 tools/gen_portraits.py --ids tao,nono  # 指定キャラのみ
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

# ── 設定 ─────────────────────────────────────────────────────────
MODEL_ID  = "1983308862240288769"   # Tsubaki.2
WIDTH     = 512
HEIGHT    = 768   # 縦長ポートレート（talk_view の立ち絵は下揃え）
STEPS     = 25
CFG       = 7
API_URL   = "https://api.pixai.art/graphql"
POLL_SEC  = 5
TIMEOUT   = 420

OUT_DIR = Path(__file__).parent.parent / "assets/portraits"

# ── 共通ネガティブ ────────────────────────────────────────────────
NEG = (
    "lowres, bad anatomy, bad hands, extra fingers, extra limbs, "
    "worst quality, low quality, blurry, deformed face, "
    "chibi, super deformed, multiple people, watermark, text"
)

# ── キャラクター定義 ─────────────────────────────────────────────
# (ファイル名, ベースプロンプト, シード)
CHARACTERS = {
    "tao": (
        # タオ爺：老齢の中国人薬膳師。白髭・杖・伝統衣装＋サイバーパンクアクセント
        "1man, elderly wise chinese herbalist, "
        "long white beard, kind wrinkled face, warm amber eyes, "
        "traditional chinese robe with faint neon circuit pattern accents, "
        "wooden staff with glowing tip, small gourd medicine bag, "
        "cyberpunk near future, soft warm lantern light, "
        "calm dignified expression, Arknights style, "
        "full body standing, front facing, "
        "masterpiece, best quality, anime style, clean lineart, "
        "flat dark purple background",
        5001,
    ),
    "nono": (
        # ノノ：小柄なハッカー見習い少女。丸眼鏡・データ紋様・シアン系
        "1girl, small petite hacker girl, "
        "short teal cyan hair, round thick-rimmed glasses, "
        "big curious cyan eyes, freckles, "
        "white hoodie with data stream patterns printed, "
        "oversized jacket, cargo pants, sneakers, "
        "holographic tablet floating beside her, "
        "cyberpunk near future, bright screen glow, "
        "cheerful curious expression, Arknights style, "
        "full body standing, front facing, "
        "masterpiece, best quality, anime style, clean lineart, "
        "flat dark purple background",
        5002,
    ),
    "err404": (
        # 404さん：正体不明の常連。グリッチ・モノクローム・顔が一部曇る
        "1person, androgynous mysterious regular customer, "
        "ash grey short hair, pale grey eyes, "
        "plain dark monochrome hoodie with glitch error text print, "
        "digital corruption artifact pattern on sleeve, "
        "expressionless distant gaze, face slightly obscured by static, "
        "cyberpunk near future, monochrome pale look, "
        "Arknights style, anime style, clean lineart, "
        "full body standing, front facing, "
        "masterpiece, best quality, "
        "flat dark purple background",
        5003,
    ),
    "doctor": (
        # ドクター：精神外科医・店主。長い深緑の髪、グレーの目、白衣、黒タートルネック
        "1man, handsome male doctor, "
        "long dark green hair, gray eyes, cold expression, "
        "white oversized lab coat, black turtleneck, neck tattoo, "
        "slim tall body, futuristic psychiatrist, "
        "cyberpunk near future, holographic brain scan, green particles, "
        "calm dignified expression, Arknights style, "
        "full body standing, front facing, "
        "masterpiece, best quality, anime style, clean lineart, "
        "flat dark purple background",
        6001,
    ),
    "nurse": (
        # ナース：医療支援AI。ミントグリーンの髪、白いナースドレス、機械の脚
        "1girl, female android nurse, "
        "mint green hair, green eyes, "
        "white nurse dress with green accents, mechanical legs, medical IV bag, "
        "gentle smile, cybernetic body, medical support android, "
        "cyberpunk near future, healing particles, "
        "Arknights style, "
        "full body standing, front facing, "
        "masterpiece, best quality, anime style, clean lineart, "
        "flat dark purple background",
        7001,
    ),
}

# ── API helpers（gen_face_*.py と同じ）────────────────────────────
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


def create_task(api_key, prompt, seed):
    params = {
        "modelId": MODEL_ID,
        "prompts": prompt,
        "negativePrompts": NEG,
        "samplingSteps": STEPS,
        "samplingMethod": "dpmpp_2m_karras",
        "cfgScale": CFG,
        "width": WIDTH,
        "height": HEIGHT,
        "seed": seed,
    }
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


def download(url: str, dest: Path):
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "gen_portraits/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        dest.write_bytes(r.read())


def key_background(src: Path, dst: Path, tol: int = 30):
    """縁から flood-fill して単色背景を透過に抜く。"""
    try:
        from PIL import Image
        import numpy as np
        from scipy import ndimage
        img = Image.open(src).convert("RGBA")
        a = np.array(img)
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
        from PIL import Image
        Image.open(src).convert("RGBA").save(dst)
        print("saved(no-scipy)", end=" ")


# ── main ────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true", help="既存ファイルも上書き")
    parser.add_argument("--ids",   help="カンマ区切りキャラID (例: tao,nono)")
    args = parser.parse_args()

    targets = {k: v for k, v in CHARACTERS.items()
               if args.ids is None or k in args.ids.split(",")}

    api_key = load_api_key()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    TMP_DIR = Path(__file__).parent / "_out/portrait_raw"
    TMP_DIR.mkdir(parents=True, exist_ok=True)

    total = len(targets)
    for idx, (name, (prompt, seed)) in enumerate(targets.items(), 1):
        dst = OUT_DIR / f"{name}.png"
        if dst.exists() and not args.force:
            print(f"[{idx}/{total}] {name} → skip (exists)")
            continue

        print(f"[{idx}/{total}] {name} ... ", end="", flush=True)
        tmp = TMP_DIR / f"{name}_raw.png"
        try:
            task_id = create_task(api_key, prompt, seed)
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
