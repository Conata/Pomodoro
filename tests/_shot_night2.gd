extends SceneTree
## 一時：夜営業シアターだけを複数コマ撮る（店番アニメ4コマ・客の各状態を拾うため）。

const OUT := "res://_out/bench/"

var main: Control
var _f := 0
var _backup := PackedByteArray()
var _had := false
var _shots := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if FileAccess.file_exists(SaveGame.PATH):
		_had = true
		_backup = FileAccess.get_file_as_bytes(SaveGame.PATH)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.PATH))
	main = load("res://main.tscn").instantiate()
	get_root().add_child(main)


func _shot(name: String) -> void:
	get_root().get_texture().get_image().save_png(OUT + name + ".png")
	print("shot: ", name)


func _process(_d: float) -> bool:
	_f += 1
	if _f == 20:
		main._open_menu("management")
	elif _f == 30:
		main._menu_overlay.visible = false
		main._night_overlay.set_data({
			"day": 6, "keeper": "mil", "streak": 4, "regulars": 3, "customers": 11,
			"script": [
				{"dish": "麻婆豆腐", "gold": 42, "match": true}, {"dish": "焼売", "gold": 28},
				{"dish": "炒飯", "gold": 35}, {"dish": "海鮮粥", "gold": 51, "match": true},
				{"dish": "杏仁豆腐", "gold": 24}, {"dish": "麻婆豆腐", "gold": 42},
				{"dish": "焼売", "gold": 28}, {"dish": "青菜炒め", "gold": 19},
			]})
		main._night_overlay.visible = true
	elif _f > 30 and (_f - 30) % 11 == 0 and _shots < 10:
		_shots += 1
		_shot("n2_%02d" % _shots)
	elif _shots >= 10:
		get_root().remove_child(main)
		main.free()
		if _had:
			var f := FileAccess.open(SaveGame.PATH, FileAccess.WRITE)
			f.store_buffer(_backup); f.close()
		elif FileAccess.file_exists(SaveGame.PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.PATH))
		quit(0)
		return true
	return false
