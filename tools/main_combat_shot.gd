extends SceneTree
## 潜航ステージ同期の検証：戦闘になるまで早送りし、敵が表示された瞬間を撮る。

const OUT := "res://_out/"
var _main: Node = null
var _frame := 0
var _phase := 0
var _wait := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_main = load("res://main.tscn").instantiate()
	get_root().add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		0:
			if _frame >= 12:
				_main._on_home_action("depart")
				_phase = 1
		1:
			if bool(_main.sim.state["in_combat"]):
				_phase = 2
				_wait = 0
			else:
				# 遭遇まで早送り（1フレームあたり ~1.2 シム秒）
				_main.sim.state["run"]["anchor"] = float(_main.sim.state["run"]["anchor"]) - 1.2
				if float(_main.sim.state["dist"]) > 410.0:
					_phase = 2  # 安全策（行き過ぎ）
					_wait = 0
		2:
			_wait += 1
			if _wait >= 5:
				get_root().get_texture().get_image().save_png(OUT + "main_combat.png")
				print("saved: main_combat  in_combat=%s mobs=%d dist=%.0f" % [
					str(_main.sim.state["in_combat"]),
					(_main.sim.state["mobs"] as Array).size(),
					float(_main.sim.state["dist"])])
				return true
	return false
