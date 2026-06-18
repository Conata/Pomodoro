extends SceneTree
## ホームジオラマ（黒猫飯店）のスクリーンショット撮影ランナー（オフスクリーン）。
##   xvfb-run -a -s "-screen 0 800x1400x24" ./Godot... \
##     --rendering-method gl_compatibility --rendering-driver opengl3 \
##     --path . -s tools/home_shot.gd

const OUT := "res://_out/"
const SETTLE := 45
var _view: Node = null
var _frame := 0
var _shot := 0
# 店先を少しずつ角度違いで（ヨー）撮る
var _yaws := [0.0, -0.35, 0.35]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_view = load("res://home3d_test.tscn").instantiate()
	get_root().add_child(_view)
	_apply(0)


func _apply(i: int) -> void:
	_view._cam_yaw_target = _yaws[i]
	_view._cam_yaw = _yaws[i]


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame >= SETTLE:
		var img := get_root().get_texture().get_image()
		img.save_png("%shome_shot_%d.png" % [OUT, _shot])
		print("saved: home_shot_%d" % _shot)
		_shot += 1
		_frame = 0
		if _shot >= _yaws.size():
			return true
		_apply(_shot)
	return false
