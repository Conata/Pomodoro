#!/usr/bin/env bash
# gen_all_faces.sh — 全キャラの表情差分を Gemini API で一括生成する
#
# 使い方:
#   bash tools/gen_all_faces.sh           # 差分のみ（既存スキップ）
#   bash tools/gen_all_faces.sh --force   # 全上書き
#
# 必要環境:
#   pip install google-genai pillow numpy scipy
#   .env に GEMINI_API_KEY=AIza... を記入
#
# ベース画像: 各キャラの PixAI 生成 raw から neutral_blink_raw.png を使用
# （Gemini出力と同じスタイルで位置ずれが起きにくい）

set -euo pipefail
cd "$(dirname "$0")/.."

FORCE="${1:-}"
SCRIPT="tools/gen_face_gemini.py"

declare -A BASE_IMAGES=(
  [mil]="tools/_out/face_mil_raw/neutral_blink_raw.png"
  [yuzuki]="tools/_out/face_yuzuki_raw/neutral_blink_raw.png"
  [muu]="tools/_out/face_muu_raw/neutral_blink_raw.png"
  [kiriko]="tools/_out/face_kiriko_raw/neutral_blink_raw.png"
)

for CHAR in mil yuzuki muu kiriko; do
  BASE="${BASE_IMAGES[$CHAR]}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $CHAR  (base: $BASE)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if [ ! -f "$BASE" ]; then
    echo "  ⚠ ベース画像が見つかりません: $BASE"
    echo "  スキップします。"
    echo ""
    continue
  fi

  ARGS="--char $CHAR --base $BASE"
  if [ "$FORCE" = "--force" ]; then
    ARGS="$ARGS --force"
  fi

  python3 "$SCRIPT" $ARGS
  echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "全キャラ完了。Godot で再インポートしてください:"
echo "  /Applications/Godot.app/Contents/MacOS/Godot --headless --import --path ."
