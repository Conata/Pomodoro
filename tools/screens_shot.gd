extends SceneTree
## 全画面スクリーンショット束（CI証拠用）。実フロー（main.tscn）を駆動して
## ホーム/メニュー各パネル/潜航/精算リザルト/会話 を _out/screens/ に撮る。
##   xvfb-run -a -s "-screen 0 760x1320x24" godot --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --path . -s tools/screens_shot.gd
## ローカル実行でも安全：既存セーブは開始時に退避し、終了時に復元する。

const OUT := "res://_out/screens/"
const SETTLE_DEFAULT := 20

var main: Control
var _plan: Array = []      # [名前, 準備Callable, settleフレーム数]
var _step := -1
var _frame := 0
var _backup := PackedByteArray()
var _had_save := false


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_backup_save()
	main = load("res://main.tscn").instantiate()
	get_root().add_child(main)
	_plan = [
		["home", Callable(), 50],
		["menu_member", func(): main._on_home_action("member"), 20],
		["menu_market", func(): main._on_home_action("market"), 15],
		["menu_management", func(): main._on_home_action("management"), 15],
		["menu_renov", func(): main._menu_overlay.set_panel("renov"), 15],
		["menu_workshop", func(): main._on_home_action("workshop"), 15],
		["dive", func(): _start_dive(), 45],
		["result", func(): _finish_dive(), 30],
		["talk", func(): main._on_home_action("talk"), 30],
	]
	_advance()


func _start_dive() -> void:
	main.sim.state["girls"]["mil"]["aff"] = 20   # 精算リザルトに会話ボタンを出す
	main._on_home_action("pomodoro")
	# 30秒ぶん進めて戦闘/フィードが映る状態に
	main.sim.state["run"]["anchor"] = float(main.sim.state["run"]["anchor"]) - 30.0


func _finish_dive() -> void:
	# 残り時間を全て消化 → 次フレームの _process が浮上→リザルトへ
	main.sim.state["run"]["anchor"] = float(main.sim.state["run"]["anchor"]) - 1600.0


func _advance() -> void:
	_step += 1
	_frame = 0
	if _step < _plan.size():
		var prep: Callable = _plan[_step][1]
		if prep.is_valid():
			prep.call()


func _process(_delta: float) -> bool:
	if _step >= _plan.size():
		return true
	_frame += 1
	if _frame < int(_plan[_step][2]):
		return false
	var name := String(_plan[_step][0])
	var img := get_root().get_texture().get_image()
	img.save_png("%s%02d_%s.png" % [OUT, _step, name])
	print("saved: %02d_%s" % [_step, name])
	_advance()
	if _step >= _plan.size():
		# セーブ復元は main を畳んでから（終了時の自動保存に上書きされない順序）
		get_root().remove_child(main)
		main.free()
		_restore_save()
		print("done: %d screens" % _plan.size())
		return true
	return false


func _backup_save() -> void:
	if FileAccess.file_exists(SaveGame.PATH):
		_had_save = true
		_backup = FileAccess.get_file_as_bytes(SaveGame.PATH)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.PATH))


func _restore_save() -> void:
	if _had_save:
		var f := FileAccess.open(SaveGame.PATH, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_backup)
			f.close()
	elif FileAccess.file_exists(SaveGame.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.PATH))
