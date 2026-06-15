#!/usr/bin/env python3
"""
tools/pixellab_gen.py — PixelLab API (v2) アセット一括生成

Usage:
  # 表情フレーム生成（yuzuki / kiriko_npc など）
  python3 tools/pixellab_gen.py face yuzuki
  python3 tools/pixellab_gen.py face kiriko_npc

  # 戦闘スプライト生成（walk_front / walk_back / attack）
  python3 tools/pixellab_gen.py sprites kiriko
  python3 tools/pixellab_gen.py sprites mil
  python3 tools/pixellab_gen.py sprites muu

  # クリーンな探索背景
  python3 tools/pixellab_gen.py bg

  # 欠けているアセットを全て生成
  python3 tools/pixellab_gen.py all

  # 残高確認
  python3 tools/pixellab_gen.py balance

APIキー設定:
  export PIXELLAB_API_KEY=...
  または .env に  PIXELLAB_API_KEY=...

出力先（置くだけでGodotが自動採用）:
  assets/generated/face/<id>/<expr>_<state>.png
  assets/generated/sprites/<id>/<anim>.png
  assets/art/explore_bg.png
"""

import argparse
import base64
import io
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False
    print("⚠ Pillow 未インストール。スプライトシート合成・スケーリングが無効。")
    print("  pip install Pillow  で解決できます。\n")

# ─────────────────────────────────────────────
# 定数
# ─────────────────────────────────────────────

BASE_URL        = "https://api.pixellab.ai/v2"
POLL_INTERVAL   = 4       # 秒
POLL_TIMEOUT    = 600     # 10分
REPO_ROOT       = Path(__file__).parent.parent

# ─────────────────────────────────────────────
# キャラクター定義
# ─────────────────────────────────────────────

CHARACTERS = {
    "yuzuki": {
        "name": "ユズキ",
        "desc": (
            "anime girl, short warm orange hair, white chef uniform, cheerful chef, "
            "ramen shop cook, expressive face, bust portrait"
        ),
        "accent": "#E6A15A",
        "portrait": "assets/portraits/yuzuki.png",
        "ref_chara": "docs/Refs/Chara/yuzuki.png",
        "sprite_hint": "64x64 pixel art RPG sprite, anime chef girl, orange hair, front-facing",
    },
    "mil": {
        "name": "ミル",
        "desc": (
            "chibi SD anime girl, short white silver hair with pink inner color highlights, "
            "oversized black jacket, pink crop top, no glasses, "
            "stoic dark heroine, pink reddish eyes, "
            "big head small body, cute chibi proportions, bust portrait"
        ),
        "accent": "#69D2FF",
        "portrait": "assets/portraits/mil.png",
        "ref_chara": "docs/Refs/Chara/Milu.png",
        "sprite_hint": "64x64 pixel art RPG sprite, anime girl, short white silver hair pink inner color, black jacket, front-facing",
    },
    "muu": {
        "name": "ムュウ",
        "desc": (
            "anime girl, pink magenta twin tails, idol streamer outfit, bright energetic, "
            "virtual streamer vtuber, cute, bust portrait"
        ),
        "accent": "#FF88CC",
        "portrait": "assets/portraits/muu.png",
        "ref_chara": "docs/Refs/Chara/myu.png",
        "sprite_hint": "64x64 pixel art RPG sprite, anime idol girl, pink twin tails, front-facing",
    },
    "kiriko": {
        "name": "レイカ",
        "desc": (
            "anime girl, long purple hair, white lab coat, occult scientist, mysterious elegant, "
            "purple glowing accessories, bust portrait"
        ),
        "accent": "#8E6BC7",
        "portrait": "assets/portraits/kiriko.png",
        "ref_chara": "docs/Refs/Chara/reika.png",
        "sprite_hint": "64x64 pixel art RPG sprite, anime scientist girl, purple hair, front-facing",
    },
    "kiriko_npc": {
        "name": "キリコ",
        "desc": (
            "anime girl, short light purple hair, casual modern outfit, friendly client NPC, "
            "soft expression, bust portrait"
        ),
        "accent": "#C0A8D8",
        "portrait": "assets/portraits/kiriko_npc.png",
        "ref_chara": None,
        "sprite_hint": "64x64 pixel art RPG sprite, anime casual girl, light purple hair, front-facing",
    },
}

# 表情×状態 プロンプト
EXPR_PROMPTS = {
    "neutral":  "neutral relaxed expression, calm default face",
    "smile":    "smiling happily, confident bright expression",
    "surprise": "surprised shocked, wide eyes, open mouth gasp",
    "calm":     "serene focused calm, eyes gently closed or half-lidded",
    "eat":      "eating food, chewing satisfied, cheeks slightly puffed",
}
STATE_PROMPTS = {
    "closed": "mouth completely closed, eyes fully open",
    "half":   "mouth slightly open, teeth barely visible, eyes open",
    "open":   "mouth fully open wide, eyes open",
    "blink":  "eyes completely closed blinking, mouth closed",
}

# スプライト アニメ定義
SPRITE_ANIMS = {
    "walk_front": {
        "action": "character walking toward the camera, forward march cycle, 4 frames",
        "frame_count": 4,
    },
    "walk_back": {
        "action": "character walking away from the camera, back walk cycle, 4 frames",
        "frame_count": 4,
    },
    "attack": {
        "action": "character performing a forward slash attack, swinging weapon, 4 frames",
        "frame_count": 4,
    },
}

# ─────────────────────────────────────────────
# API クライアント
# ─────────────────────────────────────────────

def load_api_key() -> str:
    key = os.getenv("PIXELLAB_API_KEY", "")
    if not key:
        env_path = REPO_ROOT / ".env"
        if env_path.exists():
            for raw in env_path.read_text(encoding="utf-8").splitlines():
                line = raw.strip()
                if line.startswith("PIXELLAB_API_KEY="):
                    key = line.split("=", 1)[1].strip().strip('"').strip("'")
                    break
    if not key:
        sys.exit(
            "ERROR: PIXELLAB_API_KEY が見つかりません。\n"
            "  export PIXELLAB_API_KEY=...  または .env に記入してください。\n"
            "  APIキーは https://pixellab.ai/account から取得できます。"
        )
    return key


def api_request(key: str, method: str, path: str, body: dict | None = None) -> dict:
    url  = BASE_URL + path
    data = json.dumps(body).encode("utf-8") if body else None
    req  = urllib.request.Request(
        url, data=data, method=method,
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type":  "application/json",
            "Accept":        "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body_text = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {e.code} {e.reason}: {body_text[:500]}") from e


def poll_job(key: str, job_id: str) -> dict:
    """ジョブが完了するまでポーリングし last_response を返す"""
    deadline = time.time() + POLL_TIMEOUT
    while time.time() < deadline:
        result = api_request(key, "GET", f"/background-jobs/{job_id}")
        status = result.get("status", "unknown")
        print(f"    [{job_id[:8]}…] {status}", flush=True)
        if status == "completed":
            return result.get("last_response", {})
        if status in ("failed", "canceled", "error"):
            raise RuntimeError(f"Job {job_id} failed: {result}")
        time.sleep(POLL_INTERVAL)
    raise TimeoutError(f"Job {job_id} timed out after {POLL_TIMEOUT}s")


# ─────────────────────────────────────────────
# ヘルパー
# ─────────────────────────────────────────────

def img_to_b64(path: Path | None) -> str | None:
    """PNG → base64文字列（ファイルが無ければ None）"""
    if path is None or not path.exists():
        return None
    raw = path.read_bytes()
    return base64.b64encode(raw).decode("ascii")


def b64_to_img(b64str: str) -> "Image.Image":
    """base64文字列 → PIL Image（data:... プレフィックスも可）"""
    if not HAS_PIL:
        raise RuntimeError("Pillow が必要です: pip install Pillow")
    if b64str.startswith("data:"):
        b64str = b64str.split(",", 1)[1]
    raw = base64.b64decode(b64str)
    return Image.open(io.BytesIO(raw)).convert("RGBA")


def save_png(img: "Image.Image", dest: Path):
    dest.parent.mkdir(parents=True, exist_ok=True)
    img.save(str(dest), "PNG")
    print(f"    ✓ saved → {dest.relative_to(REPO_ROOT)}", flush=True)


def save_b64_png(b64str: str, dest: Path):
    """base64 → PNG ファイルへ保存（Pillow なしでも動く）"""
    if b64str.startswith("data:"):
        b64str = b64str.split(",", 1)[1]
    raw = base64.b64decode(b64str)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(raw)
    print(f"    ✓ saved → {dest.relative_to(REPO_ROOT)}", flush=True)


def make_sprite_sheet(frames: list["Image.Image"], frame_w: int, frame_h: int) -> "Image.Image":
    """フレームリスト → 横並び1枚のスプライトシート"""
    sheet = Image.new("RGBA", (frame_w * len(frames), frame_h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        f_resized = f.resize((frame_w, frame_h), Image.NEAREST) if f.size != (frame_w, frame_h) else f
        sheet.paste(f_resized, (i * frame_w, 0), f_resized)
    return sheet


# ─────────────────────────────────────────────
# 残高確認
# ─────────────────────────────────────────────

def cmd_balance(key: str, _args):
    result = api_request(key, "GET", "/balance")
    print(f"残高: {result}")


# ─────────────────────────────────────────────
# 顔表情フレーム生成
# ─────────────────────────────────────────────

def generate_face_frame(
    key: str,
    char_id: str,
    expr: str,
    state: str,
    ref_b64: str | None,
    ref_size: tuple[int, int] | None,
    dest: Path,
    dry_run: bool = False,
) -> bool:
    if dest.exists():
        print(f"    skip (exists): {dest.relative_to(REPO_ROOT)}")
        return True

    desc = (
        f"{CHARACTERS[char_id]['desc']}, "
        f"{EXPR_PROMPTS[expr]}, {STATE_PROMPTS[state]}, "
        "flat solid background #1a1030, centered composition, "
        "consistent head position, pixel art style anime portrait, "
        "same hairstyle clothing every frame"
    )

    if dry_run:
        print(f"    [dry] {expr}_{state}: {desc[:80]}…")
        return True

    print(f"  generate-image-v2: {expr}_{state}", flush=True)

    body: dict = {
        "description": desc,
        "image_size":  {"width": 256, "height": 256},
    }

    if ref_b64 and ref_size:
        body["reference_images"] = [
            {"image": {"base64": ref_b64},
             "size": {"width": ref_size[0], "height": ref_size[1]}}
        ]

    try:
        result = api_request(key, "POST", "/generate-image-v2", body)
        job_id = result.get("background_job_id") or result.get("id")
        if job_id:
            response = poll_job(key, job_id)
        else:
            response = result  # 同期レスポンスの場合

        images = response.get("images", [])
        if not images:
            raise RuntimeError(f"No images in response: {response}")

        img_data = images[0]
        b64 = img_data.get("base64") or img_data.get("url", "")
        save_b64_png(b64, dest)
        return True

    except RuntimeError as e:
        err = str(e)
        if "402" in err or "403" in err or "Pro" in err.lower():
            print(f"    ⚠ generate-image-v2 は Pro tier が必要です。pixflux にフォールバック…")
            return generate_face_frame_pixflux(key, char_id, expr, state, dest)
        raise


def generate_face_frame_pixflux(
    key: str,
    char_id: str,
    expr: str,
    state: str,
    dest: Path,
) -> bool:
    """generate-image-v2 が使えない場合の pixflux フォールバック"""
    desc = (
        f"{CHARACTERS[char_id]['desc']}, "
        f"{EXPR_PROMPTS[expr]}, {STATE_PROMPTS[state]}, "
        "flat solid dark background, centered, pixel art anime portrait"
    )

    print(f"  create-image-pixflux (fallback): {expr}_{state}", flush=True)

    body = {
        "description":    desc,
        "image_size":     {"width": 256, "height": 256},
        "no_background":  False,
    }

    try:
        result = api_request(key, "POST", "/create-image-pixflux", body)
    except RuntimeError as e:
        err = str(e)
        if "400" in err or "max" in err.lower():
            # pixflux max is 400x400, try smaller
            body["image_size"] = {"width": 128, "height": 128}
            result = api_request(key, "POST", "/create-image-pixflux", body)
        else:
            raise

    img_obj = result.get("image", {})
    b64 = img_obj.get("base64") or img_obj.get("url", "")
    if not b64:
        raise RuntimeError(f"No image in pixflux response: {result}")

    if HAS_PIL:
        img = b64_to_img(b64)
        img_256 = img.resize((256, 256), Image.NEAREST)
        save_png(img_256, dest)
    else:
        save_b64_png(b64, dest)

    return True


def cmd_face(key: str, args):
    char_id  = args.char_id
    dry_run  = getattr(args, "dry_run", False)
    exprs    = (args.exprs.split(",") if getattr(args, "exprs", None)
                else list(EXPR_PROMPTS.keys()))
    states   = (args.states.split(",") if getattr(args, "states", None)
                else list(STATE_PROMPTS.keys()))

    if char_id not in CHARACTERS:
        sys.exit(f"ERROR: 未知のキャラID '{char_id}'。選択肢: {list(CHARACTERS)}")

    char = CHARACTERS[char_id]
    print(f"\n▶ 表情フレーム生成: {char_id} ({char['name']})")
    print(f"  表情: {exprs}")
    print(f"  状態: {states}")

    # リファレンス画像を読み込む
    ref_b64  = None
    ref_size = None
    ref_path = REPO_ROOT / char["ref_chara"] if char.get("ref_chara") else None
    if ref_path is None or not ref_path.exists():
        ref_path = REPO_ROOT / char["portrait"]

    if ref_path.exists():
        if HAS_PIL:
            with Image.open(str(ref_path)) as im:
                w, h = im.size
                max_px = 512
                if max(w, h) > max_px:
                    scale = max_px / max(w, h)
                    im = im.resize((int(w * scale), int(h * scale)), Image.LANCZOS)
                buf = io.BytesIO()
                im.convert("RGBA").save(buf, "PNG")
                ref_b64 = base64.b64encode(buf.getvalue()).decode("ascii")
                ref_size = im.size
        else:
            ref_b64 = img_to_b64(ref_path)
            ref_size = (512, 512)  # 仮
        print(f"  参照画像: {ref_path.relative_to(REPO_ROOT)} → {ref_size}")
    else:
        print(f"  ⚠ 参照画像なし（テキストのみで生成）")

    ok = 0
    fail = 0
    total = len(exprs) * len(states)

    for expr in exprs:
        for state in states:
            dest = REPO_ROOT / f"assets/generated/face/{char_id}/{expr}_{state}.png"
            try:
                if generate_face_frame(key, char_id, expr, state,
                                       ref_b64, ref_size, dest, dry_run):
                    ok += 1
                else:
                    fail += 1
            except Exception as e:
                print(f"    ✗ ERROR {expr}_{state}: {e}", flush=True)
                fail += 1

    print(f"\n  完了: {ok}/{total} 成功, {fail} 失敗")


# ─────────────────────────────────────────────
# 戦闘スプライト生成
# ─────────────────────────────────────────────

def _pick_ref_for_sprite(char_id: str, max_px: int = 256) -> str | None:
    """
    スプライト生成用リファレンス画像を選ぶ。
    優先順: docs/Refs/Chara/<ref_chara> > assets/portraits/<id>.png
    大きい画像は max_px に収まるよう縮小してから base64 化する。
    """
    char = CHARACTERS[char_id]
    candidates = []
    if char.get("ref_chara"):
        candidates.append(REPO_ROOT / char["ref_chara"])
    candidates.append(REPO_ROOT / char["portrait"])

    for p in candidates:
        if not p.exists():
            continue
        if not HAS_PIL:
            return img_to_b64(p)
        with Image.open(str(p)) as im:
            w, h = im.size
            if max(w, h) > max_px:
                scale = max_px / max(w, h)
                im = im.resize((int(w * scale), int(h * scale)), Image.LANCZOS)
            buf = io.BytesIO()
            im.convert("RGBA").save(buf, "PNG")
            return base64.b64encode(buf.getvalue()).decode("ascii")
    return None


def generate_base_sprite(key: str, char_id: str) -> "Image.Image | None":
    """create-character-v3 でベーススプライト（南向き 64x64）を生成"""
    char    = CHARACTERS[char_id]
    desc    = char["sprite_hint"]
    ref_b64 = _pick_ref_for_sprite(char_id)

    print(f"  create-character-v3: {char_id} (ref={'yes' if ref_b64 else 'none'})", flush=True)

    body: dict = {
        "description": desc,
        "image_size":  {"width": 64, "height": 64},
    }
    if ref_b64:
        body["reference_image"] = {"base64": ref_b64}

    result   = api_request(key, "POST", "/create-character-v3", body)
    job_id   = result.get("background_job_id") or result.get("id")
    response = poll_job(key, job_id)

    # create-character-v3 は storage_urls dict (direction→URL) で返す
    urls = response.get("storage_urls", {})
    south_url = urls.get("south") or urls.get("south-east") or next(iter(urls.values()), None)
    if not south_url:
        # フォールバック: images[] から base64 を取得（旧形式）
        images = response.get("images", [])
        if not images:
            raise RuntimeError(f"No images/storage_urls in character response: {response}")
        return b64_to_img(images[0].get("base64", ""))

    # URL から画像をダウンロード
    print(f"    downloading south sprite…", flush=True)
    req = urllib.request.Request(south_url, headers={"User-Agent": "pixellab_gen/1.0"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        raw = resp.read()
    return Image.open(io.BytesIO(raw)).convert("RGBA")


def generate_animation(
    key: str,
    base_img: "Image.Image",
    action: str,
    frame_count: int,
) -> list["Image.Image"]:
    """animate-with-text-v3 でアニメフレームを生成"""
    buf = io.BytesIO()
    base_img.save(buf, "PNG")
    first_b64 = base64.b64encode(buf.getvalue()).decode("ascii")

    print(f"  animate-with-text-v3: {action[:60]}", flush=True)

    body = {
        "first_frame": {"type": "base64", "base64": first_b64},
        "action":      action,
        "frame_count": frame_count,
    }

    result  = api_request(key, "POST", "/animate-with-text-v3", body)
    job_id  = result.get("background_job_id") or result.get("id")
    response = poll_job(key, job_id)

    images = response.get("images", [])
    if not images:
        raise RuntimeError(f"No images in animation response: {response}")

    return [b64_to_img(img.get("base64", "")) for img in images]


def cmd_sprites(key: str, args):
    char_id = args.char_id
    anims   = (args.anims.split(",") if getattr(args, "anims", None)
               else list(SPRITE_ANIMS.keys()))

    if char_id not in CHARACTERS:
        sys.exit(f"ERROR: 未知のキャラID '{char_id}'")

    if not HAS_PIL:
        sys.exit("ERROR: スプライト生成には Pillow が必要です: pip install Pillow")

    print(f"\n▶ 戦闘スプライト生成: {char_id}")
    print(f"  アニメ: {anims}")

    # ベーススプライト取得
    # walk_front を再生成 or 初回生成 → create-character-v3（Refs/Chara リファレンス使用）
    # それ以外 → 既存 walk_front の先頭フレームを 64x64 に縮小して流用
    base_path = REPO_ROOT / f"assets/generated/sprites/{char_id}/walk_front.png"
    needs_new_base = "walk_front" in anims or not base_path.exists()

    if needs_new_base:
        print(f"  ベーススプライト生成中… (Refs/Chara リファレンス使用)")
        base_img = generate_base_sprite(key, char_id)
        if base_img is None:
            sys.exit("ERROR: ベーススプライト生成失敗")
    else:
        print(f"  既存スプライトをベースとして読み込み: {base_path.relative_to(REPO_ROOT)}")
        base_img = Image.open(str(base_path)).convert("RGBA")
        w, h = base_img.size
        frame_w = w // 4 if w > h else w
        base_img = base_img.crop((0, 0, frame_w, h))
        # animate-with-text-v3 の上限は256x256
        base_img = base_img.resize((64, 64), Image.NEAREST)

    frame_w = frame_h = 64

    force = getattr(args, "force", False)

    for anim_name in anims:
        dest = REPO_ROOT / f"assets/generated/sprites/{char_id}/{anim_name}.png"
        if dest.exists() and not force:
            print(f"  skip (exists): {anim_name}.png")
            continue

        anim_def = SPRITE_ANIMS[anim_name]
        print(f"\n  アニメ '{anim_name}':")

        try:
            frames = generate_animation(
                key, base_img,
                anim_def["action"],
                anim_def["frame_count"],
            )
            sheet = make_sprite_sheet(frames, frame_w, frame_h)
            save_png(sheet, dest)
        except Exception as e:
            print(f"    ✗ ERROR {anim_name}: {e}", flush=True)


# ─────────────────────────────────────────────
# 探索背景生成
# ─────────────────────────────────────────────

def cmd_bg(key: str, args):
    dest = REPO_ROOT / "assets/art/explore_bg.png"

    if dest.exists() and not getattr(args, "force", False):
        print(f"✓ 既存ファイルがあります: {dest.relative_to(REPO_ROOT)}")
        print("  上書きするには --force を指定してください。")
        return

    # 生成サイズ: pixflux max 400x400
    # ゲームの比率 ~853x1844 ≈ 1:2.16 → 190x410 に近い値 → 4x スケール
    gen_w, gen_h = 213, 460
    scale = 4

    desc = (
        "cyberpunk ruins alley, neon-lit dark street, purple and cyan neon signs, "
        "rainy atmosphere, glowing reflections on wet pavement, "
        "abandoned storefronts, overgrown vines, "
        "NO characters NO people NO UI elements NO text overlays, "
        "vertical portrait composition, deep perspective, pixel art style"
    )

    print(f"\n▶ 探索背景生成")
    print(f"  生成サイズ: {gen_w}x{gen_h} → {gen_w*scale}x{gen_h*scale} ({scale}x スケール)")

    body = {
        "description": desc,
        "image_size":  {"width": gen_w, "height": gen_h},
    }

    try:
        # まず同期 pixflux を試す
        print("  create-image-pixflux…", flush=True)
        result = api_request(key, "POST", "/create-image-pixflux", body)

        img_obj = result.get("image", {})
        b64 = img_obj.get("base64") or img_obj.get("url", "")

        if not b64:
            raise RuntimeError(f"No image in pixflux response: {result}")

        if HAS_PIL:
            img = b64_to_img(b64)
            img_scaled = img.resize((gen_w * scale, gen_h * scale), Image.NEAREST)
            save_png(img_scaled, dest)
        else:
            save_b64_png(b64, dest)
            print(f"    ⚠ Pillow なしのためスケーリング未実施 ({gen_w}x{gen_h})")

    except RuntimeError as e:
        err = str(e)
        # pixflux-background (async) にフォールバック
        if "background_job_id" in err or True:
            print("  create-image-pixflux-background (async)…", flush=True)
            try:
                result = api_request(key, "POST", "/create-image-pixflux-background", body)
                job_id = result.get("background_job_id") or result.get("id")
                response = poll_job(key, job_id)

                img_obj = response.get("image", {})
                b64 = img_obj.get("base64") or img_obj.get("url", "")

                if HAS_PIL:
                    img = b64_to_img(b64)
                    img_scaled = img.resize((gen_w * scale, gen_h * scale), Image.NEAREST)
                    save_png(img_scaled, dest)
                else:
                    save_b64_png(b64, dest)
            except Exception as e2:
                print(f"  ✗ 背景生成失敗: {e2}")
                raise


# ─────────────────────────────────────────────
# パララックス背景レイヤー生成
# ─────────────────────────────────────────────

# bg レイヤー定義（ゲームの parallax scroll 3層）
BG_LAYERS = {
    "city_far": {
        "desc": (
            "cyberpunk distant city skyline at night, "
            "purple and cyan neon glow, dark silhouette skyscrapers, "
            "rainy foggy atmosphere, glowing windows, NO characters, "
            "wide panoramic pixel art, dark moody"
        ),
        "target_w": 720, "target_h": 300,
    },
    "city_mid": {
        "desc": (
            "cyberpunk mid-ground ruined storefronts, "
            "neon signs in Japanese, wet reflective pavement, "
            "overgrown vines on concrete walls, broken fences, "
            "purple cyan orange neon, NO characters NO people, "
            "wide panoramic pixel art, sidescroller bg"
        ),
        "target_w": 720, "target_h": 260,
    },
    "interior": {
        "desc": (
            "cozy japanese ramen shop interior at night, "
            "warm lantern light, wooden counter seats, "
            "steam from pots, hanging paper menus, noren curtain, "
            "small cozy noodle restaurant, NO people NO characters, "
            "wide panoramic pixel art, warm amber tones"
        ),
        "target_w": 720, "target_h": 200,
    },
}


def cmd_bgs(key: str, args):
    """assets/generated/bg/ の parallax レイヤー3枚を生成"""
    force = getattr(args, "force", False)
    print(f"\n▶ パララックス背景レイヤー生成")

    ok = fail = 0
    for name, cfg in BG_LAYERS.items():
        dest = REPO_ROOT / f"assets/generated/bg/{name}.png"
        if dest.exists() and not force:
            print(f"  skip (exists): {name}.png")
            ok += 1
            continue

        tw, th = cfg["target_w"], cfg["target_h"]
        # pixflux max 400x400: 720/2=360, keep ratio
        gen_w = min(360, 400)
        gen_h = max(32, int(gen_w * th / tw))
        scale_x = tw / gen_w
        scale_y = th / gen_h

        print(f"  pixflux: {name}.png ({gen_w}x{gen_h} → {tw}x{th}) …", flush=True)

        body = {
            "description": cfg["desc"],
            "image_size":  {"width": gen_w, "height": gen_h},
        }

        try:
            result = api_request(key, "POST", "/create-image-pixflux", body)
            img_obj = result.get("image", {})
            b64 = img_obj.get("base64") or img_obj.get("url", "")
        except RuntimeError as e:
            # 非同期フォールバック
            print(f"    sync failed ({e}), trying async…", flush=True)
            try:
                result2 = api_request(key, "POST", "/create-image-pixflux-background", body)
                job_id  = result2.get("background_job_id") or result2.get("id")
                response = poll_job(key, job_id)
                img_obj = response.get("image", {})
                b64 = img_obj.get("base64") or img_obj.get("url", "")
            except Exception as e2:
                print(f"    ✗ {name}: {e2}", flush=True)
                fail += 1
                continue

        if not b64:
            print(f"    ✗ {name}: no image in response")
            fail += 1
            continue

        if HAS_PIL:
            img = b64_to_img(b64)
            img_scaled = img.resize((tw, th), Image.NEAREST)
            save_png(img_scaled, dest)
        else:
            save_b64_png(b64, dest)
            print(f"    ⚠ Pillow なし: {gen_w}x{gen_h} のまま保存")
        ok += 1

    print(f"\n  完了: {ok}/{len(BG_LAYERS)} 成功, {fail} 失敗")


# ─────────────────────────────────────────────
# シナリオ背景（会話シーン用・縦長ポートレート）
# ─────────────────────────────────────────────

# 縦長ポートレート 384×680 → LANCZOS 2x → 768×1360
# （pixflux max 400px, 比率9:16に近い値）
SCENE_BGS = {
    "restaurant": {
        "desc": (
            "cozy cyberpunk ramen shop interior at night, "
            "wooden counter bar seats, warm lantern amber light, "
            "steam rising from pots, noren fabric curtain doorway, "
            "paper menu boards with kanji, rain on the window glass, "
            "small intimate Japanese noodle restaurant, "
            "NO people NO characters, "
            "moody atmospheric, soft warm glow, pixel art style"
        ),
        "gen_w": 216, "gen_h": 384,
        "out_w": 432, "out_h": 768,
    },
    "street": {
        "desc": (
            "cyberpunk rainy alley at night, neon signs in Japanese, "
            "wet reflective stone pavement, purple and cyan neon glow, "
            "vending machines glowing, fire escapes, steam from grates, "
            "overgrown vines on concrete walls, dark moody atmosphere, "
            "NO people NO characters, "
            "near future city backstreet, pixel art style"
        ),
        "gen_w": 216, "gen_h": 384,
        "out_w": 432, "out_h": 768,
    },
    "mental": {
        "desc": (
            "surreal psychological dreamscape inner world, "
            "floating memory fragments shards of glass, "
            "blue purple ethereal fog mist, "
            "distorted impossible architecture ruins, "
            "dim glowing particles drifting upward, "
            "NO characters NO people, "
            "abstract psychological horror atmosphere, "
            "vertical composition, digital glitch, pixel art style"
        ),
        "gen_w": 216, "gen_h": 384,
        "out_w": 432, "out_h": 768,
    },
    "dungeon": {
        "desc": (
            "dark stone dungeon corridor interior, "
            "torchlight flickering on mossy walls, "
            "stone brick arch passage, iron door in distance, "
            "mysterious glowing rune inscriptions, "
            "damp atmospheric underground, NO characters, "
            "fantasy psychological dungeon, pixel art style"
        ),
        "gen_w": 216, "gen_h": 384,
        "out_w": 432, "out_h": 768,
    },
    # ── お店経営画面用（横長・カウンター断面）──
    "shop_interior": {
        "desc": (
            "pixel art izakaya interior viewed from customer side, "
            "wooden bar counter in foreground bottom edge, "
            "staff side visible behind counter: kitchen shelves, wok stove, steaming pots, "
            "sake bottles and jars lined up on wooden shelves, "
            "hanging red paper lanterns overhead, glowing paper menu boards on back wall, "
            "neon signs in kanji purple and amber light, "
            "warm amber and purple neon color palette, "
            "cozy intimate gothic cyberpunk ramen shop atmosphere, "
            "NO people NO characters, NO exterior, interior only, "
            "wide landscape side view cross-section, pixel art 16-bit style"
        ),
        "gen_w": 390, "gen_h": 260,
        "out_w": 390, "out_h": 260,
    },
}


def _gen_bg(key: str, name: str, cfg: dict, force: bool) -> bool:
    """シーン背景1枚を生成してスケーリング保存。成功で True。"""
    dest = REPO_ROOT / f"assets/generated/scene/{name}.png"
    if dest.exists() and not force:
        print(f"  skip (exists): {name}.png")
        return True

    gw, gh = cfg["gen_w"], cfg["gen_h"]
    ow, oh = cfg["out_w"], cfg["out_h"]
    print(f"  pixflux: {name}.png ({gw}x{gh} → {ow}x{oh}) …", flush=True)
    body = {"description": cfg["desc"], "image_size": {"width": gw, "height": gh}}
    b64 = ""
    try:
        result = api_request(key, "POST", "/create-image-pixflux", body)
        img_obj = result.get("image", {})
        b64 = img_obj.get("base64") or img_obj.get("url", "")
    except RuntimeError as e:
        print(f"    sync failed ({e}), trying async…", flush=True)
        result2 = api_request(key, "POST", "/create-image-pixflux-background", body)
        job_id = result2.get("background_job_id") or result2.get("id")
        response = poll_job(key, job_id)
        img_obj = response.get("image", {})
        b64 = img_obj.get("base64") or img_obj.get("url", "")
    if not b64:
        print(f"    ✗ {name}: no image in response")
        return False
    if HAS_PIL:
        img = b64_to_img(b64)
        # LANCZOS でアップスケール（背景は NEAREST でなく滑らかに）
        img_scaled = img.resize((ow, oh), Image.LANCZOS)
        dest.parent.mkdir(parents=True, exist_ok=True)
        save_png(img_scaled, dest)
    else:
        dest.parent.mkdir(parents=True, exist_ok=True)
        save_b64_png(b64, dest)
        print(f"    ⚠ Pillow なし: {gw}x{gh} のまま保存")
    print(f"    ✓ saved → {dest.relative_to(REPO_ROOT)}")
    return True


def cmd_scene_bgs(key: str, args):
    force    = getattr(args, "force", False)
    selected = getattr(args, "ids", None)
    bgs = {k: v for k, v in SCENE_BGS.items()
           if selected is None or k in selected.split(",")}
    print(f"\n▶ シナリオ背景生成: {len(bgs)} 種")
    ok = fail = 0
    for name, cfg in bgs.items():
        try:
            if _gen_bg(key, name, cfg, force):
                ok += 1
            else:
                fail += 1
        except Exception as e:
            print(f"    ✗ {name}: {e}", flush=True)
            fail += 1
    print(f"\n  完了: {ok}/{len(bgs)} 成功, {fail} 失敗")


# ─────────────────────────────────────────────
# アイコン生成（食べ物・素材・箱・装備・FX）
# ─────────────────────────────────────────────

# 食べ物アイコン定義
FOOD_ICONS = {
    "tantan":  "spicy ramen noodles in a bowl with red chili oil and sesame, 担々麺, top view, pixel art icon 64x64",
    "mabo":    "mapo tofu in red spicy sauce in a bowl, chinese dish, 麻婆豆腐, top view, pixel art icon 64x64",
    "suanla":  "hot and sour soup in a bowl with egg and vegetables, 酸辣湯, top view, pixel art icon 64x64",
    "chashu":  "chashu ramen bowl with pork slices and soft boiled egg, 叉焼麺, top view, pixel art icon 64x64",
    "chahan":  "fried rice in a bowl with vegetables and shrimp, 炒飯, top view, pixel art icon 64x64",
    "wantan":  "wonton soup with floating dumplings in clear broth, 雲呑湯, top view, pixel art icon 64x64",
    "okayu":   "jade green rice porridge congee with garnish, 翡翠粥, top view, pixel art icon 64x64",
    "annin":   "almond jelly dessert with cherry on top, chinese sweet, 杏仁豆腐, top view, pixel art icon 64x64",
    "goma":    "sesame dango mochi balls on a plate, japanese sweet, 胡麻団子, top view, pixel art icon 64x64",
    "yakuzen": "medicinal herb hot pot with glowing ingredients, special dish, 薬膳火鍋, top view, pixel art icon 64x64",
    "parfait": "cyberpunk layered parfait with neon-blue jelly and circuit garnish, 電脳パフェ, pixel art icon 64x64",
    "wasure":  "mysterious ghost ramen bowl with fading noodles and glowing broth, 忘れ麺, pixel art icon 64x64",
}

# 素材アイコン定義
INGREDIENT_ICONS = {
    "dry":  "pixel art item icon, bundle of dried noodles and spices, 乾物 dry goods, 32x32",
    "meat": "pixel art item icon, raw pork meat slabs on a plate, 肉 meat ingredient, 32x32",
    "sea":  "pixel art item icon, fresh seafood shrimp and shellfish, 海鮮 seafood, 32x32",
}

# 箱アイコン定義
BOX_ICONS = {
    "0": "pixel art treasure chest, worn wooden box, simple, common, 32x32",
    "1": "pixel art treasure chest, iron metal box, sturdy, uncommon, 32x32",
    "2": "pixel art treasure chest, silver chest with moonlight shimmer, rare, 32x32",
    "3": "pixel art treasure chest, legendary golden chest glowing light, epic, 32x32",
}

# 装備スロットアイコン定義（グレード非依存の汎用アイコン）
EQUIP_ICONS = {
    "weapon":  "pixel art weapon icon, chinese chef cleaver knife, silhouette, dark background, 32x32",
    "armor":   "pixel art armor icon, dark body armor chestplate, silhouette, 32x32",
    "trinket": "pixel art accessory icon, glowing crystal pendant necklace, magical, 32x32",
}

# FXエフェクト定義
FX_ICONS = {
    "heal":        "pixel art healing burst, green sparkle circles expanding, bright, transparent bg, 64x64",
    "sword_hit":   "pixel art sword slash arc white streak, impact stars, transparent bg, 64x64",
    "fire":        "pixel art fire explosion ball, orange red flames burst, transparent bg, 64x64",
    "thunder":     "pixel art lightning bolt strike, yellow electric spark, transparent bg, 64x64",
}

# スキルアイコン定義（12種、data.gd SKILL_DB に対応）
SKILL_ICONS = {
    # mil — ヒール/シールド系（シアン・緑）
    "first_aid": "pixel art skill icon, glowing first aid cross with green healing sparkles, cyan tint, 32x32, dark bg",
    "cover":     "pixel art skill icon, protective shield arms embracing, cyan glow barrier, 32x32, dark bg",
    "sanctum":   "pixel art skill icon, sacred holy barrier dome glowing cyan-green, 32x32, dark bg",
    # yuzuki — 攻撃/爆発系（オレンジ・赤）
    "wok_fist":  "pixel art skill icon, fist punch with wok pan sparks flying orange, 32x32, dark bg",
    "wok_storm": "pixel art skill icon, spinning wok whirlwind orange fiery tornado, 32x32, dark bg",
    "honki":     "pixel art skill icon, powerful glowing orange red fist explosion burst, 32x32, dark bg",
    # muu — 電波/爆発/回復（ピンク・マゼンタ）
    "buzz":      "pixel art skill icon, pink neon words explosion burst viral broadcast, 32x32, dark bg",
    "encore":    "pixel art skill icon, musical note heart swirl pink healing aura, 32x32, dark bg",
    "viral":     "pixel art skill icon, pink magenta ripple wave spreading outward explosion, 32x32, dark bg",
    # kiriko — 雷/射撃（紫・青白）
    "observe":   "pixel art skill icon, crosshair scope targeting reticle purple glow, 32x32, dark bg",
    "hypothesis":"pixel art skill icon, purple lightning bolt hypothesis symbol electric arc, 32x32, dark bg",
    "reconnect": "pixel art skill icon, purple circuit reconnect beam lightning strike star, 32x32, dark bg",
}

# 改装ツリーノードアイコン定義（data.gd RENOV_NODES に対応）
RENOV_NODE_ICONS = {
    "start":      "pixel art node icon, shop key golden ornate, start node, warm glow, 32x32",
    "chest1":     "pixel art node icon, small wooden treasure chest with sparkle, 32x32",
    "chest2":     "pixel art node icon, iron chest box with shimmer, 32x32",
    "chest3":     "pixel art node icon, appraiser magnifying glass over gem, 32x32",
    "gold1":      "pixel art node icon, coin stack small gold pile, 32x32",
    "gold2":      "pixel art node icon, coin stack medium golden, 32x32",
    "gold3":      "pixel art node icon, merchant prestige badge seal gold coins, 32x32",
    "mat1":       "pixel art node icon, ingredient bundle tied herbs vegetables small, 32x32",
    "mat2":       "pixel art node icon, ingredient bundle medium tied herbs, 32x32",
    "mat3":       "pixel art node icon, underground market stall ingredients glowing, 32x32",
    "atk1":       "pixel art node icon, sharpening whetstone blade sparks, 32x32",
    "hp1":        "pixel art node icon, staff meal bowl steaming rice fortification, 32x32",
    "atk2":       "pixel art node icon, blazing flaming blade power ultimate, 32x32",
    "crit1":      "pixel art node icon, bullseye target critical hit mark, 32x32",
    "kitchen":    "pixel art node icon, kitchen expansion pots and pans counter, 32x32",
    "spd1":       "pixel art node icon, running shoes dash speed boots, 32x32",
    "sign1":      "pixel art node icon, neon shop sign glowing lantern, 32x32",
    "clockwork":  "pixel art node icon, gear clockwork mechanical auto mechanism, 32x32",
    "rest":       "pixel art node icon, crescent moon peaceful rest offline income, 32x32",
    "awaken":     "pixel art node icon, awakening eye star burst purple glow, 32x32",
    "sign2":      "pixel art node icon, bigger glowing neon sign expansion, 32x32",
}


# タブバーアイコン定義（ホーム画面フッター 6タブ）
TAB_ICONS = {
    "tab_shop":      "pixel art tab icon, steaming ramen noodle bowl with chopsticks, cozy warm orange glow, cyberpunk noodle shop, 48x48, dark purple background",
    "tab_member":    "pixel art tab icon, two anime chibi character silhouettes side by side, team party, cyan tint, 48x48, dark purple background",
    "tab_memory":    "pixel art tab icon, glowing brain with circuit lines, digital memory gem crystal, purple pink neon glow, 48x48, dark purple background",
    "tab_inventory": "pixel art tab icon, open backpack bag with items inside, inventory storage, warm gold color, 48x48, dark purple background",
    "tab_renov":     "pixel art tab icon, wrench and gear cog upgrade tools crossed, renovation upgrade, mint green glow, 48x48, dark purple background",
    "tab_stats":     "pixel art tab icon, rising bar chart graph statistics, three cyan neon bars ascending, 48x48, dark purple background",
}


def generate_icon(
    key: str,
    description: str,
    dest: Path,
    size: int = 64,
    no_bg: bool = False,
    force: bool = False,
) -> bool:
    """pixflux で小さいアイコンを同期生成"""
    if dest.exists() and not force:
        print(f"    skip (exists): {dest.relative_to(REPO_ROOT)}")
        return True

    print(f"  pixflux: {dest.name} …", flush=True)

    body = {
        "description": description,
        "image_size":  {"width": size, "height": size},
        "no_background": no_bg,
    }

    try:
        result = api_request(key, "POST", "/create-image-pixflux", body)
    except RuntimeError as e:
        # 非同期フォールバック
        if "background_job_id" in str(e) or "timeout" in str(e).lower():
            result2 = api_request(key, "POST", "/create-image-pixflux-background", body)
            job_id  = result2.get("background_job_id") or result2.get("id")
            response = poll_job(key, job_id)
            img_obj = response.get("image", {})
            b64 = img_obj.get("base64") or img_obj.get("url", "")
        else:
            raise
    else:
        img_obj = result.get("image", {})
        b64 = img_obj.get("base64") or img_obj.get("url", "")

    if not b64:
        raise RuntimeError(f"No image in response for {dest.name}")

    if HAS_PIL and no_bg:
        img = b64_to_img(b64)
        save_png(img, dest)
    else:
        save_b64_png(b64, dest)
    return True


def cmd_food(key: str, args):
    force    = getattr(args, "force", False)
    selected = getattr(args, "ids", None)
    icons    = {k: v for k, v in FOOD_ICONS.items()
                if selected is None or k in selected.split(",")}

    print(f"\n▶ 食べ物アイコン生成: {len(icons)} 種")
    ok = fail = 0
    for name, desc in icons.items():
        dest = REPO_ROOT / f"assets/generated/food/{name}.png"
        try:
            if generate_icon(key, desc, dest, size=64, no_bg=False, force=force):
                ok += 1
        except Exception as e:
            print(f"    ✗ {name}: {e}", flush=True)
            fail += 1
    print(f"\n  完了: {ok}/{len(icons)} 成功, {fail} 失敗")


def cmd_items(key: str, args):
    force = getattr(args, "force", False)
    print(f"\n▶ アイテムアイコン生成")

    tasks = []
    for name, desc in INGREDIENT_ICONS.items():
        tasks.append((REPO_ROOT / f"assets/generated/ing/{name}.png", desc, 32, False))
    for grade, desc in BOX_ICONS.items():
        tasks.append((REPO_ROOT / f"assets/generated/box/{grade}.png", desc, 32, False))
    for slot, desc in EQUIP_ICONS.items():
        tasks.append((REPO_ROOT / f"assets/generated/equip/{slot}.png", desc, 32, False))

    ok = fail = 0
    for dest, desc, size, no_bg in tasks:
        try:
            if generate_icon(key, desc, dest, size=size, no_bg=no_bg, force=force):
                ok += 1
        except Exception as e:
            print(f"    ✗ {dest.name}: {e}", flush=True)
            fail += 1
    print(f"\n  完了: {ok}/{len(tasks)} 成功, {fail} 失敗")


def cmd_fx(key: str, args):
    force = getattr(args, "force", False)
    print(f"\n▶ FXエフェクト生成: {len(FX_ICONS)} 種")

    ok = fail = 0
    for name, desc in FX_ICONS.items():
        dest = REPO_ROOT / f"assets/generated/fx/{name}.png"
        try:
            if generate_icon(key, desc, dest, size=64, no_bg=True, force=force):
                ok += 1
        except Exception as e:
            print(f"    ✗ {name}: {e}", flush=True)
            fail += 1
    print(f"\n  完了: {ok}/{len(FX_ICONS)} 成功, {fail} 失敗")


def cmd_skills(key: str, args):
    force    = getattr(args, "force", False)
    selected = getattr(args, "ids", None)
    icons    = {k: v for k, v in SKILL_ICONS.items()
                if selected is None or k in selected.split(",")}

    print(f"\n▶ スキルアイコン生成: {len(icons)} 種")
    ok = fail = 0
    for name, desc in icons.items():
        dest = REPO_ROOT / f"assets/generated/skill/{name}.png"
        try:
            if generate_icon(key, desc, dest, size=32, no_bg=False, force=force):
                ok += 1
        except Exception as e:
            print(f"    ✗ {name}: {e}", flush=True)
            fail += 1
    print(f"\n  完了: {ok}/{len(icons)} 成功, {fail} 失敗")


def cmd_renov(key: str, args):
    force = getattr(args, "force", False)
    print(f"\n▶ 改装ツリーノードアイコン生成: {len(RENOV_NODE_ICONS)} 種")

    ok = fail = 0
    for name, desc in RENOV_NODE_ICONS.items():
        dest = REPO_ROOT / f"assets/generated/renov/{name}.png"
        try:
            if generate_icon(key, desc, dest, size=32, no_bg=False, force=force):
                ok += 1
        except Exception as e:
            print(f"    ✗ {name}: {e}", flush=True)
            fail += 1
    print(f"\n  完了: {ok}/{len(RENOV_NODE_ICONS)} 成功, {fail} 失敗")


def cmd_tabs(key: str, args):
    force = getattr(args, "force", False)
    print(f"\n▶ タブバーアイコン生成: {len(TAB_ICONS)} 種")

    ok = fail = 0
    for name, desc in TAB_ICONS.items():
        dest = REPO_ROOT / f"assets/generated/ui/{name}.png"
        try:
            if generate_icon(key, desc, dest, size=48, no_bg=False, force=force):
                ok += 1
        except Exception as e:
            print(f"    ✗ {name}: {e}", flush=True)
            fail += 1
    print(f"\n  完了: {ok}/{len(TAB_ICONS)} 成功, {fail} 失敗")


# ─────────────────────────────────────────────
# all コマンド（欠けているアセットを自動判定）
# ─────────────────────────────────────────────

def cmd_all(key: str, args):
    print("▶ 欠けているアセットをスキャン中…\n")

    # 1. 表情フレーム
    all_exprs  = list(EXPR_PROMPTS.keys())
    all_states = list(STATE_PROMPTS.keys())

    for char_id in CHARACTERS:
        face_dir = REPO_ROOT / f"assets/generated/face/{char_id}"
        missing  = []
        for e in all_exprs:
            for s in all_states:
                p = face_dir / f"{e}_{s}.png"
                if not p.exists():
                    missing.append(f"{e}_{s}")

        if missing:
            print(f"表情 [{char_id}] 欠け: {len(missing)} フレーム → 生成開始")
            face_args = argparse.Namespace(
                char_id=char_id,
                exprs=None,
                states=None,
                dry_run=False,
            )
            cmd_face(key, face_args)
        else:
            print(f"表情 [{char_id}] ✓ 全 {len(all_exprs)*len(all_states)} フレーム存在")

    # 2. 戦闘スプライト
    for char_id in ["kiriko", "mil", "muu"]:
        sprite_dir = REPO_ROOT / f"assets/generated/sprites/{char_id}"
        missing_anims = [
            a for a in SPRITE_ANIMS
            if not (sprite_dir / f"{a}.png").exists()
        ]
        if missing_anims:
            print(f"\nスプライト [{char_id}] 欠け: {missing_anims} → 生成開始")
            sprite_args = argparse.Namespace(
                char_id=char_id,
                anims=",".join(missing_anims),
            )
            cmd_sprites(key, sprite_args)
        else:
            print(f"スプライト [{char_id}] ✓ 全アニメ存在")

    # 3. 探索背景
    explore_bg = REPO_ROOT / "assets/art/explore_bg.png"
    if not explore_bg.exists():
        print(f"\n探索背景 欠け → 生成開始")
        bg_args = argparse.Namespace(force=False)
        cmd_bg(key, bg_args)
    else:
        print(f"\n探索背景 ✓ 存在")

    # 4. 食べ物アイコン
    print("\n▶ 食べ物アイコン確認…")
    missing_food = [k for k in FOOD_ICONS
                    if not (REPO_ROOT / f"assets/generated/food/{k}.png").exists()]
    if missing_food:
        print(f"  欠け: {missing_food} → 生成開始")
        food_args = argparse.Namespace(force=False, ids=",".join(missing_food))
        cmd_food(key, food_args)
    else:
        print("  ✓ 全品存在")

    # 5. アイテムアイコン（素材・箱・装備）
    print("\n▶ アイテムアイコン確認…")
    missing_items = (
        [k for k in INGREDIENT_ICONS if not (REPO_ROOT / f"assets/generated/ing/{k}.png").exists()]
        + [k for k in BOX_ICONS if not (REPO_ROOT / f"assets/generated/box/{k}.png").exists()]
        + [k for k in EQUIP_ICONS if not (REPO_ROOT / f"assets/generated/equip/{k}.png").exists()]
    )
    if missing_items:
        print(f"  欠け: {missing_items} → 生成開始")
        items_args = argparse.Namespace(force=False)
        cmd_items(key, items_args)
    else:
        print("  ✓ 全品存在")

    # 6. FXエフェクト
    print("\n▶ FXエフェクト確認…")
    missing_fx = [k for k in FX_ICONS
                  if not (REPO_ROOT / f"assets/generated/fx/{k}.png").exists()]
    if missing_fx:
        print(f"  欠け: {missing_fx} → 生成開始")
        fx_args = argparse.Namespace(force=False)
        cmd_fx(key, fx_args)
    else:
        print("  ✓ 全品存在")

    # 7. スキルアイコン
    print("\n▶ スキルアイコン確認…")
    missing_skills = [k for k in SKILL_ICONS
                      if not (REPO_ROOT / f"assets/generated/skill/{k}.png").exists()]
    if missing_skills:
        print(f"  欠け: {missing_skills} → 生成開始")
        skill_args = argparse.Namespace(force=False, ids=None)
        cmd_skills(key, skill_args)
    else:
        print("  ✓ 全品存在")

    # 8. 改装ツリーノード
    print("\n▶ 改装ツリーノードアイコン確認…")
    missing_renov = [k for k in RENOV_NODE_ICONS
                     if not (REPO_ROOT / f"assets/generated/renov/{k}.png").exists()]
    if missing_renov:
        print(f"  欠け: {missing_renov} → 生成開始")
        renov_args = argparse.Namespace(force=False)
        cmd_renov(key, renov_args)
    else:
        print("  ✓ 全品存在")

    # 9. タブバーアイコン
    print("\n▶ タブバーアイコン確認…")
    missing_tabs = [k for k in TAB_ICONS
                    if not (REPO_ROOT / f"assets/generated/ui/{k}.png").exists()]
    if missing_tabs:
        print(f"  欠け: {missing_tabs} → 生成開始")
        tabs_args = argparse.Namespace(force=False)
        cmd_tabs(key, tabs_args)
    else:
        print("  ✓ 全品存在")

    print("\n── all 完了 ──")


# ─────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(
        description="PixelLab API v2 — 黒猫飯店アセット一括生成",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    sub = ap.add_subparsers(dest="cmd", required=True)

    # balance
    sub.add_parser("balance", help="APIクレジット残高を確認")

    # face
    p_face = sub.add_parser("face", help="表情フレームを生成")
    p_face.add_argument("char_id", choices=list(CHARACTERS))
    p_face.add_argument("--exprs",  help="カンマ区切り表情 (例: neutral,smile)")
    p_face.add_argument("--states", help="カンマ区切り状態 (例: closed,half,open,blink)")
    p_face.add_argument("--dry-run", dest="dry_run", action="store_true",
                        help="プロンプトを表示するだけで生成しない")

    # sprites
    p_spr = sub.add_parser("sprites", help="戦闘スプライトを生成")
    p_spr.add_argument("char_id", choices=list(CHARACTERS))
    p_spr.add_argument("--anims", help="カンマ区切りアニメ (例: walk_front,attack)")
    p_spr.add_argument("--force", action="store_true", help="既存を上書き")

    # bg
    p_bg = sub.add_parser("bg", help="探索背景を生成 (assets/art/explore_bg.png)")
    p_bg.add_argument("--force", action="store_true", help="既存ファイルを上書き")

    # bgs
    p_bgs = sub.add_parser("bgs", help="パララックス背景レイヤーを生成 (assets/generated/bg/)")
    p_bgs.add_argument("--force", action="store_true", help="既存を上書き")

    # scene_bgs
    p_sbg = sub.add_parser("scene_bgs", help="シナリオ会話背景を生成 (assets/generated/scene/)")
    p_sbg.add_argument("--ids",   help="カンマ区切りID (例: restaurant,street)")
    p_sbg.add_argument("--force", action="store_true", help="既存を上書き")

    # food
    p_food = sub.add_parser("food", help="料理アイコンを生成")
    p_food.add_argument("--ids",   help="カンマ区切りID (例: tantan,mabo)")
    p_food.add_argument("--force", action="store_true", help="既存を上書き")

    # items
    p_items = sub.add_parser("items", help="素材・箱・装備アイコンを生成")
    p_items.add_argument("--force", action="store_true", help="既存を上書き")

    # fx
    p_fx = sub.add_parser("fx", help="エフェクトスプライトを生成")
    p_fx.add_argument("--force", action="store_true", help="既存を上書き")

    # skills
    p_sk = sub.add_parser("skills", help="スキルアイコンを生成 (assets/generated/skill/)")
    p_sk.add_argument("--ids",   help="カンマ区切りスキルID (例: first_aid,cover)")
    p_sk.add_argument("--force", action="store_true", help="既存を上書き")

    # renov
    p_rv = sub.add_parser("renov", help="改装ツリーノードアイコンを生成 (assets/generated/renov/)")
    p_rv.add_argument("--force", action="store_true", help="既存を上書き")

    # tabs
    p_tabs = sub.add_parser("tabs", help="タブバーアイコンを生成 (assets/generated/ui/tab_*.png)")
    p_tabs.add_argument("--force", action="store_true", help="既存を上書き")

    # all
    sub.add_parser("all", help="欠けているアセットを全て生成")

    args = ap.parse_args()
    # dry-run / balance 確認以外はAPIキーが必要
    need_key = not (args.cmd == "balance" or getattr(args, "dry_run", False))
    key = load_api_key() if need_key or args.cmd == "balance" else "dry-run"
    if getattr(args, "dry_run", False):
        key = "dry-run"

    CMDS = {
        "balance": cmd_balance,
        "face":    cmd_face,
        "sprites": cmd_sprites,
        "bg":      cmd_bg,
        "bgs":       cmd_bgs,
        "scene_bgs": cmd_scene_bgs,
        "food":    cmd_food,
        "items":   cmd_items,
        "fx":      cmd_fx,
        "skills":  cmd_skills,
        "renov":   cmd_renov,
        "tabs":    cmd_tabs,
        "all":     cmd_all,
    }
    CMDS[args.cmd](key, args)


if __name__ == "__main__":
    main()
