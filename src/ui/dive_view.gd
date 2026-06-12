class_name DiveView
extends Control
## 潜行ビュー。集中中は「見ない前提」（DESIGN.md コアループ）なので、
## 進軍の雰囲気が一目で分かる最小限の描画に留める。

var sim: GameSim = null
var pulse := 0.0


func _ready() -> void:
	clip_contents = true


func _process(delta: float) -> void:
	pulse += delta
	if visible:
		queue_redraw()


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

	# 見出し
	var head := "第%d層 %s  %dm" % [layer + 1, biome["name"], int(dist)]
	draw_string(font, Vector2(14, 36), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.9))

	var ground := sz.y * 0.72
	draw_line(Vector2(0, ground), Vector2(sz.x, ground), Color(1, 1, 1, 0.15), 2.0)

	var run_active: bool = sim.state["run"]["active"]
	if not run_active:
		var msg := "待機中 — タスクを書いて出発しよう"
		draw_string(font, Vector2(14, sz.y * 0.5), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.6))
		return

	# パーティ（左側）
	var heroes: Array = sim.state["heroes"]
	var class_colors := {
		"warrior": Color(0.95, 0.5, 0.4),
		"mage": Color(0.5, 0.6, 1.0),
		"priest": Color(0.95, 0.9, 0.5),
		"rogue": Color(0.6, 0.95, 0.6),
	}
	var glow := 0.25 + 0.15 * sin(pulse * 2.0)
	draw_circle(Vector2(80, ground - 24), 56.0, Color(1.0, 0.4, 0.4, glow * 0.4))
	for i in heroes.size():
		var h: Dictionary = heroes[i]
		var x := 50.0 + i * 40.0
		var alive := float(h["hp"]) > 0.0
		var c: Color = class_colors.get(h["cls"], Color.WHITE)
		if not alive:
			c = Color(0.3, 0.3, 0.3)
		draw_circle(Vector2(x, ground - 16), 13.0, c)
		var ratio := clampf(float(h["hp"]) / sim.hero_maxhp(h), 0.0, 1.0)
		draw_rect(Rect2(x - 14, ground - 42, 28, 4), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(x - 14, ground - 42, 28 * ratio, 4), Color(0.4, 0.95, 0.5))

	# 敵（右側）
	var mobs: Array = sim.state["mobs"]
	for i in mobs.size():
		var m: Dictionary = mobs[i]
		var x := sz.x - 70.0 - i * 44.0
		var boss: bool = m["boss"]
		var r := 24.0 if boss else 12.0
		draw_circle(Vector2(x, ground - r - 2), r, Color(0.85, 0.25, 0.3) if boss else Color(0.7, 0.3, 0.5))
		var ratio := clampf(float(m["hp"]) / float(m["max_hp"]), 0.0, 1.0)
		draw_rect(Rect2(x - 16, ground - r * 2 - 14, 32, 4), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(x - 16, ground - r * 2 - 14, 32 * ratio, 4), Color(0.95, 0.4, 0.35))

	if float(sim.state["retreat_cd"]) > 0.0:
		draw_string(font, Vector2(14, ground + 32), "態勢を立て直している…", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.7, 0.5))
	elif mobs.is_empty():
		draw_string(font, Vector2(14, ground + 32), "進軍中…", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.5))
	else:
		draw_string(font, Vector2(14, ground + 32), "戦闘中！", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.6, 0.55))
