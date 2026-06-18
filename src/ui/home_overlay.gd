class_name HomeOverlay
extends Control
## ホーム画面（黒猫飯店）の 2D UI チロー。シネマティック構成：
##   上＝最小トップバー（≡/猫/設定/ベル）、右＝探索入口ポータル、
##   下＝VN風セリフ窓、最下部＝HD-2D フィールド帯の枠＋コンパス。
## 背後に DinerStage（店内ジオラマ）＋ FieldStrip（パーティ/敵のピクセル帯）が見える。
## タップで action_pressed(id) を発火（main.gd 側で画面遷移/ロジックに接続）。

signal action_pressed(id: String)

const PANEL_BG := Color(0.04, 0.04, 0.07, 0.78)
const PINK := Color(1.0, 0.36, 0.72)
const CYAN := Color(0.35, 0.92, 1.0)
const PURPLE := Color(0.66, 0.4, 1.0)
const GOLD := Color(1.0, 0.82, 0.4)
const TEXT := Color(0.96, 0.95, 0.98)
const TEXT_DIM := Color(0.75, 0.76, 0.84)

const STRIP_H := 168.0   # 最下部 HD-2D フィールド帯の高さ（FieldStrip と一致させる）

# ── 表示データ（main.gd から set_data()）──
var speaker := "フユキ"
var line := "「後悔が騒いでるね。奥に潜って、静かにしてあげる。」"
var day_gold := "Day 1   金 120"

var _t := 0.0
var _hits: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)


func set_data(d: Dictionary) -> void:
	for k in d:
		if k in self:
			set(k, d[k])
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


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
			action_pressed.emit(String(h["id"]))
			accept_event()
			return


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


func _icon(font: Font, c: Vector2, r: float, label: String, col: Color, id: String) -> void:
	_panel(Rect2(c - Vector2(r, r), Vector2(r * 2, r * 2)), Color(0.05, 0.05, 0.09, 0.85), col, r, 1.5)
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	_txt(font, c + Vector2(-w * 0.5, 6), label, 15, TEXT)
	_hit(Rect2(c - Vector2(r, r), Vector2(r * 2, r * 2)), id)


func _draw() -> void:
	var sz := size
	var font := get_theme_default_font()
	_hits.clear()

	# ===== トップバー（薄い帯＋アイコン） =====
	var tb := Rect2(0, 0, sz.x, 60)
	draw_rect(tb, Color(0.02, 0.02, 0.05, 0.55))
	draw_rect(Rect2(0, 60, sz.x, 1.5), Color(PINK.r, PINK.g, PINK.b, 0.4))
	_icon(font, Vector2(34, 30), 21, "≡", PINK, "menu")
	_txt(font, Vector2(66, 38), day_gold, 16, GOLD)  # 日数・所持金（実データ）
	# 右：猫 / 設定 / ベル
	_icon(font, Vector2(sz.x - 34, 30), 21, "猫", PINK, "cat")
	_icon(font, Vector2(sz.x - 86, 30), 21, "設定", CYAN, "settings")
	_icon(font, Vector2(sz.x - 138, 30), 21, "報", GOLD, "bell")

	# ===== 探索入口ポータル（右端・縦書き＋紫の渦） =====
	var pc := Vector2(sz.x - 56, sz.y * 0.47)
	_hit(Rect2(pc.x - 52, pc.y - 56, 104, 170), "depart")
	# うっすら枠
	_panel(Rect2(pc.x - 50, pc.y - 54, 100, 168), Color(0.05, 0.03, 0.10, 0.45), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.5), 14)
	var pr := 38.0 + 3.0 * sin(_t * 2.2)
	draw_circle(pc, pr + 8, Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.12))
	draw_arc(pc, pr, _t * 1.6, _t * 1.6 + TAU * 0.78, 36, PURPLE, 3.0)
	draw_arc(pc, pr * 0.6, -_t * 2.2, -_t * 2.2 + TAU * 0.62, 28, PINK, 2.5)
	draw_circle(pc, pr * 0.34, Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.85))
	# 縦書き「仕入れへ」（深層へ食材を獲りに行く＝仕入れ）
	var vy := pc.y + pr + 16.0
	for ch in "仕入れへ":
		_txt(font, Vector2(pc.x - 9, vy), ch, 17, PINK)
		vy += 22.0

	# ===== ポモドーロ集中ボタン（主役CTA・VN窓の上） =====
	var vh := 96.0
	var vy0 := sz.y - STRIP_H - vh - 8
	var cta := Rect2(sz.x * 0.5 - 145, vy0 - 70, 290, 56)
	_hit(cta, "pomodoro")
	var pulse := 0.5 + 0.5 * sin(_t * 2.5)
	_panel(cta, Color(PINK.r * 0.22, PINK.g * 0.16, PINK.b * 0.24, 0.96),
			Color(PINK.r, PINK.g, PINK.b, 0.6 + 0.3 * pulse), 16, 2.0)
	var ct := "▶  集中する（25分）"
	var ctw := font.get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
	_txt(font, Vector2(cta.position.x + (cta.size.x - ctw) * 0.5, cta.position.y + 36), ct, 19, TEXT)

	# ===== VN セリフ窓（フィールド帯の上） =====
	_panel(Rect2(16, vy0, sz.x - 32, vh), Color(0.04, 0.04, 0.08, 0.86), Color(PINK.r, PINK.g, PINK.b, 0.5), 12)
	# 名前タグ
	_panel(Rect2(28, vy0 - 14, 96, 30), Color(0.10, 0.05, 0.10, 0.95), Color(PINK.r, PINK.g, PINK.b, 0.7), 8)
	_txt(font, Vector2(40, vy0 + 8), speaker, 17, PINK)
	# ボイスアイコン
	draw_circle(Vector2(134, vy0 + 1), 8, Color(CYAN.r, CYAN.g, CYAN.b, 0.85))
	# 本文
	_txt(font, Vector2(34, vy0 + 46), line, 17, TEXT, HORIZONTAL_ALIGNMENT_LEFT, sz.x - 70)
	# 送りインジケータ
	if fmod(_t, 1.0) < 0.6:
		_txt(font, Vector2(sz.x - 44, vy0 + vh - 14), "▼", 14, PINK)

	# ===== 最下部：HD-2D フィールド帯の枠＋コンパス =====
	var fy := sz.y - STRIP_H
	# 上辺のネオンライン
	draw_rect(Rect2(0, fy, sz.x, 2), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.6))
	_hit(Rect2(0, fy, sz.x, STRIP_H), "field")
	# 左：味方／右：敵 のラベル
	_txt(font, Vector2(18, fy + 22), "PARTY", 13, CYAN)
	var ew := font.get_string_size("ENEMY", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_txt(font, Vector2(sz.x - 18 - ew, fy + 22), "ENEMY", 13, Color(1.0, 0.4, 0.85))
	# コンパス（中央下）
	var cc := Vector2(sz.x * 0.5, sz.y - 16)
	draw_arc(cc, 14, 0, TAU, 28, Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.7), 2.0)
	draw_line(cc + Vector2(0, -10), cc + Vector2(0, 10), Color(PINK.r, PINK.g, PINK.b, 0.8), 2.0)
	# 進行バー
	_panel(Rect2(sz.x * 0.5 + 26, sz.y - 22, sz.x * 0.5 - 50, 8), Color(0, 0, 0, 0.5), Color(1, 1, 1, 0.15), 3, 1)
	draw_rect(Rect2(sz.x * 0.5 + 26, sz.y - 22, (sz.x * 0.5 - 50) * 0.3, 8), PURPLE)
