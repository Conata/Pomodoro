class_name ResultOverlay
extends Control
## 浮上後の夜の精算リザルト。三行精算＋箱開封リビール＋住民ストーリーを提示し、
## 「店に戻る」で翌朝のホームへ。main.gd が set_data() で結果を流し込む。
## 箱アイコン（assets/generated/box/<grade>.png）をここで初投入。

signal action_pressed(id: String)

const PINK := Color(1.0, 0.36, 0.72)
const CYAN := Color(0.35, 0.92, 1.0)
const PURPLE := Color(0.66, 0.4, 1.0)
const GOLD := Color(1.0, 0.82, 0.4)
const GREEN := Color(0.45, 0.9, 0.5)
const TEXT := Color(0.96, 0.95, 0.98)
const TEXT_DIM := Color(0.75, 0.76, 0.84)
const BG := Color(0.04, 0.04, 0.07, 1.0)

# set_data で main.gd から差し込む結果データ
var day := 1
var lines: Array = []          # 三行精算
var gold := 0                  # 夜の売上
var boxes: Array = []          # [{grade, text, kind}]
var story := ""                # 住民ストーリー（特注が売れた夜）
var summary: Dictionary = {}   # {floor, kills, mats, minutes, resyncs, disconnected}

var _t := 0.0
var _hits: Array = []
var _box_tex: Dictionary = {}  # grade -> Texture2D（キャッシュ）


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)


func set_data(d: Dictionary) -> void:
	for k in d:
		if k in self:
			set(k, d[k])
	_t = 0.0
	queue_redraw()


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
			action_pressed.emit(String(h["id"]))
			accept_event()
			return


func _box_texture(grade: int) -> Texture2D:
	if not _box_tex.has(grade):
		var path := "res://assets/generated/box/%d.png" % grade
		_box_tex[grade] = load(path) if ResourceLoader.exists(path) else null
	return _box_tex[grade]


func _panel(rect: Rect2, bg: Color, border: Color, radius := 10.0, bw := 1.5) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(int(bw))
	sb.set_corner_radius_all(int(radius))
	draw_style_box(sb, rect)


func _txt(font: Font, pos: Vector2, s: String, size: int, col: Color, ha := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string(font, pos + Vector2(1, 1), s, ha, w, size, Color(0, 0, 0, 0.6))
	draw_string(font, pos, s, ha, w, size, col)


func _kind_col(kind: String) -> Color:
	match kind:
		"recipe": return CYAN
		"equip": return GOLD
		"shard": return PURPLE
		"invite": return PINK
		_: return GOLD


func _draw() -> void:
	var sz := size
	var font := get_theme_default_font()
	_hits.clear()
	draw_rect(Rect2(Vector2.ZERO, sz), BG)

	var disconnected: bool = bool(summary.get("disconnected", false))
	var y := 44.0

	# ヘッダー
	var head := "Day %d ― 切断された夜" % day if disconnected else "Day %d ― 夜の精算" % day
	_txt(font, Vector2(24, y), head, 24, PINK if not disconnected else Color(1.0, 0.45, 0.45))
	y += 14
	_txt(font, Vector2(24, y + 18), "＋%d G" % gold, 30, GOLD)
	y += 56

	# 収穫サマリ
	if not summary.is_empty():
		var sm := "B%dF到達 ・ 撃破%d ・ 素材+%d ・ %d分" % [
			int(summary.get("floor", 0)) + 1, int(summary.get("kills", 0)),
			int(summary.get("mats", 0)), int(round(float(summary.get("minutes", 0.0))))]
		if int(summary.get("resyncs", 0)) > 0:
			sm += " ・ 再同期%d回" % int(summary["resyncs"])
		_txt(font, Vector2(24, y), sm, 14, TEXT_DIM)
		y += 28

	# 三行精算
	_panel(Rect2(16, y, sz.x - 32, 8 + lines.size() * 52), Color(0.06, 0.06, 0.1, 0.92), Color(PINK.r, PINK.g, PINK.b, 0.4), 12)
	y += 18
	for ln in lines:
		_txt(font, Vector2(28, y + 14), String(ln), 16, TEXT, HORIZONTAL_ALIGNMENT_LEFT, sz.x - 56)
		y += 52
	y += 14

	# 箱開封リビール
	if not boxes.is_empty():
		_txt(font, Vector2(24, y), "開封 ― %d個の箱" % boxes.size(), 17, GOLD)
		y += 14
		var shown := mini(boxes.size(), 8)
		for i in shown:
			var b: Dictionary = boxes[i]
			var reveal := clampf((_t - 0.15 * i) / 0.3, 0.0, 1.0)   # 1個ずつ順にフェードイン
			if reveal <= 0.02:
				continue
			var r := Rect2(16, y, sz.x - 32, 50)
			var grade := int(b.get("grade", 0))
			var gcol := KuroData.equip_grade_color(mini(grade + 2, 6))
			_panel(r, Color(0.06, 0.06, 0.09, 0.9 * reveal), Color(gcol.r, gcol.g, gcol.b, 0.45 * reveal), 9)
			# 箱アイコン
			var tex := _box_texture(grade)
			if tex != null:
				draw_texture_rect(tex, Rect2(r.position.x + 8, y + 7, 36, 36), false, Color(1, 1, 1, reveal))
			else:
				_txt(font, Vector2(r.position.x + 12, y + 32), KuroData.BOX_NAMES[grade], 13, Color(gcol.r, gcol.g, gcol.b, reveal))
			var kcol := _kind_col(String(b.get("kind", "")))
			_txt(font, Vector2(r.position.x + 54, y + 31), String(b.get("text", "")), 14,
					Color(kcol.r, kcol.g, kcol.b, reveal), HORIZONTAL_ALIGNMENT_LEFT, sz.x - 32 - 64)
			y += 56
		if boxes.size() > shown:
			_txt(font, Vector2(24, y), "…他 %d個" % (boxes.size() - shown), 13, TEXT_DIM)
			y += 24
		y += 6

	# 住民ストーリー（特注が売れた夜の永続バフ）
	if story != "":
		var sh := 16 + ceili(float(story.length()) / 22.0) * 24
		_panel(Rect2(16, y, sz.x - 32, sh), Color(0.09, 0.05, 0.12, 0.92), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.55), 12)
		_txt(font, Vector2(28, y + 26), story, 14, Color(0.9, 0.82, 1.0), HORIZONTAL_ALIGNMENT_LEFT, sz.x - 56)
		y += sh + 12

	# 店に戻るボタン（最下部固定）
	var bw2 := 280.0
	var btn := Rect2((sz.x - bw2) * 0.5, sz.y - 84, bw2, 54)
	var pulse := 0.5 + 0.5 * sin(_t * 2.5)
	_panel(btn, Color(PINK.r * 0.22, PINK.g * 0.16, PINK.b * 0.24, 0.96),
			Color(PINK.r, PINK.g, PINK.b, 0.6 + 0.3 * pulse), 16, 2.0)
	var bl := "▶  店に戻る（翌朝へ）"
	var blw := font.get_string_size(bl, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
	_txt(font, Vector2(btn.position.x + (bw2 - blw) * 0.5, btn.position.y + 34), bl, 19, TEXT)
	_hits.append({"rect": btn, "id": "continue"})
