class_name DiveOverlay
extends Control
## 潜航（戦闘）画面の 2D UI チロー。HD-2D の戦闘ステージ（パーティ手前・敵奥）の上に重ねる。
## 参照の戦闘画面：上＝プレイヤー情報/HP/クエスト/AUTO、下＝パーティHP/SPカード＋コマンド。
## ※プロトタイプ表示。タップで command_pressed を発火（main.gd/KuroSim 側で接続）。

signal command_pressed(id: String)

const PANEL_BG := Color(0.05, 0.055, 0.10, 0.84)
const PINK := Color(1.0, 0.36, 0.72)
const CYAN := Color(0.35, 0.92, 1.0)
const PURPLE := Color(0.66, 0.4, 1.0)
const GOLD := Color(1.0, 0.82, 0.4)
const HP_COL := Color(0.45, 0.9, 0.5)
const SP_COL := Color(0.4, 0.7, 1.0)
const TEXT := Color(0.96, 0.95, 0.98)
const TEXT_DIM := Color(0.72, 0.74, 0.82)

# パーティ（表示名・現HP・最大HP・現SP・最大SP）
const PARTY := [
	{"name": "ミル", "hp": 320, "mhp": 420, "sp": 80, "msp": 100},
	{"name": "ナース", "hp": 280, "mhp": 360, "sp": 60, "msp": 100},
	{"name": "キリコ", "hp": 300, "mhp": 400, "sp": 100, "msp": 100},
	{"name": "ドクター", "hp": 210, "mhp": 450, "sp": 70, "msp": 100},
]
const COMMANDS := [
	{"label": "攻撃", "sub": "通常攻撃", "col": Color(1.0, 0.5, 0.35), "id": "attack"},
	{"label": "スキル", "sub": "SP 20", "col": CYAN, "id": "skill"},
	{"label": "防御", "sub": "被ダメ軽減", "col": SP_COL, "id": "guard"},
	{"label": "アイテム", "sub": "道具を使う", "col": HP_COL, "id": "item"},
]

var _t := 0.0
var _hits: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var p: Vector2
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		p = event.position
	elif event is InputEventScreenTouch and event.pressed:
		p = event.position
	else:
		return
	for h in _hits:
		if (h["rect"] as Rect2).has_point(p):
			command_pressed.emit(String(h["id"]))
			accept_event()
			return


func _panel(rect: Rect2, bg: Color, border: Color, radius := 10.0, bw := 1.5) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(int(bw))
	sb.set_corner_radius_all(int(radius))
	draw_style_box(sb, rect)


func _txt(font: Font, pos: Vector2, s: String, size: int, col: Color, ha := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string(font, pos + Vector2(1, 1), s, ha, w, size, Color(0, 0, 0, 0.55))
	draw_string(font, pos, s, ha, w, size, col)


func _bar(rect: Rect2, ratio: float, col: Color) -> void:
	_panel(Rect2(rect.position, rect.size), Color(0, 0, 0, 0.5), Color(1, 1, 1, 0.12), 3, 1)
	var w := rect.size.x * clampf(ratio, 0.0, 1.0)
	draw_rect(Rect2(rect.position, Vector2(w, rect.size.y)), col)


func _draw() -> void:
	var sz := size
	var font := get_theme_default_font()
	_hits.clear()

	# ===== トップバー：プレイヤー情報 =====
	var bar_h := 64.0
	_panel(Rect2(8, 8, sz.x - 16, bar_h), PANEL_BG, Color(CYAN.r, CYAN.g, CYAN.b, 0.45), 12)
	_txt(font, Vector2(22, 32), "プレイヤー", 16, TEXT)
	_txt(font, Vector2(22, 54), "Lv.12", 15, GOLD)
	_bar(Rect2(112, 20, 180, 12), 1.0, HP_COL)
	_txt(font, Vector2(300, 32), "120 / 120", 14, TEXT_DIM)
	_bar(Rect2(112, 40, 180, 8), 0.63, Color(0.5, 0.85, 1.0))  # EXP
	# 右：AUTO / 倍速 / 一時停止
	var bx := sz.x - 20
	for it in [["||", "pause"], ["AUTO", "auto"], ["≫", "fast"]]:
		var w := font.get_string_size(it[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 16
		bx -= w + 8
		_hit(Rect2(bx, 16, w, 40), String(it[1]))
		_panel(Rect2(bx, 16, w, 40), Color(0.08, 0.06, 0.12, 0.9), Color(CYAN.r, CYAN.g, CYAN.b, 0.5), 8)
		_txt(font, Vector2(bx + 8, 42), String(it[0]), 16, CYAN)

	# ===== メインクエスト（左・トップ下） =====
	var qy := bar_h + 16
	_panel(Rect2(8, qy, 250, 44), Color(0.05, 0.05, 0.09, 0.7), Color(GOLD.r, GOLD.g, GOLD.b, 0.35), 8)
	_txt(font, Vector2(20, qy + 19), "メインクエスト", 13, GOLD)
	_txt(font, Vector2(20, qy + 38), "中央ゲートへ進む  0/1", 14, TEXT)

	# ===== 下部：パーティカード＋コマンド =====
	var foot_h := 240.0
	var fy := sz.y - foot_h
	_panel(Rect2(0, fy, sz.x, foot_h), Color(0.03, 0.035, 0.07, 0.92), Color(PINK.r, PINK.g, PINK.b, 0.35), 0, 1)

	# パーティカード（横4）
	var cy := fy + 12
	var cw := (sz.x - 24) / PARTY.size()
	for i in PARTY.size():
		var d: Dictionary = PARTY[i]
		var cx := 12 + i * cw
		_panel(Rect2(cx + 3, cy, cw - 6, 86), Color(0.08, 0.07, 0.12, 0.92), Color(PINK.r, PINK.g, PINK.b, 0.3), 8)
		_txt(font, Vector2(cx + 12, cy + 24), String(d["name"]), 15, TEXT)
		_txt(font, Vector2(cx + 12, cy + 44), "HP", 11, TEXT_DIM)
		_bar(Rect2(cx + 36, cy + 35, cw - 50, 9), float(d["hp"]) / float(d["mhp"]), HP_COL)
		_txt(font, Vector2(cx + 12, cy + 64), "SP", 11, TEXT_DIM)
		_bar(Rect2(cx + 36, cy + 55, cw - 50, 9), float(d["sp"]) / float(d["msp"]), SP_COL)

	# コマンド（2x2）
	var gy := cy + 98
	var gw := (sz.x - 24) / 2.0
	var gh := 56.0
	for i in COMMANDS.size():
		var c: Dictionary = COMMANDS[i]
		var gx := 12 + (i % 2) * gw
		var gyy := gy + (i / 2) * (gh + 8)
		var r := Rect2(gx + 4, gyy, gw - 8, gh)
		_hit(r, String(c["id"]))
		_panel(r, Color(c["col"].r * 0.2, c["col"].g * 0.18, c["col"].b * 0.22, 0.92), c["col"], 10, 2)
		_txt(font, Vector2(gx + 20, gyy + 26), String(c["label"]), 19, TEXT)
		_txt(font, Vector2(gx + 20, gyy + 46), String(c["sub"]), 12, TEXT_DIM)


func _hit(rect: Rect2, id: String) -> void:
	_hits.append({"rect": rect, "id": id})
