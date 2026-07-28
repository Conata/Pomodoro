class_name ResultOverlay
extends Control
## 浮上後の夜の精算リザルト。三行精算 → 箱開封リビール → 住民ストーリー を提示し、
## 「店に戻る」で翌朝のホームへ。main.gd が set_data() で結果を流し込む。
## 箱アイコン（assets/generated/box/<grade>.png）をここで初投入。
##
## ここは「25分の見返りを受け取る瞬間」＝本作で最も強くあるべき山。設計の柱は5つ。
##   1. 等級で演出の格を変える。木/鉄はさっと出し、銀/金は 溜め→開封→着地 を長く取る。
##      銀以上だけ画面規模の演出（スポットライト・フラッシュ・光条・破片・リング）が付く。
##   2. 間を作る。等間隔の刻みをやめ、高レアの前に一拍置き、開いた後に読ませる余韻を置く。
##   3. 全部見せる。行高を個数から決めて畳む（「…他N個」で捨てない）。未開封のスロットを
##      先に敷いて「あと何個来るか」を見せる＝期待が積み上がる。
##   4. タップで送れる。1回で流れている演出を最後まで完了、もう1回で次へ。
##   5. 型は DS の5段（16/24/32/48）だけ、面は斜めカット（Kit.slab_panel）だけ。
##      有彩色は識別色1つ（暖炉オレンジ）＋状態色（危険=赤／成功=緑／獲得=金）＋等級色。
##
## 効果音：ここは Control なので main.gd の _sfx を直接は呼べない。
## 「鳴るべき瞬間」だけを sfx_cue で外へ出し、割り当て・音量・間引きは
## main.gd の SfxRouter が決める＝**音の出口は main._sfx ひとつのまま**。

signal action_pressed(id: String)
signal sfx_cue(id: String)   # 音の合図（"box_0".."box_3" ＝開封の瞬間 / "sheet_open"）

const M := DS.SP_4          # 外側マージン（全画面共通の16）

# ── 演出の時計（秒）。全体で8秒を超えないこと ─────────────────────────
const T_GOLD := 0.10        # 売上の数え上げ開始
const T_GOLD_DUR := 0.62    # 数え上げの長さ
const T_SUM := 0.30         # 収穫サマリ
const T_DAILY := 0.40       # 日課
const T_LEDGER := 0.52      # 三行精算のパネルが開く
const T_LINE0 := 0.66       # 1行目
const LINE_STEP := 0.16     # 行送り
const BOX_LEAD := 0.22      # 「開封」見出しが出てから1個目までの一拍
const BOX_BUDGET := 5.0     # 箱リビール全体の上限（超えたら一律に早回し）
const TAIL := 0.45          # 最後に読ませる余韻

# 等級ごとの尺（木/鉄/銀/金）。溜め → 開封 → 着地。
# 合計 0.26 / 0.40 / 0.76 / 1.22 秒＝金箱は木箱の 4.7 倍の時間を取る。
const LEAD := [0.02, 0.06, 0.22, 0.40]   # 溜め（銀以上は周りが暗転し、箱が震える）
const OPEN := [0.14, 0.18, 0.24, 0.32]   # 開封（閃光・リング・光条・破片）
const HOLD := [0.10, 0.16, 0.30, 0.50]   # 着地（文字が出る。銀以上は一字ずつ）

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
var _ripples: Array = []       # タップ波紋（Kit.ripples）
var _press: Dictionary = {}    # 直近の押下（押した板が沈む＝3状態目）
var _box_tex: Dictionary = {}  # grade -> Texture2D（キャッシュ）
var _wrap_cache: Dictionary = {}   # 折り返しの結果（毎フレーム測り直さない）
var _cued_ledger := false      # 三行精算のパネルが開く音を出したか
var _cued: Array = []          # 箱ごとに開封の音を出したか


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)


func set_data(d: Dictionary) -> void:
	for k in d:
		if k in self:
			set(k, d[k])
	_t = 0.0
	_claimed_now = false   # 常駐シートとして再利用するので前夜の受取表示を持ち越さない
	_press = {}
	_ripples.clear()
	_wrap_cache.clear()
	_cued_ledger = false
	_cued.clear()
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
	if not visible:
		return   # 常駐シート：閉じている間は演出時計も再描画も止める
	_t += delta
	_fire_cues()
	queue_redraw()


## 音の合図を「1回だけ」出す。_draw ではなく _process で判定する理由：
## 描画は隠れたフレームで飛ぶことがあるが、音の一回性はそれに引きずられてはいけない。
##
## 開封の瞬間＝溜め（LEAD）が終わって板が開く時刻。等級で音を変える。
## タップで送ると _t が一気に終端まで飛び、残り全部が同じフレームで開く。
## その時は**最上位の1個だけ**鳴らす（12個ぶん連打しない）。
func _fire_cues() -> void:
	if not _cued_ledger and _t >= T_LEDGER:
		_cued_ledger = true
		sfx_cue.emit("sheet_open")   # 三行精算の板が開く＝紙を置く音
	if boxes.is_empty():
		return
	var rows: Array = _plan()["rows"]
	if _cued.size() != rows.size():
		_cued.resize(rows.size())
		_cued.fill(false)
	var best := -1
	for i in rows.size():
		if bool(_cued[i]):
			continue
		var r: Dictionary = rows[i]
		if _t < float(r["t0"]) + float(r["lead"]):
			continue
		_cued[i] = true
		if best < 0 or int(r["g"]) > int((rows[best] as Dictionary)["g"]):
			best = i
	if best >= 0:
		sfx_cue.emit("box_%d" % int((rows[best] as Dictionary)["g"]))


func _gui_input(event: InputEvent) -> void:
	var p: Vector2
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		p = event.position
	elif event is InputEventScreenTouch and event.pressed:
		p = event.position
	else:
		return
	# 演出中でも押せる。当たり判定は最終位置に固定してあるので、
	# ライズイン中の板を狙って外す、ということが起きない。
	for h in _hits:
		if (h["rect"] as Rect2).has_point(p):
			Kit.ripple_add(_ripples, p, _t)
			_press = {"rect": h["rect"], "t0": _t}
			action_pressed.emit(String(h["id"]))
			accept_event()
			return
	# ボタン以外＝演出の送り。1回目は「いま流れているものを最後まで一気に」、
	# もう1回で次へ。演出を見たくない日にプレイヤーを待たせない。
	var e := _end_time()
	Kit.ripple_add(_ripples, p, _t)
	if _t < e:
		# 送り＝残りの箱が一斉に開く。_fire_cues が最上位の1個だけ鳴らす。
		_t = e
		queue_redraw()
	elif _t > e + 0.35:
		action_pressed.emit("continue")
	accept_event()


func _box_texture(grade: int) -> Texture2D:
	if not _box_tex.has(grade):
		var path := "res://assets/generated/box/%d.png" % grade
		_box_tex[grade] = load(path) if ResourceLoader.exists(path) else null
	return _box_tex[grade]


## 箱の等級色。既存の語彙（装備の等級色）に相乗りする＝色を増やしていない。
## 木=緑(2) 鉄=青(3) 銀=紫(4) 金=橙(5)。
func _grade_col(grade: int) -> Color:
	return KuroData.equip_grade_color(clampi(grade, 0, 3) + 2)


func _txt(font: Font, pos: Vector2, s: String, size: int, col: Color,
		ha := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	if col.r * 0.299 + col.g * 0.587 + col.b * 0.114 > 0.3:
		draw_string_outline(font, pos, s, ha, w, size, 3, Color(0.02, 0.02, 0.04, 0.92 * col.a))
	draw_string(font, pos, s, ha, w, size, col)


func _tw(font: Font, s: String, size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## 登場（delay 秒後に dur 秒かけて 0→1）。線形は使わない＝速く出て静かに着地する。
func _rise(delay: float, dur := 0.30) -> float:
	return Kit.out_quart((_t - delay) / dur)


## 決定的な擬似乱数（0..1）。破片や光条を毎フレーム同じ形に保つ。
func _rnd(a: int, b: int) -> float:
	var h := absi((a * 73856093) ^ (b * 19349663))
	return float(h % 10007) / 10007.0


## 日本語は語の切れ目が無いので、幅で畳む。結果は set_data まで使い回す。
func _wrap(font: Font, s: String, size: int, w: float) -> PackedStringArray:
	if s == "":
		return PackedStringArray()
	var key := "%d|%d|%s" % [size, int(w), s]
	if _wrap_cache.has(key):
		return _wrap_cache[key]
	var out := PackedStringArray()
	var cur := ""
	for i in s.length():
		var ch := s[i]
		if ch == "\n":
			out.append(cur)
			cur = ""
			continue
		var nxt := cur + ch
		if cur != "" and _tw(font, nxt, size) > w:
			out.append(cur)
			cur = ch
		else:
			cur = nxt
	if cur != "":
		out.append(cur)
	_wrap_cache[key] = out
	return out


# ══ 演出の設計図 ═══════════════════════════════════════════════════════
## 三行精算・開封見出し・箱1個ずつの開始時刻を先に全部決める。
## 尺が BOX_BUDGET を超える日（箱が大量／金箱だらけ）は一律に早回しする＝
## 等級ごとの比（＝格差）は保ったまま、全体の長さだけ抑える。
func _plan() -> Dictionary:
	var lines_end := T_LINE0 + maxf(float(lines.size() - 1), 0.0) * LINE_STEP + 0.32
	var head_t := lines_end + 0.10
	var rows: Array = []
	var t_end := lines_end + TAIL
	if not boxes.is_empty():
		var total := 0.0
		for b in boxes:
			var gi := clampi(int((b as Dictionary).get("grade", 0)), 0, 3)
			total += float(LEAD[gi]) + float(OPEN[gi]) + float(HOLD[gi])
		var sc := 1.0 if total <= BOX_BUDGET else BOX_BUDGET / total
		var t := head_t + BOX_LEAD
		for b in boxes:
			var g := clampi(int((b as Dictionary).get("grade", 0)), 0, 3)
			var ld := float(LEAD[g]) * sc
			var op := float(OPEN[g]) * sc
			var hd := float(HOLD[g]) * sc
			rows.append({"t0": t, "lead": ld, "open": op, "hold": hd, "g": g})
			t += ld + op + hd
		t_end = t + TAIL
	return {"lines_end": lines_end, "head_t": head_t, "rows": rows, "end": t_end}


func _end_time() -> float:
	return float(_plan()["end"])


# ══ 高レアの画面規模の演出 ══════════════════════════════════════════════

## 光条。中心から放射状に伸びる細い三角。金箱だけ。
func _rays(c: Vector2, u: float, col: Color, n := 12) -> void:
	var a := 1.0 - Kit.out_cubic(u)
	if a <= 0.01:
		return
	var ln := 46.0 + 320.0 * Kit.out_quint(u)
	for k in n:
		var ang := TAU * float(k) / float(n) + u * 0.30
		var d := Vector2(cos(ang), sin(ang))
		var pd := Vector2(-d.y, d.x) * (8.0 * (1.0 - u) + 1.0)
		draw_colored_polygon(PackedVector2Array([c + pd, c + d * ln, c - pd]),
				Color(col.r, col.g, col.b, 0.42 * a))


## 破片。外へ飛んで、重力で落ちる（消えるだけにしない）。
func _shards(c: Vector2, u: float, col: Color, seed_i: int, n := 12) -> void:
	var a := 1.0 - Kit.out_cubic(u)
	if a <= 0.01:
		return
	var e := Kit.out_quart(u)
	for k in n:
		var ang := TAU * (float(k) + _rnd(seed_i, k) * 0.9) / float(n)
		var sp := 70.0 + 120.0 * _rnd(seed_i, k + 50)
		var p := c + Vector2(cos(ang), sin(ang)) * sp * e
		p.y += 170.0 * u * u
		var s := (2.4 + 3.4 * _rnd(seed_i, k + 90)) * (1.0 - u * 0.55)
		var rot := ang + u * 5.0
		var dx := Vector2(cos(rot), sin(rot)) * s
		var dy := Vector2(-dx.y, dx.x) * 0.55
		draw_colored_polygon(PackedVector2Array([p + dx, p + dy, p - dx, p - dy]),
				Color(col.r, col.g, col.b, 0.9 * a))


## 等級の名札。銀は小見出し、金は見出しの大きさで、箱の上へせり上がる。
func _banner(font: Font, at: Vector2, label: String, col: Color, u: float, big: bool) -> void:
	var a := Kit.out_cubic(clampf(u * 4.0, 0.0, 1.0)) * (1.0 - Kit.in_cubic(clampf((u - 0.62) / 0.38, 0.0, 1.0)))
	if a <= 0.01:
		return
	var size := DS.T_DISPLAY if big else DS.T_HEAD
	var w := _tw(font, label, size)
	var rise := Kit.out_back(clampf(u * 3.2, 0.0, 1.0), 2.2)
	var pos := Vector2(at.x - w * 0.5, at.y - 10.0 - 26.0 * rise)
	var pad := 18.0
	var pr := Rect2(pos.x - pad, pos.y - float(size) - 6.0, w + pad * 2.0, float(size) + 18.0)
	Kit.slab(self, pr, Color(DS.INK.r, DS.INK.g, DS.INK.b, 0.92 * a))
	Kit.slab_edge(self, pr, Color(col.r, col.g, col.b, a), DS.skew(pr.size.y), 2.0)
	draw_string_outline(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(0, 0, 0, 0.9 * a))
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, a))


func _draw() -> void:
	var sz := size
	var font := get_theme_default_font()
	_hits.clear()
	Kit.set_xf(self, Vector2.ZERO)

	var plan := _plan()
	var t_end := float(plan["end"])
	var head_t := float(plan["head_t"])
	var rows: Array = plan["rows"]
	var disconnected := bool(summary.get("disconnected", false))
	var accent: Color = DS.DANGER if disconnected else DS.ACCENT
	Kit.backdrop(self, sz, "res://assets/generated/scene/restaurant.png", accent, 0.74)

	var fx: Array = []          # 画面規模の演出（内容の上へ最後に重ねる）
	var dim_a := 0.0            # 溜めのスポットライト（周りを落とす）
	var dim_y0 := 0.0
	var dim_y1 := 0.0

	# ── ヘッダ（斜めの黒板に白抜き。他画面と同じ作法）──
	var hs := (1.0 - _rise(0.0, 0.34)) * 26.0
	Kit.header(self, font, Vector2(M - hs, 26.0), "DAY %d" % day, accent, 300.0, DS.T_SUB,
			"切断された夜" if disconnected else "夜の精算")
	var y := 26.0 + float(DS.T_SUB) + 16.0 + float(DS.SP_3)

	# ── 売上（この画面の主役の数字）──
	# 0 から数え上げ、着地で一度だけ弾む。線形ではなく out_quint＝最後の1桁が静かに止まる。
	# [SFX未] 数え始め＝コインの擦れ（ループ）。ループ音は _sfx_pool（4本・一発撃ち）
	# では鳴らせないので、素材と再生経路を足すまで保留。
	var ga := _rise(T_GOLD, 0.26)
	var gk := clampf((_t - T_GOLD) / T_GOLD_DUR, 0.0, 1.0)
	var gv := int(round(float(gold) * Kit.out_quint(gk)))
	var gpop := 0.0
	if gk >= 1.0:
		gpop = Kit.out_cubic(clampf(1.0 - (_t - T_GOLD - T_GOLD_DUR) / 0.34, 0.0, 1.0))
	Kit.spot(self, Vector2(float(M) + 130.0, y + 24.0), 200.0, DS.GOLD, 0.17 * ga)
	Kit.num_draw(self, font, Vector2(M, y + 46.0), "＋%d G" % gv, DS.T_DISPLAY,
			Color(DS.GOLD.r, DS.GOLD.g, DS.GOLD.b, ga), gpop)
	y += 64.0

	# ── 収穫サマリ ──
	if not summary.is_empty():
		var sm := "B%dF到達 ・ 撃破%d ・ 素材+%d ・ %d分" % [
				int(summary.get("floor", 0)) + 1, int(summary.get("kills", 0)),
				int(summary.get("mats", 0)), int(round(float(summary.get("minutes", 0.0))))]
		if int(summary.get("resyncs", 0)) > 0:
			sm += " ・ 再同期%d回" % int(summary["resyncs"])
		var sa := _rise(T_SUM, 0.30)
		_txt(font, Vector2(float(M) + (1.0 - sa) * 10.0, y + 14.0), sm, DS.T_BODY,
				Color(DS.TEXT_2.r, DS.TEXT_2.g, DS.TEXT_2.b, sa))
		y += 30.0

	# ── 日課（連続完走・今日のポモドーロ・3完走でご祝儀）──
	if not daily.is_empty():
		var runs := int(daily.get("runs", 0))
		var da := _rise(T_DAILY, 0.30)
		var done := runs >= 3
		var dc: Color = DS.SUCCESS if done else DS.TEXT_2
		_txt(font, Vector2(float(M) + (1.0 - da) * 10.0, y + 14.0),
				"連続完走 %d ・ 今日のポモドーロ %d/3" % [streak, mini(runs, 3)], DS.T_BODY,
				Color(dc.r, dc.g, dc.b, da))
		if done:
			if bool(daily.get("claimed", false)):
				if _claimed_now:
					_txt(font, Vector2(sz.x - float(M) - 200.0, y + 14.0), "ご祝儀 +500G 受領",
							DS.T_BODY, Color(DS.GOLD.r, DS.GOLD.g, DS.GOLD.b, da))
			else:
				# 受け取れる物がある合図。押した瞬間の daily_done は main 側で鳴る。
				var cb := Rect2(sz.x - float(M) - 232.0, y - 8.0, 232.0, 36.0)
				var cd := Kit.sunk(cb, _press, _t)
				var beat := Kit.heartbeat(_t, 2.2)
				Kit.slab_panel(self, cd, Color(DS.GOLD.r * 0.22, DS.GOLD.g * 0.17, DS.GOLD.b * 0.08, 0.96 * da),
						Color(DS.GOLD.r, DS.GOLD.g, DS.GOLD.b, (0.55 + 0.45 * beat) * da), -1.0, 2.0)
				var cl := "デイリー報酬 +500G"
				_txt(font, Vector2(cd.position.x + (cd.size.x - _tw(font, cl, DS.T_BODY)) * 0.5,
						cd.position.y + 24.0), cl, DS.T_BODY, Color(DS.GOLD.r, DS.GOLD.g, DS.GOLD.b, da))
				_hits.append({"rect": cb, "id": "claim"})
		y += 38.0

	# ── 三行精算（板が開いて、1行ずつ左から差し込む）──
	# パネルが開く＝紙を置く音（sheet_open）。_fire_cues が T_LEDGER で1回出す。
	# 各行のクリックは入れない：11行の日があり、伝票と同じ「連打」になる。
	var led: Array = []
	for i in lines.size():
		for w in _wrap(font, String(lines[i]), DS.T_BODY, sz.x - float(M) * 2.0 - 28.0):
			led.append({"i": i, "s": w})
	var ph := 16.0 + float(led.size()) * 26.0 + 12.0
	var pa := _rise(T_LEDGER, 0.32)
	if pa > 0.01:
		Kit.slab_panel(self, Rect2(M, y, sz.x - float(M) * 2.0, ph),
				Color(0.05, 0.05, 0.08, 0.92 * pa), Color(accent.r, accent.g, accent.b, 0.40 * pa))
		var ry := y + 34.0
		for e in led:
			var lk := Kit.stag(_t - T_LINE0, int(e["i"]), LINE_STEP, 0.32)
			if lk > 0.01:
				_txt(font, Vector2(float(M) + 14.0 + (1.0 - lk) * 12.0, ry), String(e["s"]),
						DS.T_BODY, Color(DS.TEXT.r, DS.TEXT.g, DS.TEXT.b, lk))
			ry += 26.0
	y += ph + float(DS.SP_4)

	# ── 下から先に場所を確保する（ボタン → 会話 → ストーリー）──
	var bw := 300.0
	var btn_r := Rect2((sz.x - bw) * 0.5, sz.y - 86.0, bw, 58.0)
	var talk_r := Rect2((sz.x - bw) * 0.5, sz.y - 154.0, bw, 54.0)
	var st_rows := _wrap(font, story, DS.T_BODY, sz.x - float(M) * 2.0 - 28.0)
	var story_h := 0.0
	if st_rows.size() > 0:
		story_h = 16.0 + float(st_rows.size()) * 26.0 + 12.0
	var bottom := (talk_r.position.y if not talk.is_empty() else btn_r.position.y) - float(DS.SP_3)
	var story_y := bottom - story_h
	var box_bottom := bottom - (story_h + float(DS.SP_3) if story_h > 0.0 else 0.0)

	# ══ 箱開封リビール ══════════════════════════════════════════════════
	if not boxes.is_empty():
		if _t >= head_t:
			var bh := (1.0 - _rise(head_t, 0.26)) * 22.0
			Kit.header(self, font, Vector2(float(M) - bh, y), "開封", DS.GOLD, 240.0, DS.T_SUB,
					"%d個" % boxes.size())
		y += float(DS.T_SUB) + 16.0 + float(DS.SP_2)
		# 行の高さは個数から決める＝何個あっても全部見せる（捨てない）。
		var n := boxes.size()
		var avail := maxf(box_bottom - y, 80.0)
		var row_h := clampf(avail / float(n), 18.0, 56.0)

		# 溜めの下見：銀以上が息を吸っている間だけ、その行の上下を落として舞台にする。
		for i in n:
			var pr: Dictionary = rows[i]
			if int(pr["g"]) < 2:
				continue
			var pg := int(pr["g"])
			var pa2 := _t - float(pr["t0"])
			var pl := float(pr["lead"])
			var po := float(pr["open"])
			if pa2 < 0.0 or pa2 > pl + po:
				continue
			var k := Kit.out_cubic(pa2 / maxf(pl, 0.001)) if pa2 < pl \
					else 1.0 - Kit.out_cubic((pa2 - pl) / maxf(po, 0.001))
			dim_a = maxf(dim_a, k * (0.30 if pg == 2 else 0.48))
			dim_y0 = y + row_h * float(i)
			dim_y1 = dim_y0 + row_h
		if dim_a > 0.001:
			draw_rect(Rect2(0.0, 0.0, sz.x, dim_y0), Color(0, 0, 0, dim_a))

		for i in n:
			var b: Dictionary = boxes[i]
			var rw: Dictionary = rows[i]
			var g := int(rw["g"])
			var gcol := _grade_col(g)
			var r := Rect2(M, y + row_h * float(i) + 1.0, sz.x - float(M) * 2.0, row_h - 2.0)
			var age := _t - float(rw["t0"])
			var ld := float(rw["lead"])
			var op := float(rw["open"])
			var hd := float(rw["hold"])

			if age < 0.0:
				# 未開封のスロット。「あと何個来るか」を先に見せる＝期待が積み上がる。
				if _t >= head_t:
					var sk := DS.skew(r.size.y)
					Kit.slab(self, r, Color(0.03, 0.03, 0.05, 0.62))
					Kit.slab_edge(self, r, Color(1, 1, 1, 0.16), sk, 1.0)
					# 中の見えない箱＝地紋だけ。ここに何かが入っている、とだけ言う。
					Kit.hatch(self, r, Color(1, 1, 1, 0.022), 30.0, 8.0)
				continue

			var opened := age >= ld
			var u_open := clampf((age - ld) / maxf(op, 0.001), 0.0, 1.0)
			var u_hold := clampf((age - ld - op) / maxf(hd, 0.001), 0.0, 1.0)
			var u_fx := clampf((age - ld) / maxf(op + hd * 0.6, 0.001), 0.0, 1.0)
			# 溜めのあいだ、銀以上の箱だけ小刻みに震える（開く前に「来る」と分かる）
			var shake := 0.0
			if not opened and g >= 2:
				var lu := age / maxf(ld, 0.001)
				shake = sin(age * 78.0) * 2.6 * lu * lu
			var dr := Rect2(r.position + Vector2(shake, 0.0), r.size)

			# 面：溜めで起き上がり、開封で罫が等級色に振り切れる
			var lit := Kit.out_cubic(age / maxf(ld + op * 0.35, 0.001))
			var edge := (0.20 + 0.55 * lit) * (0.55 + 0.45 * Kit.out_cubic(u_open))
			Kit.slab_panel(self, dr, Color(0.06, 0.06, 0.09, 0.55 + 0.40 * lit),
					Color(gcol.r, gcol.g, gcol.b, edge), -1.0, 1.5 if g < 2 else 2.4)
			if g >= 3 and opened:
				# 金箱だけ面に地紋を入れる（無情報の平面を残さない）
				Kit.hatch(self, dr, Color(gcol.r, gcol.g, gcol.b, 0.07 * (0.4 + 0.6 * u_open)), 22.0, 6.0)

			# 開封の一閃（鉄以上）。板の上を白い帯が走り抜ける。
			# ここが「開いた」瞬間＝box_wood/iron/silver/gold（_fire_cues が出す）。
			if opened and u_open < 1.0 and g >= 1:
				var wx := dr.position.x + dr.size.x * Kit.out_cubic(u_open)
				draw_rect(Rect2(wx - 20.0, dr.position.y, 40.0, dr.size.y),
						Color(1, 1, 1, 0.34 * (1.0 - u_open)))

			# 箱アイコン（閉じている間は小さく、開いた瞬間に膨らんで戻る）
			var ico := clampf(row_h - 10.0, 16.0, 36.0)
			var c := Vector2(dr.position.x + 12.0 + ico * 0.5, dr.position.y + dr.size.y * 0.5)
			var isc := 0.86 + 0.05 * Kit.heartbeat(_t, 0.9)
			if opened:
				isc = 1.0 + 0.55 * (1.0 - Kit.out_quart(u_open))
			var tex := _box_texture(clampi(int(b.get("grade", 0)), 0, 3))
			var tint := Color(1, 1, 1, 0.55 + 0.45 * lit)
			if opened and u_open < 1.0:
				var wf := 1.0 - u_open
				tint = Color(1, 1, 1, tint.a).lerp(Color(1, 1, 1, 1), wf)
			if tex != null:
				var ir := Rect2(c - Vector2(ico, ico) * 0.5 * isc, Vector2(ico, ico) * isc)
				draw_texture_rect(tex, ir, false, tint)
			else:
				Kit.plate(self, c, ico * 0.5 * isc, gcol)

			# 等級名（木箱/鉄箱/銀箱/金箱）— 引きの良し悪しは、まずここで読める
			var base_y := dr.position.y + dr.size.y * 0.5 + 6.0
			var gname := String(KuroData.BOX_NAMES[clampi(g, 0, 3)])
			var nx := dr.position.x + 20.0 + ico
			_txt(font, Vector2(nx, base_y), gname, DS.T_BODY,
					Color(gcol.r, gcol.g, gcol.b, 0.35 + 0.65 * lit))

			# 中身。銀以上は一字ずつ出して「読ませる」、木/鉄はさっと出す。
			if opened:
				var txt := String(b.get("text", ""))
				var tx := nx + _tw(font, gname, DS.T_BODY) + 14.0
				var tavail := dr.end.x - 10.0 - tx
				var ta := 1.0
				if g >= 2:
					txt = txt.substr(0, int(ceil(float(txt.length()) * clampf(u_hold * 1.7, 0.0, 1.0))))
				else:
					ta = Kit.out_cubic(u_hold * 2.2)
				if ta > 0.01 and txt != "":
					_txt(font, Vector2(tx, base_y), txt, DS.T_BODY,
							Color(DS.TEXT.r, DS.TEXT.g, DS.TEXT.b, ta),
							HORIZONTAL_ALIGNMENT_LEFT, tavail)

			# 画面規模の演出は最後にまとめて重ねる（下の行に踏まれないように）。
			# 銀以上は光の出どころを行の中央へ置く：箱アイコンは左端にあるので、
			# そこを中心に放射させると画面の外へ半分こぼれて「事故」に見える。
			if opened and u_fx < 1.0:
				var hc := c if g < 2 else Vector2(sz.x * 0.5, c.y)
				fx.append({"k": "hero", "c": hc, "u": u_fx, "g": g, "col": gcol, "i": i})
			if opened and g >= 2:
				var ub := clampf((age - ld) / maxf(op + hd, 0.001), 0.0, 1.0)
				if ub < 1.0:
					fx.append({"k": "banner", "at": Vector2(sz.x * 0.5, dr.position.y),
							"s": gname, "col": gcol, "u": ub, "big": g >= 3})
				if u_open < 1.0:
					fx.append({"k": "flash", "col": gcol,
							"a": (0.18 if g == 2 else 0.44) * (1.0 - Kit.out_quart(u_open))})
		y += row_h * float(n) + float(DS.SP_3)

	# ── 住民ストーリー（特注が売れた夜の永続バフ。最後に、静かに置く）──
	if st_rows.size() > 0:
		var sa2 := _rise(maxf(t_end - 0.75, 0.0), 0.40)
		if sa2 > 0.01:
			Kit.slab_panel(self, Rect2(M, story_y, sz.x - float(M) * 2.0, story_h),
					Color(0.08, 0.06, 0.04, 0.92 * sa2), Color(accent.r, accent.g, accent.b, 0.55 * sa2))
			var sy := story_y + 34.0
			for i in st_rows.size():
				var sk2 := Kit.stag(_t - maxf(t_end - 0.75, 0.0), i, 0.06, 0.36)
				_txt(font, Vector2(float(M) + 14.0, sy), st_rows[i], DS.T_BODY,
						Color(DS.TEXT.r, DS.TEXT.g, DS.TEXT.b, sk2))
				sy += 26.0

	# ── 会話ボタン（その夜の相手がいる時だけ）──
	if not talk.is_empty():
		var gid := String(talk.get("girl", ""))
		var gname2 := String((KuroData.GIRLS.get(gid, {}) as Dictionary).get("name", gid))
		var tk := _rise(0.70, 0.42)
		var td := Kit.sunk(talk_r, _press, _t)
		td = Rect2(td.position + Vector2(0.0, (1.0 - tk) * 20.0), td.size)
		Kit.slab_panel(self, td, Color(accent.r * 0.20, accent.g * 0.16, accent.b * 0.12, 0.96 * tk),
				Color(accent.r, accent.g, accent.b, tk), -1.0, 2.0)
		var tl := "▶  %s と話す" % gname2
		_txt(font, Vector2(td.position.x + (td.size.x - _tw(font, tl, DS.T_SUB)) * 0.5,
				td.position.y + 36.0), tl, DS.T_SUB, Color(DS.TEXT.r, DS.TEXT.g, DS.TEXT.b, tk))
		_hits.append({"rect": talk_r, "id": "talk"})   # 当たり判定は最終位置に固定

	# ── 店に戻る（最下部固定・CTA）──
	var ck := _rise(0.80, 0.42)
	var cd2 := Kit.sunk(btn_r, _press, _t)
	cd2 = Rect2(cd2.position + Vector2(0.0, (1.0 - ck) * 20.0), cd2.size)
	Kit.cta(self, cd2, Color(accent.r * 0.24, accent.g * 0.17, accent.b * 0.12, 0.96 * ck),
			Color(accent.r, accent.g, accent.b, ck), Kit.heartbeat(_t, 2.6))
	var bl := "▶  店に戻る（翌朝へ）"
	_txt(font, Vector2(cd2.position.x + (cd2.size.x - _tw(font, bl, DS.T_SUB)) * 0.5,
			cd2.position.y + 38.0), bl, DS.T_SUB, Color(DS.TEXT.r, DS.TEXT.g, DS.TEXT.b, ck))
	_hits.append({"rect": btn_r, "id": "continue"})   # 当たり判定は最終位置に固定

	# ══ 画面規模の演出（内容の上へ重ねる。銀以上だけ） ═══════════════════
	if dim_a > 0.001:
		draw_rect(Rect2(0.0, dim_y1, sz.x, sz.y - dim_y1), Color(0, 0, 0, dim_a))
	for f in fx:
		match String(f["k"]):
			"hero":
				var u := float(f["u"])
				var col: Color = f["col"]
				var c: Vector2 = f["c"]
				var g := int(f["g"])
				match g:
					0:
						# 木箱：光が一度だけ点く。それだけ。
						Kit.spot(self, c, 30.0, col, 0.34 * (1.0 - u))
					1:
						Kit.spot(self, c, 40.0, col, 0.34 * (1.0 - u))
						Kit.burst(self, c, 9.0, col, u)
					2:
						# 銀箱：リングが二重に開き、破片が飛ぶ
						Kit.spot(self, c, 74.0, col, 0.42 * (1.0 - u))
						Kit.burst(self, c, 15.0, col, u)
						Kit.burst(self, c, 10.0, col, clampf(u * 1.5 - 0.30, 0.0, 1.0))
						_shards(c, u, col, int(f["i"]), 9)
					_:
						# 金箱：光条＋破片＋三重のリング。ここだけ別格に見せる。
						Kit.spot(self, c, 120.0, col, 0.52 * (1.0 - u))
						_rays(c, u, col, 14)
						_shards(c, u, col, int(f["i"]), 18)
						Kit.burst(self, c, 22.0, col, u)
						Kit.burst(self, c, 15.0, col, clampf(u * 1.4 - 0.22, 0.0, 1.0))
						Kit.burst(self, c, 10.0, col, clampf(u * 1.3 - 0.42, 0.0, 1.0))
			"flash":
				# 画面が飛ぶ瞬間は開封と同じ時刻なので、音は箱の1発に集約する
				# （閃光に別の音を重ねると、金箱の 0.76 秒が食われて山が潰れる）。
				var fc: Color = f["col"]
				draw_rect(Rect2(Vector2.ZERO, sz),
						Color((1.0 + fc.r) * 0.5, (1.0 + fc.g) * 0.5, (1.0 + fc.b) * 0.5, float(f["a"])))
			"banner":
				_banner(font, f["at"], String(f["s"]), f["col"], float(f["u"]), bool(f["big"]))

	Kit.vignette(self, sz)
	# 押した板は必ず応える（沈む→行き過ぎて戻る）
	if not _press.is_empty():
		var pk := 1.0 - clampf((_t - float(_press["t0"])) / Kit.PRESS_LIFE, 0.0, 1.0)
		if pk > 0.0:
			Kit.press(self, _press["rect"], accent, pk)
		else:
			_press = {}
	Kit.ripples(self, _ripples, _t)
