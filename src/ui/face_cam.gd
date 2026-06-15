class_name FaceCam
extends Control
## 配信者の「ワイプ（顔カメラ）」。表情シート（assets/generated/face/<id>/）があれば
## まばたき＋リップシンクで動く。無ければ立ち絵(assets/portraits/<id>.png)の頭部を
## 静止表示、それも無ければキャラ色のバストで代替する＝素材ゼロでも成立する。
##
## 表情フレーム命名（tools/slice_expressions.py の出力）:
##   <expr>_closed.png / <expr>_half.png / <expr>_open.png / <expr>_blink.png
##   expr 既定: neutral（他に smile/surprise/calm 等を set_expression で）
## TTS音声が入ったら _mouth_target を AudioServer のピークで駆動すれば本物の口パクになる。

var girl_id := ""
var speaking := false              # この配信者が今しゃべっているか（main/chrome が設定）
var expression := "neutral"
var show_label := true

var _tex_cache := {}
var _mouth := 0.0
var _mouth_target := 0.0
var _talk_t := 0.0
var _blink_t := 2.0
var _blinking := 0.0
var _pulse := 0.0


func _ready() -> void:
	clip_contents = true
	_blink_t = randf_range(2.0, 5.0)


func _process(delta: float) -> void:
	_pulse += delta
	# リップシンク（暫定：発話中は口を細かく開閉。TTS導入時は音声ピークに差し替え）
	if speaking:
		_talk_t += delta
		if _talk_t >= 0.08:
			_talk_t = 0.0
			_mouth_target = randf_range(0.15, 1.0)
	else:
		_mouth_target = 0.0
	_mouth = move_toward(_mouth, _mouth_target, delta * 12.0)
	# まばたき
	_blink_t -= delta
	if _blink_t <= 0.0:
		_blinking = 0.12
		_blink_t = randf_range(2.5, 5.5)
	if _blinking > 0.0:
		_blinking -= delta
	if visible:
		queue_redraw()


func _tex(name: String) -> Texture2D:
	if girl_id.is_empty():
		return null
	var path := "res://assets/generated/face/%s/%s.png" % [girl_id, name]
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[path]


func _portrait() -> Texture2D:
	if girl_id.is_empty():
		return null
	var path := "res://assets/portraits/%s.png" % girl_id
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[path]


## src（ピクセル矩形）を dst にアスペクト維持で隙間なく敷く（COVER）。
func _draw_cover(tex: Texture2D, dst: Rect2, src: Rect2) -> void:
	var sa := src.size.x / maxf(src.size.y, 1.0)
	var da := dst.size.x / maxf(dst.size.y, 1.0)
	if sa > da:
		var nw := src.size.y * da
		src.position.x += (src.size.x - nw) * 0.5
		src.size.x = nw
	else:
		var nh := src.size.x / da
		src.position.y += (src.size.y - nh) * 0.5
		src.size.y = nh
	draw_texture_rect_region(tex, dst, src)


func _draw() -> void:
	var sz := size
	if sz.x < 4.0 or sz.y < 4.0:
		return
	# カメラ枠（暗背景＋ネオン縁）
	var accent: Color = KuroData.GIRLS[girl_id]["color"] if KuroData.GIRLS.has(girl_id) else Color(0.5, 0.8, 1.0)
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.04, 0.05, 0.09, 0.92))
	var inner := Rect2(2, 2, sz.x - 4, sz.y - 4)
	# 顔：表情フレーム > 立ち絵頭部 > キャラ色バスト
	var drew := false
	var mouth_name := "closed"
	if _mouth >= 0.6:
		mouth_name = "open"
	elif _mouth >= 0.2:
		mouth_name = "half"
	var frame_name := ("%s_blink" % expression) if _blinking > 0.0 else ("%s_%s" % [expression, mouth_name])
	var ftex := _tex(frame_name)
	if ftex == null and _blinking > 0.0:
		ftex = _tex("%s_closed" % expression)  # blink欠けは閉口で代用
	if ftex == null:
		ftex = _tex("%s_closed" % expression)
	if ftex != null:
		_draw_cover(ftex, inner, Rect2(Vector2.ZERO, ftex.get_size()))
		drew = true
	if not drew:
		var pf := _portrait()
		if pf != null:
			var ps := pf.get_size()
			_draw_cover(pf, inner, Rect2(0, 0, ps.x, ps.y * 0.42))  # 頭〜胸元
			drew = true
	if not drew:
		# 最終フォールバック：キャラ色のバスト＋頭文字
		draw_circle(Vector2(sz.x * 0.5, sz.y * 0.92), sz.x * 0.42, accent.darkened(0.2))
		draw_circle(Vector2(sz.x * 0.5, sz.y * 0.42), sz.x * 0.26, accent)
	# 枠線（発話中は明るく脈動）
	var glow := 0.5 + (0.4 * (0.5 + 0.5 * sin(_pulse * 6.0)) if speaking else 0.0)
	draw_rect(Rect2(Vector2.ZERO, sz), Color(accent.r, accent.g, accent.b, glow), false, 2.0)
	# 名前＋赤LIVEドット
	if show_label and KuroData.GIRLS.has(girl_id):
		var font := get_theme_default_font()
		var nm := String(KuroData.GIRLS[girl_id]["name"])
		draw_rect(Rect2(0, sz.y - 20, sz.x, 20), Color(0.03, 0.03, 0.06, 0.7))
		draw_circle(Vector2(10, sz.y - 10), 3.5, Color(1.0, 0.25, 0.3))
		draw_string(font, Vector2(20, sz.y - 6), nm, HORIZONTAL_ALIGNMENT_LEFT, sz.x - 24, 12,
				Color(0.92, 0.95, 1.0))
