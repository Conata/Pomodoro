extends SceneTree
## 1日ループ検証：出発→全行程早送り→浮上（精算・翌朝）→ホーム（Day2・売上）を撮る。

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
		_main._on_home_action("depart")
		# 全行程（80秒）を超えて早送り → 浮上トリガ
		_main.sim.state["run"]["anchor"] = float(_main.sim.state["run"]["anchor"]) - 95.0
	if _frame == 80:
		get_root().get_texture().get_image().save_png(OUT + "main_loop.png")
		print("saved: main_loop  day=%d gold=%d run_active=%s" % [
			int(_main.sim.state["day"]), int(_main.sim.state["gold"]),
			str(_main.sim.state["run"]["active"])])
		return true
	return false
