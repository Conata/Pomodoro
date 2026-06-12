extends Control
## 黒猫飯店 — メインUI（DESIGN.md v4 / WORLD.md 準拠）。
## 1日のループ：朝30秒（編成・献立・扉方針）→ ダイブ（クイック80秒 or
## ポモドーロ15/25/50分）→ 浮上と同時に三行精算 → 箱開封 → 会話 → 翌朝。
## タイマーは unix 秒アンカー＋固定ステップのキャッチアップ
## （タブ非アクティブでも正確。壊すと製品価値が消える部分）。

enum Phase { MORNING, DIVE, CLOSE, NIGHT }

const COL_BG := Color(0.025, 0.05, 0.15)
const COL_PANEL := Color(0.05, 0.10, 0.27, 0.92)
const COL_EDGE := Color(0.45, 0.8, 1.0)
const COL_TEXT := Color(0.92, 0.96, 1.0)
const COL_DIM := Color(0.65, 0.8, 1.0, 0.7)

var sim: KuroSim
var phase: int = Phase.MORNING
var dive_minutes := 25.0
var dive_mode := "pomo"
var save_accum := 0.0
var log_count := 0
var pending_confirm := Callable()
var result_summary := {}
var night_data := {}

var header_label: Label
var dive: DiveView
var talk_view: TalkView
var timer_label: Label
var status_label: Label
var morning_panel: ScrollContainer
var morning_box: VBoxContainer
var girls_box: VBoxContainer
var menu_box: VBoxContainer
var door_btn: Button
var task_edit: LineEdit
var mode_group := ButtonGroup.new()
var forecast_label: Label
var dive_panel: VBoxContainer
var log_label: RichTextLabel
var door_row: HBoxContainer
var abandon_btn: Button
var close_panel: PanelContainer
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
var confirm: ConfirmationDialog
var bgm: AudioStreamPlayer
var sfx_pool: Array[AudioStreamPlayer] = []
var sfx_next := 0
var sfx_cache := {}


func _ready() -> void:
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


func _process(delta: float) -> void:
	var now := Time.get_unix_time_from_system()
	if phase == Phase.DIVE:
		_catch_up(now)
		save_accum += delta
		if save_accum >= 20.0:
			save_accum = 0.0
			_save(now)
	_update_clock(now)
	ui_accum += delta
	if ui_accum >= 1.0:
		ui_accum = 0.0
		header_label.text = _header_text()
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
			"door_loot":
				_sfx("chest_open")
				_log(e["msg"])
			"gate":
				_sfx("enemy_death")
				dive.spawn_fx("explosion", "enemy")
				_log(e["msg"])
			"resync":
				_sfx("damage")
				dive.spawn_fx("smoke", "party")
				_log(e["msg"])
			"fx":
				dive.spawn_fx(String(e.get("fx", "")), "enemy")
			_:
				_log(e["msg"])


func _on_run_complete() -> void:
	door_row.visible = false
	var disconnected: bool = result_summary.get("disconnected", false)
	_sfx("ui_denied" if disconnected else "teleport")
	if not disconnected and result_summary.get("mode", "") == "pomo":
		sim.register_completion(Time.get_date_string_from_system(), float(result_summary["minutes"]))
		_notify("浮上。%d分の集中、おつかれさま" % int(result_summary["minutes"]))
	# 浮上と同時に夜営業を即時精算（三行）
	night_data = sim.close_day()
	phase = Phase.CLOSE
	var lines: Array = night_data["lines"]
	var head := "【切断】素材半減・未送付の箱を失った\n\n" if disconnected else ""
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
	_pump_events()
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


func _on_next_morning() -> void:
	sim.next_morning()
	night_data = {}
	phase = Phase.MORNING
	_sfx("ui_confirm")
	_save(Time.get_unix_time_from_system())
	_apply_phase()
	_refresh_all()


func _apply_phase() -> void:
	dive_panel.visible = phase == Phase.DIVE
	close_panel.visible = phase == Phase.CLOSE
	tabs.visible = phase == Phase.MORNING or phase == Phase.NIGHT
	if tabs.visible:
		tabs.set_tab_hidden(0, phase != Phase.MORNING)
		tabs.set_tab_hidden(1, phase != Phase.NIGHT)
		if phase == Phase.MORNING and tabs.current_tab == 1:
			tabs.current_tab = 0
		elif phase == Phase.NIGHT and tabs.current_tab == 0:
			tabs.current_tab = 1
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
	theme = _make_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
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

	header_label = _label("", 20, Color(0.6, 0.9, 1.0))
	main_box.add_child(header_label)

	dive = DiveView.new()
	dive.sim = sim
	dive.custom_minimum_size = Vector2(0, 300)
	main_box.add_child(dive)

	timer_label = _label("--:--", 56)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_box.add_child(timer_label)
	status_label = _label("", 20, COL_DIM)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_box.add_child(status_label)

	_build_dive_panel(main_box)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size = Vector2(0, 430)
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
	talk_view.finished.connect(_on_talk_finished)
	add_child(talk_view)

	confirm = ConfirmationDialog.new()
	confirm.ok_button_text = "OK"
	confirm.cancel_button_text = "やめる"
	confirm.confirmed.connect(_on_confirmed)
	add_child(confirm)
	_build_audio()


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 24
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.13, 0.34)
	sb.border_color = Color(COL_EDGE.r, COL_EDGE.g, COL_EDGE.b, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(10)
	th.set_stylebox("normal", "Button", sb)
	var sbh := sb.duplicate()
	sbh.bg_color = Color(0.10, 0.22, 0.5)
	sbh.border_color = COL_EDGE
	th.set_stylebox("hover", "Button", sbh)
	th.set_stylebox("pressed", "Button", sbh)
	var sbd := sb.duplicate()
	sbd.bg_color = Color(0.04, 0.07, 0.16)
	sbd.border_color = Color(1, 1, 1, 0.12)
	th.set_stylebox("disabled", "Button", sbd)
	th.set_color("font_color", "Button", COL_TEXT)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color.WHITE)
	th.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.3))
	var pb := StyleBoxFlat.new()
	pb.bg_color = COL_PANEL
	pb.border_color = Color(COL_EDGE.r, COL_EDGE.g, COL_EDGE.b, 0.35)
	pb.set_border_width_all(1)
	pb.set_corner_radius_all(3)
	pb.set_content_margin_all(10)
	th.set_stylebox("panel", "PanelContainer", pb)
	return th


func _build_morning(parent: Control) -> void:
	morning_panel = ScrollContainer.new()
	morning_panel.name = "準備"
	morning_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	morning_panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	morning_box = VBoxContainer.new()
	morning_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	morning_box.add_theme_constant_override("separation", 8)
	morning_panel.add_child(morning_box)

	forecast_label = _label("", 22, Color(1.0, 0.85, 0.5))
	morning_box.add_child(forecast_label)

	morning_box.add_child(_label("― 編成（潜行3人＋店番1人。タップで店番交代）―", 18, COL_DIM))
	girls_box = VBoxContainer.new()
	girls_box.add_theme_constant_override("separation", 6)
	morning_box.add_child(girls_box)

	morning_box.add_child(_label("― 今夜の献立（4枠まで）―", 18, COL_DIM))
	menu_box = VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 4)
	morning_box.add_child(menu_box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	door_btn = _button("", _on_door_policy, 20)
	door_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(door_btn)
	morning_box.add_child(row)

	morning_box.add_child(_label("― 同期時間 ―", 18, COL_DIM))
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 6)
	for opt in [["クイック", "quick", 0.0], ["15分", "pomo", 15.0], ["25分", "pomo", 25.0], ["50分", "pomo", 50.0]]:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = mode_group
		b.text = String(opt[0])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_mode.bind(String(opt[1]), float(opt[2])))
		if float(opt[2]) == 25.0:
			b.button_pressed = true
		mrow.add_child(b)
	morning_box.add_child(mrow)
	task_edit = LineEdit.new()
	task_edit.placeholder_text = "集中するタスクを書く（ポモドーロ時）"
	task_edit.add_theme_font_size_override("font_size", 22)
	morning_box.add_child(task_edit)

	var depart := _button("☂ 潜る", _on_depart, 30)
	depart.custom_minimum_size = Vector2(0, 60)
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
	log_label.scroll_following = true
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.custom_minimum_size = Vector2(0, 200)
	log_label.add_theme_font_size_override("normal_font_size", 20)
	log_label.add_theme_color_override("default_color", COL_TEXT)
	dive_panel.add_child(log_label)
	abandon_btn = _button("撤退（切断）…", _on_abandon_pressed, 20)
	abandon_btn.modulate = Color(1, 0.7, 0.75)
	dive_panel.add_child(abandon_btn)
	# デバッグ早送り：アンカーを過去にずらすと次フレームのキャッチアップが
	# その分を固定ステップで一気に消化する（決定論は崩れない）
	var dbg := HBoxContainer.new()
	dbg.add_theme_constant_override("separation", 6)
	var dbg_label := _label("DEBUG", 14, Color(1, 1, 1, 0.3))
	dbg.add_child(dbg_label)
	for opt in [["⏩ +1分", 60.0], ["⏩ +10分", 600.0], ["⏩ 完走まで", -1.0]]:
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
	close_panel = PanelContainer.new()
	close_panel.set_anchors_preset(Control.PRESET_CENTER)
	close_panel.visible = false
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(580, 0)
	box.add_theme_constant_override("separation", 12)
	box.add_child(_label("― 閉店三行 ―", 28, Color(0.6, 0.95, 1.0)))
	close_text = _label("", 23)
	box.add_child(close_text)
	box.add_child(_button("閉店作業へ", _on_close_done, 26))
	close_panel.add_child(box)
	add_child(close_panel)


func _build_audio() -> void:
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		sfx_pool.append(p)
	var music_path := "res://assets/third_party/music/sketchbook_loop.ogg"
	if ResourceLoader.exists(music_path):
		bgm = AudioStreamPlayer.new()
		var stream: AudioStream = load(music_path)
		if stream is AudioStreamOggVorbis:
			stream.loop = true
		bgm.stream = stream
		bgm.volume_db = -18.0
		add_child(bgm)


func _label(text: String, font_size: int, color := COL_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, cb: Callable, font_size := 24) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.pressed.connect(cb)
	return b


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
	tr.modulate = Color(0.7, 0.85, 1.15)
	return tr


# --- 表示更新 ----------------------------------------------------------------


func _refresh_all() -> void:
	header_label.text = _header_text()
	if phase == Phase.MORNING:
		_refresh_morning()
	elif phase == Phase.NIGHT:
		_refresh_night()
	if tabs.visible:
		_refresh_inventory()
		_refresh_stats()
		renov_view.queue_redraw()


func _header_text() -> String:
	var s := sim.state
	return "Day%d 💰%d 素材%d ♻%d 看板%d 📦%d 🔥%d" % [
		int(s["day"]), int(s["gold"]), int(s["stock"]), int(s["scrap"]),
		sim.sign_total(), s["boxes"].size(), int(s["streak"])]


func _refresh_morning() -> void:
	var s := sim.state
	forecast_label.text = "%s今夜の予報：『%s』が出る。在庫 素材%d" % [offline_note, s["forecast"], int(s["stock"])]
	_clear(girls_box)
	for id in KuroData.GIRL_ORDER:
		var g: Dictionary = KuroData.GIRLS[id]
		var keeper: bool = s["morning"]["keeper"] == id
		var panel := PanelContainer.new()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_girl_icon(id))
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(_label("%s（%s）♥%d  攻%d HP%d" % [g["name"], g["role"], sim.aff(id),
				int(sim.girl_atk(id)), int(sim.girl_maxhp(id))], 22, g["color"]))
		col.add_child(_label("好物:%s ／ 店番:%s（%s）" % [g["fav"], g["synergy"], g["synergy_desc"]], 16, COL_DIM))
		var skill_row := HBoxContainer.new()
		skill_row.add_theme_constant_override("separation", 4)
		skill_row.add_child(_label("技 %d/%d:" % [s["girls"][id]["skills_eq"].size(), sim.skill_slots()], 15, COL_DIM))
		for sid in sim.known_skills(id):
			var def: Dictionary = KuroData.SKILL_DB[sid]
			var equipped: bool = sid in s["girls"][id]["skills_eq"]
			var sk := _button(("✦" if equipped else "") + String(def["name"]), _on_skill_toggle.bind(id, String(sid)), 15)
			if not equipped and s["girls"][id]["skills_eq"].size() >= sim.skill_slots():
				sk.disabled = true
			skill_row.add_child(sk)
		var next_tier := sim.known_skills(id).size()
		if next_tier < 3:
			skill_row.add_child(_label("（次:♥%d）" % KuroData.SKILL_UNLOCK_AFF[next_tier], 14, Color(1, 1, 1, 0.3)))
		col.add_child(skill_row)
		row.add_child(col)
		var b := _button("店番" if keeper else "潜行", _on_keeper.bind(id), 20)
		b.disabled = keeper
		if keeper:
			b.modulate = Color(1.0, 0.85, 0.5)
		row.add_child(b)
		panel.add_child(row)
		girls_box.add_child(panel)
	_clear(menu_box)
	var menu: Array = s["morning"]["menu"]
	for id in s["recipes"]:
		if int(s["recipes"][id]) <= 0:
			continue
		var r: Dictionary = KuroData.RECIPES[id]
		var star := int(s["recipes"][id])
		var in_menu: bool = id in menu
		var hit: bool = r["taste"] == s["forecast"]
		var b2 := Button.new()
		b2.toggle_mode = true
		b2.button_pressed = in_menu
		b2.text = "%s%s ☆%d [%s] %dG%s" % ["✓ " if in_menu else "", r["name"], star,
				r["taste"], KuroData.recipe_price(id, star), "  ◎予報" if hit else ""]
		b2.add_theme_font_size_override("font_size", 20)
		b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b2.pressed.connect(_on_menu_toggle.bind(String(id)))
		menu_box.add_child(b2)
	door_btn.text = "扉方針：%s（階の中間に「増築された扉」が出る）" % (
			"開ける" if s["morning"]["door"] == "open" else "無視する")


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
	var open_b := _button("📦 箱を開ける（残り %d）" % s["boxes"].size(), _on_open_box, 24)
	open_b.disabled = s["boxes"].is_empty()
	night_box.add_child(open_b)
	var talk := sim.available_talk()
	if not talk.is_empty():
		var g: Dictionary = KuroData.GIRLS[talk["girl"]]
		var scene: Dictionary = TalkData.TALKS[talk["girl"]][talk["tier"]]
		var tb := _button("💬 %s と話す —「%s」" % [g["name"], scene["title"]],
				_on_talk_start.bind(String(talk["girl"]), int(talk["tier"])), 24)
		tb.modulate = Color(1.0, 0.85, 0.95)
		night_box.add_child(tb)
	night_box.add_child(_label("― 闇市 ―", 18, COL_DIM))
	for i in KuroData.MARKET.size():
		var item: Dictionary = KuroData.MARKET[i]
		var row := HBoxContainer.new()
		var lbl := _label(String(item["name"]), 20)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var buy := _button("%dG" % int(item["price"]), _on_buy.bind(i), 20)
		buy.disabled = int(s["gold"]) < int(item["price"])
		row.add_child(buy)
		night_box.add_child(row)
	# 交易船（10分毎に在庫入替）
	ship_label = _label(_ship_head(Time.get_unix_time_from_system()), 18, Color(0.55, 0.9, 1.0))
	night_box.add_child(ship_label)
	var stock: Array = s["ship"]["stock"]
	if stock.is_empty():
		night_box.add_child(_label("（船は出払っている。次の入荷を待とう）", 16, Color(1, 1, 1, 0.4)))
	for i in stock.size():
		var entry: Dictionary = stock[i]
		var row2 := HBoxContainer.new()
		var text := ""
		if entry["type"] == "pet":
			var pet: Dictionary = KuroData.PETS[entry["pet"]]
			text = "🐾 %s — %s" % [pet["name"], pet["desc"]]
		else:
			var it: Dictionary = entry["item"]
			text = "%s %s" % [SimItems.display_name(it), SimItems.affix_text(it)]
		var lbl2 := _label(text, 18)
		lbl2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row2.add_child(lbl2)
		var buy2 := _button("%dG" % int(entry["price"]), _on_ship_buy.bind(i), 18)
		buy2.disabled = int(s["gold"]) < int(entry["price"])
		row2.add_child(buy2)
		night_box.add_child(row2)
	if not s["pets"].is_empty():
		var pet_names: Array[String] = []
		for pid in s["pets"]:
			pet_names.append(KuroData.PETS[pid]["name"])
		night_box.add_child(_label("店の住人: " + "、".join(pet_names), 16, COL_DIM))
	night_box.add_child(_label("好感度：%s" % "  ".join(_aff_summary()), 16, COL_DIM))
	var next := _button("☀ 翌朝へ", _on_next_morning, 26)
	next.custom_minimum_size = Vector2(0, 56)
	night_box.add_child(next)


func _ship_head(now: float) -> String:
	var rem := maxf(0.0, KuroData.SHIP_ROTATE_SEC - (now - float(sim.state["ship"]["rotated"])))
	return "― 🚢 交易船（入替まで %s）―" % _mmss(rem)


func _refresh_inventory() -> void:
	_clear(inv_box)
	var s := sim.state
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_label("♻ 廃材 %d" % int(s["scrap"]), 20, Color(0.7, 1.0, 0.85)))
	row.add_child(_button("一括分解", _on_bulk_salvage, 20))
	row.add_child(_button("合成 3→1", _on_synthesize, 20))
	inv_box.add_child(row)
	# 装備中サマリ
	for id in KuroData.GIRL_ORDER:
		var parts: Array[String] = []
		for slot in ["weapon", "armor", "trinket"]:
			var it: Dictionary = s["girls"][id]["equip"][slot]
			parts.append("—" if it.is_empty() else SimItems.display_name(it))
		inv_box.add_child(_label("%s: %s" % [KuroData.GIRLS[id]["name"], "  ".join(parts)], 15, COL_DIM))
	var inv: Array = s["inventory"]
	if inv.is_empty():
		inv_box.add_child(_label("倉庫は空。潜って拾おう（装備は自動装着される）", 17, Color(1, 1, 1, 0.4)))
		return
	var sorted_items := inv.duplicate()
	sorted_items.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	var shown: int = mini(sorted_items.size(), 40)
	for k in shown:
		var it: Dictionary = sorted_items[k]
		var target := _equip_target(it)
		var diff := float(it["score"]) - float(target["cur_score"])
		var badge := ("▲+%d" % int(diff)) if diff > 0.0 else ("▼%d" % int(diff))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 4)
		var name_label := _label("%s %s %s" % [SimItems.display_name(it), SimItems.affix_text(it), badge],
				16, SimItems.GRADES[int(it["grade"])]["color"])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		var eq := _button("装備", _on_equip.bind(int(it["id"])), 16)
		eq.disabled = diff <= 0.0
		line.add_child(eq)
		line.add_child(_button("分解", _on_salvage.bind(int(it["id"])), 16))
		var rr := _button("刻印", _on_reroll.bind(int(it["id"])), 16)
		rr.disabled = int(s["scrap"]) < SimItems.REROLL_COST
		line.add_child(rr)
		inv_box.add_child(line)
	if sorted_items.size() > shown:
		inv_box.add_child(_label("…ほか %d 品（スコア上位のみ表示）" % (sorted_items.size() - shown), 14, Color(1, 1, 1, 0.3)))


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
		stats_box.add_child(_button("🎁 デイリー報酬（+500G）", _on_claim_daily, 22))
	stats_box.add_child(_label("― 週間集中グラフ ―", 16, COL_DIM))
	var now := Time.get_unix_time_from_system()
	for i in range(6, -1, -1):
		var date := Time.get_datetime_string_from_unix_time(int(now) - i * 86400).substr(0, 10)
		var minutes := float(s["weekly"].get(date, 0.0))
		var bar := "▮".repeat(mini(int(minutes / 15.0) + (1 if minutes > 0.0 else 0), 20))
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
	_log("[DEBUG] %d秒 早送り" % int(seconds))


func _on_open_box() -> void:
	var r := sim.open_box()
	if r.is_empty():
		return
	_sfx("chest_open")
	var panel := PanelContainer.new()
	panel.add_child(_label("%s → %s" % [KuroData.BOX_NAMES[int(r["grade"])], r["text"]], 20,
			Color(0.7, 1.0, 0.85)))
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
	header_label.text = _header_text()


func _on_reroll(item_id: int) -> void:
	if sim.reroll_item(item_id):
		_sfx("ui_equip")
	_refresh_inventory()
	header_label.text = _header_text()


func _on_bulk_salvage() -> void:
	var r := sim.bulk_salvage()
	_sfx("ui_buy")
	_refresh_inventory()
	header_label.text = _header_text()
	inv_box.add_child(_label("一括分解: %d品 → 廃材+%d" % [int(r["count"]), int(r["dust"])], 16, Color(0.7, 1.0, 0.85)))


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


func _on_talk_start(girl: String, tier: int) -> void:
	_sfx("ui_confirm")
	talk_view.start(girl, tier)


func _on_talk_finished(girl: String, tier: int) -> void:
	sim.complete_talk(girl, tier)
	_sfx("ui_equip")
	_save(Time.get_unix_time_from_system())
	_refresh_night()
	_refresh_all()


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
		var path := "res://assets/third_party/sfx/%s.wav" % sfx_name
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
