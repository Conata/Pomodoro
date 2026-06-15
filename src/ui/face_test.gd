class_name FaceTest
extends Control
## フォネムシーケンサー テスト画面。
## F6 でこのシーンを直接実行。テキストを入力して各キャラの口パクを確認する。

const CHARS := ["mil", "yuzuki", "muu", "kiriko"]

## プリセットセリフ [char_id, text]
const PRESETS := [
	["mil",    "店長。同期を開始します"],
	["yuzuki", "帰ったら炒飯な。崩れたやつでよけりゃ"],
	["muu",    "これ配信したら伸びるかな。…切り抜き班いないや"],
	["kiriko", "観測を開始する。良い夜だ"],
	["mil",    "記憶の整理をしています。あなたの注文は、全部覚えています"],
	["yuzuki", "ミルのやつ、また核心ついてくるんだよな"],
	["muu",    "あたしのこと、覚えててくれる人いるかな。…店長は？"],
	["kiriko", "死は切断。なら、繋ぎ直せる……理論上は"],
]

const CAM_W := 152
const CAM_H := 174

var _cams: Array[FaceCam] = []
var _sel_idx := 0
var _line_edit: LineEdit
var _char_btns: Array[Button] = []
var _timers: Array = []  # タイマー参照保持（GC対策）


func _ready() -> void:
	_build_ui()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.09))


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	# ── タイトル ──────────────────────────────
	var title := Label.new()
	title.text = "フォネムシーケンサー テスト"
	title.add_theme_color_override("font_color", Color(0.50, 0.82, 1.0))
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	# ── FaceCam ワイプ行 ──────────────────────
	var cam_row := HBoxContainer.new()
	cam_row.add_theme_constant_override("separation", 18)
	vbox.add_child(cam_row)

	for id: String in CHARS:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cam_row.add_child(col)

		var cam := FaceCam.new()
		cam.girl_id = id
		cam.flip_h  = bool(KuroData.GIRLS[id].get("flip", false))
		cam.custom_minimum_size = Vector2(CAM_W, CAM_H)
		cam.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cam.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
		col.add_child(cam)
		_cams.append(cam)

		var nm := Label.new()
		nm.text = _char_name(id)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.add_theme_color_override("font_color", Color(0.75, 0.90, 1.0))
		nm.add_theme_font_size_override("font_size", 13)
		col.add_child(nm)

	# ── キャラ選択 ──────────────────────────────
	var sel_row := HBoxContainer.new()
	sel_row.add_theme_constant_override("separation", 8)
	vbox.add_child(sel_row)

	var sl := Label.new()
	sl.text = "話させる："
	sl.add_theme_color_override("font_color", Color(0.60, 0.78, 1.0))
	sel_row.add_child(sl)

	for i in CHARS.size():
		var btn := Button.new()
		btn.text = _char_name(CHARS[i])
		btn.toggle_mode = true
		btn.set_pressed_no_signal(i == 0)
		var ii := i
		btn.pressed.connect(func(): _on_select(ii))
		_char_btns.append(btn)
		sel_row.add_child(btn)

	# ── テキスト入力 ────────────────────────────
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 8)
	vbox.add_child(input_row)

	_line_edit = LineEdit.new()
	_line_edit.placeholder_text = "セリフを入力して Enter、または「話す」"
	_line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line_edit.text_submitted.connect(_on_submit)
	input_row.add_child(_line_edit)

	var speak_btn := Button.new()
	speak_btn.text = "話す"
	speak_btn.pressed.connect(func(): _on_submit(_line_edit.text))
	input_row.add_child(speak_btn)

	var all_btn := Button.new()
	all_btn.text = "全員"
	all_btn.pressed.connect(_on_speak_all)
	input_row.add_child(all_btn)

	# ── 表情ボタン行 ─────────────────────────────
	var expr_row := HBoxContainer.new()
	expr_row.add_theme_constant_override("separation", 6)
	vbox.add_child(expr_row)

	var el := Label.new()
	el.text = "表情："
	el.add_theme_color_override("font_color", Color(0.60, 0.78, 1.0))
	expr_row.add_child(el)

	for pair in [["中立", "neutral"], ["笑顔", "smile"], ["驚き", "surprise"], ["集中", "calm"], ["食事ON/OFF", "eat"]]:
		var eb := Button.new()
		eb.text = pair[0]
		var expr: String = pair[1]
		eb.pressed.connect(func(): _on_expr(expr))
		expr_row.add_child(eb)

	# ── セパレーター ─────────────────────────────
	vbox.add_child(HSeparator.new())

	# ── プリセット ──────────────────────────────
	var pl := Label.new()
	pl.text = "プリセット"
	pl.add_theme_color_override("font_color", Color(0.60, 0.78, 1.0))
	vbox.add_child(pl)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(grid)

	for p: Array in PRESETS:
		var pb := Button.new()
		pb.text = "[%s] %s" % [_char_name(p[0]), p[1]]
		pb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pb.clip_text = true
		var cid: String = p[0]
		var txt: String = p[1]
		pb.pressed.connect(func(): _on_preset(cid, txt))
		grid.add_child(pb)


# ── ヘルパー ────────────────────────────────────

func _char_name(id: String) -> String:
	return String(KuroData.GIRLS[id]["name"]) if KuroData.GIRLS.has(id) else id


func _on_select(idx: int) -> void:
	_sel_idx = idx
	for i in _char_btns.size():
		_char_btns[i].set_pressed_no_signal(i == idx)


func _on_submit(text: String) -> void:
	var t := text.strip_edges()
	if t.is_empty():
		return
	_do_speak(_cams[_sel_idx], t)


func _on_speak_all() -> void:
	var t := _line_edit.text.strip_edges()
	if t.is_empty():
		return
	for cam in _cams:
		_do_speak(cam, t)


func _on_preset(char_id: String, text: String) -> void:
	_line_edit.text = text
	var idx := CHARS.find(char_id)
	if idx >= 0:
		_on_select(idx)
	_do_speak(_cams[maxi(idx, 0)], text)


func _on_expr(expr: String) -> void:
	var cam := _cams[_sel_idx]
	if expr == "eat":
		cam.eating = not cam.eating
	elif expr == "neutral":
		cam.set_expression("neutral", 0.0)
	else:
		cam.set_expression(expr, 2.5)


func _do_speak(cam: FaceCam, text: String) -> void:
	cam.start_speech(text)
	cam.speaking = true
	var dur := clampf(text.length() * 0.16, 1.2, 8.0)
	var timer := get_tree().create_timer(dur)
	_timers.append(timer)
	timer.timeout.connect(func():
		cam.speaking = false
		_timers.erase(timer)
	)
