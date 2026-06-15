# 黒猫飯店 キャラクターデザインシステム

## 世界観
「人格治療医が患者の精神世界へ潜る」サイコロジカル×サイバーパンク。
黒猫飯店は表の顔。ダンジョン（人格世界）探索、メンタルダイブ技術が軸。

## キャラクターカラーコード

| キャラ | 色 | 象徴 | 役割 |
|---|---|---|---|
| ユズキ | オレンジ | 感情・生命・太陽 | 主人公/依頼人「私を殺してほしい」 |
| ミル | 白/シルバー | 空白・ノイズ | 観測者・ネットランナー |
| レイカ | 青 | 理性・月・聖女 | 人格管理者「フユキを消すべき」 |
| ムュウ | 青＋黄 | 生・好奇心・電気 | 配信者・探索担当 |
| ドクター | 緑＋白 | 治療・修復・神 | 黒猫飯店オーナー・全部知っている |
| ナース | 緑＋白 | 救済・母親 | 医療支援AI |

## 共通世界観タグ（全生成に付与）

```
masterpiece, best quality, absurdres,
anime character design,
full body,
near future cyberpunk,
psychological fantasy,
Arknights style,
Girls Frontline style,
clean lineart,
soft shading,
white background,
character sheet,
front view,
black cat restaurant universe,
mental dive technology,
personality dungeon,
cybernetic implants,
futuristic fashion
```

---

## キャラクター別プロンプト

### ドクター（店主・精神科医）

**キャラ設定:** 人格治療医。黒猫飯店の店主。患者の精神世界へ潜る技術を開発した張本人。

```
masterpiece, best quality,
handsome male doctor,
long dark green hair,
gray eyes,
white oversized lab coat,
black turtleneck,
black pants,
neck tattoo,
slim tall body,
cold expression,
futuristic psychiatrist,
mental surgeon,
cyberpunk medical researcher,
full body,
character sheet,
Arknights style,
high detail
```
追加タグ: `operating room, medical hologram, brain scan, green particles, memory reconstruction`

---

### ミル（ネットランナー・ハッカー）

**キャラ設定:** ネットランナー。精神世界への侵入口を作るハッカー。

```
masterpiece, best quality,
cyberpunk hacker girl,
short silver hair,
pink inner hair,
amber eyes,
oversized black leather jacket,
pink crop top,
black shorts,
asymmetrical stockings,
playful smile,
street fashion,
slim body,
full body,
character sheet,
high detail,
Arknights style
```
追加タグ: `glitch effect, digital corruption, hologram screens, cyberspace, data stream`

**FaceCam 用チビプロンプト（512×512）:**
```
1girl, chibi, super deformed, 2 head tall, thick black outline,
flat color shading, front facing bust portrait,
short silver hair, pink inner hair, amber eyes,
oversized black leather jacket, pink crop top,
cyberpunk hacker girl, street fashion, Arknights style,
anime style, simple shading,
flat single color background #1a1030
```

---

### ムュウ（探索配信者・狐っ娘）

**キャラ設定:** 探索配信者。ダンジョン探索担当。

```
masterpiece, best quality,
cute fox girl,
long blonde hair,
fox ears,
blue eyes,
white oversized jacket,
blue futuristic dress,
yellow belt,
robotic gloves,
energetic smile,
idol streamer,
cyber explorer,
full body,
character sheet,
Arknights style
```
追加タグ: `livestream UI, followers, floating drones, camera drone, chat overlay`

**FaceCam 用チビプロンプト（512×512）:**
```
1girl, chibi, super deformed, 2 head tall, thick black outline,
flat color shading, front facing bust portrait,
cute fox girl, long blonde hair, fox ears, blue eyes,
white oversized jacket, energetic smile, idol streamer,
Arknights style, anime style, simple shading,
flat single color background #1a1030
```

---

### ナース（医療支援AI）

**キャラ設定:** 医療支援AI。人格修復ユニット。

```
masterpiece, best quality,
female android nurse,
mint green hair,
green eyes,
white nurse dress,
green accents,
mechanical legs,
medical IV bag,
gentle smile,
cybernetic body,
medical support robot,
full body,
character sheet,
Arknights style
```
追加タグ: `hospital corridor, medical hologram, healing particles, emergency room`

---

### レイカ（人格管理者）

**キャラ設定:** 人格管理者。ユズキの精神世界を監視する存在。

```
masterpiece, best quality,
beautiful woman,
long blue hair,
gold eyes,
white ceremonial dress,
cybernetic prosthetic leg,
elegant posture,
cold expression,
saint-like appearance,
mental world administrator,
full body,
character sheet,
Arknights style
```
追加タグ: `cathedral, blue butterflies, moonlight, memory archive, white flowers`

**FaceCam 用チビプロンプト（512×512）:**
```
1girl, chibi, super deformed, 2 head tall, thick black outline,
flat color shading, front facing bust portrait,
long blue hair, gold eyes,
white ceremonial dress, cold expression, saint-like appearance,
Arknights style, anime style, simple shading,
flat single color background #1a1030
```

---

### ユズキ（依頼人・主人公）

**キャラ設定:** 依頼人。「私を殺してほしい」と願う少女。

```
masterpiece, best quality,
cute girl,
orange twin tails,
orange eyes,
oversized black sweatshirt,
plaid skirt,
black boots,
crossbody bag,
black choker,
slightly mischievous smile,
lonely expression,
urban street fashion,
full body,
character sheet,
Arknights style
```
追加タグ: `rainy street, orange leaves, black cat plushie, abandoned playground, sunset`

**FaceCam 用チビプロンプト（512×512）:**
```
1girl, chibi, super deformed, 2 head tall, thick black outline,
flat color shading, front facing bust portrait,
orange twin tails, orange eyes,
oversized black sweatshirt, slightly mischievous smile,
urban street fashion, Arknights style, anime style, simple shading,
flat single color background #1a1030
```

---

## シーン用追加タグ

**人格世界ボス戦:**
```
surreal dreamscape,
psychological horror,
floating memories,
fragmented city,
mental dungeon,
distorted reality,
memory fragments
```

**黒猫飯店の日常:**
```
cozy restaurant,
black cat cafe,
warm lights,
late night atmosphere,
found family
```

---

## FaceCam 生成スクリプト

| スクリプト | キャラ | シード範囲 |
|---|---|---|
| `tools/gen_face_yuzuki.py` | ユズキ | 1xxx |
| `tools/gen_face_mil.py` | ミル | 2xxx |
| `tools/gen_face_muu.py` | ムュウ | 3xxx |
| `tools/gen_face_kiriko.py` | レイカ | 4xxx |

実行方法:
```bash
python3 tools/gen_face_<char>.py            # 差分のみ生成
python3 tools/gen_face_<char>.py --force    # 全枚上書き
# 生成後
/Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .
```

## キャラ対立軸
```
ユズキ（感情）  ↕  レイカ（理性）
ムュウ（生きろ）↕  フユキ（死にたい）
ドクター（治療）↕  ナース（救済）
ミル（観測）←全ての外側
```
