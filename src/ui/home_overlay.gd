class_name HomeOverlay
extends Control
## ホーム画面の 2D UI チロー。背後の HD-2D ジオラマ（黒猫飯店）の上に重ねる。
## 参照ホーム画面のレイアウト：トップバー / 依頼 / ガチャ / サイドアイコン /
## 今日のメニュー / 探索へ出発ポータル / 下部ナビ / 吹き出し。
## ※プロトタイプ表示用（内容は代表値）。実データは main.gd 側から流し込む想定。

const PANEL_BG := Color(0.05, 0.055, 0.10, 0.82)
const PANEL_BG2 := Color(0.08, 0.06, 0.12, 0.88)
const PINK := Color(1.0, 0.36, 0.72)
const CYAN := Color(0.35, 0.92, 1.0)
const PURPLE := Color(0.66, 0.4, 1.0)
const GOLD := Color(1.0, 0.82, 0.4)
const TEXT := Color(0.96, 0.95, 0.98)
const TEXT_DIM := Color(0.72, 0.74, 0.82)

var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


# ── 描画ヘルパー ──────────────────────────────────────────────
func _panel(rect: Rect2, bg: Color, border: Color, radius := 10.0, bw := 1.5) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(int(bw))
	sb.set_corner_radius_all(int(radius))
	draw_style_box(sb, rect)


func _txt(font: Font, pos: Vector2, s: String, size: int, col: Color, ha := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string(font, pos, s, ha, w, size, col)


## ネオン発光ラベル（影＋本体）。
func _neon(font: Font, pos: Vector2, s: String, size: int, col: Color) -> void:
	draw_string(font, pos + Vector2(0, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(col.r, col.g, col.b, 0.35))
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _icon_btn(font: Font, center: Vector2, r: float, label: String, col: Color) -> void:
	_panel(Rect2(center - Vector2(r, r), Vector2(r * 2, r * 2)), PANEL_BG2, col, r, 1.5)
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	_txt(font, center + Vector2(-w * 0.5, 6), label, 15, TEXT)


func _draw() -> void:
	var sz := size
	var font := get_theme_default_font()

	# ===== トップバー =====
	var bar_h := 56.0
	_panel(Rect2(8, 8, sz.x - 16, bar_h), PANEL_BG, Color(PINK.r, PINK.g, PINK.b, 0.5), 12)
	_neon(font, Vector2(22, 38), "黒猫飯店", 22, PINK)
	_txt(font, Vector2(132, 36), "店舗ランク 1B", 14, TEXT_DIM)
	# 右側リソース
	var rx := sz.x - 24
	for item in [["石 1,280", CYAN], ["金 12,840", GOLD], ["活 120/120", Color(0.6, 1.0, 0.9)]]:
		var s: String = item[0]
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		rx -= w + 18
		_txt(font, Vector2(rx, 36), s, 16, item[1])

	# ===== 左上：本日の依頼 =====
	var qy := bar_h + 18
	_panel(Rect2(8, qy, 232, 86), PANEL_BG, Color(GOLD.r, GOLD.g, GOLD.b, 0.4), 10)
	_txt(font, Vector2(20, qy + 24), "本日の依頼", 15, GOLD)
	_txt(font, Vector2(20, qy + 48), "質屋の試練に挑む", 14, TEXT, HORIZONTAL_ALIGNMENT_LEFT, 210)
	_txt(font, Vector2(20, qy + 72), "報酬  120石  +2,400G", 13, TEXT_DIM)

	# ===== 右上：ピックアップ召喚（ガチャ） =====
	_panel(Rect2(sz.x - 200, qy, 192, 70), PANEL_BG2, Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.55), 10)
	_txt(font, Vector2(sz.x - 188, qy + 24), "ピックアップ召喚", 13, PURPLE)
	_neon(font, Vector2(sz.x - 188, qy + 50), "後悔のフユキ ↑UP", 14, PINK)

	# ===== 右サイド：アイコン列 =====
	var iy := qy + 110
	for it in [["日課", CYAN], ["任務", PINK], ["催事", GOLD]]:
		_icon_btn(font, Vector2(sz.x - 36, iy), 26, it[0], it[1])
		iy += 64

	# ===== 左サイド：占い / 編成 =====
	_icon_btn(font, Vector2(40, sz.y * 0.46), 28, "占い", PURPLE)
	_icon_btn(font, Vector2(40, sz.y * 0.46 + 70), 28, "編成", CYAN)

	# ===== 吹き出し（店番のセリフ） =====
	_speech(font, Vector2(sz.x * 0.34, sz.y * 0.32), "いらっしゃいませ！")
	_speech(font, Vector2(sz.x * 0.62, sz.y * 0.5), "次の探索、どこへ？")

	# ===== 下部：今日のメニュー =====
	var my := sz.y - 230
	_panel(Rect2(8, my, 236, 150), PANEL_BG, Color(GOLD.r, GOLD.g, GOLD.b, 0.4), 10)
	_txt(font, Vector2(20, my + 24), "今日のメニュー", 15, GOLD)
	var menu := [["麻婆豆腐", "+24"], ["黒猫ラーメン", "+18"], ["焼売のジャズ", "+12"], ["メンマみそ", "+15"]]
	var ly := my + 48
	for m in menu:
		_txt(font, Vector2(22, ly), String(m[0]), 14, TEXT)
		_txt(font, Vector2(180, ly), String(m[1]), 14, Color(0.6, 1.0, 0.6))
		ly += 24
	_txt(font, Vector2(20, my + 144), "本日の売上  8,640G", 13, GOLD)

	# ===== 探索へ出発ポータル（右下） =====
	var pc := Vector2(sz.x - 86, sz.y - 150)
	var pr := 52.0 + 3.0 * sin(_t * 2.0)
	draw_circle(pc, pr + 8, Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.12))
	draw_circle(pc, pr, Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.22))
	draw_arc(pc, pr, _t * 1.5, _t * 1.5 + TAU * 0.75, 40, PURPLE, 3.0)
	draw_arc(pc, pr * 0.62, -_t * 2.0, -_t * 2.0 + TAU * 0.6, 32, PINK, 2.5)
	draw_circle(pc, pr * 0.34, Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.8))
	var dw := font.get_string_size("探索へ出発", HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	_neon(font, pc + Vector2(-dw * 0.5, pr + 26), "探索へ出発", 15, PINK)

	# ===== 下部ナビ =====
	var nav_h := 60.0
	var ny := sz.y - nav_h
	_panel(Rect2(0, ny, sz.x, nav_h), Color(0.03, 0.035, 0.07, 0.95), Color(PINK.r, PINK.g, PINK.b, 0.4), 0, 1)
	var tabs := ["ホーム", "キャラ", "持ち物", "記録", "図鑑", "設定"]
	var tw := sz.x / tabs.size()
	for i in tabs.size():
		var active := i == 0
		var c := PINK if active else TEXT_DIM
		var lw := font.get_string_size(tabs[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		if active:
			_panel(Rect2(i * tw + 8, ny + 8, tw - 16, nav_h - 16), Color(PINK.r, PINK.g, PINK.b, 0.14), Color(PINK.r, PINK.g, PINK.b, 0.5), 8)
		_txt(font, Vector2(i * tw + (tw - lw) * 0.5, ny + 38), tabs[i], 14, c)


## 角丸吹き出し（しっぽ付き）。
func _speech(font: Font, anchor: Vector2, text: String) -> void:
	var fs := 15
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pad := 10.0
	var bw := tw + pad * 2
	var bh := 30.0
	var r := Rect2(anchor.x - bw * 0.5, anchor.y - bh, bw, bh)
	_panel(r, Color(0.96, 0.96, 0.99, 0.94), Color(PINK.r, PINK.g, PINK.b, 0.7), 10)
	draw_colored_polygon(PackedVector2Array([
		Vector2(anchor.x - 6, anchor.y), Vector2(anchor.x + 6, anchor.y), Vector2(anchor.x, anchor.y + 9),
	]), Color(0.96, 0.96, 0.99, 0.94))
	_txt(font, Vector2(r.position.x + pad, anchor.y - 9), text, fs, Color(0.1, 0.08, 0.14))
