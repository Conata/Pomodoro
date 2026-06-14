class_name UIKit
extends RefCounted
## 黒猫飯店 — 画像ベース(9-patch)UIテーマ ＋ パレット。
## テーマ＝「深夜喫茶 × オカルト × 温かい居場所」。UIは主役ではなく
## キャラと店を引き立てる"額縁"。3軸カラーで現在モードが一目で分かる：
##   オレンジ=店 / ミント=ポモドーロ / 紫=キリコ・精神世界。
##
## tools/gen_ui_kit.py が出力した assets/generated/ui/*.png を StyleBoxTexture 化。
## 後で Kenney(CC0) 等へ差し替えるときは同名 PNG を置換 or DIR 差替で済む。
## 既存 DS（シアン系・StyleBoxFlat）は温存。こちらが本テーマ。

const DIR := "res://assets/generated/ui/"

# ── パレット（Godot Theme 指定値） ──────────────────────────────────────
const BG := Color("151515")          # Background 深夜の黒
const PANEL := Color("222222")       # Panel 店内の影
const BORDER := Color("3A2A20")      # Border 木製家具
const PRIMARY := Color("E6A15A")     # 暖炉オレンジ（店/選択中/焚き火/評判上昇）
const SECONDARY := Color("69D2B0")   # ミント（ポモドーロ/成功/回復・MYOMYO共通色）
const ACCENT := Color("8E6BC7")      # 紫（オカルト/精神世界/キリコ）
const SUCCESS := Color("6FD37D")
const WARNING := Color("F2C14E")
const DANGER := Color("E05A5A")
const TEXT := Color("F5F3EE")        # 本文（真っ白は避ける）
const TEXT_MUTED := Color("B8B8B8")
const DISABLED := Color("707070")

# モード/場所の差し色
const WINDOW_NIGHT := Color("2A3550")  # 店の窓・夜の青
const CAMPFIRE := Color("FFB347")      # 焚き火
const SPARK := Color("FFD56B")         # 火花
const DUNGEON := Color("2B2D42")       # ダンジョン通常
const DUNGEON_OCCULT := Color("5B3A82")# ダンジョン・オカルト
const DUNGEON_BOSS := Color("A63D40")  # ボス

# キリコ専用（プレイヤーは色で覚える）
const KIRIKO := Color("CDB4DB")        # 薄紫
const KIRIKO_DANGER := Color("9D4EDD")
const KIRIKO_DEEP := Color("5A189A")

const ON_PRIMARY := Color("231708")    # オレンジ面の上の文字（暗色）


## テクスチャ存在チェック（未インポート/欠損時に DS へフォールバックさせる用）。
static func available() -> bool:
	return ResourceLoader.exists(DIR + "panel.png")


static func _sb(tex_name: String, tex_margin: int, content := -1) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(DIR + tex_name + ".png")
	sb.set_texture_margin_all(tex_margin)
	if content >= 0:
		sb.set_content_margin_all(content)
	return sb


# ── 個別ボックス（add_theme_stylebox_override 用） ──────────────────────
static func panel_box(content := 14) -> StyleBoxTexture:
	return _sb("panel", 22, content)

static func inset_box(content := 12) -> StyleBoxTexture:
	return _sb("panel_inset", 22, content)

static func bubble_box(content := 14) -> StyleBoxTexture:
	return _sb("bubble", 20, content)

static func row_box(content := 10) -> StyleBoxTexture:
	return _sb("row", 14, content)

static func topbar_box(content := 10) -> StyleBoxTexture:
	return _sb("topbar", 20, content)


# ── プログレスバー（HP=朱 / ポモドーロ=ミント / オカルト=紫 / 汎用=オレンジ） ──
## fill_tex: bar_danger / bar_mint / bar_purple / bar_primary
static func style_bar(bar: ProgressBar, fill_tex := "bar_primary") -> void:
	bar.add_theme_stylebox_override("background", _sb("bar_bg", 7))
	bar.add_theme_stylebox_override("fill", _sb(fill_tex, 7))


## 画面ルートに適用する Theme（控えめ＝額縁思想：既定ボタンはダークグレー）。
static func theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 19

	# パネル
	th.set_stylebox("panel", "PanelContainer", panel_box())
	th.set_stylebox("panel", "Panel", panel_box())

	# ボタン（既定＝ダークグレー。Primary は as_primary() で上書き）
	th.set_stylebox("normal", "Button", _sb("button", 18, 10))
	th.set_stylebox("hover", "Button", _sb("button_hover", 18, 10))
	th.set_stylebox("pressed", "Button", _sb("button_press", 18, 10))
	th.set_stylebox("disabled", "Button", _sb("button_disabled", 18, 10))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", TEXT_MUTED)
	th.set_color("font_disabled_color", "Button", DISABLED)

	# 入力欄
	th.set_stylebox("normal", "LineEdit", inset_box(8))
	th.set_color("font_color", "LineEdit", TEXT)
	th.set_color("font_placeholder_color", "LineEdit", TEXT_MUTED)

	# タブ（選択中＝オレンジ字）
	th.set_stylebox("tab_selected", "TabContainer", _sb("row", 14, 8))
	th.set_stylebox("tab_unselected", "TabContainer", _sb("panel_inset", 22, 8))
	th.set_stylebox("tab_hovered", "TabContainer", _sb("row", 14, 8))
	th.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())
	th.set_color("font_selected_color", "TabContainer", PRIMARY)
	th.set_color("font_unselected_color", "TabContainer", TEXT_MUTED)

	# プログレスバー既定（オレンジ）
	th.set_stylebox("background", "ProgressBar", _sb("bar_bg", 7))
	th.set_stylebox("fill", "ProgressBar", _sb("bar_primary", 7))

	# ラベル
	th.set_color("font_color", "Label", TEXT)
	return th


# ── ボタンの差し色バリエーション ──────────────────────────────────────
## Primary CTA（暖簾を出す等）＝暖炉オレンジ。
static func as_primary(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _sb("button_primary", 18, 10))
	b.add_theme_stylebox_override("hover", _sb("button_primary", 18, 10))
	b.add_theme_stylebox_override("pressed", _sb("button_press", 18, 10))
	b.add_theme_color_override("font_color", ON_PRIMARY)
	b.add_theme_color_override("font_hover_color", ON_PRIMARY)


## 集中を始める＝ポモドーロ＝ミント（Secondary）。
static func as_pomodoro(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _sb("button_mint", 18, 10))
	b.add_theme_stylebox_override("hover", _sb("button_mint", 18, 10))
	b.add_theme_stylebox_override("pressed", _sb("button_press", 18, 10))
	b.add_theme_color_override("font_color", Color("0c2a23"))
	b.add_theme_color_override("font_hover_color", Color("0c2a23"))


## 危険/撤退＝朱字。
static func as_danger(b: Button) -> void:
	b.add_theme_color_override("font_color", DANGER)
	b.add_theme_color_override("font_hover_color", Color.WHITE)


## キリコ関連＝薄紫字（プレイヤーは色で覚える）。
static func as_kiriko(b: Button) -> void:
	b.add_theme_color_override("font_color", KIRIKO)
	b.add_theme_color_override("font_hover_color", KIRIKO_DANGER)
