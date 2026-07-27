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
const DANGER := Color("e05a5a")      # 状態色・危険（切断・撤退・損）
const SUCCESS := Color("6fd37d")     # 状態色・成功（収穫・廃材・得）
const GOLD := Color(1.0, 0.82, 0.4)  # 状態色・獲得（所持金・値札）
const INK := Color("0a0812")         # 黒い板（見出しの地・反転面の文字）
const PAPER := Color("fbfaff")       # 白抜き（板の上の文字）

# ── 型（5段。DotGothic16 は16pxグリッド設計＝16の倍数だけを使う） ─────────
# 10〜15px は禁止（ドットが溶ける）。本文16／小見出し24／見出し32／数値48。
const T_MICRO := 16
const T_BODY := 16
const T_SUB := 24
const T_HEAD := 32
const T_DISPLAY := 48

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

# ── 面の形（全画面で1つ。斜めカットの平行四辺形＝P5流）────────────────
# 角丸と斜めカットの混在をやめ、「面はすべて傾いている」に寄せた。
# 傾き量を各描画点で決めると 5/8/10/12 と散らかるので、高さから1つの式で出す。
const SKEW_MIN := 5.0
const SKEW_MAX := 12.0


## 面の傾き（px）。高さに比例させ、上下限で頭打ちにする。
static func skew(h: float) -> float:
	return clampf(h * 0.18, SKEW_MIN, SKEW_MAX)


# ── ヘッダの資源表示（書式・色・ケースはここでだけ決める）──────────────
# 「DAY 12  金 1240  欠片 7」。ラベルは小さく灰・全大文字、数値は T_SUB。
# 有彩色は金だけ（獲得色）。ホームも経営もこの1つを呼ぶ＝同じ物が同じ形で出る。
const HUD_ITEMS := [["DAY", "day", false], ["金", "gold", true], ["欠片", "shards", false]]


## ヘッダ帯 bar の右詰めに資源を描く。fx は Kit.num の台帳、now は経過秒。
## 戻り値＝金の描画位置（「飛ぶ数値」の着地点に使う）。
static func draw_hud(ci: CanvasItem, font: Font, bar: Rect2, state: Dictionary,
		fx: Dictionary, now: float) -> Vector2:
	var y := bar.position.y + bar.size.y * 0.5 + float(T_SUB) * 0.34
	var items: Array = []
	var total := 0.0
	for e in HUD_ITEMS:
		var lbl := String(e[0])
		var key := String(e[1])
		var n: Dictionary = Kit.num(fx, "hud_" + key, float(int(state.get(key, 0))), now)
		var s := "%d" % int(round(float(n["v"])))
		var lw := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, T_MICRO).x
		var vw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, T_SUB).x
		items.append({"l": lbl, "s": s, "pop": float(n["pop"]), "lw": lw, "vw": vw, "gold": bool(e[2])})
		total += lw + float(SP_2) + vw + float(SP_5)
	var x := bar.end.x - float(SP_4) - total + float(SP_5)
	var gold_at := Vector2(x, y)
	for it in items:
		var lbl := String(it["l"])
		ci.draw_string_outline(font, Vector2(x, y), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, T_MICRO, 3,
				Color(0, 0, 0, 0.85))
		ci.draw_string(font, Vector2(x, y), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, T_MICRO, TEXT_MUTE)
		x += float(it["lw"]) + float(SP_2)
		if bool(it["gold"]):
			gold_at = Vector2(x, y)
		Kit.num_draw(ci, font, Vector2(x, y), String(it["s"]), T_SUB,
				GOLD if bool(it["gold"]) else PAPER, float(it["pop"]))
		x += float(it["vw"]) + float(SP_5)
	return gold_at


## 面の反転（選択＝ベタ板＋暗色の文字）で使う、地の上に置く文字色。
## as_primary() と同じ反転パターンを _draw 系の描画からも引けるようにする。
static func on(bg: Color) -> Color:
	var lum := bg.r * 0.299 + bg.g * 0.587 + bg.b * 0.114
	return INK if lum > 0.42 else PAPER


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
