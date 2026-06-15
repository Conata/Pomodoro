class_name RenovView
extends Control
## 改装ツリー（TBHルーンツリー準拠：マップ型グリッド・隣接解放）の描画とタップ判定。
## 解放済み=紫塗り、解放可能=明滅する縁、未到達=沈んだ暗色（オカルト＝紫で識別）。

signal node_tapped(node_id: String)

const CELL := 86.0
const RADIUS := 27.0
const RUNE := Color("8e6bc7")       # 紫＝オカルト/精神世界（UIKit.ACCENT と一致）
const RUNE_DIM := Color("3a2f4a")   # 未到達の沈んだ縁

var sim: KuroSim = null
var pulse := 0.0
var _tex: Dictionary = {}  # id -> Texture2D

const TEX_SIZE := 42.0  # 円内に収まるアイコンサイズ (RADIUS*2 - 余白)


func _ready() -> void:
	custom_minimum_size = Vector2(640, 660)
	for id in KuroData.RENOV_NODES:
		var path := "res://assets/generated/renov/%s.png" % id
		if ResourceLoader.exists(path):
			_tex[id] = load(path)


func _process(delta: float) -> void:
	pulse += delta
	if visible:
		queue_redraw()


func _node_center(id: String) -> Vector2:
	var pos: Array = KuroData.RENOV_NODES[id]["pos"]
	return Vector2(size.x * 0.5 + float(pos[0]) * CELL, size.y * 0.5 + float(pos[1]) * CELL)


func _draw() -> void:
	if sim == null:
		return
	var font := get_theme_default_font()
	for id in KuroData.RENOV_NODES:
		for p in KuroData.RENOV_NODES[id]["prev"]:
			var owned: bool = id in sim.state["renov"]
			draw_line(_node_center(String(p)), _node_center(id),
					Color(RUNE.r, RUNE.g, RUNE.b, 0.5) if owned else RUNE_DIM, 3.0)
	for id in KuroData.RENOV_NODES:
		var node: Dictionary = KuroData.RENOV_NODES[id]
		var c := _node_center(id)
		var owned: bool = id in sim.state["renov"]
		var avail: bool = sim.renov_available(id)
		var affordable: bool = avail and int(sim.state["gold"]) >= int(node["cost"])
		if owned:
			draw_circle(c, RADIUS, DS.SURFACE_2)
			draw_arc(c, RADIUS, 0, TAU, 32, RUNE, 3.0)
		elif avail:
			var a: float = (0.5 + 0.3 * sin(pulse * 3.0)) if affordable else 0.35
			draw_circle(c, RADIUS, DS.SURFACE)
			draw_arc(c, RADIUS, 0, TAU, 32, Color(RUNE.r, RUNE.g, RUNE.b, a + 0.3), 3.0)
		else:
			draw_circle(c, RADIUS, Color(0.08, 0.07, 0.10))
			draw_arc(c, RADIUS, 0, TAU, 32, RUNE_DIM, 2.0)
		var label_color := DS.TEXT if owned or avail else DS.TEXT_MUTE
		var nm: String = node["name"]
		var w := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_CENTER, -1, 15).x
		draw_string(font, c + Vector2(-w * 0.5, RADIUS + 19), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, label_color)
		if id in _tex:
			var alpha := 1.0 if owned else (0.75 if avail else 0.3)
			var half := TEX_SIZE * 0.5
			draw_texture_rect(_tex[id], Rect2(c - Vector2(half, half), Vector2(TEX_SIZE, TEX_SIZE)),
					false, Color(1, 1, 1, alpha))
			if not owned:
				var cost := "%dG" % int(node["cost"])
				var cw := font.get_string_size(cost, HORIZONTAL_ALIGNMENT_CENTER, -1, 13).x
				draw_string(font, c + Vector2(-cw * 0.5, RADIUS + 34), cost,
						HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DS.WARM if avail else DS.TEXT_MUTE)
		elif owned:
			var mw := font.get_string_size("●", HORIZONTAL_ALIGNMENT_CENTER, -1, 18).x
			draw_string(font, c + Vector2(-mw * 0.5, 7), "●", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, RUNE)
		else:
			var cost := "%dG" % int(node["cost"])
			var cw := font.get_string_size(cost, HORIZONTAL_ALIGNMENT_CENTER, -1, 13).x
			draw_string(font, c + Vector2(-cw * 0.5, 6), cost, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
					DS.WARM if avail else DS.TEXT_MUTE)


func _gui_input(event: InputEvent) -> void:
	var tapped: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed)
	if not tapped:
		return
	for id in KuroData.RENOV_NODES:
		if _node_center(id).distance_to(event.position) <= RADIUS + 8.0:
			node_tapped.emit(id)
			accept_event()
			return
