extends Control
## 黒猫飯店 — 新メイン（HD-2D シェル）。
## 旧メイン（経営シム/タイマー一式）は legacy/main_legacy.gd に退避。
## 本シェルは HD-2D の「ホーム（店ジオラマ＋フィールド帯）」と「潜航（戦闘）」を
## 画面遷移で繋ぐ最小構成。各オーバーレイのシグナルを受けて遷移する。
## 実ゲームロジック（KuroSim 等）への接続は set_data／各シグナルで段階的に行う。

const HOME := "res://home_screen.tscn"
const DIVE := "res://dive_screen.tscn"

var _current: Node = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_goto(HOME)


func _goto(path: String) -> void:
	if _current != null:
		_current.queue_free()
		_current = null
	_current = load(path).instantiate()
	add_child(_current)
	var overlay := _current.get_node_or_null("Overlay")
	if overlay != null:
		if overlay.has_signal("action_pressed"):
			overlay.action_pressed.connect(_on_home_action)
		if overlay.has_signal("command_pressed"):
			overlay.command_pressed.connect(_on_dive_command)


## ホームのUI操作（探索入口で潜航へ。他は当面ログのみ）。
func _on_home_action(id: String) -> void:
	match id:
		"depart", "field":
			_goto(DIVE)
		_:
			print("[home] action: ", id)


## 潜航のコマンド（一時停止で店へ戻る。他は当面ログのみ）。
func _on_dive_command(id: String) -> void:
	match id:
		"pause":
			_goto(HOME)
		_:
			print("[dive] command: ", id)
