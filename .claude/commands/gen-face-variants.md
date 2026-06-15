# gen-face-variants — Gemini API を使った表情差分生成スキル

## 概要

キャラクターの `neutral_closed.png`（または任意のベース画像）を入力として、
Gemini API (`gemini-3-pro-image-preview`) でアニメチビキャラの表情差分を自動生成する。

**メリット:**
- PixAI（テキスト→画像）より頭の角度・位置ずれが起きにくい
- 自然言語の編集指示でベース画像から最小変化で表情を変える
- 全バリアント同一ベースから生成 → 透過率・見た目が揃う

---

## 生成スクリプト

`tools/gen_face_gemini.py`

### 基本使い方

```bash
# 特定キャラ・全バリアント生成
python3 tools/gen_face_gemini.py --char mil --force

# 特定バリアントのみ
python3 tools/gen_face_gemini.py --char mil --variant smile_open --force

# ベース画像を指定（位置ずれ対策）
python3 tools/gen_face_gemini.py --char mil \
  --base tools/_out/face_mil_raw/neutral_blink_raw.png --force

# 全キャラ一括
python3 tools/gen_face_gemini.py --force
```

### 引数

| 引数 | 説明 |
|---|---|
| `--char` | キャラ名 (mil/yuzuki/muu/kiriko/all) |
| `--variant` | 特定バリアントのみ (例: smile_open) |
| `--force` | 既存ファイルも上書き |
| `--base <path>` | ベース画像を指定（デフォルト: neutral_closed.png） |
| `--model <name>` | Geminiモデル変更 |
| `--list-models` | 利用可能モデル一覧 |

---

## ベース画像の選び方（位置ずれ対策）

**問題:** PixAI生成の `neutral_closed.png` をベースにすると、
Gemini出力との背景色差・スタイル差で透過率が変わったり顔位置がずれることがある。

**解決策:** PixAI rawフォルダ（`tools/_out/face_<char>_raw/`）から
位置が良いものを選んで `--base` に指定する。

```bash
# raw ファイル確認
ls tools/_out/face_mil_raw/

# 良さそうなものをベースに全バリアント生成
python3 tools/gen_face_gemini.py --char mil \
  --base tools/_out/face_mil_raw/neutral_blink_raw.png --force
```

`neutral_closed` も同じベースで生成することで背景色・透過率が全バリアントで揃う。

---

## バリアント構成（20種）

| 感情 | closed | half | open | blink |
|---|---|---|---|---|
| neutral | 口閉じ | 少し開く | 大きく開く | 目を閉じる |
| smile | 口角上げ | 少し開く | 笑って開く | 目を細める |
| surprise | 驚き口閉じ | 少し開く | 驚き大開き | 目を閉じる |
| calm | 真剣口閉じ | 少し開く | 話す | 目を閉じる |
| eat | 食べ口閉じ | 少し開く | 食べる | 目を閉じる |

---

## 背景キーイング

4コーナー独立フラッドフィル方式（`key_background()` in gen_face_gemini.py）:
- 4隅それぞれ独立で近似色ピクセルを検出
- 全コーナーのマスクを合算
- ユズキのようにグラデーション背景でも対応

**正常時の透過率目安:** Gemini (`gemini-3-pro-image-preview`) から生成した場合、
バスト512×512のチビキャラで **32〜34%** が正常。40%超は銀髪等が一緒にキーされている可能性あり。

---

## 必要環境

```bash
pip install google-genai pillow numpy scipy
```

`.env` に追記:
```
GEMINI_API_KEY=AIza...
```

---

## キャラ別 neutral_closed の在り処

| キャラ | パス |
|---|---|
| mil | `assets/generated/face/mil/neutral_closed.png` |
| yuzuki | `assets/generated/face/yuzuki/neutral_closed.png` |
| muu | `assets/generated/face/muu/neutral_closed.png` |
| kiriko | `assets/generated/face/kiriko/neutral_closed.png` |

rawファイル（Geminiデバッグ用）: `tools/_out/face_gemini_raw/<char>/<variant>_raw.png`

---

## 生成後の Godot reimport

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .
```
