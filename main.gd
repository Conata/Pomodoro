extends Node2D
## パイプライン疎通確認シーン。
## タップカウンタとネオンの脈動だけの最小構成 — これがスマホで
## 動いたら、ビルド→Pages→実機のループは開通している。

var taps: int = 0
var pulse: float = 0.0

@onready var label: Label = $UI/Label
@onready var button: Button = $UI/Button


func _ready() -> void:
	button.pressed.connect(_on_button_pressed)
	_refresh()


func _process(delta: float) -> void:
	pulse += delta
	queue_redraw()


func _draw() -> void:
	var alpha: float = 0.35 + 0.25 * sin(pulse * 2.0)
	var center: Vector2 = get_viewport_rect().size * 0.5
	draw_circle(center, 140.0, Color(1.0, 0.35, 0.35, alpha))
	draw_circle(center, 90.0, Color(0.06, 0.04, 0.08, 1.0))


func _on_button_pressed() -> void:
	taps += 1
	_refresh()


func _refresh() -> void:
	label.text = "黒猫飯店 — pipeline OK\nタップ: %d" % taps
