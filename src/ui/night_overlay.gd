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

## 判断が生まれる形（この劇場の芯）:
##  - 同時に複数の客が「！」になる。それぞれ皿の価値（G）と残りの我慢が違う。
##  - タップは一度に1人。高い客を先に出すか、切れそうな客を先に出すか＝選択。
##  - **放置しても罰しない。** 基本の客は店番が我慢の直前に必ず滑り込む（walked_out=0）。
##    タップは上積み（チップ＋席の回転で入る追い客）であって、押さないと減るのではない。
##  - 取り逃がしうるのは「タップで呼び込んだ追い客」だけ。しかも最後のタップから
##    IDLE_FORGIVE 秒で店番が全員を引き受ける＝席を外した人は絶対に損をしない。

signal finished(tips: int, extra: int, walked_out: int)   # 劇場の終了（給仕の実績を持ち帰る）
signal tip_tapped            # タップ給仕の瞬間（SFX用・ui_buy）
## 音の合図。ここは Control なので main.gd の _sfx を直接は呼べない。
## "serve"＝店番が皿を出す／"ticket"＝伝票が1枚埋まる／
## "guest_leave"＝待ちきれず帰る／"night_close"＝締めの一幕が始まる。
## 割り当て・音量・間引きは main.gd の SfxRouter に閉じている。
signal sfx_cue(id: String)

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
const TURNAWAY_MAX := 3      # 素材切れで帰す客の演出数上限

# ── 我慢と自動給仕 ───────────────────────────────────────────────────
# 我慢は客ごとに違う（1.9〜3.3秒）。この差が「どっちを先に出すか」を生む。
# 店番は残り我慢がいちばん少ない客から出し、RESCUE を切ったら必ず滑り込む。
# ＝放置しても基本の客はひとりも取り逃がさない（増減ゼロが保証される）。
const PAT_MIN := 1.90        # 我慢の最短（秒）
const PAT_MAX := 3.30        # 我慢の最長（秒）
const PAT_BONUS := 3.20      # 追い客の我慢（少し長め＝拾える猶予を置く）
const RESCUE := 0.55         # 残り我慢がこれを切ると店番が自分で出す（安全網）
const KEEPER_CD := 0.28      # 店番が続けて出せる最短間隔
const IDLE_FORGIVE := 2.20   # 最後のタップからこの秒数で「席を外した」とみなし追い客も救済
const EXTRA_MAX := 4         # 追い客の上限（尺が伸びすぎないように）
const SEAT_SEC := 2.00       # 追い客ひとりぶんの「早出しで浮かせた席の時間」

# ── 間（タイミング）。客の一連は「歩く→座る→待つ→食べる→立つ→去る」で切れ目を作らない。
const SIT_DUR := 0.42        # 席に腰を下ろすまで（ease-out-back で軽く沈む）
const STAND_DUR := 0.34      # 立ち上がるまで
const EAT_DUR := 1.70        # 皿が来てから食べ終わるまで
const DENY_DUR := 1.20       # 素材切れの客が引き下がるまで
const WALK_IN := 320.0       # 入店の基準速度（距離から所要時間を出す）
const CLOSE_DUR := 2.60      # 締めの演出の尺
const POP_DUR := 0.42        # 売上加算のバネ
const NOREN_N := 4           # のれんの短冊数（細かく割ると布ではなく縞に見える）

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
var _coins: Array = []           # チップのコイン粒子 {p, v, t, tgt}
var _bursts: Array = []          # 一瞬の衝撃リング {pos, t, col, r0, r1, dur}
var _frac_disp := 0.0            # 進捗バーの追従値（数字と同じく ease-out）
var _digit_pop := 0.0            # 桁が増えた瞬間の強調
var _gold_digits := 1
var _tip_pop := 0.0
var _keeper_lunge := 0.0         # 配膳の瞬間、店番が身を乗り出す量
var _keeper_dir := 0.0
var _noren: Array = []           # のれんの短冊 {o, v}
var _spawn_i := 0                # 何人目を入れようとしているか（素材切れの散らしに使う）
var _turn_done := 0
var _turn_total := 0
var _spawn_total := 1
var _close := 0.0                # 締めの演出の経過（_end_t 到達後）
var _wipe := 0.0                 # 締めの布巾の位置 0..1
# ── 給仕の実績（settle_service へ渡す3つの数）─────────────────────────
var _per_plate := 0              # 1皿の平均売上。sim の per_plate と同じ源（script の合計÷皿数）
var _extra_served := 0           # 追い客のうち実際に捌けた人数 → extra
var _walked := 0                 # 我慢が切れて帰った人数 → walked_out
var _saved := 0.0                # 早出しで浮かせた席の時間（貯まると追い客が入る）
var _extra_pend := 0             # 入店待ちの追い客
var _extra_born := 0             # これまでに入店した追い客
var _keeper_cd := 0.0            # 店番の手が空くまで
var _last_tap := -999.0          # 最後にタップした時刻（席を外した判定に使う）
var _bonus_pop := 0.0            # 追い客が増えた瞬間の強調
var _lost_pop := 0.0             # 取り逃がした瞬間の強調

static var _glow_t: ImageTexture = null
static var _vign_t: ImageTexture = null
static var _bg_t: Texture2D = null
static var _bg_loaded := false
static var _pix_cache: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # ドット絵をカリッと拡大
	if _noren.is_empty():
		for i in NOREN_N:
			_noren.append({"o": 0.0, "v": 0.0})
	_warm_up()
	set_process(true)


## 3px グリッドへ量子化。全ての図形座標をここに通してピクセル密度を揃える。
func q(v: float) -> float:
	return round(v / U) * U


# ── イージング ───────────────────────────────────────────────────────
# 線形補間は「機械が動かした」ように見える。入りと抜きを必ず付ける。

## ease-out cubic（減速して着く：入店・着席・立ち上がり）
func _eo(k: float) -> float:
	var x := 1.0 - clampf(k, 0.0, 1.0)
	return 1.0 - x * x * x


## ease-in cubic（加速して去る：退店）
func _ei(k: float) -> float:
	var x := clampf(k, 0.0, 1.0)
	return x * x * x


## smoothstep（両端で止まる：仕草・布巾）
func _eio(k: float) -> float:
	var x := clampf(k, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## 到着のカーブ。前半は一定の歩調、後半だけ減速して席の手前で止まる。
func _arrive(k: float) -> float:
	var x := clampf(k, 0.0, 1.0)
	if x < 0.58:
		return x * 1.28
	var u := (x - 0.58) / 0.42
	return 0.7424 + 0.2576 * (1.0 - (1.0 - u) * (1.0 - u))


## ease-out-back（行き過ぎて戻る：腰を下ろす・伝票に皿が入る）
func _eob(k: float) -> float:
	var x := clampf(k, 0.0, 1.0) - 1.0
	return 1.0 + x * x * (2.70158 * x + 1.70158)


## 減衰バウンド（着地：皿・木札）
func _bnc(k: float) -> float:
	var x := clampf(k, 0.0, 1.0)
	return absf(sin(x * PI * 2.2)) * (1.0 - x) * (1.0 - x)


## フレームレート非依存の指数追従。lerp(a,b,delta*k) は fps で結果が変わる。
func _chase(cur: float, tgt: float, rate: float, delta: float) -> float:
	return cur + (tgt - cur) * (1.0 - exp(-rate * delta))


## 上演データを流し込んで初期化。script が空なら呼ばず、直接リザルトへ。
func set_data(d: Dictionary) -> void:
	day = int(d.get("day", 1))
	keeper = String(d.get("keeper", "kiriko"))
	streak = int(d.get("streak", 0))
	regulars = int(d.get("regulars", 0))
	_script = (d.get("script", []) as Array).duplicate()
	_total = maxi(int(d.get("customers", _script.size())), _script.size())
	_turnaway = mini(_total - _script.size(), TURNAWAY_MAX)
	_turn_total = _turnaway
	_turn_done = 0
	_spawn_i = 0
	_spawn_total = maxi(_script.size() + _turn_total, 1)
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
	_spawn_cd = 0.28          # 幕開けの静止を短くする（最初の一人が早く暖簾を割る）
	# 入店の間隔は我慢より短くする。ここが我慢より長いと「1人ずつ順番に」になり、
	# 同時に複数が！にならない＝選択が発生しない。席数（5）が実際の律速になる。
	_interval = clampf(13.0 / maxf(float(_spawn_total), 1.0), 0.55, 1.05)
	# 1皿の平均売上。sim.settle_service の per_plate と同じ源から取る
	# （night.gold == script の gold 合計、night.served == script の皿数）。
	var sum_g := 0
	for s in _script:
		sum_g += int((s as Dictionary).get("gold", 0))
	_per_plate = int(round(float(sum_g) / maxf(float(_script.size()), 1.0))) if not _script.is_empty() else 0
	_extra_served = 0
	_walked = 0
	_saved = 0.0
	_extra_pend = 0
	_extra_born = 0
	_keeper_cd = 0.0
	_last_tap = -999.0
	_bonus_pop = 0.0
	_lost_pop = 0.0
	_end_t = 0.0
	_close = 0.0
	_wipe = 0.0
	_done = false
	_t = 0.0
	_coins = []
	_bursts = []
	_frac_disp = 0.0
	_digit_pop = 0.0
	_gold_digits = 1
	_tip_pop = 0.0
	_keeper_lunge = 0.0
	_keeper_dir = 0.0
	_noren = []
	for i in NOREN_N:
		_noren.append({"o": 0.0, "v": 0.0})
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
	finished.emit(_tips, _extra_served, _walked)


func _process(delta: float) -> void:
	if not visible or _done:
		return
	delta = minf(delta, 0.05)      # ヒッチで状態機械を飛び越えさせない
	_t += delta
	_spawn_cd -= delta
	# 売上のカウントアップは指数追従（fps 非依存）。lerpf(a,b,delta*k) は
	# フレームレートで速度が変わってしまうので使わない。
	_gold_disp = _chase(_gold_disp, float(_gold_shown), 7.0, delta)
	if _gold_shown - _gold_disp < 0.6:
		_gold_disp = float(_gold_shown)
	var nd := str(int(round(_gold_disp))).length()
	if nd > _gold_digits:
		_gold_digits = nd
		_digit_pop = 0.55           # 桁が増えた＝夜の格が上がった瞬間
	_pop = maxf(_pop - delta, 0.0)
	_digit_pop = maxf(_digit_pop - delta, 0.0)
	_tip_pop = maxf(_tip_pop - delta, 0.0)
	_keeper_lunge = maxf(_keeper_lunge - delta * 1.7, 0.0)
	_bonus_pop = maxf(_bonus_pop - delta, 0.0)
	_lost_pop = maxf(_lost_pop - delta, 0.0)
	_frac_disp = _chase(_frac_disp, clampf(float(_served_shown) / maxf(_total, 1.0), 0.0, 1.0), 6.0, delta)
	# 入店スケジューラ：空席があれば次の客を入れる。
	# 追い客（早出しで浮いた席に滑り込む客）を優先＝「席が空いた瞬間に次が入る」が見える。
	if _spawn_cd <= 0.0:
		var seat := _free_seat()
		if seat >= 0 and _extra_pend > 0 and not _script.is_empty():
			_extra_pend -= 1
			_extra_born += 1
			_total += 1                                  # 伝票のスロットがその場で1つ増える
			_bonus_pop = 0.75
			_spawn(seat, (_extra_born * 5 + day) % _script.size(), true)
			_spawn_cd = maxf(_interval * 0.55, 0.42)
		elif seat >= 0 and (_next < _script.size() or _turnaway > 0):
			var serving := -1
			# 素材切れの客は最後にまとめない。まとめると夜が「✕が3回」で終わる。
			# Bresenham で全体に散らし、最初と最後は必ず配膳の客にする。
			var turn_now := _turnaway > 0 and _next < _script.size() \
					and _turn_done * _spawn_total < _spawn_i * _turn_total
			if _next < _script.size() and not turn_now:
				serving = _next
				_next += 1
			else:
				_turnaway -= 1
				_turn_done += 1
			_spawn(seat, serving, false)
			_spawn_cd = _interval
	# 客の状態機械 — in → sit → wait → eat → up → out を途切れさせない
	var cy := q(size.y * COUNTER_Y)
	for c in _custs:
		c["t"] = float(c["t"]) + delta
		c["joy"] = maxf(float(c.get("joy", 0.0)) - delta, 0.0)
		c["angry"] = maxf(float(c.get("angry", 0.0)) - delta, 0.0)
		var seat_x := _seat_x(int(c["seat"]))
		var ct := float(c["t"])
		match String(c["state"]):
			"in":
				# 一定の歩調で来て、席の手前で減速して止まる。
				# 等速のまま急停止すると「瞬間移動」に、全区間 ease だと滑って見える。
				c["wt"] = float(c["wt"]) + delta
				var k := clampf(ct / float(c["dur"]), 0.0, 1.0)
				var rt := 7.2 + float(int(c["seed"]) % 5) * 0.55
				# 一歩ごとの速度の脈（人は等速では歩かない）
				var stride := sin(float(c["wt"]) * rt + float(c["ph"])) * 3.5 * (1.0 - k)
				c["x"] = lerpf(float(c["x0"]), seat_x, _arrive(k)) + stride
				if k >= 1.0:
					c["x"] = seat_x
					c["state"] = "sit"
					c["t"] = 0.0
			"sit":
				# 腰を下ろす。ease-out-back で一度沈んで戻る＝椅子の反発。
				var k2 := clampf(ct / SIT_DUR, 0.0, 1.0)
				c["sit"] = clampf(_eob(k2), 0.0, 1.12)
				if k2 >= 1.0:
					c["sit"] = 1.0
					c["state"] = "wait" if int(c["serving"]) >= 0 else "deny"
					c["t"] = 0.0
					c["bt"] = 0.0
			"wait":
				c["bt"] = float(c["bt"]) + delta
				# 我慢が減る。ゲージはこの値をそのまま映す（切れる瞬間まで黙っていない）。
				c["pat"] = float(c["pat"]) - delta
				_tick_gesture(c, delta)
				if float(c["pat"]) <= 0.0:
					# 基本の客はここで必ず店番が滑り込む＝放置しても取り逃がさない。
					# 帰るのは「タップで呼び込んだ追い客」を、動いている最中に放った時だけ。
					if bool(c.get("bonus", false)) and (_t - _last_tap) < IDLE_FORGIVE:
						_walk_out(c)
					else:
						_serve(c, false)
			"deny":
				c["bt"] = float(c["bt"]) + delta
				if ct >= DENY_DUR:
					_leave(c)
			"eat":
				if ct >= EAT_DUR:
					var s: Dictionary = _script[int(c["serving"])]
					var bns := bool(c.get("bonus", false))
					# 追い客の皿は1皿ぶんの平均＝sim の extra_gold と同じ勘定にする。
					var g := _per_plate if bns else int(s["gold"])
					var mt := (not bns) and bool(s.get("match", false))
					if bns:
						_extra_served += 1
						_bonus_pop = 0.75
					_gold_shown += g
					_pop = POP_DUR
					_served_shown += 1
					if mt:
						_matched += 1
					_plates.append({"kind": _dish_kind(String(s["dish"])),
							"match": mt, "t": 0.0})
					sfx_cue.emit("ticket")   # 伝票が1枚埋まる（1夜で11枚前後・最小音量）
					_floats.append({"pos": Vector2(seat_x, cy - CUST_H + 12.0),
							"text": ("追い客 +%dG" % g) if bns else ("+%dG" % g),
							"col": GOLD, "t": 0.0})
					_burst(Vector2(seat_x + 51.0, cy - 18.0), GOLD, 9.0, 33.0, 0.28)
					_leave(c)
			"up":
				# 立ち上がる（席は既に空けてある＝次の客が歩き出せる）
				var k3 := clampf(ct / STAND_DUR, 0.0, 1.0)
				c["sit"] = 1.0 - _eo(k3)
				if k3 >= 1.0:
					c["state"] = "out"
					c["t"] = 0.0
			"out":
				# 加速して去る。ease-in なので歩き出しが柔らかい。
				c["wt"] = float(c["wt"]) + delta
				var spd := lerpf(70.0, 430.0, _ei(clampf(ct / 0.8, 0.0, 1.0)))
				c["x"] = float(c["x"]) + spd * delta * float(c["dir"])
	_tick_keeper(delta)
	# 退店しきった客を消す
	var keep: Array = []
	for c in _custs:
		if String(c["state"]) == "out" and (float(c["x"]) < -80.0 or float(c["x"]) > size.x + 90.0):
			continue
		keep.append(c)
	_custs = keep
	_tick_noren(delta)
	_tick_coins(delta)
	# フロート寿命
	for f in _floats:
		f["t"] = float(f["t"]) + delta
	while not _floats.is_empty() and float(_floats[0]["t"]) > 1.4:
		_floats.pop_front()
	# 伝票の皿（スロットへ落ちる演出の時計）
	for p in _plates:
		p["t"] = float(p.get("t", 9.0)) + delta
	var bi := 0
	while bi < _bursts.size():
		_bursts[bi]["t"] = float(_bursts[bi]["t"]) + delta
		if float(_bursts[bi]["t"]) >= float(_bursts[bi]["dur"]):
			_bursts.remove_at(bi)
		else:
			bi += 1
	# 全員はけて配膳も尽きたら、締めの演出をひと幕やってから終了
	if _custs.is_empty() and _next >= _script.size() and _turnaway <= 0 and _extra_pend <= 0:
		_end_t += delta
		if _end_t >= 0.35:
			if _close <= 0.0:
				_burst(Vector2(size.x * 0.5, cy - 30.0), GOLD, 24.0, 210.0, 0.85)
				_pop = POP_DUR
				sfx_cue.emit("night_close")   # 拭く→のれん→木札→暗転 の入口
			_close += delta
			_wipe = _eio(clampf((_close - 0.10) / 0.95, 0.0, 1.0))
			if _close >= CLOSE_DUR:
				_finish()
	queue_redraw()


## 待っている間の仕草。時計を見る／隣と話す／体を揺らす／頭を掻く を
## 一人ずつ違う間隔で回す。同時に同じ動きをすると「群れ」になってしまう。
func _tick_gesture(c: Dictionary, delta: float) -> void:
	var gc := float(c.get("gcur", 0.0))
	if gc > 0.0:
		c["gcur"] = maxf(gc - delta, 0.0)
		return
	var gt := float(c.get("gt", 1.0)) - delta
	if gt <= 0.0:
		var sq := int(c.get("gseq", 0))
		c["g"] = sq % 4
		c["gseq"] = sq + 1 + (int(c.get("seed", 0)) % 3)
		c["gcur"] = 0.85
		gt = 0.85 + float(int(c.get("seed", 0)) % 9) * 0.17
	c["gt"] = gt


## のれん。短冊ごとにバネで揺れ、客が潜ると押される＝「今、人が入ってきた」が読める。
func _tick_noren(delta: float) -> void:
	if _noren.size() < NOREN_N:
		_noren = []
		for i in NOREN_N:
			_noren.append({"o": 0.0, "v": 0.0})
	for i in NOREN_N:
		var sx := _noren_x(i)
		var push := 0.0
		for c in _custs:
			var st := String(c["state"])
			if st != "in" and st != "out":
				continue
			var d := absf(float(c["x"]) - sx)
			if d < 54.0:
				push += float(c["dir"]) * (1.0 - d / 54.0) * 34.0
		var n: Dictionary = _noren[i]
		var v := float(n["v"])
		var o := float(n["o"])
		v += (push - o) * 34.0 * delta - v * 5.2 * delta
		n["v"] = v
		n["o"] = o + v * delta


## チップのコイン。前半は放物線、後半は伝票のチップ欄へ吸い込まれる。
func _tick_coins(delta: float) -> void:
	var i := 0
	while i < _coins.size():
		var c: Dictionary = _coins[i]
		var t := float(c["t"]) + delta
		c["t"] = t
		if t < 0.42:
			var v: Vector2 = c["v"]
			v.y += 900.0 * delta
			c["v"] = v
			c["p"] = (c["p"] as Vector2) + v * delta
		else:
			if not c.has("from"):
				c["from"] = c["p"]      # 放物線の終端を吸い込みの起点にする
			var k := clampf((t - 0.42) / 0.52, 0.0, 1.0)
			c["p"] = (c["from"] as Vector2).lerp(c["tgt"] as Vector2, _eio(k))
		if t >= 0.98:
			_coins.remove_at(i)
			_tip_pop = 0.42
		else:
			i += 1


func _burst(pos: Vector2, col: Color, r0: float, r1: float, dur: float) -> void:
	_bursts.append({"pos": pos, "t": 0.0, "col": col, "r0": r0, "r1": r1, "dur": dur})
	while _bursts.size() > 12:
		_bursts.pop_front()


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


func _waiting() -> int:
	var n := 0
	for c in _custs:
		if String(c["state"]) == "wait":
			n += 1
	return n


## 客をひとり入れる。serving は _script の添字（-1 は素材切れで帰す客）。
## bonus=true は「早出しで浮いた席へ滑り込んだ追い客」＝タップの上積み。
func _spawn(seat: int, serving: int, bonus: bool) -> void:
	_spawn_i += 1
	_seats[seat] = true
	# 先頭 regulars 人は常連（連続完走が連れてきた顔なじみ。チップ2倍）
	var is_reg := (not bonus) and serving >= 0 and serving < regulars
	var sd := (seat * 7 + maxi(serving, 0) * 13 + _spawn_i * 5 + day * 3) % 997
	var x0 := size.x + 54.0
	var sx := _seat_x(seat)
	# 我慢は客ごとに違う。ここが全員同じだと「どっちを先に出すか」が消える。
	var pat := PAT_BONUS if bonus else lerpf(PAT_MIN, PAT_MAX, float(sd % 17) / 16.0)
	_custs.append({"seat": seat, "x": x0, "x0": x0, "state": "in", "t": 0.0,
			"dur": clampf((x0 - sx) / WALK_IN, 0.85, 1.95),
			"serving": serving, "seed": sd, "sit": 0.0,
			# 位相・歩調・呼吸を一人ずつずらす。全員同位相は「人形の列」に見える。
			"ph": float(sd % 61) * 0.103, "wt": float(sd % 29) * 0.21,
			"br": 0.92 + float(sd % 9) * 0.075,
			"gt": 0.7 + float(sd % 7) * 0.31, "gcur": 0.0, "g": sd % 4, "gseq": sd,
			"joy": 0.0, "bt": 0.0, "angry": 0.0,
			"pat": pat, "pat0": pat, "bonus": bonus,
			"scarf": GOLD if is_reg else SCARF[(_spawn_i + seat) % SCARF.size()],
			"dir": -1.0, "regular": is_reg,
			"rname": REGULAR_NAMES[maxi(serving, 0) % REGULAR_NAMES.size()] if is_reg else ""})


## 自動給仕。店番は「残り我慢がいちばん少ない客」から出す＝プレイヤーと同じ優先順位。
##
## 放置しても罰しないのはここで担保している：
##  - 基本の客は RESCUE（残り0.55秒）で必ず店番が出す。混み合って店番の手が塞がっても、
##    我慢が0になった時点の分岐（_process の "wait"）で無条件に配膳する。取り逃しは起きない。
##  - 追い客だけは、プレイヤーが動いている間に限って自力で待つ。最後のタップから
##    IDLE_FORGIVE 秒が過ぎたら店番が引き受ける＝席を外した人は一皿も失わない。
func _tick_keeper(delta: float) -> void:
	_keeper_cd = maxf(_keeper_cd - delta, 0.0)
	if _keeper_cd > 0.0:
		return
	var forgive := (_t - _last_tap) >= IDLE_FORGIVE
	var best: Dictionary = {}
	var bp := 1e9
	for c in _custs:
		if String(c["state"]) != "wait":
			continue
		var p := float(c["pat"])
		var thr := RESCUE if (forgive or not bool(c.get("bonus", false))) else -1.0
		if p <= thr and p < bp:
			bp = p
			best = c
	if not best.is_empty():
		_keeper_cd = KEEPER_CD
		_serve(best, false)


## 配膳：待ち客に皿を出す。tapped=true はタップ給仕（チップが乗る）。
func _serve(c: Dictionary, tapped: bool) -> void:
	if String(c["state"]) != "wait":
		return
	c["state"] = "eat"
	c["t"] = 0.0
	var seat_x := _seat_x(int(c["seat"]))
	var cy := q(size.y * COUNTER_Y)
	var s: Dictionary = _script[int(c["serving"])]
	# 追い客の皿は「予報的中」の勘定に入れない（_matched と表示を食い違わせない）
	var hit := bool(s.get("match", false)) and not bool(c.get("bonus", false))
	_floats.append({"pos": Vector2(seat_x, cy - CUST_H + 30.0),
			"text": String(s["dish"]) + ("　★予報的中" if hit else ""),
			"col": CYAN if hit else TEXT, "t": 0.0})
	# 吹き出しが消える瞬間を「弾けた」ことにする（ふっと消えると気づかれない）
	var bub := Vector2(seat_x, cy - CUST_H - 42.0)
	_burst(bub, GOLD if not tapped else Color(1.0, 0.94, 0.76), 12.0, 66.0, 0.34)
	# 店番が身を乗り出して出す
	_keeper_lunge = 1.0
	_keeper_dir = signf(seat_x - size.x * KEEPER_X)
	# 皿を置く音。タップ給仕の時は tip_tapped（ui_buy＝コイン）が同じ瞬間に鳴るので
	# 重ねない＝4本のプールを1回の給仕で2本食わない。
	if not tapped:
		sfx_cue.emit("serve")
	if tapped:
		_last_tap = _t
		# 早出しで浮いた席の時間を貯める。SEAT_SEC ぶん貯まるごとに追い客がひとり入る。
		# 「早く回せば次が入る」を、プレイヤーの操作から直接引き出す。
		_saved += maxf(float(c.get("pat", 0.0)) - RESCUE, 0.0)
		while _saved >= SEAT_SEC and _extra_born + _extra_pend < EXTRA_MAX \
				and _next < _script.size():
			_saved -= SEAT_SEC
			_extra_pend += 1
			_bonus_pop = 0.75
			_floats.append({"pos": Vector2(size.x - 108.0, cy - CUST_H - 66.0),
					"text": "追い客がもう一人", "col": GOLD, "t": 0.0})
		# 常連はチップ2倍——顔なじみは覚えていてくれる
		var rate := 0.30 if bool(c.get("regular", false)) else 0.15
		var base_g := _per_plate if bool(c.get("bonus", false)) else int(s["gold"])
		var tip := maxi(int(base_g * rate), 1)
		_tips += tip
		_floats.append({"pos": Vector2(seat_x, cy - CUST_H - 6.0),
				"text": "チップ +%d" % tip, "col": GOLD, "t": 0.0})
		c["joy"] = 0.72                    # 客が喜ぶ（手応え）
		_tip_pop = 0.5
		_burst(bub, GOLD, 20.0, 132.0, 0.46)
		# コインが弾けて伝票のチップ欄へ吸い込まれる
		var tgt := Vector2(size.x - 132.0, size.y - 66.0)
		for i in 6:
			var a := -PI * 0.82 + PI * 0.64 * (float(i) / 5.0)
			var sp := 210.0 + float((int(c.get("seed", 0)) + i * 7) % 5) * 34.0
			_coins.append({"p": bub, "v": Vector2(cos(a), sin(a)) * sp, "t": 0.0,
					"tgt": tgt, "r": 6.0 + float(i % 3) * 1.5})
		tip_tapped.emit()


## 我慢が切れて帰る。理由を必ず言葉で出す（黙って消えると「バグ」に見える）。
## ここへ来るのは追い客だけ——プレイヤーがタップで呼び込み、動いている最中に放った客。
func _walk_out(c: Dictionary) -> void:
	var seat_x := _seat_x(int(c["seat"]))
	var cy := q(size.y * COUNTER_Y)
	_walked += 1
	_total = maxi(_total - 1, _served_shown)
	_gold_shown = maxi(_gold_shown - _per_plate, 0)     # 伝票の数字がその場で落ちる
	_pop = POP_DUR
	_lost_pop = 1.0
	_floats.append({"pos": Vector2(seat_x, cy - CUST_H - 30.0),
			"text": "待ちきれず帰った", "col": DENY, "t": 0.0})
	_floats.append({"pos": Vector2(seat_x, cy - CUST_H + 12.0),
			"text": "-%dG" % _per_plate, "col": DENY, "t": 0.0})
	_burst(Vector2(seat_x, cy - CUST_H - 42.0), DENY, 12.0, 108.0, 0.46)
	sfx_cue.emit("guest_leave")                         # 背を向けて出ていく音
	c["angry"] = 1.5                                    # 去り際まで✕の吹き出しを残す
	_leave(c)


## 席は「立ち上がり」の開始で空ける。次の客が歩き出せるので流れが途切れない。
func _leave(c: Dictionary) -> void:
	_seats[int(c["seat"])] = false
	c["state"] = "up"
	c["t"] = 0.0
	c["dir"] = 1.0 if float(c["x"]) > size.x * 0.42 else -1.0


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
	# 待ち客のタップ給仕。同時に複数が！になるので、重なった時は
	# 「いちばん近い客」を選ぶ（配列の先頭優先だと隣の客が出てしまう）。
	var cy := q(size.y * COUNTER_Y)
	var pick: Dictionary = {}
	var pd := 1e9
	for c in _custs:
		if String(c["state"]) != "wait":
			continue
		# 当たりは頭〜吹き出し（我慢ゲージ）まで含める。ゲージを狙って押せること。
		var r := Rect2(float(c["x"]) - 54.0, cy - CUST_H - 138.0, 108.0, CUST_H + 138.0)
		if r.has_point(p):
			var d := absf(float(c["x"]) - p.x)
			if d < pd:
				pd = d
				pick = c
	if not pick.is_empty():
		_serve(pick, true)
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

	# ── 7b. のれん（客はこの後ろを潜って出入りする）──────────────────
	_draw_noren(sz, art_top)

	# ── 8. 前板（下半身を隠す）＋天面の光る前縁 ─────────────────────
	_draw_apron(sz, cy)
	_draw_edge(sz, cy)
	_draw_wipe(sz, cy)

	# ── 9. 天面の上のもの（席札・おしぼり・出された皿）────────────
	_draw_counter_props(font, cy)

	# ── 10. 吹き出しとフロート ──────────────────────────────────────
	for c in _custs:
		_draw_bubble(font, c, cy)
	for f in _floats:
		var ft := float(f["t"])
		var a := clampf(1.0 - (ft - 0.9) / 0.5, 0.0, 1.0)
		# 立ち上がりは速く、上ほど減速して止まる（等速で流れると数字が読めない）
		var pos: Vector2 = (f["pos"] as Vector2) + Vector2(0, -40.0 * _eo(ft / 1.1))
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

	# ── 13. ヒント ＋ 席の回転メーター ──────────────────────────────
	_draw_flow(font, rec.position.y)
	if _t < 8.0:
		var hint := "！をタップで即・給仕 — チップと追い客が増える（放置でも店番が出す）"
		var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.S)).x
		var ha := clampf((8.0 - _t) / 1.2, 0.0, 1.0)
		var hr := Rect2(q((sz.x - hw) * 0.5 - 15.0), rec.position.y - 48.0, q(hw + 30.0), 33.0)
		_panel(hr, Color(0.04, 0.035, 0.06, 0.86 * ha), Color(GOLD.r, GOLD.g, GOLD.b, 0.40 * ha), 8, 1.0)
		_sh(font, Vector2(hr.position.x + 15, hr.position.y + 23), hint, int(FS.S), Color(TEXT.r, TEXT.g, TEXT.b, ha))

	# ── 14. ヘッダー（右端基点で右から積む）─────────────────────────
	_draw_header(font, sz)

	# ── 15. 粒子（チップのコイン・衝撃リング）──────────────────────
	_draw_coins()
	_draw_bursts()

	_vignette(sz)
	# 締めは暗く落として最後に灯りをひとつ残す（完全静止の黒画面を作らない）
	if _close > 0.0:
		var dim := _eio(clampf((_close - 1.05) / 1.3, 0.0, 1.0))
		if dim > 0.0:
			draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.015, 0.04, dim * 0.34))
			_glow(Vector2(sz.x * 0.5, q(sz.y * COUNTER_Y) - 150.0), sz.x * 0.5, LANT_WARM, 0.10 * (1.0 - dim))
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

## 提灯ごとに炎の周期も揺れの周期も変える。同じ sin を共有すると、
## 3つの灯りが「1枚の板」として点滅して見えてしまう。
const LANT_F := [2.7, 3.35, 4.15, 5.3, 3.9]
const LANT_G := [6.1, 7.7, 9.2, 5.9, 8.4]
const LANT_S := [0.37, 0.44, 0.31, 0.52, 0.41]     # 揺れの周期


func _flick(i: int) -> float:
	var n := i % LANT_F.size()
	return 1.0 + 0.055 * sin(_t * float(LANT_F[n]) + float(i) * 1.93) \
			+ 0.032 * sin(_t * float(LANT_G[n]) + float(i) * 0.71)


## 提灯の横揺れ（振り子）。芯の位置は動くが輝度は落とさない。
func _lsway(i: int) -> float:
	var n := i % LANT_S.size()
	return round((sin(_t * float(LANT_S[n]) * TAU * 0.32 + float(i) * 2.27) * 1.15
			+ 0.45 * sin(_t * float(LANT_S[n]) * TAU * 0.71 + float(i)))) * U


## 画面で最も明るい点はここ。芯を白に近い暖色で置き、周りへ光をこぼす。
func _draw_lanterns(sz: Vector2, art_top: float, cy: float) -> void:
	# 締めでは灯りを落として「店じまい」を作る（消しはしない）
	var dim := 1.0 - 0.30 * _eio(clampf((_close - 1.0) / 1.2, 0.0, 1.0))
	# 環境光は提灯より先に。芯の上に半透明を重ねると最明部が245を割る。
	_glow(Vector2(sz.x * 0.5, cy - 150.0), sz.x * 0.75, LANT_WARM, 0.10 * dim)
	_lantern(Vector2(q(sz.x * 0.22), 93.0), q(66.0), 20.0, _flick(0) * dim, _lsway(0))
	_lantern(Vector2(q(sz.x * 0.50), 93.0), q(105.0), 26.0, _flick(1) * dim, _lsway(1))
	_lantern(Vector2(q(sz.x * 0.78), 93.0), q(66.0), 20.0, _flick(2) * dim, _lsway(2))
	# カウンター上の小さな灯（客の顔を起こす）
	var li := 3
	for fx in [0.20, 0.80]:
		var lp := Vector2(q(sz.x * fx), q(art_top + 24.0))
		# 小さい灯も 3px 単位で揺らす（係数で割ると 1.5px が出てグリッドが崩れる）
		_lantern(lp - Vector2(0, 24.0), 24.0, 13.0, _flick(li) * dim, _lsway(li + 7))
		li += 1


func _lantern(top: Vector2, cord: float, r: float, flick: float, sway := 0.0) -> void:
	var by := q(top.y + cord)
	# 紐は上端で固定、下端が揺れる＝振り子として読める
	_pxdiag(Vector2(top.x, top.y), Vector2(top.x + sway, by), Color(0.22, 0.16, 0.10))
	top = Vector2(top.x + sway, top.y)
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


## のれん（入口）。客はこの後ろを潜って出入りし、短冊は押されて揺れる。
## 「今、人が入ってきた」を布の動きで先に知らせる＝出入りが唐突でなくなる。
## 幅も色も控えめに。提灯より目立つ赤い面を作ると、画面の主役が入れ替わる。
const NOREN_W := 96.0
const NOREN_CLOTH := Color(0.245, 0.115, 0.105)
const NOREN_RIM := Color(0.58, 0.32, 0.22)


func _noren_x(i: int) -> float:
	return q(size.x - NOREN_W + (float(i) + 0.5) * (NOREN_W / float(NOREN_N)))


func _draw_noren(sz: Vector2, art_top: float) -> void:
	if _noren.size() < NOREN_N:
		return
	var lift := _eo(clampf((_close - 0.45) / 0.95, 0.0, 1.0))       # 締めで巻き上げる
	# 裾の高さは「立っている客の頭がかすめ、座った客には掛からない」位置に置く。
	var y0 := q(art_top + 3.0 - lift * 21.0)
	var full := 66.0
	var hgt := q(full * (1.0 - lift * 0.86))
	if hgt < U:
		return
	var pitch := NOREN_W / float(NOREN_N)
	# 鴨居と竿（ここが入口の上端だと読ませる）
	draw_rect(Rect2(q(sz.x - NOREN_W - 18.0), y0 - 15, q(NOREN_W + 24.0), 12), Color(0.155, 0.105, 0.075))
	draw_rect(Rect2(q(sz.x - NOREN_W - 18.0), y0 - 15, q(NOREN_W + 24.0), 3), Color(0.32, 0.23, 0.14))
	draw_rect(Rect2(q(sz.x - NOREN_W - 12.0), y0 - 3, q(NOREN_W + 18.0), 3), Color(0.42, 0.31, 0.18))
	_glow(Vector2(sz.x - NOREN_W * 0.5, y0 + hgt * 0.4), 132.0, LANT_WARM, 0.07)
	for i in NOREN_N:
		var cxx := _noren_x(i)
		# 押された量（バネ）＋その短冊固有のそよぎ
		# 振れ幅は短冊の幅より小さく抑える。超えると布が裂けたように見える。
		var o := clampf(float(_noren[i]["o"]), -18.0, 18.0)
		var amb := sin(_t * (0.58 + float(i) * 0.11) + float(i) * 1.87) * 2.6 \
				+ 0.8 * sin(_t * (1.31 + float(i) * 0.07) + float(i) * 0.9)
		var yy := 0.0
		while yy < hgt:
			var f := yy / full                      # 下ほど大きく振れる（竿が支点）
			var dx := q((o + amb) * pow(f, 1.45))
			var band := NOREN_CLOTH.darkened(0.10 * sin(f * 3.4 + float(i)))
			draw_rect(Rect2(q(cxx - pitch * 0.5 + dx + 1.5), q(y0 + yy), q(pitch - 3.0), U), band)
			yy += U
		# 上端の光る縁と、染め抜きの文字（短冊ごとに位置が違う＝布が別々に揺れて見える）
		var dxt := q((o + amb) * pow(15.0 / full, 1.45))
		draw_rect(Rect2(q(cxx - pitch * 0.5 + dxt + 1.5), q(y0), q(pitch - 3.0), 3), NOREN_RIM)
		if hgt > 36.0:
			# 染め抜きは1短冊に1文字ぶん。細い線を並べると縞に戻ってしまう。
			var dxm := q((o + amb) * pow(30.0 / full, 1.45))
			draw_rect(Rect2(q(cxx - pitch * 0.26 + dxm), q(y0 + 24.0), q(pitch * 0.52), q(15.0)),
					Color(0.90, 0.85, 0.76, 0.82))
			draw_rect(Rect2(q(cxx - pitch * 0.12 + dxm), q(y0 + 27.0), q(pitch * 0.24), 6),
					NOREN_CLOTH.darkened(0.15))
		var dxb := q((o + amb) * pow(hgt / full, 1.45))
		draw_rect(Rect2(q(cxx - pitch * 0.5 + dxb + 1.5), q(y0 + hgt - 3.0), q(pitch - 3.0), 3),
				Color(0.12, 0.05, 0.05, 0.75))


## 締めの布巾。カウンターを拭いて、通った跡だけ天面が濡れて光る。
func _draw_wipe(sz: Vector2, cy: float) -> void:
	if _close <= 0.0 or _wipe <= 0.0 or _wipe >= 1.0:
		return
	var wx := q(lerpf(sz.x * 0.80, sz.x * 0.10, _wipe))
	# 濡れた跡（布巾の後ろ側）
	draw_rect(Rect2(wx, cy - SLAB_H + 3, q(sz.x * 0.80 - wx), SLAB_H - 6),
			Color(1.0, 0.88, 0.62, 0.16 * (1.0 - _wipe)))
	var flap: float = round(sin(_wipe * PI * 7.0) * 1.0) * U
	draw_rect(Rect2(wx - 24, cy - SLAB_H - 6 + flap, 48, SLAB_H + 6), Color(0.84, 0.80, 0.70))
	draw_rect(Rect2(wx - 24, cy - SLAB_H - 6 + flap, 48, 3), Color(0.96, 0.93, 0.86))
	draw_rect(Rect2(wx - 24, cy - 6 + flap, 48, 3), Color(0.42, 0.38, 0.34))
	_glow(Vector2(wx, cy - 9), 66.0, Color(1.0, 0.92, 0.74), 0.16)


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
		# 客がいる席の湯呑からは湯気が上がる。3px 単位で動く身体と違って
		# ここは連続して動くので、どの客のそばにも「止まらないもの」が必ずある。
		var sph := float(i) * 1.37
		for k in 2:
			var up := fmod(_t * (0.46 + float(i) * 0.045) + sph + float(k) * 0.5, 1.0)
			var swy := sin(_t * (1.7 + float(i) * 0.23) + sph + float(k) * 2.0) * 3.5
			draw_rect(Rect2(q(tc.x - 3.0 + k * 6.0 + swy), tc.y - 21.0 - up * 27.0, 2, 7.0 + up * 4.0),
					Color(1, 1, 1, (0.20 - k * 0.06) * (1.0 - up) * (1.0 - up * 0.4)))
		var c: Dictionary = occupied[i]
		# 席札（常連＝顔なじみ／追い客＝早出しで空いた席に入った客）
		var nm := ""
		if bool(c.get("bonus", false)):
			nm = "追い客"
		elif bool(c.get("regular", false)):
			nm = String(c.get("rname", "常連"))
		if nm != "":
			var nw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.XS)).x
			var pw := q(nw + 14.0)
			var pr := Rect2(q(x - pw * 0.5), cy - 18, pw, 15)
			draw_rect(Rect2(pr.position + Vector2(0, 3), pr.size), Color(0, 0, 0, 0.45))
			draw_rect(pr, Color(0.42, 0.31, 0.18))
			draw_rect(Rect2(pr.position, Vector2(pr.size.x, 2)), Color(0.66, 0.50, 0.30))
			draw_string(font, Vector2(pr.position.x + 7, pr.position.y + 11), nm,
					HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.XS), Color(1.0, 0.90, 0.66))
		# 出された皿。放物線で飛んできて、着地で潰れて跳ね、湯気が吹き上がる。
		if String(c["state"]) == "eat":
			var s: Dictionary = _script[int(c["serving"])]
			var ct := float(c["t"])
			var p := _plate_pos(c, cy)
			var land := clampf((ct - PLATE_FLY) / 0.45, 0.0, 1.0)
			var fly := clampf(ct / PLATE_FLY, 0.0, 1.0)
			# 飛んでいる間は動きの尾を引く（1コマだけ見えて消えるのを防ぐ）
			if fly < 1.0:
				for k in 3:
					var tp := _plate_pos({"seat": c["seat"], "t": maxf(ct - 0.035 * (k + 1), 0.0)}, cy)
					_ellipse(tp, Vector2(13.0 - k * 2.0, 4.0), Color(1.0, 0.86, 0.58, 0.20 - k * 0.06))
			if land > 0.0 and land < 1.0:
				_glow(p + Vector2(0, -6), lerpf(78.0, 24.0, land), Color(1.0, 0.88, 0.62),
						(1.0 - land) * 0.46)
				# 着地の砂ぼこり（左右へ散る短い横棒）
				for k2 in 2:
					var sgn := -1.0 if k2 == 0 else 1.0
					draw_rect(Rect2(q(p.x + sgn * (15.0 + 21.0 * land)), q(p.y + 3.0),
							9, 2), Color(1.0, 0.90, 0.70, (1.0 - land) * 0.45))
			if bool(s.get("match", false)):
				_glow(p + Vector2(0, -6), 42.0, CYAN, 0.24 + 0.10 * sin(_t * 3.7 + x * 0.05))
			# 着地の潰れ。皿だけスケールを掛けて重さを出す。
			var sq := _plate_squash(ct)
			if sq > 0.0:
				draw_set_transform(p, 0.0, Vector2(1.0 + sq, 1.0 - sq * 0.8))
				_dish(Vector2.ZERO, 33.0, _dish_kind(String(s["dish"])))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				_dish(p, 33.0, _dish_kind(String(s["dish"])))
			# 湯気：置かれた直後は勢いよく、そのあと細く長く上る
			if land > 0.02:
				var burst := 1.0 + (1.0 - land) * 1.6
				for k3 in 3:
					var wob := sin(_t * (1.55 + k3 * 0.37) + x * 0.031 + k3 * 2.1) * 6.0
					var rise := (27.0 + k3 * 9.0) * burst
					draw_rect(Rect2(q(p.x - 9.0 + k3 * 9.0 + wob), q(p.y - rise), 3, q(9.0 * burst)),
							Color(1, 1, 1, (0.24 - k3 * 0.05) * clampf(land * 3.0, 0.0, 1.0)))


const PLATE_FLY := 0.40      # 店番の手元から席へ皿が飛ぶ時間
const PLATE_BNC := 0.44      # 着地してから落ち着くまで


## 皿の位置。店番の手元から放物線で飛び、着地で二度バウンドして止まる。
## 横は ease-out（減速して置かれる）、縦は sin の弧＋減衰バウンド。
## 客の腕もここを終点にするので、皿と人が同じ1点を共有する。
func _plate_pos(c: Dictionary, cy: float) -> Vector2:
	var x := _seat_x(int(c["seat"]))
	var t := float(c["t"])
	var pt := clampf(t / PLATE_FLY, 0.0, 1.0)
	var px := q(lerpf(size.x * KEEPER_X, x + 51.0, _eo(pt)))
	var y0 := cy - 69.0                    # 店番の手元の高さ
	var y1 := cy - 12.0                    # 天面
	var py := lerpf(y0, y1, _eio(pt)) - 46.0 * sin(pt * PI)
	if pt >= 1.0:
		py = y1 - 15.0 * _bnc((t - PLATE_FLY) / PLATE_BNC)
	return Vector2(px, py)


## 着地の潰れ（横に広がって縦に縮む）。0 なら等倍。
func _plate_squash(t: float) -> float:
	var k := (t - PLATE_FLY) / 0.22
	if k < 0.0 or k > 1.0:
		return 0.0
	return sin(k * PI) * 0.30


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
	# 立っている間は背が伸びる（座ると沈む）。下半身は前板に隠れるので、
	# 「全高が変わる」ことが着席・起立の唯一の手がかりになる。
	var sit: float = clampf(float(c.get("sit", 1.0)), 0.0, 1.15)
	return {
		"h": CUST_H * (float(POSE_H[pose]) + jitter) * (1.0 + 0.185 * (1.0 - sit)),
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
		"lreach": Vector2.ZERO,
		"leat": 0.0,
		"chop": Vector2.ZERO,
		"hdx": 0.0,
		"hdy": 0.0,
		"swing": 0.0,
	}


## 客一人の描画。歩く／座る／待つ／食べる／立つ をここで身体の形に落とす。
func _draw_customer(c: Dictionary, cy: float) -> void:
	var st := String(c["state"])
	var walk := st == "in" or st == "out"
	var x := q(float(c["x"]))
	var sp := _cust_spec(c)
	var ph: float = float(c.get("ph", 0.0))
	var sit: float = clampf(float(c.get("sit", 1.0)), 0.0, 1.15)
	var bob := 0.0
	if walk:
		# 歩行の上下動。歩調は一人ずつ違う（同じ拍で揃うと行進に見える）
		var rate := 7.2 + float(int(c.get("seed", 0)) % 5) * 0.55
		var wt := float(c.get("wt", 0.0))
		bob = round(absf(sin(wt * rate + ph)) * 2.0) * U
		sp["swing"] = sin(wt * rate + ph)      # 腕振り
	else:
		# 呼吸。3px 単位で -1/0/+1 段だけ動かす＝ドット絵の「息をしている」量。
		# 3px の整数倍だけ動かす。1.5px を混ぜるとグリッドが崩れて絵がにじむ。
		var br: float = float(c.get("br", 1.0))
		bob = round(sin(_t * br + ph) * 0.7) * U
		# 胴・頭・横揺れの周期を大きくずらす。近い周期だと三つが同時に止まり、
		# 「息をしていない客」が 0.5 秒ぶん出てしまう。
		sp["hdy"] = round(sin(_t * br * 1.63 + ph + 0.9) * 0.55) * U
		sp["hdx"] = round(sin(_t * br * 0.47 + ph * 1.9) * 0.6) * U
	var base: float = q(cy + 9.0 + (1.0 - sit) * 12.0) - bob
	# 待っている間の仕草（時計を見る・隣と話す・体を揺らす・頭を掻く）
	if st == "wait" or st == "deny":
		_apply_gesture(c, sp, x, base, cy)
	# 食べている間は腕の終点を皿へ寄せる。腕が届くだけで「その皿はこの人のもの」になる。
	if st == "eat":
		var et := float(c["t"])
		var pp := _plate_pos(c, cy)
		sp["eat"] = _eo(clampf((et - PLATE_FLY * 0.5) / 0.42, 0.0, 1.0))
		# 皿↔口を往復する（箸を運ぶ）。1回ごとに頭が少し落ちる。
		var bite := clampf((et - PLATE_FLY - 0.20) / (EAT_DUR - PLATE_FLY - 0.25), 0.0, 1.0)
		var cyc := _eio(absf(sin(bite * PI * 2.6)))
		var mouth := Vector2(x + float(sp["hr"]) * 0.5, base - float(sp["h"]) + float(sp["hr"]) * 1.9)
		sp["reach"] = (pp + Vector2(-15.0, 6.0)).lerp(mouth, cyc * 0.88)
		sp["chop"] = pp + Vector2(-6.0, -6.0)      # 箸の先は器の中
		sp["hdy"] = float(sp["hdy"]) + round(cyc * 1.4) * U
		sp["hdx"] = float(sp["hdx"]) + round((1.0 - cyc) * 1.2) * U   # 器へ身を寄せる
		sp["look"] = 0.0
		sp["down"] = true
	# タップ給仕の反応：肩を上げて喜ぶ
	var joy: float = float(c.get("joy", 0.0))
	if joy > 0.0:
		var jk := sin(clampf(joy / 0.72, 0.0, 1.0) * PI * 3.0) * (joy / 0.72)
		base -= round(absf(jk) * 1.4) * U
		sp["hdy"] = float(sp["hdy"]) - round(absf(jk) * 1.0) * U
	base = q(base)
	# 影（天面に落ちる接地影）。立ち上がると薄く広がる。
	draw_rect(Rect2(x - float(sp["sw"]) - 6, cy - SLAB_H, float(sp["sw"]) * 2.0 + 12, 3),
			Color(0, 0, 0, 0.35 - 0.14 * (1.0 - sit)))
	# 濃い輪郭 → 暖色のリムライト → 本体
	for o in [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3), Vector2(0, 3)]:
		_person(x + o.x, base + o.y, sp, INK, true)
	# リムライトは提灯のある上側だけ（全周に回すとシール状になる）
	for o2 in [Vector2(0, -3), Vector2(-3, -3)]:
		_person(x + o2.x, base + o2.y, sp, RIM, true)
	_person(x, base, sp, INK, false)


## 仕草を身体の形に落とす。env は 0→1→0 の山なので入りも抜けも滑らか。
func _apply_gesture(c: Dictionary, sp: Dictionary, x: float, base: float, _cy: float) -> void:
	var gc := float(c.get("gcur", 0.0))
	if gc <= 0.0:
		return
	var gp := 1.0 - gc / 0.85
	var env := sin(clampf(gp, 0.0, 1.0) * PI)
	var h: float = sp["h"]
	var hr: float = sp["hr"]
	var head := Vector2(x, base - h + hr * 1.4)
	match int(c.get("g", 0)):
		0:   # 時計を見る（左手を顔の前へ・目線を落とす）
			sp["lreach"] = head + Vector2(-hr * 0.9, hr * 0.9)
			sp["leat"] = env
			sp["down"] = true
		1:   # 隣と話す（首を振ってうなずく）
			sp["look"] = float(sp["look"]) * 0.2 + signf(sin(float(c.get("ph", 0.0)) * 3.0)) * 0.9
			sp["hdx"] = float(sp["hdx"]) + round(env * 1.2) * U
			sp["hdy"] = float(sp["hdy"]) + round(absf(sin(gp * PI * 3.0)) * env * 1.2) * U
		2:   # 体を揺らす（退屈）
			sp["hdx"] = float(sp["hdx"]) + round(sin(gp * PI * 2.0) * env * 1.6) * U
		_:   # 頭を掻く
			sp["lreach"] = head + Vector2(-hr * 1.1, -hr * 1.0)
			sp["leat"] = env
			sp["hdy"] = float(sp["hdy"]) + round(env * 0.8) * U


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
	var hx := x + float(POSE_HEADDX[pose]) * (0.6 if down else 1.0) + float(sp.get("hdx", 0.0))
	var hcy := top + hr + 3.0 + (3.0 if pose == POSE_STOOP else 0.0) + float(sp.get("hdy", 0.0))
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
		# 服の陰影と前立て（べた塗りを避けて布に見せる）。
		# 頭が前傾・横揺れすると肩口の頂点が前立てを追い越して自己交差する
		# ＝三角形分割が失敗して陰影が丸ごと消える。順序を保証しておく。
		var v5x := x - sw * 0.42
		var v1x := minf(hx - 10.5, v5x - 3.0)
		draw_colored_polygon(PackedVector2Array([
				Vector2(v1x, sy - 15), Vector2(x - sw, sy + 3 + slope), Vector2(x - sw * 0.95, base),
				Vector2(x - sw * 0.45, base), Vector2(v5x, sy - 6)]),
				Color(0, 0, 0, 0.20))
		draw_rect(Rect2(x - 2, sy - 6, 4, base - sy + 6), cloth.darkened(0.35))
		draw_rect(Rect2(x - sw * 0.55, sy - 4 + slope * 0.4, 6, 4), cloth.lightened(0.25))
		draw_rect(Rect2(x + sw * 0.55 - 6, sy - 4 + slope * 0.4, 6, 4), cloth.lightened(0.25))
	# 腕。通常は天面へ、食事中は右腕の終点を皿へ寄せる（＝皿と人が繋がる）。
	# 歩行中は肩を支点に前後へ振る。仕草では左腕が顔や頭へ届く。
	var arm_y := base - 27.0
	var swing: float = sp.get("swing", 0.0)
	var lreach: Vector2 = sp.get("lreach", Vector2.ZERO)
	var leat: float = sp.get("leat", 0.0)
	for s in [-1.0, 1.0]:
		var sh := Vector2(x + s * (sw - 3), sy + slope * 0.6)
		var hand := Vector2(x + s * (sw + 4.5), arm_y)
		if swing != 0.0:
			hand += Vector2(swing * s * 9.0, -absf(swing) * 4.5)
		if eat > 0.0 and s > 0.0 and reach != Vector2.ZERO:
			hand = hand.lerp(reach, eat)
		if leat > 0.0 and s < 0.0 and lreach != Vector2.ZERO:
			hand = hand.lerp(lreach, leat)
		var d := (hand - sh)
		if d.length() < 1.0:
			d = Vector2(0, 1)
		var nrm := Vector2(-d.y, d.x).normalized() * 7.5
		draw_colored_polygon(PackedVector2Array([sh - nrm, sh + nrm, hand + nrm, hand - nrm]),
				cloth.darkened(0.28))
		if not use_flat:
			draw_rect(Rect2(q(hand.x - 7.5), q(hand.y - 7.5), 15, 10.5), skin)
		# 箸。手と器を繋ぐ細い2本。手が動くたびに角度が変わるので、
		# 3px 単位で止まりがちな身体に「連続して動くもの」がひとつ増える。
		var chop: Vector2 = sp.get("chop", Vector2.ZERO)
		if s > 0.0 and chop != Vector2.ZERO and eat > 0.35:
			var cd := (chop - hand).normalized()
			var cn := Vector2(-cd.y, cd.x) * 2.0
			for k in 2:
				var off := cn * (1.0 if k == 0 else -1.0)
				draw_colored_polygon(PackedVector2Array([
						hand + off, hand + off + cn * 0.6,
						chop + off * 0.4 + cn * 0.6, chop + off * 0.4]),
						flat if use_flat else Color(0.78, 0.66, 0.44))
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
				var sph := x * 0.041
				for k in 3:
					var wob := sin(_t * (1.12 + float(k) * 0.29) + sph + float(k) * 1.7) * 7.0
					var up := fmod(_t * 0.42 + sph + float(k) * 0.33, 1.0)
					draw_rect(Rect2(q(sx + 9 + wob), q(arm_y - 21.0 - k * 12.0 - up * 21.0), 3, 8),
							Color(1, 1, 1, (0.17 - k * 0.045) * (1.0 - up * 0.7)))
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


## 残りの我慢（0..1）。ゲージも枠の色もここ一箇所から出す＝表示が食い違わない。
func _pat_frac(c: Dictionary) -> float:
	return clampf(float(c.get("pat", 1.0)) / maxf(float(c.get("pat0", 1.0)), 0.01), 0.0, 1.0)


## 我慢の残りを色にする。金（余裕）→ 橙（そろそろ）→ 赤（切れる）。
## 切れる瞬間まで金のままだと、プレイヤーは選べない。
func _pat_col(f: float) -> Color:
	if f < 0.32:
		return DENY
	if f < 0.60:
		return Color(1.0, 0.62, 0.28)
	return GOLD


## 頭上の吹き出し：注文の料理アイコン＋皿の値段＋残りの我慢ゲージ。
## この3つが揃って初めて「どっちを先に出すか」が選べる。
func _draw_bubble(font: Font, c: Dictionary, cy: float) -> void:
	var st := String(c["state"])
	var angry: float = float(c.get("angry", 0.0))
	if st != "wait" and st != "deny" and angry <= 0.0:
		return
	# 帰っていく客の✕は素材切れと同じ形で出す（去った理由が去り際まで残る）
	var mode := "wait" if st == "wait" else "deny"
	var x := q(float(c["x"]))
	var sp := _cust_spec(c)
	var ph: float = float(c.get("ph", 0.0))
	var top := q(cy + 9.0) - float(sp["h"])
	var bw := 84.0
	var bh := 84.0 if mode == "wait" else 60.0
	# 客ごとに違う周期でふわりと上下する（全部同じだと看板に見える）
	var float_y: float = round(sin(_t * (2.05 + fmod(ph, 0.6)) + ph * 2.3) * 1.2) * U
	var by := q(top - bh - 18.0 + float_y)
	var f := _pat_frac(c) if mode == "wait" else 0.0
	# 切れかけほど速く脈打つ＝視界の端でも「急いでいる客」が拾える
	var rate := 4.4 + fmod(ph, 1.3) + (1.0 - f) * 9.0
	var pulse := 0.5 + 0.5 * sin(_t * rate + ph)
	var accent := _pat_col(f) if mode == "wait" else DENY
	var bx := clampf(q(x - bw * 0.5), 6.0, size.x - bw - 6.0)
	var r := Rect2(bx, by, bw, bh)
	# 出るときは弾んで開く。ぱっと出るとプレイヤーの目が拾えない。
	# スケール 0 は多角形が潰れて三角形分割に失敗する。最小値を残す。
	var pin := maxf(_eob(clampf(float(c.get("bt", 1.0)) / 0.24, 0.0, 1.0)), 0.08)
	if angry > 0.0:
		pin = maxf(clampf(angry / 1.5, 0.0, 1.0), 0.08)
	var piv := Vector2(x, by + bh + 15.0)
	if pin < 0.999:
		draw_set_transform(piv, 0.0, Vector2(pin, pin))
		_bubble_body(font, c, mode, Rect2(r.position - piv, r.size), Vector2(x, by) - piv, accent, pulse)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	_glow(Vector2(x, by + bh * 0.5), 84.0, accent, 0.14 + 0.14 * pulse)
	# 切れる直前は客ごと赤く縁取る。吹き出しの中だけだと視線が下に落ちた時に気づけない。
	if mode == "wait" and f < 0.32:
		_glow(Vector2(x, cy - CUST_H * 0.5), 120.0, DENY, 0.10 + 0.18 * pulse)
	_bubble_body(font, c, mode, r, Vector2(x, by), accent, pulse)


## 吹き出しの中身。ポップイン中は draw_set_transform 下で同じ形を描く。
func _bubble_body(font: Font, c: Dictionary, st: String, r: Rect2, anchor: Vector2,
		accent: Color, pulse: float) -> void:
	var bx := r.position.x
	var by := r.position.y
	var bw := r.size.x
	var bh := r.size.y
	var x := anchor.x
	# しっぽ
	draw_colored_polygon(PackedVector2Array([Vector2(x - 10.5, by + bh - 3), Vector2(x + 10.5, by + bh - 3),
			Vector2(x + 1.5, by + bh + 18)]), Color(0.97, 0.95, 0.92, 0.97))
	_panel(r, Color(0.97, 0.95, 0.92, 0.97), Color(accent.r, accent.g, accent.b, 0.5 + 0.5 * pulse), 10, 2.0)
	if st == "wait":
		var s: Dictionary = _script[int(c["serving"])]
		var bns := bool(c.get("bonus", false))
		var f := _pat_frac(c)
		# 器も少し呼吸する（客ごとに位相違い）
		var dz := 48.0 + sin(_t * 3.1 + float(c.get("ph", 0.0)) * 2.0) * 1.6
		_dish(Vector2(bx + bw * 0.5, by + bh * 0.40), dz, _dish_kind(String(s["dish"])), true)
		if bool(s.get("match", false)) and not bns:
			_pxcircle(Vector2(bx + bw - 15, by + 15), maxi(int(round((10.0) / U)), 1), Color(0.20, 0.62, 0.78))
			_sh(font, Vector2(bx + bw - 21, by + 20), "★", int(FS.XS), Color(0.95, 1.0, 1.0))
		# ① 皿の価値。アイコンだけでは「高い客」が分からず、選ぶ根拠が消える。
		var gt := "%dG" % (_per_plate if bns else int(s["gold"]))
		var gw := font.get_string_size(gt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.S)).x
		draw_string(font, Vector2(bx + (bw - gw) * 0.5, by + bh - 24.0), gt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.S), Color(0.34, 0.22, 0.08))
		# ② 残りの我慢。減っていくのが常に見えている＝切れる瞬間まで黙っていない。
		_patience_bar(Rect2(bx + 12.0, by + bh - 18.0, bw - 24.0, 7.0), f)
		# 「！」は切れかけほど大きく赤くなる（タップの手がかりは常に同じ位置）
		var eg := 1.0 + (1.0 - f) * 0.9
		var ex := bx + 12.0
		var ey := by + 15.0
		draw_rect(Rect2(ex - 2.0 * eg, ey - 9.0 * eg, 4.0 * eg, 13.0 * eg), accent)
		draw_rect(Rect2(ex - 2.0 * eg, ey + 6.0 * eg, 4.0 * eg, 4.0 * eg), accent)
	else:
		_pxdiag(Vector2(bx + 21, by + 18), Vector2(bx + bw - 21, by + bh - 18), Color(0.75, 0.25, 0.22), 2)
		_pxdiag(Vector2(bx + bw - 21, by + 18), Vector2(bx + 21, by + bh - 18), Color(0.75, 0.25, 0.22), 2)


## 我慢ゲージ。残量そのままの長さ＋4分割の目盛（何割残っているかが一瞬で読める）。
func _patience_bar(r: Rect2, f: float) -> void:
	draw_rect(Rect2(r.position + Vector2(0, 1), r.size), Color(0, 0, 0, 0.22))
	draw_rect(r, Color(0.28, 0.24, 0.21, 0.95))
	var col := _pat_col(f)
	if f < 0.32:
		# 切れる直前は明滅させる。色だけだと画面の端では気づけない。
		var bl := 0.62 + 0.38 * sin(_t * 17.0)
		col = Color(col.r, col.g * bl, col.b * bl)
	var w := maxf(r.size.x * f, 2.0)
	draw_rect(Rect2(r.position, Vector2(w, r.size.y)), col)
	draw_rect(Rect2(r.position, Vector2(w, 2.0)), Color(1, 1, 1, 0.42))
	for k in 3:
		draw_rect(Rect2(r.position.x + r.size.x * float(k + 1) / 4.0, r.position.y, 1.0, r.size.y),
				Color(0, 0, 0, 0.30))


# ── 店番 ──────────────────────────────────────────────────────────────

func _draw_keeper(sz: Vector2, cy: float) -> void:
	# 配膳の瞬間は席の方へ身を乗り出し、締めではカウンターを拭く動きに合わせて動く。
	var lean := _eo(clampf(_keeper_lunge * 2.4, 0.0, 1.0)) * _keeper_lunge * _keeper_dir
	# 締めの布巾は行って戻る。片道だけだと拭き終わりに店番がずれたまま残る。
	var wipe_off := sin(clampf(_wipe, 0.0, 1.0) * PI) * 42.0 if _close > 0.0 else 0.0
	var kx := q(sz.x * KEEPER_X + lean * 26.0 - wipe_off)
	# 立ち仕事の重心移動（提灯とも客とも違う周期）
	var kbob: float = round(sin(_t * 1.13 + 0.8) * 0.6) * U - round(absf(lean) * 1.6) * U
	_glow(Vector2(kx, cy - KEEPER_H * 0.55), 150.0, LANT_WARM, 0.24 + 0.10 * _keeper_lunge)
	if _keeper_frames.is_empty():
		return
	# 出す瞬間だけコマ送りを速める＝手が動いている
	var fr := _t * (3.0 + 5.0 * _keeper_lunge)
	var tex: Texture2D = _keeper_frames[int(fr) % _keeper_frames.size()]
	if tex == null:
		return
	var kh := q(KEEPER_H)
	var kw := q(kh * tex.get_width() / float(tex.get_height()))
	var kr := Rect2(q(kx - kw * 0.5), q(cy - 12.0 - kh + kbob), kw, kh)
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
		# 提灯の揺れがそのまま光柱の根元を動かす（灯りと床が繋がって見える）
		var lx := q(sz.x * float(lant_fx[li]) + _lsway(li) * 0.7)
		var col_h := h * (0.90 if li == 1 else 0.66)
		var base_w := 21.0 if li == 1 else 15.0
		var peak := (0.30 if li == 1 else 0.20) * (0.92 + 0.08 * _flick(li))
		var wr: float = [0.62, 0.83, 0.71][li]
		var yy := floor_y
		while yy < floor_y + col_h:
			var f := (yy - floor_y) / maxf(col_h, 1.0)
			var wdt := q(base_w * lerpf(1.0, 1.6, f))
			var wob := sin(f * (4.4 + li * 0.7) + _t * wr + li * 2.1) * 12.0 * f
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
	# 猫は等速で往復しない。歩いては立ち止まる（三角波を丸めた進み方）。
	var cph := _t * 0.22
	var cwalk := sin(cph) * 0.82 + sin(cph * 3.0) * 0.12
	_draw_cat(Vector2(q(sz.x * (0.5 + 0.32 * cwalk)), q(rec_top - 27.0)),
			cos(cph) * 0.82 + cos(cph * 3.0) * 0.36)
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
	# 立ちのぼる湯気（1本ずつ周期も上る速さも違う。同期すると簾のように見える）
	var top := base.y - 6.0 - 4 * 21.0 - 18.0
	for k in 4:
		var fr := 0.71 + float(k) * 0.23
		var w2 := sin(_t * fr + float(k) * 2.4) * 7.5 + 2.5 * sin(_t * fr * 2.3 + float(k))
		var up := fmod(_t * (0.30 + 0.07 * k) + float(k) * 0.27, 1.0)
		draw_rect(Rect2(q(base.x - 24.0 + k * 16.0 + w2), q(top - 12.0 - k * 6.0 - up * 42.0),
				3, q(15.0 + up * 9.0)), Color(1, 1, 1, 0.09 * (1.0 - up)))
	_glow(Vector2(base.x, top), 96.0, LANT_WARM, 0.06 + 0.012 * sin(_t * 1.41 + 0.7))


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
func _draw_cat(pos: Vector2, vel := 1.0) -> void:
	var dirx: float = signf(vel) if absf(vel) > 0.06 else 1.0
	var mov := clampf(absf(vel), 0.0, 1.0)
	var body := Color(0.035, 0.032, 0.055)
	# 歩いている時だけ体が上下する（止まっている猫は止まる）
	pos.y -= round(absf(sin(_t * 4.3)) * mov * 1.0) * U
	draw_rect(Rect2(pos.x - 27, pos.y + 8, 54, 6), Color(0, 0, 0, 0.4))
	_ellipse(pos, Vector2(24, 12), body)
	# 脚（歩いている）
	for s in [-1.0, 1.0]:
		var lg: float = round(sin(_t * 4.3 + (0.0 if s < 0.0 else PI)) * mov * 1.0) * U
		draw_rect(Rect2(pos.x + s * 12.0 - 3, pos.y + 4 + lg * 0.5, 6, 10 - lg * 0.5), body)
	var hx := pos.x + 20.0 * dirx
	# 立ち止まると耳が動く
	var ear: float = round(sin(_t * 1.9) * (1.0 - mov) * 1.2) * U
	pos.y += ear * 0.0
	_pxcircle(Vector2(hx, pos.y - 9 - ear * 0.5), maxi(int(round((10.5) / U)), 1), body)
	draw_colored_polygon(PackedVector2Array([Vector2(hx - 9, pos.y - 14),
			Vector2(hx - 3, pos.y - 25), Vector2(hx + 1, pos.y - 13)]), body)
	draw_colored_polygon(PackedVector2Array([Vector2(hx + 9, pos.y - 14),
			Vector2(hx + 3, pos.y - 25), Vector2(hx - 1, pos.y - 13)]), body)
	draw_rect(Rect2(q(hx + 1.5 * dirx), q(pos.y - 12), 4, 4), Color(1.0, 0.82, 0.4, 0.95))
	draw_rect(Rect2(q(hx - 6.0 * dirx), q(pos.y - 12), 4, 4), Color(1.0, 0.82, 0.4, 0.75))
	var tx := pos.x - 21.0 * dirx
	var sway := sin(_t * 2.2) * 7.5 + sin(_t * 3.7 + 1.2) * 3.5
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
	# 伸びるのは実数ではなく追従値。跳ねずに、しかし遅れて伸びる。
	if _frac_disp > 0.0:
		var fw := maxf(pb.size.x * _frac_disp, 6.0)
		draw_rect(Rect2(pb.position, Vector2(fw, pb.size.y)), GOLD)
		draw_rect(Rect2(pb.position, Vector2(fw, 2)), Color(1.0, 0.94, 0.72))
		# 先端が走る（伸びている最中だけ明るい）
		var frac := clampf(float(_served_shown) / maxf(_total, 1.0), 0.0, 1.0)
		var run := clampf((frac - _frac_disp) * 14.0, 0.0, 1.0)
		_glow(Vector2(pb.position.x + fw, pb.position.y + 3), 33.0 + 30.0 * run, GOLD, 0.45 + 0.35 * run)

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
			# スロットへ「落ちて入る」。上から降りてきて、縁が一度光る。
			var age := float(pl.get("t", 9.0))
			var dk := clampf(age / 0.46, 0.0, 1.0)
			var drop := q(-30.0 * (1.0 - _eo(dk)) + 12.0 * _bnc(dk))
			var flash := clampf(1.0 - age / 0.55, 0.0, 1.0)
			var sc := Vector2(cx, cyy + drop)
			if dk < 1.0:
				_glow(sc, ring * (2.6 + 2.0 * (1.0 - dk)), GOLD, 0.30 * flash)
			if bool(pl["match"]):
				_glow(sc, ring * 2.2, CYAN, 0.30)
				_pxring(sc, ru, Color(CYAN.r, CYAN.g, CYAN.b, 0.9))
			else:
				_pxring(sc, ru, Color(1, 1, 1, 0.16 + 0.70 * flash))
			_dish(Vector2(sc.x, sc.y + pitch * 0.13), pitch * 0.62, int(pl["kind"]))
			if flash > 0.0:
				_pxring(Vector2(cx, cyy), maxi(int(round(ring * (1.0 + 1.6 * (1.0 - flash)) / U)), 2),
						Color(1.0, 0.92, 0.66, flash * 0.5), 1)
		else:
			# 未配膳＝伏せた空皿。これから埋まる余白として読ませる
			_pxring(Vector2(cx, cyy), ru, Color(1, 1, 1, 0.11))
			_ellipse(Vector2(cx, cyy + pitch * 0.08), Vector2(ring * 0.72, ring * 0.27), Color(1, 1, 1, 0.09))
			_ellipse(Vector2(cx, cyy + pitch * 0.05), Vector2(ring * 0.52, ring * 0.19), Color(0, 0, 0, 0.30))

	# 売上（大きく・コイン付き・カウントアップ）
	draw_rect(Rect2(r.position.x + 18, gy - 63, r.size.x - 36, 1.5), Color(1, 1, 1, 0.10))
	var coin := Vector2(r.position.x + 45.0, gy - 21.0)
	# 加算の瞬間は減衰バネで跳ねる（山を1つ描くだけだと「大きくなった」で終わる）
	var pk := 1.0
	if _pop > 0.0:
		var u := POP_DUR - _pop
		pk = 1.0 + 0.26 * exp(-7.0 * u) * cos(u * 26.0)
	var dpop := _eo(clampf(_digit_pop / 0.55, 0.0, 1.0)) * (_digit_pop / 0.55)
	pk += dpop * 0.22                                   # 桁が増えた瞬間はさらに大きく
	_glow(coin, 60.0 + 60.0 * dpop, GOLD, 0.22 + 0.35 * dpop)
	draw_set_transform(coin, sin(_t * 0.9) * 0.02 + dpop * 0.30, Vector2(pk, pk))
	_coin(Vector2.ZERO, 21.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var gs := "%d" % int(round(_gold_disp))
	var gw := font.get_string_size(gs, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.XL)).x
	var gp := Vector2(coin.x + 36.0, gy)
	if dpop > 0.0:
		_pxring(Vector2(gp.x + gw * 0.5, gp.y - 15.0),
				maxi(int(round(lerpf(90.0, 24.0, dpop) / U)), 2), Color(1.0, 0.94, 0.70, dpop * 0.55), 1)
	draw_set_transform(gp, 0.0, Vector2(pk, pk))
	draw_string(font, Vector2(2, 3), gs, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.XL), Color(0, 0, 0, 0.6))
	# 桁が増えた瞬間だけ白へ寄せる＝夜の格が一段上がった合図
	var gcol := Color(1.0, 0.88, 0.52).lerp(Color(1.0, 1.0, 0.94), dpop)
	draw_string(font, Vector2.ZERO, gs, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.XL), gcol)
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
	# 上積みの内訳。売上の大きな数字が「なぜ」動いたかを同じ画面で言い切る。
	var brk_y := gy - 33.0
	if _walked > 0:
		var lo := "待ちきれず %d人 −%dG" % [_walked, _walked * _per_plate]
		var lw := font.get_string_size(lo, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.S)).x
		var lk := 1.0 + 0.22 * _lost_pop
		var lp := Vector2(stamp.x - 39.0 - lw, brk_y)
		if _lost_pop > 0.0:
			_glow(Vector2(lp.x + lw * 0.5, brk_y - 5), 84.0, DENY, 0.30 * _lost_pop)
		draw_set_transform(lp, 0.0, Vector2(lk, lk))
		draw_string(font, Vector2(1, 1), lo, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.S), Color(0, 0, 0, 0.55))
		draw_string(font, Vector2.ZERO, lo, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.S), DENY)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		brk_y -= 21.0
	if _extra_served > 0:
		var ex := "追い客 %d人 +%dG" % [_extra_served, _extra_served * _per_plate]
		var ew := font.get_string_size(ex, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.S)).x
		var ek := 1.0 + 0.22 * _bonus_pop
		var ep := Vector2(stamp.x - 39.0 - ew, brk_y)
		if _bonus_pop > 0.0:
			_glow(Vector2(ep.x + ew * 0.5, brk_y - 5), 84.0, GOLD, 0.30 * _bonus_pop)
		draw_set_transform(ep, 0.0, Vector2(ek, ek))
		draw_string(font, Vector2(1, 1), ex, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.S), Color(0, 0, 0, 0.55))
		draw_string(font, Vector2.ZERO, ex, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.S), GOLD)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var ts := ("チップ +%dG" % _tips) if _tips > 0 else "チップ　—"
	var tcol := GOLD if _tips > 0 else TEXT_DIM
	var tw := font.get_string_size(ts, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.M)).x
	# コインが着いた瞬間に跳ねる＝タップの手応えがここまで繋がる
	var tk := 1.0
	if _tip_pop > 0.0:
		var tu := 0.5 - _tip_pop
		tk = 1.0 + 0.30 * exp(-8.0 * tu) * cos(tu * 30.0)
	if _tips > 0:
		_glow(Vector2(stamp.x - 39.0 - tw * 0.5, gy - 15), 90.0 + 60.0 * _tip_pop, GOLD, 0.14 + 0.30 * _tip_pop)
	var tp := Vector2(stamp.x - 39.0 - tw, gy - 9)
	draw_set_transform(tp, 0.0, Vector2(tk, tk))
	draw_string(font, Vector2(1, 1), ts, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.M), Color(0, 0, 0, 0.55))
	draw_string(font, Vector2.ZERO, ts, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.M), tcol)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 締めの木札（最後の客が帰ったあと、画面を静止させないための一手）
	_draw_closing(font, r, Vector2(gp.x + gw * 0.5, gp.y - 18.0))


## 席の回転メーター。早出しで浮かせた時間が貯まると追い客がひとり入る——
## その「あと少し」が見えないと、タップが上積みに繋がっている実感が出ない。
func _draw_flow(font: Font, rec_top: float) -> void:
	if _saved <= 0.0 and _extra_born <= 0:
		return
	var r := Rect2(q(18.0), q(rec_top - 90.0), q(198.0), 33.0)
	var lit := clampf(_bonus_pop / 0.75, 0.0, 1.0)
	_panel(r, Color(0.04, 0.035, 0.06, 0.86), Color(GOLD.r, GOLD.g, GOLD.b, 0.35 + 0.5 * lit), 8, 1.0)
	_sh(font, Vector2(r.position.x + 10.0, r.position.y + 22.0), "回転", int(FS.XS), TEXT_DIM)
	var bar := Rect2(r.position.x + 42.0, r.position.y + 13.0, 66.0, 7.0)
	draw_rect(bar, Color(0, 0, 0, 0.5))
	var f := clampf(_saved / SEAT_SEC, 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(maxf(bar.size.x * f, 2.0), bar.size.y)), GOLD)
	draw_rect(Rect2(bar.position, Vector2(maxf(bar.size.x * f, 2.0), 2.0)), Color(1.0, 0.94, 0.72))
	if lit > 0.0:
		_glow(Vector2(bar.position.x + bar.size.x, bar.position.y + 3.0), 42.0 + 42.0 * lit, GOLD, 0.40 * lit)
	var bt := "追い客 %d人" % _extra_born
	_sh(font, Vector2(bar.position.x + bar.size.x + 9.0, r.position.y + 22.0), bt, int(FS.XS), GOLD)


## 締め：木札が上から落ちてバウンドし、売上に光の輪が広がる。
func _draw_closing(font: Font, r: Rect2, gold_at: Vector2) -> void:
	if _close <= 0.0:
		return
	var k := clampf((_close - 0.75) / 0.85, 0.0, 1.0)
	if k <= 0.0:
		return
	# 売上を一度だけ大きく囲む
	var rk := clampf((_close - 0.75) / 0.9, 0.0, 1.0)
	if rk < 1.0:
		_pxring(gold_at, maxi(int(round(lerpf(30.0, 190.0, _eo(rk)) / U)), 2),
				Color(1.0, 0.92, 0.66, (1.0 - rk) * (1.0 - rk) * 0.55), 1)
	var txt := "完売御礼" if _served_shown >= maxi(_total, 1) else "本日の営業 終了"
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.M)).x
	var pw := q(tw + 48.0)
	var ph := 45.0
	var ty := r.position.y - 60.0
	# 落ちて弾む（等速で降りると「板が滑り込んだ」に見える）
	var y := ty - 96.0 * (1.0 - _eo(k)) + 15.0 * _bnc(k)
	var px := q(r.position.x + (r.size.x - pw) * 0.5)
	var tilt := sin(k * PI * 3.0) * (1.0 - k) * 0.06
	draw_rect(Rect2(px + pw * 0.5 - 2, y - 24, 4, 24), Color(0.34, 0.26, 0.15))
	draw_set_transform(Vector2(px + pw * 0.5, y), tilt, Vector2.ONE)
	var lr := Rect2(-pw * 0.5, 0, pw, ph)
	draw_rect(Rect2(lr.position + Vector2(3, 5), lr.size), Color(0, 0, 0, 0.5))
	draw_rect(lr, Color(0.44, 0.33, 0.19))
	draw_rect(Rect2(lr.position, Vector2(pw, 3)), Color(0.70, 0.55, 0.32))
	draw_rect(Rect2(lr.position.x, lr.position.y + ph - 3, pw, 3), Color(0.16, 0.11, 0.07))
	draw_string(font, Vector2(-tw * 0.5 + 1, 31), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.M),
			Color(0, 0, 0, 0.5))
	draw_string(font, Vector2(-tw * 0.5, 30), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FS.M),
			Color(1.0, 0.93, 0.74))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_glow(Vector2(px + pw * 0.5, y + ph * 0.5), 132.0, GOLD, 0.14 * k)


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


## 湯気。位置から位相と周期を作る＝画面に並んだ器が一斉に同じ揺れをしない。
func _steam(c: Vector2, s: float) -> void:
	var u := s / 12.0
	var ph := c.x * 0.037 + c.y * 0.021
	var fr := 2.4 + fmod(absf(c.x) * 0.013 + absf(c.y) * 0.007, 1.5)
	var w := sin(_t * fr + ph) * u * 0.55
	var rise := fmod(_t * (0.5 + fr * 0.1) + ph, 1.0)      # 立ちのぼって消える周期
	for i in 2:
		var sx := c.x - s * 0.16 + i * s * 0.32 + w * (1.0 if i == 0 else -1.0)
		var dy := rise * u * 1.6
		draw_rect(Rect2(q(sx), c.y - u * 4.4 - dy, 2, u * 1.4), Color(1, 1, 1, 0.24 * (1.0 - rise * 0.5)))
		draw_rect(Rect2(q(sx + 2), c.y - u * 5.8 - dy, 2, u * 1.2), Color(1, 1, 1, 0.16 * (1.0 - rise)))


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
		var r := lerpf(9.0, 60.0, e)
		_pxcircle(p, maxi(int(round(r / U)), 1), Color(1, 1, 1, (1.0 - k) * 0.07))
		_pxring(p, maxi(int(round(r / U)), 1), Color(1, 1, 1, (1.0 - k) * 0.42), 1)
		# 二重の輪（遅れて追いかける）で「押した」感触を強くする
		var k2 := clampf(k * 1.8 - 0.35, 0.0, 1.0)
		if k2 > 0.0 and k2 < 1.0:
			_pxring(p, maxi(int(round(lerpf(6.0, 33.0, 1.0 - pow(1.0 - k2, 2.0)) / U)), 1),
					Color(1.0, 0.90, 0.66, (1.0 - k2) * 0.34), 1)
		i += 1


## チップのコイン。回転を横幅で表し、伝票のチップ欄へ吸い込まれて消える。
func _draw_coins() -> void:
	for c in _coins:
		var p: Vector2 = c["p"]
		var t := float(c["t"])
		var a := clampf(1.0 - (t - 0.72) / 0.26, 0.0, 1.0)
		var rr: float = c["r"]
		var spin := absf(cos(t * 15.0 + rr))
		var w := maxf(q(rr * 2.0 * spin), U)
		var h := q(rr * 2.0)
		_glow(p, rr * 4.5, GOLD, 0.22 * a)
		draw_rect(Rect2(q(p.x - w * 0.5), q(p.y - h * 0.5), w, h), Color(0.62, 0.42, 0.14, a))
		draw_rect(Rect2(q(p.x - w * 0.5), q(p.y - h * 0.5 + U), w, maxf(h - U * 2.0, U)),
				Color(1.0, 0.84, 0.36, a))
		draw_rect(Rect2(q(p.x - w * 0.5), q(p.y - h * 0.5 + U), maxf(w * 0.4, U), U),
				Color(1.0, 0.96, 0.74, a))


## 衝撃の輪。配膳・タップ・締めの「今」を1点に集める。
func _draw_bursts() -> void:
	for b in _bursts:
		var k := clampf(float(b["t"]) / float(b["dur"]), 0.0, 1.0)
		var e := _eo(k)
		var r := lerpf(float(b["r0"]), float(b["r1"]), e)
		var a := (1.0 - k) * (1.0 - k)
		var col: Color = b["col"]
		_pxring(b["pos"], maxi(int(round(r / U)), 1), Color(col.r, col.g, col.b, a * 0.55), 1)
		_glow(b["pos"], r * 1.15, col, a * 0.16)


## 影付きテキスト。
func _sh(font: Font, pos: Vector2, s: String, size_px: int, col: Color) -> void:
	draw_string(font, pos + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(0, 0, 0, 0.55))
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, col)
