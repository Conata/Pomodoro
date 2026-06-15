class_name Portrait
extends RefCounted
## 高解像度キャラ表示。ストーリー/ステータスではピクセルスプライトではなく
## 「等身の高いキャラ」を出す（MIDNIGHT VIDEO 系の暗がり＋ネオンの立ち絵）。
##
## 本物の立ち絵が用意できたら res://assets/portraits/<id>.png を置くだけで
## 自動的に差し替わる（draw_into が override 画像を優先）。それまでは
## キャラ色のシルエット＋光る瞳でムーディに描く。

const ART_DIR := "res://assets/portraits/"

# キャラ別の見た目パラメータ（髪型・色・瞳）。本物の art が来るまでの指標。
const LOOK := {
	"mil": {"accent": Color(0.55, 0.8, 1.0), "eye": Color(0.5, 0.95, 1.0),
		"hair": Color(0.20, 0.34, 0.52), "style": "long", "warm": false},
	"yuzuki": {"accent": Color(1.0, 0.62, 0.4), "eye": Color(1.0, 0.72, 0.4),
		"hair": Color(0.42, 0.26, 0.18), "style": "ponytail", "warm": true},
	"muu": {"accent": Color(1.0, 0.6, 0.85), "eye": Color(1.0, 0.6, 0.85),
		"hair": Color(0.46, 0.24, 0.4), "style": "twintail", "warm": true},
	"kiriko": {"accent": Color(0.72, 0.62, 1.0), "eye": Color(0.78, 0.55, 1.0),
		"hair": Color(0.26, 0.2, 0.4), "style": "hood", "warm": false},
	# NPC：依頼人キリコ（薄紫・フード。プレイヤーは色で覚える）
	"kiriko_npc": {"accent": Color(0.80, 0.70, 0.86), "eye": Color(0.62, 0.31, 0.87),
		"hair": Color(0.35, 0.10, 0.60), "style": "hood", "warm": false},
	# 匿名の来店客（店の賑わい用・無個性なグレー）
	"guest": {"accent": Color(0.58, 0.60, 0.66), "eye": Color(0.85, 0.80, 0.70),
		"hair": Color(0.22, 0.22, 0.26), "style": "short", "warm": false},
	# 特注レシピ常連
	"tao": {"accent": Color(0.78, 0.66, 0.43), "eye": Color(0.92, 0.80, 0.60),
		"hair": Color(0.88, 0.88, 0.88), "style": "long", "warm": true},
	"nono": {"accent": Color(0.49, 0.91, 0.85), "eye": Color(0.40, 0.98, 0.90),
		"hair": Color(0.25, 0.42, 0.56), "style": "short", "warm": false},
	"err404": {"accent": Color(0.69, 0.69, 0.72), "eye": Color(0.55, 0.55, 0.62),
		"hair": Color(0.15, 0.15, 0.18), "style": "hood", "warm": false},
	# 精神外科医（深緑・グレー瞳・長髪）
	"doctor": {"accent": Color(0.45, 0.90, 0.70), "eye": Color(0.30, 0.78, 0.55),
		"hair": Color(0.10, 0.22, 0.16), "style": "long", "warm": false},
	# 医療支援AI（ミントグリーン・白衣）
	"nurse": {"accent": Color(0.60, 0.98, 0.88), "eye": Color(0.50, 0.94, 0.80),
		"hair": Color(0.22, 0.52, 0.45), "style": "short", "warm": false},
}

static var _cache := {}


static func art_for(id: String) -> Texture2D:
	if not _cache.has(id):
		var path := ART_DIR + id + ".png"
		_cache[id] = load(path) if ResourceLoader.exists(path) else null
	return _cache[id]


## rect 内にキャラを描く。t はアニメ用時間（瞬き・リムの揺らぎ）。
## blink=true で瞬きあり。本物 art があればそれを KEEP_ASPECT で描く。
static func draw_into(ci: CanvasItem, id: String, rect: Rect2, t: float) -> void:
	var art := art_for(id)
	if art != null:
		var asz := art.get_size()
		var scale := minf(rect.size.x / asz.x, rect.size.y / asz.y)
		var dsz := asz * scale
		# VN立ち絵は下揃え（足元をnamebandに合わせる）
		var pos := Vector2(rect.position.x + (rect.size.x - dsz.x) * 0.5,
				rect.position.y + rect.size.y - dsz.y)
		ci.draw_texture_rect(art, Rect2(pos, dsz), false)
		return
	_draw_silhouette(ci, id, rect, t)


## キャラ色のシルエット立ち絵（暗がりに光る瞳）。
static func _draw_silhouette(ci: CanvasItem, id: String, rect: Rect2, t: float) -> void:
	var look: Dictionary = LOOK.get(id, LOOK["mil"])
	var accent: Color = look["accent"]
	var hair: Color = look["hair"]
	var style: String = look["style"]
	var cx := rect.position.x + rect.size.x * 0.5
	var w := rect.size.x
	var h := rect.size.y
	var top := rect.position.y

	# 背景：頭の後ろにアクセント色のソフトグロー
	var glow_c := Color(accent.r, accent.g, accent.b, 0.10)
	for i in range(5, 0, -1):
		ci.draw_circle(Vector2(cx, top + h * 0.34), w * 0.10 * i, Color(accent.r, accent.g, accent.b, 0.03))
	ci.draw_circle(Vector2(cx, top + h * 0.34), w * 0.30, glow_c)

	var skin := Color(0.10, 0.12, 0.18)  # 影に沈んだ肌
	var skin_lit := Color(0.16, 0.19, 0.27)
	var unit := h * 0.01

	# 肩（丸い台形シルエット）
	var sh_top := top + h * 0.62
	var sh_w := w * 0.78
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(cx - sh_w * 0.5, top + h),
		Vector2(cx - sh_w * 0.42, sh_top),
		Vector2(cx + sh_w * 0.42, sh_top),
		Vector2(cx + sh_w * 0.5, top + h),
	]), Color(0.06, 0.08, 0.14))
	# 服のリムライト（左肩）
	ci.draw_line(Vector2(cx - sh_w * 0.42, sh_top), Vector2(cx - sh_w * 0.5, top + h),
			Color(accent.r, accent.g, accent.b, 0.5), 2.0)

	# 首
	ci.draw_rect(Rect2(cx - w * 0.07, top + h * 0.5, w * 0.14, h * 0.14), skin)

	# 頭（楕円）
	var head_c := Vector2(cx, top + h * 0.34)
	var head_r := Vector2(w * 0.20, h * 0.17)
	_draw_ellipse(ci, head_c, head_r, skin, 28)
	# 頬のわずかな受け光（右）
	_draw_ellipse(ci, head_c + Vector2(head_r.x * 0.45, head_r.y * 0.2), head_r * 0.5, Color(skin_lit.r, skin_lit.g, skin_lit.b, 0.6), 20)

	# 髪（後ろ）
	_draw_hair_back(ci, head_c, head_r, hair, style, h)
	# 髪（前髪）
	_draw_hair_front(ci, head_c, head_r, hair, accent, style)

	# 瞳：暗がりに光る（このゲームの顔）
	var blink := fposmod(t, 4.6) < 4.45
	var eye_dy := head_r.y * 0.12
	var eye_dx := head_r.x * 0.42
	var eye: Color = look["eye"]
	for s in [-1.0, 1.0]:
		var ec := head_c + Vector2(s * eye_dx, eye_dy)
		if blink:
			# グロー
			ci.draw_circle(ec, unit * 1.4, Color(eye.r, eye.g, eye.b, 0.35))
			_draw_ellipse(ci, ec, Vector2(unit * 0.9, unit * 1.25), eye, 14)
			ci.draw_circle(ec + Vector2(-unit * 0.2, -unit * 0.3), unit * 0.32, Color(1, 1, 1, 0.95))
		else:
			ci.draw_line(ec + Vector2(-unit * 0.8, 0), ec + Vector2(unit * 0.8, 0), Color(eye.r, eye.g, eye.b, 0.6), 2.0)
	# 口（細く）
	ci.draw_line(head_c + Vector2(-unit * 0.7, head_r.y * 0.55), head_c + Vector2(unit * 0.7, head_r.y * 0.55),
			Color(0.05, 0.06, 0.1), 2.0)

	# 頭頂のリムライト（左から差すネオン）
	for a in range(0, 14):
		var ang := PI * 0.5 + (a / 14.0) * PI * 0.7
		var p := head_c + Vector2(cos(ang) * head_r.x, -sin(ang) * head_r.y)
		ci.draw_circle(p, 1.6, Color(accent.r, accent.g, accent.b, 0.45))


static func _draw_ellipse(ci: CanvasItem, c: Vector2, r: Vector2, col: Color, seg: int) -> void:
	var pts := PackedVector2Array()
	for i in seg:
		var a := TAU * i / seg
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	ci.draw_colored_polygon(pts, col)


static func _draw_hair_back(ci: CanvasItem, hc: Vector2, hr: Vector2, hair: Color, style: String, h: float) -> void:
	var dark := Color(hair.r * 0.6, hair.g * 0.6, hair.b * 0.6)
	match style:
		"long":
			ci.draw_colored_polygon(PackedVector2Array([
				hc + Vector2(-hr.x * 1.1, -hr.y * 0.3),
				hc + Vector2(-hr.x * 1.25, h * 0.30),
				hc + Vector2(hr.x * 1.25, h * 0.30),
				hc + Vector2(hr.x * 1.1, -hr.y * 0.3),
			]), dark)
		"ponytail":
			ci.draw_colored_polygon(PackedVector2Array([
				hc + Vector2(hr.x * 0.7, -hr.y),
				hc + Vector2(hr.x * 1.7, h * 0.06),
				hc + Vector2(hr.x * 1.3, h * 0.24),
				hc + Vector2(hr.x * 0.6, h * 0.05),
			]), dark)
		"twintail":
			for s in [-1.0, 1.0]:
				ci.draw_colored_polygon(PackedVector2Array([
					hc + Vector2(s * hr.x * 0.9, -hr.y * 0.4),
					hc + Vector2(s * hr.x * 1.7, h * 0.02),
					hc + Vector2(s * hr.x * 1.5, h * 0.26),
					hc + Vector2(s * hr.x * 0.8, h * 0.08),
				]), dark)
		"hood":
			ci.draw_colored_polygon(PackedVector2Array([
				hc + Vector2(-hr.x * 1.3, -hr.y * 0.2),
				hc + Vector2(-hr.x * 1.45, h * 0.22),
				hc + Vector2(hr.x * 1.45, h * 0.22),
				hc + Vector2(hr.x * 1.3, -hr.y * 0.2),
			]), Color(hair.r * 0.5, hair.g * 0.5, hair.b * 0.5))


static func _draw_hair_front(ci: CanvasItem, hc: Vector2, hr: Vector2, hair: Color, accent: Color, style: String) -> void:
	# 前髪のかたまり（頭頂〜額）。ゆるい流し前髪（角張った二股を避ける）
	ci.draw_colored_polygon(PackedVector2Array([
		hc + Vector2(-hr.x * 1.05, -hr.y * 0.1),
		hc + Vector2(-hr.x * 1.12, -hr.y * 1.15),
		hc + Vector2(hr.x * 1.12, -hr.y * 1.15),
		hc + Vector2(hr.x * 1.05, -hr.y * 0.1),
		hc + Vector2(hr.x * 0.62, -hr.y * 0.62),
		hc + Vector2(hr.x * 0.18, -hr.y * 0.5),
		hc + Vector2(-hr.x * 0.28, -hr.y * 0.66),
		hc + Vector2(-hr.x * 0.7, -hr.y * 0.5),
	]), hair)
	if style == "hood":
		# フードの影
		ci.draw_arc(hc, hr.x * 1.2, PI * 1.05, PI * 1.95, 18, Color(accent.r, accent.g, accent.b, 0.4), 2.0)
	# 前髪のハイライト一本
	ci.draw_line(hc + Vector2(-hr.x * 0.6, -hr.y * 0.9), hc + Vector2(-hr.x * 0.3, -hr.y * 0.2),
			Color(accent.r, accent.g, accent.b, 0.5), 2.0)
