class_name HomeOverlay
extends Control
## ホーム画面の 2D UI チロー。背後の HD-2D ジオラマ（黒猫飯店）の上に重ねる。
## 参照ホーム画面のレイアウト：トップバー / 依頼 / ガチャ / サイドアイコン /
## 今日のメニュー / 探索へ出発ポータル / 下部ナビ / 吹き出し。
## ※プロトタイプ表示用（内容は代表値）。実データは main.gd 側から流し込む想定。

const PANEL_BG := Color(0.05, 0.055, 0.10, 0.82)
const PANEL_BG2 := Color(0.08, 0.06, 0.12, 0.88)
const PINK := Color(1.0, 0.36, 0.72)
const CYAN := Color(0.35, 0.92, 1.0)
const PURPLE := Color(0.66, 0.4, 1.0)
const GOLD := Color(1.0, 0.82, 0.4)
const TEXT := Color(0.96, 0.95, 0.98)
const TEXT_DIM := Color(0.72, 0.74, 0.82)

## タップされた UI 要素の ID を通知（main.gd 側で接続して実ロジックに繋ぐ）。
## 例: "depart"（探索へ出発）, "nav_chara", "gacha", "quest", "daily", "party" ...
signal action_pressed(id: String)

var _t := 0.0
var _hits: Array = []   # {rect: Rect2, id: String}（_draw で毎フレーム再構築）

# ── 表示データ（main.gd から set_data() で差し込む。既定はプレースホルダ）──
var shop_rank := "店舗ランク 1B"
var res_gems := "1,280"
var res_gold := "12,840"
var res_energy := "120/120"
var quest_body := "質屋の試練に挑む"
var quest_reward := "報酬  120石  +2,400G"
var gacha_pickup := "後悔のフユキ ↑UP"
var sales := "8,640G"
var menu := [["麻婆豆腐", "+24"], ["黒猫ラーメン", "+18"], ["焼売のジャズ", "+12"], ["メンマみそ", "+15"]]
var speeches := ["いらっしゃいませ！", "次の探索、どこへ？"]


## main.gd から実データを流し込む（キー＝上記プロパティ名）。
func set_data(d: Dictionary) -> void:
	for k in d:
		if k in self:
			set(k, d[k])
	queue_redraw()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # タップを受ける
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## クリック/タップ位置を当たり判定し、ヒットした UI の ID をシグナルで通知。
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


# ── 描画ヘルパー ──────────────────────────────────────────────
func _panel(rect: Rect2, bg: Color, border: Color, radius := 10.0, bw := 1.5) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(int(bw))
	sb.set_corner_radius_all(int(radius))
	draw_style_box(sb, rect)


func _txt(font: Font, pos: Vector2, s: String, size: int, col: Color, ha := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	# 可読性のため 1px の影を敷く
	draw_string(font, pos + Vector2(1, 1), s, ha, w, size, Color(0, 0, 0, 0.55))
	draw_string(font, pos, s, ha, w, size, col)


## ネオン発光ラベル（影＋本体）。
func _neon(font: Font, pos: Vector2, s: String, size: int, col: Color) -> void:
	draw_string(font, pos + Vector2(0, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(col.r, col.g, col.b, 0.35))
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _icon_btn(font: Font, center: Vector2, r: float, label: String, col: Color) -> void:
	_panel(Rect2(center - Vector2(r, r), Vector2(r * 2, r * 2)), PANEL_BG2, col, r, 1.5)
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	_txt(font, center + Vector2(-w * 0.5, 6), label, 16, TEXT)


func _draw() -> void:
	var sz := size
	var font := get_theme_default_font()
	_hits.clear()

	# ===== トップバー =====
	var bar_h := 66.0
	_panel(Rect2(8, 8, sz.x - 16, bar_h), PANEL_BG, Color(PINK.r, PINK.g, PINK.b, 0.5), 12)
	_neon(font, Vector2(22, 46), "黒猫飯店", 27, PINK)
	_txt(font, Vector2(168, 44), shop_rank, 16, TEXT_DIM)
	# 右側リソース
	var rx := sz.x - 26
	for item in [["石 " + res_gems, CYAN], ["金 " + res_gold, GOLD], ["活 " + res_energy, Color(0.6, 1.0, 0.9)]]:
		var s: String = item[0]
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		rx -= w + 20
		_txt(font, Vector2(rx, 44), s, 18, item[1])

	# ===== 左上：本日の依頼 =====
	var qy := bar_h + 22
	_hit(Rect2(8, qy, 248, 98), "quest")
	_panel(Rect2(8, qy, 248, 98), PANEL_BG, Color(GOLD.r, GOLD.g, GOLD.b, 0.4), 10)
	_txt(font, Vector2(22, qy + 28), "本日の依頼", 17, GOLD)
	_txt(font, Vector2(22, qy + 54), quest_body, 16, TEXT, HORIZONTAL_ALIGNMENT_LEFT, 224)
	_txt(font, Vector2(22, qy + 80), quest_reward, 14, TEXT_DIM)

	# ===== 右上：ピックアップ召喚（ガチャ） =====
	_hit(Rect2(sz.x - 218, qy, 210, 80), "gacha")
	_panel(Rect2(sz.x - 218, qy, 210, 80), PANEL_BG2, Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.55), 10)
	_txt(font, Vector2(sz.x - 204, qy + 28), "ピックアップ召喚", 15, PURPLE)
	_neon(font, Vector2(sz.x - 204, qy + 58), gacha_pickup, 16, PINK)

	# ===== 右サイド：アイコン列 =====
	var iy := qy + 128
	for it in [["日課", CYAN, "daily"], ["任務", PINK, "mission"], ["催事", GOLD, "event"]]:
		_icon_btn(font, Vector2(sz.x - 40, iy), 30, it[0], it[1])
		_hit(Rect2(sz.x - 70, iy - 30, 60, 60), String(it[2]))
		iy += 74

	# ===== 左サイド：占い / 編成 =====
	_icon_btn(font, Vector2(44, sz.y * 0.46), 32, "占い", PURPLE)
	_hit(Rect2(12, sz.y * 0.46 - 32, 64, 64), "uranai")
	_icon_btn(font, Vector2(44, sz.y * 0.46 + 80), 32, "編成", CYAN)
	_hit(Rect2(12, sz.y * 0.46 + 48, 64, 64), "party")

	# ===== 吹き出し（店番のセリフ） =====
	var sp_pos := [Vector2(sz.x * 0.34, sz.y * 0.32), Vector2(sz.x * 0.62, sz.y * 0.5)]
	for i in mini(speeches.size(), sp_pos.size()):
		if String(speeches[i]) != "":
			_speech(font, sp_pos[i], String(speeches[i]))

	# ===== 下部：今日のメニュー =====
	var my := sz.y - 256
	_panel(Rect2(8, my, 252, 168), PANEL_BG, Color(GOLD.r, GOLD.g, GOLD.b, 0.4), 10)
	_txt(font, Vector2(22, my + 28), "今日のメニュー", 17, GOLD)
	var ly := my + 56
	for m in menu:
		_txt(font, Vector2(24, ly), String(m[0]), 16, TEXT)
		_txt(font, Vector2(190, ly), String(m[1]), 16, Color(0.6, 1.0, 0.6))
		ly += 27
	_txt(font, Vector2(22, my + 160), "本日の売上  " + sales, 15, GOLD)

	# ===== 探索へ出発ポータル（右下） =====
	var pc := Vector2(sz.x - 86, sz.y - 150)
	_hit(Rect2(pc.x - 60, pc.y - 60, 120, 150), "depart")
	var pr := 52.0 + 3.0 * sin(_t * 2.0)
	draw_circle(pc, pr + 8, Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.12))
	draw_circle(pc, pr, Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.22))
	draw_arc(pc, pr, _t * 1.5, _t * 1.5 + TAU * 0.75, 40, PURPLE, 3.0)
	draw_arc(pc, pr * 0.62, -_t * 2.0, -_t * 2.0 + TAU * 0.6, 32, PINK, 2.5)
	draw_circle(pc, pr * 0.34, Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.8))
	var dw := font.get_string_size("探索へ出発", HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	_neon(font, pc + Vector2(-dw * 0.5, pr + 28), "探索へ出発", 17, PINK)

	# ===== 下部ナビ =====
	var nav_h := 70.0
	var ny := sz.y - nav_h
	_panel(Rect2(0, ny, sz.x, nav_h), Color(0.03, 0.035, 0.07, 0.96), Color(PINK.r, PINK.g, PINK.b, 0.4), 0, 1)
	var tabs := ["ホーム", "キャラ", "持ち物", "記録", "図鑑", "設定"]
	var tab_ids := ["nav_home", "nav_chara", "nav_items", "nav_log", "nav_dex", "nav_settings"]
	var tw := sz.x / tabs.size()
	for i in tabs.size():
		_hit(Rect2(i * tw, ny, tw, nav_h), tab_ids[i])
		var active := i == 0
		var c := PINK if active else TEXT_DIM
		var lw := font.get_string_size(tabs[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		if active:
			_panel(Rect2(i * tw + 8, ny + 8, tw - 16, nav_h - 16), Color(PINK.r, PINK.g, PINK.b, 0.16), Color(PINK.r, PINK.g, PINK.b, 0.55), 8)
		_txt(font, Vector2(i * tw + (tw - lw) * 0.5, ny + 44), tabs[i], 17, c)


## 角丸吹き出し（しっぽ付き）。
func _speech(font: Font, anchor: Vector2, text: String) -> void:
	var fs := 17
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pad := 10.0
	var bw := tw + pad * 2
	var bh := 30.0
	var r := Rect2(anchor.x - bw * 0.5, anchor.y - bh, bw, bh)
	_panel(r, Color(0.96, 0.96, 0.99, 0.94), Color(PINK.r, PINK.g, PINK.b, 0.7), 10)
	draw_colored_polygon(PackedVector2Array([
		Vector2(anchor.x - 6, anchor.y), Vector2(anchor.x + 6, anchor.y), Vector2(anchor.x, anchor.y + 9),
	]), Color(0.96, 0.96, 0.99, 0.94))
	_txt(font, Vector2(r.position.x + pad, anchor.y - 9), text, fs, Color(0.1, 0.08, 0.14))
