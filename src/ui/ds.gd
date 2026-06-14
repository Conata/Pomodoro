class_name DS
extends RefCounted
## 黒猫飯店 デザインシステム — 唯一の真実（single source of truth）。
## Vignelli の規律（型は少なく・グリッド・識別色・余白で語る）を、
## リファレンスのダークネオン美学に翻訳したトークンとコンポーネント工場。
## UI スクリプトはすべてここから色・型・間隔・スタイルを引く。
## docs/DESIGN_SYSTEM.md と対で維持すること。

# ── 色（深夜喫茶×オカルト×温かい居場所。識別色＝暖炉オレンジ） ──────────
# 指定パレット。3軸＝オレンジ(店)/ミント(ポモドーロ)/紫(キリコ)。
# 詳細・モード差し色・キリコ専用色は src/ui/ui_theme.gd(UIKit) を参照。
const BG := Color("151515")          # 画面の地（深夜の黒）
const SURFACE := Color("222222")     # 面（店内の影）
const SURFACE_2 := Color("2e2e2e")   # 面・押下/選択
const LINE := Color("3a2a20b3")      # 罫・縁（木製家具・α0.7）
const TEXT := Color("f5f3ee")        # 本文（真っ白を避ける）
const TEXT_2 := Color("b8b8b8")      # 副文
const TEXT_MUTE := Color("707070")   # 注記/無効
const ACCENT := Color("e6a15a")      # 識別色（暖炉オレンジ＝店）
const ACCENT_DIM := Color("e6a15a80")
const WARM := Color("e6a15a")        # 店番・看板の暖色
const DANGER := Color("e05a5a")      # 切断・撤退
const SUCCESS := Color("6fd37d")     # 収穫・廃材

# ── 型（5段。見出し≒2×本文。これ以上増やさない） ──────────────────────
const T_MICRO := 14
const T_BODY := 19
const T_SUB := 24
const T_HEAD := 38
const T_DISPLAY := 54

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
	var h := _sb(Color("f4b86e"), Color(1, 1, 1, 0.0), R_SM, SP_3)  # 明るい暖炉オレンジ
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_color_override("font_color", Color("231708"))       # オレンジ面の上の暗色
	b.add_theme_color_override("font_hover_color", Color("231708"))
	b.add_theme_color_override("font_pressed_color", Color("160f05"))
	return b


static func as_danger(b: Button) -> Button:
	b.add_theme_color_override("font_color", DANGER)
	b.add_theme_color_override("font_hover_color", Color(1, 0.6, 0.65))
	return b
