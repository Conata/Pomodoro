class_name TalkView
extends Control
## 会話シーン（VNレイヤー）。Rain98 系の文法：
## 青一色の画面、雨、白の斜めバンドに黒文字の名前、行送りはタップ。
## 選択肢はアウトラインの白枠ボックス2つ。

## 汎用シーンプレイヤー。会話・イベント・チュートリアルを同じ仕組みで再生する。
## scene = {"title":見出し, "lines":[[who,text]...], 任意で "a"/"b"（2択）}。
## who: "g"=話者, "*"=地の文（雨/行動）。finished は meta を返すので
## 呼び出し側が文脈（会話完了/イベント既読など）を処理する。
signal finished(meta: Dictionary)

const FRAME_DIR := "res://assets/third_party/dungeon/frames/"

var girl := ""          # 立ち絵＆名前の話者
var scene_data := {}
var queue: Array = []  # [[who, text], ...]
var picked := false
var pulse := 0.0
var _meta := {}
var _tex_cache := {}

var choice_a: Button
var choice_b: Button


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	choice_a = _mk_choice()
	choice_b = _mk_choice()
	choice_a.pressed.connect(_on_choice.bind("a"))
	choice_b.pressed.connect(_on_choice.bind("b"))


func _mk_choice() -> Button:
	var b := Button.new()
	b.visible = false
	b.add_theme_font_size_override("font_size", DS.T_SUB)
	var sb := DS._sb(Color(DS.SURFACE_2.r, DS.SURFACE_2.g, DS.SURFACE_2.b, 0.9), DS.ACCENT, DS.R_SM, DS.SP_3, 2)
	sb.skew = Vector2(-0.12, 0.0)  # Rain98 の斜めバンド
	b.add_theme_stylebox_override("normal", sb)
	var sb2 := sb.duplicate()
	sb2.bg_color = DS.ACCENT
	b.add_theme_stylebox_override("hover", sb2)
	b.add_theme_stylebox_override("pressed", sb2)
	b.add_theme_color_override("font_color", DS.TEXT)
	b.add_theme_color_override("font_hover_color", Color(0.02, 0.06, 0.12))
	add_child(b)
	return b


## 好感度会話（TalkData）を再生。
func start(p_girl: String, p_tier: int) -> void:
	play(TalkData.TALKS[p_girl][p_tier], p_girl, {"kind": "talk", "girl": p_girl, "tier": p_tier})


## 任意のシーンを再生（イベント/チュートリアル兼用）。
func play(scene: Dictionary, speaker: String, meta: Dictionary) -> void:
	girl = speaker
	scene_data = scene
	queue = scene["lines"].duplicate()
	picked = false
	_meta = meta
	visible = true
	_advance_to_current()


func _process(delta: float) -> void:
	pulse += delta
	if visible:
		queue_redraw()


func _advance_to_current() -> void:
	# 2択は scene に "a" があり、まだ選んでいない時だけ出す
	var show_choice: bool = queue.is_empty() and scene_data.has("a") and not picked
	choice_a.visible = show_choice
	choice_b.visible = show_choice
	if show_choice:
		choice_a.text = String(scene_data["a"]["t"])
		choice_b.text = String(scene_data["b"]["t"])
		var w := size.x - 120.0
		choice_a.position = Vector2(60, size.y * 0.42)
		choice_a.size = Vector2(w, 56)
		choice_b.position = Vector2(60, size.y * 0.42 + 72)
		choice_b.size = Vector2(w, 56)
	# 行が尽きて、選択肢が無い（or選択済み）なら終了
	if queue.is_empty() and (picked or not scene_data.has("a")):
		visible = false
		finished.emit(_meta)


func _on_choice(which: String) -> void:
	picked = true
	queue = scene_data[which]["r"].duplicate()
	choice_a.visible = false
	choice_b.visible = false
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var tapped: bool = (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed)
	if not tapped or choice_a.visible:
		return
	if not queue.is_empty():
		queue.pop_front()
	accept_event()
	_advance_to_current()


func _tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[path]


func _band(y: float, h: float, color: Color, skew_px: float = 26.0) -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(skew_px, y), Vector2(size.x, y),
		Vector2(size.x - skew_px, y + h), Vector2(0, y + h),
	]), color)


func _draw() -> void:
	var sz := size
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.025, 0.05, 0.16, 1.0))
	# 雨
	for i in 60:
		var speed := 380.0 + fposmod(i * 41.3, 260.0)
		var px := fposmod(i * 67.1 - pulse * speed * 0.2, sz.x + 40.0) - 20.0
		var py := fposmod(i * 113.7 + pulse * speed, sz.y + 30.0) - 15.0
		draw_line(Vector2(px, py), Vector2(px - 5, py + 18),
				Color(0.6, 0.82, 1.0, 0.08 + fposmod(i * 0.11, 0.1)), 1.2)
	# 立ち絵（等身の高いキャラ。ピクセルではなくポートレート）。
	# res://assets/portraits/<id>.png があればそれ、無ければシルエット。
	var g: Dictionary = KuroData.GIRLS[girl]
	var pw := sz.x * 0.62
	var ph := sz.y * 0.62
	Portrait.draw_into(self, girl, Rect2(sz.x - pw - 20.0, 10.0, pw, ph), pulse)
	var font := get_theme_default_font()
	# 名前の斜めバンド（白地に黒、Rain98 の名前演出）
	_band(sz.y * 0.62, 52.0, Color(0.94, 0.97, 1.0))
	draw_string(font, Vector2(46, sz.y * 0.62 + 38), "%s — %s" % [g["name"], scene_data.get("title", "")],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.03, 0.06, 0.15))
	# 台詞バンド
	_band(sz.y * 0.62 + 64.0, 150.0, Color(DS.BG.r, DS.BG.g, DS.BG.b, 0.95))
	draw_rect(Rect2(0, sz.y * 0.62 + 64.0, sz.x, 2), Color(DS.ACCENT.r, DS.ACCENT.g, DS.ACCENT.b, 0.7))
	if not queue.is_empty():
		var line: Array = queue[0]
		var who := String(line[0])
		var text := String(line[1])
		if who == "*":
			draw_string(font, Vector2(46, sz.y * 0.62 + 64.0 + 62),
					"…… " + text, HORIZONTAL_ALIGNMENT_LEFT, int(sz.x - 92), 22, Color(0.6, 0.78, 1.0, 0.8))
		else:
			draw_string(font, Vector2(46, sz.y * 0.62 + 64.0 + 62),
					"「" + text + "」", HORIZONTAL_ALIGNMENT_LEFT, int(sz.x - 92), 26, Color(0.93, 0.97, 1.0))
		var hint_a := 0.5 + 0.4 * sin(pulse * 4.0)
		draw_string(font, Vector2(sz.x - 70, sz.y * 0.62 + 64.0 + 132), "▼",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.6, 0.9, 1.0, hint_a))
	elif not picked:
		draw_string(font, Vector2(46, sz.y * 0.38), "── どう返す？",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.7, 0.88, 1.0, 0.8))
	# 黒猫（カウンターの端）
	draw_circle(Vector2(40, sz.y * 0.62 - 10), 9.0, Color(0.01, 0.02, 0.05))
	draw_circle(Vector2(34, sz.y * 0.62 - 20), 6.0, Color(0.01, 0.02, 0.05))
	var blink := fposmod(pulse, 4.0) < 3.7
	if blink:
		draw_circle(Vector2(33, sz.y * 0.62 - 21), 1.2, Color(0.55, 0.95, 0.7))
		draw_circle(Vector2(36, sz.y * 0.62 - 21), 1.2, Color(0.55, 0.95, 0.7))
