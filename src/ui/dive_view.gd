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

const FX_DEFS := {
	"explosion": {"file": "res://assets/third_party/effects/explosion2.png", "size": 50, "frames": 18, "fps": 24.0},
	"lightning": {"file": "res://assets/third_party/effects/lightning_strike.png", "size": 66, "frames": 13, "fps": 22.0},
	"smoke": {"file": "res://assets/third_party/effects/smoke.png", "size": 64, "frames": 13, "fps": 14.0},
	"song": {"file": "res://assets/third_party/effects/lightning_strike.png", "size": 66, "frames": 13, "fps": 26.0},
	"heal": {"file": "res://assets/generated/fx/heal.png", "size": 48, "frames": 10, "fps": 18.0},
}

var sim: KuroSim = null
var pulse := 0.0
var _tex_cache := {}
var _fx_active: Array = []
var _bubble := {}  # {girl, text, t}


func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## キャラのセリフ吹き出しを数秒表示。
func say(girl_id: String, text: String) -> void:
	_bubble = {"girl": girl_id, "text": text, "t": 3.6}


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
	if visible:
		queue_redraw()


func spawn_fx(kind: String, at: String = "enemy") -> void:
	if not FX_DEFS.has(kind) or _fx_active.size() >= FX_MAX:
		return
	_fx_active.append({"kind": kind, "at": at, "t": 0.0})


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


func _draw_sprite(tex: Texture2D, foot: Vector2, flip: bool = false, tint: Color = TINT) -> void:
	var s := tex.get_size() * SCALE
	var rect := Rect2(foot - Vector2(s.x * 0.5, s.y), s)
	if flip:
		rect = Rect2(rect.position + Vector2(rect.size.x, 0), Vector2(-rect.size.x, rect.size.y))
	draw_texture_rect(tex, rect, false, tint)


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
	var bg: Color = biome["color"]
	# 背景：深い青の縦グラデーション
	draw_rect(Rect2(Vector2.ZERO, sz), Color(bg.r * 0.4, bg.g * 0.4, bg.b * 0.55))
	# 電脳深層の摩天楼（視差スクロール）。バイオーム色で淡く染める
	var dist := float(sim.state["dist"])
	var city_tint := Color(bg.r * 1.6 + 0.4, bg.g * 1.6 + 0.5, bg.b * 1.6 + 0.6, 0.9)
	_draw_parallax("bg/city_far.png", dist * 0.10, sz.y * 0.40, city_tint)
	_draw_parallax("bg/city_mid.png", dist * 0.22, sz.y * 0.46, Color(city_tint.r, city_tint.g, city_tint.b, 1.0))
	draw_rect(Rect2(0, sz.y * 0.6, sz.x, sz.y * 0.4), Color(0.02, 0.04, 0.10, 0.4))
	_draw_lightshaft(sz)

	var progress := fmod(dist, KuroData.FLOOR_LEN) / KuroData.FLOOR_LEN
	draw_rect(Rect2(0, 0, sz.x, 5), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(0, 0, sz.x * progress, 5), DS.ACCENT)

	var head := "B%dF %s  %dm" % [fl + 1, biome["name"], int(dist)]
	draw_string(font, Vector2(14, 36), head, HORIZONTAL_ALIGNMENT_LEFT, -1, DS.T_SUB, DS.TEXT)
	if int(run.get("banked", 0)) > 0:
		draw_string(font, Vector2(sz.x - 190, 36), "送付済の箱 ×%d" % int(run["banked"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, DS.ACCENT)

	var ground := sz.y * 0.80
	draw_line(Vector2(0, ground), Vector2(sz.x, ground), DS.LINE, 2.0)

	var in_combat: bool = sim.state["in_combat"]
	var door_open := float(run["door_pending"]) > 0.0
	var mode := "idle" if in_combat or door_open else "run"

	# 扉（クイック決断バナー中）
	if door_open:
		var door_tex := _tex(FRAME_DIR + "doors_leaf_closed.png")
		if door_tex != null:
			_draw_sprite(door_tex, Vector2(sz.x * 0.5, ground), false, Color(0.8, 0.9, 1.3))

	# 戦闘中の突進モーション（味方は右へ、敵は左へ、交互に踏み込む）
	var lunge_party := (7.0 * maxf(0.0, sin(pulse * 5.0))) if in_combat else 0.0
	var lunge_enemy := (7.0 * maxf(0.0, sin(pulse * 5.0 + PI))) if in_combat else 0.0

	# 潜行メンバー（左）
	var ds: Array = sim.divers()
	for i in ds.size():
		var id: String = ds[i]
		var x := 56.0 + i * 60.0 + lunge_party
		var alive := float(sim.state["hp"].get(id, 0.0)) > 0.0
		var tex := _anim_tex(String(KuroData.GIRLS[id]["sprite"]), mode if alive else "idle")
		if tex != null:
			_draw_sprite(tex, Vector2(x, ground), false, TINT if alive else Color(0.25, 0.3, 0.45))
			if alive:
				_draw_hp(x, ground - tex.get_size().y * SCALE - 10.0,
						float(sim.state["hp"][id]) / sim.girl_maxhp(id))
		else:
			draw_circle(Vector2(x, ground - 14), 12.0, KuroData.GIRLS[id]["color"])

	# 敵（右・左向き）
	var boss_mob := {}
	for i in sim.state["mobs"].size():
		var m: Dictionary = sim.state["mobs"][i]
		var x: float = sz.x - 90.0 - i * 58.0 - lunge_enemy
		var tex2 := _anim_tex(String(m.get("sprite", "")), "idle")
		var ratio := clampf(float(m["hp"]) / float(m["max_hp"]), 0.0, 1.0)
		var tint: Color = Color(1.0, 0.55, 0.6) if m["boss"] else (Color(0.9, 0.75, 1.1) if m["elite"] else TINT)
		if m["boss"]:
			boss_mob = m
			# ボスは一回り大きく、脈動するオーラ
			draw_circle(Vector2(x, ground - 30), 40.0 + 4.0 * sin(pulse * 3.0), Color(1.0, 0.3, 0.35, 0.16))
		if tex2 != null:
			_draw_sprite(tex2, Vector2(x, ground), true, tint)
			_draw_hp(x, ground - tex2.get_size().y * SCALE - 10.0, ratio, 44.0 if m["boss"] else 32.0)
		else:
			draw_circle(Vector2(x, ground - 14), 16.0 if m["boss"] else 10.0, tint)

	# ボス演出：上部の専用HPバー＋ラベル＋赤いふち
	if not boss_mob.is_empty():
		_draw_boss_stage(sz, font, boss_mob)

	_draw_fx(ground)
	_draw_rain(sz)

	# セリフ吹き出し（潜行中のキャラの掛け合い）
	if not _bubble.is_empty():
		var bi := ds.find(String(_bubble["girl"]))
		if bi >= 0:
			_draw_bubble(font, Vector2(56.0 + bi * 60.0, ground - 64.0),
					String(KuroData.GIRLS[_bubble["girl"]]["name"]), String(_bubble["text"]))

	var status := "進軍中…"
	if door_open:
		status = "増築された扉の前で足が止まる（%d秒）" % int(ceil(float(run["door_pending"])))
	elif int(run["resyncs"]) > 0 and in_combat:
		status = "戦闘中（再同期 %d 回目）" % int(run["resyncs"])
	elif in_combat:
		status = "戦闘中"
	draw_string(font, Vector2(14, ground + 30), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
			Color(0.95, 0.75, 0.8) if in_combat else Color(0.7, 0.85, 1.0, 0.6))
