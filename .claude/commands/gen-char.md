# 黒猫飯店 キャラクター画像生成ガイド

このスキルは `docs/design/characters.md` に基づき、キャラクターごとの PixAI 生成ワークフローを案内します。

## 使い方
引数にキャラ名（`mil` / `yuzuki` / `muu` / `kiriko` / 全員なら `all`）を渡す。
例: `/gen-char mil`

---

## 共通世界観タグ（全生成に付与）
```
masterpiece, best quality, absurdres,
anime character design, near future cyberpunk,
psychological fantasy, Arknights style, Girls Frontline style,
clean lineart, soft shading, white background,
character sheet, front view,
black cat restaurant universe, mental dive technology,
personality dungeon, cybernetic implants, futuristic fashion
```

---

## FaceCam 用チビ生成（Godot ワイプ向け・512×512）

**実行方法:**
```bash
# 差分のみ生成（既存スキップ）
python3 tools/gen_face_<char>.py

# 全枚強制再生成
python3 tools/gen_face_<char>.py --force

# 特定1枚だけ再生成
rm assets/generated/face/<char>/<expr>_<state>.png
python3 tools/gen_face_<char>.py

# 生成後 import 更新
/Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .
```

| キャラ | スクリプト | シード範囲 | モデル |
|---|---|---|---|
| ユズキ | `tools/gen_face_yuzuki.py` | 1xxx | Tsubaki.2 |
| ミル | `tools/gen_face_mil.py` | 2xxx | Tsubaki.2 |
| ムュウ | `tools/gen_face_muu.py` | 3xxx | Tsubaki.2 |
| レイカ | `tools/gen_face_kiriko.py` | 4xxx | Tsubaki.2 |

---

## 探索チビスプライト生成（256×96 px 4コマシート）

**スクリプト:** `tools/gen_sprite.py`
**モデル:** Tsubaki.2（gen_face_* と同じ）
**出力:** `assets/generated/sprites/<id>/<anim>.png`（256×96、4フレーム横並び）

```bash
# 単体キャラ・全アニメ
python3 tools/gen_sprite.py yuzuki

# 全キャラ
python3 tools/gen_sprite.py all

# アニメ指定
python3 tools/gen_sprite.py mil --anim walk_front

# 強制再生成
python3 tools/gen_sprite.py all --force

# プロンプト確認のみ（APIコール無し）
python3 tools/gen_sprite.py all --dry-run
```

| キャラ | シードベース | アニメ |
|---|---|---|
| ユズキ | 1000 | walk_front, attack |
| ミル | 2000 | walk_front, attack |
| ムュウ | 3000 | walk_front, attack |
| レイカ | 4000 | walk_front, attack |

**サイズ仕様:**
- PixAI 生成: 512×768 px
- NEAREST 縮小: 64×96 px/フレーム
- 出力シート: 256×96 px（4フレーム横並び）
- Godot 側: `CHIBI_FRAMES=4` で自動分割、表示高さに合わせてスケール

**中間ファイル:** `tools/_out/sprite_raw/<id>/<anim>_f<n>_raw.png`（再生成スキップに使用）

---

## キャラ別フルボディプロンプト（Arknights/GFL スタイル）

詳細は `docs/design/characters.md` を参照。

### ユズキ（オレンジ・感情・主人公）
```
cute girl, orange twin tails, orange eyes,
oversized black sweatshirt, plaid skirt, black boots,
crossbody bag, black choker, slightly mischievous smile, lonely expression,
urban street fashion, full body, character sheet, Arknights style
```
シーン追加: `rainy street, orange leaves, black cat plushie, sunset`

### ミル（白・観測・ネットランナー）
```
cyberpunk hacker girl, short silver hair, pink inner hair, amber eyes,
oversized black leather jacket, pink crop top, black shorts,
asymmetrical stockings, playful smile, street fashion, slim body,
full body, character sheet, high detail, Arknights style
```
シーン追加: `glitch effect, digital corruption, hologram screens, cyberspace`

### ムュウ（青黄・生・探索配信者）
```
cute fox girl, long blonde hair, fox ears, blue eyes,
white oversized jacket, blue futuristic dress, yellow belt, robotic gloves,
energetic smile, idol streamer, cyber explorer,
full body, character sheet, Arknights style
```
シーン追加: `livestream UI, floating drones, camera drone, chat overlay`

### レイカ（青・理性・人格管理者）
```
beautiful woman, long blue hair, gold eyes,
white ceremonial dress, cybernetic prosthetic leg,
elegant posture, cold expression, saint-like appearance,
mental world administrator, full body, character sheet, Arknights style
```
シーン追加: `cathedral, blue butterflies, moonlight, memory archive, white flowers`

### ドクター（緑・治療・黒猫飯店オーナー）
```
handsome male doctor, long dark green hair, gray eyes,
white oversized lab coat, black turtleneck, black pants,
neck tattoo, slim tall body, cold expression,
futuristic psychiatrist, mental surgeon, full body, character sheet, Arknights style
```
シーン追加: `operating room, medical hologram, brain scan, green particles`

### ナース（緑白・救済・医療支援AI）
```
female android nurse, mint green hair, green eyes,
white nurse dress, green accents, mechanical legs, medical IV bag,
gentle smile, cybernetic body, medical support robot,
full body, character sheet, Arknights style
```
シーン追加: `hospital corridor, medical hologram, healing particles`

---

## シーン用追加タグ

**人格世界ボス戦:**
```
surreal dreamscape, psychological horror, floating memories,
fragmented city, mental dungeon, distorted reality, memory fragments
```

**黒猫飯店の日常:**
```
cozy restaurant, black cat cafe, warm lights,
late night atmosphere, found family
```

---

## 向き（flip）設定
FaceCam ワイプの向きは `src/ui/face_cam.gd` の `flip_h` プロパティで制御。
`data.gd` の GIRLS["flip"] で各キャラのデフォルト向きを管理。

| キャラ | flip_h | 理由 |
|---|---|---|
| mil | false | 左端→右向き（画面内向き） |
| yuzuki | true | 右寄り→左向き |
| muu | true | 右寄り→左向き |
| kiriko | false | 左端→右向き |

---

## 新キャラ追加手順
1. `docs/design/characters.md` にプロンプトを追記
2. `tools/gen_face_<新キャラ>.py` を既存スクリプトからコピーして BASE/VARIANTS を書き換え
3. `src/sim/data.gd` の GIRLS に追加（color, flip 含む）
4. `src/ui/face_test.gd` の CHARS に追加
