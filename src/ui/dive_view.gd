class_name DiveView
extends Control
## 潜行ビュー。集中中は「見ない前提」（DESIGN.md コアループ）なので、
## 進軍の雰囲気が一目で分かる最小限の描画に留める。
## スプライトは 0x72 DungeonTilesetII（CC0）。見つからない場合は図形で代替。

const FRAME_DIR := "res://assets/third_party/dungeon/frames/"
const FX_DIR := "res://assets/third_party/effects/"
const SCALE := 3.0
const ANIM_FPS := 6.0
const FX_MAX := 6

# 横一列のスプライトシート（pimen / sanctumpixel、フレームは正方形）
const FX_DEFS := {
	"explosion": {"file": "explosion2.png", "size": 50, "frames": 18, "fps": 24.0},
	"lightning": {"file": "lightning_strike.png", "size": 66, "frames": 13, "fps": 22.0},
	"smoke": {"file": "smoke.png", "size": 64, "frames": 13, "fps": 14.0},
}

var sim: GameSim = null
var pulse := 0.0
var _tex_cache := {}
var _fx_active: Array = []


func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # ピクセルアートをくっきり


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


## エフェクト発火。at は "enemy"（右側）か "party"（左側）。
func spawn_fx(kind: String, at: String = "enemy") -> void:
	if not FX_DEFS.has(kind) or _fx_active.size() >= FX_MAX:
		return
	_fx_active.append({"kind": kind, "at": at, "t": 0.0})


func _fx_tex(file: String) -> Texture2D:
	if not _tex_cache.has(file):
		var path := FX_DIR + file
		_tex_cache[file] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[file]


func _draw_fx(ground: float) -> void:
	for fx in _fx_active:
		var def: Dictionary = FX_DEFS[fx["kind"]]
		var tex := _fx_tex(String(def["file"]))
		if tex == null:
			continue
		var frame := int(float(fx["t"]) * float(def["fps"]))
		frame = clampi(frame, 0, int(def["frames"]) - 1)
		var fsize := int(def["size"])
		var region := Rect2(frame * fsize, 0, fsize, fsize)
		var draw_size := fsize * SCALE
		var x := (size.x - 110.0) if fx["at"] == "enemy" else 90.0
		var rect := Rect2(x - draw_size * 0.5, ground - draw_size, draw_size, draw_size)
		draw_texture_rect_region(tex, rect, region)


func _tex(frame_name: String) -> Texture2D:
	if not _tex_cache.has(frame_name):
		var path := FRAME_DIR + frame_name + ".png"
		_tex_cache[frame_name] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[frame_name]


## prefix+モードの現在アニメフレーム（4枚ループ）。無ければ null。
func _anim_tex(prefix: String, mode: String) -> Texture2D:
	if prefix.is_empty():
		return null
	var f := int(pulse * ANIM_FPS) % 4
	var tex := _tex("%s_%s_anim_f%d" % [prefix, mode, f])
	if tex == null:
		tex = _tex("%s_anim_f%d" % [prefix, f])  # necromancer 等は idle/run 区別なし
	return tex


func _draw_sprite(tex: Texture2D, foot: Vector2, flip: bool = false) -> void:
	var sz := tex.get_size() * SCALE
	var rect := Rect2(foot - Vector2(sz.x * 0.5, sz.y), sz)
	if flip:
		rect = Rect2(rect.position + Vector2(rect.size.x, 0), Vector2(-rect.size.x, rect.size.y))
	draw_texture_rect(tex, rect, false)


func _draw_hp_bar(center_x: float, top_y: float, ratio: float, width: float = 34.0) -> void:
	draw_rect(Rect2(center_x - width * 0.5, top_y, width, 5), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(center_x - width * 0.5, top_y, width * clampf(ratio, 0.0, 1.0), 5), Color(0.4, 0.95, 0.5))


func _draw() -> void:
	if sim == null:
		return
	var sz := size
	var layer := sim.current_layer()
	var biome: Dictionary = GameData.BIOMES[layer % GameData.BIOMES.size()]
	var bg: Color = biome["color"]
	draw_rect(Rect2(Vector2.ZERO, sz), Color(bg.r * 0.45, bg.g * 0.45, bg.b * 0.45))
	var font := get_theme_default_font()

	# 層内の進捗バー（上端）
	var dist := float(sim.state["distance"])
	var progress := fmod(dist, GameData.LAYER_LENGTH) / GameData.LAYER_LENGTH
	draw_rect(Rect2(0, 0, sz.x, 6), Color(0, 0, 0, 0.4))
	draw_rect(Rect2(0, 0, sz.x * progress, 6), Color(1.0, 0.45, 0.4))

	var head := "第%d層 %s  %dm" % [layer + 1, biome["name"], int(dist)]
	draw_string(font, Vector2(14, 36), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.9))

	var ground := sz.y * 0.78
	draw_line(Vector2(0, ground), Vector2(sz.x, ground), Color(1, 1, 1, 0.15), 2.0)

	# 宝箱バッジ（右上）
	var chests := int(sim.state["chests"])
	if chests > 0:
		var chest_tex := _tex("chest_full_open_anim_f0")
		if chest_tex != null:
			draw_texture_rect(chest_tex, Rect2(sz.x - 92, 14, 32, 32), false)
		draw_string(font, Vector2(sz.x - 54, 38), "×%d" % chests, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1.0, 0.85, 0.4))

	var run_active: bool = sim.state["run"]["active"]
	if not run_active:
		draw_string(font, Vector2(14, sz.y * 0.5), "待機中 — タスクを書いて出発しよう",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.6))
		return

	var in_combat: bool = sim.state["in_combat"]
	var mobs: Array = sim.state["mobs"]

	# パーティ（左側）。移動中は run、戦闘中は idle アニメ
	var heroes: Array = sim.state["heroes"]
	var class_colors := {
		"warrior": Color(0.95, 0.5, 0.4),
		"mage": Color(0.5, 0.6, 1.0),
		"priest": Color(0.95, 0.9, 0.5),
		"rogue": Color(0.6, 0.95, 0.6),
	}
	var mode := "idle" if in_combat or float(sim.state["retreat_cd"]) > 0.0 else "run"
	for i in heroes.size():
		var h: Dictionary = heroes[i]
		var x := 52.0 + i * 58.0
		var alive := float(h["hp"]) > 0.0
		var prefix: String = GameData.CLASS_SPRITES.get(h["cls"], "")
		var tex := _anim_tex(prefix, mode if alive else "idle")
		if tex != null:
			if not alive:
				var dead_rect := Rect2(Vector2(x - tex.get_size().x * SCALE * 0.5, ground - tex.get_size().y * SCALE), tex.get_size() * SCALE)
				draw_texture_rect(tex, dead_rect, false, Color(0.35, 0.35, 0.35))
			else:
				_draw_sprite(tex, Vector2(x, ground))
			_draw_hp_bar(x, ground - tex.get_size().y * SCALE - 12.0, float(h["hp"]) / sim.hero_maxhp(h))
		else:
			var c: Color = class_colors.get(h["cls"], Color.WHITE) if alive else Color(0.3, 0.3, 0.3)
			draw_circle(Vector2(x, ground - 16), 13.0, c)
			_draw_hp_bar(x, ground - 46, float(h["hp"]) / sim.hero_maxhp(h), 28.0)

	# 敵（右側、左向き）
	for i in mobs.size():
		var m: Dictionary = mobs[i]
		var boss: bool = m["boss"]
		var x := sz.x - 86.0 - i * 60.0
		var tex := _anim_tex(String(m.get("sprite", "")), "idle")
		var ratio := clampf(float(m["hp"]) / float(m["max_hp"]), 0.0, 1.0)
		if tex != null:
			_draw_sprite(tex, Vector2(x, ground), true)
			_draw_hp_bar(x, ground - tex.get_size().y * SCALE - 12.0, ratio, 44.0 if boss else 34.0)
		else:
			var r := 24.0 if boss else 12.0
			draw_circle(Vector2(x, ground - r - 2), r, Color(0.85, 0.25, 0.3) if boss else Color(0.7, 0.3, 0.5))
			_draw_hp_bar(x, ground - r * 2 - 14, ratio, 32.0)

	_draw_fx(ground)

	if float(sim.state["retreat_cd"]) > 0.0:
		draw_string(font, Vector2(14, ground + 32), "態勢を立て直している…", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.7, 0.5))
	elif mobs.is_empty():
		draw_string(font, Vector2(14, ground + 32), "進軍中…", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.5))
	else:
		draw_string(font, Vector2(14, ground + 32), "戦闘中！", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.6, 0.55))
