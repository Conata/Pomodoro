extends SceneTree
## 潜航ステージ同期の検証：手動 step で遭遇まで進め、in_combat が立った瞬間で止めて撮る。
## main 側の catch_up が余分に進めないよう anchor=now で中和する。

const OUT := "res://_out/"
var _main: Node = null
var _frame := 0
var _phase := 0
var _wait := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_main = load("res://main.tscn").instantiate()
	get_root().add_child(_main)


func _neutralize() -> void:
	# main._process の catch_up を 0 ステップにする（自前 step だけで進めるため）
	_main.sim.state["run"]["anchor"] = Time.get_unix_time_from_system()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		0:
			if _frame >= 10:
				_main._on_home_action("depart")
				_phase = 1
		1:
			_neutralize()
			# 遭遇まで手動で進める。in_combat が立った瞬間に止める
			for _i in 240:
				_main.sim.step(0.2)
				if bool(_main.sim.state["in_combat"]) or not bool(_main.sim.state["run"]["active"]):
					break
			if bool(_main.sim.state["in_combat"]) or not bool(_main.sim.state["run"]["active"]):
				_phase = 2
				_wait = 0
		2:
			_neutralize()  # combat を凍結（敵を表示したまま）
			_wait += 1
			if _wait >= 5:
				get_root().get_texture().get_image().save_png(OUT + "main_combat.png")
				print("saved: main_combat  in_combat=%s mobs=%d dist=%.0f" % [
					str(_main.sim.state["in_combat"]),
					(_main.sim.state["mobs"] as Array).size(),
					float(_main.sim.state["dist"])])
				return true
	return false
