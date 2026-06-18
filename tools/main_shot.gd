extends SceneTree
## 新メイン（HD-2D シェル）起動画面のスクリーンショット。

const OUT := "res://_out/"
var _frame := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	get_root().add_child(load("res://main.tscn").instantiate())


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame >= 60:
		get_root().get_texture().get_image().save_png(OUT + "main_home.png")
		print("saved: main_home")
		return true
	return false
