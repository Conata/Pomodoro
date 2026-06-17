class_name ChibiTest
extends Control
## ChibiAnim ステートマシン テスト画面。
## F6 でこのシーンを直接実行。
## 4キャラのスプライトを並べ、ボタンでアニメーションパラメーターを切り替えて確認する。

const CHARS := ["mil", "yuzuki", "muu", "kiriko"]
const CHIBI_H := 160.0

# ── アニメーション状態プリセット（ボタン1つ = Unity の SetBool/SetFloat セット）──
# label: ボタンラベル, params: update_params() の引数
const PRESETS: Array[Dictionary] = [
	{"label": "idle",        "speed": 0.0, "combat": false, "hurt": false, "dead": false},
	{"label": "run",         "speed": 1.0, "combat": false, "hurt": false, "dead": false},
	{"label": "attack",      "speed": 0.0, "combat": true,  "hurt": false, "dead": false},
	{"label": "hurt",        "speed": 0.0, "combat": true,  "hurt": true,  "dead": false},
	{"label": "die",         "speed": 0.0, "combat": false, "hurt": false, "dead": true},
	{"label": "dash",        "speed": 0.0, "combat": false, "hurt": false, "dead": false, "dash": true},
	{"label": "jump",        "speed": 0.0, "combat": false, "hurt": false, "dead": false, "air": true},
	{"label": "double_jump", "speed": 0.0, "combat": false, "hurt": false, "dead": false, "air": true, "djump": true},
	{"label": "wall_slide",  "speed": 0.0, "combat": false, "hurt": false, "dead": false, "air": true, "wall": true},
	{"label": "climb",       "speed": 0.0, "combat": false, "hurt": false, "dead": false, "climb": true},
	{"label": "skill1",      "speed": 0.0, "combat": false, "hurt": false, "dead": false, "skill": 1},
	{"label": "skill2",      "speed": 0.0, "combat": false, "hurt": false, "dead": false, "skill": 2},
	{"label": "skill3",      "speed": 0.0, "combat": false, "hurt": false, "dead": false, "skill": 3},
	{"label": "acquire",     "speed": 0.0, "combat": false, "hurt": false, "dead": false, "acquire": true},
]

var _anims: Dictionary = {}     # char_id → ChibiAnim
var _tex_cache: Dictionary = {}
var _state_labels: Dictionary = {}  # char_id → Label（現在ステート表示）
var _path_labels: Dictionary = {}   # char_id → Label（読み込みパス表示）
var _preset_btns: Array[Button] = []
var _cur_preset: int = 0
var _canvas: Control            # スプライト描画専用 Control


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for id in CHARS:
		_anims[id] = ChibiAnim.new(id)
	_build_ui()
	_apply_preset(0)


func _process(delta: float) -> void:
	for anim: ChibiAnim in _anims.values():
		anim.tick(delta)
	# ステートラベル更新
	for id in CHARS:
		if _state_labels.has(id):
			var a: ChibiAnim = _anims[id]
			var total := a._get_frame_count(id, a.current_state())
			_state_labels[id].text = "%s  f%d/%d" % [a.current_state(), a._frame, total]
	if _canvas:
		_canvas.queue_redraw()


# ────────────────────────────────────────────────────────
# UI 構築
# ────────────────────────────────────────────────────────
func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# ── タイトル ──────────────────────────────────────────
	var title := Label.new()
	title.text = "ChibiAnim ステートマシン テスト"
	title.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0))
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	# ── スプライト描画エリア ────────────────────────────────
	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(0, CHIBI_H + 20)
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.draw.connect(_on_canvas_draw)
	vbox.add_child(_canvas)

	# ── キャラ名 + ステートラベル行 ──────────────────────────
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 0)
	vbox.add_child(name_row)

	for id in CHARS:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		name_row.add_child(col)

		var nm := Label.new()
		nm.text = _char_name(id)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.add_theme_color_override("font_color", KuroData.GIRLS[id]["color"])
		nm.add_theme_font_size_override("font_size", 14)
		col.add_child(nm)

		var sl := Label.new()
		sl.text = "idle  f0/0"
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.add_theme_color_override("font_color", Color(0.6, 0.9, 0.7))
		sl.add_theme_font_size_override("font_size", 11)
		col.add_child(sl)
		_state_labels[id] = sl

		# 読み込みパスをデバッグ表示（シートずれの特定に使う）
		var pl2 := Label.new()
		pl2.text = "..."
		pl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pl2.add_theme_color_override("font_color", Color(0.45, 0.5, 0.6))
		pl2.add_theme_font_size_override("font_size", 9)
		pl2.clip_text = true
		col.add_child(pl2)
		_path_labels[id] = pl2

	vbox.add_child(HSeparator.new())

	# ── プリセットボタン（Unity の Transition Trigger 相当）────────
	var pl := Label.new()
	pl.text = "アニメーション プリセット（ステートマシン パラメーター）"
	pl.add_theme_color_override("font_color", Color(0.6, 0.78, 1.0))
	pl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(pl)

	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(grid)

	for i in PRESETS.size():
		var p: Dictionary = PRESETS[i]
		var btn := Button.new()
		btn.text = p["label"]
		btn.toggle_mode = true
		btn.set_pressed_no_signal(i == 0)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ii := i
		btn.pressed.connect(func(): _apply_preset(ii))
		_preset_btns.append(btn)
		grid.add_child(btn)

	vbox.add_child(HSeparator.new())

	# ── ヒント ────────────────────────────────────────────
	var hint := Label.new()
	hint.text = "ヒント: スプライトがない状態は idle_f0 にフォールバック（Override Controller 的動作）"
	hint.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
	hint.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hint)


# ────────────────────────────────────────────────────────
# キャンバス描画（dive_view._draw_chibi と同じロジック）
# ────────────────────────────────────────────────────────
func _on_canvas_draw() -> void:
	var sz := _canvas.size
	var n := CHARS.size()
	var slot := sz.x / n
	var ground := sz.y - 8.0

	for i in n:
		var id: String = CHARS[i]
		var cx := slot * (i + 0.5)

		var anim: ChibiAnim = _anims[id]
		var path := anim.current_path()
		var tex := _load_tex(path)
		var used_path := path

		# フォールバック: 現フレームが存在しなければ idle_f0 を試す
		if tex == null:
			used_path = "res://assets/generated/sprites/%s/idle_f0.png" % id
			tex = _load_tex(used_path)

		# パスラベル更新（ファイル名のみ短縮表示）
		if _path_labels.has(id):
			var lbl: Label = _path_labels[id]
			if tex != null:
				var fname := used_path.get_file()
				var ts := tex.get_size()
				# シートずれ警告: 幅が高さの1.5倍超なら赤表示
				if ts.x > ts.y * 1.5:
					lbl.text = "⚠ %s (%dx%d)" % [fname, int(ts.x), int(ts.y)]
					lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
				else:
					lbl.text = "%s (%dx%d)" % [fname, int(ts.x), int(ts.y)]
					lbl.add_theme_color_override("font_color", Color(0.45, 0.5, 0.6))
			else:
				lbl.text = "NOT FOUND"
				lbl.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2))

		if tex == null:
			# テクスチャなし → キャラカラーの円で代替
			_canvas.draw_circle(Vector2(cx, ground - CHIBI_H * 0.5), 20.0, KuroData.GIRLS[id]["color"])
			continue

		var ts := tex.get_size()

		# シートずれ対策: 幅が高さの1.5倍超 = 横並びシートとみなし先頭1フレーム分を切り出す
		var src_rect: Rect2
		if ts.x > ts.y * 1.5:
			# 1フレーム幅をシート高さと同じとみなしてクロップ
			src_rect = Rect2(0, 0, ts.y, ts.y)
		else:
			src_rect = Rect2(Vector2.ZERO, ts)

		var sc := CHIBI_H / src_rect.size.y
		var dw := src_rect.size.x * sc
		var rect := Rect2(cx - dw * 0.5, ground - CHIBI_H, dw, CHIBI_H)

		# 輪郭線
		var ofs := maxf(1.0, sc * 0.5)
		var outline := Color(0.0, 0.0, 0.05, 0.7)
		for ov in [Vector2(ofs, 0), Vector2(-ofs, 0), Vector2(0, ofs), Vector2(0, -ofs)]:
			_canvas.draw_texture_rect_region(tex, Rect2(rect.position + ov, rect.size), src_rect, outline)
		_canvas.draw_texture_rect_region(tex, rect, src_rect, Color.WHITE)

		# 地面ライン
		_canvas.draw_line(Vector2(cx - dw * 0.5, ground), Vector2(cx + dw * 0.5, ground),
				Color(0.4, 0.5, 0.7, 0.4), 1.5)


func _load_tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[path]


# ────────────────────────────────────────────────────────
# プリセット適用（Unity の SetFloat/SetBool 一括呼び出し相当）
# ────────────────────────────────────────────────────────
func _apply_preset(idx: int) -> void:
	_cur_preset = idx
	for i in _preset_btns.size():
		_preset_btns[i].set_pressed_no_signal(i == idx)

	var p: Dictionary = PRESETS[idx]
	for id in CHARS:
		var anim: ChibiAnim = _anims[id]
		anim.update_params(
			float(p.get("speed", 0.0)),
			bool(p.get("combat", false)),
			bool(p.get("hurt", false)),
			bool(p.get("dead", false)),
			bool(p.get("air", false)),
			bool(p.get("djump", false)),
			bool(p.get("wall", false)),
			bool(p.get("climb", false)),
			bool(p.get("dash", false)),
			int(p.get("skill", 0)),
			bool(p.get("acquire", false)),
		)


func _char_name(id: String) -> String:
	return String(KuroData.GIRLS[id]["name"]) if KuroData.GIRLS.has(id) else id


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.09))
