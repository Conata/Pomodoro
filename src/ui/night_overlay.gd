class_name NightOverlay
extends Control
## 夜営業シアター — デイブザダイバーの夜の店にあたる報酬劇場。
## 浮上→精算のあいだに、close_day の配膳記録（script）をカウンター越しに上演する：
## 客が入店→着席→注文の吹き出し→皿が出る→支払い→退店。
## タップ給仕（吹き出しの客をタップ）で即配膳＋チップ。放置でも自動で完走し、
## スキップも常時可能——5分休憩の楽しみであって、義務にはしない。
##
## 画づくりの方針（デイブ基準）:
##  - 客は「人」に見えること。髪型・服・体格・肌がひとりずつ違う。
##  - カウンター前板が客の下半身を隠す＝「カウンター越しに座っている」絵。
##  - 提灯の芯が画面で最も明るい点。暖色の光が全体を包む。
##  - 画面に無情報の黒い平面を作らない。下部は「今夜の伝票」。
##  - ピクセル密度を 3px モジュールに統一（q()）。背景は等倍（1テクセル=1px）。

signal finished(tips: int)   # 劇場の終了（チップ合計を持ち帰る）
signal tip_tapped            # タップ給仕の瞬間（SFX用）

# 状態色は一対一対応にする：CYAN=予報的中 だけ。金＝お金（売上・チップ）、赤＝素材切れ。
# （マゼンタは「バグの色」として空けておく＝画に出たら異常と分かる）
const CYAN := Color(0.35, 0.92, 1.0)     # 予報的中 — この意味以外に使わない
const GOLD := Color(1.0, 0.82, 0.4)      # 金（売上・チップ・常連）
const DENY := Color(1.0, 0.45, 0.42)     # 素材切れ
const TEXT := Color(0.96, 0.95, 0.98)
const TEXT_DIM := Color(0.72, 0.74, 0.82)
const BG_ART := "res://assets/generated/bg/interior.png"

## 文字は5段だけ。11段あった頃は「意味の違い」ではなく「気分の違い」で選ばれていた。
const FS := {XS = 10, S = 14, M = 18, L = 24, XL = 48}

const U := 3.0               # ピクセル密度モジュール（全座標をこの倍数へ）
const COUNTER_Y := 0.46      # カウンター天面（画面比）— 構図を上へ寄せる
const SEAT_XS := [0.11, 0.27, 0.43, 0.73, 0.89]
const SEAT_JITTER := 14.0    # 等間隔をやめる幅（±px）。整列した椅子は工場に見える
const KEEPER_X := 0.58       # 店番はカウンターの奥、席の切れ目に立つ
const SLAB_H := 18.0         # 天面の厚み
const APRON_H := 99.0        # 前板の高さ
const CUST_H := 120.0        # 客の全高（基準体格）
const KEEPER_H := 144.0      # 48テクセル×3（背景・客と同じ3pxモジュール）
const AUTO_SERVE := 2.4      # 着席から自動配膳までの秒数（この間はタップ給仕可）
const TURNAWAY_MAX := 3      # 素材切れで帰す客の演出数上限

# 木・灯り
const WOOD_SLAB := Color(0.36, 0.245, 0.155)
const WOOD_EDGE := Color(0.82, 0.60, 0.34)
const WOOD_APRON := Color(0.215, 0.145, 0.105)
const WOOD_DARK := Color(0.115, 0.08, 0.065)
const FLOOR_C := Color(0.058, 0.052, 0.078)
const LANT_CORE := Color(1.0, 0.99, 0.96)   # 提灯の芯＝画面最大輝度。揺らさない。
const LANT_WARM := Color(1.0, 0.72, 0.36)
const RIM := Color(1.0, 0.80, 0.50, 0.85)
const INK := Color(0.02, 0.02, 0.045, 0.92)

# 客のばらつき（全員違う人にするための素材）
const HAIRS := [Color(0.40, 0.27, 0.19), Color(0.20, 0.18, 0.26), Color(0.76, 0.60, 0.32),
		Color(0.62, 0.26, 0.24), Color(0.34, 0.42, 0.52), Color(0.80, 0.77, 0.82),
		Color(0.50, 0.24, 0.44), Color(0.28, 0.38, 0.30)]
const CLOTHS := [Color(0.36, 0.20, 0.22), Color(0.17, 0.25, 0.34), Color(0.38, 0.31, 0.17),
		Color(0.24, 0.19, 0.34), Color(0.15, 0.30, 0.26), Color(0.40, 0.24, 0.14),
		Color(0.24, 0.24, 0.29), Color(0.33, 0.16, 0.28)]
const SKINS := [Color(0.62, 0.45, 0.35), Color(0.72, 0.55, 0.43), Color(0.52, 0.37, 0.29),
		Color(0.66, 0.50, 0.40), Color(0.45, 0.32, 0.26)]
# 影の客のマフラー色（ネオンノワールの差し色）
const SCARF := [Color(0.95, 0.4, 0.5), Color(0.4, 0.8, 0.95), Color(0.95, 0.75, 0.35),
		Color(0.7, 0.5, 0.95), Color(0.45, 0.9, 0.6), Color(0.9, 0.55, 0.8)]

const REGULAR_NAMES := ["タオ爺", "ノノ", "404さん", "傘の人", "夜勤明け"]

var day := 1
var keeper := "kiriko"
var streak := 0
var regulars := 0            # 今夜来ている常連の数（先頭の客がそれになる）

var _script: Array = []      # close_day の配膳記録 [{dish, gold, match}]
var _next := 0               # 次に配る serving
var _turnaway := 0           # 素材切れで帰す残り人数（演出）
var _custs: Array = []       # {seat,x,state,t,serving,scarf,dir,...}
var _seats: Array = [false, false, false, false, false]
var _floats: Array = []      # 頭上のフロート {pos, text, col, t}
var _tips := 0
var _gold_shown := 0         # 積み上がる売上（配膳ごとに加算）
var _gold_disp := 0.0        # 表示上の売上（カウントアップ用）
var _pop := 0.0              # 加算の瞬間のスケールポップ残り秒
var _served_shown := 0
var _matched := 0
var _plates: Array = []      # 伝票に積む皿 [{kind, match}]
var _total := 0              # 今夜の客数（伝票のスロット数）
var _spawn_cd := 0.0
var _interval := 1.2
var _end_t := 0.0
var _done := false
var _t := 0.0
var _hits: Array = []
var _ripples: Array = []
var _keeper_frames: Array = []   # 事前生成した店番のドット絵フレーム

static var _glow_t: ImageTexture = null
static var _vign_t: ImageTexture = null
static var _bg_t: Texture2D = null
static var _bg_loaded := false
static var _pix_cache: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # ドット絵をカリッと拡大
	_warm_up()
	set_process(true)


## 3px グリッドへ量子化。全ての図形座標をここに通してピクセル密度を揃える。
func q(v: float) -> float:
	return round(v / U) * U


## 上演データを流し込んで初期化。script が空なら呼ばず、直接リザルトへ。
func set_data(d: Dictionary) -> void:
	day = int(d.get("day", 1))
	keeper = String(d.get("keeper", "kiriko"))
	streak = int(d.get("streak", 0))
	regulars = int(d.get("regulars", 0))
	_script = (d.get("script", []) as Array).duplicate()
	_total = maxi(int(d.get("customers", _script.size())), _script.size())
	_turnaway = mini(_total - _script.size(), TURNAWAY_MAX)
	_next = 0
	_custs = []
	_seats = [false, false, false, false, false]
	_floats = []
	_plates = []
	_tips = 0
	_gold_shown = 0
	_gold_disp = 0.0
	_pop = 0.0
	_served_shown = 0
	_matched = 0
	_spawn_cd = 0.5
	_interval = clampf(30.0 / maxf(_script.size(), 1.0), 0.55, 1.8)
	_end_t = 0.0
	_done = false
	_t = 0.0
	_warm_up()
	queue_redraw()


## 生成テクスチャは必ず _draw の外で作る。描画中に GPU へ上げると
## そのフレームだけ未初期化のまま（マゼンタの矩形）出てしまう。
func _warm_up() -> void:
	_glow_tex()
	_vign_tex()
	if not _bg_loaded:
		_bg_loaded = true
		_bg_t = load(BG_ART) if ResourceLoader.exists(BG_ART) else null
	_keeper_frames.clear()
	for i in 4:
		var t := _pix("res://assets/generated/sprites/%s/idle_f%d.png" % [keeper, i], 48)
		# 隅が不透明なフレームは地が抜けていない＝色板が出る。捨てて f0 に落とす。
		if not _frame_ok(t):
			t = _pix("res://assets/generated/sprites/%s/idle_f0.png" % keeper, 48)
		if _frame_ok(t):
			_keeper_frames.append(t)


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
	_gold_disp = lerpf(_gold_disp, float(_gold_shown), clampf(delta * 8.0, 0.0, 1.0))
	_pop = maxf(_pop - delta, 0.0)
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
			var sd := (seat * 7 + maxi(serving, 0) * 13 + _turnaway * 5 + day * 3) % 997
			_custs.append({"seat": seat, "x": size.x + 40.0, "state": "in", "t": 0.0,
					"serving": serving, "seed": sd,
					"scarf": GOLD if is_reg else SCARF[(_next + _turnaway) % SCARF.size()],
					"dir": -1.0, "regular": is_reg,
					"rname": REGULAR_NAMES[serving % REGULAR_NAMES.size()] if is_reg else ""})
			_spawn_cd = _interval
	# 客の状態機械
	var cy := q(size.y * COUNTER_Y)
	for c in _custs:
		c["t"] = float(c["t"]) + delta
		var seat_x := _seat_x(int(c["seat"]))
		match String(c["state"]):
			"in":
				c["x"] = maxf(float(c["x"]) - 320.0 * delta, seat_x)
				if float(c["x"]) <= seat_x + 0.5:
					c["state"] = "wait" if int(c["serving"]) >= 0 else "deny"
					c["t"] = 0.0
			"wait":
				if float(c["t"]) >= AUTO_SERVE:
					_serve(c, false)
			"deny":
				# 素材切れ：申し訳ない ✕ を出して帰す
				if float(c["t"]) >= 1.3:
					_leave(c)
			"eat":
				if float(c["t"]) >= 1.5:
					var s: Dictionary = _script[int(c["serving"])]
					var g := int(s["gold"])
					_gold_shown += g
					_gold_disp = maxf(_gold_disp, float(_gold_shown) - g * 0.9)
					_pop = 0.18
					_served_shown += 1
					if bool(s.get("match", false)):
						_matched += 1
					_plates.append({"kind": _dish_kind(String(s["dish"])), "match": bool(s.get("match", false))})
					_floats.append({"pos": Vector2(seat_x, cy - CUST_H + 12.0),
							"text": "+%dG" % g, "col": GOLD, "t": 0.0})
					_leave(c)
			"out":
				c["x"] = float(c["x"]) + 340.0 * delta * float(c["dir"])
	# 退店しきった客を消す
	var keep: Array = []
	for c in _custs:
		if String(c["state"]) == "out" and (float(c["x"]) < -70.0 or float(c["x"]) > size.x + 70.0):
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
		if _end_t >= 1.2:
			_finish()
	queue_redraw()


## 席の x。等間隔だと「椅子を並べた工場」に見えるので seed で ±14px 崩す。
## day を混ぜて、同じ夜のあいだは動かず、日が変われば並びが変わる。
func _seat_x(i: int) -> float:
	var j := (float((i * 37 + day * 23 + 11) % 29) / 14.0 - 1.0) * SEAT_JITTER
	return q(float(SEAT_XS[i]) * size.x + j)


func _free_seat() -> int:
	for i in _seats.size():
		if not _seats[i]:
			return i
	return -1


## 配膳：待ち客に皿を出す。tapped=true はタップ給仕（チップが乗る）。
func _serve(c: Dictionary, tapped: bool) -> void:
	c["state"] = "eat"
	c["t"] = 0.0
	var seat_x := _seat_x(int(c["seat"]))
	var cy := q(size.y * COUNTER_Y)
	var s: Dictionary = _script[int(c["serving"])]
	_floats.append({"pos": Vector2(seat_x, cy - CUST_H + 30.0),
			"text": String(s["dish"]) + ("　★予報的中" if bool(s.get("match", false)) else ""),
			"col": CYAN if bool(s.get("match", false)) else TEXT, "t": 0.0})
	if tapped:
		# 常連はチップ2倍——顔なじみは覚えていてくれる
		var rate := 0.30 if bool(c.get("regular", false)) else 0.15
		var tip := maxi(int(int(s["gold"]) * rate), 1)
		_tips += tip
		_floats.append({"pos": Vector2(seat_x, cy - CUST_H - 6.0),
				"text": "チップ +%d" % tip, "col": GOLD, "t": 0.0})
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
	_ripple_add(p)
	for h in _hits:
		if (h["rect"] as Rect2).has_point(p):
			if String(h["id"]) == "skip":
				_finish()
			accept_event()
			return
	# 待ち客のタップ給仕（当たりは頭〜吹き出しを含む広めの矩形）
	var cy := q(size.y * COUNTER_Y)
	for c in _custs:
		if String(c["state"]) != "wait":
			continue
		var r := Rect2(float(c["x"]) - 48.0, cy - CUST_H - 62.0, 96.0, CUST_H + 62.0)
		if r.has_point(p):
			_serve(c, true)
			accept_event()
			return


# ══════════════════════════════════════════════════════════════════════
#  描画
# ══════════════════════════════════════════════════════════════════════

func _draw() -> void:
	var sz := size
	var font := get_theme_default_font()
	_hits.clear()
	var cy := q(sz.y * COUNTER_Y)
	var art_top := cy - 200.0
	var floor_y := cy + APRON_H
	var rec := Rect2(q(18.0), q(sz.y - 384.0), q(sz.x - 36.0), q(366.0))

	# ── 1. 奥の壁（背景アートの上を procedural で埋める）─────────────
	_draw_wall(sz, art_top)
	# ── 2. 背景アート（等倍・横合わせ。上端はカウンターから逆算）────
	_draw_backart(sz, cy)
	# ── 3. 提灯（画面で最も明るい点をここで作る）────────────────────
	_draw_lanterns(sz, art_top, cy)
	# ── 4. カウンター下〜土間のベース ────────────────────────────────
	draw_rect(Rect2(0, cy, sz.x, sz.y - cy), FLOOR_C)
	_glow(Vector2(sz.x * 0.5, cy - 40.0), sz.x * 0.62, LANT_WARM, 0.16)

	# ── 5. 店番（カウンターの奥）───────────────────────────────────
	_draw_keeper(sz, cy)

	# ── 6. カウンター天面 ───────────────────────────────────────────
	draw_rect(Rect2(0, cy - SLAB_H, sz.x, SLAB_H), WOOD_SLAB)
	for i in 26:
		var gx := q(i * sz.x / 26.0 + 7.0)
		draw_rect(Rect2(gx, cy - SLAB_H + 3, 2, SLAB_H - 6), Color(0, 0, 0, 0.10))
	draw_rect(Rect2(0, cy - SLAB_H, sz.x, 3), Color(0.52, 0.36, 0.22))

	# ── 7. 客（前板より先に描く＝カウンター越しに座って見える）──────
	for c in _custs:
		_draw_customer(c, cy)

	# ── 8. 前板（下半身を隠す）＋天面の光る前縁 ─────────────────────
	_draw_apron(sz, cy)
	_draw_edge(sz, cy)

	# ── 9. 天面の上のもの（席札・おしぼり・出された皿）────────────
	_draw_counter_props(font, cy)

	# ── 10. 吹き出しとフロート ──────────────────────────────────────
	for c in _custs:
		_draw_bubble(font, c, cy)
	for f in _floats:
		var ft := float(f["t"])
		var a := clampf(1.0 - (ft - 0.9) / 0.5, 0.0, 1.0)
		var pos: Vector2 = (f["pos"] as Vector2) + Vector2(0, -26.0 * ft)
		var col: Color = f["col"]
		var s := String(f["text"])
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.M)).x
		var fx := clampf(pos.x - w * 0.5, 10.0, sz.x - w - 10.0)
		draw_string(font, Vector2(fx + 1, pos.y + 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.M), Color(0, 0, 0, 0.65 * a))
		draw_string(font, Vector2(fx, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.M), Color(col.r, col.g, col.b, a))

	# ── 11. 土間（反射・スキャンライン・黒猫）──────────────────────
	_draw_floor(sz, cy, floor_y, rec.position.y)

	# ── 12. 今夜の伝票（下部の死に領域を報酬パネルへ）───────────────
	_draw_receipt(font, rec)

	# ── 13. ヒント ─────────────────────────────────────────────────
	if _t < 8.0:
		var hint := "！の客をタップで給仕 — チップが入る"
		var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.S)).x
		var ha := clampf((8.0 - _t) / 1.2, 0.0, 1.0)
		var hr := Rect2(q((sz.x - hw) * 0.5 - 15.0), rec.position.y - 48.0, q(hw + 30.0), 33.0)
		_panel(hr, Color(0.04, 0.035, 0.06, 0.86 * ha), Color(GOLD.r, GOLD.g, GOLD.b, 0.40 * ha), 8, 1.0)
		_sh(font, Vector2(hr.position.x + 15, hr.position.y + 23), hint, int(FS.S), Color(TEXT.r, TEXT.g, TEXT.b, ha))

	# ── 14. ヘッダー（右端基点で右から積む）─────────────────────────
	_draw_header(font, sz)

	_vignette(sz)
	_draw_ripples()


# ── 奥の壁 ────────────────────────────────────────────────────────────

## 背景アートの上に広がる壁。梁・吊り棚の酒瓶・品書きの木札・吊るした植物で
## 「無情報の平面」を潰す。デイブの店＝あらゆる面に情報がある。
func _draw_wall(sz: Vector2, art_top: float) -> void:
	_vgrad(Rect2(0, 0, sz.x, art_top + 4.0), Color(0.045, 0.042, 0.075), Color(0.115, 0.085, 0.085))
	# 縦の柱
	for fx in [0.035, 0.965]:
		var px := q(sz.x * fx - 15.0)
		draw_rect(Rect2(px, 0, 30, art_top), Color(0.115, 0.082, 0.062))
		draw_rect(Rect2(px, 0, 3, art_top), Color(0.24, 0.17, 0.11))
	# 天井の梁（上端）
	draw_rect(Rect2(0, 60, sz.x, 33), Color(0.13, 0.09, 0.07))
	draw_rect(Rect2(0, 60, sz.x, 3), Color(0.26, 0.18, 0.12))
	draw_rect(Rect2(0, 90, sz.x, 3), Color(0.05, 0.035, 0.03))
	for i in 12:
		draw_rect(Rect2(q(30.0 + i * sz.x / 12.0), 69, 6, 6), Color(0.30, 0.22, 0.14))
	# 中央の品書き板（梁から吊る）
	var mb := Rect2(q(sz.x * 0.30), 96.0, q(sz.x * 0.40), 60.0)
	draw_rect(Rect2(mb.position.x + 12, 93, 3, 6), Color(0.35, 0.26, 0.15))
	draw_rect(Rect2(mb.position.x + mb.size.x - 15, 93, 3, 6), Color(0.35, 0.26, 0.15))
	draw_rect(Rect2(mb.position + Vector2(0, 4), mb.size), Color(0, 0, 0, 0.4))
	draw_rect(mb, Color(0.155, 0.115, 0.085))
	draw_rect(Rect2(mb.position, Vector2(mb.size.x, 3)), Color(0.36, 0.26, 0.16))
	draw_rect(Rect2(mb.position.x, mb.position.y + mb.size.y - 3, mb.size.x, 3), Color(0.05, 0.04, 0.03))
	for row in 3:
		var ry := q(mb.position.y + 12.0 + row * 15.0)
		var rn := 5 + row
		for k in rn:
			draw_rect(Rect2(q(mb.position.x + 15.0 + k * (mb.size.x - 30.0) / rn), ry,
					(mb.size.x - 30.0) / rn - 9.0, 4), Color(0.85, 0.68, 0.36, 0.55 - row * 0.10))
	# 吊るした唐辛子と小札（面を情報で埋める）
	for cxf in [0.135, 0.175, 0.825, 0.865]:
		var cxx := q(sz.x * cxf)
		draw_rect(Rect2(cxx - 1, 93, 2, 15), Color(0.35, 0.28, 0.16))
		for k2 in 5:
			var pyy := q(105.0 + k2 * 12.0)
			draw_colored_polygon(PackedVector2Array([Vector2(cxx - 5, pyy), Vector2(cxx + 5, pyy),
					Vector2(cxx + 1, pyy + 16)]), Color(0.68, 0.18, 0.14) if k2 % 2 == 0 else Color(0.58, 0.14, 0.12))
	for txf in [0.265, 0.735]:
		var txx := q(sz.x * txf)
		draw_rect(Rect2(txx - 1, 93, 2, 12), Color(0.35, 0.28, 0.16))
		draw_rect(Rect2(txx - 12, 105, 24, 36), Color(0.48, 0.37, 0.22))
		draw_rect(Rect2(txx - 12, 105, 24, 3), Color(0.70, 0.56, 0.34))
		for k3 in 3:
			draw_rect(Rect2(txx - 6, q(114.0 + k3 * 9.0), 9, 3), Color(0.16, 0.10, 0.07, 0.85))
	# 吊り棚（酒瓶がずらり）
	var shelf_y := q(art_top - 108.0)
	draw_rect(Rect2(q(sz.x * 0.06), shelf_y, q(sz.x * 0.88), 9), Color(0.24, 0.165, 0.105))
	draw_rect(Rect2(q(sz.x * 0.06), shelf_y, q(sz.x * 0.88), 3), Color(0.42, 0.30, 0.18))
	draw_rect(Rect2(q(sz.x * 0.06), shelf_y + 9, q(sz.x * 0.88), 6), Color(0.05, 0.04, 0.04))
	var bottle_cols := [Color(0.30, 0.42, 0.28), Color(0.42, 0.26, 0.18), Color(0.24, 0.30, 0.42),
			Color(0.46, 0.38, 0.22), Color(0.34, 0.22, 0.30), Color(0.20, 0.34, 0.34)]
	var bx := q(sz.x * 0.085)
	var bi := 0
	while bx < sz.x * 0.93:
		# 中央の提灯の真下は空ける
		if absf(bx - sz.x * 0.5) > 42.0:
			var bh := q(27.0 + float((bi * 17) % 4) * 9.0)
			var bw := q(12.0 + float(bi % 2) * 3.0)
			var col: Color = bottle_cols[bi % bottle_cols.size()]
			draw_rect(Rect2(bx, shelf_y - bh, bw, bh), col)
			draw_rect(Rect2(bx + bw * 0.5 - 3, shelf_y - bh - 12, 6, 12), col.darkened(0.25))
			draw_rect(Rect2(bx, shelf_y - bh, 3, bh), col.lightened(0.30))
			draw_rect(Rect2(bx, shelf_y - bh - 15, 6, 3), Color(0.85, 0.78, 0.60, 0.5))
			bi += 1
		bx += q(24.0)
	# 品書きの木札（吊り下げ）
	var rail_y := q(art_top - 84.0)
	draw_rect(Rect2(0, rail_y, sz.x, 6), Color(0.20, 0.14, 0.09))
	for i in 9:
		var tx := q(sz.x * (0.055 + i * 0.1075))
		var th := q(24.0 + float((i * 7) % 4) * 9.0)
		var tw := q(21.0 + float((i * 5) % 3) * 6.0)
		var warm := 0.44 + float((i * 3) % 3) * 0.06
		draw_rect(Rect2(tx + tw * 0.4, rail_y + 6, 3, 9), Color(0.35, 0.28, 0.16))
		draw_rect(Rect2(tx + 2, rail_y + 18, tw, th), Color(0, 0, 0, 0.35))
		draw_rect(Rect2(tx, rail_y + 15, tw, th), Color(warm + 0.10, warm - 0.04, warm - 0.20))
		draw_rect(Rect2(tx, rail_y + 15, tw, 3), Color(0.74, 0.60, 0.38))
		for k in int(th / 9.0) - 1:
			draw_rect(Rect2(tx + 6, rail_y + 27 + k * 9, tw - 12, 3), Color(0.16, 0.10, 0.07, 0.8))
		if i % 3 == 1:
			draw_rect(Rect2(tx + tw - 12, rail_y + th + 3, 8, 8), Color(0.72, 0.20, 0.16))
	# 吊るした植物
	_draw_plant(Vector2(q(sz.x * 0.085), 93.0))
	_draw_plant(Vector2(q(sz.x * 0.915), 93.0))
	# 壁の下端＝アートへの継ぎ目を隠す梁
	draw_rect(Rect2(0, art_top - 21, sz.x, 21), Color(0.14, 0.095, 0.07))
	draw_rect(Rect2(0, art_top - 21, sz.x, 3), Color(0.30, 0.21, 0.13))
	draw_rect(Rect2(0, art_top - 3, sz.x, 3), Color(0.04, 0.03, 0.03))


func _draw_plant(top: Vector2) -> void:
	var pot_y := q(top.y + 42.0)
	for dx in [-12.0, 0.0, 12.0]:
		_pxdiag(Vector2(top.x + dx * 0.3, top.y), Vector2(top.x + dx, pot_y), Color(0.30, 0.24, 0.16))
	draw_rect(Rect2(top.x - 15, pot_y, 30, 21), Color(0.36, 0.20, 0.14))
	draw_rect(Rect2(top.x - 18, pot_y, 36, 6), Color(0.46, 0.27, 0.18))
	var leaf := Color(0.16, 0.32, 0.20)
	for i in 7:
		var a := PI * 0.15 + PI * 0.70 * (i / 6.0)
		var l := 33.0 + float((i * 13) % 3) * 12.0
		var tip := Vector2(top.x + cos(a) * l * 1.15, pot_y + 15.0 + sin(a) * l)
		draw_colored_polygon(PackedVector2Array([
				Vector2(top.x, pot_y + 6), tip,
				Vector2(top.x + cos(a) * l * 0.55 + 7.0, pot_y + 9.0 + sin(a) * l * 0.55)]),
				leaf if i % 2 == 0 else leaf.lightened(0.18))


# ── 背景アート（等倍）────────────────────────────────────────────────

func _draw_backart(sz: Vector2, cy: float) -> void:
	if _bg_t == null:
		return
	var ts := _bg_t.get_size()
	var s := sz.x / ts.x                    # 横合わせ（1テクセル=1px）
	var dst := ts * s
	var top := q(cy - dst.y)
	draw_texture_rect(_bg_t, Rect2(0, top, dst.x, dst.y), false)
	# 夜の暗幕（濁らせないよう軽く。暖色の光は上から別に足す）
	draw_rect(Rect2(0, top, dst.x, dst.y), Color(0.03, 0.02, 0.06, 0.30))
	_vgrad(Rect2(0, top, dst.x, dst.y * 0.45), Color(0.01, 0.01, 0.04, 0.55), Color(0, 0, 0, 0))


# ── 提灯 ──────────────────────────────────────────────────────────────

## 画面で最も明るい点はここ。芯を白に近い暖色で置き、周りへ光をこぼす。
func _draw_lanterns(sz: Vector2, art_top: float, cy: float) -> void:
	var flick := 1.0 + 0.05 * sin(_t * 3.1) + 0.03 * sin(_t * 7.7)
	# 環境光は提灯より先に。芯の上に半透明を重ねると最明部が245を割る。
	_glow(Vector2(sz.x * 0.5, cy - 150.0), sz.x * 0.75, LANT_WARM, 0.10)
	_lantern(Vector2(q(sz.x * 0.22), 93.0), q(66.0), 20.0, flick)
	_lantern(Vector2(q(sz.x * 0.50), 93.0), q(105.0), 26.0, 1.0 / flick)
	_lantern(Vector2(q(sz.x * 0.78), 93.0), q(66.0), 20.0, flick * 0.98)
	# カウンター上の小さな灯（客の顔を起こす）
	for fx in [0.20, 0.80]:
		var lp := Vector2(q(sz.x * fx), q(art_top + 24.0))
		_lantern(lp - Vector2(0, 24.0), 24.0, 13.0, flick)


func _lantern(top: Vector2, cord: float, r: float, flick: float) -> void:
	var by := q(top.y + cord)
	draw_rect(Rect2(top.x - 1, top.y, 3, cord), Color(0.22, 0.16, 0.10))
	var h := r * 2.6
	var body := Color(0.92, 0.42, 0.26)
	# 提灯の胴（縦に膨らんだ樽形）
	for i in int(h / U):
		var yy := by + i * U
		var k := (i * U) / h
		var w := r * (0.62 + 0.38 * sin(k * PI))
		var shade := 1.0 - absf(k - 0.42) * 0.35
		draw_rect(Rect2(q(top.x - w), yy, q(w * 2.0), U),
				Color(body.r * shade, body.g * shade, body.b * shade))
	# 骨（横のリブ）
	for i in int(h / 9.0):
		var yy2 := by + i * 9.0
		var k2 := (i * 9.0) / h
		var w2 := r * (0.62 + 0.38 * sin(k2 * PI))
		draw_rect(Rect2(q(top.x - w2), yy2, q(w2 * 2.0), 1.5), Color(0.35, 0.14, 0.10, 0.55))
	# 上下の口金
	draw_rect(Rect2(q(top.x - r * 0.5), by - 3, q(r), 6), Color(0.20, 0.15, 0.10))
	draw_rect(Rect2(q(top.x - r * 0.5), by + h - 3, q(r), 6), Color(0.20, 0.15, 0.10))
	# 光のにじみ（揺らぐのはここだけ）→ 芯（画面最大輝度・揺らさない）
	var c := Vector2(top.x, by + h * 0.5)
	_glow(c, r * 5.2, LANT_WARM, 0.30 * flick)
	_glow(c, r * 2.1, Color(1.0, 0.88, 0.66), 0.55 * flick)
	# 芯に flick を掛けると「最も明るい点」が消えるフレームができる。
	# 小さく・不透明・固定値で置き、画面の輝度の頂点をここに釘付けにする。
	draw_rect(Rect2(q(c.x - 6.0), q(c.y - 9.0), 15, 21), Color(1.0, 0.90, 0.70, 0.45))
	draw_rect(Rect2(q(c.x - 3.0), q(c.y - 6.0), 6, 9), LANT_CORE)


# ── カウンター ───────────────────────────────────────────────────────

func _draw_apron(sz: Vector2, cy: float) -> void:
	_vgrad(Rect2(0, cy, sz.x, APRON_H), WOOD_APRON.lightened(0.12), WOOD_DARK)
	# 縦板の継ぎ目
	var n := int(sz.x / 60.0)
	for i in n + 1:
		var px := q(i * 60.0)
		draw_rect(Rect2(px, cy + 3, 2, APRON_H - 6), Color(0, 0, 0, 0.30))
		draw_rect(Rect2(px + 2, cy + 3, 1.5, APRON_H - 6), Color(1, 1, 1, 0.035))
	# 前板に貼った品書きの短冊（面を情報で埋める）
	for i in 6:
		var sx := q(sz.x * (0.085 + i * 0.166))
		var sh := q(39.0 + float((i * 5) % 3) * 9.0)
		var sr := Rect2(sx - 15, cy + 18, 30, sh)
		draw_rect(Rect2(sr.position + Vector2(2, 3), sr.size), Color(0, 0, 0, 0.45))
		draw_rect(sr, Color(0.40, 0.32, 0.21))
		draw_rect(Rect2(sr.position, Vector2(sr.size.x, 3)), Color(0.60, 0.48, 0.30))
		for k in int(sh / 9.0) - 1:
			draw_rect(Rect2(sr.position.x + 11, q(sr.position.y + 9.0 + k * 9.0), 8, 3),
					Color(0.14, 0.09, 0.07, 0.9))
	# 足掛けの横棒（真鍮）。前縁と同じ理由で、ここも全幅一様の直線にはしない
	# ——明るい水平線が2本走ると、画面がもう一度上下に割れる。
	var rail_y := cy + APRON_H - 33.0
	draw_rect(Rect2(0, rail_y, sz.x, 5), Color(0.28, 0.20, 0.10))
	var rsig := sz.x * 0.28
	var rseg := q(30.0)
	var rx := 0.0
	var ri := 0
	while rx < sz.x:
		var rmid := rx + rseg * 0.5
		var rd := sz.x
		for lx in [sz.x * 0.22, sz.x * 0.50, sz.x * 0.78]:
			rd = minf(rd, absf(rmid - float(lx)))
		var rg := exp(-(rd * rd) / (2.0 * rsig * rsig))
		draw_rect(Rect2(rx, rail_y, rseg - 3.0 * float((ri * 5 + 1) % 3), 2),
				Color(0.72, 0.56, 0.28, clampf(0.10 + 0.72 * rg, 0.0, 1.0)))
		rx += rseg
		ri += 1
	# 支持金具（ここで横棒が視覚的に切れる）
	for i in int(sz.x / 120.0) + 1:
		draw_rect(Rect2(q(i * 120.0), rail_y - 3, 8, 15), Color(0.22, 0.16, 0.09))
	# 幅木
	draw_rect(Rect2(0, cy + APRON_H - 12, sz.x, 12), Color(0.145, 0.10, 0.075))
	draw_rect(Rect2(0, cy + APRON_H - 12, sz.x, 3), Color(0.30, 0.21, 0.13))
	draw_rect(Rect2(0, cy + APRON_H, sz.x, 9), Color(0, 0, 0, 0.45))


## 天面の前縁（木口）。全幅・均一輝度の直線は画面を上下に断ち切ってしまうので、
## 提灯からの距離でガウス減衰させた短い矩形の連なりにし、数箇所は木口を欠けさせる。
func _draw_edge(sz: Vector2, cy: float) -> void:
	var lant := [sz.x * 0.22, sz.x * 0.50, sz.x * 0.78]
	var chips := [0.075, 0.29, 0.505, 0.70, 0.925]      # 木口の欠け（5箇所）
	var seg := q(24.0)
	var sig := sz.x * 0.26
	var i := 0
	var sx := 0.0
	while sx < sz.x:
		var mid := sx + seg * 0.5
		var f := mid / sz.x
		var chipped := false
		for cf in chips:
			if absf(f - float(cf)) < 0.014:
				chipped = true
		var d := sz.x
		for lx in lant:
			d = minf(d, absf(mid - float(lx)))
		var g := exp(-(d * d) / (2.0 * sig * sig))       # 提灯からのガウス減衰
		# 目地は等間隔にしない（等間隔だと破線に見えて、また「線」に戻ってしまう）
		var w := seg - 3.0 * float((i * 7 + 3) % 4)
		if chipped:
			# 欠け＝木口が剥げて光が乗らない。ここで直線が切れる。
			draw_rect(Rect2(sx, cy - 3, w, 4), WOOD_SLAB.darkened(0.42))
			draw_rect(Rect2(sx + 3, cy - 3, w - 6, 2), Color(0.06, 0.04, 0.03, 0.75))
		else:
			draw_rect(Rect2(sx, cy - 3, w, 4),
					Color(WOOD_EDGE.r, WOOD_EDGE.g, WOOD_EDGE.b, clampf(0.16 + 0.80 * g, 0.0, 1.0)))
			draw_rect(Rect2(sx, cy + 1, w, 2),
					Color(1.0, 0.86, 0.60, clampf(0.06 + 0.62 * g, 0.0, 1.0)))
		sx += seg
		i += 1


## 天面の上：席札・おしぼり・出された皿。
func _draw_counter_props(font: Font, cy: float) -> void:
	var occupied := {}
	for c in _custs:
		if String(c["state"]) != "in" and String(c["state"]) != "out":
			occupied[int(c["seat"])] = c
	for i in SEAT_XS.size():
		var x := _seat_x(i)
		# 湯呑（空席でも天面に情報がある）
		var tc := Vector2(x - 45, cy - 6)
		draw_rect(Rect2(tc.x - 9, tc.y, 18, 3), Color(0, 0, 0, 0.4))
		draw_colored_polygon(PackedVector2Array([Vector2(tc.x - 7.5, tc.y - 12), Vector2(tc.x + 7.5, tc.y - 12),
				Vector2(tc.x + 4.5, tc.y), Vector2(tc.x - 4.5, tc.y)]), Color(0.46, 0.44, 0.42))
		draw_rect(Rect2(tc.x - 7.5, tc.y - 13.5, 15, 3), Color(0.30, 0.36, 0.30))
		draw_rect(Rect2(tc.x - 6, tc.y - 10.5, 2, 9), Color(0.78, 0.76, 0.72))
		if not occupied.has(i):
			continue
		var c: Dictionary = occupied[i]
		# 席札（常連＝この席の顔なじみ）
		if bool(c.get("regular", false)):
			var nm := String(c.get("rname", "常連"))
			var nw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.XS)).x
			var pw := q(nw + 14.0)
			var pr := Rect2(q(x - pw * 0.5), cy - 18, pw, 15)
			draw_rect(Rect2(pr.position + Vector2(0, 3), pr.size), Color(0, 0, 0, 0.45))
			draw_rect(pr, Color(0.42, 0.31, 0.18))
			draw_rect(Rect2(pr.position, Vector2(pr.size.x, 2)), Color(0.66, 0.50, 0.30))
			draw_string(font, Vector2(pr.position.x + 7, pr.position.y + 11), nm,
					HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.XS), Color(1.0, 0.90, 0.66))
		# 出された皿。着地でグローと湯気が立つ＝「今この瞬間置かれた」が読める。
		if String(c["state"]) == "eat":
			var s: Dictionary = _script[int(c["serving"])]
			var p := _plate_pos(c, cy)
			var land := clampf((float(c["t"]) - PLATE_FLY) / 0.45, 0.0, 1.0)
			if land > 0.0:
				_glow(p + Vector2(0, -6), lerpf(66.0, 24.0, land), Color(1.0, 0.88, 0.62),
						(1.0 - land) * 0.42)
			if bool(s.get("match", false)):
				_glow(p + Vector2(0, -6), 42.0, CYAN, 0.28)
			_dish(p, 33.0, _dish_kind(String(s["dish"])))
			# 湯気（上へ上る半透明の小矩形×3）
			if land > 0.05:
				for k in 3:
					var wob := sin(_t * 1.9 + k * 2.1) * 6.0
					draw_rect(Rect2(q(p.x - 9.0 + k * 9.0 + wob), q(p.y - 27.0 - k * 9.0), 3, 9),
							Color(1, 1, 1, (0.22 - k * 0.05) * land))


const PLATE_FLY := 0.34      # 店番の手元から席へ皿が飛ぶ時間


## 皿の位置。落下は ease(pt, 2.4) で加速し、着地でいちど2pxめり込ませて戻す。
## 客の腕もここを終点にするので、皿と人が同じ1点を共有する。
func _plate_pos(c: Dictionary, cy: float) -> Vector2:
	var x := _seat_x(int(c["seat"]))
	var t := float(c["t"])
	var pt := clampf(t / PLATE_FLY, 0.0, 1.0)
	var fall := ease(pt, 2.4)
	var px := q(lerpf(size.x * KEEPER_X, x + 51.0, pt))
	var sink := 0.0
	if pt >= 1.0:
		sink = sin(clampf((t - PLATE_FLY) / 0.16, 0.0, 1.0) * PI) * 2.0
	return Vector2(px, cy - 12.0 - (1.0 - fall) * 24.0 + sink)


# ── 客 ────────────────────────────────────────────────────────────────

## 3種の骨格。パレットだけ替えた5人は同じ人にしか見えない——
## 別人にするには「輪郭・姿勢・目線・持ち物」を振る必要がある。
const POSE_STOOP := 0    # 猫背（首が肩に埋まり頭が前に出る。小さく丸い）
const POSE_SQUARE := 1   # いかり肩（肩が張って高い。大柄）
const POSE_PETITE := 2   # 小柄（背が低く頭が相対的に大きい）

# 体格倍率（±25%以上振らないと別人にならない。±7%では同じ人の呼吸に見えた）
const POSE_H := [0.98, 1.18, 0.74]
const POSE_W := [0.98, 1.26, 0.80]
const POSE_HEAD := [1.00, 0.96, 1.16]
const POSE_NECK := [0.62, 1.25, 0.88]   # 首の長さ
const POSE_SLOPE := [10.0, -5.0, 4.0]   # 肩の下がり（負＝いかり肩）
const POSE_HEADDX := [4.5, 0.0, 0.0]    # 頭の前傾

const PROP_NONE := -1
const PROP_UMBRELLA := 0
const PROP_HAT := 1
const PROP_SMOKE := 2


func _cust_spec(c: Dictionary) -> Dictionary:
	var sd := int(c.get("seed", 0))
	var is_reg := bool(c.get("regular", false))
	var seat := int(c.get("seat", 0))
	var pose := sd % 3
	var jitter := float((sd / 3) % 5) * 0.035 - 0.07
	var style := (sd / 11) % 6
	var prop: int = [PROP_UMBRELLA, PROP_HAT, PROP_SMOKE, PROP_NONE][(sd / 13) % 4]
	if prop == PROP_HAT and style == 3:
		prop = PROP_NONE                      # 鳥打帽の上に笠は被らない
	# 目線：隣を見る／店番を見る／うつむく の3状態。全員正面だと「客」ではなく「的」に見える。
	var gaze := (sd / 23) % 3
	var look := 0.0
	var down := false
	match gaze:
		0:  look = 1.0 if seat < 2 else -1.0                              # 隣を見る
		1:  look = signf(KEEPER_X - float(SEAT_XS[seat]))                 # 店番を見る
		_:  down = true                                                   # うつむく
	return {
		"h": CUST_H * (float(POSE_H[pose]) + jitter),
		"sw": 27.0 * (float(POSE_W[pose]) + jitter * 0.6),
		"hr": 21.0 * float(POSE_HEAD[pose]) * (0.96 + float((sd / 9) % 3) * 0.04),
		"pose": pose,
		"look": look,
		"down": down,
		"prop": prop,
		"hair": HAIRS[sd % HAIRS.size()],
		"cloth": CLOTHS[(sd / 5) % CLOTHS.size()] if not is_reg else CLOTHS[(sd / 5) % CLOTHS.size()].lightened(0.10),
		"skin": SKINS[(sd / 7) % SKINS.size()],
		"style": style,
		"accent": c["scarf"],
		"eat": 0.0,
		"reach": Vector2.ZERO,
	}


func _draw_customer(c: Dictionary, cy: float) -> void:
	var st := String(c["state"])
	var walk := st == "in" or st == "out"
	var x := q(float(c["x"]))
	var bob: float = round(absf(sin(_t * 8.0)) * 2.0) * U if walk else round(absf(sin(_t * 1.6)) * 0.6) * U
	var base: float = q(cy + 9.0) - bob
	var sp := _cust_spec(c)
	# 食べている間は腕の終点を皿へ寄せる。腕が届くだけで「その皿はこの人のもの」になる。
	if st == "eat":
		sp["eat"] = clampf((float(c["t"]) - 0.12) / 0.34, 0.0, 1.0)
		sp["reach"] = _plate_pos(c, cy) + Vector2(-15.0, 6.0)
		sp["look"] = 0.0
		sp["down"] = true
	# 影（天面に落ちる接地影）
	draw_rect(Rect2(x - float(sp["sw"]) - 6, cy - SLAB_H, float(sp["sw"]) * 2.0 + 12, 3), Color(0, 0, 0, 0.35))
	# 濃い輪郭 → 暖色のリムライト → 本体
	for o in [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3), Vector2(0, 3)]:
		_person(x + o.x, base + o.y, sp, INK, true)
	# リムライトは提灯のある上側だけ（全周に回すとシール状になる）
	for o2 in [Vector2(0, -3), Vector2(-3, -3)]:
		_person(x + o2.x, base + o2.y, sp, RIM, true)
	_person(x, base, sp, INK, false)


## 手続き描画の人。骨格（pose）・目線（look）・持ち物（prop）が客ごとに違う。
func _person(x: float, base: float, sp: Dictionary, flat: Color, use_flat: bool) -> void:
	var h: float = sp["h"]
	var sw: float = sp["sw"]
	var hr: float = sp["hr"]
	var pose := int(sp.get("pose", 0))
	var look: float = sp.get("look", 0.0)
	var down := bool(sp.get("down", false))
	var eat: float = sp.get("eat", 0.0)
	var reach: Vector2 = sp.get("reach", Vector2.ZERO)
	var hair: Color = flat if use_flat else sp["hair"]
	var cloth: Color = flat if use_flat else sp["cloth"]
	var skin: Color = flat if use_flat else sp["skin"]
	var top := base - h
	var slope: float = POSE_SLOPE[pose]
	var hx := x + float(POSE_HEADDX[pose]) * (0.6 if down else 1.0)
	var hcy := top + hr + 3.0 + (3.0 if pose == POSE_STOOP else 0.0)
	var sy := top + hr * 2.0 + 12.0 * float(POSE_NECK[pose])   # 肩の高さ
	var style := int(sp["style"])

	# 傘は体の後ろ（外形を変えるので輪郭パスでも描く）
	if int(sp.get("prop", PROP_NONE)) == PROP_UMBRELLA:
		var ux := x - sw - 12.0
		draw_rect(Rect2(q(ux), q(sy - 21.0), 5, base - sy + 21.0), flat if use_flat else Color(0.20, 0.22, 0.30))
		draw_rect(Rect2(q(ux - 3), q(sy - 30.0), 11, 12), flat if use_flat else Color(0.24, 0.26, 0.36))
		draw_rect(Rect2(q(ux - 9), q(sy - 33.0), 9, 5), flat if use_flat else Color(0.42, 0.30, 0.18))

	# 髪（後ろ髪：頭より一回り大きい）
	if style == 1:
		draw_rect(Rect2(hx - hr - 3, hcy - hr, hr * 2.0 + 6, hr + (sy - hcy) + 21), hair)
	_pxcircle(Vector2(hx, hcy - 3), int(round((hr + 3.0) / U)), hair)
	# 首（猫背は短く肩に埋まる）
	var neck_w: float = 15.0 if pose != POSE_SQUARE else 18.0
	draw_rect(Rect2(hx - neck_w * 0.5, hcy + hr - 6, neck_w, maxf(sy - (hcy + hr) + 9.0, 6.0)), skin.darkened(0.25))
	# 胴（首→肩の傾斜→腰）。slope が肩の張りをつくる。
	draw_colored_polygon(PackedVector2Array([
			Vector2(hx - 10.5, sy - 15), Vector2(x - sw, sy + 3 + slope), Vector2(x - sw * 0.95, base),
			Vector2(x + sw * 0.95, base), Vector2(x + sw, sy + 3 + slope), Vector2(hx + 10.5, sy - 15)]), cloth)
	if not use_flat:
		# 服の陰影と前立て（べた塗りを避けて布に見せる）
		draw_colored_polygon(PackedVector2Array([
				Vector2(hx - 10.5, sy - 15), Vector2(x - sw, sy + 3 + slope), Vector2(x - sw * 0.95, base),
				Vector2(x - sw * 0.45, base), Vector2(x - sw * 0.42, sy - 6)]),
				Color(0, 0, 0, 0.20))
		draw_rect(Rect2(x - 2, sy - 6, 4, base - sy + 6), cloth.darkened(0.35))
		draw_rect(Rect2(x - sw * 0.55, sy - 4 + slope * 0.4, 6, 4), cloth.lightened(0.25))
		draw_rect(Rect2(x + sw * 0.55 - 6, sy - 4 + slope * 0.4, 6, 4), cloth.lightened(0.25))
	# 腕。通常は天面へ、食事中は右腕の終点を皿へ寄せる（＝皿と人が繋がる）。
	var arm_y := base - 27.0
	for s in [-1.0, 1.0]:
		var sh := Vector2(x + s * (sw - 3), sy + slope * 0.6)
		var hand := Vector2(x + s * (sw + 4.5), arm_y)
		if eat > 0.0 and s > 0.0 and reach != Vector2.ZERO:
			hand = hand.lerp(reach, eat)
		var d := (hand - sh)
		if d.length() < 1.0:
			d = Vector2(0, 1)
		var nrm := Vector2(-d.y, d.x).normalized() * 7.5
		draw_colored_polygon(PackedVector2Array([sh - nrm, sh + nrm, hand + nrm, hand - nrm]),
				cloth.darkened(0.28))
		if not use_flat:
			draw_rect(Rect2(q(hand.x - 7.5), q(hand.y - 7.5), 15, 10.5), skin)
	# 顔
	_pxcircle(Vector2(hx, hcy), int(round(hr / U)), skin)
	draw_rect(Rect2(hx - hr * 0.72, hcy, hr * 1.44, hr * 0.9), skin)
	# 前髪・髪型
	if not use_flat:
		_hair_style(hx, hcy, hr, style, hair, cloth)
		# 目と口。look で横へ、うつむきで下へずらす＝「会話している店内」になる。
		var lx := look * hr * 0.22
		var ey := hcy + 2.0 + (5.0 if down else 0.0)
		var eye := Color(0.10, 0.07, 0.09)
		draw_rect(Rect2(q(hx - hr * 0.56 + lx), q(ey), 4, 6 if not down else 3), eye)
		draw_rect(Rect2(q(hx + hr * 0.24 + lx), q(ey), 4, 6 if not down else 3), eye)
		draw_rect(Rect2(q(hx - hr * 0.56 + lx), q(ey - 5), 5, 2), hair.darkened(0.2))
		draw_rect(Rect2(q(hx + hr * 0.24 + lx), q(ey - 5), 5, 2), hair.darkened(0.2))
		draw_rect(Rect2(q(hx - 3 + lx * 0.7), q(ey + 11), 7, 3), Color(0.34, 0.16, 0.16, 0.85))
		# 頬にかかる提灯の光
		draw_rect(Rect2(q(hx - hr * 0.92), q(hcy - hr * 0.35), 5, 12), Color(1.0, 0.86, 0.62, 0.28))
		# 差し色（マフラー／襟）
		var cy_collar := maxf(sy - 15.0, hcy + hr - 1.0)
		draw_rect(Rect2(hx - 15, cy_collar, 30, 10), (sp["accent"] as Color).darkened(0.15))
		draw_rect(Rect2(hx - 15, cy_collar, 30, 3), (sp["accent"] as Color).lightened(0.15))
	else:
		_hair_style(hx, hcy, hr, style, flat, flat)
	# 笠と煙草（頭・手の外形を変える持ち物）
	_person_prop(sp, hx, hcy, hr, x, sw, arm_y, flat, use_flat)


## 持ち物。シルエットの外形を変えるのが目的なので、輪郭パスでも同じ形を描く。
func _person_prop(sp: Dictionary, hx: float, hcy: float, hr: float, x: float, sw: float,
		arm_y: float, flat: Color, use_flat: bool) -> void:
	match int(sp.get("prop", PROP_NONE)):
		PROP_HAT:
			# 笠。つばで頭の輪郭は変えるが、目線が読めないと客が「人」でなくなるので
			# 縁は眉の上まで。顔は必ず出す。
			var brim := hr * 1.55
			var col: Color = flat if use_flat else Color(0.62, 0.50, 0.28)
			draw_colored_polygon(PackedVector2Array([
					Vector2(hx - brim, hcy - hr * 0.72), Vector2(hx, hcy - hr - 15.0),
					Vector2(hx + brim, hcy - hr * 0.72)]), col)
			draw_rect(Rect2(q(hx - brim), q(hcy - hr * 0.72), q(brim * 2.0), 4),
					flat if use_flat else Color(0.44, 0.34, 0.18))
		PROP_SMOKE:
			# 煙草（手の先に一本＋立ちのぼる煙）
			var sx := x + sw + 12.0
			draw_rect(Rect2(q(sx), q(arm_y - 12.0), 9, 4), flat if use_flat else Color(0.90, 0.88, 0.82))
			draw_rect(Rect2(q(sx + 9), q(arm_y - 12.0), 4, 4), flat if use_flat else Color(1.0, 0.52, 0.22))
			if not use_flat:
				for k in 3:
					var wob := sin(_t * 1.3 + k * 1.7) * 6.0
					draw_rect(Rect2(q(sx + 9 + wob), q(arm_y - 24.0 - k * 12.0), 3, 8),
							Color(1, 1, 1, 0.16 - k * 0.04))
		_:
			pass


func _hair_style(x: float, hcy: float, hr: float, style: int, hair: Color, cloth: Color) -> void:
	var fringe := hcy - hr - 3.0            # 生え際の上端
	match style:
		0:   # 短髪（前髪をまっすぐ・こめかみを残す）
			draw_rect(Rect2(x - hr, fringe, hr * 2.0, hr * 0.52), hair)
			draw_rect(Rect2(x - hr - 3, fringe, 6, hr * 0.95), hair)
			draw_rect(Rect2(x + hr - 3, fringe, 6, hr * 0.95), hair)
		1:   # 長髪（サイドが肩まで）
			draw_rect(Rect2(x - hr, fringe, hr * 2.0, hr * 0.44), hair)
			draw_rect(Rect2(x - hr - 3, hcy - hr, 7.5, hr * 2.1), hair)
			draw_rect(Rect2(x + hr - 4.5, hcy - hr, 7.5, hr * 2.1), hair)
		2:   # 団子頭（かんざし付き）
			draw_rect(Rect2(x - hr, fringe, hr * 2.0, hr * 0.40), hair)
			_pxcircle(Vector2(x, fringe - hr * 0.34), maxi(int(round((hr * 0.46) / U)), 1), hair)
			draw_rect(Rect2(x - hr * 0.6, fringe - hr * 0.40, hr * 1.2, 3), Color(0.85, 0.66, 0.30))
		3:   # 帽子（鳥打帽）
			draw_rect(Rect2(x - hr - 1.5, hcy - hr - 7.5, hr * 2.0 + 3, hr * 0.72), cloth.lightened(0.14))
			draw_rect(Rect2(x - hr - 1.5, hcy - hr - 7.5, hr * 2.0 + 3, 3), cloth.lightened(0.34))
			draw_rect(Rect2(x - hr - 10.5, hcy - hr * 0.42, hr * 2.0 + 21, 6), cloth.darkened(0.28))
			draw_rect(Rect2(x - hr, hcy - hr * 0.42 - 3, hr * 2.0, 4), hair)
		4:   # 逆立った髪
			draw_rect(Rect2(x - hr, fringe, hr * 2.0, hr * 0.44), hair)
			for i in 3:
				var sx := x - hr * 0.72 + i * hr * 0.72
				draw_colored_polygon(PackedVector2Array([Vector2(sx - 7.5, fringe + 3),
						Vector2(sx + 3, fringe - hr * 0.66), Vector2(sx + 7.5, fringe + 3)]), hair)
		5:   # ポニーテール
			draw_rect(Rect2(x - hr, fringe, hr * 2.0, hr * 0.46), hair)
			_pxcircle(Vector2(x + hr + 4.5, hcy - 3), maxi(int(round((7.5) / U)), 1), hair)
			_pxcircle(Vector2(x + hr + 7.5, hcy + 10.5), maxi(int(round((6.0) / U)), 1), hair)
			draw_rect(Rect2(x + hr - 3, hcy - 12, 6, 9), Color(0.85, 0.35, 0.45))
		_:
			draw_rect(Rect2(x - hr, fringe, hr * 2.0, hr * 0.52), hair)


## 頭上の吹き出し：注文の料理アイコンが入る（デイブの注文表示）。
func _draw_bubble(font: Font, c: Dictionary, cy: float) -> void:
	var st := String(c["state"])
	if st != "wait" and st != "deny":
		return
	var x := q(float(c["x"]))
	var sp := _cust_spec(c)
	var top := q(cy + 9.0) - float(sp["h"])
	var bw := 78.0
	var bh := 66.0
	var by := q(top - bh - 18.0)
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	var accent := GOLD if st == "wait" else DENY
	var bx := clampf(q(x - bw * 0.5), 6.0, size.x - bw - 6.0)
	var r := Rect2(bx, by, bw, bh)
	_glow(Vector2(x, by + bh * 0.5), 78.0, accent, 0.14 + 0.12 * pulse)
	# しっぽ
	draw_colored_polygon(PackedVector2Array([Vector2(x - 10.5, by + bh - 3), Vector2(x + 10.5, by + bh - 3),
			Vector2(x + 1.5, by + bh + 18)]), Color(0.97, 0.95, 0.92, 0.97))
	_panel(r, Color(0.97, 0.95, 0.92, 0.97), Color(accent.r, accent.g, accent.b, 0.5 + 0.5 * pulse), 10, 2.0)
	if st == "wait":
		var s: Dictionary = _script[int(c["serving"])]
		_dish(Vector2(bx + bw * 0.5, by + bh * 0.62), 54.0, _dish_kind(String(s["dish"])), true)
		if bool(s.get("match", false)):
			_pxcircle(Vector2(bx + bw - 15, by + 15), maxi(int(round((10.0) / U)), 1), Color(0.20, 0.62, 0.78))
			_sh(font, Vector2(bx + bw - 21, by + 20), "★", int(FS.XS), Color(0.95, 1.0, 1.0))
	else:
		_pxdiag(Vector2(bx + 21, by + 18), Vector2(bx + bw - 21, by + bh - 18), Color(0.75, 0.25, 0.22), 2)
		_pxdiag(Vector2(bx + bw - 21, by + 18), Vector2(bx + 21, by + bh - 18), Color(0.75, 0.25, 0.22), 2)


# ── 店番 ──────────────────────────────────────────────────────────────

func _draw_keeper(sz: Vector2, cy: float) -> void:
	var kx := q(sz.x * KEEPER_X)
	_glow(Vector2(kx, cy - KEEPER_H * 0.55), 150.0, LANT_WARM, 0.24)
	if _keeper_frames.is_empty():
		return
	var tex: Texture2D = _keeper_frames[int(_t * 3.0) % _keeper_frames.size()]
	if tex == null:
		return
	var kh := q(KEEPER_H)
	var kw := q(kh * tex.get_width() / float(tex.get_height()))
	var kr := Rect2(q(kx - kw * 0.5), q(cy - 12.0 - kh), kw, kh)
	# 足元の影
	draw_rect(Rect2(kr.position.x + 6, cy - 18, kr.size.x - 12, 6), Color(0, 0, 0, 0.45))
	draw_texture_rect(tex, kr, false)


## 高解像度スプライトをドット絵化（縮小＋α2値化）。3pxモジュールに密度を揃える。
##
## マゼンタ矩形が出ていた原因はここ。素材の「抜いた」画素は α=0 でも RGB に
## マゼンタが残っている。素の resize は透明画素の RGB まで平均に混ぜるので、
## 縮小で生まれた中間 α が 0.42 を超えた瞬間、不透明なマゼンタとして焼き付く。
## 対策は 3 段構え：
##   (1) 焼き込みの不透明地は _strip_matte で resize の前に抜く（縮小後だと
##       隅の色が混ざって判定が落ちるので、必ず convert 直後）。
##   (2) 乗算済みαで縮小する＝透明画素は色を持ち込まない（にじみの根治）。
##   (3) それでも残った異常は _warm_up 側で捨てる。
func _pix(path: String, pix_h: int) -> Texture2D:
	var key := "%s:%d" % [path, pix_h]
	if _pix_cache.has(key):
		return _pix_cache[key]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		var src: Texture2D = load(path)
		var img: Image = src.get_image() if src != null else null
		if img != null:
			img = img.duplicate()
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			_strip_matte(img)
			# 乗算済みαへ（透明画素の RGB を 0 にしてから縮小する）
			var sw := img.get_width()
			var sh := img.get_height()
			for y in sh:
				for x in sw:
					var sc := img.get_pixel(x, y)
					img.set_pixel(x, y, Color(sc.r * sc.a, sc.g * sc.a, sc.b * sc.a, sc.a))
			var w := maxi(int(round(sw * float(pix_h) / maxf(sh, 1.0))), 1)
			img.resize(w, pix_h, Image.INTERPOLATE_BILINEAR)
			for y in img.get_height():
				for x in w:
					var col := img.get_pixel(x, y)
					if col.a > 0.42:
						# 乗算済みを戻す。α で割らないと縁が黒ずむ。
						var inv := 1.0 / maxf(col.a, 0.001)
						img.set_pixel(x, y, Color(clampf(col.r * inv, 0.0, 1.0),
								clampf(col.g * inv, 0.0, 1.0), clampf(col.b * inv, 0.0, 1.0), 1.0))
					else:
						img.set_pixel(x, y, Color(0, 0, 0, 0))
			t = ImageTexture.create_from_image(img)
	_pix_cache[key] = t
	return t


## 一部の生成フレームは背景（マゼンタ/白）が不透明で焼き込まれており、そのまま描くと
## キャラの後ろに色板が出る。bbox の4隅が同色なら「地」とみなし、画像の縁から連結した
## 同色だけを抜く（キャラ内部の同系色は残る）。dive_side_view.gd と同等の処理。
func _strip_matte(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	if w < 6 or h < 6:
		return
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.5:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 - x0 < 4 or y1 - y0 < 4:
		return
	# 「地」は矩形なので bbox の4隅が同色なら焼き込み背景。
	# （キャラのシルエットなら隅は透明か色がばらけるので誤爆しない）
	var corners := [Vector2i(x0 + 1, y0 + 1), Vector2i(x1 - 1, y0 + 1),
			Vector2i(x0 + 1, y1 - 1), Vector2i(x1 - 1, y1 - 1)]
	var counts := {}
	var seeds := {}
	for p: Vector2i in corners:
		var c := img.get_pixel(p.x, p.y)
		if c.a < 0.5:
			continue
		var k := "%d_%d_%d" % [int(c.r * 12), int(c.g * 12), int(c.b * 12)]
		counts[k] = int(counts.get(k, 0)) + 1
		seeds[k] = c
	var best := ""
	var bestn := 0
	for k in counts:
		if int(counts[k]) > bestn:
			bestn = int(counts[k])
			best = k
	if best == "" or bestn < 3:
		return
	var sd: Color = seeds[best]
	var seen := PackedByteArray()
	seen.resize(w * h)
	var qq: Array[Vector2i] = []
	for x in w:
		qq.append(Vector2i(x, 0))
		qq.append(Vector2i(x, h - 1))
	for y in h:
		qq.append(Vector2i(0, y))
		qq.append(Vector2i(w - 1, y))
	var i := 0
	while i < qq.size():
		var p: Vector2i = qq[i]
		i += 1
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
			continue
		var key2 := p.y * w + p.x
		if seen[key2] != 0:
			continue
		var c := img.get_pixel(p.x, p.y)
		if c.a > 0.5 and absf(c.r - sd.r) + absf(c.g - sd.g) + absf(c.b - sd.b) > 0.28:
			continue
		seen[key2] = 1
		img.set_pixel(p.x, p.y, Color(c.r, c.g, c.b, 0.0))
		qq.append(Vector2i(p.x + 1, p.y))
		qq.append(Vector2i(p.x - 1, p.y))
		qq.append(Vector2i(p.x, p.y + 1))
		qq.append(Vector2i(p.x, p.y - 1))


## 生成済みフレームの健全性検査。四隅が不透明＝地が抜けていないので使わない。
func _frame_ok(t: Texture2D) -> bool:
	if t == null:
		return false
	var img := t.get_image()
	if img == null:
		return false
	var w := img.get_width()
	var h := img.get_height()
	if w < 4 or h < 4:
		return false
	for p in [Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, h - 1), Vector2i(w - 1, h - 1),
			Vector2i(w / 2, 0), Vector2i(w / 2, h - 1)]:
		if img.get_pixel(p.x, p.y).a > 0.5:
			return false
	# 画面いっぱいのべた板（＝地が残っている）も弾く
	var opq := 0
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			if img.get_pixel(x, y).a > 0.5:
				opq += 1
	return float(opq) / float(maxi((h / 2) * (w / 2), 1)) < 0.88


# ── 土間 ──────────────────────────────────────────────────────────────

## カウンターと提灯の反射・スキャンライン・黒猫。無情報の黒を作らない。
func _draw_floor(sz: Vector2, cy: float, floor_y: float, rec_top: float) -> void:
	var h := rec_top - floor_y
	if h <= 0.0:
		return
	# 背景の半透明コピーを反転して敷くのはやめた（描画バグにしか見えない）。
	# 濡れた土間に落ちるのは「提灯の光柱」だけ。sin で横に蛇行し、下ほど幅が広がる。
	_vgrad(Rect2(0, floor_y, sz.x, 48.0), Color(0.30, 0.20, 0.13, 0.30), Color(0.30, 0.20, 0.13, 0.0))
	# 反射を下へ向けて消す
	_vgrad(Rect2(0, floor_y, sz.x, h), Color(FLOOR_C.r, FLOOR_C.g, FLOOR_C.b, 0.0),
			Color(FLOOR_C.r, FLOOR_C.g, FLOOR_C.b, 0.95))
	# 光柱は暗幕の上に落とす（下に敷くと自分の落とす影に消される）
	var lant_fx := [0.22, 0.50, 0.78]
	for li in 3:
		var lx := q(sz.x * float(lant_fx[li]))
		var col_h := h * (0.90 if li == 1 else 0.66)
		var base_w := 21.0 if li == 1 else 15.0
		var peak := 0.30 if li == 1 else 0.20
		var yy := floor_y
		while yy < floor_y + col_h:
			var f := (yy - floor_y) / maxf(col_h, 1.0)
			var wdt := q(base_w * lerpf(1.0, 1.6, f))
			var wob := sin(f * 5.2 + _t * 0.8 + li * 2.1) * 12.0 * f
			var a := (1.0 - f) * (1.0 - f) * peak
			draw_rect(Rect2(q(lx - wdt * 0.5 + wob), yy, wdt, U), Color(1.0, 0.74, 0.40, a))
			yy += U
	# 灯だまり
	_glow(Vector2(sz.x * 0.5, floor_y + 30.0), sz.x * 0.55, LANT_WARM, 0.10)
	_glow(Vector2(sz.x * 0.22, floor_y + 66.0), 132.0, LANT_WARM, 0.07)
	_glow(Vector2(sz.x * 0.78, floor_y + 66.0), 132.0, LANT_WARM, 0.07)
	# スキャンライン（3px間隔）
	var yy := floor_y
	while yy < rec_top:
		draw_rect(Rect2(0, yy, sz.x, 1), Color(1, 1, 1, 0.02))
		yy += 3.0
	# 石畳の目地（横＋縦。土間を「床」として読ませる）
	var rows := 5
	for i in rows:
		var ly := q(floor_y + 24.0 + i * 39.0)
		if ly < rec_top - 6.0:
			draw_rect(Rect2(0, ly, sz.x, 1.5), Color(1, 1, 1, 0.045))
			var cols := 4 + i
			for k in cols:
				var vx := q(sz.x * (k + 0.5) / cols + (i % 2) * 18.0)
				draw_rect(Rect2(vx, ly, 1.5, minf(39.0, rec_top - ly)), Color(1, 1, 1, 0.028))
	_draw_cat(Vector2(q(sz.x * (0.5 + 0.30 * sin(_t * 0.25))), q(rec_top - 27.0)))
	# 手前の荷（蒸籠と木箱）— 前景のシルエットで奥行きを作り、黒い平面を潰す
	_draw_seiro(Vector2(q(sz.x * 0.13), rec_top - 6.0))
	_draw_crates(Vector2(q(sz.x * 0.87), rec_top - 6.0))


## 積み上げた蒸籠（湯気つき）。手前の暗いシルエット＋提灯側のリムライト。
func _draw_seiro(base: Vector2) -> void:
	var wood := Color(0.30, 0.21, 0.13)
	var rim := Color(0.72, 0.52, 0.26)
	draw_rect(Rect2(base.x - 60, base.y - 6, 120, 6), Color(0, 0, 0, 0.45))
	for i in 4:
		var y := base.y - 6.0 - i * 21.0
		var w := 108.0
		var band := wood.darkened(i * 0.07)
		draw_rect(Rect2(base.x - w * 0.5, y - 21, w, 21), band)
		draw_rect(Rect2(base.x - w * 0.5, y - 21, w, 3), rim)              # 天面の光
		draw_rect(Rect2(base.x - w * 0.5, y - 6, w, 6), band.darkened(0.4))  # 段の影
		draw_rect(Rect2(base.x - w * 0.5, y - 21, 3, 21), rim.darkened(0.35))
		for k in 3:
			draw_rect(Rect2(q(base.x - w * 0.5 + 12.0 + k * (w - 24.0) / 3.0), y - 15, 3, 9),
					Color(0, 0, 0, 0.25))
	# 一番上は蓋（編み目）
	var ty := base.y - 6.0 - 4 * 21.0
	draw_rect(Rect2(base.x - 57, ty - 15, 114, 15), wood.lightened(0.12))
	draw_rect(Rect2(base.x - 57, ty - 15, 114, 3), rim.lightened(0.12))
	for k in 5:
		draw_rect(Rect2(q(base.x - 45.0 + k * 21.0), ty - 12, 3, 12), Color(0, 0, 0, 0.22))
	# 立ちのぼる湯気
	var top := base.y - 6.0 - 4 * 21.0 - 18.0
	for k in 3:
		var w2 := sin(_t * 1.6 + k) * 6.0
		draw_rect(Rect2(q(base.x - 18.0 + k * 18.0 + w2), q(top - 18.0 - k * 6.0), 3, 15),
				Color(1, 1, 1, 0.07))
	_glow(Vector2(base.x, top), 96.0, LANT_WARM, 0.06)


## 酒箱の山。
func _draw_crates(base: Vector2) -> void:
	var dark := Color(0.26, 0.185, 0.115)
	var rim := Color(0.70, 0.50, 0.24)
	draw_rect(Rect2(base.x - 60, base.y - 6, 120, 6), Color(0, 0, 0, 0.45))
	var boxes := [Vector2(0, 0), Vector2(-15, -48), Vector2(18, -96)]
	for i in boxes.size():
		var o: Vector2 = boxes[i]
		var r := Rect2(base.x + o.x - 48, base.y + o.y - 48, 96, 48)
		draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.35))
		draw_rect(r, dark.darkened(i * 0.06))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), rim)
		draw_rect(Rect2(r.position, Vector2(3, r.size.y)), rim.darkened(0.4))
		_pxdiag(r.position + Vector2(6, 6), r.position + r.size - Vector2(6, 6), Color(0, 0, 0, 0.35))
		_pxdiag(r.position + Vector2(r.size.x - 6, 6), r.position + Vector2(6, r.size.y - 6),
				Color(0, 0, 0, 0.35))
		draw_rect(Rect2(r.position.x + 27, r.position.y + 15, 42, 18), Color(0.85, 0.68, 0.32, 0.30))
		draw_rect(Rect2(r.position.x + 33, r.position.y + 21, 30, 3), Color(0.20, 0.12, 0.07, 0.8))
		draw_rect(Rect2(r.position.x + 33, r.position.y + 27, 21, 3), Color(0.20, 0.12, 0.07, 0.8))


## 店名の主・黒猫。土間をゆっくり往復し、尻尾だけがネオンの間で揺れる。
func _draw_cat(pos: Vector2) -> void:
	var dirx: float = signf(cos(_t * 0.25))
	var body := Color(0.035, 0.032, 0.055)
	draw_rect(Rect2(pos.x - 27, pos.y + 8, 54, 6), Color(0, 0, 0, 0.4))
	_ellipse(pos, Vector2(24, 12), body)
	# 脚（歩いている）
	for s in [-1.0, 1.0]:
		draw_rect(Rect2(pos.x + s * 12.0 - 3, pos.y + 4, 6, 10), body)
	var hx := pos.x + 20.0 * dirx
	_pxcircle(Vector2(hx, pos.y - 9), maxi(int(round((10.5) / U)), 1), body)
	draw_colored_polygon(PackedVector2Array([Vector2(hx - 9, pos.y - 14),
			Vector2(hx - 3, pos.y - 25), Vector2(hx + 1, pos.y - 13)]), body)
	draw_colored_polygon(PackedVector2Array([Vector2(hx + 9, pos.y - 14),
			Vector2(hx + 3, pos.y - 25), Vector2(hx - 1, pos.y - 13)]), body)
	draw_rect(Rect2(q(hx + 1.5 * dirx), q(pos.y - 12), 4, 4), Color(1.0, 0.82, 0.4, 0.95))
	draw_rect(Rect2(q(hx - 6.0 * dirx), q(pos.y - 12), 4, 4), Color(1.0, 0.82, 0.4, 0.75))
	var tx := pos.x - 21.0 * dirx
	var sway := sin(_t * 2.2) * 7.5
	_pxdiag(Vector2(tx, pos.y - 3), Vector2(tx - 14.0 * dirx + sway * 0.4, pos.y - 24 - absf(sway) * 0.4),
			body)


# ── 今夜の伝票 ────────────────────────────────────────────────────────

## 下部の死に領域を報酬パネルへ。配膳済みの皿を左から積み、売上を大きく出す。
func _draw_receipt(font: Font, r: Rect2) -> void:
	# 木のボード
	draw_rect(Rect2(r.position + Vector2(0, 6), r.size), Color(0, 0, 0, 0.5))
	_vgrad(r, Color(0.135, 0.098, 0.082), Color(0.075, 0.058, 0.058))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color(0.42, 0.30, 0.18))
	draw_rect(Rect2(r.position.x, r.position.y + r.size.y - 3, r.size.x, 3), Color(0.04, 0.03, 0.03))
	for i in int(r.size.y / 24.0):
		draw_rect(Rect2(r.position.x + 6, q(r.position.y + 15.0 + i * 24.0), r.size.x - 12, 1),
				Color(1, 1, 1, 0.022))
	# 見出し
	var hx := r.position.x + 21.0
	var hy := r.position.y + 36.0
	draw_rect(Rect2(hx - 9, hy - 15, 4, 18), GOLD)
	_sh(font, Vector2(hx, hy), "今夜の伝票", int(FS.M), TEXT)
	var sub := "%d / %d 皿" % [_served_shown, maxi(_total, 1)]
	var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.S)).x
	_sh(font, Vector2(r.position.x + r.size.x - 21 - sw, hy), sub, int(FS.S), TEXT_DIM)
	if _matched > 0:
		var mt := "★予報的中 %d" % _matched
		var mw := font.get_string_size(mt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.S)).x
		_sh(font, Vector2(r.position.x + r.size.x - 21 - sw - mw - 18, hy), mt, int(FS.S), CYAN)
	# 進捗バー（空の伝票でも「これから埋まる夜」が見える）
	var pb := Rect2(r.position.x + 18, hy + 12, r.size.x - 36, 6)
	draw_rect(pb, Color(0, 0, 0, 0.45))
	draw_rect(Rect2(pb.position, Vector2(pb.size.x, 1.5)), Color(1, 1, 1, 0.08))
	var frac := clampf(float(_served_shown) / maxf(_total, 1.0), 0.0, 1.0)
	if frac > 0.0:
		var fw := maxf(pb.size.x * frac, 6.0)
		draw_rect(Rect2(pb.position, Vector2(fw, pb.size.y)), GOLD)
		draw_rect(Rect2(pb.position, Vector2(fw, 2)), Color(1.0, 0.94, 0.72))
		_glow(Vector2(pb.position.x + fw, pb.position.y + 3), 33.0, GOLD, 0.45)

	# 皿のスロット（今夜の客数ぶん。埋まった順に料理アイコン）
	var gy := r.position.y + r.size.y - 33.0
	var slots := clampi(maxi(_total, _script.size()), 1, 24)
	var band_top := hy + 24.0
	var band_h := (gy - 78.0) - band_top
	var pitch := 48.0
	var cols := 1
	var rows := 1
	for p in [78.0, 66.0, 60.0, 54.0, 48.0, 42.0]:
		pitch = p
		cols = maxi(int((r.size.x - 42.0) / p), 1)
		rows = int(ceil(slots / float(cols)))
		if rows * p <= band_h:
			break
	var ox := r.position.x + 21.0 + (r.size.x - 42.0 - cols * pitch) * 0.5
	var oy := band_top + (band_h - rows * pitch) * 0.5
	var ring := pitch * 0.44
	var ru := maxi(int(round(ring / U)), 2)     # 皿スロットは3px単位の円環で打つ
	for i in slots:
		var cx := q(ox + (i % cols) * pitch + pitch * 0.5)
		var cyy := q(oy + int(i / cols) * pitch + pitch * 0.5)
		if i < _plates.size():
			var pl: Dictionary = _plates[i]
			if bool(pl["match"]):
				_glow(Vector2(cx, cyy), ring * 2.2, CYAN, 0.30)
				_pxring(Vector2(cx, cyy), ru, Color(CYAN.r, CYAN.g, CYAN.b, 0.9))
			else:
				_pxring(Vector2(cx, cyy), ru, Color(1, 1, 1, 0.16))
			_dish(Vector2(cx, cyy + pitch * 0.13), pitch * 0.62, int(pl["kind"]))
		else:
			# 未配膳＝伏せた空皿。これから埋まる余白として読ませる
			_pxring(Vector2(cx, cyy), ru, Color(1, 1, 1, 0.11))
			_ellipse(Vector2(cx, cyy + pitch * 0.08), Vector2(ring * 0.72, ring * 0.27), Color(1, 1, 1, 0.09))
			_ellipse(Vector2(cx, cyy + pitch * 0.05), Vector2(ring * 0.52, ring * 0.19), Color(0, 0, 0, 0.30))

	# 売上（大きく・コイン付き・カウントアップ）
	draw_rect(Rect2(r.position.x + 18, gy - 63, r.size.x - 36, 1.5), Color(1, 1, 1, 0.10))
	var coin := Vector2(r.position.x + 45.0, gy - 21.0)
	var pk := 1.0 if _pop <= 0.0 else 1.0 + 0.25 * sin((1.0 - _pop / 0.18) * PI)
	_glow(coin, 60.0, GOLD, 0.22)
	draw_set_transform(coin, 0.0, Vector2(pk, pk))
	_coin(Vector2.ZERO, 21.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var gs := "%d" % int(round(_gold_disp))
	var gw := font.get_string_size(gs, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.XL)).x
	var gp := Vector2(coin.x + 36.0, gy)
	draw_set_transform(gp, 0.0, Vector2(pk, pk))
	draw_string(font, Vector2(2, 3), gs, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.XL), Color(0, 0, 0, 0.6))
	draw_string(font, Vector2.ZERO, gs, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.XL), Color(1.0, 0.88, 0.52))
	draw_string(font, Vector2(gw + 6, -2), "G", HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.L), Color(0.85, 0.66, 0.34))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_sh(font, Vector2(coin.x - 21.0, gy - 51.0), "今夜の売上", int(FS.XS), TEXT_DIM)
	# 右下は空けない。伝票の朱印（毎晩必ず捺す）＋チップを常時置いて、
	# 平均輝度9の死に領域を潰す。チップも金色＝シアンは「予報的中」専用に戻す。
	var stamp := Vector2(q(r.position.x + r.size.x - 51.0), q(gy - 24.0))
	var seal := Color(0.74, 0.20, 0.17, 0.92)
	_glow(stamp, 66.0, Color(0.95, 0.32, 0.24), 0.10)
	_pxring(stamp, 9, seal, 1)
	_pxring(stamp, 6, Color(seal.r, seal.g, seal.b, 0.5), 1)
	draw_rect(Rect2(stamp.x - 9, stamp.y - 3, 18, 3), seal)
	draw_rect(Rect2(stamp.x - 3, stamp.y - 9, 6, 18), seal)
	draw_rect(Rect2(stamp.x - 9, stamp.y + 6, 18, 3), seal)
	_sh(font, Vector2(stamp.x - 24.0, stamp.y + 39.0), "夜%d" % day, int(FS.XS), TEXT_DIM)
	var ts := ("チップ +%dG" % _tips) if _tips > 0 else "チップ　—"
	var tcol := GOLD if _tips > 0 else TEXT_DIM
	var tw := font.get_string_size(ts, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.M)).x
	if _tips > 0:
		_glow(Vector2(stamp.x - 39.0 - tw * 0.5, gy - 15), 90.0, GOLD, 0.14)
	_sh(font, Vector2(stamp.x - 39.0 - tw, gy - 9), ts, int(FS.M), tcol)


func _coin(c: Vector2, r: float) -> void:
	_pxcircle(c, maxi(int(round((r) / U)), 1), Color(0.55, 0.38, 0.12))
	_pxcircle(c, maxi(int(round((r - 2.0) / U)), 1), Color(1.0, 0.80, 0.32))
	_pxcircle(c - Vector2(r * 0.22, r * 0.22), maxi(int(round((r * 0.62) / U)), 1), Color(1.0, 0.92, 0.60))
	draw_rect(Rect2(c.x - r * 0.26, c.y - r * 0.26, r * 0.52, r * 0.52), Color(0.42, 0.28, 0.09))
	draw_rect(Rect2(c.x - r * 0.16, c.y - r * 0.16, r * 0.32, r * 0.32), Color(0.62, 0.44, 0.16))


# ── 料理アイコン ──────────────────────────────────────────────────────

func _dish_kind(name: String) -> int:
	if name.contains("麺"):
		return 0
	if name.contains("麻婆") or name.contains("火鍋"):
		return 1
	if name.contains("湯") or name.contains("雲呑"):
		return 2
	if name.contains("飯"):
		return 3
	if name.contains("粥"):
		return 4
	if name.contains("杏仁") or name.contains("パフェ"):
		return 5
	if name.contains("団子"):
		return 6
	return 7


## 料理アイコン（s は一辺の目安）。吹き出しにも伝票にも同じ絵を使う。
func _dish(c: Vector2, s: float, kind: int, on_light := false) -> void:
	var u := s / 12.0
	var shadow := Color(0, 0, 0, 0.30 if on_light else 0.45)
	draw_rect(Rect2(c.x - s * 0.42, c.y + u * 1.2, s * 0.84, u * 0.8), shadow)
	var bowl_out := Color(0.86, 0.84, 0.82)
	var bowl_in := Color(0.62, 0.60, 0.62)
	match kind:
		0:   # 麺
			_bowl(c, s, Color(0.90, 0.88, 0.86), Color(0.30, 0.22, 0.18))
			draw_rect(Rect2(c.x - s * 0.30, c.y - u * 1.6, s * 0.60, u * 1.1), Color(0.92, 0.80, 0.42))
			for i in 3:
				draw_rect(Rect2(q(c.x - s * 0.24 + i * s * 0.20), c.y - u * 2.4, u * 0.9, u * 1.2), Color(0.96, 0.86, 0.50))
			_pxcircle(Vector2(c.x + s * 0.16, c.y - u * 1.8), maxi(int(round((u * 1.3) / U)), 1), Color(0.98, 0.94, 0.86))
			_pxcircle(Vector2(c.x + s * 0.16, c.y - u * 1.8), maxi(int(round((u * 0.6) / U)), 1), Color(0.98, 0.70, 0.24))
			draw_rect(Rect2(c.x - s * 0.30, c.y - u * 2.0, u * 1.6, u * 0.7), Color(0.24, 0.52, 0.28))
			_steam(c, s)
		1:   # 麻婆
			_bowl(c, s, Color(0.36, 0.30, 0.34), Color(0.18, 0.14, 0.16))
			draw_rect(Rect2(c.x - s * 0.30, c.y - u * 1.9, s * 0.60, u * 1.5), Color(0.78, 0.24, 0.16))
			for i in 4:
				draw_rect(Rect2(q(c.x - s * 0.24 + i * s * 0.15), c.y - u * 1.7, u * 1.1, u * 1.0),
						Color(0.96, 0.92, 0.82))
			draw_rect(Rect2(c.x - s * 0.10, c.y - u * 2.4, u * 1.4, u * 0.6), Color(0.28, 0.60, 0.30))
			_steam(c, s)
		2:   # 湯
			_bowl(c, s, bowl_out, Color(0.34, 0.30, 0.28))
			draw_rect(Rect2(c.x - s * 0.30, c.y - u * 1.8, s * 0.60, u * 1.4), Color(0.88, 0.74, 0.44))
			_pxcircle(Vector2(c.x - s * 0.12, c.y - u * 1.4), maxi(int(round((u * 1.4) / U)), 1), Color(0.96, 0.92, 0.84))
			_pxcircle(Vector2(c.x + s * 0.14, c.y - u * 1.2), maxi(int(round((u * 1.2) / U)), 1), Color(0.96, 0.92, 0.84))
			_steam(c, s)
		3:   # 飯
			_plate(c, s)
			draw_colored_polygon(PackedVector2Array([Vector2(c.x - s * 0.26, c.y - u * 0.4),
					Vector2(c.x, c.y - u * 3.4), Vector2(c.x + s * 0.26, c.y - u * 0.4)]),
					Color(0.94, 0.88, 0.72))
			for i in 5:
				draw_rect(Rect2(q(c.x - s * 0.18 + i * s * 0.09), q(c.y - u * (1.0 + (i % 3) * 0.7)), 2, 2),
						Color(0.86, 0.52, 0.26))
		4:   # 粥
			_bowl(c, s, Color(0.92, 0.91, 0.88), Color(0.42, 0.48, 0.42))
			draw_rect(Rect2(c.x - s * 0.30, c.y - u * 1.8, s * 0.60, u * 1.4), Color(0.86, 0.90, 0.78))
			draw_rect(Rect2(c.x - s * 0.08, c.y - u * 2.2, u * 1.8, u * 0.7), Color(0.30, 0.62, 0.34))
			_steam(c, s)
		5:   # 甘味（杯）
			draw_colored_polygon(PackedVector2Array([Vector2(c.x - s * 0.24, c.y - u * 2.6),
					Vector2(c.x + s * 0.24, c.y - u * 2.6), Vector2(c.x + s * 0.16, c.y + u * 1.2),
					Vector2(c.x - s * 0.16, c.y + u * 1.2)]), Color(0.90, 0.90, 0.94))
			draw_rect(Rect2(c.x - s * 0.22, c.y - u * 2.6, s * 0.44, u * 1.4), Color(0.98, 0.96, 0.92))
			_pxcircle(Vector2(c.x + s * 0.10, c.y - u * 2.9), maxi(int(round((u * 1.0) / U)), 1), Color(0.90, 0.26, 0.30))
			draw_rect(Rect2(c.x - s * 0.28, c.y + u * 1.2, s * 0.56, u * 0.8), Color(0.72, 0.72, 0.78))
		6:   # 団子
			_plate(c, s)
			for i in 3:
				_pxcircle(Vector2(c.x - s * 0.20 + i * s * 0.20, c.y - u * 1.4), maxi(int(round((u * 1.6) / U)), 1), Color(0.80, 0.62, 0.32))
				_pxcircle(Vector2(c.x - s * 0.22 + i * s * 0.20, c.y - u * 1.8), maxi(int(round((u * 0.6) / U)), 1), Color(0.96, 0.86, 0.60))
		_:
			_plate(c, s)
			draw_colored_polygon(PackedVector2Array([Vector2(c.x - s * 0.24, c.y - u * 0.4),
					Vector2(c.x, c.y - u * 3.0), Vector2(c.x + s * 0.24, c.y - u * 0.4)]),
					Color(0.78, 0.60, 0.34))


const ICON_INK := Color(0.13, 0.10, 0.12)


func _bowl(c: Vector2, s: float, outer: Color, rim: Color) -> void:
	var u := s / 12.0
	# 濃い縁取り（白い吹き出しの上でも形が読める）
	draw_colored_polygon(PackedVector2Array([Vector2(c.x - s * 0.39, c.y - u * 2.7),
			Vector2(c.x + s * 0.39, c.y - u * 2.7), Vector2(c.x + s * 0.23, c.y + u * 2.4),
			Vector2(c.x - s * 0.23, c.y + u * 2.4)]), ICON_INK)
	draw_colored_polygon(PackedVector2Array([Vector2(c.x - s * 0.36, c.y - u * 2.0),
			Vector2(c.x + s * 0.36, c.y - u * 2.0), Vector2(c.x + s * 0.20, c.y + u * 1.6),
			Vector2(c.x - s * 0.20, c.y + u * 1.6)]), outer)
	draw_rect(Rect2(c.x - s * 0.36, c.y - u * 2.4, s * 0.72, u * 0.8), rim)
	draw_rect(Rect2(c.x - s * 0.32, c.y - u * 1.2, u * 1.0, u * 2.0), outer.lightened(0.30))
	draw_rect(Rect2(c.x - s * 0.20, c.y + u * 1.6, s * 0.40, u * 0.7), rim.darkened(0.15))


func _plate(c: Vector2, s: float) -> void:
	var u := s / 12.0
	_ellipse(Vector2(c.x, c.y + u * 0.2), Vector2(s * 0.44, u * 1.9), ICON_INK)
	_ellipse(Vector2(c.x, c.y), Vector2(s * 0.40, u * 1.5), Color(0.88, 0.86, 0.84))
	_ellipse(Vector2(c.x, c.y - u * 0.3), Vector2(s * 0.30, u * 1.0), Color(0.96, 0.94, 0.92))


func _steam(c: Vector2, s: float) -> void:
	var u := s / 12.0
	var w := sin(_t * 3.0) * u * 0.5
	for i in 2:
		var sx := c.x - s * 0.16 + i * s * 0.32 + w * (1.0 if i == 0 else -1.0)
		draw_rect(Rect2(q(sx), c.y - u * 4.4, 2, u * 1.4), Color(1, 1, 1, 0.22))
		draw_rect(Rect2(q(sx + 2), c.y - u * 5.8, 2, u * 1.2), Color(1, 1, 1, 0.14))


# ── ヘッダー ──────────────────────────────────────────────────────────

## 右端を基点に右から積む（決め打ち算術をやめて対称に）。
func _draw_header(font: Font, sz: Vector2) -> void:
	var h := 66.0
	_vgrad(Rect2(0, 0, sz.x, h), Color(0.02, 0.02, 0.045, 0.96), Color(0.03, 0.025, 0.055, 0.86))
	draw_rect(Rect2(0, h, sz.x, 2), Color(GOLD.r, GOLD.g, GOLD.b, 0.45))
	draw_rect(Rect2(0, h + 2, sz.x, 8), Color(GOLD.r, GOLD.g, GOLD.b, 0.06))
	var m := 16.0
	# 左：タイトル
	_sh(font, Vector2(m, 42), "Day %d — 夜の営業" % day, int(FS.M), TEXT)
	# 右：右端から積む（スキップ → 常連チップ）
	var right := sz.x - m
	var skip_w := 86.0
	var skip_r := Rect2(q(right - skip_w), 15.0, skip_w, 36.0)
	_hits.append({"rect": skip_r, "id": "skip"})
	_panel(skip_r, Color(0.05, 0.05, 0.09, 0.9), Color(TEXT.r, TEXT.g, TEXT.b, 0.40), 8, 1.2)
	var sw := font.get_string_size("スキップ", HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.S)).x
	_sh(font, Vector2(skip_r.position.x + (skip_w - sw) * 0.5, skip_r.position.y + 24), "スキップ", int(FS.S), TEXT)
	right = skip_r.position.x - 12.0
	if regulars > 0:
		var reg := "連続%d日・常連%d人" % [streak, regulars]
		var rw := font.get_string_size(reg, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.S)).x
		var rr := Rect2(q(right - rw - 20.0), 18.0, q(rw + 20.0), 30.0)
		_panel(rr, Color(GOLD.r * 0.22, GOLD.g * 0.18, 0.05, 0.85), Color(GOLD.r, GOLD.g, GOLD.b, 0.35), 7, 1.0)
		_sh(font, Vector2(rr.position.x + 10, rr.position.y + 20), reg, int(FS.S), GOLD)


# ══════════════════════════════════════════════════════════════════════
#  自前の描画プリミティブ（Kit に依存せずここで完結させる）
# ══════════════════════════════════════════════════════════════════════

static func _glow_tex() -> ImageTexture:
	if _glow_t == null:
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var v := Vector2(x / float(n - 1) - 0.5, y / float(n - 1) - 0.5).length() * 2.0
				var a := clampf(1.0 - v, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a * a * a))
		_glow_t = ImageTexture.create_from_image(img)
	return _glow_t


static func _vign_tex() -> ImageTexture:
	if _vign_t == null:
		var n := 128
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var v := Vector2(x / float(n - 1) - 0.5, y / float(n - 1) - 0.5).length() * 2.0
				var a := clampf((v - 0.70) / 0.55, 0.0, 1.0)
				img.set_pixel(x, y, Color(0, 0, 0, a * a * 0.38))
		_vign_t = ImageTexture.create_from_image(img)
	return _vign_t


func _glow(center: Vector2, radius: float, col: Color, alpha: float) -> void:
	draw_texture_rect(_glow_tex(), Rect2(center - Vector2(radius, radius), Vector2(radius * 2, radius * 2)),
			false, Color(col.r, col.g, col.b, alpha))


func _vignette(sz: Vector2) -> void:
	draw_texture_rect(_vign_tex(), Rect2(Vector2.ZERO, sz), false)


func _vgrad(r: Rect2, top: Color, bot: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0),
			r.position + r.size, r.position + Vector2(0, r.size.y)]),
			PackedColorArray([top, top, bot, bot]))


func _panel(r: Rect2, bg: Color, border: Color, radius := 8, bw := 1.5) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(maxi(int(bw), 1))
	draw_style_box(sb, r)


## 3px単位のブレゼンハム円。draw_circle は必ずアンチエイリアスされるので、
## ドット絵の中に混ぜるとベクター図形が浮く。r_units は3pxモジュール数。
func _pxcircle(center: Vector2, r_units: int, col: Color) -> void:
	var cx: float = round(center.x / U) * U
	var cy: float = round(center.y / U) * U
	var r := maxi(r_units, 1)
	var rr := float(r * r) + 0.35
	for dy in range(-r, r + 1):
		var sp := int(floor(sqrt(maxf(rr - float(dy * dy), 0.0))))
		draw_rect(Rect2(cx - sp * U, cy + dy * U, (sp * 2 + 1) * U, U), col)


## 3px単位の円環（伝票の皿スロット）。draw_arc の置き換え。
func _pxring(center: Vector2, r_units: int, col: Color, thick := 1) -> void:
	var cx: float = round(center.x / U) * U
	var cy: float = round(center.y / U) * U
	var r := maxi(r_units, 1)
	var ri := maxi(r - thick, 0)
	var rr := float(r * r) + 0.35
	var rri := float(ri * ri) + 0.35
	for dy in range(-r, r + 1):
		var so := int(floor(sqrt(maxf(rr - float(dy * dy), 0.0))))
		if absi(dy) > ri:
			draw_rect(Rect2(cx - so * U, cy + dy * U, (so * 2 + 1) * U, U), col)
			continue
		var si := int(floor(sqrt(maxf(rri - float(dy * dy), 0.0))))
		var lw := maxf(float(so - si) * U, U)
		draw_rect(Rect2(cx - so * U, cy + dy * U, lw, U), col)
		draw_rect(Rect2(cx + (si + 1) * U, cy + dy * U, lw, U), col)


## 3x3矩形の連なりで斜線を引く。draw_line の1pxアンチエイリアス線は
## 周りのドット絵と解像度が合わず、そこだけ別の絵に見えてしまう。
func _pxdiag(a: Vector2, b: Vector2, col: Color, thick := 1) -> void:
	var n := maxi(int(ceil(a.distance_to(b) / U)), 1)
	var t := float(thick) * U
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		draw_rect(Rect2(round(p.x / U) * U, round(p.y / U) * U, t, t), col)


func _ellipse(center: Vector2, radii: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, col)


## 楕円（旧 API 名の互換。外部から呼ばれても動くよう残す）。
func draw_ellipse_shim(center: Vector2, radii: Vector2, col: Color) -> void:
	_ellipse(center, radii, col)


func _ripple_add(p: Vector2) -> void:
	_ripples.append({"pos": p, "t0": _t})
	while _ripples.size() > 6:
		_ripples.pop_front()


func _draw_ripples() -> void:
	var i := 0
	while i < _ripples.size():
		var k := (_t - float(_ripples[i]["t0"])) / 0.45
		if k >= 1.0:
			_ripples.remove_at(i)
			continue
		var e := 1.0 - pow(1.0 - k, 2.0)
		var p: Vector2 = _ripples[i]["pos"]
		var r := lerpf(10.0, 46.0, e)
		_pxcircle(p, maxi(int(round(r / U)), 1), Color(1, 1, 1, (1.0 - k) * 0.06))
		_pxring(p, maxi(int(round(r / U)), 1), Color(1, 1, 1, (1.0 - k) * 0.30))
		i += 1


## 影付きテキスト。
func _sh(font: Font, pos: Vector2, s: String, size_px: int, col: Color) -> void:
	draw_string(font, pos + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(0, 0, 0, 0.55))
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, col)
