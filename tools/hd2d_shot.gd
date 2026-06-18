extends SceneTree
## HD-2D プロトタイプのスクリーンショット撮影用ランナー（オフスクリーン）。
## 使い方:
##   xvfb-run -a -s "-screen 0 800x1400x24" \
##     ./Godot_v4.6-stable_linux.x86_64 --rendering-driver opengl3 \
##     --path . -s tools/hd2d_shot.gd
## res://_out/hd2d_shot_*.png に複数アングルを保存して終了する。

const OUT := "res://_out/"
const SETTLE := 50           # アングル切替後に待つフレーム数（カメラ補間＋アニメ）
var _view: Node = null
var _frame := 0
var _shot := 0
# {yaw(rad), dist, height, player(Vector3), moving(bool), label}
var _angles := [
	{"yaw": 0.0, "dist": 15.0, "height": 13.0, "pos": Vector3(0, 0, 3.0), "moving": false, "label": "overview"},
	{"yaw": 0.0, "dist": 9.0, "height": 8.0, "pos": Vector3(0, 0, 4.0), "moving": false, "label": "front"},
	{"yaw": 0.0, "dist": 12.0, "height": 9.0, "pos": Vector3(0, 0, 2.0), "moving": true, "label": "wide"},
	{"yaw": PI * 0.5, "dist": 11.0, "height": 9.0, "pos": Vector3(-2, 0, 0.0), "moving": true, "label": "rot90"},
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var ps: PackedScene = load("res://hd2d_test.tscn")
	_view = ps.instantiate()
	get_root().add_child(_view)
	_apply_angle(0)


func _apply_angle(i: int) -> void:
	var a: Dictionary = _angles[i]
	# Hd2dView の内部状態を直接ドライブ（入力を介さずアングルを決め打ち）
	_view._cam_yaw_target = float(a["yaw"])
	_view._cam_yaw = float(a["yaw"])
	_view._cam_dist_target = float(a["dist"])
	_view._cam_dist = float(a["dist"])
	_view._cam_height = float(a["height"])
	_view._player_pos = a["pos"]
	# 歩行ポーズを見せたいときは run、止めたいときは idle に固定
	_view._force_moving = bool(a["moving"])


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame >= SETTLE:
		var img := get_root().get_texture().get_image()
		var name := "%shd2d_shot_%d_%s.png" % [OUT, _shot, _angles[_shot]["label"]]
		img.save_png(name)
		print("saved: ", name)
		_shot += 1
		_frame = 0
		if _shot >= _angles.size():
			return true
		_apply_angle(_shot)
	return false
