class_name NightOverlay
extends Control
## 夜営業シアター — デイブザダイバーの夜の鮨屋にあたる報酬劇場。
## 浮上→精算のあいだに、close_day の配膳記録（script）をカウンター越しに上演する：
## 影の客が入店→着席→今日の素材の皿が出る→支払い→退店。
## タップ給仕（待ち客をタップ）で即配膳＋チップ。放置でも自動で完走し、
## スキップも常時可能——5分休憩の楽しみであって、義務にはしない。

signal finished(tips: int)   # 劇場の終了（チップ合計を持ち帰る）
signal tip_tapped            # タップ給仕の瞬間（SFX用）

const PINK := Color(1.0, 0.36, 0.72)
const CYAN := Color(0.35, 0.92, 1.0)
const GOLD := Color(1.0, 0.82, 0.4)
const TEXT := Color(0.96, 0.95, 0.98)
const TEXT_DIM := Color(0.72, 0.74, 0.82)
const BG_ART := "res://assets/generated/bg/interior.png"

const COUNTER_Y := 0.62      # カウンター天面（画面比）
const SEAT_XS := [0.15, 0.32, 0.50, 0.68, 0.85]
const CUST_H := 58.0         # 影の客の身長
const KEEPER_H := 96.0       # 店番ちびの描画高
const AUTO_SERVE := 2.4      # 着席から自動配膳までの秒数（この間はタップ給仕可）
const TURNAWAY_MAX := 3      # 素材切れで帰す客の演出数上限

# 影の客のマフラー色（ネオンノワールの差し色）
const SCARF := [Color(0.95, 0.4, 0.5), Color(0.4, 0.8, 0.95), Color(0.95, 0.75, 0.35),
		Color(0.7, 0.5, 0.95), Color(0.45, 0.9, 0.6), Color(0.9, 0.55, 0.8)]

const REGULAR_NAMES := ["タオ爺", "ノノ", "404さん", "傘の人", "夜勤明けの人"]

var day := 1
var keeper := "kiriko"
var streak := 0
var regulars := 0            # 今夜来ている常連の数（先頭の客がそれになる）

var _script: Array = []      # close_day の配膳記録 [{dish, gold, match}]
var _next := 0               # 次に配る serving
var _turnaway := 0           # 素材切れで帰す残り人数（演出）
var _custs: Array = []       # {seat,x,state,t,serving,scarf,dir}
var _seats: Array = [false, false, false, false, false]
var _floats: Array = []      # 頭上のフロート {pos, text, col, t}
var _tips := 0
var _gold_shown := 0         # 積み上がる売上表示（配膳ごとに加算）
var _served_shown := 0
var _spawn_cd := 0.0
var _interval := 1.2
var _end_t := 0.0
var _done := false
var _t := 0.0
var _hits: Array = []
var _ripples: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # ドット絵をカリッと拡大
	set_process(true)


## 上演データを流し込んで初期化。script が空なら呼ばず、直接リザルトへ。
func set_data(d: Dictionary) -> void:
	day = int(d.get("day", 1))
	keeper = String(d.get("keeper", "kiriko"))
	streak = int(d.get("streak", 0))
	regulars = int(d.get("regulars", 0))
	_script = (d.get("script", []) as Array).duplicate()
	_turnaway = mini(int(d.get("customers", 0)) - _script.size(), TURNAWAY_MAX)
	_next = 0
	_custs = []
	_seats = [false, false, false, false, false]
	_floats = []
	_tips = 0
	_gold_shown = 0
	_served_shown = 0
	_spawn_cd = 0.6
	_interval = clampf(30.0 / maxf(_script.size(), 1.0), 0.55, 1.8)
	_end_t = 0.0
	_done = false
	_t = 0.0
	queue_redraw()


## 外部（スキップ・CI）から即終了する。
func skip() -> void:
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit(_tips)


func _process(delta: float) -> void:
	if not visible or _done:
		return
	_t += delta
	_spawn_cd -= delta
	# 入店スケジューラ：空席があれば次の客（配膳 or 素材切れ）を入れる
	if _spawn_cd <= 0.0:
		var seat := _free_seat()
		if seat >= 0 and (_next < _script.size() or _turnaway > 0):
			var serving := -1
			if _next < _script.size():
				serving = _next
				_next += 1
			else:
				_turnaway -= 1
			_seats[seat] = true
			# 先頭 regulars 人は常連（連続完走が連れてきた顔なじみ。チップ2倍）
			var is_reg := serving >= 0 and serving < regulars
			_custs.append({"seat": seat, "x": size.x + 30.0, "state": "in", "t": 0.0,
					"serving": serving, "scarf": GOLD if is_reg else SCARF[(_next + _turnaway) % SCARF.size()],
					"dir": -1.0, "regular": is_reg,
					"rname": REGULAR_NAMES[serving % REGULAR_NAMES.size()] if is_reg else ""})
			_spawn_cd = _interval
	# 客の状態機械
	for c in _custs:
		c["t"] = float(c["t"]) + delta
		var seat_x: float = float(SEAT_XS[int(c["seat"])]) * size.x
		match String(c["state"]):
			"in":
				c["x"] = maxf(float(c["x"]) - 300.0 * delta, seat_x)
				if float(c["x"]) <= seat_x + 0.5:
					c["state"] = "wait" if int(c["serving"]) >= 0 else "deny"
					c["t"] = 0.0
			"wait":
				if float(c["t"]) >= AUTO_SERVE:
					_serve(c, false)
			"deny":
				# 素材切れ：申し訳ない ✕ を出して帰す
				if float(c["t"]) >= 1.2:
					_leave(c)
			"eat":
				if float(c["t"]) >= 1.4:
					var g := int((_script[int(c["serving"])] as Dictionary)["gold"])
					_gold_shown += g
					_served_shown += 1
					_floats.append({"pos": Vector2(seat_x, size.y * COUNTER_Y - CUST_H - 26.0),
							"text": "+%dG" % g, "col": GOLD, "t": 0.0})
					_leave(c)
			"out":
				c["x"] = float(c["x"]) + 320.0 * delta * float(c["dir"])
	# 退店しきった客を消す
	var keep: Array = []
	for c in _custs:
		if String(c["state"]) == "out" and (float(c["x"]) < -60.0 or float(c["x"]) > size.x + 60.0):
			continue
		keep.append(c)
	_custs = keep
	# フロート寿命
	for f in _floats:
		f["t"] = float(f["t"]) + delta
	while not _floats.is_empty() and float(_floats[0]["t"]) > 1.4:
		_floats.pop_front()
	# 全員はけて配膳も尽きたら、ひと呼吸おいて終了
	if _custs.is_empty() and _next >= _script.size() and _turnaway <= 0:
		_end_t += delta
		if _end_t >= 1.0:
			_finish()
	queue_redraw()


func _free_seat() -> int:
	for i in _seats.size():
		if not _seats[i]:
			return i
	return -1


## 配膳：待ち客に皿を出す。tapped=true はタップ給仕（チップが乗る）。
func _serve(c: Dictionary, tapped: bool) -> void:
	c["state"] = "eat"
	c["t"] = 0.0
	var seat_x: float = float(SEAT_XS[int(c["seat"])]) * size.x
	var s: Dictionary = _script[int(c["serving"])]
	_floats.append({"pos": Vector2(seat_x, size.y * COUNTER_Y - CUST_H - 6.0),
			"text": String(s["dish"]) + ("★" if bool(s["match"]) else ""),
			"col": CYAN if bool(s["match"]) else TEXT, "t": 0.0})
	if tapped:
		# 常連はチップ2倍——顔なじみは覚えていてくれる
		var rate := 0.30 if bool(c.get("regular", false)) else 0.15
		var tip := maxi(int(int(s["gold"]) * rate), 1)
		_tips += tip
		_floats.append({"pos": Vector2(seat_x, size.y * COUNTER_Y - CUST_H - 44.0),
				"text": "チップ +%d" % tip, "col": PINK, "t": 0.0})
		tip_tapped.emit()


func _leave(c: Dictionary) -> void:
	_seats[int(c["seat"])] = false
	c["state"] = "out"
	c["t"] = 0.0
	c["dir"] = 1.0 if float(c["x"]) > size.x * 0.5 else -1.0


func _gui_input(event: InputEvent) -> void:
	var p: Vector2
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		p = event.position
	elif event is InputEventScreenTouch and event.pressed:
		p = event.position
	else:
		return
	Kit.ripple_add(_ripples, p, _t)
	for h in _hits:
		if (h["rect"] as Rect2).has_point(p):
			if String(h["id"]) == "skip":
				_finish()
			accept_event()
			return
	# 待ち客のタップ給仕（当たりは客の矩形）
	var cy := size.y * COUNTER_Y
	for c in _custs:
		if String(c["state"]) != "wait":
			continue
		var r := Rect2(float(c["x"]) - 26.0, cy - CUST_H - 8.0, 52.0, CUST_H + 16.0)
		if r.has_point(p):
			_serve(c, true)
			accept_event()
			return


func _draw() -> void:
	var sz := size
	var font := get_theme_default_font()
	_hits.clear()
	var cy := sz.y * COUNTER_Y

	# 背景：店内アート＋夜の暗幕
	Kit.backdrop(self, sz, BG_ART, PINK, 0.62)
	# 提灯あかり（カウンター上の温度）
	Kit.spot(self, Vector2(sz.x * 0.5, cy - 180.0), sz.x * 0.55, Color(1.0, 0.75, 0.45), 0.16)

	# ===== カウンター（天面＋前板＋足元） =====
	draw_rect(Rect2(0, cy - 10, sz.x, 10), Color(0.30, 0.20, 0.13))          # 天面
	draw_rect(Rect2(0, cy - 12, sz.x, 3), Color(0.62, 0.45, 0.28))           # 天面ハイライト
	draw_rect(Rect2(0, cy, sz.x, 96), Color(0.16, 0.11, 0.09))               # 前板
	draw_rect(Rect2(0, cy + 96, sz.x, sz.y - cy - 96), Color(0.05, 0.045, 0.07))  # 土間
	# 土間の板目と、カウンター下の温かい灯だまり
	for i in 5:
		var ly := cy + 120.0 + i * 34.0
		if ly < sz.y:
			draw_rect(Rect2(0, ly, sz.x, 1.5), Color(1, 1, 1, 0.025))
	Kit.spot(self, Vector2(sz.x * 0.5, cy + 130.0), sz.x * 0.4, Color(1.0, 0.7, 0.4), 0.05)
	# スツール
	for sx in SEAT_XS:
		var x: float = float(sx) * sz.x
		draw_rect(Rect2(x - 16, cy + 58, 32, 8), Color(0.35, 0.24, 0.15))
		draw_rect(Rect2(x - 3, cy + 66, 6, 26), Color(0.22, 0.15, 0.10))
	_draw_cat(Vector2(sz.x * (0.5 + 0.36 * sin(_t * 0.25)), cy + 168.0))

	# ===== 店番（カウンターの奥・ちびドット） =====
	var ktex := Kit.pix_tex("res://assets/generated/sprites/%s/idle_f%d.png" % [keeper, int(_t * 3.0) % 4], 32)
	if ktex == null:
		ktex = Kit.pix_tex("res://assets/generated/sprites/%s/idle_f0.png" % keeper, 32)
	if ktex != null:
		var kh := KEEPER_H
		var kw := kh * ktex.get_width() / float(ktex.get_height())
		draw_texture_rect(ktex, Rect2(sz.x * 0.5 - kw * 0.5, cy - 14 - kh, kw, kh), false)

	# ===== 影の客たち =====
	for c in _custs:
		_draw_customer(font, c, cy)

	# ===== フロート（皿名・+G・チップ） =====
	for f in _floats:
		var ft := float(f["t"])
		var a := clampf(1.0 - (ft - 0.9) / 0.5, 0.0, 1.0)
		var pos: Vector2 = (f["pos"] as Vector2) + Vector2(0, -22.0 * ft)
		var col: Color = f["col"]
		var s := String(f["text"])
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(font, pos + Vector2(-w * 0.5 + 1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0, 0, 0, 0.6 * a))
		draw_string(font, pos + Vector2(-w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(col.r, col.g, col.b, a))

	# ===== ヘッダー：夜の営業＋売上カウンタ＋スキップ =====
	draw_rect(Rect2(0, 0, sz.x, 64), Color(0.02, 0.02, 0.05, 0.9))
	draw_rect(Rect2(0, 64, sz.x, 1.5), Color(PINK.r, PINK.g, PINK.b, 0.5))
	var title := "Day %d — 夜の営業" % day
	_sh(font, Vector2(18, 40), title, 18, TEXT)
	if regulars > 0:
		var reg := "連続%d日・常連%d人" % [streak, regulars]
		_sh(font, Vector2(18 + font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 14, 40),
				reg, 13, GOLD)
	var gs := "売上 %dG" % _gold_shown
	if _tips > 0:
		gs += "  チップ %d" % _tips
	var gw := font.get_string_size(gs, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	_sh(font, Vector2(sz.x - gw - 120, 40), gs, 16, GOLD)
	var skip_r := Rect2(sz.x - 96, 14, 82, 38)
	_hits.append({"rect": skip_r, "id": "skip"})
	Kit.panel(self, skip_r, Color(0.05, 0.05, 0.09, 0.9), Color(CYAN.r, CYAN.g, CYAN.b, 0.5), 8, 1.2)
	_sh(font, Vector2(skip_r.position.x + 12, skip_r.position.y + 26), "スキップ", 14, CYAN)
	# ヒント（タップ給仕）
	if _t < 7.0:
		var hint := "！の客をタップで給仕 — チップが入る"
		var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var hr := Rect2((sz.x - hw) * 0.5 - 14, cy + 118, hw + 28, 30)
		Kit.panel(self, hr, Color(0.03, 0.03, 0.06, 0.8), Color(GOLD.r, GOLD.g, GOLD.b, 0.35), 8, 1.0)
		_sh(font, Vector2(hr.position.x + 14, hr.position.y + 21), hint, 15, TEXT)

	Kit.vignette(self, sz)
	Kit.ripples(self, _ripples, _t)


## 影の客を1人描く（ネオンの差し色マフラーの、顔のない夜の住人）。
func _draw_customer(font: Font, c: Dictionary, cy: float) -> void:
	var x := float(c["x"])
	var st := String(c["state"])
	var walk := st == "in" or st == "out"
	var bob := absf(sin(_t * 9.0)) * (3.0 if walk else 0.6)
	var base := cy + (58.0 if not walk else 84.0)   # 着席時はスツールの座面へ
	var h := CUST_H
	var y0 := base - h - bob
	var body := Color(0.10, 0.10, 0.16)
	var rim: Color = c["scarf"]
	var is_reg := bool(c.get("regular", false))
	if is_reg:
		body = Color(0.14, 0.12, 0.10)   # 常連は少し温かい影
	# 胴（丸みのある影）＋頭
	draw_rect(Rect2(x - 14, y0 + 16, 28, h - 16), body)
	draw_circle(Vector2(x, y0 + 12), 12.0, body)
	# 常連の名前タグ（着席中のみ・小さく）
	if is_reg and not walk:
		var nm := String(c.get("rname", "常連"))
		var nw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		_sh(font, Vector2(x - nw * 0.5, y0 + h + 16), nm, 11, GOLD)
	# マフラー（差し色）と目（ネオンの点）
	draw_rect(Rect2(x - 13, y0 + 20, 26, 5), rim)
	draw_circle(Vector2(x - 4, y0 + 10), 1.6, Color(rim.r, rim.g, rim.b, 0.9))
	draw_circle(Vector2(x + 4, y0 + 10), 1.6, Color(rim.r, rim.g, rim.b, 0.9))
	# 歩行の足
	if walk:
		var ph := sin(_t * 12.0)
		draw_rect(Rect2(x - 9 + ph * 3.0, base - 8, 7, 8), body)
		draw_rect(Rect2(x + 2 - ph * 3.0, base - 8, 7, 8), body)
	# 状態バブル
	match st:
		"wait":
			var pulse := 0.5 + 0.5 * sin(_t * 5.0)
			var br := Rect2(x - 15, y0 - 26, 30, 22)
			Kit.panel(self, br, Color(0.04, 0.04, 0.08, 0.92), Color(GOLD.r, GOLD.g, GOLD.b, 0.4 + 0.4 * pulse), 7, 1.2)
			_sh(font, Vector2(x - 5, y0 - 10), "！", 14, GOLD)
		"deny":
			_sh(font, Vector2(x - 6, y0 - 10), "✕", 15, Color(1.0, 0.5, 0.45))
		"eat":
			# 皿（カウンター天面）
			var pt := clampf(float(c["t"]) / 0.3, 0.0, 1.0)
			var px := lerpf(size.x * 0.5, x, pt)
			draw_ellipse_shim(Vector2(px, cy - 16), Vector2(13, 5), Color(0.9, 0.88, 0.85))
			draw_circle(Vector2(px, cy - 18), 5.0, Color(0.85, 0.55, 0.3))


## 店名の主・黒猫。土間をゆっくり往復し、尻尾だけがネオンの間で揺れる。
func _draw_cat(pos: Vector2) -> void:
	var dirx: float = signf(cos(_t * 0.25))
	var body := Color(0.03, 0.03, 0.05)
	draw_ellipse_shim(pos, Vector2(16, 8), body)                    # 胴
	var hx := pos.x + 14.0 * dirx
	draw_circle(Vector2(hx, pos.y - 6), 7.0, body)                  # 頭
	draw_colored_polygon(PackedVector2Array([Vector2(hx - 6, pos.y - 10),
			Vector2(hx - 2, pos.y - 17), Vector2(hx, pos.y - 9)]), body)   # 耳
	draw_colored_polygon(PackedVector2Array([Vector2(hx + 6, pos.y - 10),
			Vector2(hx + 2, pos.y - 17), Vector2(hx, pos.y - 9)]), body)
	draw_circle(Vector2(hx + 2.0 * dirx, pos.y - 7), 1.3, Color(1.0, 0.82, 0.4, 0.9))  # 金の目
	var tx := pos.x - 15.0 * dirx
	var sway := sin(_t * 2.2) * 6.0
	draw_line(Vector2(tx, pos.y - 2), Vector2(tx - 10.0 * dirx + sway * 0.4, pos.y - 16 - absf(sway) * 0.4),
			body, 3.0)                                              # 尻尾


## 楕円（Godot 4.6 の CanvasItem.draw_ellipse と衝突しない自前名）。
func draw_ellipse_shim(center: Vector2, radii: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, col)


## 影付きテキスト。
func _sh(font: Font, pos: Vector2, s: String, size_px: int, col: Color) -> void:
	draw_string(font, pos + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(0, 0, 0, 0.55))
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, col)
