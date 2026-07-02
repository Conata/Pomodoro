extends Control
## 黒猫飯店 — 新メイン（HD-2D シェル）＋ KuroSim ロジック接続。
## 旧メイン（経営シム/タイマー一式）は legacy/main_legacy.gd に退避。
## 本シェルは HD-2D の「ホーム」「潜航（戦闘）」を画面遷移で繋ぎ、
## 潜航は KuroSim を実際に駆動して結果をオーバーレイへ反映する（表示層＝HD-2D）。

const HOME := "res://home_screen.tscn"
const DIVE := "res://dive_screen.tscn"
const MENU := "res://menu_screen.tscn"
const RESULT := "res://result_screen.tscn"

var sim: KuroSim = null
var _current: Node = null
var _dive_overlay: Node = null   # 潜航中のみ。毎フレーム set_data で更新
var _dive_stage: Node = null     # 潜航中のみ。敵の出し入れを同期
var _menu_overlay: Node = null   # メニュー（メンバー/市場/経営/工房）表示中のみ
var _in_dive := false
var _speed := 1                  # 潜航の早送り倍率（fast コマンドで 1→2→3 巡回）
var _home_data: Dictionary = {}  # ホーム表示データ（日数/金/セリフ）
var _last_summary: Dictionary = {}  # 直近の run_complete サマリ（精算リザルト表示用）
var _save_accum := 0.0           # 潜航中オートセーブの蓄積秒
const AUTOSAVE_SEC := 20.0       # 潜航中はこの間隔で自動保存（旧メイン同方式）
var _title_accum := 0.0          # タブタイトル残時間の更新間隔（1秒毎）
const TITLE_DEFAULT := "黒猫飯店"

var _talk_view: TalkView = null  # 会話（VN）オーバーレイ（常駐・必要時に最前面で再生）
var _pending_talk: Dictionary = {}  # 再生中の会話 {girl, tier}（完了時に complete_talk）


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 会話オーバーレイを常駐。CanvasLayer(高layer)に載せ、画面遷移に関係なく最前面で再生。
	var talk_layer := CanvasLayer.new()
	talk_layer.layer = 10
	add_child(talk_layer)
	_talk_view = TalkView.new()
	_talk_view.visible = false
	_talk_view.finished.connect(_on_talk_finished)
	talk_layer.add_child(_talk_view)
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


## Web通知（旧メイン同方式）。ブラウザ権限がある時だけ出す。ネイティブでは無音。
func _notify(text: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"if(window.Notification&&Notification.permission==='granted'){new Notification(%s);}" % JSON.stringify(text),
			true)


## 通知許可のリクエスト（未決定の時だけ・ダイブ開始のユーザー操作に乗せる）。
func _request_notify_permission() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"if(window.Notification&&Notification.permission==='default'){Notification.requestPermission();}",
			true)


func _mmss(sec: float) -> String:
	var s := maxi(int(ceil(sec)), 0)
	return "%d:%02d" % [int(s / 60.0), s % 60]


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
	# 探索イベント（撃破・箱・記憶・扉・再同期…）を潜航オーバーレイのフィードへ。
	# run_complete サマリ（撃破数/到達階など）は精算リザルト用に確保する。
	var evs := sim.drain_events()
	if _dive_overlay != null and _dive_overlay.has_method("add_events"):
		_dive_overlay.add_events(evs)
	for e in evs:
		if String(e.get("kind", "")) == "run_complete":
			_last_summary = e.get("summary", {})
	if not bool(sim.state["run"]["active"]):
		_surface()                # 浮上＝精算→リザルト→翌朝→店へ
		return
	# 潜航中オートセーブ（中断・クラッシュでも進行を失わない）
	_save_accum += delta
	if _save_accum >= AUTOSAVE_SEC:
		_save_accum = 0.0
		_save()
	# タブタイトルに残時間（別タブで作業中でも進捗が見える＝ポモドーロの芯）
	_title_accum += delta
	if _title_accum >= 1.0:
		_title_accum = 0.0
		var run: Dictionary = sim.state["run"]
		var remain := maxf(float(run["duration"]) - float(run["elapsed"]), 0.0)
		var label := String(run["task"]) if run["mode"] == "pomo" else "クイック"
		DisplayServer.window_set_title("%s ▼ %s" % [_mmss(remain), label])


## ホーム表示データを KuroSim から更新（日数・所持金・ストリーク・セリフ）。
func _refresh_home_data(vn_line: String) -> void:
	var dg := "Day %d   金 %d" % [int(sim.state["day"]), int(sim.state["gold"])]
	if int(sim.state["streak"]) > 0:
		dg += "   連%d" % int(sim.state["streak"])
	_home_data = {"day_gold": dg, "line": vn_line}


## 浮上：その日の営業を精算し、箱を開け、結果をリザルト画面で提示する。
## 「店に戻る」で翌朝のホームへ（翌朝への進行は continue 時に行う）。
func _surface() -> void:
	# 店番が客人/未設定でも keeper_apt を持つ既定に補正（クラッシュ防止）
	var keeper: String = sim.state["morning"]["keeper"]
	if not (KuroData.GIRLS.get(keeper, {}) as Dictionary).has("keeper_apt"):
		sim.state["morning"]["keeper"] = "kiriko"
	var night: Dictionary = sim.close_day()
	# 箱を開封し、1個ずつ結果を集める（リザルトでリビール）
	var box_results: Array = []
	while not (sim.state["boxes"] as Array).is_empty():
		var r: Dictionary = sim.open_box()
		if r.is_empty():
			break
		box_results.append(r)
	# ポモドーロ完走を日課に記録（デイリー/ストリーク/週間）＋完走通知。
	# 切断（クイック全滅など）はカウントしない＝旧メインと同じ規律。
	if String(_last_summary.get("mode", "")) == "pomo" and not bool(_last_summary.get("disconnected", false)):
		sim.register_completion(Time.get_date_string_from_system(), float(_last_summary.get("minutes", 0.0)))
		_notify("浮上。%d分の集中、おつかれさま" % int(round(float(_last_summary.get("minutes", 0.0)))))
	# その夜話せる相手（aff閾値の未読シーン・1夜1人）。next_morning 前に確保。
	var talk: Dictionary = sim.available_talk()
	var result_data := {
		"day": int(sim.state["day"]),   # いま閉じた夜の日付（next_morning 前に確保）
		"lines": night.get("lines", []),
		"gold": int(night.get("gold", 0)),
		"boxes": box_results,
		"story": String(night.get("story", "")),
		"summary": _last_summary,
		"talk": talk,
		"daily": (sim.state["daily"] as Dictionary).duplicate(),
		"streak": int(sim.state["streak"]),
	}
	_last_summary = {}
	# 翌朝へ進めてから保存（リザルト中にアプリが落ちても状態は常に整合）
	sim.next_morning()
	_refresh_home_data("「お疲れさま。今夜は %dG の売上だったよ」" % int(night.get("gold", 0)))
	_save()             # 精算・開封・翌朝の確定を保存
	_show_result(result_data)


## 精算リザルト画面を開いて結果を流し込む。
func _show_result(data: Dictionary) -> void:
	_goto(RESULT)
	if _current != null:
		var overlay := _current.get_node_or_null("Overlay")
		if overlay != null and overlay.has_method("set_data"):
			overlay.set_data(data)


## リザルトの会話ボタンから、その夜の相手と会話（VN）を最前面で再生する。
func _start_result_talk() -> void:
	if _current == null or _talk_view == null:
		return
	var overlay := _current.get_node_or_null("Overlay")
	if overlay == null or not ("talk" in overlay):
		return
	var t: Dictionary = overlay.talk
	if t.is_empty():
		return
	_pending_talk = t
	_talk_view.position = Vector2.ZERO
	_talk_view.size = size           # CanvasLayer内なので画面サイズを明示
	_talk_view.start(String(t["girl"]), int(t["tier"]))


## 会話終了：好感度・既読を確定し、リザルトの会話ボタンを消す。
func _on_talk_finished(meta: Dictionary) -> void:
	var gid := String(meta.get("girl", ""))
	if gid != "" and sim != null:
		sim.complete_talk(gid, int(meta.get("tier", 0)))
		sim.drain_events()
		_save()
	_pending_talk = {}
	if _talk_view != null:
		_talk_view.visible = false
	if _current != null:
		var overlay := _current.get_node_or_null("Overlay")
		if overlay != null and overlay.has_method("clear_talk"):
			overlay.clear_talk()


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
	if not _in_dive:
		DisplayServer.window_set_title(TITLE_DEFAULT)   # 潜航以外はタイトルを戻す
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
			_request_notify_permission()   # 完走通知の許可（ユーザー操作起点なのでここ）
			sim.drain_events()    # ホーム/メニューの残存イベントを捨ててから開始
			sim.start_run("pomo", 25.0, Time.get_unix_time_from_system(), "集中仕入れ")
			_save_accum = 0.0
			_save()       # 開始時点を保存（中断しても再開できる）
			_goto(DIVE)
		"depart", "field":
			# クイック仕入れ（80秒）
			sim.drain_events()
			sim.start_run("quick", 1.0, Time.get_unix_time_from_system(), "仕入れ")
			_save_accum = 0.0
			_save()
			_goto(DIVE)
		"talk":
			# 精算リザルトの会話ボタン → その夜の相手と会話（VN）を再生
			_start_result_talk()
		"claim":
			# デイリー報酬（3完走で+500G・1日1回）
			if sim.claim_daily():
				sim.drain_events()
				_save()
				if _current != null:
					var ov := _current.get_node_or_null("Overlay")
					if ov != null and ov.has_method("claim_done"):
						ov.claim_done()
		"continue":
			# 精算リザルトから翌朝のホームへ（next_morning は浮上時に済み）
			_refresh_home_data("「おはよう。今日はどこで仕入れる？」")
			_goto(HOME)
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
	var need := {
		"buy": 2, "ship": 2, "keeper": 2, "menu": 2, "renov": 2,
		"skill": 3, "tree": 3, "bag_store": 2, "salvage_bag": 2,
		"reroll_storage": 2, "salvage_storage": 2, "equip_storage": 3,
		"socket_storage": 3, "remove_gem": 3,
	}
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
		"bag_all":
			var moved := sim.bag_all_to_storage()
			toast = "バッグから倉庫へ %d件移動" % moved
		"bag_store":
			toast = "倉庫へ移動" if sim.bag_to_storage(int(parts[1])) else "倉庫がいっぱい（廃材化）"
		"synth_bag":
			var made_bag := sim.synthesize_all()
			toast = "バッグ合成 %d件" % made_bag if made_bag > 0 else "合成できる装備がない"
		"bulk_salvage_bag":
			var rb: Dictionary = sim.bulk_salvage()
			toast = "バッグ不要品 %d件 → 廃材%d" % [int(rb.get("count", 0)), int(rb.get("dust", 0))]
		"salvage_bag":
			var dust_bag := sim.salvage_item(int(parts[1]))
			toast = "分解 → 廃材%d" % dust_bag if dust_bag > 0 else "分解できない"
		"synth_storage":
			var made_storage := sim.synthesize_storage()
			toast = "倉庫合成 %d件" % made_storage if made_storage > 0 else "合成できる装備がない"
		"bulk_salvage_storage":
			var rs: Dictionary = sim.bulk_salvage_storage()
			toast = "倉庫不要品 %d件 → 廃材%d" % [int(rs.get("count", 0)), int(rs.get("dust", 0))]
		"reroll_storage":
			toast = "刻印を更新" if sim.reroll_storage(int(parts[1])) else "廃材不足／対象なし"
		"salvage_storage":
			var dust_storage := sim.salvage_from_storage(int(parts[1]))
			toast = "分解 → 廃材%d" % dust_storage if dust_storage > 0 else "分解できない"
		"equip_storage":
			var gid := parts[2]
			toast = "%s に装備" % KuroData.GIRLS[gid]["name"] if sim.equip_from_storage(int(parts[1]), gid) else "装備できない"
		"socket_storage":
			toast = "装飾を嵌めた" if sim.socket_gem(int(parts[1]), parts[2]) else "装飾できない"
		"remove_gem":
			toast = "装飾を外した" if sim.remove_gem(int(parts[1]), int(parts[2])) else "外せない"
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
