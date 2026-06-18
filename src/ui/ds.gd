class_name DS
extends RefCounted
## 黒猫飯店 デザインシステム — 唯一の真実（single source of truth）。
## Vignelli の規律（型は少なく・グリッド・識別色・余白で語る）を、
## リファレンス（MIDNIGHT VIDEO / Rain98）の【ダークネオン】美学に翻訳した
## トークンと描画コンポーネント工場。UI スクリプトは色・型・間隔・描画を
## すべてここから引く（home/dive/menu オーバーレイも DS 参照に統一済み）。
## docs/DESIGN_SYSTEM.md と対で維持すること。
##
## 識別色＝シアン（ACCENT）。差し色＝ピンク(キャラ/CTA)・紫(深層/オカルト)・金(資源/看板)。
## 暖色テーマ（ui_theme.gd / UIKit）は別路線として棚上げ。現行の正はこのネオン DS。

# ── 色（ダークネオン。色は「意味」を持つ） ───────────────────────────────
const BG := Color("0c0c14")          # 画面の地（ほぼ黒の紺）
const SURFACE := Color("14141f")     # カードの面
const SURFACE_2 := Color("1d1d2b")   # 面・押下/選択（一段上げ）
const LINE := Color("5aebff40")      # 罫・縁（シアン半透明）
const TEXT := Color("f5f2fa")        # 本文（真っ白を避ける）
const TEXT_2 := Color("bfc0cc")      # 副文
const TEXT_MUTE := Color("8a8b99")   # 注記/無効
const INK := Color("00000099")       # 文字の落ち影（可読性確保）

# 差し色（neon）。実画面はこの別名を参照する（旧ローカル定義を撤廃）。
const CYAN := Color(0.35, 0.92, 1.0)   # 識別色＝この店のアイデンティティ
const PINK := Color(1.0, 0.36, 0.72)   # キャラ・CTA・会話
const PURPLE := Color(0.66, 0.4, 1.0)  # 深層・オカルト・潜行
const GOLD := Color(1.0, 0.82, 0.4)    # 資源・看板・店番
const HP := Color(0.45, 0.9, 0.5)      # HP・収穫

const ACCENT := CYAN                  # 識別色（CTA・見出し罫・選択）
const ACCENT_DIM := Color(0.35, 0.92, 1.0, 0.5)
const WARM := GOLD                    # 店番・ネオン看板の暖色
const DANGER := Color("e0606a")       # 切断・撤退
const SUCCESS := HP                   # 収穫・廃材

# ── 型（5段。見出し≒2×本文。これ以上増やさない。実画面の密度に合わせ neon 調） ──
const T_MICRO := 12   # 注記・サブ
const T_BODY := 15    # 本文（基準）
const T_SUB := 18     # 小見出し
const T_HEAD := 22    # 見出し
const T_DISPLAY := 40 # 数字の主役（残り時間など）

# ── 間隔（8px基準。場当たりを排す） ──────────────────────────────────
const SP_1 := 4
const SP_2 := 8
const SP_3 := 12
const SP_4 := 16
const SP_5 := 24

# ── 角丸 ──────────────────────────────────────────────────────────
const R_SM := 4
const R_MD := 8
const R_LG := 12


static func _sb(bg: Color, border: Color, radius: int, pad: int, bw := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	return s


## カードの面（level 0=面, 1=一段上げ）。
static func card_style(level := 0) -> StyleBoxFlat:
	var bg := SURFACE if level == 0 else SURFACE_2
	return _sb(bg, LINE, R_MD, SP_3)


## アクセント枠のカード（店番ハイライト等）。
static func card_accent(tint: Color) -> StyleBoxFlat:
	var s := _sb(Color(tint.r * 0.16, tint.g * 0.14, tint.b * 0.1, 0.92),
			Color(tint.r, tint.g, tint.b, 0.55), R_MD, SP_3)
	return s


## テーマ（ボタン3系統・タブ・入力・パネル）を組む。
static func theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = T_BODY

	# ボタン: ゴースト（既定）
	var ghost := _sb(Color(0.10, 0.16, 0.28, 0.9), LINE, R_SM, SP_2)
	var ghost_h := _sb(SURFACE_2, ACCENT_DIM, R_SM, SP_2)
	var ghost_d := _sb(Color(0.05, 0.08, 0.15, 0.7), Color(1, 1, 1, 0.08), R_SM, SP_2)
	th.set_stylebox("normal", "Button", ghost)
	th.set_stylebox("hover", "Button", ghost_h)
	th.set_stylebox("pressed", "Button", ghost_h)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_stylebox("disabled", "Button", ghost_d)
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color.WHITE)
	th.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.28))

	# パネル（PanelContainer 既定＝カード）
	th.set_stylebox("panel", "PanelContainer", card_style(0))

	# タブ
	var tab_sel := _sb(SURFACE_2, ACCENT, R_SM, SP_2)
	tab_sel.border_width_left = 0
	tab_sel.border_width_top = 0
	tab_sel.border_width_right = 0
	tab_sel.border_width_bottom = 2
	var tab_un := _sb(Color(0.05, 0.08, 0.15, 0.6), Color(0, 0, 0, 0), R_SM, SP_2)
	th.set_stylebox("tab_selected", "TabContainer", tab_sel)
	th.set_stylebox("tab_unselected", "TabContainer", tab_un)
	th.set_stylebox("tab_hovered", "TabContainer", tab_sel)
	th.set_stylebox("panel", "TabContainer", _sb(Color(0.02, 0.04, 0.10, 0.0), Color(0, 0, 0, 0), R_MD, SP_1, 0))
	th.set_color("font_selected_color", "TabContainer", Color.WHITE)
	th.set_color("font_unselected_color", "TabContainer", TEXT_2)
	th.set_constant("side_margin", "TabContainer", 0)

	# 入力欄
	var le := _sb(Color(0.05, 0.09, 0.18, 1), LINE, R_SM, SP_2)
	th.set_stylebox("normal", "LineEdit", le)
	th.set_color("font_color", "LineEdit", TEXT)
	th.set_color("font_placeholder_color", "LineEdit", TEXT_MUTE)
	return th


# ── ボタン3系統のスタイルを個別ノードへ適用 ──────────────────────────
static func as_primary(b: Button) -> Button:
	var n := _sb(ACCENT, Color(1, 1, 1, 0.0), R_SM, SP_3)
	var h := _sb(Color(0.6, 0.97, 1.0), Color(1, 1, 1, 0.0), R_SM, SP_3)  # 明るいシアン
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_color_override("font_color", Color("06121a"))       # シアン面の上の暗色
	b.add_theme_color_override("font_hover_color", Color("06121a"))
	b.add_theme_color_override("font_pressed_color", Color("040b10"))
	return b


static func as_danger(b: Button) -> Button:
	b.add_theme_color_override("font_color", DANGER)
	b.add_theme_color_override("font_hover_color", Color(1, 0.6, 0.65))
	return b


# ── 共有描画ヘルパー（_draw ベースのオーバーレイが委譲する唯一の実装） ──────
# home/dive/menu の各オーバーレイはローカルに同じ _panel/_txt/_bar を持っていた。
# その実体をここへ集約し、各画面は薄いラッパー（self を渡すだけ）から呼ぶ。
# ci＝描画先 CanvasItem（呼び出し元の Control を self で渡す）。

## 角丸パネル（塗り＋縁）。
static func panel(ci: CanvasItem, rect: Rect2, bg: Color, border: Color, radius := R_LG, bw := 1.5) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(int(bw))
	sb.set_corner_radius_all(int(radius))
	ci.draw_style_box(sb, rect)


## 任意のサイズ指定を型スケール5段（12/15/18/22/40）の最寄りへ丸める。
## 「描画される文字は必ず5段のどれか」をシステムとして保証する強制装置。
## 呼び出し側は DS.T_* を渡すのが正だが、生の数値でも自動でスケールへ吸着する。
static func snap_size(n: int) -> int:
	if n < 14:
		return T_MICRO    # 12
	if n < 17:
		return T_BODY     # 15
	if n < 20:
		return T_SUB      # 18
	if n < 31:
		return T_HEAD     # 22
	return T_DISPLAY      # 40


## 落ち影つきテキスト（可読性：1px のインク影）。サイズは型スケールへ吸着。
static func txt(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, col: Color,
		ha := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	var sz := snap_size(size)
	ci.draw_string(font, pos + Vector2(1, 1), s, ha, w, sz, INK)
	ci.draw_string(font, pos, s, ha, w, sz, col)


## 文字幅（中央寄せ計算用）。描画と同じく型スケールへ吸着させ整合を保つ。
static func tw(font: Font, s: String, size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, snap_size(size)).x


## 比率バー（地＋塗り）。ratio 0〜1。
static func bar(ci: CanvasItem, rect: Rect2, ratio: float, col: Color) -> void:
	panel(ci, rect, Color(0, 0, 0, 0.5), Color(1, 1, 1, 0.12), 3, 1)
	var w := rect.size.x * clampf(ratio, 0.0, 1.0)
	if w > 1.0:
		ci.draw_rect(Rect2(rect.position, Vector2(w, rect.size.y)), col)
