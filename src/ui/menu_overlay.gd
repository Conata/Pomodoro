class_name MenuOverlay
extends Control
## 各主要機能（メンバー／市場／経営／工房）のメニュー画面。
## フッターナビでパネルを切替え、ホームと同じ世界観の 2D UI を _draw で描く。
## KuroSim を参照して描画し、状態変更はすべて action_pressed(id) で main.gd へ委譲する
## （id にパラメータを ":" 区切りで載せる。例 "buy:0" / "renov:gold1" / "keeper:muu"）。

signal action_pressed(id: String)

const PINK := Color(1.0, 0.36, 0.72)
const CYAN := Color(0.35, 0.92, 1.0)
const PURPLE := Color(0.66, 0.4, 1.0)
const GOLD := Color(1.0, 0.82, 0.4)
const GREEN := Color(0.45, 0.9, 0.5)
const TEXT := Color(0.96, 0.95, 0.98)
const TEXT_DIM := Color(0.75, 0.76, 0.84)
const BG := Color(0.05, 0.05, 0.08, 1.0)

const HEADER_H := 84.0
const FOOTER_H := 58.0

# フッターナビ（home_overlay と揃える）。
const NAV := [
	{"id": "home",       "icon": "家", "label": "ホーム",   "col": CYAN},
	{"id": "member",     "icon": "仲", "label": "メンバー", "col": PINK},
	{"id": "market",     "icon": "市", "label": "市場",     "col": GOLD},
	{"id": "management", "icon": "店", "label": "経営",     "col": PURPLE},
	{"id": "workshop",   "icon": "工", "label": "工房",     "col": CYAN},
]
const PANEL_TITLES := {
	"member": "メンバー — 編成・育成",
	"market": "市場 — 闇市と交易船",
	"management": "経営 — 今夜の仕込み",
	"workshop": "工房 — 改装ツリー",
}

var sim = null                 # KuroSim 参照（main.gd が bind() で渡す）
var panel := "member"          # 表示中のパネル
var _sel_girl := "mil"         # メンバー画面で選択中の子
var _toast := ""
var _toast_t := 0.0
var _t := 0.0
var _hits: Array = []
var _tex: Dictionary = {}      # アイコン/立ち絵テクスチャのキャッシュ（path -> Texture2D|null）


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)


func bind(sim_ref) -> void:
	sim = sim_ref
	queue_redraw()


func set_panel(id: String) -> void:
	panel = id
	queue_redraw()


func set_toast(s: String) -> void:
	_toast = s
	_toast_t = 2.6
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _toast_t > 0.0:
		_toast_t -= delta
	queue_redraw()


# ── 入力・描画ヘルパー ────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	var p: Vector2
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		p = event.position
	elif event is InputEventScreenTouch and event.pressed:
		p = event.position
	else:
		return
	for h in _hits:
		if (h["rect"] as Rect2).has_point(p):
			var id := String(h["id"])
			if id.begins_with("_"):
				_local(id)            # 純UI操作（選択など）はその場で処理
			else:
				action_pressed.emit(id)
			accept_event()
			return


## 画面内だけで完結する操作（選択ハイライトなど）。
func _local(id: String) -> void:
	if id.begins_with("_selg:"):
		_sel_girl = id.substr(6)
		queue_redraw()


func _hit(rect: Rect2, id: String) -> void:
	_hits.append({"rect": rect, "id": id})


func _panel(rect: Rect2, bg: Color, border: Color, radius := 10.0, bw := 1.5) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(int(bw))
	sb.set_corner_radius_all(int(radius))
	draw_style_box(sb, rect)


func _txt(font: Font, pos: Vector2, s: String, size: int, col: Color, ha := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string(font, pos + Vector2(1, 1), s, ha, w, size, Color(0, 0, 0, 0.6))
	draw_string(font, pos, s, ha, w, size, col)


func _tw(font: Font, s: String, size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## アセットをキャッシュ付きで取得（無ければ null）。
func _icon(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]


## アイコンを rect 内にアスペクト維持で描く。存在すれば true（呼び出し側の文字fallback判定用）。
func _draw_icon(path: String, rect: Rect2, modulate := Color(1, 1, 1, 1)) -> bool:
	var tex := _icon(path)
	if tex == null:
		return false
	var ts := tex.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return false
	var scale := minf(rect.size.x / ts.x, rect.size.y / ts.y)
	var dst := ts * scale
	var pos := rect.position + (rect.size - dst) * 0.5
	draw_texture_rect(tex, Rect2(pos, dst), false, modulate)
	return true


## ラベル付きボタン。enabled=false は灰色＆非ヒット。
func _btn(font: Font, rect: Rect2, label: String, col: Color, id: String, enabled := true, size := 16) -> void:
	var c := col if enabled else Color(0.4, 0.4, 0.45)
	_panel(rect, Color(c.r * 0.18, c.g * 0.16, c.b * 0.2, 0.92), Color(c.r, c.g, c.b, 0.8 if enabled else 0.4), 9, 1.5)
	var w := _tw(font, label, size)
	_txt(font, Vector2(rect.position.x + (rect.size.x - w) * 0.5, rect.position.y + rect.size.y * 0.5 + size * 0.38),
			label, size, TEXT if enabled else TEXT_DIM)
	if enabled:
		_hit(rect, id)


func _bar(rect: Rect2, frac: float, col: Color) -> void:
	_panel(rect, Color(0, 0, 0, 0.5), Color(1, 1, 1, 0.12), 3, 1)
	var w := rect.size.x * clampf(frac, 0.0, 1.0)
	if w > 1.0:
		draw_rect(Rect2(rect.position, Vector2(w, rect.size.y)), col)


func _draw() -> void:
	var sz := size
	var font := get_theme_default_font()
	_hits.clear()
	draw_rect(Rect2(Vector2.ZERO, sz), BG)

	_draw_header(font, sz)
	if sim != null:
		match panel:
			"member": _draw_member(font, sz)
			"market": _draw_market(font, sz)
			"management": _draw_management(font, sz)
			"workshop": _draw_workshop(font, sz)
	_draw_footer(font, sz)
	_draw_toast(font, sz)


func _draw_header(font: Font, sz: Vector2) -> void:
	draw_rect(Rect2(0, 0, sz.x, HEADER_H), Color(0.02, 0.02, 0.05, 0.96))
	draw_rect(Rect2(0, HEADER_H, sz.x, 1.5), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.5))
	# 戻る
	_btn(font, Rect2(12, 22, 92, 40), "← 店へ", CYAN, "home", true, 15)
	# タイトル
	_txt(font, Vector2(120, 38), String(PANEL_TITLES.get(panel, "")), 18, TEXT)
	# 日数・所持金・欠片
	if sim != null:
		var s: Dictionary = sim.state
		var info := "Day %d    金 %d    欠片 %d" % [int(s["day"]), int(s["gold"]), int(s["shards"])]
		var w := _tw(font, info, 15)
		_txt(font, Vector2(sz.x - w - 14, 62), info, 15, GOLD)


# ── メンバー ─────────────────────────────────────────────────────────────────

func _draw_member(font: Font, sz: Vector2) -> void:
	var ids: Array = KuroData.GIRL_ORDER
	var y := HEADER_H + 12.0
	# 6人チップ
	var n := ids.size()
	var gap := 8.0
	var cw := (sz.x - 24 - gap * (n - 1)) / float(n)
	for i in n:
		var id: String = ids[i]
		var g: Dictionary = KuroData.GIRLS[id]
		var r := Rect2(12 + i * (cw + gap), y, cw, 58)
		var active := id == _sel_girl
		var col: Color = g["color"]
		_panel(r, Color(col.r * 0.16, col.g * 0.16, col.b * 0.2, 0.95),
				col if active else Color(col.r, col.g, col.b, 0.35), 9, 2.0 if active else 1.0)
		if active:
			draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 3), col)
		# 顔アイコン（無ければ名前のみ）
		var drew := _draw_icon("res://assets/generated/face/%s/neutral_open.png" % id,
				Rect2(r.position.x + (cw - 32) * 0.5, r.position.y + 4, 32, 32),
				Color(1, 1, 1, 1.0 if active else 0.8))
		var nm := String(g["name"])
		var ny := r.position.y + (49.0 if drew else 26.0)
		_txt(font, Vector2(r.position.x + (cw - _tw(font, nm, 13)) * 0.5, ny), nm, 13, TEXT if active else TEXT_DIM)
		if not drew:
			var af := "♥%d" % sim.aff(id)
			_txt(font, Vector2(r.position.x + (cw - _tw(font, af, 12)) * 0.5, r.position.y + 46), af, 12, PINK)
		_hit(r, "_selg:" + id)

	# 選択中の子の詳細カード
	var gid := _sel_girl
	var g: Dictionary = KuroData.GIRLS[gid]
	y += 70
	var card := Rect2(12, y, sz.x - 24, 118)
	_panel(card, Color(0.06, 0.06, 0.1, 0.92), Color(g["color"].r, g["color"].g, g["color"].b, 0.5), 12)
	# 立ち絵（左・無ければテキストだけ左寄せ）
	var has_portrait := _draw_icon("res://assets/portraits/%s.png" % gid, Rect2(18, y + 7, 80, 104))
	var tx := 110.0 if has_portrait else 26.0
	_txt(font, Vector2(tx, y + 28), String(g["name"]), 22, g["color"])
	_txt(font, Vector2(tx, y + 52), String(g["role"]), 13, TEXT_DIM)
	# ステータス
	_txt(font, Vector2(tx, y + 80), "攻 %d" % int(sim.girl_atk(gid)), 16, Color(1.0, 0.6, 0.45))
	_txt(font, Vector2(tx + 96, y + 80), "HP %d" % int(sim.girl_maxhp(gid)), 16, GREEN)
	# 好感度バー
	_txt(font, Vector2(tx, y + 104), "♥", 14, PINK)
	_bar(Rect2(tx + 22, y + 92, sz.x - 24 - tx - 22 - 56, 14), sim.aff(gid) / 100.0, PINK)
	_txt(font, Vector2(sz.x - 24 - 48, y + 104), "%d/100" % sim.aff(gid), 13, PINK)
	# 店番シナジー
	_txt(font, Vector2(sz.x - 24 - 210, y + 28), "店番:%s" % String(g["synergy"]), 12, GOLD)
	_txt(font, Vector2(sz.x - 24 - 210, y + 46), String(g["synergy_desc"]), 11, TEXT_DIM)

	# スキル（装備枠）
	y += 132
	var slots: int = sim.skill_slots()
	var eq: Array = sim.state["girls"][gid]["skills_eq"]
	_txt(font, Vector2(20, y), "スキル（装備 %d/%d）" % [eq.size(), slots], 15, CYAN)
	y += 12
	var known: Array = sim.known_skills(gid)
	var col2 := 0
	for sid in known:
		var def: Dictionary = KuroData.SKILL_DB[sid]
		var rx := 12 + (col2 % 2) * (sz.x - 24) * 0.5
		var ry := y + 12 + int(col2 / 2) * 44
		var r := Rect2(rx, ry, (sz.x - 24) * 0.5 - 8, 38)
		var on: bool = sid in eq
		_panel(r, Color(0.08, 0.08, 0.12, 0.95), CYAN if on else Color(0.4, 0.42, 0.5, 0.6), 8, 2.0 if on else 1.0)
		# スキルアイコン（doctor/nurse 等は未用意 → テキストのみ）
		var has_icon := _draw_icon("res://assets/generated/skill/%s.png" % sid, Rect2(rx + 6, ry + 5, 28, 28),
				Color(1, 1, 1, 1.0 if on else 0.7))
		var stx := rx + (40.0 if has_icon else 10.0)
		_txt(font, Vector2(stx, ry + 17), String(def["name"]), 14, TEXT if on else TEXT_DIM)
		_txt(font, Vector2(stx, ry + 33), "CD%.0fs  %s" % [float(def["cd"]), ("装備中" if on else "タップで装備")], 11,
				CYAN if on else TEXT_DIM)
		_hit(r, "skill:%s:%s" % [gid, sid])
		col2 += 1
	y += 12 + int((known.size() + 1) / 2) * 44 + 14

	# 育成ツリー（記憶の欠片）
	_txt(font, Vector2(20, y), "育成ツリー（記憶の欠片で解放）", 15, PURPLE)
	y += 18
	var nodes: Array = KuroData.GIRL_TREES.get(gid, [])
	var owned: Array = sim.state["girls"][gid].get("tree", [])
	for node in nodes:
		var nid := String(node["id"])
		var r := Rect2(12, y, sz.x - 24, 40)
		var is_owned: bool = nid in owned
		var avail: bool = sim.tree_available(gid, nid)
		var border := GREEN if is_owned else (PURPLE if avail else Color(0.35, 0.35, 0.4, 0.5))
		_panel(r, Color(0.07, 0.07, 0.1, 0.9), border, 8, 1.5)
		_txt(font, Vector2(24, y + 25), String(node["name"]), 14, TEXT if (is_owned or avail) else TEXT_DIM)
		var eff := _effect_label(node["effect"])
		_txt(font, Vector2(180, y + 25), eff, 12, TEXT_DIM)
		if is_owned:
			_txt(font, Vector2(sz.x - 24 - 56, y + 25), "解放済", 13, GREEN)
		else:
			var cost := int(node["cost"])
			var req := int(node.get("req_aff", 0))
			if avail:
				_btn(font, Rect2(sz.x - 24 - 96, y + 6, 90, 28), "欠片%d" % cost, PURPLE, "tree:%s:%s" % [gid, nid],
						int(sim.state["shards"]) >= cost, 13)
			else:
				var why := "♥%d必要" % req if sim.aff(gid) < req else "前提未"
				_txt(font, Vector2(sz.x - 24 - 80, y + 25), why, 12, Color(0.6, 0.6, 0.66))
		y += 46


func _effect_label(eff: Dictionary) -> String:
	if eff.has("skill"):
		return "技：%s" % String(KuroData.SKILL_DB[eff["skill"]]["name"])
	var parts: Array = []
	for k in eff:
		var nm := String({"atk": "攻", "hp": "HP", "crit": "会心"}.get(k, k))
		parts.append("%s+%d%%" % [nm, int(float(eff[k]) * 100)])
	return "・".join(parts)


# ── 市場 ─────────────────────────────────────────────────────────────────────

func _draw_market(font: Font, sz: Vector2) -> void:
	var y := HEADER_H + 16.0
	var s: Dictionary = sim.state
	# 在庫（素材アイコン＋数）
	_txt(font, Vector2(16, y + 4), "在庫", 14, TEXT_DIM)
	var ix := 64.0
	for ing in ["dry", "meat", "sea"]:
		var cnt := int(s["stock"][ing])
		var drew := _draw_icon("res://assets/generated/ing/%s.png" % ing, Rect2(ix, y - 8, 26, 26))
		_txt(font, Vector2(ix + (28.0 if drew else 0.0), y + 4),
				str(cnt) if drew else "%s%d" % [KuroData.ING_NAMES[ing], cnt], 14, TEXT)
		ix += 74.0 if drew else 88.0
	y += 28

	# 闇市（固定3品）
	_txt(font, Vector2(16, y), "闇市", 17, GOLD)
	y += 16
	for i in KuroData.MARKET.size():
		var it: Dictionary = KuroData.MARKET[i]
		var r := Rect2(12, y, sz.x - 24, 56)
		_panel(r, Color(0.07, 0.06, 0.04, 0.92), Color(GOLD.r, GOLD.g, GOLD.b, 0.4), 10)
		_txt(font, Vector2(26, y + 24), String(it["name"]), 15, TEXT)
		_txt(font, Vector2(26, y + 44), "%dG" % int(it["price"]), 14, GOLD)
		var can: bool = int(s["gold"]) >= int(it["price"])
		_btn(font, Rect2(sz.x - 24 - 100, y + 13, 94, 32), "買う", GOLD, "buy:%d" % i, can, 15)
		y += 64

	# 交易船（10分毎ローテ・装備/ペット）
	y += 8
	_txt(font, Vector2(16, y), "交易船（10分毎に入替）", 17, CYAN)
	y += 16
	var ship: Array = s["ship"]["stock"]
	if ship.is_empty():
		_txt(font, Vector2(26, y + 8), "今は停泊していない。", 14, TEXT_DIM)
		return
	for i in ship.size():
		var entry: Dictionary = ship[i]
		var r := Rect2(12, y, sz.x - 24, 56)
		var label := ""
		var sub := ""
		var col := CYAN
		if entry["type"] == "pet":
			var pet: Dictionary = KuroData.PETS[entry["pet"]]
			label = "🐾 " + String(pet["name"])
			sub = String(pet["desc"])
			col = PINK
		else:
			var item: Dictionary = entry["item"]
			var grade := int(item["grade"])
			label = SimItems.display_name(item)
			sub = "%s ・ %s" % [SimItems.GRADES[grade]["name"], SimItems.affix_text(item)]
			col = KuroData.equip_grade_color(grade)
		_panel(r, Color(0.05, 0.07, 0.09, 0.92), Color(col.r, col.g, col.b, 0.45), 10)
		# 装備はスロットアイコン（武器/防具/装飾）を添える
		var tx := 26.0
		if entry["type"] != "pet":
			if _draw_icon("res://assets/generated/equip/%s.png" % String(entry["item"]["slot"]), Rect2(18, y + 10, 36, 36), col):
				tx = 62.0
		_txt(font, Vector2(tx, y + 24), label, 15, col)
		_txt(font, Vector2(tx, y + 44), "%s   %dG" % [sub, int(entry["price"])], 13, TEXT_DIM)
		var can: bool = int(s["gold"]) >= int(entry["price"])
		_btn(font, Rect2(sz.x - 24 - 100, y + 13, 94, 32), "買う", col, "ship:%d" % i, can, 15)
		y += 64


# ── 経営 ─────────────────────────────────────────────────────────────────────

func _draw_management(font: Font, sz: Vector2) -> void:
	var y := HEADER_H + 14.0
	var s: Dictionary = sim.state
	var m: Dictionary = s["morning"]

	# 今夜の見込み
	_panel(Rect2(12, y, sz.x - 24, 56), Color(0.06, 0.06, 0.1, 0.92), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.4), 10)
	_txt(font, Vector2(24, y + 24), "今夜の予報『%s』   看板 %d   客見込み 約%d人" % [
			String(s["forecast"]), sim.sign_total(), 8 + sim.sign_total()], 14, TEXT)
	_txt(font, Vector2(24, y + 44), "店番の仕込みと献立で、浮上後の三行精算が変わる。", 12, TEXT_DIM)
	y += 70

	# 店番選択
	_txt(font, Vector2(16, y), "店番（その夜の営業性能を決める）", 15, GOLD)
	y += 16
	var ids: Array = KuroData.GIRL_ORDER
	var n := ids.size()
	var gap := 8.0
	var cw := (sz.x - 24 - gap * (n - 1)) / float(n)
	for i in n:
		var id: String = ids[i]
		var g: Dictionary = KuroData.GIRLS[id]
		var r := Rect2(12 + i * (cw + gap), y, cw, 50)
		var active: bool = id == m["keeper"]
		var col: Color = g["color"]
		_panel(r, Color(col.r * 0.16, col.g * 0.16, col.b * 0.2, 0.95),
				col if active else Color(col.r, col.g, col.b, 0.3), 8, 2.0 if active else 1.0)
		var nm := String(g["name"])
		var apt := "適性%.0f%%" % (float(g["keeper_apt"]) * 100)
		var drew := _draw_icon("res://assets/generated/face/%s/neutral_open.png" % id,
				Rect2(r.position.x + 4, r.position.y + 13, 24, 24), Color(1, 1, 1, 1.0 if active else 0.8))
		if drew:
			_txt(font, Vector2(r.position.x + 30, r.position.y + 22), nm, 12, TEXT if active else TEXT_DIM)
			_txt(font, Vector2(r.position.x + 30, r.position.y + 40), apt, 10, GOLD if active else TEXT_DIM)
		else:
			_txt(font, Vector2(r.position.x + (cw - _tw(font, nm, 13)) * 0.5, r.position.y + 22), nm, 13, TEXT if active else TEXT_DIM)
			_txt(font, Vector2(r.position.x + (cw - _tw(font, apt, 10)) * 0.5, r.position.y + 40), apt, 10, GOLD if active else TEXT_DIM)
		_hit(r, "keeper:" + id)
	# 選択店番のシナジー
	var kg: Dictionary = KuroData.GIRLS[m["keeper"]]
	y += 58
	_txt(font, Vector2(16, y), "→ %s：%s（%s）" % [String(kg["name"]), String(kg["synergy"]), String(kg["synergy_desc"])], 13, CYAN)
	y += 24

	# 扉方針
	_txt(font, Vector2(16, y), "扉の方針", 15, GOLD)
	var door_open: bool = String(m["door"]) == "open"
	_btn(font, Rect2(140, y - 18, 110, 32), "開ける" if door_open else "見送る", PURPLE if door_open else TEXT_DIM, "door", true, 14)
	y += 26

	# 献立デッキ
	var menu: Array = m["menu"]
	_txt(font, Vector2(16, y), "献立デッキ（%d/%d）— タップで出し入れ" % [menu.size(), sim.menu_limit()], 15, GOLD)
	y += 18
	var owned: Array = []
	for rid in KuroData.RECIPES:
		if int(s["recipes"].get(rid, 0)) > 0:
			owned.append(rid)
	var perrow := 3
	var rcw := (sz.x - 24 - 8 * (perrow - 1)) / float(perrow)
	for i in owned.size():
		var rid: String = owned[i]
		var rec: Dictionary = KuroData.RECIPES[rid]
		var rx := 12 + (i % perrow) * (rcw + 8)
		var ry := y + int(i / perrow) * 50
		var r := Rect2(rx, ry, rcw, 44)
		var on: bool = rid in menu
		var tcol: Color = KuroData.TASTE_COLORS[rec["taste"]]
		_panel(r, Color(0.07, 0.07, 0.1, 0.95) if not on else Color(tcol.r * 0.2, tcol.g * 0.18, tcol.b * 0.2, 0.95),
				tcol if on else Color(0.4, 0.4, 0.46, 0.6), 8, 2.0 if on else 1.0)
		var star := int(s["recipes"].get(rid, 1))
		# 料理アイコン
		var has_food := _draw_icon("res://assets/generated/food/%s.png" % rid, Rect2(rx + 6, ry + 6, 32, 32),
				Color(1, 1, 1, 1.0 if on else 0.7))
		var ftx := rx + (44.0 if has_food else 8.0)
		_txt(font, Vector2(ftx, ry + 20), String(rec["name"]), 13, TEXT if on else TEXT_DIM)
		_txt(font, Vector2(ftx, ry + 37), "%s ☆%d  %dG" % [String(rec["taste"]), star, int(rec["base"])], 10, tcol if on else TEXT_DIM)
		_hit(r, "menu:" + rid)


# ── 工房（改装ツリー・マップ）────────────────────────────────────────────────

func _draw_workshop(font: Font, sz: Vector2) -> void:
	var y := HEADER_H + 12.0
	var s: Dictionary = sim.state
	_txt(font, Vector2(16, y), "改装ツリー（ゴールドで解放・隣接から伸ばす）", 14, TEXT_DIM)
	y += 22

	# pos(x:-3..3, y:-3..3) を画面座標へ。中央を基準に格子配置。
	var nodes: Dictionary = KuroData.RENOV_NODES
	var ox := sz.x * 0.5
	var cell := 92.0
	var oy := y + 3 * cell + 30.0   # y=-3 が一番上に来るよう原点を下げる
	var map_bottom := oy + 3 * cell + 40.0

	# 接続線（prev → node）
	for nid in nodes:
		var node: Dictionary = nodes[nid]
		var np: Array = node["pos"]
		var to := Vector2(ox + float(np[0]) * cell, oy + float(np[1]) * cell)
		for p in node["prev"]:
			var pp: Array = nodes[p]["pos"]
			var fr := Vector2(ox + float(pp[0]) * cell, oy + float(pp[1]) * cell)
			var owned_link: bool = (nid in s["renov"]) and (p in s["renov"])
			draw_line(fr, to, Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.55 if owned_link else 0.18), 2.0)

	# ノード
	var rad := 30.0
	for nid in nodes:
		var node: Dictionary = nodes[nid]
		var np: Array = node["pos"]
		var c := Vector2(ox + float(np[0]) * cell, oy + float(np[1]) * cell)
		var is_owned: bool = nid in s["renov"]
		var avail: bool = sim.renov_available(nid)
		var can: bool = avail and int(s["gold"]) >= int(node["cost"])
		var col := GREEN if is_owned else (GOLD if can else (PURPLE if avail else Color(0.4, 0.4, 0.46)))
		var r := Rect2(c - Vector2(rad, rad), Vector2(rad * 2, rad * 2))
		_panel(r, Color(col.r * 0.16, col.g * 0.16, col.b * 0.2, 0.96), col, rad, 2.0 if (is_owned or avail) else 1.0)
		# 改装アイコン（無ければ名前テキスト）
		var lit := is_owned or avail
		var has_icon := _draw_icon("res://assets/generated/renov/%s.png" % nid, Rect2(c.x - 19, c.y - 22, 38, 38),
				Color(1, 1, 1, 1.0 if lit else 0.4))
		if not has_icon:
			var nm := String(node["name"])
			_txt(font, Vector2(c.x - _tw(font, nm, 11) * 0.5, c.y - 2), nm, 11, TEXT if lit else TEXT_DIM)
		if not is_owned and int(node["cost"]) > 0:
			var cs := "%d" % int(node["cost"])
			_txt(font, Vector2(c.x - _tw(font, cs, 11) * 0.5, c.y + 19), cs, 11, GOLD if can else TEXT_DIM)
		if avail:
			_hit(r, "renov:" + nid)

	# 凡例＋現在の効果サマリ
	var ly := map_bottom
	_txt(font, Vector2(16, ly), "緑=解放済 / 金=今買える / 紫=前提達成 / 灰=未開放", 12, TEXT_DIM)
	ly += 22
	var sm := "効果合計  攻+%d%% ・ HP+%d%% ・ 金+%d%% ・ 看板+%d" % [
		int(sim.renov_bonus("atk") * 100), int(sim.renov_bonus("hp") * 100),
		int(sim.renov_bonus("gold") * 100), int(sim.renov_bonus("sign"))]
	_txt(font, Vector2(16, ly), sm, 13, CYAN)


# ── フッター・トースト ────────────────────────────────────────────────────────

func _draw_footer(font: Font, sz: Vector2) -> void:
	var fy := sz.y - FOOTER_H
	draw_rect(Rect2(0, fy, sz.x, FOOTER_H), Color(0.03, 0.03, 0.06, 0.97))
	draw_rect(Rect2(0, fy, sz.x, 1.5), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.55))
	var n := NAV.size()
	var cw := sz.x / float(n)
	for i in n:
		var e: Dictionary = NAV[i]
		var x0 := cw * i
		var id := String(e["id"])
		_hit(Rect2(x0, fy, cw, FOOTER_H), id)
		var col: Color = e["col"]
		var active := id == panel
		if active:
			draw_rect(Rect2(x0, fy, cw, FOOTER_H), Color(col.r, col.g, col.b, 0.10))
			draw_rect(Rect2(x0, fy, cw, 2.0), col)
		var gcol := col if active else Color(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.9)
		var cx := x0 + cw * 0.5
		var glyph := String(e["icon"])
		_txt(font, Vector2(cx - _tw(font, glyph, 22) * 0.5, fy + 28), glyph, 22, gcol)
		var label := String(e["label"])
		_txt(font, Vector2(cx - _tw(font, label, 11) * 0.5, fy + 48), label, 11, gcol)


func _draw_toast(font: Font, sz: Vector2) -> void:
	if _toast_t <= 0.0 or _toast == "":
		return
	var a := clampf(_toast_t / 0.6, 0.0, 1.0)
	var w := _tw(font, _toast, 15) + 36
	var r := Rect2((sz.x - w) * 0.5, sz.y - FOOTER_H - 56, w, 38)
	_panel(r, Color(0.08, 0.06, 0.12, 0.92 * a), Color(PINK.r, PINK.g, PINK.b, 0.7 * a), 10)
	_txt(font, Vector2(r.position.x + 18, r.position.y + 24), _toast, 15, Color(TEXT.r, TEXT.g, TEXT.b, a))
