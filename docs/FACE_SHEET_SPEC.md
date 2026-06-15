# 表情シート仕様書

配信ワイプ（`FaceCam`）の口パク・まばたき・戦闘表情に使う素材の仕様。

---

## 1. 全体構成

```
assets/generated/face/<id>/
    neutral_closed.png    # 通常・待機
    neutral_half.png
    neutral_open.png
    neutral_blink.png
    smile_closed.png      # 攻撃・得意
    smile_half.png
    smile_open.png
    smile_blink.png
    surprise_closed.png   # 被弾・驚き
    surprise_half.png
    surprise_open.png
    surprise_blink.png
    calm_closed.png       # 詠唱・集中
    calm_half.png
    calm_open.png
    calm_blink.png
    eat_closed.png        # 食事（黒猫飯店 MORNING フェーズ）
    eat_half.png
    eat_open.png
    eat_blink.png
    meta.json
```

`<id>` は `mil` / `yuzuki` / `muu` / `kiriko` / `kiriko_npc`。

---

## 2. 表情（行）の意味と発動タイミング

| expr | 意味 | ゲーム内での発動 |
|---|---|---|
| `neutral` | 通常・待機 | 常時デフォルト |
| `smile` | 攻撃・得意顔 | スキル発動（hit / aoe 系）|
| `surprise` | 驚き・被弾 | 敵の攻撃を受けたとき（2秒CD）|
| `calm` | 集中・詠唱 | 回復・シールドスキル発動時 |
| `eat` | 食事中 | MORNING フェーズ（黒猫飯店）常時 |

**優先度**: 戦闘イベントが来ると 1.8 秒間その表情を維持 → 自動で `neutral` に戻る。
**`eat` の特殊性**: `speaking` より低優先。話しかけられると会話表情が上書きする。

### eat 表情の口アニメ（咀嚼）

`speaking` と異なり、ゆっくりした周期的な口の開閉。

```
closed(0.35s) → half(0.35s) → open(0.35s) → half(0.35s) → closed … （1周 約1.4秒）
```

絵的なポイント：
- `eat_closed`：口を閉じて咀嚼している（頬がちょっとふくれている）
- `eat_half`：ゆっくり開口
- `eat_open`：大きめに開口（ひと口サイズ）
- `eat_blink`：目を細める（「うまっ」の顔）← まばたきと兼用でOK

---

## 3. 状態（列）の意味

| state | 意味 | 使われ方 |
|---|---|---|
| `closed` | 口とじ・目開け | 無発話時のデフォルト |
| `half` | 口半開き | 発話中（音量低め）|
| `open` | 口全開 | 発話中（音量高め）|
| `blink` | 目閉じ | まばたき（2〜5秒ごとにランダム）|

リップシンクは `closed → half → open` をランダムな間隔で切り替え。TTS音声が入ったら音量ピーク駆動に差し替え予定。

---

## 4. シート素材の作り方

### 4-1. グリッド構成

**4行 × 4列 = 16コマ** を 1枚の透過PNGにまとめる。

```
        closed   half   open   blink
neutral  [0,0]  [0,1]  [0,2]  [0,3]
smile    [1,0]  [1,1]  [1,2]  [1,3]
surprise [2,0]  [2,1]  [2,2]  [2,3]
calm     [3,0]  [3,1]  [3,2]  [3,3]
```

### 4-2. 推奨サイズ

| 項目 | 推奨値 |
|---|---|
| 1コマのサイズ | 512×512 px（正方形） |
| シート全体 | 2048×2048 px |
| 背景 | **透過PNG が理想**。無理なら単色フラット（下記）|
| 頭の位置 | **全コマで固定**（位置がズレると口パクがガクガクする）|
| 差分 | 口と目だけ変える。髪・服・体は全コマ完全に同じに |

### 4-3. 単色背景を使う場合

透過に見えない生成物でも、単色背景なら後でキーイングで抜ける。

推奨色（キャラに使われていない色）:
- `#1a1030`（濃紫）— ほとんどのキャラで安全
- `#00ff00`（グリーン）— 肌・髪が暖色系のキャラ向け

PixAI / ComfyUI のプロンプトに `flat single color background, #1a1030` 等を入れる。

### 4-4. 最小構成（これだけでも口パクとまばたきが成立）

`neutral` の 1行（4コマ）だけでも動く。

```
neutral_closed / neutral_half / neutral_open / neutral_blink
```

---

## 5. スライサの使い方

```bash
pip install Pillow          # numpy/scipy があると背景除去の品質が上がる

# フル（4×4）。透過PNGの場合
python3 tools/slice_expressions.py kiriko sheet_reika.png

# フル（4×4）。単色背景 #1a1030 を抜く場合
python3 tools/slice_expressions.py kiriko sheet_reika.png --bg 1a1030

# neutral の 1行だけ（最小）
python3 tools/slice_expressions.py muu muu_neutral.png \
    --rows 1 --cols 4 \
    --exprs neutral \
    --bg 00ff00
```

出力先: `assets/generated/face/<id>/` に各 PNG ＋ `meta.json`。

### 注意: 頭位置ズレの自動補正

スライサは全コマの **union bbox** で一括トリミングするため、
生成ツールが各コマの余白を変えても自動的に位置が揃う。
ただし「頭の位置が行によって数百px違う」場合は補正しきれないので、
生成時に構図を揃えることが重要。

---

## 6. フォールバック順

素材がなくても動作する（あるものを自動で使う）。

```
1. 表情シート    assets/generated/face/<id>/<expr>_<state>.png
       ↓ なければ
2. blink 欠けは closed で代用、expr 欠けは neutral で代用
       ↓ それもなければ
3. 立ち絵の頭部  assets/portraits/<id>.png の上部 42% をクロップ表示
       ↓ それもなければ
4. キャラ色のバスト（コード生成シルエット）
```

---

## 7. キャラ別メモ

| id | 表示名 | アクセント色 | 表情の方向性 |
|---|---|---|---|
| `mil` | ミル | シアン | ダークヒロイン。smile は静かな笑み、surprise は抑制的 |
| `yuzuki` | ユズキ | 暖色（オレンジ） | 表情豊か。smile は満面、surprise は大げさでOK |
| `muu` | ムュウ | ピンク〜マゼンタ | 配信者らしい明るさ。全表情やや大げさに |
| `kiriko` | レイカ | 紫 | オカルトサイエンティスト。calm が本領。smile は不敵に |
| `kiriko_npc` | キリコ | 薄紫 | 依頼人NPC。neutral 主体で十分 |

---

## 8. 将来拡張：tomari-guruguru 方式（25方向）

現在の `FaceCam` は口パク＋まばたきのみだが、
`rotejin/tomari-guruguru` の形式（5×5グリッド×6シート=150コマ）に対応すれば
**マウス追従でキャラが視線を動かす**機能を追加できる。

対応する場合の素材形式:
- 1シート 4500×4500px（1コマ900px）
- シート 6枚（A〜F: 目開閉 × 口とじ/中間/開け）
- スライサ: `rotejin/tomari-guruguru/tools/slice_character_sheets.py`

現在の `neutral/smile/surprise/calm` の 4表情と直交する機能なので、
将来は「どの表情でも25方向に振り向く」形に拡張可能。
