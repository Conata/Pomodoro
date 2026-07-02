class_name ResultOverlay
extends Control
## 浮上後の夜の精算リザルト。三行精算＋箱開封リビール＋住民ストーリーを提示し、
## 「店に戻る」で翌朝のホームへ。main.gd が set_data() で結果を流し込む。
## 箱アイコン（assets/generated/box/<grade>.png）をここで初投入。

signal action_pressed(id: String)

const PINK := Color(1.0, 0.36, 0.72)
const CYAN := Color(0.35, 0.92, 1.0)
const PURPLE := Color(0.66, 0.4, 1.0)
const GOLD := Color(1.0, 0.82, 0.4)
const GREEN := Color(0.45, 0.9, 0.5)
const TEXT := Color(0.96, 0.95, 0.98)
const TEXT_DIM := Color(0.75, 0.76, 0.84)
const BG := Color(0.04, 0.04, 0.07, 1.0)

# set_data で main.gd から差し込む結果データ
var day := 1
var lines: Array = []          # 三行精算
var gold := 0                  # 夜の売上
var boxes: Array = []          # [{grade, text, kind}]
var story := ""                # 住民ストーリー（特注が売れた夜）
var summary: Dictionary = {}   # {floor, kills, mats, minutes, resyncs, disconnected}
var talk: Dictionary = {}      # その夜話せる相手 {girl, tier}（無ければ空）
var daily: Dictionary = {}     # {date, runs, claimed}（ポモドーロ完走の日課）
var streak := 0                # 連続完走
var _claimed_now := false      # この画面で報酬を受け取った直後の表示用

var _t := 0.0
var _hits: Array = []
var _ripples: Array = []   # タップ波紋（Kit.ripples）
var _box_tex: Dictionary = {}  # grade -> Texture2D（キャッシュ）


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)


func set_data(d: Dictionary) -> void:
	for k in d:
		if k in self:
			set(k, d[k])
	_t = 0.0
	queue_redraw()


## 会話を消化した後に呼ぶ：会話ボタンを消す。
func clear_talk() -> void:
	talk = {}
	queue_redraw()


## デイリー報酬を受け取った後に呼ぶ：ボタンを受取済表示へ。
func claim_done() -> void:
	daily["claimed"] = true
	_claimed_now = true
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
			Kit.ripple_add(_ripples, p, _t)
			action_pressed.emit(String(h["id"]))
			accept_event()
			return


func _box_texture(grade: int) -> Texture2D:
	if not _box_tex.has(grade):
		var path := "res://assets/generated/box/%d.png" % grade
		_box_tex[grade] = load(path) if ResourceLoader.exists(path) else null
	return _box_tex[grade]


func _panel(rect: Rect2, bg: Color, border: Color, radius := 10.0, bw := 1.5) -> void:
	Kit.panel(self, rect, bg, border, radius, bw)


func _txt(font: Font, pos: Vector2, s: String, size: int, col: Color, ha := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string(font, pos + Vector2(1, 1), s, ha, w, size, Color(0, 0, 0, 0.6))
	draw_string(font, pos, s, ha, w, size, col)


## 登場演出のイージング（delay 秒後に dur 秒かけて 0→1）。
func _in(delay: float, dur := 0.3) -> float:
	var k := clampf((_t - delay) / dur, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


func _kind_col(kind: String) -> Color:
	match kind:
		"recipe": return CYAN
		"equip": return GOLD
		"shard": return PURPLE
		"invite": return PINK
		_: return GOLD


func _draw() -> void:
	var sz := size
	var font := get_theme_default_font()
	_hits.clear()
	var disconnected: bool = bool(summary.get("disconnected", false))
	Kit.backdrop(self, sz, "res://assets/generated/scene/restaurant.png",
			Color(1.0, 0.45, 0.45) if disconnected else GOLD, 0.74)
	var y := 44.0

	# ヘッダー
	var head := "Day %d ― 切断された夜" % day if disconnected else "Day %d ― 夜の精算" % day
	var hc := PINK if not disconnected else Color(1.0, 0.45, 0.45)
	var a0 := _in(0.0, 0.35)
	_txt(font, Vector2(24, y), head, 24, Color(hc.r, hc.g, hc.b, a0))
	y += 14
	# 売上はカウントアップ（0.15s 後から 0.9s かけて）
	var a1 := _in(0.12, 0.4)
	var shown_gold := int(round(float(gold) * _in(0.15, 0.9)))
	Kit.spot(self, Vector2(110, y + 8), 130.0, GOLD, 0.16 * a1)
	_txt(font, Vector2(24, y + 18), "＋%d G" % shown_gold, 30, Color(GOLD.r, GOLD.g, GOLD.b, a1))
	y += 56

	# 収穫サマリ
	if not summary.is_empty():
		var sm := "B%dF到達 ・ 撃破%d ・ 素材+%d ・ %d分" % [
			int(summary.get("floor", 0)) + 1, int(summary.get("kills", 0)),
			int(summary.get("mats", 0)), int(round(float(summary.get("minutes", 0.0))))]
		if int(summary.get("resyncs", 0)) > 0:
			sm += " ・ 再同期%d回" % int(summary["resyncs"])
		var a2 := _in(0.25, 0.35)
		_txt(font, Vector2(24, y), sm, 14, Color(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, a2))
		y += 28

	# 日課（連続完走・今日のポモドーロ・3完走でご祝儀）
	if not daily.is_empty():
		var runs := int(daily.get("runs", 0))
		var a2b := _in(0.32, 0.35)
		_txt(font, Vector2(24, y), "連続完走 %d ・ 今日のポモドーロ %d/3" % [streak, mini(runs, 3)], 14,
				Color(CYAN.r, CYAN.g, CYAN.b, a2b))
		if runs >= 3:
			if bool(daily.get("claimed", false)):
				if _claimed_now:
					_txt(font, Vector2(sz.x - 196, y), "ご祝儀 +500G 受領", 14, GOLD)
			else:
				var cb := Rect2(sz.x - 206, y - 20, 190, 30)
				_panel(cb, Color(GOLD.r * 0.22, GOLD.g * 0.18, GOLD.b * 0.1, 0.95), GOLD, 9, 1.5)
				var cl := "デイリー報酬 +500G"
				var clw := font.get_string_size(cl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
				_txt(font, Vector2(cb.position.x + (cb.size.x - clw) * 0.5, cb.position.y + 20), cl, 13, GOLD)
				_hits.append({"rect": cb, "id": "claim"})
		y += 28

	# 三行精算（パネル→1行ずつタイプライン的に）
	var a3 := _in(0.4, 0.35)
	_panel(Rect2(16, y, sz.x - 32, 30 + lines.size() * 52), Color(0.06, 0.06, 0.1, 0.92 * a3),
			Color(PINK.r, PINK.g, PINK.b, 0.4 * a3), 12)
	y += 18
	for i in lines.size():
		var la := _in(0.5 + i * 0.22, 0.3)
		_txt(font, Vector2(28, y + 14), String(lines[i]), 16, Color(TEXT.r, TEXT.g, TEXT.b, la),
				HORIZONTAL_ALIGNMENT_LEFT, sz.x - 56)
		y += 52
	y += 34

	# 箱開封リビール
	if not boxes.is_empty():
		var a4 := _in(0.95, 0.3)
		_txt(font, Vector2(24, y), "開封 ― %d個の箱" % boxes.size(), 17, Color(GOLD.r, GOLD.g, GOLD.b, a4))
		y += 14
		var shown := mini(boxes.size(), 8)
		for i in shown:
			var b: Dictionary = boxes[i]
			var reveal := clampf((_t - 1.05 - 0.12 * i) / 0.3, 0.0, 1.0)   # 三行の後に1個ずつ
			if reveal <= 0.02:
				continue
			var r := Rect2(16, y, sz.x - 32, 50)
			var grade := int(b.get("grade", 0))
			var gcol := KuroData.equip_grade_color(mini(grade + 2, 6))
			_panel(r, Color(0.06, 0.06, 0.09, 0.9 * reveal), Color(gcol.r, gcol.g, gcol.b, 0.45 * reveal), 9)
			# 箱アイコン
			var tex := _box_texture(grade)
			if tex != null:
				draw_texture_rect(tex, Rect2(r.position.x + 8, y + 7, 36, 36), false, Color(1, 1, 1, reveal))
			else:
				_txt(font, Vector2(r.position.x + 12, y + 32), KuroData.BOX_NAMES[grade], 13, Color(gcol.r, gcol.g, gcol.b, reveal))
			var kcol := _kind_col(String(b.get("kind", "")))
			_txt(font, Vector2(r.position.x + 54, y + 31), String(b.get("text", "")), 14,
					Color(kcol.r, kcol.g, kcol.b, reveal), HORIZONTAL_ALIGNMENT_LEFT, sz.x - 32 - 64)
			y += 56
		if boxes.size() > shown:
			_txt(font, Vector2(24, y), "…他 %d個" % (boxes.size() - shown), 13, TEXT_DIM)
			y += 24
		y += 6

	# 住民ストーリー（特注が売れた夜の永続バフ）
	if story != "":
		var sh := 16 + ceili(float(story.length()) / 22.0) * 24
		_panel(Rect2(16, y, sz.x - 32, sh), Color(0.09, 0.05, 0.12, 0.92), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.55), 12)
		_txt(font, Vector2(28, y + 26), story, 14, Color(0.9, 0.82, 1.0), HORIZONTAL_ALIGNMENT_LEFT, sz.x - 56)
		y += sh + 12

	# 会話ボタン（その夜の相手がいる時だけ・継続ボタンの上）
	if not talk.is_empty():
		var gid := String(talk.get("girl", ""))
		var gname := String((KuroData.GIRLS.get(gid, {}) as Dictionary).get("name", gid))
		var bk := _in(0.7, 0.4)
		var tb := Rect2((sz.x - 280) * 0.5, sz.y - 150 + (1.0 - bk) * 18.0, 280, 50)
		_panel(tb, Color(CYAN.r * 0.2, CYAN.g * 0.18, CYAN.b * 0.22, 0.96 * bk), Color(CYAN.r, CYAN.g, CYAN.b, bk), 14, 2.0)
		var tl := "▶  %s と話す" % gname
		var tlw := font.get_string_size(tl, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		_txt(font, Vector2(tb.position.x + (280 - tlw) * 0.5, tb.position.y + 32), tl, 18, Color(TEXT.r, TEXT.g, TEXT.b, bk))
		_hits.append({"rect": tb, "id": "talk"})

	Kit.vignette(self, sz)

	# 店に戻るボタン（最下部固定・ライズイン）
	var ck := _in(0.8, 0.4)
	var bw2 := 280.0
	var btn := Rect2((sz.x - bw2) * 0.5, sz.y - 84 + (1.0 - ck) * 18.0, bw2, 54)
	var pulse := 0.5 + 0.5 * sin(_t * 2.5)
	_panel(btn, Color(PINK.r * 0.22, PINK.g * 0.16, PINK.b * 0.24, 0.96 * ck),
			Color(PINK.r, PINK.g, PINK.b, (0.6 + 0.3 * pulse) * ck), 16, 2.0)
	var bl := "▶  店に戻る（翌朝へ）"
	var blw := font.get_string_size(bl, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
	_txt(font, Vector2(btn.position.x + (bw2 - blw) * 0.5, btn.position.y + 34), bl, 19, TEXT)
	_hits.append({"rect": btn, "id": "continue"})
	Kit.ripples(self, _ripples, _t)
