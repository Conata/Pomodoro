extends SceneTree
## 潜航（戦闘）画面（3Dステージ＋2D UI）のスクリーンショット。

const OUT := "res://_out/"
var _frame := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	get_root().add_child(load("res://dive_screen.tscn").instantiate())


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame >= 50:
		get_root().get_texture().get_image().save_png(OUT + "dive_screen.png")
		print("saved: dive_screen")
		return true
	return false
