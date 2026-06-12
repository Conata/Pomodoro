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
	"explosion": {"file": "explosion2.png", "size": 50, "frames": 18, "fps": 24.0},
	"lightning": {"file": "lightning_strike.png", "size": 66, "frames": 13, "fps": 22.0},
	"smoke": {"file": "smoke.png", "size": 64, "frames": 13, "fps": 14.0},
	"song": {"file": "lightning_strike.png", "size": 66, "frames": 13, "fps": 26.0},
}

var sim: KuroSim = null
var pulse := 0.0
var _tex_cache := {}
var _fx_active: Array = []


func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(delta: float) -> void:
	pulse += delta
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


func _draw_hp(center_x: float, top_y: float, ratio: float, width: float = 34.0) -> void:
	draw_rect(Rect2(center_x - width * 0.5, top_y, width, 4), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(center_x - width * 0.5, top_y, width * clampf(ratio, 0.0, 1.0), 4), Color(0.5, 0.9, 1.0))


func _draw_fx(ground: float) -> void:
	for fx in _fx_active:
		var def: Dictionary = FX_DEFS[fx["kind"]]
		var tex := _tex(FX_DIR + String(def["file"]))
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
	var fl := sim.current_floor()
	var biome: Dictionary = KuroData.BIOMES[fl % KuroData.BIOMES.size()]
	var bg: Color = biome["color"]
	# 背景：深い青の縦グラデーション
	draw_rect(Rect2(Vector2.ZERO, sz), Color(bg.r * 0.4, bg.g * 0.4, bg.b * 0.55))
	draw_rect(Rect2(0, sz.y * 0.6, sz.x, sz.y * 0.4), Color(0.02, 0.04, 0.10, 0.55))
	var font := get_theme_default_font()

	var run: Dictionary = sim.state["run"]
	var dist := float(sim.state["dist"])
	var progress := fmod(dist, KuroData.FLOOR_LEN) / KuroData.FLOOR_LEN
	draw_rect(Rect2(0, 0, sz.x, 5), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(0, 0, sz.x * progress, 5), Color(0.45, 0.85, 1.0))

	var head := "B%dF %s  %dm" % [fl + 1, biome["name"], int(dist)]
	draw_string(font, Vector2(14, 36), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.8, 0.92, 1.0))
	if int(run.get("banked", 0)) > 0:
		draw_string(font, Vector2(sz.x - 190, 36), "送付済の箱 ×%d" % int(run["banked"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.55, 0.9, 1.0, 0.9))

	var ground := sz.y * 0.80
	draw_line(Vector2(0, ground), Vector2(sz.x, ground), Color(0.5, 0.8, 1.0, 0.18), 2.0)

	if not run["active"]:
		_draw_rain(sz)
		draw_string(font, Vector2(14, sz.y * 0.5), "雨。開店前。編成を決めて潜る",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.7, 0.85, 1.0, 0.6))
		return

	var in_combat: bool = sim.state["in_combat"]
	var door_open := float(run["door_pending"]) > 0.0
	var mode := "idle" if in_combat or door_open else "run"

	# 扉（クイック決断バナー中）
	if door_open:
		var door_tex := _tex(FRAME_DIR + "doors_leaf_closed.png")
		if door_tex != null:
			_draw_sprite(door_tex, Vector2(sz.x * 0.5, ground), false, Color(0.8, 0.9, 1.3))

	# 潜行メンバー（左）
	var ds: Array = sim.divers()
	for i in ds.size():
		var id: String = ds[i]
		var x := 56.0 + i * 60.0
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
	for i in sim.state["mobs"].size():
		var m: Dictionary = sim.state["mobs"][i]
		var x: float = sz.x - 90.0 - i * 58.0
		var tex2 := _anim_tex(String(m.get("sprite", "")), "idle")
		var ratio := clampf(float(m["hp"]) / float(m["max_hp"]), 0.0, 1.0)
		var tint: Color = Color(1.0, 0.55, 0.6) if m["boss"] else (Color(0.9, 0.75, 1.1) if m["elite"] else TINT)
		if tex2 != null:
			_draw_sprite(tex2, Vector2(x, ground), true, tint)
			_draw_hp(x, ground - tex2.get_size().y * SCALE - 10.0, ratio, 44.0 if m["boss"] else 32.0)
		else:
			draw_circle(Vector2(x, ground - 14), 16.0 if m["boss"] else 10.0, tint)

	_draw_fx(ground)
	_draw_rain(sz)

	var status := "進軍中…"
	if door_open:
		status = "増築された扉の前で足が止まる（%d秒）" % int(ceil(float(run["door_pending"])))
	elif int(run["resyncs"]) > 0 and in_combat:
		status = "戦闘中（再同期 %d 回目）" % int(run["resyncs"])
	elif in_combat:
		status = "戦闘中"
	draw_string(font, Vector2(14, ground + 30), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
			Color(0.95, 0.75, 0.8) if in_combat else Color(0.7, 0.85, 1.0, 0.6))
