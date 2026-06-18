# 黒猫飯店 デザインシステム

UIの色・型・間隔・コンポーネントの唯一の真実は **`src/ui/ds.gd`（class `DS`）**。
新しいUIは必ずここから引く。Vignelli の規律（型は少なく・グリッド・識別色・
余白で語る）を、リファレンス（MIDNIGHT VIDEO / Rain98）の **ダークネオン** 美学に
翻訳したもの。

**移植状況**：home/dive/menu の実オーバーレイはローカルに色・描画を直書きしていたが、
DS のトークン（差し色含む）と描画ヘルパーへ統一済み。`DS.ACCENT` をシアンに揃えたことで
DiveView/TalkView/RenovView も自動的にネオンへ整合する。暖色路線の `ui_theme.gd`（UIKit・
オレンジ/ミント/紫の画像9-patch）は別路線として**棚上げ**（現行の正はこのネオン DS）。

## トークン

### 色（色は「意味」を持つ）
| トークン | 用途 |
|---|---|
| `BG` | 画面の地（ほぼ黒の紺） |
| `SURFACE` / `SURFACE_2` | カードの面 / 一段上げ・選択 |
| `LINE` | 罫・縁（シアン半透明） |
| `TEXT` / `TEXT_2` / `TEXT_MUTE` | 本文 / 副文 / 注記 |
| `INK` | 文字の落ち影（可読性） |
| **`ACCENT`（=`CYAN`）** | **識別色＝シアン。この店のアイデンティティ**（CTA・見出し罫・選択） |
| `PINK` | キャラ・CTA・会話 |
| `PURPLE` | 深層・オカルト・潜行 |
| `GOLD`（=`WARM`） | 資源・看板・店番（ネオン看板の暖色） |
| `HP`（=`SUCCESS`） | HP・収穫・廃材 |
| `DANGER` | 切断・撤退 |

差し色（PINK/PURPLE/GOLD/HP）は意味別名。`ACCENT=CYAN` / `WARM=GOLD` / `SUCCESS=HP` は
セマンティック名のエイリアス。実画面はローカル色定義を持たず、すべてこの別名を参照する。

### 型（5段。見出し≒2×本文。これ以上増やさない）
`T_MICRO 14` / `T_BODY 19`（基準）/ `T_SUB 24` / `T_HEAD 38` / `T_DISPLAY 54`

### 間隔（8px基準）
`SP_1 4` / `SP_2 8` / `SP_3 12` / `SP_4 16` / `SP_5 24`

### 角丸
`R_SM 4` / `R_MD 8` / `R_LG 12`

## 描画ヘルパー（_draw ベースのオーバーレイ用・唯一の実装）
home/dive/menu の各オーバーレイは手描き（`_draw`）。同じ `_panel/_txt/_bar` を各画面が
重複保持していたのを **DS の static に集約**した。各画面は `self` を渡す薄いラッパー経由で呼ぶ。
- `DS.panel(ci, rect, bg, border, radius, bw)` — 角丸パネル（塗り＋縁）
- `DS.txt(ci, font, pos, s, size, col, ha, w)` — 落ち影つきテキスト
- `DS.bar(ci, rect, ratio, col)` — 比率バー
- `DS.tw(font, s, size)` — 文字幅（中央寄せ計算）

## コンポーネント（Control ノード用）
- **テーマ** `DS.theme()` — ボタン3系統・タブ・入力・パネルを一括。
- **カード** `PanelContainer`（既定で `card_style`）／ `DS.card_accent(WARM)`（店番）。
- **ボタン**：既定＝ゴースト（縁のみ）／ `DS.as_primary()`＝アクセント塗りCTA（潜る・翌朝へ・閉店作業へ）／ `DS.as_danger()`＝撤退。
- **見出し** `_section(title)` — フラッシュレフトの小見出し＋直下2px罫（Vignelli の Grandi Stazioni サイン）。中央寄せの「― 〜 ―」は使わない。
- **資源バッジ** `_badge(icon, value)` — ヘッダーの資源バー。
- **リスト行** `_list_row(title, action, cb, enabled, icon, color)` — 1行1アクションの薄カード（闇市・交易船）。先頭アイコン＋伸長見出し＋末尾ゴーストボタン。
- **適用範囲**：UIの色はメイン画面だけでなく DiveView / TalkView / RenovView も DS から引く（HP低下=DANGER、罫・吹き出し=ACCENT 等）。
- **アイコン** `assets/generated/`（料理/箱/素材、`tools/gen_assets.py` で再生成）。

## 規律（self-critique）
- 型が5段を超えていないか／中央寄せ多用していないか／装飾だけの色がないか／
  CTAは1画面に1つか／余白で階層が出ているか。出ていれば線や箱を足さない。
