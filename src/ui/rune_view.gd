class_name RuneView
extends Control
## ルーンツリーのマップ描画とタップ判定。
## 解放済み=塗り、解放可能=シアン縁（買えるなら明るく）、未到達=灰。

signal node_tapped(node_id: String)

const CELL := 86.0
const RADIUS := 27.0

var sim: GameSim = null
var pulse := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(640, 680)


func _process(delta: float) -> void:
	pulse += delta
	if visible:
		queue_redraw()


func _node_center(id: String) -> Vector2:
	var pos: Array = GameData.RT_NODES[id]["pos"]
	return Vector2(size.x * 0.5 + float(pos[0]) * CELL, size.y * 0.5 + float(pos[1]) * CELL)


func _draw() -> void:
	if sim == null:
		return
	var font := get_theme_default_font()
	# エッジ
	for id in GameData.RT_NODES:
		for p in GameData.RT_NODES[id]["prev"]:
			var owned: bool = id in sim.state["runes"]
			draw_line(_node_center(String(p)), _node_center(id), Color(0.6, 1.0, 0.9, 0.5) if owned else Color(1, 1, 1, 0.15), 3.0)
	# ノード
	for id in GameData.RT_NODES:
		var node: Dictionary = GameData.RT_NODES[id]
		var c := _node_center(id)
		var owned: bool = id in sim.state["runes"]
		var avail: bool = sim.rune_available(id)
		var affordable: bool = avail and int(sim.state["gold"]) >= int(node["cost"])
		if owned:
			draw_circle(c, RADIUS, Color(0.15, 0.5, 0.4))
			draw_arc(c, RADIUS, 0, TAU, 32, Color(0.5, 1.0, 0.85), 3.0)
		elif avail:
			var a := 0.5 + 0.3 * sin(pulse * 3.0) if affordable else 0.35
			draw_circle(c, RADIUS, Color(0.1, 0.25, 0.3))
			draw_arc(c, RADIUS, 0, TAU, 32, Color(0.4, 0.9, 1.0, a + 0.3), 3.0)
		else:
			draw_circle(c, RADIUS, Color(0.15, 0.15, 0.18))
			draw_arc(c, RADIUS, 0, TAU, 32, Color(1, 1, 1, 0.12), 2.0)
		var label_color := Color(1, 1, 1, 0.9) if owned or avail else Color(1, 1, 1, 0.35)
		var nm: String = node["name"]
		var w := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_CENTER, -1, 16).x
		draw_string(font, c + Vector2(-w * 0.5, RADIUS + 20), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, label_color)
		if not owned:
			var cost := "%dG" % int(node["cost"])
			var cw := font.get_string_size(cost, HORIZONTAL_ALIGNMENT_CENTER, -1, 14).x
			draw_string(font, c + Vector2(-cw * 0.5, 6), cost, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.85, 0.4, 0.9) if avail else Color(1, 1, 1, 0.3))
		else:
			var mark := "✓"
			var mw := font.get_string_size(mark, HORIZONTAL_ALIGNMENT_CENTER, -1, 18).x
			draw_string(font, c + Vector2(-mw * 0.5, 7), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.6, 1.0, 0.85))


func _gui_input(event: InputEvent) -> void:
	var tap_pos := Vector2.ZERO
	var tapped := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tap_pos = event.position
		tapped = true
	elif event is InputEventScreenTouch and event.pressed:
		tap_pos = event.position
		tapped = true
	if not tapped:
		return
	for id in GameData.RT_NODES:
		if _node_center(id).distance_to(tap_pos) <= RADIUS + 8.0:
			node_tapped.emit(id)
			accept_event()
			return
