extends Control
## 黒猫飯店 — 新メイン（HD-2D シェル）＋ KuroSim ロジック接続。
## 旧メイン（経営シム/タイマー一式）は legacy/main_legacy.gd に退避。
## 本シェルは HD-2D の「ホーム」「潜航（戦闘）」を画面遷移で繋ぎ、
## 潜航は KuroSim を実際に駆動して結果をオーバーレイへ反映する（表示層＝HD-2D）。

const HOME := "res://home_screen.tscn"
const DIVE := "res://dive_screen.tscn"

var sim: KuroSim = null
var _current: Node = null
var _dive_overlay: Node = null   # 潜航中のみ。毎フレーム set_data で更新
var _in_dive := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	sim = KuroSim.new()           # フレッシュなゲーム状態（gold 120 / day 1）
	_goto(HOME)


func _process(_delta: float) -> void:
	if not _in_dive or sim == null:
		return
	# KuroSim を実時間アンカーで駆動（タブ非アクティブでも正確：旧メインと同方式）
	_catch_up(Time.get_unix_time_from_system())
	_update_dive_ui()
	if not bool(sim.state["run"]["active"]):
		_goto(HOME)               # 浮上＝店へ戻る


## 固定ステップのキャッチアップ（now － anchor 分だけ step を回す）。
func _catch_up(now: float) -> void:
	var run: Dictionary = sim.state["run"]
	if not bool(run["active"]):
		return
	var target := now - float(run["anchor"])
	var steps := mini(int((target - float(run["elapsed"])) / KuroData.SIM_DT), 200000)
	for _i in steps:
		sim.step(KuroData.SIM_DT)
		if not bool(run["active"]):
			break


func _goto(path: String) -> void:
	if _current != null:
		_current.queue_free()
		_current = null
	_dive_overlay = null
	_in_dive = (path == DIVE)
	_current = load(path).instantiate()
	add_child(_current)
	var overlay := _current.get_node_or_null("Overlay")
	if overlay != null:
		if overlay.has_signal("action_pressed"):
			overlay.action_pressed.connect(_on_home_action)
		if overlay.has_signal("command_pressed"):
			overlay.command_pressed.connect(_on_dive_command)
			_dive_overlay = overlay


## ホームのUI操作（探索入口で潜航開始）。
func _on_home_action(id: String) -> void:
	match id:
		"depart", "field":
			# クイックダイブ（80秒）を開始して潜航画面へ
			sim.start_run("quick", 1.0, Time.get_unix_time_from_system(), "探索")
			_goto(DIVE)
		_:
			print("[home] action: ", id)


## 潜航のコマンド（KuroSim はオート戦闘。一時停止で撤退して店へ）。
func _on_dive_command(id: String) -> void:
	match id:
		"pause":
			if sim != null and bool(sim.state["run"]["active"]):
				sim.abandon_run()
			_goto(HOME)
		_:
			print("[dive] command: ", id)


## 潜航オーバーレイへ KuroSim の実データを流し込む。
func _update_dive_ui() -> void:
	if _dive_overlay == null:
		return
	var ds: Array = sim.divers()
	var party: Array = []
	var tot := 0.0
	var mx := 0.0
	for gid in ds:
		var g: Dictionary = KuroData.GIRLS.get(gid, {})
		var hp := int(sim.state["hp"].get(gid, 0))
		var mhp := maxi(int(sim.girl_maxhp(gid)), 1)
		tot += hp
		mx += mhp
		party.append({"name": String(g.get("name", gid)), "hp": hp, "mhp": mhp, "sp": 100, "msp": 100})
	var run: Dictionary = sim.state["run"]
	var remain := maxf(float(run["duration"]) - float(run["elapsed"]), 0.0)
	var prog := fmod(float(sim.state["dist"]), KuroData.FLOOR_LEN) / KuroData.FLOOR_LEN
	_dive_overlay.set_data({
		"party": party,
		"player_lv": "B%d" % sim.current_floor(),
		"player_hp": (tot / mx) if mx > 0.0 else 0.0,
		"player_exp": prog,
		"quest_text": "深層 B%d  残り %d秒" % [sim.current_floor(), int(remain)],
	})
