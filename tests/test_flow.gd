extends SceneTree
## 遊びの流れを実際の main.tscn で通す検証。
##
## なぜ要るか：単体テスト（test_sim.gd）は sim だけを叩くので、
## **UI の描画中に起きる辞書アクセスや、画面遷移をまたぐ状態の食い違いを一切見ない。**
## 実際、店番にドクター／ナースを選ぶと精算で落ちるバグが 251 件の単体テストを
## 全部すり抜けていた（_flavor_line の台詞プールが4人ぶんしか無かった）。
##
## 実行（3D の描画コンテキストが要るので xvfb 経由）:
##   timeout 500 xvfb-run -a -s "-screen 0 760x1320x24" /tmp/Godot_v4.6-stable_linux.x86_64 \
##     --rendering-method gl_compatibility --rendering-driver opengl3 --audio-driver Dummy \
##     --path . -s tests/test_flow.gd
##
## 落ちた行は SCRIPT ERROR として出るので、NG が 0 でも標準エラーを必ず見ること。

var main: Control
var _f := 0
var _fail := 0
var _log: Array = []
var _errors_before := 0

const PANELS := ["management", "member", "market", "workshop", "renov", "map"]


func _ck(cond: bool, label: String) -> void:
	_log.append(("  ok: " if cond else "  NG: ") + label)
	if not cond:
		_fail += 1


func _initialize() -> void:
	if FileAccess.file_exists(SaveGame.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.PATH))
	main = load("res://main.tscn").instantiate()
	get_root().add_child(main)


# パネル掃きは「1フレームに1枚」でなければ意味がない。queue_redraw() は次フレームまで
# 遅延するので、1フレーム内で6枚切り替えると最後の1枚しか _draw が走らない
# （＝通っていないコードを通ったと誤認する）。掃き中はメインの進行を止めて数える。
var _sweep_i := -1
var _sweep_label := ""


func _sweep_start(label: String) -> void:
	_sweep_i = 0
	_sweep_label = label


## 掃き中なら1枚だけ開いて true を返す（呼び出し側はそのフレームを消費する）。
func _sweep_tick() -> bool:
	if _sweep_i < 0:
		return false
	if _sweep_i >= PANELS.size():
		main._menu_overlay.visible = false
		_sweep_i = -1
		_ck(true, _sweep_label)
		return false
	main._open_menu(PANELS[_sweep_i])
	main._menu_overlay.queue_redraw()
	_sweep_i += 1
	return true


# 店番の掃き。6人を1フレームに詰め込むと最後の1人しか描かれない。
var _kw_i := -1


func _keeper_start() -> void:
	_kw_i = 0


func _keeper_tick() -> bool:
	if _kw_i < 0:
		return false
	if _kw_i >= KuroData.GIRL_ORDER.size():
		main._menu_overlay.visible = false
		_kw_i = -1
		_ck(true, "6人すべてを店番にして経営パネルを1枚ずつ描ける")
		return false
	main.sim.set_keeper(String(KuroData.GIRL_ORDER[_kw_i]))
	main._open_menu("management")
	main._menu_overlay.queue_redraw()
	_kw_i += 1
	return true


func _process(_d: float) -> bool:
	# 掃き中はメインの進行を進めない（1フレーム1枚を守る）
	if _sweep_tick() or _keeper_tick():
		return false
	_f += 1
	var sim = main.sim
	if _f == 20:
		_ck(main._screen == "res://home_screen.tscn", "ホームで始まる")
		# 装備を持たせてから全パネルを掃く（空の一覧しか描かないと穴を見逃す）
		sim.state["gold"] = 9000
		sim.state["shards"] = 30
		sim.state["scrap"] = 500
		for i in 5:
			var it := SimItems.roll(sim.rng, 4, sim._next_id())
			sim.state["storage"].append(it)
		sim.equip_from_storage(int((sim.state["storage"][0] as Dictionary)["id"]), "mil")
		_sweep_start("全パネルを1枚ずつ描画できる")
	elif _f == 40:
		_keeper_start()   # 6人それぞれを店番にして経営パネルを1枚ずつ描く
	elif _f == 41:
		main._on_home_action("pomodoro")
	elif _f == 60:
		_ck(bool(sim.state["run"]["active"]), "潜航が始まる")
		# 潜航中もシートを開けること（世界の上に窓が開く方式）
		_sweep_start("潜航中でも全パネルを1枚ずつ描画できる")
		sim.state["run"]["anchor"] = float(sim.state["run"]["anchor"]) - 400.0
	elif _f == 85:
		_ck(int(sim.state["run"]["kills"]) > 0, "撃破が積み上がる（%d体）" % int(sim.state["run"]["kills"]))
		_ck(sim.sync_level() >= 2, "同期率が上がる（Lv.%d）" % sim.sync_level())
		sim.state["run"]["anchor"] = float(sim.state["run"]["anchor"]) - float(sim.state["run"]["duration"])
	elif _f == 110:
		_ck(not bool(sim.state["run"]["active"]), "潜航が終わる")
		# 夜営業を放置で流す（タップしない＝席を外した人と同じ条件）
		if main._night_overlay.visible:
			for i in 4000:
				if not main._night_overlay.visible:
					break
				main._night_overlay._process(1.0 / 60.0)
		_ck(not main._night_overlay.visible, "夜営業が放置でも完走する")
	elif _f == 130:
		_ck(main._result_overlay.visible, "精算が出る")
		main._on_home_action("to_home")
	elif _f == 150:
		_ck(int(sim.state["day"]) >= 2, "翌日になる（Day %d）" % int(sim.state["day"]))
		_sweep_start("翌日も全パネルを1枚ずつ描画できる")
		# 中断のペナルティ経路：潜航を始めて即やめる
		main._on_home_action("pomodoro")
	elif _f == 165:
		sim.abandon_run()
		_ck(bool(sim.state["crowd_penalty"]), "中断で客足のペナルティが立つ")
		main._goto(main.HOME)
	elif _f == 185:
		var f: Dictionary = sim.forecast_night()
		_ck(int(f["customers"]) > 0, "罰つきでも見込みが出る（客%d人）" % int(f["customers"]))
		_sweep_start("罰つきの状態でも全パネルを1枚ずつ描画できる")
	elif _f == 186:
		# 掃きが終わってから締める（掃きの直後に quit すると最後の1回が走らない）
		for l in _log:
			print(l)
		print("--- 流れの検証: %s（NG %d件）" % ["FAIL" if _fail > 0 else "PASS", _fail])
		quit(1 if _fail > 0 else 0)
		return true
	return false
