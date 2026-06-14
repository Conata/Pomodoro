class_name UIKit
extends RefCounted
## 黒猫飯店 — 画像ベース(9-patch)UIテーマ。
## tools/gen_ui_kit.py が出力した assets/generated/ui/*.png を StyleBoxTexture 化する。
## 暫定の自家生成キット。後で Kenney「UI Pack: Sci-Fi/RPG Expansion」(CC0) 等へ
## 差し替えるときは、同名 PNG を置換するか DIR を差し替えるだけでよい（スロット共通）。
## 既存の DS（StyleBoxFlat・シアン系）は温存。こちらは暖色＝モックアップ準拠。

const DIR := "res://assets/generated/ui/"

# 文字色（暖色テーマ）。アンバーボタン上は暗色、本文はクリーム。
const INK := Color(0.92, 0.89, 0.83)
const INK_DIM := Color(0.66, 0.61, 0.52)
const ON_AMBER := Color(0.13, 0.09, 0.03)
const AMBER := Color(0.91, 0.63, 0.23)
const RED := Color(0.82, 0.23, 0.18)


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


# ── プログレスバー（HP/EP/汎用）を 9-patch で塗る ──────────────────────
## ProgressBar に背景＋指定色の fill を適用する。fill_tex: bar_hp / bar_ep / bar_amber
static func style_bar(bar: ProgressBar, fill_tex := "bar_amber") -> void:
	bar.add_theme_stylebox_override("background", _sb("bar_bg", 7))
	bar.add_theme_stylebox_override("fill", _sb(fill_tex, 7))


## 画面ルートに適用する Theme（ボタン3系統＋パネル＋タブ＋入力＋バー既定）。
static func theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 19

	# パネル（PanelContainer / Panel）
	th.set_stylebox("panel", "PanelContainer", panel_box())
	th.set_stylebox("panel", "Panel", panel_box())

	# ボタン（既定＝アンバー CTA）
	th.set_stylebox("normal", "Button", _sb("button", 18, 10))
	th.set_stylebox("hover", "Button", _sb("button_hover", 18, 10))
	th.set_stylebox("pressed", "Button", _sb("button_press", 18, 10))
	th.set_stylebox("disabled", "Button", _sb("button_disabled", 18, 10))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", ON_AMBER)
	th.set_color("font_hover_color", "Button", ON_AMBER)
	th.set_color("font_pressed_color", "Button", Color(0.08, 0.05, 0.0))
	th.set_color("font_disabled_color", "Button", Color(0.62, 0.58, 0.5))

	# 入力欄
	th.set_stylebox("normal", "LineEdit", inset_box(8))
	th.set_color("font_color", "LineEdit", INK)
	th.set_color("font_placeholder_color", "LineEdit", INK_DIM)

	# タブ
	th.set_stylebox("tab_selected", "TabContainer", _sb("row", 14, 8))
	th.set_stylebox("tab_unselected", "TabContainer", _sb("panel_inset", 22, 8))
	th.set_stylebox("tab_hovered", "TabContainer", _sb("row", 14, 8))
	th.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())
	th.set_color("font_selected_color", "TabContainer", AMBER)
	th.set_color("font_unselected_color", "TabContainer", INK_DIM)

	# プログレスバー既定
	th.set_stylebox("background", "ProgressBar", _sb("bar_bg", 7))
	th.set_stylebox("fill", "ProgressBar", _sb("bar_amber", 7))

	return th


# ── ボタンを朱(危険/撤退)系に上書き ────────────────────────────────────
static func as_danger(b: Button) -> void:
	b.add_theme_color_override("font_color", Color(1, 0.86, 0.82))
	b.add_theme_color_override("font_hover_color", Color.WHITE)


## ゴースト(地味)ボタン＝枠だけ。準備画面のサブ操作など。
static func as_ghost(b: Button) -> void:
	b.add_theme_stylebox_override("normal", inset_box(10))
	b.add_theme_stylebox_override("hover", row_box(10))
	b.add_theme_stylebox_override("pressed", row_box(10))
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
