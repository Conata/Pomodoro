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
	"map": "深層マップ — ステージ選択",
	"member": "メンバー — 編成・育成",
	"market": "市場 — 闇市と交易船",
	"management": "経営 — 今夜の仕込み",
	"renov": "経営 — 改装ツリー",
	"workshop": "工房 — Cube 装備加工",
}
# パネル毎の背景アートとアクセント（世界観の奥行き。Kit.backdrop で敷く）
const PANEL_BG_ART := {
	"map": "res://assets/generated/scene/dungeon.png",
	"member": "res://assets/generated/scene/restaurant.png",
	"market": "res://assets/generated/scene/street.png",
	"management": "res://assets/generated/scene/shop_interior.png",
	"renov": "res://assets/generated/scene/shop_interior.png",
	"workshop": "res://assets/generated/bg/interior.png",
}
const PANEL_ACCENT := {
	"map": CYAN, "member": PINK, "market": GOLD, "management": PURPLE, "renov": PURPLE, "workshop": CYAN,
}

var sim = null                 # KuroSim 参照（main.gd が bind() で渡す）
var panel := "member"          # 表示中のパネル
var _sel_girl := "mil"         # メンバー画面で選択中の子
var _work_view := "storage"     # 工房: storage / bag
var _work_item_id := -1         # 工房で選択中の装備ID
var _work_gem := "em_core"      # 工房で選択中のソケット素材
var _toast := ""
var _toast_t := 0.0
var _panel_t := 9.0            # パネル切替からの経過秒（登場トランジション用）
var _t := 0.0
var _hits: Array = []
var _ripples: Array = []   # タップ波紋（Kit.ripples）
var _tex: Dictionary = {}      # アイコン/立ち絵テクスチャのキャッシュ（path -> Texture2D|null）


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)


func bind(sim_ref) -> void:
	sim = sim_ref
	queue_redraw()


func set_panel(id: String) -> void:
	if panel != id:
		_panel_t = 0.0
	panel = id
	queue_redraw()


func set_toast(s: String) -> void:
	_toast = s
	_toast_t = 2.6
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return   # 常駐シート：閉じている間は再描画を止める
	_t += delta
	_panel_t += delta
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
			Kit.ripple_add(_ripples, p, _t)
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
	elif id.begins_with("_panel:"):
		if panel != id.substr(7):
			_panel_t = 0.0
		panel = id.substr(7)
		queue_redraw()
	elif id.begins_with("_work:"):
		_work_view = id.substr(6)
		_work_item_id = -1
		queue_redraw()
	elif id.begins_with("_selitem:"):
		_work_item_id = int(id.substr(9))
		queue_redraw()
	elif id.begins_with("_selgem:"):
		_work_gem = id.substr(8)
		queue_redraw()


func _hit(rect: Rect2, id: String) -> void:
	_hits.append({"rect": rect, "id": id})


func _panel(rect: Rect2, bg: Color, border: Color, radius := 10.0, bw := 1.5) -> void:
	Kit.panel(self, rect, bg, border, radius, bw)


## 文字。ドロップシャドウ（1,1のにじみ）ではなく暗色アウトラインで抜く。
## 反転面の暗色文字（識別色のベタ板の上）にはアウトラインを掛けない＝滲ませない。
func _txt(font: Font, pos: Vector2, s: String, size: int, col: Color, ha := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	if col.r * 0.299 + col.g * 0.587 + col.b * 0.114 > 0.3:
		draw_string_outline(font, pos, s, ha, w, size, 3, Color(0.02, 0.02, 0.04, 0.92))
	draw_string(font, pos, s, ha, w, size, col)


func _tw(font: Font, s: String, size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## アセットをキャッシュ付きで取得（無ければ null）。
func _icon(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]


## アイコンを rect 内にアスペクト維持で描く。存在すれば true（呼び出し側の文字fallback判定用）。
## plated=true で共通の暗い丸皿バックプレートを敷き、不透明な生成アイコンは地色を抜く
## （白地の正方形が画面の最明部になる事故を止める）。
func _draw_icon(path: String, rect: Rect2, modulate := Color(1, 1, 1, 1), plated := false) -> bool:
	var tex := Kit.cutout_tex(path) if plated else _icon(path)
	if tex == null:
		return false
	var ts := tex.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return false
	if plated:
		Kit.plate(self, rect.get_center(), maxf(rect.size.x, rect.size.y) * 0.62,
				Color(modulate.r, modulate.g, modulate.b, 0.5))
	var scale := minf(rect.size.x / ts.x, rect.size.y / ts.y)
	var dst := ts * scale
	var pos := rect.position + (rect.size - dst) * 0.5
	draw_texture_rect(tex, Rect2(pos, dst), false, modulate)
	return true


## 小さな操作チップ（識別色の輪郭＋本文）。斜めの板で統一する。
func _chip(font: Font, r: Rect2, label: String, col: Color, id: String) -> void:
	Kit.slab(self, r, Color(col.r * 0.22, col.g * 0.18, col.b * 0.26, 0.95), 8.0)
	Kit.slab_edge(self, r, Color(col.r, col.g, col.b, 0.85), 8.0, 1.5)
	_txt(font, Vector2(r.position.x + (r.size.x - _tw(font, label, DS.T_BODY)) * 0.5 + 4.0,
			r.position.y + r.size.y * 0.5 + 6.0), label, DS.T_BODY, DS.TEXT)
	_hit(r, id)


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
	Kit.bar(self, rect, frac, col)


func _draw() -> void:
	var sz := size
	var font := get_theme_default_font()
	_hits.clear()
	var accent: Color = PANEL_ACCENT.get(panel, PURPLE)
	if sim != null and bool(sim.state["run"]["active"]):
		# 潜航中の寄り道：背景絵は敷かず暗幕だけ＝下で戦い続けるステージが透ける
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.02, 0.05, 0.84))
	else:
		Kit.backdrop(self, sz, String(PANEL_BG_ART.get(panel, "")), accent, 0.64)

	_draw_header(font, sz)
	# パネル切替トランジション：内容が下から浮き上がり、暗幕が明ける
	var pk := clampf(_panel_t / 0.25, 0.0, 1.0)
	pk = pk * pk * (3.0 - 2.0 * pk)
	if sim != null:
		if pk < 1.0:
			draw_set_transform(Vector2(0.0, (1.0 - pk) * 16.0), 0.0, Vector2.ONE)
		match panel:
			"map": _draw_map(font, sz)
			"member": _draw_member(font, sz)
			"market": _draw_market(font, sz)
			"management": _draw_management(font, sz)
			"renov": _draw_renov(font, sz)
			"workshop": _draw_workshop(font, sz)
		if pk < 1.0:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_rect(Rect2(0, HEADER_H + 2, sz.x, sz.y - HEADER_H - FOOTER_H - 2),
					Color(0.02, 0.02, 0.05, (1.0 - pk) * 0.65))
	_draw_footer(font, sz)
	Kit.vignette(self, sz)
	_draw_toast(font, sz)
	Kit.ripples(self, _ripples, _t)


func _draw_header(font: Font, sz: Vector2) -> void:
	draw_rect(Rect2(0, 0, sz.x, HEADER_H), Color(DS.INK.r, DS.INK.g, DS.INK.b, 0.97))
	Kit.hatch(self, Rect2(0, 0, sz.x, HEADER_H), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.07), 26.0, 9.0)
	draw_rect(Rect2(0, HEADER_H - 3.0, sz.x, 3.0), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.85))
	# 戻る（潜航中＝編成の寄り道なら「潜航へ復帰」。残り時間はアンカーから実時間で計算）
	var title_x := 120.0
	if sim != null and bool(sim.state["run"]["active"]):
		var run: Dictionary = sim.state["run"]
		var remain := maxf(float(run["duration"]) \
				- (Time.get_unix_time_from_system() - float(run["anchor"])), 0.0)
		var lbl := "▼ %d:%02d 潜航へ" % [int(remain / 60.0), int(remain) % 60]
		var bw := _tw(font, lbl, DS.T_BODY) + 26
		var pulse := 0.5 + 0.5 * sin(_t * 3.0)
		_btn(font, Rect2(12, 22, bw, 40), lbl, GOLD.lerp(Color(1.0, 0.55, 0.4), pulse), "resume_dive", true, DS.T_BODY)
		title_x = 12.0 + bw + 16.0
	else:
		_btn(font, Rect2(12, 22, 104, 40), "← 店へ", PURPLE, "home", true, DS.T_BODY)
	# タイトル
	_txt(font, Vector2(title_x, 40), String(PANEL_TITLES.get(panel, "")), DS.T_SUB, DS.PAPER)
	# 日数・所持金・欠片（ラベルは小さく灰、数値は白。有彩色を増やさない）
	if sim != null:
		var s: Dictionary = sim.state
		var pairs := [["DAY", "%d" % int(s["day"])], ["金", "%d" % int(s["gold"])],
				["欠片", "%d" % int(s["shards"])]]
		var total := 0.0
		for p in pairs:
			total += _tw(font, String(p[0]), DS.T_MICRO) + 6.0 + _tw(font, String(p[1]), DS.T_SUB) + 20.0
		var hx := sz.x - 16.0 - total + 20.0
		for p in pairs:
			_txt(font, Vector2(hx, 68), String(p[0]), DS.T_MICRO, DS.TEXT_MUTE)
			hx += _tw(font, String(p[0]), DS.T_MICRO) + 6.0
			_txt(font, Vector2(hx, 68), String(p[1]), DS.T_SUB, DS.PAPER)
			hx += _tw(font, String(p[1]), DS.T_SUB) + 20.0


# ── 深層マップ（ステージ制・タスクバーヒーロー準拠）──────────────────────────

func _draw_map(font: Font, sz: Vector2) -> void:
	var y := HEADER_H + 12.0
	var diff := int(sim.state.get("difficulty", 0))

	# 難易度セレクタ（4段。前難易度で第1幕突破が解放条件）
	Kit.header(self, font, Vector2(16, y), "難易度", GOLD, sz.x - 32)
	y += 48
	var dw := (sz.x - 24 - 8 * 3) / 4.0
	for d in KuroData.DIFFICULTIES.size():
		var dd: Dictionary = KuroData.DIFFICULTIES[d]
		var r := Rect2(12 + d * (dw + 8), y, dw, 52)
		var unlocked: bool = sim.diff_unlocked(d)
		var active := d == diff
		var col: Color = dd["color"]
		if not unlocked:
			col = Color(0.4, 0.4, 0.46)
		_panel(r, Color(col.r * 0.18, col.g * 0.16, col.b * 0.2, 0.94),
				col if active else Color(col.r, col.g, col.b, 0.35), 9, 2.0 if active else 1.0)
		if active:
			Kit.spot(self, r.get_center(), dw * 0.7, col, 0.20)
		var nm := String(dd["name"])
		_txt(font, Vector2(r.position.x + (dw - _tw(font, nm, 13)) * 0.5, r.position.y + 22), nm, 13,
				TEXT if unlocked else TEXT_DIM)
		var sub := ("×%.1f" % float(dd["mult"])) if unlocked else "第%d幕突破で解放" % 1
		_txt(font, Vector2(r.position.x + (dw - _tw(font, sub, 10)) * 0.5, r.position.y + 40), sub, 10,
				col if unlocked else TEXT_DIM)
		if unlocked:
			_hit(r, "diff:%d" % d)
	y += 66

	# ステージ一覧（最前線の前後を窓表示。クリア済みは周回可）
	var cleared: int = sim.stage_cleared(diff)
	var frontier := cleared + 1
	var sel := int(sim.state.get("stage_sel", -1))
	if sel < 0 or sel > frontier:
		sel = frontier
	Kit.header(self, font, Vector2(16, y), "ステージ", CYAN, sz.x - 32, DS.T_SUB, "クリア済みは周回できる")
	y += 48
	var first := maxi(0, frontier - 3)
	if first > 0:
		_txt(font, Vector2(24, y + 14), "… %d-1 までクリア済み" % (int(first / float(KuroData.ACT_LEN)) + 1), 12, TEXT_DIM)
		y += 24
	for fl in range(first, frontier + 2):
		var r := Rect2(12, y, sz.x - 24, 52)
		var unlocked: bool = fl <= frontier
		var is_cleared := fl <= cleared
		var is_sel := fl == sel
		var biome: Dictionary = KuroData.BIOMES[fl % KuroData.BIOMES.size()]
		var bcol: Color = biome["color"]
		var row_col := CYAN if is_sel else (Color(bcol.r * 2.2, bcol.g * 2.2, bcol.b * 2.2) if unlocked else Color(0.35, 0.35, 0.4))
		_panel(r, Color(0.05, 0.06, 0.10, 0.93 if unlocked else 0.6),
				Color(row_col.r, row_col.g, row_col.b, 0.85 if is_sel else 0.4), 10, 2.0 if is_sel else 1.0)
		# 章票
		var chip := KuroData.stage_label(fl)
		_txt(font, Vector2(26, y + 32), chip, 18, TEXT if unlocked else TEXT_DIM)
		# バイオーム＋落ちる素材（店の需要から行き先を選べるように）
		draw_circle(Vector2(96, y + 26), 5.0, Color(bcol.r * 2.0, bcol.g * 2.0, bcol.b * 2.0) if unlocked else TEXT_DIM)
		_txt(font, Vector2(108, y + 22), String(biome["name"]), 13, TEXT if unlocked else TEXT_DIM)
		if unlocked:
			var ing := String(biome["ing"])
			var itag := String(KuroData.ING_NAMES.get(ing, ing))
			var ix := 112.0 + _tw(font, String(biome["name"]), 13) + 8.0
			var icol: Color = {"dry": GOLD, "meat": Color(1.0, 0.55, 0.45), "sea": CYAN}.get(ing, TEXT_DIM)
			_panel(Rect2(ix, y + 10, _tw(font, itag, 11) + 12, 18),
					Color(icol.r * 0.16, icol.g * 0.14, icol.b * 0.16, 0.9), Color(icol.r, icol.g, icol.b, 0.5), 5, 1.0)
			_txt(font, Vector2(ix + 6, y + 24), itag, 11, icol)
		# ボス（心象語）と推奨戦力
		var psyche: String = KuroData.PSYCHE[fl % KuroData.PSYCHE.size()]
		var power := int(KuroData.depth_scale(fl) * float(KuroData.DIFFICULTIES[diff]["mult"]) * 10.0)
		_txt(font, Vector2(108, y + 42), ("BOSS 人格『%s』 ・ 戦力%d" % [psyche, power]) if unlocked else "？？？", 11,
				TEXT_DIM)
		# 状態
		if not unlocked:
			_txt(font, Vector2(sz.x - 64, y + 32), "🔒", 16, TEXT_DIM)
		elif is_sel:
			_txt(font, Vector2(sz.x - 70, y + 32), "▶ 出撃", 14, CYAN)
		elif is_cleared:
			_txt(font, Vector2(sz.x - 64, y + 32), "✓", 16, GREEN)
		else:
			_txt(font, Vector2(sz.x - 78, y + 32), "最前線", 12, GOLD)
		if unlocked:
			_hit(r, "stage:%d" % fl)
		y += 58

	# 出撃ボタン（フッターの上）
	var by := sz.y - FOOTER_H - 150.0
	if y < by:
		y = by
	var sortie := Rect2(16, sz.y - FOOTER_H - 140, sz.x - 32, 56)
	var pulse := 0.5 + 0.5 * sin(_t * 2.5)
	Kit.cta(self, sortie, Color(PINK.r * 0.22, PINK.g * 0.16, PINK.b * 0.24, 0.96), PINK, pulse)
	var sl := "▶  ステージ %s に集中して潜る（25分）" % KuroData.stage_label(sel)
	_txt(font, Vector2(sortie.position.x + (sortie.size.x - _tw(font, sl, 17)) * 0.5, sortie.position.y + 35), sl, 17, TEXT)
	_hit(sortie, "sortie_pomo")
	_btn(font, Rect2(16, sz.y - FOOTER_H - 72, sz.x - 32, 44), "クイック仕入れ（80秒）", CYAN, "sortie_quick", true, 15)


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

## 素材1個の原価。闇市の「素材箱（乾・肉・海 +2ずつ）」100G ÷ 6個 から引く。
const MAT_COST := 17
const PAD := 16.0


func _draw_management(font: Font, sz: Vector2) -> void:
	var s: Dictionary = sim.state
	var m: Dictionary = s["morning"]
	var ac := PURPLE                       # この画面の支配色（他の有彩色は出さない）
	var w := sz.x - PAD * 2.0
	var top := HEADER_H
	var bot := sz.y - FOOTER_H
	# 斜めの地紋：無情報の平面を作らない
	Kit.hatch(self, Rect2(0, top, sz.x, bot - top), Color(ac.r, ac.g, ac.b, 0.055), 26.0, 9.0)

	var fc: Dictionary = sim.forecast_night()
	var taste := String(s["forecast"])
	var tcol: Color = KuroData.TASTE_COLORS.get(taste, ac)

	# ① 今夜の予報 ------------------------------------------------------- 96..192
	_mg_forecast(font, Rect2(PAD, top + 12.0, w, 96.0), taste, tcol, fc)

	# ② 店番 -------------------------------------------------------------
	Kit.header(self, font, Vector2(PAD, 216.0), "店番", ac, w + 26.0, DS.T_HEAD, "この夜の売上を決める")
	_mg_keepers(font, Rect2(PAD, 272.0, w, 128.0), m)
	# 選択店番のシナジー（識別色の帯に反転で）
	var kg: Dictionary = KuroData.GIRLS[m["keeper"]]
	var syn := Rect2(PAD, 408.0, w, 32.0)
	Kit.slab(self, syn, Color(ac.r, ac.g, ac.b, 0.92), 8.0)
	_txt(font, Vector2(syn.position.x + 20.0, syn.position.y + 23.0),
			"%s ／ %s ＝ %s" % [String(kg["name"]), String(kg["synergy"]), String(kg["synergy_desc"])],
			DS.T_BODY, DS.on(ac))

	# ③ 扉の方針 ---------------------------------------------------------
	Kit.header(self, font, Vector2(PAD, 448.0), "扉", ac, w + 26.0, DS.T_HEAD, "潜航中の扉をどう扱うか")
	_chip(font, Rect2(sz.x - PAD - 168.0, 456.0, 168.0, 32.0), "改装ツリー ▸", ac, "_panel:renov")
	var door_open: bool = String(m["door"]) == "open"
	_mg_segment(font, Rect2(PAD, 504.0, w, 56.0), "踏み込む", "見送る", door_open, "door", ac)

	# ④ 献立デッキ -------------------------------------------------------
	var menu: Array = m["menu"]
	Kit.header(self, font, Vector2(PAD, 568.0), "献立", ac, w + 26.0, DS.T_HEAD,
			"%d/%d 皿　タップで出し入れ" % [menu.size(), sim.menu_limit()])
	var settle_top := bot - 316.0                       # 906
	_mg_deck(font, Rect2(PAD, 624.0, w, settle_top - 640.0), s, menu, taste)

	# ⑤ 今夜の三行精算（この画面の結論。画面最大の文字はここ）-------------
	_mg_settle(font, Rect2(PAD, settle_top, w, 308.0), fc, door_open)


## 予報の帯：傾いた黒板に、味の一文字を反転面で叩き込む。
func _mg_forecast(font: Font, r: Rect2, taste: String, tcol: Color, fc: Dictionary) -> void:
	var ac := PURPLE
	Kit.slab(self, Rect2(r.position.x + 8.0, r.position.y + 8.0, r.size.x - 8.0, r.size.y),
			Color(ac.r, ac.g, ac.b, 0.85), 12.0)
	Kit.slab(self, r, Color(DS.INK.r, DS.INK.g, DS.INK.b, 0.97), 12.0)
	# 味の一文字（反転面）
	var g := Rect2(r.position.x + 20.0, r.position.y + 16.0, 64.0, 64.0)
	Kit.slab(self, g, tcol, 8.0)
	_txt(font, Vector2(g.position.x + (g.size.x - _tw(font, taste, DS.T_DISPLAY)) * 0.5 + 4.0,
			g.position.y + 52.0), taste, DS.T_DISPLAY, DS.INK)
	var tx := r.position.x + 104.0
	_txt(font, Vector2(tx, r.position.y + 34.0), "今夜の予報", DS.T_MICRO, Color(tcol.r, tcol.g, tcol.b, 0.95))
	_txt(font, Vector2(tx, r.position.y + 68.0), "『%s』が高く売れる" % taste, DS.T_SUB, DS.PAPER)
	# 数値は等幅で大きく（白のみ）
	var x1 := r.end.x - 232.0
	_txt(font, Vector2(x1, r.position.y + 34.0), "看板", DS.T_MICRO, DS.TEXT_2)
	_txt(font, Vector2(x1, r.position.y + 68.0), "%d" % sim.sign_total(), DS.T_SUB, DS.PAPER)
	var x2 := r.end.x - 128.0
	_txt(font, Vector2(x2, r.position.y + 34.0), "客見込み", DS.T_MICRO, DS.TEXT_2)
	_txt(font, Vector2(x2, r.position.y + 68.0), "%d人" % int(fc["customers"]), DS.T_SUB, DS.PAPER)


## 店番6枚。選択＝面の反転（識別色のベタ＋暗色の文字）。最良適性は緑＋24px＋バッジ。
func _mg_keepers(font: Font, area: Rect2, m: Dictionary) -> void:
	var ac := PURPLE
	var ids: Array = KuroData.GIRL_ORDER
	var n := ids.size()
	var gap := 8.0
	var cw := (area.size.x - gap * (n - 1)) / float(n)
	var best := 0.0
	for id in ids:
		best = maxf(best, float(KuroData.GIRLS[id]["keeper_apt"]))
	for i in n:
		var id: String = ids[i]
		var g: Dictionary = KuroData.GIRLS[id]
		var r := Rect2(area.position.x + i * (cw + gap), area.position.y, cw, area.size.y)
		var active: bool = id == m["keeper"]
		var apt := float(g["keeper_apt"])
		var is_best := apt >= best - 0.001
		if active:
			Kit.slab(self, Rect2(r.position.x + 5.0, r.position.y + 6.0, r.size.x - 5.0, r.size.y),
					Color(0, 0, 0, 0.72), 8.0)
			Kit.slab(self, r, ac, 8.0)
		else:
			Kit.slab(self, r, Color(0.03, 0.028, 0.05, 0.92), 8.0)
			Kit.slab_edge(self, r, Color(1, 1, 1, 0.16), 8.0, 1.0)
		var fg := DS.on(ac) if active else DS.TEXT
		var cx := r.position.x + cw * 0.5 + 2.0
		var iy := r.position.y + (34.0 if is_best else 26.0)
		_draw_icon("res://assets/generated/face/%s/neutral_open.png" % id,
				Rect2(cx - 22.0, iy - 22.0, 44.0, 44.0),
				Color(1, 1, 1, 1.0 if active else 0.85), true)
		var nm := String(g["name"])
		_txt(font, Vector2(cx - _tw(font, nm, DS.T_BODY) * 0.5, r.position.y + 82.0), nm, DS.T_BODY, fg)
		# 適性：最良は SUCCESS＋24px、他は本文
		var vs := DS.T_SUB if is_best else DS.T_BODY
		var vc := fg
		if is_best:
			vc = DS.on(ac) if active else DS.SUCCESS
		var vt := "%d%%" % int(apt * 100.0)
		_txt(font, Vector2(cx - _tw(font, vt, vs) * 0.5, r.position.y + 108.0), vt, vs, vc)
		# 適性の横バー（数字だけでなく量でも比べられるように）
		Kit.bar(self, Rect2(r.position.x + 10.0, r.position.y + 114.0, cw - 20.0, 6.0),
				clampf((apt - 0.6) / 0.9, 0.05, 1.0),
				(DS.INK if active else DS.SUCCESS) if is_best else
				(Color(DS.INK.r, DS.INK.g, DS.INK.b, 0.8) if active else Color(ac.r, ac.g, ac.b, 0.9)))
		# 最良適性は帯で宣言する（バッジは小さすぎて読めない）
		if is_best:
			var br := Rect2(r.position.x + 1.0, r.position.y + 1.0, cw - 2.0, 22.0)
			Kit.slab(self, br, DS.SUCCESS, 6.0)
			_txt(font, Vector2(br.position.x + (br.size.x - _tw(font, "最適", DS.T_MICRO)) * 0.5 + 3.0,
					br.position.y + 17.0), "最適", DS.T_MICRO, DS.INK)
		_hit(r, "keeper:" + id)


## 全幅の2択セグメント（選択側だけが面の反転）。
func _mg_segment(font: Font, r: Rect2, a: String, b: String, first: bool, id: String, ac: Color) -> void:
	var half := r.size.x * 0.5
	var labels := [a, b]
	for i in 2:
		var cell := Rect2(r.position.x + i * half, r.position.y, half - (4.0 if i == 0 else 0.0), r.size.y)
		var on := (i == 0) == first
		if on:
			Kit.slab(self, Rect2(cell.position.x + 5.0, cell.position.y + 6.0, cell.size.x - 5.0, cell.size.y),
					Color(0, 0, 0, 0.72), 10.0)
			Kit.slab(self, cell, ac, 10.0)
		else:
			Kit.slab(self, cell, Color(0.03, 0.028, 0.05, 0.88), 10.0)
			Kit.slab_edge(self, cell, Color(1, 1, 1, 0.14), 10.0, 1.0)
		var lbl := String(labels[i])
		var col := DS.on(ac) if on else DS.TEXT_2
		_txt(font, Vector2(cell.position.x + (cell.size.x - _tw(font, lbl, DS.T_SUB)) * 0.5,
				cell.position.y + r.size.y * 0.5 + 9.0), lbl, DS.T_SUB, col)
	_hit(r, id)


## 献立カード（縦型：丸皿アイコン＋料理名＋メタ行）。左端4pxの縦帯＝味。
func _mg_deck(font: Font, area: Rect2, s: Dictionary, menu: Array, taste: String) -> void:
	var ac := PURPLE
	var owned: Array = []
	for rid in KuroData.RECIPES:
		if int(s["recipes"].get(rid, 0)) > 0:
			owned.append(rid)
	if owned.is_empty():
		_txt(font, Vector2(area.position.x + 8.0, area.position.y + 32.0), "レシピがまだ無い。", DS.T_BODY, DS.TEXT_2)
		return
	# 品数に応じて列を決め、端数の行は幅を伸ばして埋める（右側に穴を作らない）
	var per := 2 if owned.size() <= 4 else 3
	var gap := 10.0
	var cw := (area.size.x - gap * (per - 1)) / float(per)
	var rows := int(ceil(owned.size() / float(per)))
	var ch := clampf((area.size.y - gap * (rows - 1)) / float(rows), 76.0, 140.0)
	var max_rows := maxi(int((area.size.y + gap) / (76.0 + gap)), 1)
	var shown := owned.size()
	if rows > max_rows:
		rows = max_rows
		shown = rows * per
		ch = clampf((area.size.y - gap * (rows - 1)) / float(rows), 76.0, 140.0)
	var tall := ch >= 112.0
	var total := mini(shown, owned.size())
	var last_row := int((total - 1) / per)
	var last_n := total - last_row * per
	var last_cw := (area.size.x - gap * (last_n - 1)) / float(last_n)
	for i in total:
		var rid: String = owned[i]
		var rec: Dictionary = KuroData.RECIPES[rid]
		var row := int(i / per)
		# 端数の行はカードを伸ばして幅いっぱいに（無情報の平面を残さない）
		var this_w := cw if row < last_row else last_cw
		var r := Rect2(area.position.x + (i % per) * (this_w + gap),
				area.position.y + row * (ch + gap), this_w, ch)
		var on: bool = rid in menu
		var rc: Color = KuroData.TASTE_COLORS[rec["taste"]]
		var hit: bool = String(rec["taste"]) == taste
		if on:
			Kit.slab(self, Rect2(r.position.x + 5.0, r.position.y + 6.0, r.size.x - 5.0, r.size.y),
					Color(0, 0, 0, 0.72), 8.0)
			Kit.slab(self, r, ac, 8.0)
		else:
			Kit.slab(self, r, Color(0.03, 0.028, 0.05, 0.92), 8.0)
			Kit.slab_edge(self, r, Color(1, 1, 1, 0.16), 8.0, 1.0)
		# 味は枠線ではなく左端の縦帯へ（予報と同じ色＝結びつき）
		Kit.slab(self, Rect2(r.position.x + 4.0, r.position.y + 4.0, 16.0, r.size.y - 8.0), DS.INK, 4.0)
		Kit.slab(self, Rect2(r.position.x + 7.0, r.position.y + 7.0, 10.0, r.size.y - 14.0),
				Color(rc.r, rc.g, rc.b, 1.0 if hit else 0.45), 3.0)
		var fg := DS.on(ac) if on else DS.TEXT
		var sub := DS.on(ac) if on else DS.TEXT_2
		var nm := String(rec["name"])
		var star := int(s["recipes"].get(rid, 1))
		var meta := "☆%d　%dG" % [star, int(rec["base"])]
		var path := "res://assets/generated/food/%s.png" % rid
		var mid := r.position.x + 20.0 + (this_w - 20.0) * 0.5
		if cw >= 280.0:      # 行ごとに型を変えない（列幅で一律に決める）
			# 幅広：皿を左に、名とメタを中、単価を右端に（数値は等幅で大きく）
			var iy := r.position.y + ch * 0.5
			_draw_icon(path, Rect2(r.position.x + 34.0, iy - 36.0, 72.0, 72.0),
					Color(1, 1, 1, 1.0 if on else 0.8), true)
			_txt(font, Vector2(r.position.x + 126.0, iy + 2.0), nm, DS.T_SUB, fg)
			_txt(font, Vector2(r.position.x + 126.0, iy + 28.0),
					"%s ・ ☆%d" % [String(rec["taste"]), star], DS.T_MICRO, sub)
			var pv := "%dG" % int(rec["base"])
			_txt(font, Vector2(r.end.x - _tw(font, pv, DS.T_SUB) - 20.0, iy + 10.0), pv, DS.T_SUB, fg)
		elif tall:
			_draw_icon(path, Rect2(mid - 30.0, r.position.y + 12.0, 60.0, 60.0),
					Color(1, 1, 1, 1.0 if on else 0.8), true)
			_txt(font, Vector2(mid - _tw(font, nm, DS.T_SUB) * 0.5, r.position.y + 102.0), nm, DS.T_SUB, fg)
			_txt(font, Vector2(mid - _tw(font, meta, DS.T_MICRO) * 0.5, r.position.y + 126.0),
					meta, DS.T_MICRO, sub)
		else:
			_draw_icon(path, Rect2(r.position.x + 28.0, r.position.y + (ch - 40.0) * 0.5, 40.0, 40.0),
					Color(1, 1, 1, 1.0 if on else 0.8), true)
			_txt(font, Vector2(r.position.x + 76.0, r.position.y + ch * 0.5), nm, DS.T_BODY, fg)
			_txt(font, Vector2(r.position.x + 76.0, r.position.y + ch * 0.5 + 20.0), meta, DS.T_MICRO, sub)
		if hit:
			var br := Rect2(r.end.x - 54.0, r.position.y + 4.0, 48.0, 20.0)
			Kit.slab(self, br, rc, 5.0)
			_txt(font, Vector2(br.position.x + 8.0, br.position.y + 16.0), "予報", DS.T_MICRO, DS.INK)
		_hit(r, "menu:" + rid)
	if shown < owned.size():
		_txt(font, Vector2(area.position.x + 4.0, area.end.y + 14.0),
				"…他 %d 品" % (owned.size() - shown), DS.T_MICRO, DS.TEXT_2)


## 今夜の三行精算（見込み）。この画面の結論を、画面最大の文字で置く。
func _mg_settle(font: Font, r: Rect2, fc: Dictionary, door_open: bool) -> void:
	var ac := PURPLE
	var served := int(fc["served"])
	var revenue := int(fc["gold"])
	var cost := served * MAT_COST
	var profit := revenue - cost
	# 見出しの黒板
	var head := Rect2(r.position.x, r.position.y, r.size.x, 48.0)
	Kit.slab(self, Rect2(head.position.x + 7.0, head.position.y + 6.0, head.size.x - 7.0, head.size.y),
			Color(ac.r, ac.g, ac.b, 0.5), 10.0)
	Kit.slab(self, head, Color(DS.INK.r, DS.INK.g, DS.INK.b, 0.97), 10.0)
	Kit.slab(self, Rect2(head.position.x + 8.0, head.position.y, 9.0, head.size.y), ac, 10.0)
	_txt(font, Vector2(head.position.x + 30.0, head.position.y + 34.0), "今夜の三行精算", DS.T_HEAD, DS.PAPER)
	var note := "見込み"
	_txt(font, Vector2(head.end.x - _tw(font, note, DS.T_MICRO) - 20.0, head.position.y + 32.0),
			note, DS.T_MICRO, Color(ac.r, ac.g, ac.b, 0.95))
	# 面
	var body := Rect2(r.position.x, r.position.y + 48.0, r.size.x, r.size.y - 48.0)
	Kit.slab(self, body, Color(0.03, 0.028, 0.05, 0.92), 10.0)
	Kit.hatch(self, body.grow(-6.0), Color(ac.r, ac.g, ac.b, 0.05), 22.0, 7.0)
	var x := body.position.x + 24.0
	# 一行目：客と皿
	var y1 := body.position.y + 44.0
	_txt(font, Vector2(x, y1), "客", DS.T_MICRO, DS.TEXT_2)
	_txt(font, Vector2(x + 28.0, y1), "%d" % int(fc["customers"]), DS.T_SUB, DS.PAPER)
	_txt(font, Vector2(x + 28.0 + _tw(font, "%d" % int(fc["customers"]), DS.T_SUB) + 4.0, y1), "人", DS.T_MICRO, DS.TEXT_2)
	var x2 := x + 148.0
	_txt(font, Vector2(x2, y1), "出す皿", DS.T_MICRO, DS.TEXT_2)
	_txt(font, Vector2(x2 + 76.0, y1), "%d" % served, DS.T_SUB, DS.PAPER)
	_txt(font, Vector2(x2 + 76.0 + _tw(font, "%d" % served, DS.T_SUB) + 4.0, y1), "皿", DS.T_MICRO, DS.TEXT_2)
	var x3 := body.end.x - 148.0
	_txt(font, Vector2(x3, y1), "仕込み", DS.T_MICRO, DS.TEXT_2)
	_txt(font, Vector2(x3 + 76.0, y1), "%d" % int(fc["prep"]), DS.T_SUB, DS.TEXT)
	# 二行目：売上と原価
	var y2 := y1 + 40.0
	_txt(font, Vector2(x, y2), "売上", DS.T_MICRO, DS.TEXT_2)
	_txt(font, Vector2(x + 52.0, y2), "+%dG" % revenue, DS.T_SUB, DS.PAPER)
	_txt(font, Vector2(x2, y2), "原価", DS.T_MICRO, DS.TEXT_2)
	_txt(font, Vector2(x2 + 52.0, y2), "-%dG" % cost, DS.T_SUB, DS.DANGER)
	_txt(font, Vector2(x3, y2), "単価", DS.T_MICRO, DS.TEXT_2)
	_txt(font, Vector2(x3 + 52.0, y2), "%dG" % (int(revenue / float(maxi(served, 1)))), DS.T_SUB, DS.TEXT)
	# 三行目：純益（面の反転・画面最大）
	var pcol := ac if profit >= 0 else DS.DANGER
	var slab := Rect2(body.position.x + 8.0, y2 + 22.0, body.size.x - 16.0, 88.0)
	Kit.slab(self, Rect2(slab.position.x + 7.0, slab.position.y + 7.0, slab.size.x - 7.0, slab.size.y),
			Color(0, 0, 0, 0.75), 12.0)
	Kit.slab(self, slab, pcol, 12.0)
	var pink := DS.on(pcol)
	_txt(font, Vector2(slab.position.x + 26.0, slab.position.y + 42.0), "純益", DS.T_SUB, pink)
	_txt(font, Vector2(slab.position.x + 26.0, slab.position.y + 70.0),
			"浮上したら手元に残る", DS.T_MICRO, Color(pink.r, pink.g, pink.b, 0.8))
	var pv := "%s%dG" % ["+" if profit >= 0 else "-", absi(profit)]
	_txt(font, Vector2(slab.end.x - _tw(font, pv, DS.T_DISPLAY) - 32.0, slab.position.y + 62.0),
			pv, DS.T_DISPLAY, pink)
	# 補足2行（素材切れ・扉の方針）
	var ny := slab.end.y + 26.0
	var short_n := int(fc["short"])
	var out: Array = fc["out"]
	var names: Array = []
	for ing in out:
		names.append(String(KuroData.ING_NAMES.get(ing, ing)))
	if short_n > 0:
		_txt(font, Vector2(x, ny), "▲ 素材切れで %d 皿を売り逃す（%s）" % [
				short_n, "・".join(names) if not names.is_empty() else "在庫不足"], DS.T_MICRO, DS.DANGER)
	elif not names.is_empty():
		_txt(font, Vector2(x, ny), "● 今夜で %s を使い切る。明日の仕入れが要る。" % "・".join(names),
				DS.T_MICRO, DS.TEXT_2)
	else:
		_txt(font, Vector2(x, ny), "● 素材は足りている。仕込みも客数に届く。", DS.T_MICRO, DS.SUCCESS)
	_txt(font, Vector2(x, ny + 24.0), ("● 扉：踏み込む＝箱50% / 素材+3〜5が30% / 罠20%"
			if door_open else "● 扉：見送る＝取り分は増えないが、誰も削られない"), DS.T_MICRO, DS.TEXT_2)


# ── 工房（Cube: 装備加工）────────────────────────────────────────────────────

func _draw_workshop(font: Font, sz: Vector2) -> void:
	var y := HEADER_H + 12.0
	var s: Dictionary = sim.state
	_txt(font, Vector2(16, y), "Cube: 倉庫・分解・合成・刻印・装飾をここに集約", 14, TEXT_DIM)
	y += 26

	# 資源とビュー切替
	_panel(Rect2(12, y, sz.x - 24, 58), Color(0.045, 0.06, 0.08, 0.96), Color(CYAN.r, CYAN.g, CYAN.b, 0.35), 10)
	_txt(font, Vector2(26, y + 25), "倉庫 %d/%d   バッグ %d/%d   廃材 %d" % [
			(s["storage"] as Array).size(), KuroData.STORAGE_MAX,
			(s["inventory"] as Array).size(), KuroData.BAG_MAX,
			int(s["scrap"])], 15, CYAN)
	_btn(font, Rect2(sz.x - 246, y + 12, 108, 34), "倉庫", CYAN, "_work:storage", _work_view != "storage", 14)
	_btn(font, Rect2(sz.x - 130, y + 12, 108, 34), "バッグ", GOLD, "_work:bag", _work_view != "bag", 14)
	y += 72

	# 一括操作
	if _work_view == "storage":
		_btn(font, Rect2(12, y, 110, 34), "合成", PURPLE, "synth_storage", true, 14)
		_btn(font, Rect2(132, y, 132, 34), "不要分解", PINK, "bulk_salvage_storage", true, 14)
	else:
		_btn(font, Rect2(12, y, 132, 34), "全て倉庫へ", CYAN, "bag_all", not (s["inventory"] as Array).is_empty(), 14)
		_btn(font, Rect2(154, y, 132, 34), "バッグ合成", PURPLE, "synth_bag", true, 14)
		_btn(font, Rect2(296, y, 132, 34), "不要分解", PINK, "bulk_salvage_bag", true, 14)
	y += 46

	var list: Array = s["storage"] if _work_view == "storage" else s["inventory"]
	var shown := mini(list.size(), 7)
	_txt(font, Vector2(16, y), "装備リスト（%s）" % ("倉庫" if _work_view == "storage" else "バッグ"), 15, TEXT)
	y += 16
	var row_h := 48.0
	var selected := {}
	var selected_idx := -1
	for i in shown:
		var it: Dictionary = list[i]
		var iid := int(it["id"])
		if iid == _work_item_id:
			selected = it
			selected_idx = i
		var grade := int(it["grade"])
		var col := KuroData.equip_grade_color(grade)
		var r := Rect2(12, y + i * (row_h + 6), sz.x * 0.58, row_h)
		var active := iid == _work_item_id
		_panel(r, Color(0.06, 0.065, 0.09, 0.95), col if active else Color(col.r, col.g, col.b, 0.38), 8, 2.0 if active else 1.0)
		var tx := r.position.x + 12.0
		if _draw_icon("res://assets/generated/equip/%s.png" % String(it["slot"]), Rect2(r.position.x + 8, r.position.y + 8, 32, 32), col):
			tx += 38.0
		_txt(font, Vector2(tx, r.position.y + 20), SimItems.display_name(it), 14, col)
		_txt(font, Vector2(tx, r.position.y + 39), "%s  score %.1f  %s" % [
				SimItems.GRADES[grade]["name"], float(it["score"]), SimItems.affix_text(it)], 11, TEXT_DIM)
		_hit(r, "_selitem:%d" % iid)
	if list.size() > shown:
		_txt(font, Vector2(18, y + shown * (row_h + 6) + 18), "…他 %d件" % (list.size() - shown), 12, TEXT_DIM)

	# 詳細・加工パネル
	var dx := sz.x * 0.62
	var dw := sz.x - dx - 12
	_panel(Rect2(dx, y, dw, 372), Color(0.055, 0.055, 0.085, 0.94), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.45), 12)
	if selected.is_empty() and not list.is_empty():
		selected = list[0]
		selected_idx = 0
	if selected.is_empty():
		_txt(font, Vector2(dx + 18, y + 34), "装備がありません", 18, TEXT)
		_txt(font, Vector2(dx + 18, y + 62), "潜行・交易船・箱で装備を入手すると、ここで加工できます。", 13, TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT, dw - 36)
	else:
		_draw_workshop_detail(font, Rect2(dx + 14, y + 14, dw - 28, 344), selected, selected_idx, _work_view)


func _draw_workshop_detail(font: Font, rect: Rect2, item: Dictionary, idx: int, source: String) -> void:
	var grade := int(item["grade"])
	var col := KuroData.equip_grade_color(grade)
	var y := rect.position.y
	var x := rect.position.x
	_txt(font, Vector2(x, y + 18), SimItems.display_name(item), 17, col)
	_txt(font, Vector2(x, y + 42), "%s / %s / score %.1f" % [
			SimItems.GRADES[grade]["name"], SimItems.SLOTS[item["slot"]]["name"], float(item["score"])], 13, TEXT_DIM)
	var sum := SimItems.stat_summary(item)
	_txt(font, Vector2(x, y + 76), "base %.1f   攻+%d%%  体+%d%%  速+%d%%" % [
			float(sum["base"]), int(sum["atk"]), int(sum["hp"]), int(sum["spd"])], 13, TEXT)
	_txt(font, Vector2(x, y + 98), "金+%d%%  材+%d%%  会+%d%%" % [
			int(sum["gold"]), int(sum["mat"]), int(sum["crit"])], 13, TEXT)

	y += 122
	if source == "bag":
		_btn(font, Rect2(x, y, 128, 32), "倉庫へ", CYAN, "bag_store:%d" % int(item["id"]), true, 13)
		_btn(font, Rect2(x + 138, y, 118, 32), "分解", PINK, "salvage_bag:%d" % int(item["id"]), true, 13)
		return

	_btn(font, Rect2(x, y, 110, 32), "刻印", PURPLE, "reroll_storage:%d" % int(item["id"]), int(sim.state["scrap"]) >= SimItems.REROLL_COST, 13)
	_btn(font, Rect2(x + 120, y, 110, 32), "分解", PINK, "salvage_storage:%d" % int(item["id"]), true, 13)
	y += 44

	_txt(font, Vector2(x, y), "装備先", 13, TEXT_DIM)
	y += 8
	var ids: Array = KuroData.GIRL_ORDER
	for i in mini(ids.size(), 6):
		var gid: String = ids[i]
		var gx := x + (i % 3) * 86
		var gy := y + 10 + int(i / 3) * 36
		_btn(font, Rect2(gx, gy, 76, 28), String(KuroData.GIRLS[gid]["name"]), KuroData.GIRLS[gid]["color"], "equip_storage:%d:%s" % [int(item["id"]), gid], true, 11)
	y += 90

	var cap := SimItems.socket_capacity(grade)
	var sockets: Array = item.get("sockets", [])
	_txt(font, Vector2(x, y), "装飾ソケット %d/%d" % [sockets.size(), cap], 13, TEXT_DIM)
	y += 10
	var gems: Array = KuroData.SOCKET_GEMS.keys()
	for i in mini(gems.size(), 4):
		var gem: String = gems[i]
		var active := gem == _work_gem
		_btn(font, Rect2(x + i * 78, y + 10, 70, 28), String(KuroData.SOCKET_GEMS[gem]["name"]).substr(0, 4), GOLD if active else TEXT_DIM, "_selgem:%s" % gem, not active, 10)
	y += 48
	_btn(font, Rect2(x, y, 112, 32), "嵌める", GREEN, "socket_storage:%d:%s" % [idx, _work_gem], cap > sockets.size(), 13)
	_btn(font, Rect2(x + 122, y, 112, 32), "外す", TEXT_DIM, "remove_gem:%d:0" % idx, not sockets.is_empty(), 13)


# ── 経営サブビュー（改装ツリー・マップ）──────────────────────────────────────

func _draw_renov(font: Font, sz: Vector2) -> void:
	var y := HEADER_H + 12.0
	var s: Dictionary = sim.state
	_btn(font, Rect2(12, y, 132, 34), "← 仕込みへ", PURPLE, "_panel:management", true, 14)
	y += 48
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
		if panel == "renov" and id == "management":
			active = true
		if active:
			draw_rect(Rect2(x0, fy, cw, FOOTER_H), Color(col.r, col.g, col.b, 0.10))
			draw_rect(Rect2(x0, fy, cw, 2.0), col)
			Kit.spot(self, Vector2(x0 + cw * 0.5, fy + FOOTER_H * 0.55), cw * 0.72, col, 0.22)
		var gcol := col if active else Color(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.9)
		var cx := x0 + cw * 0.5
		var glyph := String(e["icon"])
		_txt(font, Vector2(cx - _tw(font, glyph, DS.T_SUB) * 0.5, fy + 30), glyph, DS.T_SUB, gcol)
		var label := String(e["label"])
		_txt(font, Vector2(cx - _tw(font, label, DS.T_MICRO) * 0.5, fy + 50), label, DS.T_MICRO, gcol)


func _draw_toast(font: Font, sz: Vector2) -> void:
	if _toast_t <= 0.0 or _toast == "":
		return
	var a := clampf(_toast_t / 0.6, 0.0, 1.0)
	var w := _tw(font, _toast, DS.T_BODY) + 40
	var r := Rect2((sz.x - w) * 0.5, sz.y - FOOTER_H - 60, w, 40)
	Kit.slab(self, r, Color(DS.INK.r, DS.INK.g, DS.INK.b, 0.95 * a), 10.0)
	Kit.slab_edge(self, r, Color(PINK.r, PINK.g, PINK.b, 0.8 * a), 10.0, 2.0)
	_txt(font, Vector2(r.position.x + 22, r.position.y + 27), _toast, DS.T_BODY, Color(TEXT.r, TEXT.g, TEXT.b, a))
