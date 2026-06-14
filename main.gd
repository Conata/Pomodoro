extends Control
## 黒猫飯店 — メインUI（DESIGN.md v4 / WORLD.md 準拠）。
## 1日のループ：朝30秒（編成・献立・扉方針）→ ダイブ（クイック80秒 or
## ポモドーロ15/25/50分）→ 浮上と同時に三行精算 → 箱開封 → 会話 → 翌朝。
## タイマーは unix 秒アンカー＋固定ステップのキャッチアップ
## （タブ非アクティブでも正確。壊すと製品価値が消える部分）。

enum Phase { MORNING, DIVE, CLOSE, NIGHT }

# デザインシステム（src/ui/ds.gd）から引く。色・型・間隔の唯一の真実は DS。
const COL_BG := DS.BG
const COL_PANEL := DS.SURFACE
const COL_EDGE := DS.ACCENT
const COL_TEXT := DS.TEXT
const COL_DIM := DS.TEXT_2
const COL_ACCENT := DS.ACCENT       # 識別色（シアン）= この店のアイデンティティ
const COL_WARM := DS.WARM           # 店番・ネオン看板の暖色アクセント
const TYPE_SMALL := DS.T_MICRO
const TYPE_BODY := DS.T_BODY
const TYPE_SUB := DS.T_SUB
const TYPE_HEAD := DS.T_HEAD
const TYPE_DISPLAY := DS.T_DISPLAY
const SP_1 := DS.SP_1
const SP_2 := DS.SP_2
const SP_3 := DS.SP_3
const SP_4 := DS.SP_4

var sim: KuroSim
var phase: int = Phase.MORNING
var dive_minutes := 25.0
var dive_mode := "pomo"
var save_accum := 0.0
var log_count := 0
var pending_confirm := Callable()
var result_summary := {}
var night_data := {}

var header_bar: HBoxContainer
var dive: DiveView
var dive_frame: PanelContainer
var talk_view: TalkView
var timer_box: VBoxContainer
var timer_label: Label
var status_label: Label
var morning_panel: ScrollContainer
var morning_box: VBoxContainer
var girls_box: VBoxContainer
var menu_box: VBoxContainer
var menu_title: Label
var stock_row: HBoxContainer
var door_btn: Button
var task_edit: LineEdit
var mode_group := ButtonGroup.new()
var forecast_label: Label
var dive_panel: VBoxContainer
var log_label: RichTextLabel
var door_row: HBoxContainer
var abandon_btn: Button
var close_panel: Control
var close_text: Label
var night_panel: ScrollContainer
var night_box: VBoxContainer
var tabs: TabContainer
var inv_box: VBoxContainer
var renov_view: RenovView
var renov_info: Label
var stats_box: VBoxContainer
var ship_label: Label
var ui_accum := 0.0
var offline_note := ""
var banter_rng := RandomNumberGenerator.new()
var banter_timer := 0.0
var banter_next := 6.0
var _ex_queue: Array = []  # 掛け合いの残り行
var _ex_timer := 0.0
var confirm: ConfirmationDialog
var status_overlay: Control
var status_portrait: PortraitRect
var status_name: Label
var status_head: VBoxContainer
var status_body: VBoxContainer
var bgm: AudioStreamPlayer       # 店テーマ（Abstraction CC0）
var bgm_dive: AudioStreamPlayer  # 潜行ドローン（手続き生成）
var bgm_battle: AudioStreamPlayer  # 戦闘レイヤー（手続き生成）
var sfx_pool: Array[AudioStreamPlayer] = []
var sfx_next := 0
var sfx_cache := {}


func _ready() -> void:
	banter_rng.randomize()
	var saved := SaveGame.load_state()
	sim = KuroSim.new(saved)
	_build_ui()
	var now0 := Time.get_unix_time_from_system()
	var offline := sim.apply_offline(now0)
	if not offline.is_empty():
		offline_note = "【安息】閉店中に +%dG・素材+%d（離席%d分）\n" % [
			int(offline["gold"]), int(offline["mats"]), int(float(offline["away"]) / 60.0)]
	sim.maybe_rotate_ship(now0)
	if sim.state["run"]["active"]:
		phase = Phase.DIVE  # 集中中に閉じても復帰できる
	elif not sim.state["pending_night"].is_empty():
		night_data = sim.state["pending_night"]
		phase = Phase.NIGHT
		_refresh_night()
	_pump_events()
	_apply_phase()
	_refresh_all()
	_maybe_event("tutorial")  # 初回だけチュートリアルを出す


## 未読イベントなら再生する。発火条件を増やすのはここに1行。
func _maybe_event(id: String) -> void:
	if id in sim.state["events_seen"] or not EventData.EVENTS.has(id):
		return
	if talk_view.visible:
		return
	var ev: Dictionary = EventData.EVENTS[id]
	talk_view.play(ev, String(ev["speaker"]), {"kind": "event", "id": id})


## 物語の芯：深度・日数の節目で1本ずつ発火（休憩=夜/朝の安全な場で）。
## 条件を足すのはこの表に1行。先頭の未読・条件成立を1つだけ出す。
func _check_story_events() -> void:
	var floor_reached := int(sim.state["best_floor"]) + 1
	var day := int(sim.state["day"])
	var milestones := [
		["story_b3", floor_reached >= 3],
		["story_b6", floor_reached >= 6],
		["story_b10", floor_reached >= 10],
		["story_day3", day >= 3],
	]
	for m in milestones:
		if bool(m[1]) and not String(m[0]) in sim.state["events_seen"]:
			_maybe_event(String(m[0]))
			return  # 1回に1本だけ


## シーン（会話/イベント）完了時の共通処理。
func _on_scene_finished(meta: Dictionary) -> void:
	match String(meta.get("kind", "")):
		"talk":
			sim.complete_talk(String(meta["girl"]), int(meta["tier"]))
			_sfx("ui_equip")
			_save(Time.get_unix_time_from_system())
			_refresh_night()
			_refresh_all()
		"event":
			if not meta["id"] in sim.state["events_seen"]:
				sim.state["events_seen"].append(meta["id"])
				_save(Time.get_unix_time_from_system())


func _process(delta: float) -> void:
	var now := Time.get_unix_time_from_system()
	_update_bgm(delta)
	if phase == Phase.DIVE:
		_catch_up(now)
		save_accum += delta
		if save_accum >= 20.0:
			save_accum = 0.0
			_save(now)
		# 掛け合い再生中はそれを優先、無ければ何もない時間の独り言
		if not _ex_queue.is_empty():
			_ex_timer -= delta
			if _ex_timer <= 0.0:
				var ln: Array = _ex_queue.pop_front()
				_say(String(ln[0]), String(ln[1]))
				_ex_timer = 2.4
		else:
			banter_timer += delta
			if banter_timer >= banter_next:
				banter_timer = 0.0
				banter_next = banter_rng.randf_range(8.0, 15.0)
				_idle_banter()
	_update_clock(now)
	ui_accum += delta
	if ui_accum >= 1.0:
		ui_accum = 0.0
		_refresh_header()
		if phase == Phase.NIGHT:
			var before := float(sim.state["ship"]["rotated"])
			sim.maybe_rotate_ship(now)
			if float(sim.state["ship"]["rotated"]) != before:
				_refresh_night()
			elif ship_label != null and is_instance_valid(ship_label):
				ship_label.text = _ship_head(now)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if sim != null:
			_save(Time.get_unix_time_from_system())


# --- シミュレーション駆動 ----------------------------------------------------


func _catch_up(now: float) -> void:
	var run: Dictionary = sim.state["run"]
	if not run["active"]:
		return
	var target := now - float(run["anchor"])
	var steps := mini(int((target - float(run["elapsed"])) / KuroData.SIM_DT), 200000)
	for i in steps:
		sim.step(KuroData.SIM_DT)
		if not run["active"]:
			break
	_pump_events()


func _pump_events() -> void:
	for e in sim.drain_events():
		match String(e["kind"]):
			"run_complete":
				result_summary = e["summary"]
				_on_run_complete()
			"door":
				_sfx("ui_confirm")
				_log(e["msg"])
				door_row.visible = true
				_banter("door")
			"door_loot":
				_sfx("chest_open")
				_log(e["msg"])
			"gate":
				_sfx("enemy_death")
				dive.spawn_fx("explosion", "enemy")
				_log(e["msg"])
				_banter("gate")
			"boss":
				_log(e["msg"])
				_banter("boss")
			"resync":
				_sfx("damage")
				dive.spawn_fx("smoke", "party")
				_log(e["msg"])
				_banter("wipe")
			"loot":
				_log(e["msg"])
				if banter_rng.randf() < 0.3:
					_banter("loot")
			"level":
				_sfx("thunder")
				dive.spawn_fx("lightning", "party")
				_log(e["msg"])
				_banter("levelup")
			"fx":
				var fxn := String(e.get("fx", ""))
				dive.spawn_fx(fxn, FxData.side_of(fxn))  # 出す側もFxData定義に従う
			_:
				_log(e["msg"])


# --- 掛け合い（潜行中のキャラのセリフ）---------------------------------------


func _banter(cat: String) -> void:
	var line := Banter.pick(cat, sim.divers(), banter_rng)
	if not line.is_empty():
		_say(String(line["girl"]), String(line["text"]))
		banter_timer = 0.0  # 直後の独り言と被らせない


## 何もない時間：戦況に応じて combat/boss/idle を喋る。
## 平時は4割で二人の掛け合いを始める（無ければ独り言）。
func _idle_banter() -> void:
	if phase != Phase.DIVE:
		return
	var cat := "idle"
	for m in sim.state["mobs"]:
		if m["boss"]:
			cat = "boss"
			break
	if cat == "idle" and sim.state["in_combat"]:
		cat = "combat"
	if cat == "idle" and banter_rng.randf() < 0.4:
		var ex := Banter.pick_exchange(sim.divers(), banter_rng)
		if not ex.is_empty():
			_ex_queue = ex["lines"].duplicate()
			_ex_timer = 0.0
			return
	_banter(cat)


func _say(gid: String, text: String) -> void:
	dive.say(gid, text)
	_log("[color=#9fd8ff]%s[/color]「%s」" % [KuroData.GIRLS[gid]["name"], text])


func _on_run_complete() -> void:
	door_row.visible = false
	_ex_queue.clear()
	var disconnected: bool = result_summary.get("disconnected", false)
	_sfx("ui_denied" if disconnected else "teleport")
	if not disconnected and result_summary.get("mode", "") == "pomo":
		sim.register_completion(Time.get_date_string_from_system(), float(result_summary["minutes"]))
		_notify("浮上。%d分の集中、おつかれさま" % int(result_summary["minutes"]))
	# 浮上と同時に夜営業を即時精算（三行）
	night_data = sim.close_day()
	phase = Phase.CLOSE
	var lines: Array = night_data["lines"]
	var head := "【切断】素材半減・未送付の箱を失った\n" if disconnected else ""
	var mats_by: Dictionary = result_summary.get("mats_by", {})
	if not mats_by.is_empty():
		head += "収穫: 乾物%d 肉%d 海鮮%d\n\n" % [
			int(mats_by.get("dry", 0)), int(mats_by.get("meat", 0)), int(mats_by.get("sea", 0))]
	close_text.text = head + "%s\n%s\n%s" % [lines[0], lines[1], lines[2]]
	_save(Time.get_unix_time_from_system())
	_apply_phase()
	_refresh_all()


# --- フェーズ遷移 ------------------------------------------------------------


func _on_depart() -> void:
	if sim.state["morning"]["menu"].is_empty():
		_log("献立が空だ。せめて一品")
		return
	var now := Time.get_unix_time_from_system()
	_request_notify_permission()
	_sfx("ui_confirm")
	if bgm != null and not bgm.playing:
		bgm.play()
	var task := task_edit.text.strip_edges()
	sim.start_run(dive_mode, dive_minutes, now, task if task != "" else "集中セッション")
	phase = Phase.DIVE
	log_label.clear()
	log_count = 0
	_ex_queue.clear()
	banter_timer = 0.0
	banter_next = 3.5
	_pump_events()
	_banter("start")
	_save(now)
	_apply_phase()
	_refresh_all()


func _on_abandon_pressed() -> void:
	_ask("本当に撤退する？\n切断扱い：素材半減・未送付の箱を失う・翌夜の客足が減る\n（ボス箱は送付済みなので無事）", _on_abandon_confirmed)


func _on_abandon_confirmed() -> void:
	_catch_up(Time.get_unix_time_from_system())
	sim.abandon_run()
	_pump_events()


func _on_close_done() -> void:
	phase = Phase.NIGHT
	if night_data.get("story", "") != "":
		_sfx("thunder")
	_apply_phase()
	_refresh_all()
	_check_story_events()  # 浮上後の安全な場で物語の節目を出す


func _on_next_morning() -> void:
	sim.next_morning()
	night_data = {}
	phase = Phase.MORNING
	_sfx("ui_confirm")
	_save(Time.get_unix_time_from_system())
	_apply_phase()
	_refresh_all()
	_check_story_events()  # 日数の節目（story_day3 等）


func _apply_phase() -> void:
	var diving := phase == Phase.DIVE
	dive_panel.visible = diving
	close_panel.visible = phase == Phase.CLOSE
	timer_box.visible = diving
	# 潜行中はビューを大きく、待機中は薄い店先バナーに畳む（スマホ一画面のため）
	if diving:
		dive.custom_minimum_size = Vector2(0, 230)
		dive_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		dive.custom_minimum_size = Vector2(0, 92)
		dive_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tabs.visible = phase == Phase.MORNING or phase == Phase.NIGHT
	if tabs.visible:
		# 準備(0)と閉店後(1)はフェーズ排他。該当タブを明示選択してから他方を隠す
		tabs.set_tab_hidden(0, false)
		tabs.set_tab_hidden(1, false)
		tabs.current_tab = 0 if phase == Phase.MORNING else 1
		tabs.set_tab_hidden(0, phase != Phase.MORNING)
		tabs.set_tab_hidden(1, phase != Phase.NIGHT)
	if phase != Phase.DIVE:
		door_row.visible = false


func _update_clock(now: float) -> void:
	var run: Dictionary = sim.state["run"]
	var title := "黒猫飯店"
	match phase:
		Phase.DIVE:
			var rem := maxf(0.0, float(run["duration"]) - (now - float(run["anchor"])))
			timer_label.text = _mmss(rem)
			if run["mode"] == "pomo":
				status_label.text = String(run["task"])
				title = "%s ▼ %s" % [_mmss(rem), run["task"]]
			else:
				status_label.text = "クイック同期中"
				title = "%s ▼ クイック" % _mmss(rem)
			abandon_btn.visible = run["mode"] == "pomo"
		Phase.MORNING:
			timer_label.text = "Day %d" % int(sim.state["day"])
			status_label.text = "開店前。雨。"
		Phase.NIGHT:
			timer_label.text = "閉店後"
			status_label.text = "箱と、会話と、雨音。"
		Phase.CLOSE:
			timer_label.text = "精算"
			status_label.text = ""
	DisplayServer.window_set_title(title)


func _mmss(sec: float) -> String:
	var s := int(ceil(sec))
	return "%02d:%02d" % [int(s / 60.0), s % 60]


# --- UI構築 ------------------------------------------------------------------


func _build_ui() -> void:
	# 画像ベース(9-patch)テーマを優先。生成テクスチャ未インポート時は DS(flat) へ。
	theme = UIKit.theme() if UIKit.available() else DS.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # 生成アイコンをドットのまま拡大
	var bgrect := ColorRect.new()
	bgrect.color = COL_BG
	bgrect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bgrect)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		root.add_theme_constant_override(m, 12)
	add_child(root)
	var main_box := VBoxContainer.new()
	main_box.add_theme_constant_override("separation", 8)
	root.add_child(main_box)

	var header_panel := PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel", DS._sb(DS.SURFACE, DS.LINE, DS.R_MD, DS.SP_2))
	header_bar = HBoxContainer.new()
	header_bar.add_theme_constant_override("separation", DS.SP_4)
	header_panel.add_child(header_bar)
	main_box.add_child(header_panel)

	# 店先バナー（待機中）／潜行画面（ダイブ中）。高さはフェーズで可変
	dive = DiveView.new()
	dive.sim = sim
	dive.custom_minimum_size = Vector2(0, 92)
	dive.clip_contents = true
	dive_frame = PanelContainer.new()
	dive_frame.add_theme_stylebox_override("panel", _banner_style())
	dive_frame.add_child(dive)
	dive_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	main_box.add_child(dive_frame)

	# タイマー帯（潜行中のみ表示）
	timer_box = VBoxContainer.new()
	timer_box.add_theme_constant_override("separation", 0)
	timer_label = _label("--:--", TYPE_DISPLAY)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_box.add_child(timer_label)
	status_label = _label("", TYPE_BODY, COL_DIM)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_box.add_child(status_label)
	main_box.add_child(timer_box)

	_build_dive_panel(main_box)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_box.add_child(tabs)
	_build_morning(tabs)
	_build_night(tabs)
	_build_inventory_tab()
	_build_renov_tab()
	_build_stats_tab()
	_build_close()

	talk_view = TalkView.new()
	talk_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	talk_view.visible = false
	talk_view.finished.connect(_on_scene_finished)
	add_child(talk_view)

	confirm = ConfirmationDialog.new()
	confirm.ok_button_text = "OK"
	confirm.cancel_button_text = "やめる"
	confirm.confirmed.connect(_on_confirmed)
	add_child(confirm)
	_build_status_overlay()
	_build_audio()


## TBH の英雄画面のような、高解像度キャラ＋装備＋スキルの詳細。
func _build_status_overlay() -> void:
	status_overlay = Control.new()
	status_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	status_overlay.visible = false
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.04, 0.03, 0.88)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	status_overlay.add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 20)
	status_overlay.add_child(margin)
	var card := PanelContainer.new()
	margin.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	# 上段：ポートレート＋名前/ステータス
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	status_portrait = PortraitRect.new()
	status_portrait.custom_minimum_size = Vector2(170, 230)
	top.add_child(status_portrait)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	status_name = _label("", TYPE_HEAD, COL_TEXT)
	info.add_child(status_name)
	status_head = VBoxContainer.new()
	status_head.add_theme_constant_override("separation", 4)
	info.add_child(status_head)
	top.add_child(info)
	box.add_child(top)
	# 下段：装備・スキル・育成ツリー（スクロール）
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	status_body = VBoxContainer.new()
	status_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_body.add_theme_constant_override("separation", 5)
	scroll.add_child(status_body)
	box.add_child(scroll)
	var close := _button("閉じる", _close_status, TYPE_SUB)
	close.custom_minimum_size = Vector2(0, 50)
	box.add_child(close)
	add_child(status_overlay)


func _open_status(id: String) -> void:
	if not status_overlay.visible:
		_sfx("ui_confirm")
	var s := sim.state
	var g: Dictionary = KuroData.GIRLS[id]
	status_portrait.girl_id = id
	status_name.text = String(g["name"])
	_clear(status_head)
	status_head.add_child(_label(String(g["role"]), TYPE_BODY, COL_WARM))
	status_head.add_child(_label("♥ 好感度 %d / 100" % sim.aff(id), TYPE_BODY, Color(1.0, 0.7, 0.85)))
	status_head.add_child(_label("攻撃 %d　最大HP %d" % [int(sim.girl_atk(id)), int(sim.girl_maxhp(id))], TYPE_BODY))
	var fav := _label("好物 %s ／ 店番：%s" % [g["fav"], g["synergy"]], TYPE_SMALL, COL_DIM)
	fav.autowrap_mode = TextServer.AUTOWRAP_OFF
	status_head.add_child(fav)
	_clear(status_body)
	# 装備（3枠）。倉庫タブで埋める
	status_body.add_child(_section("装備"))
	for slot in ["weapon", "armor", "trinket"]:
		var it: Dictionary = s["girls"][id]["equip"][slot]
		var slot_name: String = SimItems.SLOTS[slot]["name"]
		if it.is_empty():
			status_body.add_child(_label("%s： —（倉庫で装着）" % slot_name, TYPE_SMALL, Color(1, 1, 1, 0.45)))
		else:
			status_body.add_child(_label("%s： %s %s" % [slot_name, SimItems.display_name(it), SimItems.affix_text(it)],
					TYPE_SMALL, SimItems.GRADES[int(it["grade"])]["color"]))
	# 育成ツリー（記憶の欠片で解放）
	status_body.add_child(_section("育成ツリー　記憶の欠片 %d" % int(s["shards"])))
	for node in KuroData.GIRL_TREES.get(id, []):
		var owned: bool = node["id"] in s["girls"][id].get("tree", [])
		var avail: bool = sim.tree_available(id, String(node["id"]))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", SP_2)
		var desc := _tree_node_desc(node)
		var col := DS.ACCENT if owned else (COL_TEXT if avail else COL_DIM)
		var lbl := _label(("● " if owned else "○ ") + String(node["name"]) + "  " + desc, TYPE_SMALL, col)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(lbl)
		if owned:
			line.add_child(_label("解放済", TYPE_SMALL, DS.ACCENT))
		else:
			var buy := _button("欠片%d" % int(node["cost"]), _on_tree_buy.bind(id, String(node["id"])), TYPE_SMALL)
			buy.disabled = not avail or int(s["shards"]) < int(node["cost"])
			if not avail and int(node.get("req_aff", 0)) > sim.aff(id):
				buy.text = "♥%d必要" % int(node["req_aff"])
			line.add_child(buy)
		status_body.add_child(line)
	# スキル（装備/外し）。枠は覚醒で増える
	status_body.add_child(_section("スキル（装備枠 %d）" % sim.skill_slots()))
	var sk_flow := HFlowContainer.new()
	sk_flow.add_theme_constant_override("h_separation", 5)
	sk_flow.add_theme_constant_override("v_separation", 5)
	for sid in sim.known_skills(id):
		var def: Dictionary = KuroData.SKILL_DB[sid]
		var equipped: bool = sid in s["girls"][id]["skills_eq"]
		var sk := _button(("★" if equipped else "") + String(def["name"]), _on_status_skill.bind(id, String(sid)), TYPE_SMALL)
		if not equipped and s["girls"][id]["skills_eq"].size() >= sim.skill_slots():
			sk.disabled = true
		sk_flow.add_child(sk)
	status_body.add_child(sk_flow)
	status_overlay.visible = true


func _tree_node_desc(node: Dictionary) -> String:
	var e: Dictionary = node["effect"]
	if e.has("skill"):
		return "技習得"
	var parts: Array[String] = []
	if e.has("atk"):
		parts.append("攻+%d%%" % int(float(e["atk"]) * 100))
	if e.has("hp"):
		parts.append("HP+%d%%" % int(float(e["hp"]) * 100))
	if e.has("crit"):
		parts.append("会心+%d%%" % int(float(e["crit"]) * 100))
	return "／".join(parts)


func _on_tree_buy(id: String, node_id: String) -> void:
	if sim.tree_unlock(id, node_id):
		_sfx("ui_equip")
		_pump_events()
		_save(Time.get_unix_time_from_system())
		_refresh_header()
		_open_status(id)  # 再描画


func _on_status_skill(id: String, sid: String) -> void:
	sim.equip_skill(id, sid)
	_open_status(id)


func _close_status() -> void:
	status_overlay.visible = false


## 店先バナーの枠（角丸＋ネオン縁、内側余白なし）。
func _banner_style() -> StyleBoxFlat:
	var b := DS._sb(DS.SURFACE, Color(DS.ACCENT.r, DS.ACCENT.g, DS.ACCENT.b, 0.45), DS.R_MD, 0)
	return b


## CTA（主要動線）ボタン：アクセント塗り。
func _cta(text: String, cb: Callable, font_size := DS.T_SUB) -> Button:
	return DS.as_primary(_button(text, cb, font_size))


## 資源バッジ：アイコン＋数値（ヘッダーの資源バー用）。
func _badge(tex: Texture2D, value: String, color := COL_TEXT) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", DS.SP_1)
	if tex != null:
		hb.add_child(_icon_rect(tex, 22))
	var l := _label(value, DS.T_BODY, color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	hb.add_child(l)
	return hb


func _build_morning(parent: Control) -> void:
	morning_panel = ScrollContainer.new()
	morning_panel.name = "準備"
	morning_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	morning_panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	morning_box = VBoxContainer.new()
	morning_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	morning_box.add_theme_constant_override("separation", 6)
	morning_panel.add_child(morning_box)

	forecast_label = _label("", 19, Color(1.0, 0.85, 0.5))
	morning_box.add_child(forecast_label)
	stock_row = HBoxContainer.new()
	stock_row.add_theme_constant_override("separation", 2)
	morning_box.add_child(stock_row)

	girls_box = VBoxContainer.new()
	girls_box.add_theme_constant_override("separation", 5)
	morning_box.add_child(girls_box)

	menu_title = _label("献立", 15, COL_DIM)
	morning_box.add_child(menu_title)
	menu_box = VBoxContainer.new()
	morning_box.add_child(menu_box)

	# 下部アクション帯：扉方針＋同期時間＋タスク＋潜る
	var ctrl := HBoxContainer.new()
	ctrl.add_theme_constant_override("separation", 6)
	door_btn = _button("", _on_door_policy, 17)
	door_btn.custom_minimum_size = Vector2(150, 0)
	ctrl.add_child(door_btn)
	for opt in [["速80s", "quick", 0.0], ["15", "pomo", 15.0], ["25", "pomo", 25.0], ["50", "pomo", 50.0]]:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = mode_group
		b.text = String(opt[0])
		b.add_theme_font_size_override("font_size", 17)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_mode.bind(String(opt[1]), float(opt[2])))
		if float(opt[2]) == 25.0:
			b.button_pressed = true
		ctrl.add_child(_juice(b))
	morning_box.add_child(ctrl)
	task_edit = LineEdit.new()
	task_edit.placeholder_text = "集中するタスクを書く（ポモドーロ時）"
	task_edit.add_theme_font_size_override("font_size", 19)
	morning_box.add_child(task_edit)

	var depart := _cta("☂ 潜る", _on_depart, TYPE_SUB)
	depart.custom_minimum_size = Vector2(0, 56)
	morning_box.add_child(depart)
	parent.add_child(morning_panel)


func _build_dive_panel(parent: Control) -> void:
	dive_panel = VBoxContainer.new()
	dive_panel.add_theme_constant_override("separation", 8)
	dive_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	door_row = HBoxContainer.new()
	door_row.add_theme_constant_override("separation", 8)
	door_row.visible = false
	var open_b := _button("扉を開ける", _on_door_choice.bind(true), 22)
	open_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	door_row.add_child(open_b)
	var skip_b := _button("無視して進む", _on_door_choice.bind(false), 22)
	skip_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	door_row.add_child(skip_b)
	dive_panel.add_child(door_row)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.custom_minimum_size = Vector2(0, 120)
	log_label.add_theme_font_size_override("normal_font_size", 19)
	log_label.add_theme_color_override("default_color", COL_TEXT)
	dive_panel.add_child(log_label)
	abandon_btn = DS.as_danger(_button("撤退（切断）…", _on_abandon_pressed, TYPE_BODY))
	dive_panel.add_child(abandon_btn)
	# デバッグ早送り：アンカーを過去にずらすと次フレームのキャッチアップが
	# その分を固定ステップで一気に消化する（決定論は崩れない）
	var dbg := HBoxContainer.new()
	dbg.add_theme_constant_override("separation", 6)
	var dbg_label := _label("DEBUG", 14, Color(1, 1, 1, 0.3))
	dbg.add_child(dbg_label)
	for opt in [["≫ +1分", 60.0], ["≫ +10分", 600.0], ["≫ 完走まで", -1.0]]:
		var b := _button(String(opt[0]), _on_debug_ff.bind(float(opt[1])), 16)
		b.modulate = Color(1, 1, 1, 0.55)
		dbg.add_child(b)
	dive_panel.add_child(dbg)
	parent.add_child(dive_panel)


func _build_night(parent: Control) -> void:
	night_panel = ScrollContainer.new()
	night_panel.name = "閉店後"
	night_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	night_panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	night_box = VBoxContainer.new()
	night_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	night_box.add_theme_constant_override("separation", 8)
	night_panel.add_child(night_box)
	parent.add_child(night_panel)


func _scroll_tab(title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	sc.add_child(box)
	tabs.add_child(sc)
	return box


func _build_inventory_tab() -> void:
	inv_box = _scroll_tab("倉庫")


func _build_renov_tab() -> void:
	var box := _scroll_tab("改装")
	renov_info = _label("ノードをタップして解放（隣のノードから順に）", 17, COL_DIM)
	box.add_child(renov_info)
	renov_view = RenovView.new()
	renov_view.sim = sim
	renov_view.node_tapped.connect(_on_renov_tapped)
	box.add_child(renov_view)


func _build_stats_tab() -> void:
	stats_box = _scroll_tab("統計")


func _build_close() -> void:
	# 全画面オーバーレイ＋中央カード（はみ出し防止のため幅をマージンで束縛）
	close_panel = Control.new()
	close_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	close_panel.visible = false
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.04, 0.03, 0.82)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	close_panel.add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(m, 28)
	close_panel.add_child(margin)
	# 縦スペーサーで上下中央寄せしつつ、カードは束縛幅いっぱいに広げる
	var col := VBoxContainer.new()
	margin.add_child(col)
	var sp_top := Control.new()
	sp_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sp_top)
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", SP_3)
	box.add_child(_section("閉店三行"))
	close_text = _label("", TYPE_BODY)
	close_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(close_text)
	var done := _cta("閉店作業へ", _on_close_done, TYPE_SUB)
	done.custom_minimum_size = Vector2(0, 54)
	box.add_child(done)
	card.add_child(box)
	col.add_child(card)
	var sp_bot := Control.new()
	sp_bot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sp_bot)
	add_child(close_panel)


func _build_audio() -> void:
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		sfx_pool.append(p)
	# ElevenLabs(mp3) > 手続き生成(wav) > 現行（CC0/手続き）の順で優先
	bgm = _make_loop(_audio_pick("bgm_el/store", "res://assets/third_party/music/sketchbook_loop.ogg"), -16.0)
	bgm_dive = _make_loop(_audio_pick("bgm_el/dive", "res://assets/generated/bgm/dive_drone.wav"), -60.0)
	bgm_battle = _make_loop(_audio_pick("bgm_el/battle", "res://assets/generated/bgm/battle_layer.wav"), -60.0)


## 生成BGMがあればそのパス（mp3優先・無ければwav）、無ければフォールバックを返す。
func _audio_pick(gen_base: String, fallback: String) -> String:
	var base := "res://assets/generated/" + gen_base
	if ResourceLoader.exists(base + ".mp3"):
		return base + ".mp3"
	if ResourceLoader.exists(base + ".wav"):
		return base + ".wav"
	return fallback


## ループ再生する AudioStreamPlayer を作る（OGG/WAV 両対応）。
func _make_loop(path: String, vol_db: float) -> AudioStreamPlayer:
	if not ResourceLoader.exists(path):
		return null
	var p := AudioStreamPlayer.new()
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamMP3:
		stream.loop = true  # ElevenLabs生成のBGM
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	p.stream = stream
	p.volume_db = vol_db
	add_child(p)
	return p


## フェーズ・戦況でBGMをクロスフェード（店⇄潜行＋戦闘レイヤー）。
func _update_bgm(delta: float) -> void:
	var diving := phase == Phase.DIVE
	var in_combat: bool = diving and sim.state["in_combat"]
	_fade(bgm, -16.0 if not diving else -42.0, delta)
	_fade(bgm_dive, -10.0 if diving else -60.0, delta)
	_fade(bgm_battle, -10.0 if in_combat else -60.0, delta)


func _fade(p: AudioStreamPlayer, target_db: float, delta: float) -> void:
	if p == null:
		return
	# 鳴っていなければ開始（ユーザー操作後＝Webの自動再生制限を回避）
	if not p.playing and bgm != null and bgm.playing and target_db > -55.0:
		p.play()
	p.volume_db = move_toward(p.volume_db, target_db, 30.0 * delta)


func _label(text: String, font_size: int, color := COL_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


## Vignelli の「ルーラー」：フラッシュレフトの小見出し＋直下に 2px の罫。
## 中央寄せの「― 〜 ―」を置き換え、型を吊るす規律にする。
func _section(text: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", SP_1)
	var lbl := _label(text, TYPE_SMALL, COL_ACCENT)
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(lbl)
	var rule := ColorRect.new()
	rule.color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.5)
	rule.custom_minimum_size = Vector2(0, 2)
	box.add_child(rule)
	return box


func _button(text: String, cb: Callable, font_size := TYPE_SUB) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.pressed.connect(cb)
	return _juice(b)


## 押し心地：押下で少し縮み、離すとポンと戻る。全ボタンに自動適用。
## トグル等 Button.new() を直接作る箇所も _juice(b) を通せば同じ手触りになる。
func _juice(b: Button) -> Button:
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.button_down.connect(func() -> void:
		b.pivot_offset = b.size * 0.5
		create_tween().tween_property(b, "scale", Vector2(0.93, 0.93), 0.06))
	b.button_up.connect(func() -> void:
		var tw := create_tween()
		tw.tween_property(b, "scale", Vector2(1.05, 1.05), 0.07)
		tw.tween_property(b, "scale", Vector2.ONE, 0.08))
	return b


var _gen_cache := {}


func _gen_tex(path: String) -> Texture2D:
	if not _gen_cache.has(path):
		var full := "res://assets/generated/%s.png" % path
		_gen_cache[path] = load(full) if ResourceLoader.exists(full) else null
	return _gen_cache[path]


func _food_icon(id: String) -> Texture2D:
	return _gen_tex("food/" + id)


func _box_icon(grade: int) -> Texture2D:
	return _gen_tex("box/%d" % grade)


func _ing_icon(kind: String) -> Texture2D:
	return _gen_tex("ing/" + kind)


func _icon_rect(tex: Texture2D, sz: int) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = Vector2(sz, sz)
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return tr


func _girl_icon(id: String) -> TextureRect:
	var tr := TextureRect.new()
	var sprite: String = KuroData.GIRLS[id]["sprite"]
	var path := "res://assets/third_party/dungeon/frames/%s_idle_anim_f0.png" % sprite
	if not ResourceLoader.exists(path):
		path = "res://assets/third_party/dungeon/frames/%s_anim_f0.png" % sprite
	if ResourceLoader.exists(path):
		tr.texture = load(path)
	tr.custom_minimum_size = Vector2(52, 78)
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.modulate = Color(1.08, 1.0, 0.9)  # わずかに暖色へ寄せる
	return tr


# --- 表示更新 ----------------------------------------------------------------


func _refresh_all() -> void:
	_refresh_header()
	if phase == Phase.MORNING:
		_refresh_morning()
	elif phase == Phase.NIGHT:
		_refresh_night()
	if tabs.visible:
		_refresh_inventory()
		_refresh_stats()
		renov_view.queue_redraw()


## ヘッダーの資源バー（アイコン付きバッジ）。
func _refresh_header() -> void:
	var s := sim.state
	_clear(header_bar)
	header_bar.add_child(_badge(null, "Day %d" % int(s["day"]), COL_WARM))
	header_bar.add_child(_badge(null, "金%d" % int(s["gold"]), Color(1.0, 0.86, 0.5)))
	header_bar.add_child(_badge(_box_icon(2), "%d" % s["boxes"].size()))
	if int(s["streak"]) > 0:
		header_bar.add_child(_badge(null, "連%d" % int(s["streak"]), COL_ACCENT))
	# 右寄せのスペーサー＋廃材
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_bar.add_child(sp)
	header_bar.add_child(_badge(null, "欠片%d" % int(s["shards"]), Color(1.0, 0.7, 0.85)))
	header_bar.add_child(_badge(null, "屑%d" % int(s["scrap"]), DS.SUCCESS))


func _refresh_morning() -> void:
	var s := sim.state
	forecast_label.text = "%s予報『%s』の客が多い夜" % [offline_note, s["forecast"]]
	# 素材在庫をアイコン付きで
	_clear(stock_row)
	for kind in KuroData.INGS:
		var ic := _ing_icon(kind)
		if ic != null:
			stock_row.add_child(_icon_rect(ic, 26))
		var sl := _label("%s%d　" % [KuroData.ING_NAMES[kind], int(s["stock"][kind])], 18, COL_DIM)
		sl.autowrap_mode = TextServer.AUTOWRAP_OFF
		stock_row.add_child(sl)
	_clear(girls_box)
	for id in KuroData.GIRL_ORDER:
		girls_box.add_child(_girl_card(id))
	menu_title.text = "献立 %d/%d枠 ｜ ◎=予報一致 ⚠=素材切れ" % [s["morning"]["menu"].size(), sim.menu_limit()]
	_clear(menu_box)
	var menu: Array = s["morning"]["menu"]
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 5)
	for id in s["recipes"]:
		if int(s["recipes"][id]) <= 0:
			continue
		var r: Dictionary = KuroData.RECIPES[id]
		var star := int(s["recipes"][id])
		var in_menu: bool = id in menu
		var hit: bool = r["taste"] == s["forecast"]
		var ing_stock := int(s["stock"].get(r["ing"], 0))
		var b2 := Button.new()
		b2.toggle_mode = true
		b2.button_pressed = in_menu
		b2.text = "%s%s☆%d %s%d%s%s" % ["● " if in_menu else "", r["name"], star,
				KuroData.ING_NAMES[r["ing"]], ing_stock,
				" ◎" if hit else "", " ！" if ing_stock <= 0 else ""]
		b2.add_theme_font_size_override("font_size", 17)
		var fi := _food_icon(id)
		if fi != null:
			b2.icon = fi
			b2.add_theme_constant_override("icon_max_width", 26)
		if in_menu:
			b2.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
		b2.pressed.connect(_on_menu_toggle.bind(String(id)))
		flow.add_child(_juice(b2))
	menu_box.add_child(flow)
	door_btn.text = "扉方針：%s" % ("開ける" if s["morning"]["door"] == "open" else "無視する")


## コンパクトな編成カード（小型立ち絵＋2行＋店番トグル）。
func _girl_card(id: String) -> PanelContainer:
	var s := sim.state
	var g: Dictionary = KuroData.GIRLS[id]
	var keeper: bool = s["morning"]["keeper"] == id
	var panel := PanelContainer.new()
	if keeper:
		panel.add_theme_stylebox_override("panel", DS.card_accent(COL_WARM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	# 立ち絵タップで詳細（ステータス）画面
	var icon_btn := Button.new()
	icon_btn.flat = true
	icon_btn.custom_minimum_size = Vector2(44, 58)
	icon_btn.pressed.connect(_open_status.bind(id))
	var icon := _girl_icon(id)
	icon.custom_minimum_size = Vector2(38, 54)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_btn.add_child(icon)
	row.add_child(icon_btn)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	var role := "店番" if keeper else "潜行"
	col.add_child(_label("%s ♥%d  攻%d HP%d  好%s" % [g["name"], sim.aff(id),
			int(sim.girl_atk(id)), int(sim.girl_maxhp(id)), g["fav"]], 18, g["color"]))
	# スキルチップ（コンパクト）
	var skill_row := HBoxContainer.new()
	skill_row.add_theme_constant_override("separation", 3)
	for sid in sim.known_skills(id):
		var def: Dictionary = KuroData.SKILL_DB[sid]
		var equipped: bool = sid in s["girls"][id]["skills_eq"]
		var sk := _button(("★" if equipped else "") + String(def["name"]), _on_skill_toggle.bind(id, String(sid)), 14)
		if not equipped and s["girls"][id]["skills_eq"].size() >= sim.skill_slots():
			sk.disabled = true
		skill_row.add_child(sk)
	if keeper:
		var syn := _label("→ %s" % g["synergy"], 14, Color(1.0, 0.85, 0.5))
		syn.autowrap_mode = TextServer.AUTOWRAP_OFF
		skill_row.add_child(syn)
	col.add_child(skill_row)
	row.add_child(col)
	var b := _button(role, _on_keeper.bind(id), 18)
	b.custom_minimum_size = Vector2(58, 0)
	b.disabled = keeper
	if keeper:
		b.modulate = Color(1.0, 0.85, 0.5)
	row.add_child(b)
	panel.add_child(row)
	return panel


func _refresh_night() -> void:
	_clear(night_box)
	var s := sim.state
	if not night_data.is_empty():
		var panel := PanelContainer.new()
		var box := VBoxContainer.new()
		for line in night_data["lines"]:
			box.add_child(_label(String(line), 20))
		panel.add_child(box)
		night_box.add_child(panel)
		if night_data.get("story", "") != "":
			var sp := PanelContainer.new()
			var sl := _label("【住民の物語】\n" + String(night_data["story"]), 19, Color(1.0, 0.9, 0.6))
			sp.add_child(sl)
			night_box.add_child(sp)
	var open_b := _button("箱を開ける（残り %d）" % s["boxes"].size(), _on_open_box, 24)
	open_b.disabled = s["boxes"].is_empty()
	if not s["boxes"].is_empty():
		var bi := _box_icon(int(s["boxes"][0]))
		if bi != null:
			open_b.icon = bi
			open_b.add_theme_constant_override("icon_max_width", 30)
	night_box.add_child(open_b)
	var talk := sim.available_talk()
	if not talk.is_empty():
		var g: Dictionary = KuroData.GIRLS[talk["girl"]]
		var scene: Dictionary = TalkData.TALKS[talk["girl"]][talk["tier"]]
		var tb := _button("会話：%s —「%s」" % [g["name"], scene["title"]],
				_on_talk_start.bind(String(talk["girl"]), int(talk["tier"])), 24)
		tb.modulate = Color(1.0, 0.85, 0.95)
		night_box.add_child(tb)
	night_box.add_child(_section("闇市"))
	for i in KuroData.MARKET.size():
		var item: Dictionary = KuroData.MARKET[i]
		var icon: Texture2D = null
		if String(item["id"]) == "mats":
			icon = _ing_icon("meat")
		elif String(item["id"]) == "recipe":
			icon = _food_icon("chashu")
		night_box.add_child(_list_row(String(item["name"]), "%dG" % int(item["price"]),
				_on_buy.bind(i), int(s["gold"]) >= int(item["price"]), icon))
	# 交易船（10分毎に在庫入替）
	ship_label = _label(_ship_head(Time.get_unix_time_from_system()), TYPE_SMALL, COL_ACCENT)
	ship_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	night_box.add_child(ship_label)
	var ship_rule := ColorRect.new()
	ship_rule.color = DS.ACCENT_DIM
	ship_rule.custom_minimum_size = Vector2(0, 2)
	night_box.add_child(ship_rule)
	var stock: Array = s["ship"]["stock"]
	if stock.is_empty():
		night_box.add_child(_label("（船は出払っている。次の入荷を待とう）", TYPE_SMALL, COL_DIM))
	for i in stock.size():
		var entry: Dictionary = stock[i]
		var text := ""
		var tcol := COL_TEXT
		if entry["type"] == "pet":
			var pet: Dictionary = KuroData.PETS[entry["pet"]]
			text = "ペット：%s — %s" % [pet["name"], pet["desc"]]
			tcol = COL_WARM
		else:
			var it: Dictionary = entry["item"]
			text = "%s %s" % [SimItems.display_name(it), SimItems.affix_text(it)]
			tcol = SimItems.GRADES[int(entry["item"]["grade"])]["color"]
		night_box.add_child(_list_row(text, "%dG" % int(entry["price"]),
				_on_ship_buy.bind(i), int(s["gold"]) >= int(entry["price"]), null, tcol))
	if not s["pets"].is_empty():
		var pet_names: Array[String] = []
		for pid in s["pets"]:
			pet_names.append(KuroData.PETS[pid]["name"])
		night_box.add_child(_label("店の住人: " + "、".join(pet_names), 16, COL_DIM))
	night_box.add_child(_label("好感度：%s" % "  ".join(_aff_summary()), 16, COL_DIM))
	var next := _cta("☀ 翌朝へ", _on_next_morning, TYPE_SUB)
	next.custom_minimum_size = Vector2(0, 56)
	night_box.add_child(next)


## リスト行コンポーネント：[アイコン] 見出し（伸長）[末尾アクション]。
## 闇市・交易船など「1行1アクション」のリストに使う。面はSURFACEの薄カード。
func _list_row(title: String, action_text: String, cb: Callable, enabled: bool,
		icon: Texture2D = null, title_color := COL_TEXT) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", DS._sb(DS.SURFACE, DS.LINE, DS.R_SM, DS.SP_2))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SP_2)
	if icon != null:
		row.add_child(_icon_rect(icon, 30))
	var lbl := _label(title, TYPE_BODY, title_color)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var act := _button(action_text, cb, TYPE_BODY)
	act.disabled = not enabled
	act.custom_minimum_size = Vector2(78, 0)
	row.add_child(act)
	panel.add_child(row)
	return panel


func _ship_head(now: float) -> String:
	var rem := maxf(0.0, KuroData.SHIP_ROTATE_SEC - (now - float(sim.state["ship"]["rotated"])))
	return "交易船　入替まで %s" % _mmss(rem)


func _refresh_inventory() -> void:
	_clear(inv_box)
	var s := sim.state
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", SP_2)
	row.add_child(_badge(null, "屑 %d" % int(s["scrap"]), DS.SUCCESS))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	row.add_child(_button("一括分解", _on_bulk_salvage, TYPE_BODY))
	row.add_child(_button("合成 3→1", _on_synthesize, TYPE_BODY))
	inv_box.add_child(row)
	# 装備中サマリ
	inv_box.add_child(_section("装備中"))
	for id in KuroData.GIRL_ORDER:
		var parts: Array[String] = []
		for slot in ["weapon", "armor", "trinket"]:
			var it: Dictionary = s["girls"][id]["equip"][slot]
			parts.append("—" if it.is_empty() else SimItems.display_name(it))
		var sl := _label("%s  %s" % [KuroData.GIRLS[id]["name"], "  ".join(parts)], TYPE_SMALL, COL_DIM)
		sl.autowrap_mode = TextServer.AUTOWRAP_OFF
		inv_box.add_child(sl)
	var inv: Array = s["inventory"]
	inv_box.add_child(_section("倉庫"))
	if inv.is_empty():
		inv_box.add_child(_label("倉庫は空。潜って拾おう（装備は自動装着される）", TYPE_SMALL, COL_DIM))
		return
	var sorted_items := inv.duplicate()
	sorted_items.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	var shown: int = mini(sorted_items.size(), 40)
	for k in shown:
		var it: Dictionary = sorted_items[k]
		var target := _equip_target(it)
		var diff := float(it["score"]) - float(target["cur_score"])
		var badge := ("▲+%d" % int(diff)) if diff > 0.0 else ("▼%d" % int(diff))
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", DS._sb(DS.SURFACE, DS.LINE, DS.R_SM, DS.SP_2))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", SP_1)
		var name_label := _label("%s %s %s" % [SimItems.display_name(it), SimItems.affix_text(it), badge],
				TYPE_SMALL, SimItems.GRADES[int(it["grade"])]["color"])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		var eq := _button("装備", _on_equip.bind(int(it["id"])), TYPE_SMALL)
		eq.disabled = diff <= 0.0
		line.add_child(eq)
		line.add_child(_button("分解", _on_salvage.bind(int(it["id"])), TYPE_SMALL))
		var rr := _button("刻印", _on_reroll.bind(int(it["id"])), TYPE_SMALL)
		rr.disabled = int(s["scrap"]) < SimItems.REROLL_COST
		line.add_child(rr)
		panel.add_child(line)
		inv_box.add_child(panel)
	if sorted_items.size() > shown:
		inv_box.add_child(_label("…ほか %d 品（スコア上位のみ表示）" % (sorted_items.size() - shown), TYPE_SMALL, COL_DIM))


## このアイテムを最も活かせる子（現装備スコアが最低）。
func _equip_target(item: Dictionary) -> Dictionary:
	var best_id := KuroData.GIRL_ORDER[0]
	var best_cur := INF
	for id in KuroData.GIRL_ORDER:
		var cur: Dictionary = sim.state["girls"][id]["equip"][item["slot"]]
		var cur_score := 0.0 if cur.is_empty() else float(cur["score"])
		if cur_score < best_cur:
			best_cur = cur_score
			best_id = id
	return {"girl": best_id, "cur_score": best_cur}


func _refresh_stats() -> void:
	_clear(stats_box)
	var s := sim.state
	var total_min := float(s["stats"]["focus_min"])
	stats_box.add_child(_label("累計集中: %d時間%d分   潜行: %d回" % [
		int(total_min / 60.0), int(total_min) % 60, int(s["stats"]["dives"])], 20))
	stats_box.add_child(_label("ストリーク: %d連続完走   最深: B%dF   営業: %d日目" % [
		int(s["streak"]), int(s["best_floor"]) + 1, int(s["day"])], 18))
	var today := Time.get_date_string_from_system()
	var runs_today := int(s["daily"]["runs"]) if String(s["daily"]["date"]) == today else 0
	stats_box.add_child(_label("デイリー: 今日 %d/3 完走（ポモドーロのみ）" % runs_today, 18))
	if runs_today >= 3 and not s["daily"]["claimed"]:
		stats_box.add_child(_button("デイリー報酬（+500G）", _on_claim_daily, TYPE_SUB))
	# デバッグ：獲得x10トグル
	var dbg := _button("DEBUG 獲得x10：%s" % ("ON" if s.get("debug_x10", false) else "OFF"),
			_on_toggle_debug_gain, TYPE_SMALL)
	dbg.modulate = Color(1, 0.85, 0.5) if s.get("debug_x10", false) else Color(1, 1, 1, 0.6)
	stats_box.add_child(dbg)
	stats_box.add_child(_section("週間集中グラフ"))
	var now := Time.get_unix_time_from_system()
	for i in range(6, -1, -1):
		var date := Time.get_datetime_string_from_unix_time(int(now) - i * 86400).substr(0, 10)
		var minutes := float(s["weekly"].get(date, 0.0))
		var bar := "■".repeat(mini(int(minutes / 15.0) + (1 if minutes > 0.0 else 0), 20))
		stats_box.add_child(_label("%s  %s %d分" % [date.substr(5), bar, int(minutes)], 16))
	stats_box.add_child(_label(
		"Sprites:0x72(CC0) FX:pimen SFX:Leohpaz Music:Abstraction(CC0) Font:DotGothic16(OFL)",
		12, Color(1, 1, 1, 0.25)))


func _aff_summary() -> Array[String]:
	var out: Array[String] = []
	for id in KuroData.GIRL_ORDER:
		out.append("%s♥%d" % [KuroData.GIRLS[id]["name"], sim.aff(id)])
	return out


func _log(msg: String) -> void:
	if msg.is_empty():
		return
	log_count += 1
	if log_count > 300:
		log_label.clear()
		log_count = 0
	log_label.append_text(msg + "\n")


# --- 操作 --------------------------------------------------------------------


func _on_keeper(id: String) -> void:
	sim.set_keeper(id)
	_refresh_morning()


func _on_menu_toggle(id: String) -> void:
	sim.toggle_menu(id)
	_refresh_morning()


func _on_door_policy() -> void:
	var m: Dictionary = sim.state["morning"]
	m["door"] = "skip" if m["door"] == "open" else "open"
	_refresh_morning()


func _on_mode(mode: String, minutes: float) -> void:
	dive_mode = mode
	dive_minutes = minutes
	task_edit.visible = mode == "pomo"


func _on_door_choice(open: bool) -> void:
	door_row.visible = false
	sim.resolve_door(open)
	_pump_events()


## デバッグ早送り。seconds=-1 は残り時間ぜんぶ（完走まで）。
func _on_debug_ff(seconds: float) -> void:
	var run: Dictionary = sim.state["run"]
	if not run["active"]:
		return
	if seconds < 0.0:
		seconds = float(run["duration"]) - float(run["elapsed"]) + 1.0
	run["anchor"] = float(run["anchor"]) - seconds
	_log("（DEBUG）%d秒 早送り" % int(seconds))


func _on_open_box() -> void:
	var r := sim.open_box()
	if r.is_empty():
		return
	_sfx("chest_open")
	var panel := PanelContainer.new()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var bi := _box_icon(int(r["grade"]))
	if bi != null:
		hb.add_child(_icon_rect(bi, 30))
	var rl := _label("%s → %s" % [KuroData.BOX_NAMES[int(r["grade"])], r["text"]], 20, DS.SUCCESS)
	rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(rl)
	panel.add_child(hb)
	night_box.add_child(panel)
	night_box.move_child(panel, 1)
	_save(Time.get_unix_time_from_system())
	_refresh_night()


func _on_buy(idx: int) -> void:
	var r := sim.market_buy(idx)
	if r.is_empty():
		return
	_sfx("ui_buy")
	_save(Time.get_unix_time_from_system())
	_refresh_night()


func _on_skill_toggle(girl_id: String, skill_id: String) -> void:
	sim.equip_skill(girl_id, skill_id)
	_refresh_morning()


func _on_equip(item_id: int) -> void:
	for it in sim.state["inventory"]:
		if int(it["id"]) == item_id:
			sim.equip_from_inventory(item_id, String(_equip_target(it)["girl"]))
			_sfx("ui_equip")
			break
	_refresh_all()


func _on_salvage(item_id: int) -> void:
	sim.salvage_item(item_id)
	_refresh_inventory()
	_refresh_header()


func _on_reroll(item_id: int) -> void:
	if sim.reroll_item(item_id):
		_sfx("ui_equip")
	_refresh_inventory()
	_refresh_header()


func _on_bulk_salvage() -> void:
	var r := sim.bulk_salvage()
	_sfx("ui_buy")
	_refresh_inventory()
	_refresh_header()
	inv_box.add_child(_label("一括分解: %d品 → 廃材+%d" % [int(r["count"]), int(r["dust"])], 16, DS.SUCCESS))


func _on_synthesize() -> void:
	var made := sim.synthesize_all()
	if made > 0:
		_sfx("ui_equip")
	_pump_events()
	_refresh_all()


func _on_renov_tapped(id: String) -> void:
	var node: Dictionary = KuroData.RENOV_NODES[id]
	if id in sim.state["renov"]:
		renov_info.text = "%s: %s（改装済み）" % [node["name"], node["desc"]]
		return
	if not sim.renov_available(id):
		renov_info.text = "%s: 隣の区画から先に改装しよう" % node["name"]
		return
	renov_info.text = "%s: %s" % [node["name"], node["desc"]]
	_ask("「%s」を %dG で改装する？\n%s" % [node["name"], int(node["cost"]), node["desc"]],
			_on_renov_confirmed.bind(id))


func _on_renov_confirmed(id: String) -> void:
	if sim.unlock_renov(id):
		_sfx("ui_confirm")
		_pump_events()
		_save(Time.get_unix_time_from_system())
		_refresh_all()
	else:
		renov_info.text = "ゴールドが足りない…"


func _on_ship_buy(idx: int) -> void:
	if sim.buy_ship(idx):
		_sfx("ui_buy")
		_pump_events()
		_save(Time.get_unix_time_from_system())
		_refresh_all()


func _on_claim_daily() -> void:
	if sim.claim_daily():
		_sfx("chest_open")
		_pump_events()
		_save(Time.get_unix_time_from_system())
		_refresh_all()


func _on_toggle_debug_gain() -> void:
	sim.state["debug_x10"] = not sim.state.get("debug_x10", false)
	_sfx("ui_confirm")
	_save(Time.get_unix_time_from_system())
	_refresh_all()


func _on_talk_start(girl: String, tier: int) -> void:
	_sfx("ui_confirm")
	talk_view.start(girl, tier)  # 完了は _on_scene_finished が処理


func _ask(text: String, cb: Callable) -> void:
	pending_confirm = cb
	confirm.dialog_text = text
	confirm.popup_centered()


func _on_confirmed() -> void:
	if pending_confirm.is_valid():
		pending_confirm.call()
	pending_confirm = Callable()


func _clear(box: Control) -> void:
	for c in box.get_children():
		c.queue_free()


func _save(now: float) -> void:
	sim.sync_rng()
	sim.state["last_seen"] = now
	SaveGame.save_state(sim.state)


func _sfx(sfx_name: String) -> void:
	if not sfx_cache.has(sfx_name):
		# ElevenLabs(mp3) > 手続き生成(wav) > 現行(wav) の順で優先
		var gen := "res://assets/generated/sfx/" + sfx_name
		var path := "res://assets/third_party/sfx/%s.wav" % sfx_name
		if ResourceLoader.exists(gen + ".mp3"):
			path = gen + ".mp3"
		elif ResourceLoader.exists(gen + ".wav"):
			path = gen + ".wav"
		sfx_cache[sfx_name] = load(path) if ResourceLoader.exists(path) else null
	var stream: AudioStream = sfx_cache[sfx_name]
	if stream == null:
		return
	var p := sfx_pool[sfx_next]
	sfx_next = (sfx_next + 1) % sfx_pool.size()
	p.stream = stream
	p.play()


func _notify(text: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"if(window.Notification&&Notification.permission==='granted'){new Notification(%s);}" % JSON.stringify(text),
			true)


func _request_notify_permission() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"if(window.Notification&&Notification.permission==='default'){Notification.requestPermission();}",
			true)
