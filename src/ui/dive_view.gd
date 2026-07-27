class_name DiveView
extends Control
## 潜行ビュー（電脳深層）。Rain98 系のビジュアル言語：
## 深い青のモノクローム、絶え間ない雨、シアンの発光、白の斜めバンド。
## スプライトは 0x72 DungeonTilesetII（CC0）を青に沈めて使う。

const FX_DIR := "res://assets/third_party/effects/"
const SCALE := 3.0
const ANIM_FPS := 6.0
const FX_MAX := 6
const TINT := Color(0.62, 0.78, 1.15)  # 青に沈める
const RAIN_N := 46

# エフェクト定義は FxData（src/sim/fx_data.gd）に一元化。ここは別名。
const FX_DEFS := FxData.FX

var sim: KuroSim = null
var pulse := 0.0
var remaining := -1.0  # 集中の残り秒（main から供給・配信タイマー表示用）
var _tex_cache := {}
var _mob_frames := {}   # "<sprite>:<f>" -> 反転済み1コマ Texture2D
var _fx_active: Array = []
var _bubble := {}  # {girl, text, t}
var _dialog: Array = []  # 直近の掛け合いログ {who,text,col}
var _damage_pops: Array = []  # {val, x, y, t, col}  ダメージ数字ポップアップ
# ChibiAnim インスタンス（キャラ id → ChibiAnim）
# Unity の Animator コンポーネントに相当（キャラごとに1つ）
var _chibi_anims: Dictionary = {}
# 疑似Camera2D（ノード化せず draw_set_transform で表現＝決定論を崩さず軽い）
var _cam_zoom := 1.04
var _cam_zoom_target := 1.04
var _cam_shake := 0.0
var _was_combat := false
var _party_hit_t := 0.0  # 味方被弾のけぞり残り秒（hit アニメ切替用）
const BASE_ZOOM := 1.04


func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## キャラのセリフ吹き出しを数秒表示。掛け合いログにも積む（下部の配信ログ）。
func say(girl_id: String, text: String) -> void:
	# 発話時間をテキスト長に比例させる（日本語: 約5〜6文字/秒）
	var speak_dur := clampf(text.length() * 0.16, 1.2, 4.5)
	_bubble = {"girl": girl_id, "text": text, "t": speak_dur}
	var col := Color(0.7, 0.85, 1.0)
	if KuroData.GIRLS.has(girl_id):
		col = KuroData.GIRLS[girl_id]["color"]
	_dialog.append({"who": girl_id, "text": text, "col": col})
	while _dialog.size() > 4:
		_dialog.pop_front()


func _process(delta: float) -> void:
	pulse += delta
	# ChibiAnim のステートマシンを毎フレーム更新（Unity の Animator.Update() 相当）
	for anim: ChibiAnim in _chibi_anims.values():
		anim.tick(delta)
	if not _bubble.is_empty():
		_bubble["t"] = float(_bubble["t"]) - delta
		if float(_bubble["t"]) <= 0.0:
			_bubble = {}
	var i := 0
	while i < _damage_pops.size():
		var p: Dictionary = _damage_pops[i]
		p["t"] = float(p["t"]) + delta
		if float(p["t"]) > 1.2:
			_damage_pops.remove_at(i)
		else:
			i += 1
	i = 0
	while i < _fx_active.size():
		var fx: Dictionary = _fx_active[i]
		fx["t"] = float(fx["t"]) + delta
		var def: Dictionary = FX_DEFS[fx["kind"]]
		if float(fx["t"]) * float(def["fps"]) >= float(def["frames"]):
			_fx_active.remove_at(i)
		else:
			i += 1
	# カメラ（疑似Camera2D）：戦闘突入でズームイン、被弾でシェイク、平時は緩く戻す
	if sim != null and sim.state["run"]["active"]:
		var c: bool = sim.state["in_combat"]
		if c and not _was_combat:
			_cam_zoom_target = 1.2
			_cam_shake = maxf(_cam_shake, 7.0)
		_was_combat = c
	_cam_zoom_target = lerpf(_cam_zoom_target, BASE_ZOOM, delta * 1.4)
	_cam_zoom = lerpf(_cam_zoom, _cam_zoom_target, delta * 7.0)
	_cam_shake = maxf(0.0, _cam_shake - delta * 26.0)
	_party_hit_t = maxf(0.0, _party_hit_t - delta)
	if visible:
		queue_redraw()


func spawn_damage(amount: int, at: String = "enemy") -> void:
	if amount <= 0:
		return
	var x := (size.x * 0.76) if at == "enemy" else (size.x * 0.24)
	x += randf_range(-18.0, 18.0)
	var y := size.y * 0.42 + randf_range(-10.0, 10.0)
	var col := Color(1.0, 0.92, 0.3) if at == "enemy" else Color(1.0, 0.4, 0.45)
	_damage_pops.append({"val": amount, "x": x, "y": y, "t": 0.0, "col": col})
	if at == "party":
		_party_hit_t = 0.32  # 被弾のけぞり（hit アニメ）を再生する時間


func spawn_fx(kind: String, at: String = "enemy") -> void:
	if not FX_DEFS.has(kind) or _fx_active.size() >= FX_MAX:
		return
	_fx_active.append({"kind": kind, "at": at, "t": 0.0})
	# 被弾/衝撃でカメラを揺らす（味方側は強め）
	var mag := 10.0 if at == "party" else 6.0
	if kind == "lightning" or kind == "explosion":
		mag += 3.0
	_cam_shake = maxf(_cam_shake, mag)


func _tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[path]


## 敵スプライトの1コマ（味方と同じ生成スプライト系。64x96 の4コマ横ストリップ）。
## 左（味方）を向くよう反転済みのテクスチャを作って返す。
func _mob_frame(sprite_name: String) -> Texture2D:
	var f := int(pulse * ANIM_FPS) % 4
	var key := "%s:%d" % [sprite_name, f]
	if _mob_frames.has(key):
		return _mob_frames[key]
	var t: Texture2D = null
	var sheet := _tex("res://assets/generated/sprites/%s/walk_front.png" % sprite_name)
	if sheet == null:
		sheet = _tex("res://assets/generated/sprites/mob_drone/walk_front.png")
	if sheet != null:
		var img := sheet.get_image()
		if img != null:
			img = img.duplicate()
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			var fw := int(img.get_width() / 4)
			var frame := Image.create(fw, img.get_height(), false, Image.FORMAT_RGBA8)
			frame.blit_rect(img, Rect2i(fw * f, 0, fw, img.get_height()), Vector2i.ZERO)
			frame.flip_x()
			t = ImageTexture.create_from_image(frame)
	_mob_frames[key] = t
	return t


## 待機中の店先バナー。薄い高さ（~96px）でも成立するモダンなネオン演出：
## 深い藍のグラデ＋雨＋ネオンの暖色サイン「黒猫飯店」＋脈動する OPEN ＋黒猫。
func _draw_storefront(sz: Vector2, font: Font) -> void:
	# 店内（暖色）を背景に。窓の外は冷たいネオン都市＝寒暖の対比
	var interior := _tex("res://assets/generated/bg/interior.png")
	if interior != null:
		draw_texture_rect(interior, Rect2(0, 0, sz.x, sz.y), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.13, 0.08, 0.06))
	# 文字の可読性のため下を少し沈める
	draw_rect(Rect2(0, sz.y * 0.5, sz.x, sz.y * 0.5), Color(0.05, 0.03, 0.02, 0.45))
	_draw_rain(sz)
	# 提灯（暖色の脈動する円）
	var lantern_glow := 0.35 + 0.12 * sin(pulse * 2.0)
	draw_circle(Vector2(46, sz.y * 0.5), 26.0, Color(1.0, 0.45, 0.35, lantern_glow * 0.5))
	draw_circle(Vector2(46, sz.y * 0.5), 13.0, Color(1.0, 0.55, 0.4, 0.9))
	# ネオンの店名（暖色＋淡いグロー）
	var title := "黒猫飯店"
	var tsize := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 38)
	var tx := 80.0
	var ty := sz.y * 0.5 + 14.0
	draw_string(font, Vector2(tx + 1.5, ty + 1.5), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 38, Color(1.0, 0.4, 0.3, 0.35))
	draw_string(font, Vector2(tx, ty), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 38, Color(1.0, 0.78, 0.55))
	# OPEN サイン（シアンの明滅）
	var open_on := fposmod(pulse, 3.0) < 2.7
	var open_col := Color(0.4, 1.0, 0.9, 1.0) if open_on else Color(0.4, 1.0, 0.9, 0.2)
	draw_string(font, Vector2(tx + tsize.x + 20.0, ty), "OPEN", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, open_col)
	# 黒猫（右下のカウンター端で目を光らせている）
	var cx := sz.x - 42.0
	var cy := sz.y - 20.0
	draw_circle(Vector2(cx, cy), 12.0, Color(0.01, 0.02, 0.05))
	draw_circle(Vector2(cx - 8, cy - 12), 6.0, Color(0.01, 0.02, 0.05))  # 耳
	draw_circle(Vector2(cx + 8, cy - 12), 6.0, Color(0.01, 0.02, 0.05))
	if fposmod(pulse, 4.0) < 3.7:  # まばたき
		draw_circle(Vector2(cx - 4, cy - 3), 1.6, Color(0.55, 0.95, 0.7))
		draw_circle(Vector2(cx + 4, cy - 3), 1.6, Color(0.55, 0.95, 0.7))


## キャラの頭上にセリフ吹き出しを描く（角丸＋しっぽ）。横幅は画面内に収める。
func _draw_bubble(font: Font, anchor: Vector2, who: String, text: String) -> void:
	var fs := 17
	var pad := 9.0
	var line := "%s「%s」" % [who, text]
	var tw := minf(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, size.x - 28.0)
	var bw := tw + pad * 2
	var bh := 30.0
	var bx := clampf(anchor.x - bw * 0.4, 8.0, size.x - bw - 8.0)
	var by := anchor.y - bh
	var fade: float = clampf(float(_bubble["t"]) / 0.6, 0.0, 1.0)
	var bg := Color(0.92, 0.96, 1.0, 0.95 * fade)
	var rect := Rect2(bx, by, bw, bh)
	draw_rect(rect, bg)
	draw_rect(Rect2(bx, by, bw, 2), Color(DS.ACCENT.r, DS.ACCENT.g, DS.ACCENT.b, fade))  # 上辺アクセント
	# しっぽ
	var tip := clampf(anchor.x, bx + 8, bx + bw - 8)
	draw_colored_polygon(PackedVector2Array([
		Vector2(tip - 6, by + bh), Vector2(tip + 6, by + bh), Vector2(tip, by + bh + 9),
	]), bg)
	draw_string(font, Vector2(bx + pad, by + bh - 9), line, HORIZONTAL_ALIGNMENT_LEFT,
			int(bw - pad * 2), fs, Color(0.05, 0.08, 0.16, fade))


func _draw_rain(sz: Vector2) -> void:
	for i in RAIN_N:
		var speed := 420.0 + fposmod(i * 37.7, 220.0)
		var px := fposmod(i * 73.3 - pulse * speed * 0.22, sz.x + 40.0) - 20.0
		var py := fposmod(i * 131.7 + pulse * speed, sz.y + 30.0) - 15.0
		var a := 0.10 + fposmod(i * 0.13, 0.14)
		draw_line(Vector2(px, py), Vector2(px - 5.0, py + 16.0), Color(0.65, 0.85, 1.0, a), 1.2)


func _draw_sprite(tex: Texture2D, foot: Vector2, flip: bool = false, tint: Color = TINT, scl: float = SCALE) -> void:
	var s := tex.get_size() * scl
	var rect := Rect2(foot - Vector2(s.x * 0.5, s.y), s)
	if flip:
		rect = Rect2(rect.position + Vector2(rect.size.x, 0), Vector2(-rect.size.x, rect.size.y))
	draw_texture_rect(tex, rect, false, tint)


## 足元の楕円ソフトシャドウ（2層）。楕円の中心は足元のすぐ下（+1px）に置き、
## 内は濃く小さく／外は薄く広く＝地面に落ちた影の減衰を作る（浮きを消す）。
func _draw_shadow(cx: float, ground: float, w: float) -> void:
	for layer: Array in [[w * 1.62, 0.25], [w, 0.55]]:
		var ww: float = layer[0]
		var pts := PackedVector2Array()
		var seg := 20
		for k in seg:
			var a := TAU * k / seg
			pts.append(Vector2(cx + cos(a) * ww * 0.5, ground + 1.0 + sin(a) * ww * 0.10))
		draw_colored_polygon(pts, Color(0, 0, 0, layer[1]))


## 個別フレームスプライト（assets/generated/sprites/<id>/<anim>_f<n>.png）を
## 足元基準で描画。ChibiAnim ステートマシンが現在フレームを管理。描いた幅を返す（0=未描画）。
##
## Unity 対応:
##   ChibiAnim（Base Controller） → ステート遷移はクラス内部で完結
##   char_id ごとのスプライトフォルダ → Override Controller（クリップ差し替え）
##   update_params() → SetFloat/SetBool 群

func _get_chibi_anim(id: String) -> ChibiAnim:
	if not _chibi_anims.has(id):
		_chibi_anims[id] = ChibiAnim.new(id)
	return _chibi_anims[id]


func _draw_chibi(id: String, foot: Vector2, in_combat: bool, alive: bool, h: float, flip: bool = false, hit: bool = false, moving: bool = true, outline_col: Color = Color(0.0, 0.0, 0.05, 0.72)) -> float:
	# パラメーターを Animator に渡す（Unity の SetFloat/SetBool に相当）
	var anim: ChibiAnim = _get_chibi_anim(id)
	anim.update_params(
		1.0 if moving else 0.0,  # speed
		in_combat and not hit,   # in_combat
		in_combat and hit,       # is_hurt
		not alive,               # is_dead
	)

	# 現在フレームのパスを取得（Override Controller がクリップを差し替える部分）
	var path := anim.current_path()
	var tex := _tex(path)

	# テクスチャが無ければ idle にフォールバック、それも無ければ yuzuki で代用
	if tex == null:
		tex = _tex("res://assets/generated/sprites/%s/idle_f0.png" % id)
	if tex == null and id != "yuzuki":
		return _draw_chibi("yuzuki", foot, in_combat, alive, h, flip, hit, moving, outline_col)
	if tex == null:
		return 0.0

	var sc := h / tex.get_size().y
	var dw := tex.get_size().x * sc

	var rect := Rect2(foot.x - dw * 0.5, foot.y - h, dw, h)
	if flip:
		rect = Rect2(rect.position + Vector2(rect.size.x, 0), Vector2(-rect.size.x, rect.size.y))
	var tint := Color(1, 1, 1) if alive else Color(0.45, 0.47, 0.58)
	# ピクセルアート輪郭線（4方向）。敵は赤い輪郭で「敵である」ことを色で伝える。
	var ofs := maxf(1.0, sc * 0.5)
	for ov in [Vector2(ofs, 0), Vector2(-ofs, 0), Vector2(0, ofs), Vector2(0, -ofs)]:
		draw_texture_rect(tex, Rect2(rect.position + ov, rect.size), false, outline_col)
	draw_texture_rect(tex, rect, false, tint)
	return dw



## 視差スクロールの背景レイヤー（横タイル）。
func _draw_parallax(path: String, scroll: float, top_y: float, tint: Color) -> void:
	var tex := _tex("res://assets/generated/" + path)
	if tex == null:
		return
	var tw := tex.get_size().x
	var th := tex.get_size().y
	var off := fposmod(scroll, tw)
	for k in range(-1, ceili(size.x / tw) + 2):
		draw_texture_rect(tex, Rect2(k * tw - off, top_y, tw, th), false, tint)


## ボス戦の専用演出：画面端の赤いふち＋上部の大きなボスHPバー。
func _draw_boss_stage(sz: Vector2, font: Font, boss: Dictionary) -> void:
	var pulse_a := 0.18 + 0.10 * sin(pulse * 4.0)
	# 赤いふち（4辺）
	var edge := 6.0
	var ec := Color(1.0, 0.3, 0.35, pulse_a)
	draw_rect(Rect2(0, 0, sz.x, edge), ec)
	draw_rect(Rect2(0, sz.y - edge, sz.x, edge), ec)
	draw_rect(Rect2(0, 0, edge, sz.y), ec)
	draw_rect(Rect2(sz.x - edge, 0, edge, sz.y), ec)
	# ボスHPバー（上部・全幅）
	var by := 52.0
	var bw := sz.x - 28.0
	var ratio := clampf(float(boss["hp"]) / float(boss["max_hp"]), 0.0, 1.0)
	draw_rect(Rect2(14, by, bw, 12), Color(0.1, 0.02, 0.04, 0.85))
	draw_rect(Rect2(14, by, bw * ratio, 12), Color(0.95, 0.3, 0.32))
	draw_rect(Rect2(14, by, bw, 12), Color(1.0, 0.5, 0.5, 0.4), false, 1.0)
	draw_string(font, Vector2(16, by - 4), "◆ %s" % String(boss["name"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.6, 0.62))


## ネオンの光芒（上から差すシアンの光）。
func _draw_lightshaft(sz: Vector2) -> void:
	var tex := _tex("res://assets/third_party/overlays/raylight.png")
	if tex == null:
		return
	var a := 0.10 + 0.05 * sin(pulse * 0.8)
	draw_texture_rect(tex, Rect2(sz.x * 0.45, -20, 320, 460), false, Color(0.45, 0.85, 1.0, a))
	draw_texture_rect(tex, Rect2(-40, -10, 240, 380), false, Color(0.5, 0.8, 1.0, a * 0.7))


func _draw_hp(center_x: float, top_y: float, ratio: float, width: float = 34.0) -> void:
	draw_rect(Rect2(center_x - width * 0.5, top_y, width, 4), Color(0, 0, 0, 0.55))
	var r := clampf(ratio, 0.0, 1.0)
	var c: Color = DS.ACCENT if r > 0.3 else DS.DANGER  # 低HPは危険色
	draw_rect(Rect2(center_x - width * 0.5, top_y, width * r, 4), c)


## FX は「被弾した実体の座標」に付ける（ハードコードのx座標は使わない）。
func _draw_fx(ground: float, party_x: Array, enemy_x: Array) -> void:
	for fx in _fx_active:
		var def: Dictionary = FX_DEFS[fx["kind"]]
		var tex := _tex(String(def["file"]))
		if tex == null:
			continue
		var frame := clampi(int(float(fx["t"]) * float(def["fps"])), 0, int(def["frames"]) - 1)
		var fsize := int(def["size"])
		var dsize := fsize * SCALE
		var anchors: Array = enemy_x if fx["at"] == "enemy" else party_x
		var x := (size.x * 0.76) if fx["at"] == "enemy" else (size.x * 0.24)
		if not anchors.is_empty():
			var sx := 0.0
			for v in anchors:
				sx += float(v)
			x = sx / anchors.size()
		draw_texture_rect_region(tex, Rect2(x - dsize * 0.5, ground - dsize, dsize, dsize),
				Rect2(frame * fsize, 0, fsize, fsize))


func _draw() -> void:
	if sim == null:
		return
	var sz := size
	var run: Dictionary = sim.state["run"]
	var font := get_theme_default_font()

	# 待機中（朝/夜/精算）は薄い店先バナー。潜行画面は出さない
	if not run["active"]:
		_draw_storefront(sz, font)
		return

	var fl := sim.current_floor()
	var biome: Dictionary = KuroData.BIOMES[fl % KuroData.BIOMES.size()]
	var dist := float(sim.state["dist"])
	var in_combat: bool = sim.state["in_combat"]
	var door_open := float(run["door_pending"]) > 0.0
	var ground := sz.y * 0.44           # 足元を上げて背景（空）に面積を渡す
	var chibi_h := clampf(sz.y * 0.26, 140.0, 240.0)

	# ====== ワールド層（疑似カメラ：ズーム/緩いパン/被弾シェイク）======
	var zoom := _cam_zoom
	var focus := Vector2(
		sz.x * 0.5 + sin(pulse * 0.22) * sz.x * 0.02 + (sz.x * 0.06 if in_combat else 0.0),
		ground)
	var shake := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _cam_shake
	draw_set_transform(focus * (1.0 - zoom) + shake, 0.0, Vector2(zoom, zoom))

	_draw_explore_bg(sz, biome, dist)
	_draw_ground(sz, ground, biome)

	# 突進モーション＆歩行のゆれ（自動歩行感）
	var lunge_party := (9.0 * maxf(0.0, sin(pulse * 5.0))) if in_combat else 0.0
	var lunge_enemy := (9.0 * maxf(0.0, sin(pulse * 5.0 + PI))) if in_combat else 0.0
	var bob := 0.0 if in_combat else sin(pulse * 3.0) * 3.0

	# 扉（クイック決断バナー中）→ イベントカード演出
	if door_open:
		_draw_event_cards(sz, font)

	# 潜行メンバー（左クラスタ・自動歩行）
	var ds: Array = sim.divers()
	var n := ds.size()
	var party_w := sz.x * (0.46 if in_combat else 0.52)
	var slot := party_w / float(maxi(n, 1))
	var ch := minf(chibi_h, slot * 2.2)
	var party_x: Array = []
	for i in n:
		var id: String = ds[i]
		var x := sz.x * 0.05 + slot * (i + 0.5) + lunge_party
		party_x.append(x)
		var alive := float(sim.state["hp"].get(id, 0.0)) > 0.0
		var foot := Vector2(x, ground + (bob if alive else 0.0))
		# 被弾フラグ＝直近に味方ダメージ発生／停止フラグ＝決断バナー中（door_open）で足踏み停止
		var hit := _party_hit_t > 0.0
		var moving := not door_open
		var dw := _draw_chibi(id, foot, in_combat, alive, ch, false, hit, moving)
		if dw > 0.0:
			_draw_shadow(x, ground, dw * 0.34)
			# 頭上HPは被弾時だけ（常設のHPは下部カードに一本化）
			if alive and hit:
				_draw_hp(x, foot.y - ch - 12.0, float(sim.state["hp"][id]) / sim.girl_maxhp(id),
						maxf(36.0, dw * 0.7))
		else:
			draw_circle(Vector2(x, ground - 14), 12.0, KuroData.GIRLS[id]["color"])

	# 敵（右・前景）：味方と同じ生成スプライトを味方の1.35倍で描き、
	# 足元に赤い接地リング＋赤い輪郭で「敵である」ことを伝える（赤い✕は廃止）。
	var enemy_cx := sz.x * 0.8
	var enemy_x: Array = []
	for i in sim.state["mobs"].size():
		var m: Dictionary = sim.state["mobs"][i]
		var x: float = enemy_cx - i * (slot * 0.7) - lunge_enemy
		enemy_x.append(x)
		var ratio := clampf(float(m["hp"]) / float(m["max_hp"]), 0.0, 1.0)
		var eh := ch * (2.0 if m["boss"] else 1.35)
		var tex2 := _mob_frame(String(m.get("sprite", "mob_drone")))
		if tex2 != null:
			var escl := eh / tex2.get_size().y
			var edw := tex2.get_size().x * escl
			_draw_shadow(x, ground, edw * 0.34)
			_draw_enemy_ring(Vector2(x, ground), edw * 0.30)
			var er := Rect2(x - edw * 0.5, ground - eh, edw, eh)
			var eo := maxf(1.0, escl * 0.55)
			for ov in [Vector2(eo, 0), Vector2(-eo, 0), Vector2(0, eo), Vector2(0, -eo)]:
				draw_texture_rect(tex2, Rect2(er.position + ov, er.size), false, Color(0.8, 0.1, 0.15, 0.85))
			draw_texture_rect(tex2, er, false, Color(1, 1, 1))
			_draw_hp(x, ground - eh - 10.0, ratio, 48.0 if m["boss"] else 34.0)
		else:
			draw_circle(Vector2(x, ground - 14), 16.0 if m["boss"] else 10.0, TINT)

	_draw_fx(ground, party_x, enemy_x)

	# セリフ吹き出し（頭上・ワールド層）
	if not _bubble.is_empty():
		var bi := ds.find(String(_bubble["girl"]))
		if bi >= 0 and bi < party_x.size():
			_draw_bubble(font, Vector2(float(party_x[bi]), ground - ch - 6.0),
					String(KuroData.GIRLS[_bubble["girl"]]["name"]), String(_bubble["text"]))

	# ゴールオーブ（階層の終端マーカー）
	_draw_goal_orb(sz, ground, dist, font)

	# ====== スクリーン層（雨・ダメージ数字。DiveChrome がさらにその上に重なる）======
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_rain(sz)
	_draw_damage_numbers(font)


## 探索の背景。提供イラスト（assets/art/explore_bg.png）を COVERED で敷き、
## 立ち絵/UIを前景として際立たせるため全体を沈める。無ければプロシージャル都市。
func _draw_explore_bg(sz: Vector2, biome: Dictionary, dist: float) -> void:
	var tex := _tex("res://assets/art/explore_bg.png")
	if tex != null:
		var ts := tex.get_size()
		var sc := maxf(sz.x / ts.x, sz.y / ts.y)
		var dw := ts.x * sc
		var dh := ts.y * sc
		var drift := sin(pulse * 0.15) * 8.0  # 緩い縦ドリフト＝生命感
		draw_texture_rect(tex, Rect2((sz.x - dw) * 0.5, (sz.y - dh) * 0.5 + drift, dw, dh), false)
		draw_rect(Rect2(0, 0, sz.x, sz.y), Color(0.03, 0.03, 0.07, 0.42))
		# ※下半分を沈める暗幕は廃止（画面の下半分を殺していた）。
		_draw_lightshaft(sz)
		return
	# フォールバック：従来のプロシージャル都市（視差スクロール）
	var bg: Color = biome["color"]
	draw_rect(Rect2(Vector2.ZERO, sz), Color(bg.r * 0.4, bg.g * 0.4, bg.b * 0.55))
	var city_tint := Color(bg.r * 1.6 + 0.4, bg.g * 1.6 + 0.5, bg.b * 1.6 + 0.6, 0.9)
	_draw_parallax("bg/city_far.png", dist * 0.10, sz.y * 0.30, city_tint)
	_draw_parallax("bg/city_mid.png", dist * 0.22, sz.y * 0.36, Color(city_tint.r, city_tint.g, city_tint.b, 1.0))
	draw_rect(Rect2(0, sz.y * 0.5, sz.x, sz.y * 0.5), Color(0.02, 0.04, 0.10, 0.4))
	_draw_lightshaft(sz)


## 地面プラットフォーム（タイル状のレール）。キャラを「乗せる」接地感。
func _draw_ground(sz: Vector2, ground: float, biome: Dictionary) -> void:
	var plat_h := sz.y * 0.06
	var base_col: Color = biome["color"]
	var far_c := Color(base_col.r * 0.3 + 0.08, base_col.g * 0.3 + 0.06, base_col.b * 0.3 + 0.14)
	var near_c := Color(base_col.r * 0.5 + 0.20, base_col.g * 0.5 + 0.18, base_col.b * 0.5 + 0.26)
	# 床（奥＝暗く、手前＝明るく。下端まで塗って正体不明の黒帯を作らない）
	draw_polygon(
			PackedVector2Array([Vector2(0, ground), Vector2(sz.x, ground),
					Vector2(sz.x, sz.y), Vector2(0, sz.y)]),
			PackedColorArray([far_c, far_c, near_c, near_c]))
	# 透視ライン（下ほど間隔が広がる）
	var depth := sz.y - ground
	for i in range(1, 9):
		var k := float(i) / 9.0
		draw_rect(Rect2(0, ground + depth * pow(k, 1.7), sz.x, 1.0),
				Color(0.62, 0.52, 0.95, 0.05 + 0.10 * k))
	# 上辺のハイライト（接地のアンカー）
	draw_rect(Rect2(0, ground - 2.0, sz.x, 2.0), Color(base_col.r * 0.9 + 0.3, base_col.g * 0.9 + 0.35, base_col.b * 0.9 + 0.6, 0.75))
	draw_rect(Rect2(0, ground, sz.x, 1.0), Color(0, 0, 0, 0.5))
	# 手前の濡れた路面の反射（ネオンが伸びる）
	for r: Array in [[0.22, Color(1.0, 0.42, 0.78)], [0.55, Color(0.40, 0.95, 1.0)],
			[0.84, Color(1.0, 0.62, 0.30)]]:
		var rx := sz.x * float(r[0])
		var c: Color = r[1]
		for j in 6:
			var w := 9.0 + j * 5.0
			draw_rect(Rect2(rx - w * 0.5 + sin(pulse * 1.3 + j) * 3.0,
					ground + depth * (0.14 + j * 0.12), w, 3.0),
					Color(c.r, c.g, c.b, 0.17 * (1.0 - j / 7.0)))
	# ネオン管の芯（画面で一番明るい点を短く置く）
	for k in 5:
		draw_rect(Rect2(fposmod(sz.x * (0.08 + k * 0.21) - dist_scroll(), sz.x), ground - 3.0, 14.0, 2.0),
				Color(0.95, 1.0, 1.0))


func dist_scroll() -> float:
	return float(sim.state["dist"]) * 14.0 if sim != null else 0.0


## 扉決断中のイベントカード演出（3枚フロート）。
## ゲーム内容は未確定→「?」カードで期待感を煽る。
func _draw_event_cards(sz: Vector2, font: Font) -> void:
	var n_cards := 3
	var cw := minf(70.0, sz.x * 0.16)
	var ch := cw * 1.32
	var gap := cw * 0.22
	var total := cw * n_cards + gap * (n_cards - 1)
	var cx0 := (sz.x - total) * 0.5
	var base_y := sz.y * 0.14
	var labels := ["宝物", "食料", "罠?"]
	var colors := [Color(1.0, 0.82, 0.3), Color(0.4, 0.95, 0.65), Color(1.0, 0.42, 0.45)]
	for i in n_cards:
		var bob := sin(pulse * 2.0 + i * 1.1) * 4.0
		var x := cx0 + i * (cw + gap)
		var y := base_y + bob
		# カード本体
		draw_rect(Rect2(x, y, cw, ch), Color(0.09, 0.07, 0.16, 0.93))
		draw_rect(Rect2(x, y, cw, ch), colors[i], false, 1.5)
		# 上辺カラーバー
		draw_rect(Rect2(x, y, cw, 4.0), colors[i])
		# ? マーク（大きく中央）
		var qs := int(cw * 0.55)
		var qw := font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, qs).x
		draw_string(font, Vector2(x + (cw - qw) * 0.5, y + ch * 0.58),
				"?", HORIZONTAL_ALIGNMENT_LEFT, -1, qs, Color(colors[i].r, colors[i].g, colors[i].b, 0.85))
		# 下部ラベル
		var lfs := int(cw * 0.19)
		var lw := font.get_string_size(labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x
		draw_string(font, Vector2(x + (cw - lw) * 0.5, y + ch - 8.0),
				labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, Color(0.85, 0.92, 1.0, 0.8))


## 階層ゴールのオーブ（右端・常時表示）。階層終端/ボス位置の視覚的アンカー。
func _draw_goal_orb(sz: Vector2, ground: float, dist: float, font: Font) -> void:
	var prog := fmod(dist, KuroData.FLOOR_LEN) / KuroData.FLOOR_LEN
	var orb_x := sz.x * 0.91
	var orb_y := ground - 30.0
	var r_base := 18.0
	# ボス近接（>85%）なら赤みが強く脈動
	var near_boss := prog > 0.85
	var r := r_base * (1.0 + 0.08 * sin(pulse * (3.5 if near_boss else 1.8)))
	var inner_col := Color(1.0, 0.4, 0.45) if near_boss else Color(0.4, 0.9, 1.0)
	var outer_col := Color(inner_col.r, inner_col.g, inner_col.b, 0.15 + 0.08 * sin(pulse * 2.0))
	draw_circle(Vector2(orb_x, orb_y), r * 2.2, outer_col)
	draw_circle(Vector2(orb_x, orb_y), r * 1.35, Color(inner_col.r, inner_col.g, inner_col.b, 0.30))
	draw_circle(Vector2(orb_x, orb_y), r, Color(inner_col.r * 0.6, inner_col.g * 0.6, inner_col.b * 0.6, 0.85))
	draw_circle(Vector2(orb_x, orb_y), r * 0.5, inner_col)
	# 接続ライン（オーブ→地面）
	draw_line(Vector2(orb_x, orb_y + r), Vector2(orb_x, ground),
			Color(inner_col.r, inner_col.g, inner_col.b, 0.3), 1.5)
	# ラベル
	var lbl := "BOSS" if near_boss else "GOAL"
	var lfs := 11
	var lw := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x
	draw_string(font, Vector2(orb_x - lw * 0.5, orb_y + r + 14.0),
			lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, Color(inner_col.r, inner_col.g, inner_col.b, 0.8))


## ダメージ数字ポップアップ（スクリーン層で描く）。
func _draw_damage_numbers(font: Font) -> void:
	for p in _damage_pops:
		var prog := float(p["t"]) / 1.2
		var y := float(p["y"]) - prog * 44.0
		var alpha := 1.0 - prog * prog
		# 序盤は大きく、後半は小さく消えていく
		var fs := int(lerp(26.0, 16.0, prog))
		var col: Color = p["col"]
		var txt := str(int(p["val"]))
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var px := float(p["x"]) - tw * 0.5
		# 影（1px ずらし）
		draw_string(font, Vector2(px + 1.5, y + 1.5), txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, alpha * 0.6))
		draw_string(font, Vector2(px, y), txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.r, col.g, col.b, alpha))


## 敵の足元の赤い接地リング（脈動）。「敵はここに立っている」を最短で伝える。
func _draw_enemy_ring(feet: Vector2, rx: float) -> void:
	var p := 0.5 + 0.5 * sin(pulse * 3.0)
	var k := 1.0 + 0.07 * p
	var col := Color(1.0, 0.22, 0.26, 0.34 + 0.24 * p)
	for scale: float in [1.0, 0.62]:
		var pts := PackedVector2Array()
		for i in 21:
			var a := TAU * i / 20.0
			pts.append(feet + Vector2(0, 1) + Vector2(cos(a) * rx * k * scale,
					sin(a) * rx * k * scale * 0.30))
		draw_polyline(pts, Color(col.r, col.g, col.b, col.a * (1.0 if scale > 0.9 else 0.6)), 2.0)
