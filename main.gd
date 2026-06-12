extends Control
## POMODORO HERO — メインUI。
## 状態駆動UI（DESIGN.md UX原則）: 出発設定は待機中のみ、集中中は画面を静かに。
## タイマーは Date.now() 相当（unix秒）アンカー＋固定ステップのキャッチアップで、
## タブ非アクティブでも進行が正確（壊すと製品価値が消える部分）。

enum Phase { IDLE, FOCUS, RESULT, BREAK }

const TAB_KEYS := ["party", "inventory", "runes", "market", "stats"]
const TAB_NAMES := ["編成", "倉庫", "ルーン", "市場", "統計"]

var sim: GameSim
var phase: int = Phase.IDLE
var selected_minutes := 25.0
var last_duration := 25.0
var break_until := 0.0
var save_accum := 0.0
var ui_accum := 0.0
var log_count := 0
var pending_confirm := Callable()
var result_summary := {}

var header_label: Label
var dive: DiveView
var timer_label: Label
var task_label: Label
var blessing_box: VBoxContainer
var blessing_buttons: Array[Button] = []
var hint_btn: Button
var idle_panel: VBoxContainer
var task_edit: LineEdit
var duration_group := ButtonGroup.new()
var focus_panel: VBoxContainer
var log_label: RichTextLabel
var break_panel: VBoxContainer
var break_label: Label
var return_btn: Button
var tabs: TabContainer
var party_box: VBoxContainer
var inv_box: VBoxContainer
var rune_view: RuneView
var rune_info: Label
var market_box: VBoxContainer
var stats_box: VBoxContainer
var result_panel: PanelContainer
var result_text: Label
var confirm: ConfirmationDialog
var bgm: AudioStreamPlayer
var sfx_pool: Array[AudioStreamPlayer] = []
var sfx_next := 0
var sfx_cache := {}


func _ready() -> void:
	var saved := SaveGame.load_state()
	sim = GameSim.new(saved)
	_build_ui()
	var now := Time.get_unix_time_from_system()
	var offline: Dictionary = sim.apply_offline(now)
	if not offline.is_empty():
		_log("安息の効果: 離席 %d分 → +%dG" % [int(offline["away"] / 60.0), int(offline["gold"])])
	sim.maybe_rotate_ship(now)
	if sim.state["run"]["active"]:
		phase = Phase.FOCUS  # 集中中に閉じても復帰できる
	_pump_events()
	_apply_phase()
	_refresh_all()


func _process(delta: float) -> void:
	var now := Time.get_unix_time_from_system()
	if phase == Phase.FOCUS:
		_catch_up(now)
		save_accum += delta
		if save_accum >= 20.0:
			save_accum = 0.0
			_save(now)
	elif phase == Phase.BREAK and now >= break_until:
		_log("休憩おわり。次のセッションへ！")
		_enter_idle()
	_update_clock(now)
	ui_accum += delta
	if ui_accum >= 1.0:
		ui_accum = 0.0
		header_label.text = _header_text()
		if tabs.visible and TAB_KEYS[tabs.current_tab] == "market":
			sim.maybe_rotate_ship(now)
			_refresh_market()


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
	if float(run["duration"]) <= 0.0:
		# 放置モードの追いつきは2時間で打ち切る（それ以上は安息ルーンの領分）
		target = minf(target, float(run["elapsed"]) + 7200.0)
	var steps := int((target - float(run["elapsed"])) / GameData.SIM_DT)
	steps = mini(steps, 200000)
	for i in steps:
		sim.step(GameData.SIM_DT)
		if not run["active"]:
			break
	_pump_events()


func _pump_events() -> void:
	for e in sim.drain_events():
		match String(e["kind"]):
			"run_complete":
				result_summary = e["summary"]
				_on_run_complete()
			"blessing", "blessing_done":
				_log(e["msg"])
				_update_blessing_ui()
			"level":
				_sfx("thunder")
				_log(e["msg"])
			"gate":
				_sfx("enemy_death")
				_log(e["msg"])
			"wipe":
				_sfx("damage")
				_log(e["msg"])
			_:
				_log(e["msg"])


func _on_run_complete() -> void:
	var now := Time.get_unix_time_from_system()
	var minutes := float(result_summary["minutes"])
	sim.register_completion(Time.get_date_string_from_system(), minutes)
	last_duration = minutes
	_sfx("teleport")
	_notify("完走！ %d分の集中、おつかれさま" % int(minutes))
	phase = Phase.RESULT
	result_text.text = _result_body()
	_save(now)
	_apply_phase()
	_refresh_all()


func _result_body() -> String:
	var r := result_summary
	return "タスク: %s\n集中: %d分\n獲得G: +%d\n討伐: %d体  ドロップ: %d品\n到達: 第%d層 (%dm 前進)\nストリーク: %d" % [
		r["task"], int(r["minutes"]), int(r["gold"]), int(r["kills"]),
		int(r["items"]), int(r["layer"]) + 1, int(r["dist"]), int(sim.state["streak"]),
	]


# --- フェーズ遷移 ------------------------------------------------------------


func _on_depart() -> void:
	var task := task_edit.text.strip_edges()
	if task.is_empty():
		task = "集中セッション"
	var now := Time.get_unix_time_from_system()
	_request_notify_permission()
	_sfx("ui_confirm")
	if bgm != null and not bgm.playing:
		bgm.play()  # Webの自動再生制限はユーザー操作起点なら通る
	sim.start_run(task, selected_minutes, now)
	if selected_minutes > 0.0:
		last_duration = selected_minutes
	phase = Phase.FOCUS
	_pump_events()
	_save(now)
	_apply_phase()
	_refresh_all()


func _on_return_home() -> void:
	# 放置モードの帰還＝完走扱い
	_catch_up(Time.get_unix_time_from_system())
	if sim.state["run"]["active"]:
		sim.finish_run()
		_pump_events()


func _on_abandon_confirmed() -> void:
	_sfx("ui_denied")
	sim.abandon_run()
	_pump_events()
	_enter_idle()


func _start_break() -> void:
	phase = Phase.BREAK
	break_until = Time.get_unix_time_from_system() + (600.0 if last_duration >= 50.0 else 300.0)
	_apply_phase()
	_refresh_all()


func _enter_idle() -> void:
	phase = Phase.IDLE
	_save(Time.get_unix_time_from_system())
	_apply_phase()
	_refresh_all()


func _apply_phase() -> void:
	idle_panel.visible = phase == Phase.IDLE
	focus_panel.visible = phase == Phase.FOCUS
	# 「帰還」は放置モード専用。ポモドーロは満了か撤退のみ（早期完走させない）
	return_btn.visible = float(sim.state["run"]["duration"]) <= 0.0
	break_panel.visible = phase == Phase.BREAK
	result_panel.visible = phase == Phase.RESULT
	tabs.visible = phase == Phase.IDLE or phase == Phase.BREAK
	hint_btn.visible = tabs.visible
	_update_blessing_ui()


func _update_clock(now: float) -> void:
	var run: Dictionary = sim.state["run"]
	var title := "POMODORO HERO"
	match phase:
		Phase.FOCUS:
			if float(run["duration"]) > 0.0:
				var rem := maxf(0.0, float(run["duration"]) - (now - float(run["anchor"])))
				timer_label.text = _mmss(rem)
				title = "%s ▶ %s" % [_mmss(rem), run["task"]]
			else:
				var up := now - float(run["anchor"])
				timer_label.text = "%s ▲" % _mmss(up)
				title = "放置中 ▲ %s" % _mmss(up)
			task_label.text = String(run["task"])
		Phase.BREAK:
			var rem2 := maxf(0.0, break_until - now)
			timer_label.text = _mmss(rem2)
			task_label.text = "休憩中 — 倉庫整理やルーン解放をどうぞ"
			title = "☕ %s 休憩" % _mmss(rem2)
		Phase.RESULT:
			timer_label.text = "完走！"
			task_label.text = ""
		_:
			timer_label.text = "--:--"
			task_label.text = "第%d層から出発できる" % (int(sim.state["checkpoint"]) + 1)
	DisplayServer.window_set_title(title)


func _mmss(sec: float) -> String:
	var s := int(ceil(sec))
	return "%02d:%02d" % [int(s / 60.0), s % 60]


# --- UI構築 ------------------------------------------------------------------


func _build_ui() -> void:
	var th := Theme.new()
	th.default_font_size = 24
	theme = th
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		root.add_theme_constant_override(m, 14)
	add_child(root)

	var main_box := VBoxContainer.new()
	main_box.add_theme_constant_override("separation", 10)
	root.add_child(main_box)

	header_label = _label("", 22, Color(1.0, 0.85, 0.4))
	main_box.add_child(header_label)

	dive = DiveView.new()
	dive.sim = sim
	dive.custom_minimum_size = Vector2(0, 280)
	main_box.add_child(dive)

	timer_label = _label("--:--", 64)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_box.add_child(timer_label)

	task_label = _label("", 22, Color(1, 1, 1, 0.6))
	task_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_box.add_child(task_label)

	blessing_box = VBoxContainer.new()
	blessing_box.visible = false
	blessing_box.add_child(_label("✨ 加護を選ぼう（15秒で自動選択）", 20, Color(1.0, 0.9, 0.5)))
	var bb_row := HBoxContainer.new()
	bb_row.add_theme_constant_override("separation", 8)
	for i in 3:
		var b := _button("", _on_blessing.bind(i), 20)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		blessing_buttons.append(b)
		bb_row.add_child(b)
	blessing_box.add_child(bb_row)
	main_box.add_child(blessing_box)

	hint_btn = _button("", _on_hint, 20)
	hint_btn.flat = true
	hint_btn.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0))
	main_box.add_child(hint_btn)

	_build_idle_panel(main_box)
	_build_focus_panel(main_box)
	_build_break_panel(main_box)
	_build_tabs(main_box)
	_build_result_panel()

	confirm = ConfirmationDialog.new()
	confirm.ok_button_text = "OK"
	confirm.cancel_button_text = "やめる"
	confirm.confirmed.connect(_on_confirmed)
	add_child(confirm)
	_build_audio()


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


func _build_idle_panel(parent: Control) -> void:
	idle_panel = VBoxContainer.new()
	idle_panel.add_theme_constant_override("separation", 10)
	task_edit = LineEdit.new()
	task_edit.placeholder_text = "今からやるタスクを書く"
	task_edit.add_theme_font_size_override("font_size", 26)
	idle_panel.add_child(task_edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for m in [15.0, 25.0, 50.0, 0.0]:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = duration_group
		b.text = "放置" if m == 0.0 else "%d分" % int(m)
		b.add_theme_font_size_override("font_size", 24)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_duration.bind(m))
		if m == 25.0:
			b.button_pressed = true
		row.add_child(b)
	idle_panel.add_child(row)
	var depart := _button("⚔ 出発する", _on_depart, 32)
	depart.custom_minimum_size = Vector2(0, 64)
	idle_panel.add_child(depart)
	parent.add_child(idle_panel)


func _build_focus_panel(parent: Control) -> void:
	focus_panel = VBoxContainer.new()
	focus_panel.add_theme_constant_override("separation", 8)
	focus_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label = RichTextLabel.new()
	log_label.scroll_following = true
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.custom_minimum_size = Vector2(0, 220)
	log_label.add_theme_font_size_override("normal_font_size", 20)
	focus_panel.add_child(log_label)
	var row := HBoxContainer.new()
	return_btn = _button("帰還する", _on_return_home, 20)
	return_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(return_btn)
	var ab := _button("撤退…", _on_abandon_pressed, 20)
	ab.modulate = Color(1, 0.6, 0.6)
	row.add_child(ab)
	focus_panel.add_child(row)
	parent.add_child(focus_panel)


func _build_break_panel(parent: Control) -> void:
	break_panel = VBoxContainer.new()
	break_label = _label("☕ 休憩中", 26, Color(0.6, 1.0, 0.8))
	break_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	break_panel.add_child(break_label)
	var skip := _button("休憩を終える", _enter_idle, 22)
	break_panel.add_child(skip)
	parent.add_child(break_panel)


func _build_tabs(parent: Control) -> void:
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size = Vector2(0, 420)
	party_box = _scroll_tab("編成")
	inv_box = _scroll_tab("倉庫")
	var rune_box := _scroll_tab("ルーン")
	rune_info = _label("ノードをタップして解放（隣接ノードから）", 18, Color(1, 1, 1, 0.6))
	rune_box.add_child(rune_info)
	rune_view = RuneView.new()
	rune_view.sim = sim
	rune_view.node_tapped.connect(_on_rune_tapped)
	rune_box.add_child(rune_view)
	market_box = _scroll_tab("市場")
	stats_box = _scroll_tab("統計")
	parent.add_child(tabs)


func _scroll_tab(title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	sc.add_child(box)
	tabs.add_child(sc)
	return box


func _build_result_panel() -> void:
	result_panel = PanelContainer.new()
	result_panel.set_anchors_preset(Control.PRESET_CENTER)
	result_panel.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(560, 0)
	box.add_child(_label("✅ 完走！", 40, Color(0.6, 1.0, 0.8)))
	result_text = _label("", 24)
	box.add_child(result_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var br := _button("☕ 休憩へ", _start_break, 26)
	br.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(br)
	var next := _button("続けて出発", _enter_idle, 26)
	row.add_child(next)
	box.add_child(row)
	result_panel.add_child(box)
	add_child(result_panel)


func _label(text: String, font_size: int, color := Color(1, 1, 1, 0.92)) -> Label:
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


# --- 表示更新 ----------------------------------------------------------------


func _refresh_all() -> void:
	header_label.text = _header_text()
	_refresh_party()
	_refresh_inventory()
	_refresh_market()
	_refresh_stats()
	_update_hint()
	_update_tab_dots()
	rune_view.queue_redraw()


func _header_text() -> String:
	var s := sim.state
	return "💰%d  ✨%d  📦%d  🔥%d連" % [int(s["gold"]), int(s["stardust"]), int(s["chests"]), int(s["streak"])]


func _log(msg: String) -> void:
	if msg.is_empty():
		return
	log_count += 1
	if log_count > 300:
		log_label.clear()
		log_count = 0
	log_label.append_text(msg + "\n")


func _update_blessing_ui() -> void:
	var pb: Dictionary = sim.state["pending_blessing"]
	if pb.is_empty() or phase != Phase.FOCUS:
		blessing_box.visible = false
		return
	blessing_box.visible = true
	for i in 3:
		var b: Dictionary = GameData.BLESSINGS[int(pb["opts"][i])]
		blessing_buttons[i].text = "%s\n%s" % [b["name"], b["desc"]]


func _on_blessing(i: int) -> void:
	sim.choose_blessing(i)
	_pump_events()
	_update_blessing_ui()


func _update_hint() -> void:
	var h := sim.hint()
	if h.is_empty():
		hint_btn.text = "💡 順調。次の完走を狙おう"
		hint_btn.disabled = true
	else:
		hint_btn.text = "💡 " + String(h["msg"])
		hint_btn.disabled = false
		hint_btn.set_meta("tab", h["tab"])


func _on_hint() -> void:
	if hint_btn.has_meta("tab"):
		tabs.current_tab = TAB_KEYS.find(String(hint_btn.get_meta("tab")))


func _update_tab_dots() -> void:
	var s := sim.state
	var dots := {
		"party": _has_skill_gap() or (s["heroes"].size() < sim.party_limit() and int(s["gold"]) >= sim.hire_cost()),
		"inventory": int(s["chests"]) > 0,
		"runes": _has_affordable_rune(),
		"market": false,
		"stats": int(s["daily"]["runs"]) >= 3 and not s["daily"]["claimed"],
	}
	for i in TAB_KEYS.size():
		tabs.set_tab_title(i, TAB_NAMES[i] + (" ●" if dots[TAB_KEYS[i]] else ""))


func _has_skill_gap() -> bool:
	for h in sim.state["heroes"]:
		if h["skills_eq"].size() < sim.skill_slots():
			for id in sim.known_skills(h):
				if not id in h["skills_eq"]:
					return true
	return false


func _has_affordable_rune() -> bool:
	for id in GameData.RT_NODES:
		if sim.rune_available(id) and int(sim.state["gold"]) >= int(GameData.RT_NODES[id]["cost"]):
			return true
	return false


# --- 編成タブ ----------------------------------------------------------------


func _refresh_party() -> void:
	_clear(party_box)
	var heroes: Array = sim.state["heroes"]
	for i in heroes.size():
		var h: Dictionary = heroes[i]
		var panel := PanelContainer.new()
		var box := VBoxContainer.new()
		var cls_label: String = GameData.CLASSES[h["cls"]]["name"]
		box.add_child(_label("%s（%s）Lv%d   HP %d/%d  攻 %d" % [
			h["name"], cls_label, int(h["lv"]),
			int(h["hp"]), int(sim.hero_maxhp(h)), int(sim.hero_atk(h)),
		], 22))
		var eq_parts: Array[String] = []
		for slot in ["weapon", "armor", "trinket"]:
			var it: Dictionary = h["equip"][slot]
			eq_parts.append("—" if it.is_empty() else SimItems.display_name(it))
		box.add_child(_label("装備: " + "  ".join(eq_parts), 18, Color(1, 1, 1, 0.6)))
		box.add_child(_label("スキル（枠 %d/%d）" % [h["skills_eq"].size(), sim.skill_slots()], 18, Color(1, 1, 1, 0.6)))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		for id in sim.known_skills(h):
			var def: Dictionary = GameData.SKILL_DB[id]
			var equipped: bool = id in h["skills_eq"]
			var b := _button(("✦" if equipped else "") + String(def["name"]), _on_skill_toggle.bind(i, id), 20)
			if not equipped and h["skills_eq"].size() >= sim.skill_slots():
				b.disabled = true
			row.add_child(b)
		box.add_child(row)
		panel.add_child(box)
		party_box.add_child(panel)
	if heroes.size() < sim.party_limit():
		var cost := sim.hire_cost()
		var hire := _button("⚑ ヒーローを雇う（%dG）" % cost, _on_hire, 24)
		hire.disabled = int(sim.state["gold"]) < cost
		party_box.add_child(hire)
	elif sim.party_limit() < 3:
		party_box.add_child(_label("枠を増やすには「指揮」ルーンを解放", 18, Color(1, 1, 1, 0.5)))


func _on_skill_toggle(hero_idx: int, skill_id: String) -> void:
	sim.equip_skill(hero_idx, skill_id)
	_refresh_party()
	_update_hint()
	_update_tab_dots()


func _on_hire() -> void:
	if sim.hire_hero():
		_pump_events()
		_save(Time.get_unix_time_from_system())
		_refresh_all()


# --- 倉庫タブ ----------------------------------------------------------------


func _refresh_inventory() -> void:
	_clear(inv_box)
	var s := sim.state
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var open_btn := _button("📦 箱を開ける（%d）" % int(s["chests"]), _on_open_chests, 22)
	open_btn.disabled = int(s["chests"]) <= 0
	row.add_child(open_btn)
	row.add_child(_button("一括分解", _on_bulk_salvage, 22))
	row.add_child(_button("合成 3→1", _on_synthesize, 22))
	inv_box.add_child(row)
	var inv: Array = s["inventory"]
	if inv.is_empty():
		inv_box.add_child(_label("倉庫は空。潜って拾おう", 18, Color(1, 1, 1, 0.5)))
		return
	var sorted_items := inv.duplicate()
	sorted_items.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	var shown: int = mini(sorted_items.size(), 40)
	for k in shown:
		var it: Dictionary = sorted_items[k]
		var target := _equip_target(it)
		var diff := float(it["score"]) - float(target["cur_score"])
		var badge := ("▲+%d" % int(diff)) if diff > 0.0 else ("▼%d" % int(diff))
		var grade_color: Color = GameData.GRADES[int(it["grade"])]["color"]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		var name_label := _label("%s %s  %s" % [SimItems.display_name(it), SimItems.affix_text(it), badge], 18, grade_color)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		var eq := _button("装備", _on_equip.bind(int(it["id"])), 18)
		eq.disabled = diff <= 0.0
		line.add_child(eq)
		line.add_child(_button("分解", _on_salvage.bind(int(it["id"])), 18))
		var rr := _button("刻印", _on_reroll.bind(int(it["id"])), 18)
		rr.disabled = int(s["stardust"]) < GameData.REROLL_COST
		line.add_child(rr)
		inv_box.add_child(line)
	if sorted_items.size() > shown:
		inv_box.add_child(_label("…ほか %d 品（スコア順上位のみ表示）" % (sorted_items.size() - shown), 16, Color(1, 1, 1, 0.4)))


## このアイテムを最も活かせるヒーロー（現装備スコアが最低）と、そのスコア。
func _equip_target(item: Dictionary) -> Dictionary:
	var heroes: Array = sim.state["heroes"]
	var best_idx := 0
	var best_cur := INF
	for i in heroes.size():
		var cur: Dictionary = heroes[i]["equip"][item["slot"]]
		var cur_score := 0.0 if cur.is_empty() else float(cur["score"])
		if cur_score < best_cur:
			best_cur = cur_score
			best_idx = i
	return {"idx": best_idx, "cur_score": best_cur}


func _on_open_chests() -> void:
	_sfx("chest_open")
	sim.open_chests()
	_pump_events()
	_save(Time.get_unix_time_from_system())
	_refresh_all()


func _on_bulk_salvage() -> void:
	var r := sim.bulk_salvage()
	_log("一括分解: %d品 → 星屑 +%d" % [int(r["count"]), int(r["dust"])])
	_refresh_all()


func _on_synthesize() -> void:
	var made := sim.synthesize_all()
	if made == 0:
		_log("合成できる組み合わせがない（同グレード3つ必要）")
	_pump_events()
	_refresh_all()


func _on_equip(item_id: int) -> void:
	for it in sim.state["inventory"]:
		if int(it["id"]) == item_id:
			sim.equip_from_inventory(item_id, int(_equip_target(it)["idx"]))
			_sfx("ui_equip")
			break
	_refresh_all()


func _on_salvage(item_id: int) -> void:
	var dust := sim.salvage_item(item_id)
	_log("分解 → 星屑 +%d" % dust)
	_refresh_inventory()
	header_label.text = _header_text()


func _on_reroll(item_id: int) -> void:
	sim.reroll_item(item_id)
	_pump_events()
	_refresh_inventory()
	header_label.text = _header_text()


# --- ルーンタブ --------------------------------------------------------------


func _on_rune_tapped(id: String) -> void:
	var node: Dictionary = GameData.RT_NODES[id]
	if id in sim.state["runes"]:
		rune_info.text = "%s: %s（解放済み）" % [node["name"], node["desc"]]
		return
	if not sim.rune_available(id):
		rune_info.text = "%s: 隣のノードを先に解放しよう" % node["name"]
		return
	rune_info.text = "%s: %s" % [node["name"], node["desc"]]
	_ask("ルーン「%s」を %dG で解放する？\n%s" % [node["name"], int(node["cost"]), node["desc"]],
			_on_rune_confirmed.bind(id))


func _on_rune_confirmed(id: String) -> void:
	if sim.unlock_rune(id):
		_sfx("ui_confirm")
		_pump_events()
		_save(Time.get_unix_time_from_system())
		_refresh_all()
	else:
		rune_info.text = "ゴールドが足りない…"


# --- 市場タブ ----------------------------------------------------------------


func _refresh_market() -> void:
	_clear(market_box)
	var now := Time.get_unix_time_from_system()
	var ship: Dictionary = sim.state["ship"]
	var rem := maxf(0.0, GameData.SHIP_ROTATE_SEC - (now - float(ship["rotated"])))
	market_box.add_child(_label("🚢 交易船 — 在庫入替まで %s" % _mmss(rem), 20, Color(0.6, 0.9, 1.0)))
	var stock: Array = ship["stock"]
	if stock.is_empty():
		market_box.add_child(_label("在庫なし。次の入荷を待とう", 18, Color(1, 1, 1, 0.5)))
	for i in stock.size():
		var entry: Dictionary = stock[i]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		var text := ""
		if entry["type"] == "pet":
			var pet: Dictionary = GameData.PETS[entry["pet"]]
			text = "🐾 %s — %s" % [pet["name"], pet["desc"]]
		else:
			var it: Dictionary = entry["item"]
			text = "%s %s" % [SimItems.display_name(it), SimItems.affix_text(it)]
		var lbl := _label(text, 18)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(lbl)
		var buy := _button("%dG" % int(entry["price"]), _on_buy.bind(i), 18)
		buy.disabled = int(sim.state["gold"]) < int(entry["price"])
		line.add_child(buy)
		market_box.add_child(line)
	if not sim.state["pets"].is_empty():
		var pet_names: Array[String] = []
		for pid in sim.state["pets"]:
			pet_names.append(GameData.PETS[pid]["name"])
		market_box.add_child(_label("連れているペット: " + "、".join(pet_names), 18, Color(1, 1, 1, 0.6)))


func _on_buy(idx: int) -> void:
	if sim.buy_ship(idx):
		_sfx("ui_buy")
		_pump_events()
		_save(Time.get_unix_time_from_system())
		_refresh_all()


# --- 統計タブ ----------------------------------------------------------------


func _refresh_stats() -> void:
	_clear(stats_box)
	var s := sim.state
	var total_min := float(s["stats"]["focus_min"])
	stats_box.add_child(_label("累計集中: %d時間%d分" % [int(total_min / 60.0), int(total_min) % 60], 22))
	stats_box.add_child(_label("完走: %d回   ストリーク: %d連   最深: 第%d層" % [
		int(s["stats"]["runs"]), int(s["streak"]), int(s["best_layer"]) + 1,
	], 20))
	var daily: Dictionary = s["daily"]
	var today := Time.get_date_string_from_system()
	var runs_today := int(daily["runs"]) if String(daily["date"]) == today else 0
	stats_box.add_child(_label("デイリー: 今日 %d/3 完走" % runs_today, 20))
	if runs_today >= 3 and not daily["claimed"]:
		stats_box.add_child(_button("🎁 デイリー報酬を受け取る（+500G）", _on_claim_daily, 22))
	stats_box.add_child(_label("― 週間集中グラフ ―", 18, Color(1, 1, 1, 0.5)))
	var now := Time.get_unix_time_from_system()
	for i in range(6, -1, -1):
		var date := Time.get_datetime_string_from_unix_time(int(now) - i * 86400).substr(0, 10)
		var minutes := float(s["weekly"].get(date, 0.0))
		var bar := "▮".repeat(mini(int(minutes / 15.0) + (1 if minutes > 0.0 else 0), 20))
		stats_box.add_child(_label("%s  %s %d分" % [date.substr(5), bar, int(minutes)], 18))
	# クレジット（SFXは帰属表示が必須。詳細は assets/third_party/CREDITS.md）
	stats_box.add_child(_label("― クレジット ―", 16, Color(1, 1, 1, 0.4)))
	stats_box.add_child(_label(
		"Sprites: 0x72 (CC0) / SFX: Leohpaz — Minifantasy & RPG Essentials / Music: Abstraction (CC0) / Font: DotGothic16 (OFL)",
		14, Color(1, 1, 1, 0.4)))


func _on_claim_daily() -> void:
	if sim.claim_daily():
		_pump_events()
		_refresh_all()


# --- 共通 --------------------------------------------------------------------


func _on_duration(m: float) -> void:
	selected_minutes = m


func _on_abandon_pressed() -> void:
	_ask("本当に撤退する？\nストリークがリセットされ、所持金の10%を失う", _on_abandon_confirmed)


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
