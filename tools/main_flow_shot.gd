extends SceneTree
## メイン→探索出発→潜航（KuroSim駆動）のフローを撮る。
## 出発後にアンカーを過去へずらして戦闘まで早送りし、潜航画面を保存。

const OUT := "res://_out/"
var _main: Node = null
var _frame := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_main = load("res://main.tscn").instantiate()
	get_root().add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 16:
		# 探索へ出発（KuroSim start_run → 潜航画面）
		_main._on_home_action("depart")
		# 25 シム秒ぶん早送り（遭遇→戦闘まで進める）
		_main.sim.state["run"]["anchor"] = float(_main.sim.state["run"]["anchor"]) - 25.0
	if _frame == 64:
		get_root().get_texture().get_image().save_png(OUT + "main_dive.png")
		print("saved: main_dive  in_combat=%s dist=%.0f" % [
			str(_main.sim.state["in_combat"]), float(_main.sim.state["dist"])])
		return true
	return false
