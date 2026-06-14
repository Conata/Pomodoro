class_name DiveView
extends Control
## 潜行ビュー（電脳深層）。Rain98 系のビジュアル言語：
## 深い青のモノクローム、絶え間ない雨、シアンの発光、白の斜めバンド。
## スプライトは 0x72 DungeonTilesetII（CC0）を青に沈めて使う。

const FRAME_DIR := "res://assets/third_party/dungeon/frames/"
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
var _fx_active: Array = []
var _bubble := {}  # {girl, text, t}
var _dialog: Array = []  # 直近の掛け合いログ {who,text,col}
# 疑似Camera2D（ノード化せず draw_set_transform で表現＝決定論を崩さず軽い）
var _cam_zoom := 1.04
var _cam_zoom_target := 1.04
var _cam_shake := 0.0
var _was_combat := false
const BASE_ZOOM := 1.04
const VIEWERS_BASE := 8200


func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## キャラのセリフ吹き出しを数秒表示。掛け合いログにも積む（下部の配信ログ）。
func say(girl_id: String, text: String) -> void:
	_bubble = {"girl": girl_id, "text": text, "t": 3.6}
	var col := Color(0.7, 0.85, 1.0)
	if KuroData.GIRLS.has(girl_id):
		col = KuroData.GIRLS[girl_id]["color"]
	_dialog.append({"who": girl_id, "text": text, "col": col})
	while _dialog.size() > 4:
		_dialog.pop_front()


func _process(delta: float) -> void:
	pulse += delta
	if not _bubble.is_empty():
		_bubble["t"] = float(_bubble["t"]) - delta
		if float(_bubble["t"]) <= 0.0:
			_bubble = {}
	var i := 0
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
	if visible:
		queue_redraw()


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


func _anim_tex(prefix: String, mode: String) -> Texture2D:
	if prefix.is_empty():
		return null
	var f := int(pulse * ANIM_FPS) % 4
	var tex := _tex(FRAME_DIR + "%s_%s_anim_f%d.png" % [prefix, mode, f])
	if tex == null:
		tex = _tex(FRAME_DIR + "%s_anim_f%d.png" % [prefix, f])  # necromancer 等
	return tex


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


## 足元の楕円ソフトシャドウ。キャラを地面に「立たせる」ための接地感。
func _draw_shadow(cx: float, ground: float, w: float) -> void:
	var pts := PackedVector2Array()
	var seg := 20
	for k in seg:
		var a := TAU * k / seg
		pts.append(Vector2(cx + cos(a) * w * 0.5, ground + 5.0 + sin(a) * w * 0.16))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.30))


## 提供キャラの横スプライトシート（assets/generated/sprites/<id>/<anim>.png、4コマ）を
## 足元基準でコマ送り描画。青tintはかけず本来の色で出す。あれば true。
## 提供キャラの横スプライトシート（4コマ）を、指定の表示高さ h・足元基準で描く。
## 立ち絵を主役に＝画面に応じて大きく見せる。描いた幅を返す（0=未描画）。
const CHIBI_FRAMES := 4
func _draw_chibi(id: String, foot: Vector2, in_combat: bool, alive: bool, h: float, flip: bool = false) -> float:
	var anim := "attack" if in_combat else "walk_front"
	var tex := _tex("res://assets/generated/sprites/%s/%s.png" % [id, anim])
	if tex == null:
		tex = _tex("res://assets/generated/sprites/%s/walk_front.png" % id)
	if tex == null:  # 暫定：自前シートが無いキャラは全員ユズキで代用
		tex = _tex("res://assets/generated/sprites/yuzuki/%s.png" % anim)
	if tex == null:
		tex = _tex("res://assets/generated/sprites/yuzuki/walk_front.png")
	if tex == null:
		return 0.0
	var fw := tex.get_size().x / float(CHIBI_FRAMES)
	var fh := tex.get_size().y
	var f := int(pulse * ANIM_FPS) % CHIBI_FRAMES
	var sc := h / fh
	var dw := fw * sc
	var rect := Rect2(foot.x - dw * 0.5, foot.y - h, dw, h)
	if flip:
		rect = Rect2(rect.position + Vector2(rect.size.x, 0), Vector2(-rect.size.x, rect.size.y))
	var tint := Color(1, 1, 1) if alive else Color(0.45, 0.47, 0.58)
	draw_texture_rect_region(tex, rect, Rect2(f * fw, 0, fw, fh), tint)
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


func _draw_fx(ground: float) -> void:
	for fx in _fx_active:
		var def: Dictionary = FX_DEFS[fx["kind"]]
		var tex := _tex(String(def["file"]))
		if tex == null:
			continue
		var frame := clampi(int(float(fx["t"]) * float(def["fps"])), 0, int(def["frames"]) - 1)
		var fsize := int(def["size"])
		var dsize := fsize * SCALE
		var x := (size.x - 120.0) if fx["at"] == "enemy" else 100.0
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
	var ground := sz.y * 0.58           # 立ち絵の足元（モックに合わせ画面中段）
	var chibi_h := clampf(sz.y * 0.26, 140.0, 240.0)

	# ====== ワールド層（疑似カメラ：ズーム/緩いパン/被弾シェイク）======
	var zoom := _cam_zoom
	var focus := Vector2(
		sz.x * 0.5 + sin(pulse * 0.22) * sz.x * 0.02 + (sz.x * 0.06 if in_combat else 0.0),
		ground)
	var shake := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _cam_shake
	draw_set_transform(focus * (1.0 - zoom) + shake, 0.0, Vector2(zoom, zoom))

	_draw_explore_bg(sz, biome, dist)
	draw_line(Vector2(0, ground), Vector2(sz.x, ground),
			Color(DS.LINE.r, DS.LINE.g, DS.LINE.b, 0.30), 2.0)

	# 突進モーション＆歩行のゆれ（自動歩行感）
	var lunge_party := (9.0 * maxf(0.0, sin(pulse * 5.0))) if in_combat else 0.0
	var lunge_enemy := (9.0 * maxf(0.0, sin(pulse * 5.0 + PI))) if in_combat else 0.0
	var bob := 0.0 if in_combat else sin(pulse * 3.0) * 3.0

	# 扉（クイック決断バナー中）
	if door_open:
		var door_tex := _tex(FRAME_DIR + "doors_leaf_closed.png")
		if door_tex != null:
			_draw_sprite(door_tex, Vector2(sz.x * 0.5, ground), false, Color(0.8, 0.9, 1.3),
					(chibi_h * 0.9) / door_tex.get_size().y)

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
		var dw := _draw_chibi(id, foot, in_combat, alive, ch, false)
		if dw > 0.0:
			_draw_shadow(x, ground + 2.0, dw * 0.74)
			if alive:
				_draw_hp(x, foot.y - ch - 12.0, float(sim.state["hp"][id]) / sim.girl_maxhp(id),
						maxf(36.0, dw * 0.7))
		else:
			var tex := _anim_tex(String(KuroData.GIRLS[id]["sprite"]), "run" if alive else "idle")
			if tex != null:
				var scl := (ch * 0.9) / tex.get_size().y
				_draw_shadow(x, ground + 2.0, tex.get_size().x * scl * 0.7)
				_draw_sprite(tex, foot, false, TINT if alive else Color(0.25, 0.3, 0.45), scl)
				if alive:
					_draw_hp(x, foot.y - ch - 12.0, float(sim.state["hp"][id]) / sim.girl_maxhp(id))
			else:
				draw_circle(Vector2(x, ground - 14), 12.0, KuroData.GIRLS[id]["color"])

	# 敵（右・前景）：通常はスプライト。戦闘中は赤い✕のうずを重ねる（モック準拠）
	var boss_mob := {}
	var enemy_cx := sz.x * 0.8
	for i in sim.state["mobs"].size():
		var m: Dictionary = sim.state["mobs"][i]
		var x: float = enemy_cx - i * (slot * 0.7) - lunge_enemy
		var tex2 := _anim_tex(String(m.get("sprite", "")), "idle")
		var ratio := clampf(float(m["hp"]) / float(m["max_hp"]), 0.0, 1.0)
		var tint: Color = Color(1.0, 0.55, 0.6) if m["boss"] else (Color(0.9, 0.75, 1.1) if m["elite"] else TINT)
		if m["boss"]:
			boss_mob = m
		if tex2 != null:
			var escl := clampf((ch * 0.62) / tex2.get_size().y, SCALE, 16.0)
			if m["boss"]:
				escl *= 1.3
			_draw_shadow(x, ground + 2.0, tex2.get_size().x * escl * 0.7)
			_draw_sprite(tex2, Vector2(x, ground), true, tint, escl)
			_draw_hp(x, ground - tex2.get_size().y * escl - 10.0, ratio, 48.0 if m["boss"] else 34.0)
		else:
			draw_circle(Vector2(x, ground - 14), 16.0 if m["boss"] else 10.0, tint)
	if in_combat:
		var rr := chibi_h * (0.78 if not boss_mob.is_empty() else 0.5)
		_draw_redx(Vector2(enemy_cx, ground - ch * 0.45), rr, not boss_mob.is_empty())

	_draw_fx(ground)

	# セリフ吹き出し（頭上・ワールド層）
	if not _bubble.is_empty():
		var bi := ds.find(String(_bubble["girl"]))
		if bi >= 0 and bi < party_x.size():
			_draw_bubble(font, Vector2(float(party_x[bi]), ground - ch - 6.0),
					String(KuroData.GIRLS[_bubble["girl"]]["name"]), String(_bubble["text"]))

	# ====== スクリーン層（カメラの影響を受けない配信UI）======
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_rain(sz)
	_draw_stream_chrome(sz, font, fl, biome, dist, in_combat)
	_draw_minimap(sz, font, fl, dist)
	_draw_dialog_log(sz, font)


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
		draw_rect(Rect2(0, sz.y * 0.6, sz.x, sz.y * 0.4), Color(0.01, 0.01, 0.03, 0.42))
		return
	# フォールバック：従来のプロシージャル都市（視差スクロール）
	var bg: Color = biome["color"]
	draw_rect(Rect2(Vector2.ZERO, sz), Color(bg.r * 0.4, bg.g * 0.4, bg.b * 0.55))
	var city_tint := Color(bg.r * 1.6 + 0.4, bg.g * 1.6 + 0.5, bg.b * 1.6 + 0.6, 0.9)
	_draw_parallax("bg/city_far.png", dist * 0.10, sz.y * 0.30, city_tint)
	_draw_parallax("bg/city_mid.png", dist * 0.22, sz.y * 0.36, Color(city_tint.r, city_tint.g, city_tint.b, 1.0))
	draw_rect(Rect2(0, sz.y * 0.5, sz.x, sz.y * 0.5), Color(0.02, 0.04, 0.10, 0.4))
	_draw_lightshaft(sz)


## 敵遭遇のサイン：赤く脈動する✕のうず（ボスは大きく＋外周リング）。
func _draw_redx(center: Vector2, r: float, big: bool) -> void:
	var p := 0.5 + 0.5 * sin(pulse * 3.0)
	draw_circle(center, r * (1.15 + 0.06 * p), Color(0.95, 0.15, 0.2, 0.10 + 0.06 * p))
	draw_circle(center, r * 0.8, Color(0.7, 0.05, 0.12, 0.16))
	var a := r * 0.62
	var w := maxf(4.0, r * 0.12)
	var col := Color(1.0, 0.25, 0.3, 0.85 + 0.15 * p)
	draw_line(center + Vector2(-a, -a), center + Vector2(a, a), col, w)
	draw_line(center + Vector2(-a, a), center + Vector2(a, -a), col, w)
	if big:
		draw_arc(center, r, 0.0, TAU, 48, Color(1.0, 0.3, 0.35, 0.5), 2.0)


## 配信チロップ：左上=階層/探索率、右上=LIVE+配信名+視聴/いいね、
## 中央上=残り時間（配信タイマー）、左下=REC。
func _draw_stream_chrome(sz: Vector2, font: Font, fl: int, biome: Dictionary,
		dist: float, in_combat: bool) -> void:
	var pad := 12.0
	# 左上：階層・区画・探索率
	var pct := int(fmod(dist, KuroData.FLOOR_LEN) / KuroData.FLOOR_LEN * 100.0)
	draw_string(font, Vector2(pad, 26), "B%dF %s" % [fl + 1, String(biome["name"])],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, DS.TEXT)
	draw_string(font, Vector2(pad, 46), "探索率 %d%%" % pct,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.85, 1.0, 0.85))
	# 右上：LIVE バッジ＋配信タイトル
	var streamer := "ムュウ"
	var ds := sim.divers()
	if not ds.is_empty() and KuroData.GIRLS.has(ds[0]):
		streamer = String(KuroData.GIRLS[ds[0]]["name"])
	var title := "%sの都市伝説LIVE" % streamer
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	if fposmod(pulse, 1.4) < 1.1:
		draw_circle(Vector2(sz.x - pad - tw - 50.0, 22), 5.0, Color(1.0, 0.2, 0.25))
	draw_string(font, Vector2(sz.x - pad - tw - 40.0, 27), "LIVE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.35, 0.4))
	draw_string(font, Vector2(sz.x - pad - tw, 27), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, DS.TEXT)
	# 視聴者数・いいね（distベースで緩く増える＋ゆらぎ）
	var viewers := VIEWERS_BASE + int(dist * 1.1) + int(40.0 * sin(pulse * 0.7))
	var likes := viewers * 26 / 10
	var stat := "視聴 %s ・ いいね %s" % [_fmt_comma(viewers), _fmt_k(likes)]
	var sw := font.get_string_size(stat, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, Vector2(sz.x - pad - sw, 48), stat,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.9, 1.0, 0.85))
	# 中央上：残り時間（配信タイマー）
	if remaining >= 0.0:
		var t := _mmss(remaining)
		var tsz := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 32)
		draw_string(font, Vector2((sz.x - tsz.x) * 0.5 + 1, 43), t,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(0, 0, 0, 0.5))
		draw_string(font, Vector2((sz.x - tsz.x) * 0.5, 42), t,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 32, DS.ACCENT)
	# 左下：REC（掛け合いログの上に重ねない位置）
	var ry := sz.y - 124.0
	if fposmod(pulse, 1.2) < 0.9:
		draw_circle(Vector2(pad + 6, ry - 5), 5.0, Color(1.0, 0.2, 0.25))
	draw_string(font, Vector2(pad + 16, ry), "REC", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.5, 0.55))
	if in_combat:
		draw_string(font, Vector2(pad + 64, ry), "交戦中", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.6, 0.65))


## 左上のミニマップ（10%大）。階層の進行をノード列で表す。
func _draw_minimap(sz: Vector2, font: Font, fl: int, dist: float) -> void:
	var w := sz.x * 0.28
	var h := maxf(46.0, sz.y * 0.11)
	var x := 12.0
	var y := 64.0
	draw_rect(Rect2(x, y, w, h), Color(0.03, 0.04, 0.08, 0.55))
	draw_rect(Rect2(x, y, w, h), Color(0.4, 0.85, 1.0, 0.25), false, 1.0)
	var cells := 6
	var prog := fmod(dist, KuroData.FLOOR_LEN) / KuroData.FLOOR_LEN
	var cur := clampi(int(prog * cells), 0, cells - 1)
	var cw := w / float(cells + 1)
	var cy := y + h * 0.46
	for k in cells:
		var cx := x + cw * (k + 1)
		if k > 0:
			draw_line(Vector2(x + cw * k, cy), Vector2(cx, cy), Color(0.4, 0.7, 1.0, 0.4), 1.5)
		if k == cur:
			draw_circle(Vector2(cx, cy), 4.5 + 1.5 * sin(pulse * 4.0), Color(0.4, 1.0, 0.85))
		elif k < cur:
			draw_circle(Vector2(cx, cy), 3.5, Color(0.5, 0.8, 1.0, 0.7))
		else:
			draw_circle(Vector2(cx, cy), 3.0, Color(0.4, 0.5, 0.7, 0.4))
	draw_string(font, Vector2(x + 6, y + h - 6), "MAP B%dF" % (fl + 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.8, 1.0, 0.7))


## 左下の掛け合いログ（直近4行・下ほど新しく濃い）。
func _draw_dialog_log(sz: Vector2, font: Font) -> void:
	var pad := 12.0
	var fs := 16
	var lh := 22.0
	var n := _dialog.size()
	if n == 0:
		return
	var y0 := sz.y - 16.0 - n * lh
	draw_rect(Rect2(0, y0 - 8, sz.x * 0.64, n * lh + 12), Color(0.02, 0.02, 0.05, 0.5))
	for i in n:
		var d: Dictionary = _dialog[i]
		var who := String(d["who"])
		if KuroData.GIRLS.has(d["who"]):
			who = String(KuroData.GIRLS[d["who"]]["name"])
		var y := y0 + i * lh + 16.0
		var alpha := lerpf(0.55, 1.0, float(i + 1) / float(n))
		var col: Color = d["col"]
		draw_string(font, Vector2(pad + 2, y), who, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(col.r, col.g, col.b, alpha))
		var nw := font.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(pad + 2 + nw, y), "「%s」" % String(d["text"]),
				HORIZONTAL_ALIGNMENT_LEFT, int(sz.x * 0.60 - nw), fs, Color(0.92, 0.95, 1.0, alpha))


func _fmt_comma(v: int) -> String:
	var s := str(v)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out


func _fmt_k(v: int) -> String:
	return ("%.1fK" % (v / 1000.0)) if v >= 1000 else str(v)


func _mmss(sec: float) -> String:
	var s := int(ceil(sec))
	return "%02d:%02d" % [int(s / 60.0), s % 60]
