class_name Kit
extends RefCounted
## 黒猫飯店 — ネオンノワール描画キット（新HD-2Dシェル用）。
## 各オーバーレイの即時描画（_draw）から呼ぶ静的関数群。
## パネル＝ガラス（影＋縦グラデ＋外グロー＋天面ハイライト＋罫）、
## 背景＝シーン絵カバー＋暗幕＋ビネットで「画面の奥行き」を統一する。
## 色はオーバーレイ側の意味色（PINK/CYAN/GOLD/PURPLE）をそのまま受ける。

# ── 生成テクスチャのキャッシュ（初回だけ作る） ──────────────────────────
static var _shadow_sb: StyleBoxTexture = null   # 9-patch のソフトシャドウ
static var _sheen_tex: ImageTexture = null      # 縦グラデ（天面シーン/底面シェード）
static var _vign_tex: ImageTexture = null       # ビネット（四隅の落ち込み）
static var _glow_tex: ImageTexture = null       # ラジアルグロー（アクセント下敷き）
static var _bg_cache: Dictionary = {}           # path -> Texture2D|null


## 9-patch ソフトシャドウ。角丸パネルの下に敷く。
static func _shadow() -> StyleBoxTexture:
	if _shadow_sb == null:
		var n := 48
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var dx := maxf(maxf(16.0 - x, x - 32.0), 0.0)
				var dy := maxf(maxf(16.0 - y, y - 32.0), 0.0)
				var d := sqrt(dx * dx + dy * dy)
				var a := clampf(1.0 - d / 15.0, 0.0, 1.0)
				img.set_pixel(x, y, Color(0, 0, 0, a * a * 0.6))
		_shadow_sb = StyleBoxTexture.new()
		_shadow_sb.texture = ImageTexture.create_from_image(img)
		_shadow_sb.set_texture_margin_all(20)
	return _shadow_sb


## 1x64 の縦グラデ（上＝白シーン／下＝黒シェード）。ガラスの面に重ねる。
static func _sheen() -> ImageTexture:
	if _sheen_tex == null:
		var img := Image.create(1, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			var t := y / 63.0
			var top := clampf(1.0 - t * 2.6, 0.0, 1.0)     # 上 38% で消える
			var bot := clampf((t - 0.55) / 0.45, 0.0, 1.0) # 下 45% で立ち上がる
			var a_w := top * top * 0.085
			var a_b := bot * bot * 0.22
			# 白と黒を1枚に合成（白が勝つ側は白、下は黒）
			if a_w >= a_b:
				img.set_pixel(0, y, Color(1, 1, 1, a_w))
			else:
				img.set_pixel(0, y, Color(0, 0, 0, a_b))
		_sheen_tex = ImageTexture.create_from_image(img)
	return _sheen_tex


static func _vignette() -> ImageTexture:
	if _vign_tex == null:
		var n := 128
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var v := Vector2(x / float(n - 1) - 0.5, y / float(n - 1) - 0.5).length() * 2.0
				var a := clampf((v - 0.62) / 0.55, 0.0, 1.0)
				img.set_pixel(x, y, Color(0, 0, 0, a * a * 0.42))
		_vign_tex = ImageTexture.create_from_image(img)
	return _vign_tex


static func _glow() -> ImageTexture:
	if _glow_tex == null:
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var v := Vector2(x / float(n - 1) - 0.5, y / float(n - 1) - 0.5).length() * 2.0
				var a := clampf(1.0 - v, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a * a * a))
		_glow_tex = ImageTexture.create_from_image(img)
	return _glow_tex


# ── パネル（ガラス）────────────────────────────────────────────────────

## 既存 _panel(rect, bg, border, radius, bw) 互換のリッチ版。
## 影 → 面 → 縦グラデ → 外グロー → 天面ハイライト → 罫 の順で重ねる。
static func panel(ci: CanvasItem, rect: Rect2, bg: Color, border: Color, radius := 10.0, bw := 1.5) -> void:
	# 影（面がほぼ不透明な時だけ。薄いオーバーレイ面には落とさない）
	if bg.a >= 0.55 and rect.size.y > 20.0:
		ci.draw_style_box(_shadow(), rect.grow(9))
	# 面
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(radius))
	ci.draw_style_box(sb, rect)
	# 縦グラデ（ガラスのシーン。角のはみ出しは暗地では知覚されない）
	ci.draw_texture_rect(_sheen(), rect.grow(-1.0), false)
	# 外グロー（アクセント色のにじみ＝ネオン）
	if border.a > 0.05:
		var glow := StyleBoxFlat.new()
		glow.draw_center = false
		glow.set_corner_radius_all(int(radius) + 2)
		glow.set_border_width_all(3)
		glow.border_color = Color(border.r, border.g, border.b, border.a * 0.16)
		ci.draw_style_box(glow, rect.grow(2))
	# 天面ハイライト（1pxの内側ライン＝面の折り返し）
	var hl_y := rect.position.y + 1.5
	ci.draw_line(Vector2(rect.position.x + radius, hl_y),
			Vector2(rect.position.x + rect.size.x - radius, hl_y), Color(1, 1, 1, 0.055), 1.0)
	# 罫
	var line := StyleBoxFlat.new()
	line.draw_center = false
	line.set_corner_radius_all(int(radius))
	line.set_border_width_all(maxi(int(bw), 1))
	line.border_color = border
	ci.draw_style_box(line, rect)


## アクセントの強い主役ボタン面（CTA）。panel＋強めの二重グロー。
static func cta(ci: CanvasItem, rect: Rect2, bg: Color, accent: Color, pulse := 0.0, radius := 16.0) -> void:
	# 大きめの下敷きグロー
	var g := Color(accent.r, accent.g, accent.b, 0.10 + 0.10 * pulse)
	ci.draw_texture_rect(_glow(), rect.grow(26), false, g)
	panel(ci, rect, bg, Color(accent.r, accent.g, accent.b, 0.65 + 0.3 * pulse), radius, 2.0)


# ── 画面の地（背景・ビネット・ヘッダー帯）──────────────────────────────

static func _bg_tex(path: String) -> Texture2D:
	if not _bg_cache.has(path):
		_bg_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _bg_cache[path]


## シーン絵をカバーで敷き、暗幕＋アクセントの底光りで「店の奥行き」を作る。
static func backdrop(ci: CanvasItem, sz: Vector2, path: String, accent: Color, darken := 0.66) -> void:
	var tex := _bg_tex(path)
	if tex == null:
		ci.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.05, 0.05, 0.08, 1.0))
	else:
		var ts := tex.get_size()
		var s := maxf(sz.x / ts.x, sz.y / ts.y)
		var dst := ts * s
		ci.draw_texture_rect(tex, Rect2((sz - dst) * 0.5, dst), false)
	# 暗幕（上下を強めに落として中央に視線を集める）
	ci.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.02, 0.05, darken))
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(sz.x, 0), Vector2(sz.x, sz.y * 0.30), Vector2(0, sz.y * 0.30)])
	var top_c := Color(0.01, 0.01, 0.04, 0.55)
	ci.draw_polygon(pts, PackedColorArray([top_c, top_c, Color(0, 0, 0, 0), Color(0, 0, 0, 0)]))
	var pts2 := PackedVector2Array([Vector2(0, sz.y * 0.62), Vector2(sz.x, sz.y * 0.62), Vector2(sz.x, sz.y), Vector2(0, sz.y)])
	var bot_c := Color(0.01, 0.01, 0.04, 0.72)
	ci.draw_polygon(pts2, PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), bot_c, bot_c]))
	# アクセントの底光り（画面下からネオンが差す）
	ci.draw_texture_rect(_glow(), Rect2(sz.x * 0.5 - sz.x * 0.9, sz.y - sz.x * 0.55, sz.x * 1.8, sz.x * 0.9),
			false, Color(accent.r, accent.g, accent.b, 0.05))


## 最後に全画面へ掛けるビネット。
static func vignette(ci: CanvasItem, sz: Vector2) -> void:
	ci.draw_texture_rect(_vignette(), Rect2(Vector2.ZERO, sz), false)


## セクション見出し：アクセントのチップ＋ラベル＋ヘアライン。
static func header(ci: CanvasItem, font: Font, pos: Vector2, label: String, accent: Color, width := 0.0, size := 15) -> void:
	ci.draw_rect(Rect2(pos.x, pos.y - size + 3, 4, size), accent)
	ci.draw_string(font, Vector2(pos.x + 12, pos.y + 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.6))
	ci.draw_string(font, Vector2(pos.x + 11, pos.y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.96, 0.95, 0.98))
	if width > 0.0:
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		ci.draw_line(Vector2(pos.x + 22 + tw, pos.y - size * 0.35),
				Vector2(pos.x + width, pos.y - size * 0.35), Color(1, 1, 1, 0.08), 1.0)


## アクティブ項目の下敷きグロー（フッターの現在地など）。
static func spot(ci: CanvasItem, center: Vector2, radius: float, accent: Color, alpha := 0.22) -> void:
	ci.draw_texture_rect(_glow(), Rect2(center - Vector2(radius, radius), Vector2(radius * 2, radius * 2)),
			false, Color(accent.r, accent.g, accent.b, alpha))


# ── リップル（タップの波紋・押下フィードバック）──────────────────────────

const RIPPLE_LIFE := 0.45

## タップ位置を記録（各オーバーレイの _ripples 配列へ）。now はオーバーレイの _t。
static func ripple_add(list: Array, pos: Vector2, now: float) -> void:
	list.append({"pos": pos, "t0": now})
	while list.size() > 6:
		list.pop_front()


## リップルを描画し、寿命切れを取り除く。_draw の最後に呼ぶ。
static func ripples(ci: CanvasItem, list: Array, now: float) -> void:
	var i := 0
	while i < list.size():
		var k := (now - float(list[i]["t0"])) / RIPPLE_LIFE
		if k >= 1.0:
			list.remove_at(i)
			continue
		var e := 1.0 - pow(1.0 - k, 2.0)
		var p: Vector2 = list[i]["pos"]
		var r := lerpf(10.0, 46.0, e)
		ci.draw_circle(p, r, Color(1, 1, 1, (1.0 - k) * 0.06))
		ci.draw_arc(p, r, 0, TAU, 40, Color(1, 1, 1, (1.0 - k) * 0.30), 2.0)
		i += 1


## HP/進行バー：内側の溝＋グラデ入り本体＋先端の粒。
static func bar(ci: CanvasItem, rect: Rect2, frac: float, col: Color) -> void:
	var bgsb := StyleBoxFlat.new()
	bgsb.bg_color = Color(0, 0, 0, 0.55)
	bgsb.set_corner_radius_all(int(rect.size.y * 0.5))
	bgsb.border_color = Color(1, 1, 1, 0.10)
	bgsb.set_border_width_all(1)
	ci.draw_style_box(bgsb, rect)
	var w := rect.size.x * clampf(frac, 0.0, 1.0)
	if w > 2.0:
		var fill := StyleBoxFlat.new()
		fill.bg_color = col
		fill.set_corner_radius_all(int(rect.size.y * 0.5))
		var fr := Rect2(rect.position + Vector2(1, 1), Vector2(maxf(w - 2.0, rect.size.y - 2.0), rect.size.y - 2))
		ci.draw_style_box(fill, fr)
		ci.draw_texture_rect(_sheen(), fr, false)
		# 先端の光
		ci.draw_texture_rect(_glow(), Rect2(fr.position.x + fr.size.x - rect.size.y, fr.position.y - 3,
				rect.size.y * 2, rect.size.y + 6), false, Color(col.r, col.g, col.b, 0.5))
