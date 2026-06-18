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
var _dive_stage: Node = null     # 潜航中のみ。敵の出し入れを同期
var _in_dive := false
var _speed := 1                  # 潜航の早送り倍率（fast コマンドで 1→2→3 巡回）
var _home_data: Dictionary = {}  # ホーム表示データ（日数/金/セリフ）


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	sim = KuroSim.new()           # フレッシュなゲーム状態（gold 120 / day 1）
	_refresh_home_data("「いらっしゃい。今日はどこで仕入れる？」")
	_goto(HOME)


func _process(delta: float) -> void:
	if not _in_dive or sim == null:
		return
	# 早送り：アンカーを余分に巻き戻して「より多くの時間が経った」ことにする
	if _speed > 1 and bool(sim.state["run"]["active"]):
		sim.state["run"]["anchor"] = float(sim.state["run"]["anchor"]) - float(_speed - 1) * delta
	# KuroSim を実時間アンカーで駆動（タブ非アクティブでも正確：旧メインと同方式）
	_catch_up(Time.get_unix_time_from_system())
	_update_dive_ui()
	if not bool(sim.state["run"]["active"]):
		_surface()                # 浮上＝精算→翌朝→店へ


## ホーム表示データを KuroSim から更新（日数・所持金・セリフ）。
func _refresh_home_data(vn_line: String) -> void:
	_home_data = {
		"day_gold": "Day %d   金 %d" % [int(sim.state["day"]), int(sim.state["gold"])],
		"line": vn_line,
	}


## 浮上：その日の営業を精算し、箱を開け、翌朝へ進めて店に戻る（1日ループ）。
func _surface() -> void:
	# 店番が客人/未設定でも keeper_apt を持つ既定に補正（クラッシュ防止）
	var keeper: String = sim.state["morning"]["keeper"]
	if not (KuroData.GIRLS.get(keeper, {}) as Dictionary).has("keeper_apt"):
		sim.state["morning"]["keeper"] = "kiriko"
	var summary: Dictionary = sim.close_day()
	while not (sim.state["boxes"] as Array).is_empty():
		if sim.open_box().is_empty():
			break
	sim.next_morning()
	_refresh_home_data("「お疲れさま。今夜は %dG の売上だったよ」" % int(summary.get("gold", 0)))
	_goto(HOME)


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
	_dive_stage = null
	_speed = 1
	_in_dive = (path == DIVE)
	_current = load(path).instantiate()
	add_child(_current)
	if _in_dive:
		_dive_stage = _current.get_node_or_null("Stage")
	var overlay := _current.get_node_or_null("Overlay")
	if overlay != null:
		if overlay.has_signal("action_pressed"):
			overlay.action_pressed.connect(_on_home_action)
			if overlay.has_method("set_data") and not _home_data.is_empty():
				overlay.set_data(_home_data)   # ホーム：実データ反映（日数/金/セリフ）
		if overlay.has_signal("command_pressed"):
			overlay.command_pressed.connect(_on_dive_command)
			_dive_overlay = overlay


## ホームのUI操作（仕入れへ で仕入れ開始／フッターで各主要機能へ）。
func _on_home_action(id: String) -> void:
	match id:
		"pomodoro":
			# 25分ポモドーロ集中＝仕入れ（早送り/早期終了は仕入れ画面のボタンで）
			sim.start_run("pomo", 25.0, Time.get_unix_time_from_system(), "集中仕入れ")
			_goto(DIVE)
		"depart", "field":
			# クイック仕入れ（80秒）
			sim.start_run("quick", 1.0, Time.get_unix_time_from_system(), "仕入れ")
			_goto(DIVE)
		"home":
			# フッター「ホーム」＝現在地。セリフだけ戻す。
			_say_home("「おかえり。今日も飯店、開けるよ。」")
		"member":
			# 主要機能：メンバー（編成/会話/好感度）。新シェルへは移植中。
			_say_home("「メンバーの編成画面は移植中。もう少しで会えるよ。」")
		"market":
			# 主要機能：闇市（仕入れた素材の売買）。新シェルへは移植中。
			_say_home("「闇市はまだ仕込み中。掘り出し物、楽しみにしてて。」")
		"management":
			# 主要機能：経営（夜の精算/店づくり）。新シェルへは移植中。
			_say_home("「経営の帳簿はまだ閉じたまま。夜の精算はこれからだよ。」")
		"workshop":
			# 主要機能：工房（改装/設備）。新シェルへは移植中。
			_say_home("「工房は建てかけ。改装はもうちょっと待ってね。」")
		_:
			print("[home] action: ", id)


## ホームのVNセリフを差し替えて、現在のホームオーバーレイへ即時反映する。
func _say_home(vn_line: String) -> void:
	_refresh_home_data(vn_line)
	if _current != null:
		var overlay := _current.get_node_or_null("Overlay")
		if overlay != null and overlay.has_method("set_data"):
			overlay.set_data(_home_data)


## 潜航のコマンド。KuroSim はオート戦闘なので、fast=早送り倍率、pause=撤退を実効化。
## 攻撃/スキル/防御/アイテムの手動発動は KuroSim 側 API（手動アクション）が要るため当面ログ。
func _on_dive_command(id: String) -> void:
	match id:
		"home", "pause":
			# 中断して店へ戻る（撤退）
			if sim != null and bool(sim.state["run"]["active"]):
				sim.abandon_run()
			_goto(HOME)
		"finish":
			# 早期終了＝今すぐ浮上（残り時間を飛ばして正常終了→精算）
			var run: Dictionary = sim.state["run"]
			if bool(run["active"]):
				run["elapsed"] = float(run["duration"])
				sim.step(KuroData.SIM_DT)   # 終端処理を発火（次フレームの _process が _surface）
		"fast":
			_speed = (_speed % 3) + 1        # 1→2→3→1
		_:
			print("[dive] command(未接続: 要KuroSim手動アクションAPI): ", id)


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
	# 3D ステージの敵を sim の mob 数＆戦闘フラグに同期
	if _dive_stage != null and _dive_stage.has_method("set_dive_state"):
		_dive_stage.set_dive_state((sim.state["mobs"] as Array).size(), bool(sim.state["in_combat"]))
	var run: Dictionary = sim.state["run"]
	var remain := maxf(float(run["duration"]) - float(run["elapsed"]), 0.0)
	var prog := fmod(float(sim.state["dist"]), KuroData.FLOOR_LEN) / KuroData.FLOOR_LEN
	_dive_overlay.set_data({
		"party": party,
		"player_lv": "B%d" % sim.current_floor(),
		"player_hp": (tot / mx) if mx > 0.0 else 0.0,
		"player_exp": prog,
		"quest_text": "仕入れ中  B%d  残り %d秒" % [sim.current_floor(), int(remain)],
		"speed_mult": _speed,
	})
