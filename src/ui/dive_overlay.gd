class_name DiveOverlay
extends Control
## 潜航（戦闘）画面の 2D UI チロー。HD-2D の戦闘ステージ（パーティ手前・敵奥）の上に重ねる。
## 参照の戦闘画面：上＝プレイヤー情報/HP/クエスト/AUTO、下＝パーティHP/SPカード＋コマンド。
## ※プロトタイプ表示。タップで command_pressed を発火（main.gd/KuroSim 側で接続）。

signal command_pressed(id: String)

const PANEL_BG := Color(0.05, 0.055, 0.10, 0.84)
const PINK := Color(1.0, 0.36, 0.72)
const CYAN := Color(0.35, 0.92, 1.0)
const PURPLE := Color(0.66, 0.4, 1.0)
const GOLD := Color(1.0, 0.82, 0.4)
const HP_COL := Color(0.45, 0.9, 0.5)
const SP_COL := Color(0.4, 0.7, 1.0)
const TEXT := Color(0.96, 0.95, 0.98)
const TEXT_DIM := Color(0.72, 0.74, 0.82)

# ── 表示データ（main.gd / KuroSim から set_data() で差し込む。既定はプレースホルダ）──
var party: Array = [
	{"name": "ミル", "hp": 320, "mhp": 420, "sp": 80, "msp": 100},
	{"name": "ナース", "hp": 280, "mhp": 360, "sp": 60, "msp": 100},
	{"name": "キリコ", "hp": 300, "mhp": 400, "sp": 100, "msp": 100},
	{"name": "ドクター", "hp": 210, "mhp": 450, "sp": 70, "msp": 100},
]
var player_lv := "Lv.12"
var player_hp := 1.0          # 0〜1
var player_exp := 0.63        # 0〜1
var quest_text := "中央ゲートへ進む  0/1"
var speed_mult := 1           # 早送り倍率（≫ボタン表示用）
var manual_skill := false     # 手動スキルモード（DESIGN.md未決分岐の実験フラグ）
var skill_label := ""         # 次に撃てるスキル名（空＝準備中）


## main.gd / KuroSim から実データを流し込む。
func set_data(d: Dictionary) -> void:
	for k in d:
		if k in self:
			set(k, d[k])
	queue_redraw()

var _t := 0.0
var _hits: Array = []
var _log: Array = []          # 探索イベントのフィード [{msg, col, life}]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	# イベントフィードの寿命を減衰させ、古い行から消す
	for e in _log:
		e["life"] = float(e["life"]) - delta
	while not _log.is_empty() and float(_log[0]["life"]) <= 0.0:
		_log.pop_front()
	queue_redraw()


## main.gd から潜航中の sim イベントを受け取りフィードに積む（空メッセージは視覚専用なので無視）。
func add_events(events: Array) -> void:
	for e in events:
		var msg := String(e.get("msg", ""))
		if msg == "":
			continue
		_log.append({"msg": msg, "col": _kind_col(String(e.get("kind", "log"))), "life": 7.0})
	while _log.size() > 6:
		_log.pop_front()
	queue_redraw()


func _kind_col(kind: String) -> Color:
	match kind:
		"memory": return PURPLE
		"boss", "resync": return Color(1.0, 0.42, 0.46)
		"door", "door_loot", "loot", "gate": return GOLD
		"log": return TEXT_DIM
		_: return TEXT


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
			command_pressed.emit(String(h["id"]))
			accept_event()
			return


func _panel(rect: Rect2, bg: Color, border: Color, radius := 10.0, bw := 1.5) -> void:
	Kit.panel(self, rect, bg, border, radius, bw)


func _txt(font: Font, pos: Vector2, s: String, size: int, col: Color, ha := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string(font, pos + Vector2(1, 1), s, ha, w, size, Color(0, 0, 0, 0.55))
	draw_string(font, pos, s, ha, w, size, col)


func _bar(rect: Rect2, ratio: float, col: Color) -> void:
	Kit.bar(self, rect, ratio, col)


func _draw() -> void:
	var sz := size
	var font := get_theme_default_font()
	_hits.clear()

	# ===== トップバー：プレイヤー情報 =====
	var bar_h := 64.0
	_panel(Rect2(8, 8, sz.x - 16, bar_h), PANEL_BG, Color(CYAN.r, CYAN.g, CYAN.b, 0.45), 12)
	_txt(font, Vector2(22, 32), "プレイヤー", 16, TEXT)
	_txt(font, Vector2(22, 54), player_lv, 15, GOLD)
	_bar(Rect2(112, 20, 180, 12), player_hp, HP_COL)
	_txt(font, Vector2(300, 32), "%d%%" % int(player_hp * 100.0), 14, TEXT_DIM)
	_bar(Rect2(112, 40, 180, 8), player_exp, Color(0.5, 0.85, 1.0))  # EXP
	# 右：戻る（中断）／浮上（早期終了）／倍速／スキル手動⇄自動の切替
	var bx := sz.x - 20
	for it in [["戻る", "home", Color(1.0, 0.5, 0.5)], ["浮上", "finish", GOLD],
			["≫%d" % speed_mult, "fast", CYAN],
			["技:手動" if manual_skill else "技:自動", "toggle_manual", PURPLE]]:
		var lbl: String = it[0]
		var col: Color = it[2]
		var w := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 18
		bx -= w + 8
		_hit(Rect2(bx, 14, w, 44), String(it[1]))
		_panel(Rect2(bx, 14, w, 44), Color(col.r * 0.18, col.g * 0.16, col.b * 0.2, 0.92), col, 8, 1.5)
		_txt(font, Vector2(bx + 9, 42), lbl, 16, col)

	# ===== メインクエスト（左・トップ下） =====
	var qy := bar_h + 16
	_panel(Rect2(8, qy, 250, 44), Color(0.05, 0.05, 0.09, 0.7), Color(GOLD.r, GOLD.g, GOLD.b, 0.35), 8)
	_txt(font, Vector2(20, qy + 19), "メインクエスト", 13, GOLD)
	_txt(font, Vector2(20, qy + 38), quest_text, 14, TEXT)

	# ===== イベントフィード（左下・新しいものほど下、古い行は上へフェード） =====
	# 下部の高さ：手動スキル時はボタン1個ぶん高く、観賞モードはカードのみ
	var foot_h := 176.0 if manual_skill else 116.0
	var feed_bottom := sz.y - foot_h - 16.0
	var lh := 24.0
	for i in _log.size():
		var e: Dictionary = _log[_log.size() - 1 - i]   # 末尾＝最新を一番下に
		var yy := feed_bottom - i * lh
		var fade := clampf(float(e["life"]) / 1.5, 0.0, 1.0) * (1.0 - i * 0.13)
		if fade <= 0.02:
			continue
		var msg := String(e["msg"])
		var tw := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		_panel(Rect2(10, yy - 17, tw + 20, 22), Color(0.03, 0.03, 0.06, 0.62 * fade), Color(1, 1, 1, 0.06 * fade), 6, 1)
		var col: Color = e["col"]
		_txt(font, Vector2(20, yy), msg, 15, Color(col.r, col.g, col.b, fade))

	# ===== 下部：パーティカード（＋手動時のみスキルボタン） =====
	var fy := sz.y - foot_h
	_panel(Rect2(0, fy, sz.x, foot_h), Color(0.03, 0.035, 0.07, 0.92), Color(PINK.r, PINK.g, PINK.b, 0.35), 0, 1)

	# パーティカード（横4）
	var cy := fy + 12
	var cw := (sz.x - 24) / maxi(party.size(), 1)
	for i in party.size():
		var d: Dictionary = party[i]
		var cx := 12 + i * cw
		_panel(Rect2(cx + 3, cy, cw - 6, 86), Color(0.08, 0.07, 0.12, 0.92), Color(PINK.r, PINK.g, PINK.b, 0.3), 8)
		_txt(font, Vector2(cx + 12, cy + 24), String(d["name"]), 15, TEXT)
		_txt(font, Vector2(cx + 12, cy + 44), "HP", 11, TEXT_DIM)
		_bar(Rect2(cx + 36, cy + 35, cw - 50, 9), float(d["hp"]) / float(d["mhp"]), HP_COL)
		_txt(font, Vector2(cx + 12, cy + 64), "SP", 11, TEXT_DIM)
		_bar(Rect2(cx + 36, cy + 55, cw - 50, 9), float(d["sp"]) / float(d["msp"]), SP_COL)

	# スキルボタン1個（手動モードのみ・DESIGN.md未決分岐の実験）。
	# 観賞モードでは何も出さない＝オート戦闘を眺めるのが正になる。
	if manual_skill:
		var ready := skill_label != ""
		var r := Rect2(12, cy + 98, sz.x - 24, 52)
		var col := CYAN if ready else Color(0.4, 0.42, 0.5)
		var pulse := 0.5 + 0.5 * sin(_t * 3.0) if ready else 0.0
		_panel(r, Color(col.r * 0.2, col.g * 0.18, col.b * 0.22, 0.94),
				Color(col.r, col.g, col.b, 0.55 + 0.35 * pulse), 10, 2)
		var lbl := ("▶ %s" % skill_label) if ready else "スキル準備中…"
		var lw := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		_txt(font, Vector2(r.position.x + (r.size.x - lw) * 0.5, r.position.y + 33), lbl, 19,
				TEXT if ready else TEXT_DIM)
		_hit(r, "cast")


func _hit(rect: Rect2, id: String) -> void:
	_hits.append({"rect": rect, "id": id})
