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
static var _pix_cache: Dictionary = {}          # "path:h" -> Texture2D|null
static var _cut_cache: Dictionary = {}          # path -> Texture2D|null（背景を抜いたアイコン）


## 高解像度の立ち絵/アニメフレームをドット絵化（縮小＋α2値化。拡大はニアレスト前提）。
## 横スクロール潜航と夜営業シアターでピクセル密度を統一するための共通ヘルパー。
static func pix_tex(path: String, pix_h: int) -> Texture2D:
	var key := "%s:%d" % [path, pix_h]
	if _pix_cache.has(key):
		return _pix_cache[key]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		var src: Texture2D = load(path)
		var img := src.get_image()
		if img != null:
			img = img.duplicate()
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			var w := maxi(int(round(img.get_width() * float(pix_h) / maxf(img.get_height(), 1.0))), 1)
			img.resize(w, pix_h, Image.INTERPOLATE_BILINEAR)
			for y in img.get_height():
				for x in w:
					var c := img.get_pixel(x, y)
					c.a = 1.0 if c.a > 0.42 else 0.0
					img.set_pixel(x, y, c)
			t = ImageTexture.create_from_image(img)
	_pix_cache[key] = t
	return t


## 生成アイコン（不透明な正方形で書き出されたもの）の地色を縁から塗り潰して抜く。
## 白地の料理アイコンが「画面の最明部」になる事故を止め、丸皿バックプレートに乗せる。
## 既に透過を持つ画像（顔など）はそのまま返す。
static func cutout_tex(path: String, tol := 0.09) -> Texture2D:
	if _cut_cache.has(path):
		return _cut_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		var src: Texture2D = load(path)
		var img := src.get_image()
		if img != null:
			img = img.duplicate()
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			var w := img.get_width()
			var h := img.get_height()
			if w > 0 and h > 0 and img.get_pixel(0, 0).a > 0.99:
				# 縁から領域成長で「地」を抜く（隣接画素との差だけ見るのでグラデ地も剥がれ、
				# 料理の中の白は残る）。
				var seen := PackedByteArray()
				seen.resize(w * h)
				var q: Array[Vector2i] = []
				for x in w:
					q.append(Vector2i(x, 0))
					q.append(Vector2i(x, h - 1))
				for y in h:
					q.append(Vector2i(0, y))
					q.append(Vector2i(w - 1, y))
				var lim := tol * 3.0
				var i := 0
				while i < q.size():
					var p: Vector2i = q[i]
					i += 1
					if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
						continue
					var key := p.y * w + p.x
					if seen[key] != 0:
						continue
					var c := img.get_pixel(p.x, p.y)
					var edge := p.x == 0 or p.y == 0 or p.x == w - 1 or p.y == h - 1
					if not edge:
						# 既に抜けた隣（=地）と色が近いか
						var near := false
						var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
						for d in dirs:
							var n: Vector2i = p + d
							if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
								continue
							if seen[n.y * w + n.x] == 0:
								continue
							var nc := img.get_pixel(n.x, n.y)
							if nc.a > 0.02:
								continue
							if absf(c.r - nc.r) + absf(c.g - nc.g) + absf(c.b - nc.b) < lim:
								near = true
								break
						if not near:
							continue
					seen[key] = 1
					img.set_pixel(p.x, p.y, Color(c.r, c.g, c.b, 0.0))
					q.append(Vector2i(p.x + 1, p.y))
					q.append(Vector2i(p.x - 1, p.y))
					q.append(Vector2i(p.x, p.y + 1))
					q.append(Vector2i(p.x, p.y - 1))
				t = ImageTexture.create_from_image(img)
			else:
				t = src
	_cut_cache[path] = t
	return t


# ── 斜めの板（P5流：面そのものを傾け、無情報の平面を作らない）─────────────

## 平行四辺形の板。skew>0 で上辺が右へ寄る。rect の外へはみ出さない。
static func slab(ci: CanvasItem, rect: Rect2, col: Color, skew := 10.0) -> void:
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(rect.position.x + skew, rect.position.y),
		Vector2(rect.end.x, rect.position.y),
		Vector2(rect.end.x - skew, rect.end.y),
		Vector2(rect.position.x, rect.end.y)]), col)


## 斜めの板の輪郭だけ（非選択＝罫、選択＝ベタ、の対比に使う）。
static func slab_edge(ci: CanvasItem, rect: Rect2, col: Color, skew := 10.0, width := 1.5) -> void:
	var p := PackedVector2Array([
		Vector2(rect.position.x + skew, rect.position.y),
		Vector2(rect.end.x, rect.position.y),
		Vector2(rect.end.x - skew, rect.end.y),
		Vector2(rect.position.x, rect.end.y),
		Vector2(rect.position.x + skew, rect.position.y)])
	ci.draw_polyline(p, col, width)


## 斜めの地紋。無情報の平面を1cmも残さないための縞。
static func hatch(ci: CanvasItem, rect: Rect2, col: Color, spacing := 26.0, width := 9.0) -> void:
	var h := rect.size.y
	var k := rect.position.x - h
	while k < rect.end.x:
		var a := maxf(0.0, rect.position.x - k)
		var b := minf(h, rect.end.x - k)
		if b > a + 1.0:
			ci.draw_line(Vector2(k + a, rect.position.y + a), Vector2(k + b, rect.position.y + b), col, width)
		k += spacing


## アイコンの丸皿バックプレート（最明部を作らせない共通の受け皿）。
static func plate(ci: CanvasItem, center: Vector2, radius: float, tint := Color(1, 1, 1, 1)) -> void:
	ci.draw_circle(center, radius, Color(0.035, 0.03, 0.055, 0.92))
	ci.draw_arc(center, radius - 1.0, 0.0, TAU, 32, Color(tint.r, tint.g, tint.b, 0.45), 1.5)


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
				var a := clampf((v - 0.68) / 0.55, 0.0, 1.0)
				img.set_pixel(x, y, Color(0, 0, 0, a * a * 0.26))
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
		# ドット絵は整数倍だけ（非整数倍はドットが溶けて崩れ字が汚く見える）
		var s := ceilf(maxf(sz.x / ts.x, sz.y / ts.y))
		var dst := (ts * s).round()
		ci.draw_texture_rect(tex, Rect2(((sz - dst) * 0.5).round(), dst), false)
	# 暗幕（多重掛けをやめ、地の1枚＋下側の一段だけ。UI が面積を持つ前提）
	ci.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.02, 0.05, darken))
	var pts2 := PackedVector2Array([Vector2(0, sz.y * 0.66), Vector2(sz.x, sz.y * 0.66), Vector2(sz.x, sz.y), Vector2(0, sz.y)])
	var bot_c := Color(0.01, 0.01, 0.04, 0.34)
	ci.draw_polygon(pts2, PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), bot_c, bot_c]))
	# アクセントの底光り（画面下からネオンが差す）
	ci.draw_texture_rect(_glow(), Rect2(sz.x * 0.5 - sz.x * 0.9, sz.y - sz.x * 0.55, sz.x * 1.8, sz.x * 0.9),
			false, Color(accent.r, accent.g, accent.b, 0.05))


## 最後に全画面へ掛けるビネット。
static func vignette(ci: CanvasItem, sz: Vector2) -> void:
	ci.draw_texture_rect(_vignette(), Rect2(Vector2.ZERO, sz), false)


## セクション見出し：傾いた黒い板に白抜きで叩き込む（P5流）。
## pos は板の左上。高さは size+16。note は板の右へ流す小さな添え書き。
static func header(ci: CanvasItem, font: Font, pos: Vector2, label: String, accent: Color,
		width := 0.0, size := DS.T_SUB, note := "") -> void:
	var h := float(size) + 16.0
	var wd := width if width > 0.0 else 260.0
	var rect := Rect2(pos.x, pos.y, wd, h)
	var skew := 10.0
	# 識別色の下敷き（板が2枚ずれて重なる＝紙を叩きつけた感じ）
	slab(ci, Rect2(rect.position.x + 7.0, rect.position.y + 6.0, rect.size.x - 7.0, h),
			Color(accent.r, accent.g, accent.b, 0.5), skew)
	slab(ci, rect, Color(DS.INK.r, DS.INK.g, DS.INK.b, 0.97), skew)
	slab(ci, Rect2(rect.position.x + 8.0, rect.position.y, 9.0, h), accent, skew)
	var bx := rect.position.x + 30.0
	var by := rect.position.y + h * 0.5 + size * 0.36
	ci.draw_string_outline(font, Vector2(bx, by), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4,
			Color(0, 0, 0, 0.9))
	ci.draw_string(font, Vector2(bx, by), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, DS.PAPER)
	if note != "":
		var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		ci.draw_string(font, Vector2(bx + lw + 16.0, by - 1.0), note, HORIZONTAL_ALIGNMENT_LEFT, -1,
				DS.T_MICRO, Color(accent.r, accent.g, accent.b, 0.95))


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


# ── 数値の生き物化（カウントアップ／拡大／差分フロート）────────────────────
# クッキークリッカーの原則：状態が動いたら、画面が必ず何かを言う。
# 「変化の検出」をここへ集約する。各オーバーレイは今の値を渡すだけでよく、
# どこかの描画点を書き忘れない限り、黙って数字が入れ替わる箇所は生まれない。

const NUM_SNAP := 0.5      # これ以下の差は吸着（端数を残さない）
const POP_LIFE := 0.30     # 拡大の寿命（秒）
const FLOAT_LIFE := 1.05   # 差分フロートの寿命（秒）
const FLY_LIFE := 0.55     # 飛ぶ数値（支払い/収穫）の寿命（秒）
const PRESS_LIFE := 0.22   # 押下フラッシュの寿命（秒）
const BURST_LIFE := 0.85   # 解放バーストの寿命（秒）

## 現在のキャンバス平行移動。set_xf() で設定すると num_draw が復元できる
## （拡大描画のために transform を一時的に奪うので、元へ戻す先を覚えておく）。
static var xf := Vector2.ZERO


static func set_xf(ci: CanvasItem, ofs: Vector2) -> void:
	xf = ofs
	ci.draw_set_transform(ofs, 0.0, Vector2.ONE)


## 値を追いかける台帳。store はオーバーレイが持つ Dictionary。
## 返り値 {"v": 表示値（カウントアップ中）, "pop": 0..1 拡大量, "d": 変化した瞬間の差分}。
## 初回は目標値へ吸着（開いた瞬間に0から数え上げない）。
static func num(store: Dictionary, key: String, target: float, now: float) -> Dictionary:
	if not store.has(key):
		store[key] = {"v": target, "g": target, "pop": 0.0, "t": now}
		return {"v": target, "pop": 0.0, "d": 0.0}
	var e: Dictionary = store[key]
	var dt := clampf(now - float(e["t"]), 0.0, 0.1)
	e["t"] = now
	var d := 0.0
	if absf(target - float(e["g"])) > 0.0001:
		d = target - float(e["g"])
		e["g"] = target
		e["pop"] = 1.0
	var v := float(e["v"])
	var g := float(e["g"])
	v += (g - v) * clampf(dt * 9.0, 0.0, 1.0)
	if absf(g - v) < NUM_SNAP:
		v = g
	e["v"] = v
	e["pop"] = maxf(float(e["pop"]) - dt / POP_LIFE, 0.0)
	return {"v": v, "pop": float(e["pop"]), "d": d}


## 数値を「一瞬だけ拡大して」描く。size は DS の段（16/24/32/48）から選ぶこと。
## 拡大は transform で行う＝字の段数を増やさずに、変化した事実だけを見せる。
static func num_draw(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, col: Color,
		pop := 0.0) -> void:
	var at := pos
	if pop > 0.001:
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var c := Vector2(pos.x + w * 0.5, pos.y - size * 0.34)
		var sc := 1.0 + 0.45 * pop * pop
		ci.draw_set_transform(xf + c, 0.0, Vector2(sc, sc))
		at = pos - c
	ci.draw_string_outline(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.85 * col.a))
	ci.draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	if pop > 0.001:
		ci.draw_set_transform(xf, 0.0, Vector2.ONE)


## 取り消し線つきの旧値。罰の前の数字を「消された事実」として残す。
## line は取り消し線の色（赤い面の上では地に沈むので、呼び出し側が指定できる）。
static func struck(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, col: Color,
		line := DS.DANGER, outline := true) -> float:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if outline:
		ci.draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(0, 0, 0, 0.8))
	ci.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	ci.draw_line(Vector2(pos.x - 2.0, pos.y - size * 0.3), Vector2(pos.x + w + 2.0, pos.y - size * 0.3),
			Color(line.r, line.g, line.b, 0.95), 2.0)
	return w


## 差分のフロート（+120G が上へ流れて消える）。
static func float_add(list: Array, pos: Vector2, text: String, col: Color, now: float) -> void:
	list.append({"p": pos, "s": text, "c": col, "t0": now})
	while list.size() > 14:
		list.pop_front()


static func floats(ci: CanvasItem, font: Font, list: Array, now: float) -> void:
	var i := 0
	while i < list.size():
		var e: Dictionary = list[i]
		var k := (now - float(e["t0"])) / FLOAT_LIFE
		if k >= 1.0:
			list.remove_at(i)
			continue
		var ez := 1.0 - pow(1.0 - k, 2.2)
		var p: Vector2 = (e["p"] as Vector2) + Vector2(0.0, -54.0 * ez)
		var a := clampf((1.0 - k) * 1.8, 0.0, 1.0)
		var c: Color = e["c"]
		num_draw(ci, font, p, String(e["s"]), DS.T_BODY, Color(c.r, c.g, c.b, a),
				clampf(1.0 - k * 6.0, 0.0, 1.0))
		i += 1


## 飛ぶ数値。購入＝所持金から実際に飛んでいく／収穫＝手元へ飛んでくる。
static func fly_add(list: Array, from: Vector2, to: Vector2, text: String, col: Color, now: float) -> void:
	list.append({"a": from, "b": to, "s": text, "c": col, "t0": now})
	while list.size() > 10:
		list.pop_front()


static func flies(ci: CanvasItem, font: Font, list: Array, now: float) -> void:
	var i := 0
	while i < list.size():
		var e: Dictionary = list[i]
		var k := (now - float(e["t0"])) / FLY_LIFE
		if k >= 1.0:
			list.remove_at(i)
			continue
		var a: Vector2 = e["a"]
		var b: Vector2 = e["b"]
		var ctrl := (a + b) * 0.5 + Vector2(0.0, -120.0)
		var u := k * k * (3.0 - 2.0 * k)
		var p := a.lerp(ctrl, u).lerp(ctrl.lerp(b, u), u)
		var c: Color = e["c"]
		var al := clampf((1.0 - k) * 2.4, 0.0, 1.0)
		ci.draw_texture_rect(_glow(), Rect2(p - Vector2(36, 36), Vector2(72, 72)), false,
				Color(c.r, c.g, c.b, 0.40 * al))
		var s := String(e["s"])
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, DS.T_BODY).x
		num_draw(ci, font, p - Vector2(w * 0.5, -6.0), s, DS.T_BODY, Color(c.r, c.g, c.b, al))
		i += 1


## 押下フラッシュ。押せる場所は押した瞬間に必ず応える（3状態目）。
static func press(ci: CanvasItem, rect: Rect2, col: Color, k: float) -> void:
	if k <= 0.0:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.18 * k)
	sb.set_corner_radius_all(8)
	sb.border_color = Color(col.r, col.g, col.b, 0.95 * k)
	sb.set_border_width_all(2)
	ci.draw_style_box(sb, rect.grow(3.0 * k))


## 解放の瞬間。光の輪が拡がり、放射が飛ぶ（改装ノード・購入の着弾）。
static func burst(ci: CanvasItem, center: Vector2, radius: float, col: Color, k: float) -> void:
	if k <= 0.0 or k >= 1.0:
		return
	var e := 1.0 - pow(1.0 - k, 2.0)
	var a := 1.0 - k
	ci.draw_texture_rect(_glow(), Rect2(center - Vector2(radius * 2.6, radius * 2.6),
			Vector2(radius * 5.2, radius * 5.2)), false, Color(col.r, col.g, col.b, 0.55 * a))
	ci.draw_arc(center, radius * (0.7 + 2.2 * e), 0.0, TAU, 42, Color(col.r, col.g, col.b, a), 3.0 * a + 0.5)
	for i in 6:
		var ang := TAU * i / 6.0 + e * 1.2
		var d := Vector2(cos(ang), sin(ang))
		ci.draw_line(center + d * radius * (1.1 + 1.3 * e), center + d * radius * (1.5 + 2.0 * e),
				Color(col.r, col.g, col.b, a), 2.0)


## 線を「繋がる」ように描く（改装ツリーの解放直後：光が前提ノードから流れてくる）。
static func wire(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, lit: bool, k := -1.0) -> void:
	ci.draw_line(a, b, Color(col.r, col.g, col.b, 0.55 if lit else 0.18), 2.0)
	if k >= 0.0 and k < 1.0:
		var u := clampf(k * 1.4, 0.0, 1.0)
		ci.draw_line(a, a.lerp(b, u), Color(col.r, col.g, col.b, 1.0 - k * 0.5), 4.0)
		ci.draw_circle(a.lerp(b, u), 5.0 * (1.0 - k * 0.5), Color(col.r, col.g, col.b, 1.0 - k))


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
