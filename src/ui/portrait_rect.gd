class_name PortraitRect
extends Control
## ステータス画面などで高解像度キャラを表示する枠。
## Portrait.draw_into に丸投げ（本物 art があれば自動で差し替わる）。

var girl_id := "mil"
var pulse := 0.0


func _process(delta: float) -> void:
	pulse += delta
	if visible:
		queue_redraw()


func _draw() -> void:
	# 枠とソフトな背景
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.06, 0.16))
	Portrait.draw_into(self, girl_id, Rect2(Vector2.ZERO, size), pulse)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.8, 1.0, 0.35), false, 1.0)
