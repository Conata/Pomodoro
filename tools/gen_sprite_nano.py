#!/usr/bin/env python3
"""
tools/gen_sprite_nano.py — ナノバナナ（Google Gemini Imagen）チビスプライト生成

各キャラ／敵のベース画像（assets/generated/sprites/<id>/base.png）を入力に、
Gemini の画像編集（ポーズだけを差し替え）で 4 コマ分を生成し、
背景キーイング → 64×96 NEAREST 縮小 → 4 コマ横並びシート（256×96）にして
assets/generated/sprites/<id>/<anim>.png へ保存する。

gen_face_gemini.py（ベース画像から最小編集で派生）と
gen_sprite.py（背景キーイング＋シート化）のアプローチを組み合わせたもの。
Godot 側 _draw_chibi() は シート幅 / CHIBI_FRAMES(4) をフレーム幅として自動読込。

使い方:
    pip install google-genai pillow numpy scipy
    export GEMINI_API_KEY=AIza...     # または .env に記入

    python3 tools/gen_sprite_nano.py mil                    # ミルの全アニメ
    python3 tools/gen_sprite_nano.py all                    # 全キャラ全アニメ
    python3 tools/gen_sprite_nano.py mil --anim idle        # 個別アニメ
    python3 tools/gen_sprite_nano.py mil --anim idle,hit    # 複数アニメ
    python3 tools/gen_sprite_nano.py all --force            # 上書き
    python3 tools/gen_sprite_nano.py mil --dry-run          # プロンプト確認のみ
    python3 tools/gen_sprite_nano.py mil --base path/to/img.png   # ベース画像指定
    python3 tools/gen_sprite_nano.py --enemies              # 敵スプライト全種
    python3 tools/gen_sprite_nano.py mob_slime --enemies    # 敵を個別指定

出力:
    assets/generated/sprites/<id>/<anim>.png    256×96 RGBA, 横並び 4 コマ
    tools/_out/sprite_nano_raw/<id>/<anim>_f<n>_raw.png   生成元（デバッグ用）

生成後:
    /Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .
"""

import argparse
import io
import os
import sys
import time
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("ERROR: Pillow が必要です:  pip install Pillow")

# ── 設定 ──────────────────────────────────────────────────────────────────
MODEL      = "gemini-3-pro-image-preview"   # gen_face_gemini.py と同じ
FRAME_W    = 64    # 出力フレーム幅
FRAME_H    = 96    # 出力フレーム高さ
FRAMES     = 4     # 1 シート内フレーム数（Godot CHIBI_FRAMES と一致）
KEY_TOL    = 30    # 背景キー許容差（ピクセル値）

REPO_ROOT  = Path(__file__).parent.parent
OUT_BASE   = REPO_ROOT / "assets/generated/sprites"
TMP_BASE   = Path(__file__).parent / "_out/sprite_nano_raw"


# ── キャラクター定義 ──────────────────────────────────────────────────────
# gen_sprite.py の CHARS を流用しつつ、appearance は gen_face_gemini.py の
# スタイル（一致性を保つために毎回添付する見た目の説明文）で記述。
CHARS = {
    "mil": {
        "appearance": (
            "chibi super deformed anime girl, 2.5 head tall, thick black outline, "
            "short silver hair with pink inner color, amber eyes, "
            "oversized black leather jacket, pink crop top, black shorts, "
            "cyberpunk hacker street fashion"
        ),
    },
    "yuzuki": {
        "appearance": (
            "chibi super deformed anime girl, 2.5 head tall, thick black outline, "
            "orange twin tails, orange eyes, "
            "oversized black sweatshirt, plaid skirt, urban street fashion"
        ),
    },
    "muu": {
        "appearance": (
            "chibi super deformed anime fox girl, 2.5 head tall, thick black outline, "
            "long blonde hair, fox ears, blue eyes, "
            "white oversized jacket, blue futuristic dress, idol streamer style"
        ),
    },
    "kiriko": {
        "appearance": (
            "chibi super deformed anime girl, 2.5 head tall, thick black outline, "
            "long blue hair, gold eyes, white ceremonial dress, "
            "cold elegant administrator look"
        ),
    },
    "doctor": {
        "appearance": (
            "chibi super deformed anime man, 2.5 head tall, thick black outline, "
            "long dark green hair, gray eyes, white oversized lab coat, "
            "black turtleneck, futuristic psychiatrist style"
        ),
    },
    "nurse": {
        "appearance": (
            "chibi super deformed anime android girl, 2.5 head tall, thick black outline, "
            "mint green hair, green eyes, white nurse dress with green accents, "
            "mechanical legs, gentle medical support android"
        ),
    },
}

# ── 敵スプライト定義 ──────────────────────────────────────────────────────
ENEMIES = {
    "mob_slime": {
        "appearance": (
            "chibi pixel art slime monster, thick black outline, "
            "small translucent blue gelatinous blob, glowing cyan core, "
            "tiny menacing eyes, cyberpunk dungeon creature"
        ),
    },
    "mob_drone": {
        "appearance": (
            "chibi pixel art cyber drone, thick black outline, "
            "small floating metallic combat drone, single glowing red eye lens, "
            "hovering rotor blades, dark chrome body"
        ),
    },
    "mob_spider": {
        "appearance": (
            "chibi pixel art mechanical spider robot, thick black outline, "
            "four sharp angular legs, glowing red sensor cluster, "
            "dark chrome plated body, menacing crawler"
        ),
    },
    "elite_guard": {
        "appearance": (
            "chibi pixel art armored cyber soldier, thick black outline, "
            "heavy purple plated armor, glowing visor, energy shield arm, "
            "imposing elite guardian"
        ),
    },
    "boss_core": {
        "appearance": (
            "chibi pixel art floating AI core boss, thick black outline, "
            "large crystalline geometric body, multiple glowing eyes, "
            "ominous corrupted machine god, radiant menace"
        ),
    },
}

# ── アニメーション定義 ─────────────────────────────────────────────────────
# 各アニメ: [(frame_suffix, ポーズ指示)] × 4
ANIMS = {
    # 微揺れ・待機ポーズの 4 段階
    "idle": [
        ("f0", "standing relaxed in a neutral idle pose, arms resting at sides, weight centered, calm"),
        ("f1", "idle with a subtle sway to the left, shoulders raised a touch as if breathing in"),
        ("f2", "standing relaxed and centered again, a gentle settle, calm idle"),
        ("f3", "idle with a subtle sway to the right, shoulders lowered as if breathing out"),
    ],
    # 歩行サイクル 4 コマ（gen_sprite.py の walk_front と同じポーズ指示）
    "walk_front": [
        ("f0", "standing neutral pose, arms relaxed at sides, feet together, facing viewer"),
        ("f1", "mid-walk step, left foot forward, right arm slightly raised, light lean"),
        ("f2", "walking stride upright, arms mid-swing, slight bounce"),
        ("f3", "mid-walk step, right foot forward, left arm slightly raised, light lean"),
    ],
    # 攻撃モーション 4 コマ（gen_sprite.py の attack と同じポーズ指示）
    "attack": [
        ("f0", "combat ready stance, feet apart, fists raised, determined fierce expression"),
        ("f1", "launching an attack, arm thrusting forward powerfully, body twisting"),
        ("f2", "attack fully extended, arm outstretched, impact moment, dynamic pose"),
        ("f3", "recovering from the attack, returning to guard stance, confident ready"),
    ],
    # 被弾のけぞり 4 コマ
    "hit": [
        ("f0", "just got hit, body flinching, head recoiling back, pained expression"),
        ("f1", "staggering backward, leaning back, arms flailing, eyes shut in pain"),
        ("f2", "knocked off balance, deep backward lean, defensive recoil, hurt"),
        ("f3", "regaining footing, returning toward stance, wincing in recovery"),
    ],
}


# ── プロンプト構築 ─────────────────────────────────────────────────────────
def build_instruction(appearance: str, pose: str) -> str:
    return (
        "This is a chibi pixel art sprite. "
        f"Edit MINIMALLY: ONLY change body pose to [{pose}]. "
        "Do NOT change character design/colors/outfit/art style. "
        "Keep thick black outline pixel art style. Output same size. "
        f"Character description to maintain: {appearance}."
    )


# ── .env 読み込み ─────────────────────────────────────────────────────────
def load_api_key() -> str:
    key = os.getenv("GEMINI_API_KEY", "")
    if not key:
        env_path = REPO_ROOT / ".env"
        if env_path.exists():
            for line in env_path.read_text().splitlines():
                line = line.strip()
                if line.startswith("GEMINI_API_KEY="):
                    key = line.split("=", 1)[1].strip().strip('"').strip("'")
    if not key:
        sys.exit(
            "ERROR: GEMINI_API_KEY が見つかりません。\n"
            "  export GEMINI_API_KEY=AIza...\n"
            "  または .env に GEMINI_API_KEY=AIza... を追記してください。"
        )
    return key


# ── Gemini API 呼び出し（gen_face_gemini.py 流用）────────────────────────────
def generate_frame(client, model_name: str, base_img_bytes: bytes,
                   instruction: str, retries: int = 2) -> bytes | None:
    """base_img_bytes を入力画像として instruction で編集した画像を返す（PNG bytes）。"""
    from google.genai import types

    parts = [
        types.Part.from_bytes(data=base_img_bytes, mime_type="image/png"),
        types.Part.from_text(text=instruction),
    ]
    for attempt in range(retries + 1):
        try:
            response = client.models.generate_content(
                model=model_name,
                contents=parts,
                config=types.GenerateContentConfig(
                    response_modalities=["IMAGE"],
                ),
            )
            if not response.candidates:
                print(f"[no candidates, attempt {attempt+1}]", end=" ")
                time.sleep(3)
                continue
            for part in response.candidates[0].content.parts:
                if hasattr(part, "inline_data") and part.inline_data:
                    return part.inline_data.data  # bytes
            text_parts = [
                p.text for p in response.candidates[0].content.parts
                if hasattr(p, "text") and p.text
            ]
            if text_parts:
                print(f"[model returned text only: {text_parts[0][:80]!r}]", end=" ")
            else:
                print(f"[no image in response, attempt {attempt+1}]", end=" ")
            time.sleep(3)
        except Exception as e:
            msg = str(e)
            if "429" in msg or "RESOURCE_EXHAUSTED" in msg:
                wait = 60 * (attempt + 1)
                print(f"[rate limit, wait {wait}s]", end=" ", flush=True)
                time.sleep(wait)
            elif "500" in msg or "503" in msg:
                print(f"[server error {attempt+1}: {msg[:60]}]", end=" ")
                time.sleep(10)
            else:
                print(f"[error: {msg[:80]}]", end=" ")
                if attempt == retries:
                    return None
                time.sleep(5)
    return None


# ── 背景キーイング（gen_face_gemini.py の 4 隅フラッドフィル）─────────────────
def key_background(src_bytes: bytes, tol: int = KEY_TOL) -> Image.Image:
    """4 隅それぞれ独立フラッドフィルで背景を透過に抜く。RGBA Image を返す（原寸）。"""
    img = Image.open(io.BytesIO(src_bytes)).convert("RGBA")
    try:
        import numpy as np
        from scipy import ndimage

        a = np.array(img)
        h, w = a.shape[:2]
        combined_mask = np.zeros((h, w), dtype=bool)

        corners = [(0, 0), (0, w - 1), (h - 1, 0), (h - 1, w - 1)]
        for (cr, cc) in corners:
            r0, g0, b0 = int(a[cr, cc, 0]), int(a[cr, cc, 1]), int(a[cr, cc, 2])
            rgb = a[:, :, :3].astype(int)
            near = (
                (abs(rgb[:, :, 0] - r0) <= tol) &
                (abs(rgb[:, :, 1] - g0) <= tol) &
                (abs(rgb[:, :, 2] - b0) <= tol)
            )
            lbl, _ = ndimage.label(near)
            border_ids = (
                set(lbl[0, :]) | set(lbl[-1, :]) |
                set(lbl[:, 0]) | set(lbl[:, -1])
            ) - {0}
            combined_mask |= np.isin(lbl, list(border_ids))

        a[combined_mask, 3] = 0
        transparent_pct = 100 * combined_mask.sum() / (h * w)
        print(f"keyed({transparent_pct:.0f}%)", end=" ", flush=True)
        return Image.fromarray(a)
    except ImportError:
        print("no-key", end=" ", flush=True)
        return img


def downscale_nearest(img: Image.Image, w: int, h: int) -> Image.Image:
    """NEAREST で縮小（ドット感を保つ）"""
    return img.resize((w, h), Image.NEAREST)


def assemble_sheet(frames: list[Image.Image]) -> Image.Image:
    """4 フレームを横並びに結合 → 256×96"""
    assert len(frames) == FRAMES
    sheet = Image.new("RGBA", (FRAME_W * FRAMES, FRAME_H), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        sheet.paste(f, (i * FRAME_W, 0), f)
    return sheet


# ── 生成ロジック ───────────────────────────────────────────────────────────
def generate_sprite_sheet(client, model_name: str, target_id: str,
                          appearance: str, anim_name: str,
                          base_bytes: bytes, force: bool = False) -> bool:
    dest = OUT_BASE / target_id / f"{anim_name}.png"
    if dest.exists() and not force:
        print(f"  skip (exists): {dest.relative_to(REPO_ROOT)}")
        return True

    anim = ANIMS[anim_name]
    tmp_d = TMP_BASE / target_id
    tmp_d.mkdir(parents=True, exist_ok=True)

    frames: list[Image.Image] = []
    total = len(anim)

    for i, (suffix, pose) in enumerate(anim, 1):
        print(f"  [{i}/{total}] {anim_name}/{suffix} ... ", end="", flush=True)
        instruction = build_instruction(appearance, pose)
        img_bytes = generate_frame(client, model_name, base_bytes, instruction)
        if img_bytes is None:
            print("✗ FAILED")
            return False

        # 生ファイルを tmp に保存（デバッグ用）
        (tmp_d / f"{anim_name}_{suffix}_raw.png").write_bytes(img_bytes)

        keyed = key_background(img_bytes)
        frame = downscale_nearest(keyed, FRAME_W, FRAME_H)
        frames.append(frame)
        print(f"→ {FRAME_W}×{FRAME_H}")

    sheet = assemble_sheet(frames)
    dest.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(str(dest), "PNG")
    print(f"  ✓ saved → {dest.relative_to(REPO_ROOT)}  ({FRAME_W*FRAMES}×{FRAME_H})")
    return True


def load_base_bytes(target_id: str, override: str | None) -> bytes | None:
    if override:
        base_path = Path(override)
    else:
        base_path = OUT_BASE / target_id / "base.png"
    if not base_path.exists():
        print(f"[{target_id}] ⚠ ベース画像が見つかりません: {base_path}")
        if not override:
            print(f"  assets/generated/sprites/{target_id}/base.png を用意するか、")
            print(f"  --base path/to/img.png でベース画像を指定してください。")
        return None
    print(f"  base: {base_path}")
    return base_path.read_bytes()


# ── main ──────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser(
        description="ナノバナナ（Gemini）チビスプライト生成",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    ap.add_argument(
        "target", nargs="?", default=None,
        help="キャラID (mil/yuzuki/muu/kiriko/doctor/nurse/all) "
             "または敵ID（--enemies 指定時）。--enemies 単体なら全敵。",
    )
    ap.add_argument("--anim", help="カンマ区切りアニメ名 (例: idle,walk_front)。省略時は全アニメ")
    ap.add_argument("--enemies", action="store_true", help="敵スプライトを生成（ENEMIES 辞書）")
    ap.add_argument("--base", default=None, help="ベース画像を上書き指定（パス）")
    ap.add_argument("--model", default=MODEL, help=f"Gemini モデル名 (default: {MODEL})")
    ap.add_argument("--force", action="store_true", help="既存シートも上書き")
    ap.add_argument("--dry-run", action="store_true", help="プロンプトを表示するだけで生成しない")
    args = ap.parse_args()

    registry = ENEMIES if args.enemies else CHARS
    label = "敵" if args.enemies else "キャラ"

    # 対象 ID の決定
    if args.target in (None, "all"):
        if args.target is None and not args.enemies:
            ap.error("キャラIDか 'all'、または --enemies を指定してください。")
        target_ids = list(registry)
    elif args.target in registry:
        target_ids = [args.target]
    else:
        ap.error(f"不明な{label}ID: {args.target}  (選択肢: {list(registry)} / all)")

    # 対象アニメの決定
    anim_keys = args.anim.split(",") if args.anim else list(ANIMS)
    for a in anim_keys:
        if a not in ANIMS:
            ap.error(f"不明なアニメ名: {a}  (選択肢: {list(ANIMS)})")

    if args.dry_run:
        print("=== dry-run: プロンプト確認 ===\n")
        for tid in target_ids:
            appearance = registry[tid]["appearance"]
            for anim_name in anim_keys:
                print(f"▶ {tid} / {anim_name}")
                for suffix, pose in ANIMS[anim_name]:
                    instr = build_instruction(appearance, pose)
                    print(f"  {suffix}: {instr}")
                print()
        return

    api_key = load_api_key()
    from google import genai
    client = genai.Client(api_key=api_key)
    model_name = args.model

    print(f"モデル: {model_name}")
    print(f"{label}: {target_ids}")
    print(f"アニメ: {anim_keys}\n")

    ok = fail = 0
    for tid in target_ids:
        print(f"▶ {tid}")
        base_bytes = load_base_bytes(tid, args.base)
        if base_bytes is None:
            fail += len(anim_keys)
            print()
            continue
        appearance = registry[tid]["appearance"]
        for anim_name in anim_keys:
            print(f"  アニメ: {anim_name}")
            try:
                if generate_sprite_sheet(client, model_name, tid, appearance,
                                         anim_name, base_bytes, args.force):
                    ok += 1
                else:
                    fail += 1
            except Exception as e:
                print(f"  ✗ ERROR ({tid}/{anim_name}): {e}", flush=True)
                fail += 1
        print()

    total = len(target_ids) * len(anim_keys)
    print(f"── 完了: {ok}/{total} 成功, {fail} 失敗 ──")
    if ok:
        print("\nGodot で再インポート:")
        print("  /Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .")


if __name__ == "__main__":
    main()
