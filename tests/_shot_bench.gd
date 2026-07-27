extends SceneTree
## 一時：AAA品質ループ用のベースライン撮影。ホーム／経営シート／潜航／夜営業を1枚ずつ。
## 夜営業の script は描画確認用に固定データを流し込む（絵の審査が目的でシムの検証ではない）。

const OUT := "res://_out/bench/"

var main: Control
var _f := 0
var _backup := PackedByteArray()
var _had := false


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
	match _f:
		90:
			_shot("01_home")
		95:
			main._open_menu("management")
		125:
			_shot("02_management")
		130:
			main._menu_overlay.visible = false
			main._night_overlay.set_data({
				"day": 6, "keeper": "mil", "streak": 4, "regulars": 3, "customers": 11,
				"script": [
					{"dish": "麻婆豆腐", "gold": 42}, {"dish": "焼売", "gold": 28},
					{"dish": "炒飯", "gold": 35}, {"dish": "海鮮粥", "gold": 51},
					{"dish": "杏仁豆腐", "gold": 24}, {"dish": "麻婆豆腐", "gold": 42},
					{"dish": "焼売", "gold": 28}, {"dish": "青菜炒め", "gold": 19},
				]})
			main._night_overlay.visible = true
		170:
			_shot("03_night")
		175:
			main._night_overlay.skip()
			main._night_overlay.visible = false
			main._result_overlay.visible = false
			main._on_home_action("pomodoro")
		225:
			_shot("04_dive")
		230:
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
