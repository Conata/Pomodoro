class_name MemberView
extends Control
## メンバー画面の【ネイティブ Container 版・試作】。
## 旧 menu_overlay の _draw 手描き（絶対座標）に対する比較用プロトタイプ。
## 単体で開ける（member_test.tscn）。本流（menu_screen）には未接続。
##
## 狙い＝「あるべき1画面」の実証：
##  - 下部コンテンツを TabContainer + SIZE_EXPAND_FILL で組み、余白を自動吸収
##    ＝座標計算ゼロでワンスクリーン・無スクロール・全高フィット。
##  - 縦積みだったステ/スキル/育成を【セグメント（タブ）切替】に畳む。
##  - 装飾は DS.theme()（＝ネオンの唯一の真実）を継承して native コントロールへ。

var sim                       # KuroSim（bind で注入。無ければ単体起動用に生成）
var _sel := "mil"             # 選択中の子
var _tab := 0                 # 選択中セグメント（0=ステ/1=スキル/2=育成）
var _ui: Control = null       # ルート（再構築時に丸ごと差し替える）


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = DS.theme()                       # native コントロールへ DS の装飾を継承
	if sim == null:
		sim = KuroSim.new()                  # 単体起動：フレッシュな状態で見られる
	var bg := ColorRect.new()
	bg.color = DS.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_build()


## menu へ組み込む際はここに実 sim を渡す。
func bind(sim_ref) -> void:
	sim = sim_ref
	if is_inside_tree():
		_build()


# ── 構築（操作のたびに丸ごと作り直す＝座標を一切手で置かない） ─────────────────

func _build() -> void:
	if _ui != null and is_instance_valid(_ui):
		_ui.queue_free()
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 14)
	add_child(margin)
	_ui = margin

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	col.add_child(_header())
	col.add_child(_selector())
	col.add_child(_detail())
	var tabs := _tabs()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL   # ★余白を全部吸う＝1画面フィット
	col.add_child(tabs)
	col.add_child(_footer())


# ── ヘッダー（誰の画面か＋資源） ───────────────────────────────────────────────

func _header() -> Control:
	var h := HBoxContainer.new()
	var title := _lbl("メンバー — 編成・育成", DS.T_SUB, DS.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(title)
	var s: Dictionary = sim.state
	var res := _lbl("Day %d   金 %d   欠片 %d" % [int(s["day"]), int(s["gold"]), int(s["shards"])],
			DS.T_BODY, DS.GOLD)
	res.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(res)
	return h


# ── 子セレクタ（6人・横並びで均等。タップで切替） ─────────────────────────────

func _selector() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	for id in KuroData.GIRL_ORDER:
		var g: Dictionary = KuroData.GIRLS[id]
		var b := Button.new()
		b.text = "%s\n♥%d" % [String(g["name"]), sim.aff(id)]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 52)
		b.add_theme_font_size_override("font_size", DS.T_MICRO)
		if id == _sel:
			b.add_theme_color_override("font_color", g["color"])
			b.add_theme_stylebox_override("normal", DS.card_accent(g["color"]))
		b.pressed.connect(_select.bind(id))
		h.add_child(b)
	return h


# ── 詳細カード（名前・立ち絵・主要ステ・好感度） ───────────────────────────────

func _detail() -> Control:
	var gid := _sel
	var g: Dictionary = KuroData.GIRLS[gid]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", DS.card_accent(g["color"]))
	var inner := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		inner.add_theme_constant_override(m, 12)
	card.add_child(inner)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	inner.add_child(row)

	# 立ち絵ゾーン（本物が来たら res://assets/portraits/<id>.png を差すだけ。今は色面）
	var port := Panel.new()
	port.custom_minimum_size = Vector2(96, 132)
	port.add_theme_stylebox_override("panel", DS.card_accent(g["color"]))
	row.add_child(port)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	row.add_child(info)
	info.add_child(_lbl(String(g["name"]), DS.T_HEAD, g["color"]))
	info.add_child(_lbl(String(g["role"]), DS.T_MICRO, DS.TEXT_2))

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 16)
	stats.add_child(_lbl("攻 %d" % int(sim.girl_atk(gid)), DS.T_BODY, Color(1.0, 0.6, 0.45)))
	stats.add_child(_lbl("HP %d" % int(sim.girl_maxhp(gid)), DS.T_BODY, DS.HP))
	info.add_child(stats)

	var aff := HBoxContainer.new()
	aff.add_theme_constant_override("separation", 8)
	aff.add_child(_lbl("好感度", DS.T_MICRO, DS.TEXT_2))
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = sim.aff(gid)
	bar.custom_minimum_size = Vector2(0, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.modulate = DS.PINK
	aff.add_child(bar)
	aff.add_child(_lbl("%d/100" % sim.aff(gid), DS.T_MICRO, DS.PINK))
	info.add_child(aff)
	return card


# ── セグメント（ステ／スキル／育成）。縦積みをタブに畳む ───────────────────────

func _tabs() -> TabContainer:
	var tc := TabContainer.new()
	var status := _tab_status()
	status.name = "ステータス"
	tc.add_child(status)
	var skills := _tab_skills()
	skills.name = "スキル"
	tc.add_child(skills)
	var tree := _tab_tree()
	tree.name = "育成"
	tc.add_child(tree)
	tc.current_tab = clampi(_tab, 0, 2)
	tc.tab_changed.connect(func(idx: int): _tab = idx)
	return tc


func _tab_status() -> Control:
	var gid := _sel
	var g: Dictionary = KuroData.GIRLS[gid]
	var v := _pad_vbox()
	v.add_child(_kv("好みの味", String(g["fav"])))
	v.add_child(_kv("店番シナジー", "%s（%s）" % [String(g["synergy"]), String(g["synergy_desc"])]))
	v.add_child(_kv("店番適性", "%d%%" % int(float(g["keeper_apt"]) * 100)))
	var note := _lbl("好感度が上がるほど攻撃・HP が伸びる（×1+好感度/200）。", DS.T_MICRO, DS.TEXT_2)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	return v


func _tab_skills() -> Control:
	var gid := _sel
	var v := _pad_vbox()
	var eq: Array = sim.state["girls"][gid]["skills_eq"]
	v.add_child(_lbl("装備中 %d/%d ・ タップで着脱" % [eq.size(), sim.skill_slots()], DS.T_MICRO, DS.CYAN))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(grid)
	for sid in sim.known_skills(gid):
		var def: Dictionary = KuroData.SKILL_DB[sid]
		var on: bool = sid in eq
		var b := Button.new()
		b.text = "%s %s\nCD%.0fs" % [("▣" if on else "□"), String(def["name"]), float(def["cd"])]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 52)
		b.add_theme_font_size_override("font_size", DS.T_MICRO)
		b.add_theme_color_override("font_color", DS.CYAN if on else DS.TEXT_2)
		b.pressed.connect(_toggle_skill.bind(sid))
		grid.add_child(b)
	return v


func _tab_tree() -> Control:
	var gid := _sel
	var v := _pad_vbox()
	v.add_child(_lbl("記憶の欠片で解放（直線・前提順）", DS.T_MICRO, DS.PURPLE))
	var owned: Array = sim.state["girls"][gid].get("tree", [])
	for node in KuroData.GIRL_TREES.get(gid, []):
		var nid := String(node["id"])
		var is_owned: bool = nid in owned
		var avail: bool = sim.tree_available(gid, nid)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_col := DS.TEXT if (is_owned or avail) else DS.TEXT_MUTE
		var nm := _lbl(String(node["name"]), DS.T_BODY, name_col)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		row.add_child(_lbl(_eff_label(node["effect"]), DS.T_MICRO, DS.TEXT_2))
		if is_owned:
			row.add_child(_lbl("解放済", DS.T_MICRO, DS.HP))
		elif avail:
			var cost := int(node["cost"])
			var b := Button.new()
			b.text = "欠片%d" % cost
			b.disabled = int(sim.state["shards"]) < cost
			b.add_theme_font_size_override("font_size", DS.T_MICRO)
			b.pressed.connect(_unlock.bind(nid))
			row.add_child(b)
		else:
			var req := int(node.get("req_aff", 0))
			var why := "♥%d必要" % req if sim.aff(gid) < req else "前提未"
			row.add_child(_lbl(why, DS.T_MICRO, DS.TEXT_MUTE))
		v.add_child(row)
	return v


# ── フッターナビ（試作では押下をログのみ） ────────────────────────────────────

func _footer() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	for e in [["家", "home"], ["仲", "member"], ["市", "market"], ["店", "management"], ["工", "workshop"]]:
		var b := Button.new()
		b.text = String(e[0])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 44)
		if String(e[1]) == "member":
			b.add_theme_color_override("font_color", DS.PINK)
		b.pressed.connect(func(): print("[member_view] nav: ", e[1]))
		h.add_child(b)
	return h


# ── 操作（sim を駆動 → 丸ごと再構築） ─────────────────────────────────────────

func _select(id: String) -> void:
	_sel = id
	_build()


func _toggle_skill(sid: String) -> void:
	sim.equip_skill(_sel, sid)
	sim.drain_events()
	_build()


func _unlock(nid: String) -> void:
	sim.tree_unlock(_sel, nid)
	sim.drain_events()
	_build()


# ── 小物 ──────────────────────────────────────────────────────────────────────

func _lbl(s: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


## 「項目：値」の1行（左ラベル＝副文色／右値＝本文色）。
func _kv(k: String, val: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var key := _lbl(k, DS.T_MICRO, DS.TEXT_2)
	key.custom_minimum_size = Vector2(120, 0)
	h.add_child(key)
	var v := _lbl(val, DS.T_BODY, DS.TEXT)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(v)
	return h


## 内側に余白を持つ VBox（タブの中身の地）。
func _pad_vbox() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		v.add_theme_constant_override(m, 4)
	return v


func _eff_label(eff: Dictionary) -> String:
	if eff.has("skill"):
		return "技：%s" % String(KuroData.SKILL_DB[eff["skill"]]["name"])
	var parts: Array = []
	for k in eff:
		var nm := String({"atk": "攻", "hp": "HP", "crit": "会心"}.get(k, k))
		parts.append("%s+%d%%" % [nm, int(float(eff[k]) * 100)])
	return "・".join(parts)
