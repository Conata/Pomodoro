extends Control
## 黒猫飯店 — 新メイン（HD-2D シェル）＋ KuroSim ロジック接続。
## 旧メイン（経営シム/タイマー一式）は legacy/main_legacy.gd に退避。
## 本シェルは HD-2D の「ホーム」「潜航（戦闘）」を画面遷移で繋ぎ、
## 潜航は KuroSim を実際に駆動して結果をオーバーレイへ反映する（表示層＝HD-2D）。

const HOME := "res://home_screen.tscn"
const DIVE := "res://dive_screen.tscn"
const MENU := "res://menu_screen.tscn"

var sim: KuroSim = null
var _current: Node = null
var _dive_overlay: Node = null   # 潜航中のみ。毎フレーム set_data で更新
var _dive_stage: Node = null     # 潜航中のみ。敵の出し入れを同期
var _menu_overlay: Node = null   # メニュー（メンバー/市場/経営/工房）表示中のみ
var _in_dive := false
var _speed := 1                  # 潜航の早送り倍率（fast コマンドで 1→2→3 巡回）
var _home_data: Dictionary = {}  # ホーム表示データ（日数/金/セリフ）
var _save_accum := 0.0           # 潜航中オートセーブの蓄積秒
const AUTOSAVE_SEC := 20.0       # 潜航中はこの間隔で自動保存（旧メイン同方式）


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var loaded := SaveGame.load_state()
	if loaded.is_empty():
		sim = KuroSim.new()           # 新規（gold 120 / day 1）
	else:
		sim = KuroSim.new(loaded)     # セーブから再開
	sim.apply_offline(Time.get_unix_time_from_system())  # 安息収入＋last_seen 更新
	if bool(sim.state["run"]["active"]):
		# 中断したダイブを再開（_process が anchor で時間をキャッチアップする）
		_goto(DIVE)
	else:
		_refresh_home_data("「いらっしゃい。今日はどこで仕入れる？」")
		_goto(HOME)
	_save()                           # last_seen / 安息分を確定保存


## 現在の状態を保存（rng を state に同期してから書き出す）。
func _save() -> void:
	if sim == null:
		return
	sim.sync_rng()
	SaveGame.save_state(sim.state)


## アプリ終了・バックグラウンド化で取りこぼさず保存する。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_save()


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
		return
	# 潜航中オートセーブ（中断・クラッシュでも進行を失わない）
	_save_accum += delta
	if _save_accum >= AUTOSAVE_SEC:
		_save_accum = 0.0
		_save()


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
	_save()             # 精算・翌朝への確定を保存


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
	_menu_overlay = null
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
			if overlay.has_method("bind"):
				overlay.bind(sim)              # メニュー：KuroSim を参照させて実データ描画
				_menu_overlay = overlay
			if overlay.has_method("set_data") and not _home_data.is_empty():
				overlay.set_data(_home_data)   # ホーム：実データ反映（日数/金/セリフ）
		if overlay.has_signal("command_pressed"):
			overlay.command_pressed.connect(_on_dive_command)
			_dive_overlay = overlay


## ホーム／メニューのUI操作。
## フッターナビ（home/member/market/management/workshop）＝画面遷移、
## それ以外の "動詞:パラメータ" はメニュー各パネルの操作（KuroSim を実際に駆動）。
func _on_home_action(id: String) -> void:
	match id:
		"pomodoro":
			# 25分ポモドーロ集中＝仕入れ（早送り/早期終了は仕入れ画面のボタンで）
			sim.start_run("pomo", 25.0, Time.get_unix_time_from_system(), "集中仕入れ")
			_save_accum = 0.0
			_save()       # 開始時点を保存（中断しても再開できる）
			_goto(DIVE)
		"depart", "field":
			# クイック仕入れ（80秒）
			sim.start_run("quick", 1.0, Time.get_unix_time_from_system(), "仕入れ")
			_save_accum = 0.0
			_save()
			_goto(DIVE)
		"home":
			# フッター「ホーム」＝店（HD-2D ホーム）へ。既にホームならセリフだけ戻す。
			_say_home("「おかえり。今日も飯店、開けるよ。」")
		"member", "market", "management", "workshop":
			_open_menu(id)
		"menu", "cat":
			# ホーム上部の ≡／猫 はメニュー（メンバー）への近道。
			_open_menu("member")
		"settings", "bell":
			# 設定・通知は未実装（旧版から未移植）。
			print("[home] action(未実装): ", id)
		_:
			_on_menu_action(id)


## メニュー画面を開く（既に開いていればパネル切替のみ＝タブ感覚で軽量）。
func _open_menu(panel: String) -> void:
	if panel == "market" and sim != null:
		sim.maybe_rotate_ship(Time.get_unix_time_from_system())  # 入店時に交易船を更新
	if _menu_overlay != null and is_instance_valid(_menu_overlay):
		_menu_overlay.set_panel(panel)
	else:
		_goto(MENU)
		if _menu_overlay != null:
			_menu_overlay.set_panel(panel)


## メニュー各パネルの操作（"動詞:パラメータ"）。KuroSim を駆動して再描画する。
func _on_menu_action(id: String) -> void:
	if sim == null:
		return
	var parts := id.split(":")
	var verb := parts[0]
	# パラメータ付きの動詞は引数欠落なら無視（不正IDでの添字アクセス防止）。
	var need := {"buy": 2, "ship": 2, "keeper": 2, "menu": 2, "renov": 2, "skill": 3, "tree": 3, "talk": 3}
	if need.has(verb) and parts.size() < int(need[verb]):
		return
	var toast := ""
	match verb:
		"buy":
			var r: Dictionary = sim.market_buy(int(parts[1]))
			toast = String(r.get("text", "ゴールドが足りない")) if not r.is_empty() else "ゴールドが足りない"
		"ship":
			toast = "交易船から購入した" if sim.buy_ship(int(parts[1])) else "買えなかった"
		"keeper":
			sim.set_keeper(parts[1])
			toast = "店番を %s に" % KuroData.GIRLS[parts[1]]["name"]
		"menu":
			toast = "献立を更新" if sim.toggle_menu(parts[1]) else "枠がいっぱい／未所持"
		"door":
			var m: Dictionary = sim.state["morning"]
			m["door"] = "closed" if m["door"] == "open" else "open"
			toast = "扉の方針：%s" % ("開ける" if m["door"] == "open" else "見送る")
		"renov":
			toast = "改装「%s」を解放" % KuroData.RENOV_NODES[parts[1]]["name"] if sim.unlock_renov(parts[1]) else "ゴールドが足りない"
		"skill":
			toast = "スキルを更新" if sim.equip_skill(parts[1], parts[2]) else "スキル枠がいっぱい"
		"tree":
			toast = "育成ノードを解放" if sim.tree_unlock(parts[1], parts[2]) else "欠片が足りない／条件未達"
		"talk":
			sim.complete_talk(parts[1], int(parts[2]))
			toast = "%s との会話を解放（♥+6）" % KuroData.GIRLS[parts[1]]["name"]
		_:
			print("[menu] action: ", id)
			return
	sim.drain_events()  # ログイベントは破棄（トーストで代替）
	_save()             # 購入・編成・改装などの変更を保存
	if _menu_overlay != null and is_instance_valid(_menu_overlay):
		if toast != "" and _menu_overlay.has_method("set_toast"):
			_menu_overlay.set_toast(toast)
		_menu_overlay.queue_redraw()


## ホームのVNセリフを差し替えて、現在のホームオーバーレイへ即時反映する。
func _say_home(vn_line: String) -> void:
	if _menu_overlay != null or _in_dive:
		_goto(HOME)
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
			_refresh_home_data("「無理はしないで。仕切り直そう。」")
			_goto(HOME)
			_save()                          # 撤退（切断ペナルティ）を保存
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
