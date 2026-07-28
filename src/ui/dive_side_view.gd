class_name DiveSideView
extends Control
## 潜航の横スクロールステージ（タスクバーヒーロー型）。
## 構図：左＝接続ポータル＋ステージ章票、中央左＝隊列（チビキャラが右へ行進）、
## 右＝敵がスライドイン、下＝石畳の帯、奥＝ネオン都市のパララックス。
## 頭上にHPミニバー＋スキルCDピップ。main.gd が毎フレーム set_view() で駆動する。

const GROUND_Y := 0.80      # 地面ラインの画面比（キャラを画面下寄りに＝背景に空間を渡す）
const FOOT_UI_H := 132.0    # 下部カードUIの高さ（床はここまで伸ばして黒地を作らない）
const PARTY_X0 := 84.0      # 隊列先頭のx（非戦闘時は PARTY_ROAM_X だけ右へ寄る）
const PARTY_GAP := 66.0     # 隊列間隔
const PARTY_ROAM_X := 120.0 # 非戦闘時に隊列を右へ寄せる量（右半分を空にしない）
const ENEMY_X0 := 0.64      # 敵スロット先頭（画面比）
const ENEMY_GAP := 90.0

# ── 拡大率はすべて整数（非整数倍の NEAREST がテクセル割れの原因）──────────
# 表示サイズは「ピクセル高さ × 整数倍率」でしか決めない。
# 絵の大きさを変えたいときは PIX_H を動かす（倍率は動かさない）。
const PIX_MULT := 2         # アクター／背景レイヤーの共通拡大率（整数）
const GIRL_PIX_H := 56      # 味方スプライトのピクセル高さ → 112px 表示
const GIRL_H := 112.0       # = GIRL_PIX_H * PIX_MULT（頭上UIの逃げ幅計算に使う）
const MOB_PIX_H := 79       # 雑魚の「見えている」ピクセル高さ → 158px 表示
const BOSS_PIX_H := 132     # ボスの「見えている」ピクセル高さ → 264px 表示
const MOB_H := 158.0
const BOSS_H := 264.0
const MOB_DIR := "res://assets/generated/sprites/"   # 敵も味方と同じ生成スプライト系
const MOB_FRAMES := 4       # walk_front.png は 4 コマの横ストリップ

# 事前リサンプル済みの背景（元PNGを 0.65 / 0.75 倍で書き出し、ランタイムは 2倍固定）
const BG_FAR := "res://assets/generated/bg/city_far_x2.png"    # 468x195 → 936x390
const BG_MID := "res://assets/generated/bg/city_mid_x2.png"    # 540x182 → 1080x364
const MID_SRC_H := 242.0    # city_mid_x2 の元になった帯の高さ（SIGNS 座標の換算用）
const MID_SRC_TOP := 18.0   # 元PNGから捨てた上端の無地帯

# 文字サイズは5段だけ（12 / 16 / 22 / 32 / 48）。リテラルを増やさない。
const FS_S := 12
const FS_M := 16
const FS_L := 22
const FS_XL := 32

const PINK := Color(1.0, 0.36, 0.72)
const CYAN := Color(0.35, 0.92, 1.0)
const PURPLE := Color(0.66, 0.4, 1.0)
const GOLD := Color(1.0, 0.82, 0.4)
const HP_COL := Color(0.45, 0.9, 0.5)
# 敵の輪郭は上下で分ける：上半分＝月色のリムライト、下半分＝影。
# 赤の全周キーラインは被弾フレーム（0.1秒）だけに予約する。
const RIM_LIGHT := Color(0.55, 0.70, 1.0, 0.7)
const RIM_SHADOW := Color(0.05, 0.02, 0.08, 0.9)
const HIT_LINE := Color(0.92, 0.14, 0.18, 0.95)     # 被弾フレームだけの赤
const ALLY_LINE := Color(0.02, 0.02, 0.06, 0.85)
const NEON_CORE := Color(0.95, 1.0, 1.0)            # 純白は「見るべき場所」だけに使う
const STRUCT := Color(0.03, 0.02, 0.08)             # 上部に垂れる構造体シルエット

# 背景の看板を実在の語に置き換える（city_mid.png に焼かれた「実在しない漢字」を覆う）。
# rect は元 city_mid.png（720x260）のソース座標＝焼かれた看板の実測位置。
# 色相はオレンジを使わない（オレンジは「敵／危険」に予約する）。
const SIGNS := [
	{"r": Rect2(228, 66, 94, 42), "t": "深層", "c": Color(0.40, 0.95, 1.0), "v": false},
	{"r": Rect2(130, 80, 86, 28), "t": "営業中", "c": Color(1.0, 0.42, 0.78), "v": false},
	# 旧「二十四時」は画面最強のオレンジだった。値を40%落とし、色相も青紫へ退避する。
	{"r": Rect2(484, 22, 162, 52), "t": "二十四時", "c": Color(0.40, 0.37, 0.62), "v": false},
	{"r": Rect2(46, 18, 28, 90), "t": "麺処", "c": Color(0.86, 0.30, 0.46), "v": true},
	{"r": Rect2(330, 30, 24, 78), "t": "電脳", "c": Color(0.55, 0.65, 1.0), "v": true},
	{"r": Rect2(454, 16, 24, 84), "t": "黒猫", "c": Color(0.86, 0.78, 0.42), "v": true},
	{"r": Rect2(670, 54, 50, 26), "t": "酒場", "c": Color(0.45, 1.0, 0.80), "v": false},
	{"r": Rect2(0, 66, 22, 28), "t": "湯", "c": Color(0.62, 0.78, 0.92), "v": false},
]

# 階層ごとのパレット（25分の間に色が変わることが時間経過の唯一の証拠になる）。
# [空の上端, 空の地平, 看板の色相回転, 床の手前色]
const FLOOR_PAL := [
	{"top": Color(0.09, 0.04, 0.18), "hor": Color(0.26, 0.08, 0.30),
			"hue": 0.00, "floor": Color(0.27, 0.23, 0.35)},
	{"top": Color(0.04, 0.07, 0.17), "hor": Color(0.09, 0.20, 0.32),
			"hue": 0.42, "floor": Color(0.19, 0.26, 0.34)},
	{"top": Color(0.10, 0.04, 0.10), "hor": Color(0.30, 0.09, 0.18),
			"hue": 0.78, "floor": Color(0.30, 0.20, 0.26)},
	{"top": Color(0.03, 0.09, 0.12), "hor": Color(0.08, 0.26, 0.26),
			"hue": 0.20, "floor": Color(0.18, 0.28, 0.30)},
]

# set_view() で main.gd から毎フレーム
var dist := 0.0
var in_combat := false
var party: Array = []       # [{id, hp, mhp, ready, slots}]
var mobs: Array = []        # [{sprite, hp, boss}]
var gold_gain := 0
var difficulty := 0         # 難易度（章票の色とラベルに使う）

var _t := 0.0
# ── 二つの時計 ───────────────────────────────────────────────────────
# _t  ＝ 実時間。背景・パララックス・吹き出しなど「世界の流れ」に使う。
# _ct ＝ 戦闘時計。ヒットストップ中は進めない。敵・味方の芝居・戦闘FX・カメラは
#        すべてこちらを見るので、当たった瞬間だけ「敵とエフェクトだけ」が止まる。
#        下部UI（dive_overlay）は別ノードで自前の時計を持つので影響しない。
var _ct := 0.0
var _hitstop := 0.0               # 残りヒットストップ（実時間・秒）
# 止める長さ。オクトパストラベラーII 準拠で「通常は数フレーム／会心は倍以上」。
const HS_HIT := 0.045             # 通常の被打（60fpsで約3コマ）
const HS_CRIT := 0.115            # 会心（約7コマ）
const HS_HURT := 0.035            # 味方の被弾（2秒に1回なので短く）
const HS_KILL := 0.075            # 撃破
const HS_ELITE := 0.11            # エリート撃破
const HS_BOSS := 0.16             # ボス撃破
const KNOCK_DUR := 0.42           # のけぞり（当たった瞬間が最大→行き過ぎ→収束）
const APPROACH_DUR := 0.55        # 敵が奥から定位置へ寄るまで
const DEATH_LEAD := 0.16          # 撃破の予備動作（白飛び→潰れ）→ 破片までの間
var _anims: Dictionary = {}       # girl_id -> ChibiAnim
var _tex_cache: Dictionary = {}   # path -> Texture2D|null
var _pix_cache: Dictionary = {}   # path -> ピクセル化済み Texture2D|null（タスクバーヒーロー密度）
var _enemy_x: Array = []          # 敵スロットの現在x（奥から近づく）
var _enemy_t0: Array = []         # 敵スロットの出現時刻（接近の予備動作の基準・_ct）
var _enemy_land: Array = []       # 着地（定位置到達）時刻。-9.9＝まだ着いていない
var _mob_hp0: Array = []          # 敵スロットの初期HP（バー比率用）
var _last_mob_count := 0
var _form_x := 0.0                # 隊列の横オフセット（非戦闘時は右へ寄る）

# ── カメラ（punch）────────────────────────────────────────────────────
# ランダムな毎フレームぶれは「振動」であって「打撃」ではない。方向を持った減衰振動に
# する。25分見続ける画面なので短く（0.20秒）小さく（実効の最大変位は会心で約2.4px、
# ボス撃破でも約5px）で頭打ち。punch の引数は 0〜1 でクランプする。
const SHAKE_DUR := 0.20
const SHAKE_PX := 14.0
var _shake := 0.0                 # 強度 0〜1
var _shake_t0 := -9.9             # _ct 基準
var _shake_dir := Vector2(-0.94, 0.34)
var _shake_flip := 1.0            # 連打でも同じ方向に偏らせない

# ── 実体アンカーの戦闘FX（ダメージ数字・斬撃・被弾・スキルバースト）──
var _party_pos: Array = []   # 直近フレームの味方足元（floaterの追従先）
var _enemy_pos: Array = []   # 直近フレームの敵足元
var _floaters: Array = []    # {txt, col, side, slot, t0, jx}
var _slashes: Array = []     # 敵への斬撃 {slot, t0}
var _hurt_t := -9.9          # 盾役の被弾時刻（赤フラッシュ＋ノックバック）
var _party_hurt: Array = []  # 味方ごとの被弾時刻（頭上HPは被弾後0.8秒だけ出す）
var _bursts: Array = []      # スキルバースト {kind, t0}
var _striker := -1           # 直近で「殴った」味方（踏み込み演出）
var _strike_t := -9.9
var _knock: Array = []       # 敵スロットののけぞり {t0, mag}｜null
var _enemy_draw: Array = []  # 直近フレームの敵の描画情報（撃破の予備動作に使い回す）

# ── 撃破（2.5秒に1体）と同期率レベルアップの演出 ────────────────────────
# 出しすぎると画面が埋まるので、フロータは12個・破裂は6個で頭打ちにして古い順に捨てる。
const FLOAT_MAX := 12
const POP_MAX := 6
var _pops: Array = []        # 撃破の破裂 {p, t0, elite, boss}
# 「会心」の判定：sim は会心を期待値で DPS に畳んでいて per-hit のフラグを持たない。
# そこで UI 側は sim が実際に起こした2つの事実だけを見る——
#   ① 直前に技（fx イベント）が飛んだ＝決め手の一撃
#   ② その数字が直近の移動平均を明確に超えた＝装備や同期率で火力が跳ねた瞬間
# 数字そのものは sim の値をそのまま出す。大きさと白さの判定だけがUIの仕事。
var _fx_t := -9.9
var _lv_t := -9.9            # レベルアップ時刻（足元からの光柱）
var _lv_res := false         # その回が共鳴（Lv3/6/9/12）かどうか＝光柱の格を上げる

# ── 会話劇（戦闘・道中の掛け合い吹き出し。Banter 駆動）──
var _bubble: Dictionary = {}       # 表示中の吹き出し {gid, text, t0, dur}
var _bubble_q: Array = []          # 掛け合いの残り行 [[gid, text], ...]
var _banter_rng := RandomNumberGenerator.new()
## 直近にしゃべった本文（新しい順）。素の乱択だと25分で重複72%になるので、
## ここに積んで Banter 側で避けてもらう。長さは在庫の目安（1キャラ16本×人数）より
## 小さくしないと候補が枯れて逆効果になる。
var _banter_recent: Array = []
## 直前に起きた出来事（"boss"/"wipe"/"levelup"/"loot"/"gate"）。
## 少し経ったら空へ戻す＝「さっきの話」でいられる時間だけ反応させる。
var _last_event := ""
var _last_event_t := 0.0
const LAST_EVENT_SEC := 25.0
const BANTER_RECENT_MAX := 32
var _banter_wait := 3.0            # 次の自発バンターまでの秒
var _banter_cd: Dictionary = {}    # カテゴリ別クールダウン（最終発話時刻）
var _was_combat := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(true)


# ── イージング。この画面の動きは必ずここを通す（等速の演出は一つも置かない）──
## 速く出て静かに止まる。p を上げるほど「頭が速い」。
static func _e_out(u: float, p := 3.0) -> float:
	return 1.0 - pow(1.0 - clampf(u, 0.0, 1.0), p)


## 立ち上がりも収めも滑らかに（光柱の伸縮・明滅はこれだけを使う）。
static func _e_in_out(u: float) -> float:
	var x := clampf(u, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## 一度行き過ぎてから収まる（のけぞりの戻り・数字の飛び出し）。
static func _e_back(u: float, over := 1.28) -> float:
	var x := clampf(u, 0.0, 1.0) - 1.0
	return 1.0 + (over + 1.0) * x * x * x + over * x * x


## 減衰振動。u=0 で 1、途中で 0 を跨ぎ、わずかに行き過ぎてから収束する。
static func _e_recoil(u: float) -> float:
	if u <= 0.0:
		return 1.0
	return exp(-3.0 * u) * cos(5.6 * u)


func _process(delta: float) -> void:
	_t += delta
	# 出来事の時効。ずっと「さっきボスがいた」と言い続けないように。
	if _last_event != "" and _t - _last_event_t > LAST_EVENT_SEC:
		_last_event = ""
	# ヒットストップ：実時間で数えて、戦闘時計だけを止める。
	# delta のうち「止まっていた分」だけを差し引く（フレームが長い端末で
	# 1フレーム丸ごと止めてしまわない＝止める長さが fps に依存しない）。
	var cd := delta
	if _hitstop > 0.0:
		var used := minf(_hitstop, delta)
		_hitstop -= used
		cd = delta - used
	_ct += cd
	for id in _anims:
		(_anims[id] as ChibiAnim).tick(cd)
	# 非戦闘時は隊列を右へ寄せ、交戦時は左の定位置へ戻す（右半分を空にしない）。
	# 係数は指数減衰でフレームレートに依らせない（lerp の固定係数は fps 依存）。
	var target_fx := 0.0 if in_combat else PARTY_ROAM_X
	_form_x += (target_fx - _form_x) * (1.0 - exp(-delta * 3.0))
	_update_enemies(cd)
	# 吹き出し：表示時間が尽きたら掛け合いの次の行へ（0.25s の間を置く）
	if not _bubble.is_empty() and _t - float(_bubble["t0"]) > float(_bubble["dur"]):
		_bubble = {}
		if not _bubble_q.is_empty():
			var ln: Array = _bubble_q.pop_front()
			_say(String(ln[0]), String(ln[1]), 0.25)
	# 自発バンター：間が空いたら独り言か掛け合い（戦闘中は戦闘の話をする）
	if _bubble.is_empty() and _bubble_q.is_empty():
		_banter_wait -= delta
		if _banter_wait <= 0.0:
			_banter_wait = _banter_rng.randf_range(6.0, 10.0)
			var cast := _alive_cast()
			if not cast.is_empty():
				if _banter_rng.randf() < (0.5 if in_combat else 0.3):
					var ex := Banter.pick_exchange(cast, _banter_rng, _banter_recent)
					if not ex.is_empty():
						_start_exchange(ex)
				else:
					var pick := Banter.pick("combat" if in_combat else "idle", cast, _banter_rng, _banter_recent, _ctx())
					if not pick.is_empty():
						_say(String(pick["girl"]), String(pick["text"]))
	queue_redraw()


## 生存している潜行メンバーの id 一覧（バンターの話者候補）。
func _alive_cast() -> Array:
	var out: Array = []
	for p in party:
		if float(p["hp"]) > 0.0:
			out.append(String(p["id"]))
	return out


## 吹き出しを1つ表示（delay 秒後から表示扱い＝掛け合いの間）。
func _say(gid: String, text: String, delay := 0.0) -> void:
	_bubble = {"gid": gid, "text": text, "t0": _t + delay,
			"dur": clampf(text.length() * 0.13, 1.9, 4.6)}
	_note_said(gid, text)


## しゃべった本文を直近履歴へ積む（新しいものが先頭）。
func _note_said(gid: String, text: String) -> void:
	_banter_recent.push_front({"girl": gid, "text": text})
	while _banter_recent.size() > BANTER_RECENT_MAX:
		_banter_recent.pop_back()


## 掛け合い（2〜3行の応酬）を開始。
func _start_exchange(ex: Dictionary) -> void:
	var lines: Array = (ex.get("lines", []) as Array).duplicate()
	if lines.is_empty():
		return
	var first: Array = lines.pop_front()
	_bubble_q = lines
	_say(String(first[0]), String(first[1]))


## 状況イベントに反応して喋る。chance で頻度を、interrupt で割り込みを制御。
## カテゴリ毎に12秒のクールダウン（交戦は数秒毎に起きるため喋りすぎ防止）。
func _banter_event(cat: String, chance: float, interrupt := false) -> void:
	if _t - float(_banter_cd.get(cat, -99.0)) < 12.0:
		return
	if not interrupt and (not _bubble.is_empty() or not _bubble_q.is_empty()):
		return
	if _banter_rng.randf() > chance:
		return
	var cast := _alive_cast()
	if cast.is_empty():
		return
	# 戦闘開始は35%で掛け合いに発展（戦いながら会話が広がる）
	if cat == "combat" and _banter_rng.randf() < 0.35:
		var ex := Banter.pick_exchange(cast, _banter_rng, _banter_recent)
		if not ex.is_empty():
			_banter_cd[cat] = _t
			_bubble = {}
			_start_exchange(ex)
			return
	var pick := Banter.pick(cat, cast, _banter_rng, _banter_recent, _ctx())
	if pick.is_empty():
		return
	_banter_cd[cat] = _t
	if interrupt:
		_bubble_q = []
	_bubble = {}
	_say(String(pick["girl"]), String(pick["text"]))
	_banter_wait = maxf(_banter_wait, 5.0)


## 敵スロットの接近／定位置を毎フレーム進める（描画側は結果を読むだけ）。
## 交戦の開始を唐突にしないため、敵は「奥の小さい影」から定位置へ ease-out で寄る。
func _update_enemies(cd: float) -> void:
	var n := mobs.size()
	_enemy_x.resize(n)
	_enemy_t0.resize(n)
	_enemy_land.resize(n)
	if n == 0 or size.x <= 0.0:
		return
	var egap := minf(ENEMY_GAP, (size.x * 0.34) / maxf(n - 1.0, 1.0))
	for i in n:
		var boss: bool = bool((mobs[i] as Dictionary).get("boss", false))
		var slot_x := size.x * (ENEMY_X0 - 0.04) + i * egap + (26.0 if boss else 0.0)
		var t0: float = float(_enemy_t0[i]) if _enemy_t0[i] != null else -9.9
		var u := _approach(i)
		if u < 1.0:
			# 接近中：奥（画面右・やや上・小さい）から定位置へ。頭が速く尻が静かな ease-out。
			var sx := size.x * 0.99
			_enemy_x[i] = sx + (slot_x - sx) * _e_out(u, 2.6)
		else:
			# 定位置：隊列が組み替わったときだけ指数で追従（瞬間移動させない）
			var cur: float = float(_enemy_x[i]) if _enemy_x[i] != null else slot_x
			# 前の敵が倒れて枠が空いたときの詰め寄り。速すぎると死骸と重なって読めないので
			# 0.3秒くらいかけて「次の一体が前へ出る」ように寄せる。
			_enemy_x[i] = cur + (slot_x - cur) * (1.0 - exp(-cd * 5.0))
			var landed: float = float(_enemy_land[i]) if _enemy_land[i] != null else -9.9
			if landed < t0:
				_enemy_land[i] = _ct        # 着地の瞬間（土煙と小さな punch）
				punch(0.10)


## 敵スロットの接近進行度 0〜1（1＝定位置に着いた）。
func _approach(i: int) -> float:
	if i >= _enemy_t0.size() or _enemy_t0[i] == null:
		return 1.0
	return clampf((_ct - float(_enemy_t0[i])) / APPROACH_DUR, 0.0, 1.0)


## のけぞりの現在量（px・正＝味方から遠ざかる向き）。
## 当たった瞬間が最大で、ease-out で戻り、わずかに行き過ぎてから収まる。
func _knock_offset(i: int) -> float:
	if i >= _knock.size() or _knock[i] == null:
		return 0.0
	var e: Dictionary = _knock[i]
	var u := (_ct - float(e["t0"])) / KNOCK_DUR
	if u < 0.0 or u >= 1.0:
		return 0.0
	return float(e["mag"]) * _e_recoil(u)


## 戦闘のカメラシェイク（main の punch 互換）。
## 方向を持った減衰振動。既に強い揺れが走っているときは上書きしない（重ねて増幅させない）。
func punch(mag := 0.3) -> void:
	var m := clampf(mag, 0.0, 1.0)
	if m * SHAKE_PX <= absf(_shake_amp()):
		return
	_shake = m
	_shake_t0 = _ct
	_shake_flip = -_shake_flip
	_shake_dir = Vector2(-0.94 * _shake_flip, 0.34)


## 現在のカメラ変位（px）。0.20秒で収まる短い減衰振動。
func _shake_amp() -> float:
	if _shake <= 0.0:
		return 0.0
	var u := (_ct - _shake_t0) / SHAKE_DUR
	if u < 0.0 or u >= 1.0:
		return 0.0
	return _shake * SHAKE_PX * exp(-4.2 * u) * sin(u * TAU * 2.6)


## main.gd から毎フレーム：sim の実データを流し込む。
func set_view(d: Dictionary) -> void:
	dist = float(d.get("dist", dist))
	var new_combat := bool(d.get("in_combat", false))
	if new_combat and not _was_combat:
		_banter_event("combat", 0.7)
	_was_combat = new_combat
	in_combat = new_combat
	party = d.get("party", [])
	mobs = d.get("mobs", [])
	gold_gain = int(d.get("gold_gain", gold_gain))
	difficulty = int(d.get("diff", difficulty))
	# 隊列アニメの用意＆パラメーター更新（戦闘中は攻撃を周期リトリガー）
	for i in party.size():
		var id := String(party[i]["id"])
		if not _anims.has(id):
			_anims[id] = ChibiAnim.new(id)
		var dead: bool = float(party[i]["hp"]) <= 0.0
		var atk_pulse := in_combat and fposmod(_ct + i * 0.53, 1.7) < 1.15
		(_anims[id] as ChibiAnim).update_params(0.0 if in_combat else 1.0, atk_pulse, false, dead)
	# 敵スロット：新しい群れが来たら「奥から近づく」の起点時刻を打つ。
	# 一体ずつ 0.09 秒ずらす＝一斉にスライドインさせない（列が生き物に見える）。
	_enemy_t0.resize(mobs.size())
	_enemy_land.resize(mobs.size())
	if mobs.size() > _last_mob_count:
		for i in mobs.size():
			if i >= _mob_hp0.size():
				_mob_hp0.append(float(mobs[i]["hp"]))
			elif i >= _last_mob_count:
				_mob_hp0[i] = float(mobs[i]["hp"])
			if i >= _last_mob_count:
				_enemy_t0[i] = _ct + i * 0.09
				_enemy_land[i] = -9.9
				if i < _enemy_x.size():
					_enemy_x[i] = size.x * 0.99
	_last_mob_count = mobs.size()
	for i in mini(mobs.size(), _mob_hp0.size()):
		_mob_hp0[i] = maxf(_mob_hp0[i], float(mobs[i]["hp"]))


## main.gd から潜航イベントを受け取り、実体に紐づくFXへ変換する。
## 「誰が殴って→誰に当たって→いくら出たか」の因果を1画面で読めるようにする。
func add_events(events: Array) -> void:
	for e in events:
		# 「さっき何が起きたか」を控える。セリフの文脈に使う（after）。
		var k := String(e.get("kind", ""))
		if k in ["boss", "resync", "levelup", "loot", "gate"]:
			_last_event = "wipe" if k == "resync" else k
			_last_event_t = _t
		match k:
			"dmg_pop":
				var val := int(e.get("val", 0))
				if String(e.get("at", "enemy")) == "enemy":
					# 与ダメ：sim は必ず隊列の先頭（mobs[0]）を削るので、斬撃も数字も
					# スロット0に落とす（＝画面の因果と sim の因果を一致させる）。
					var slot := 0
					# 会心は sim が拍ごとに判定してフラグで流してくる。推測しない。
					# （以前は「技の直後」「火力が跳ねた」で当てにいっていたが外れる）
					var crit := bool(e.get("crit", false))
					# ① 全部止める。会心は倍以上長く止める＝「当たった感触」の芯。
					_hitstop = maxf(_hitstop, HS_CRIT if crit else HS_HIT)
					# 同じ場所に積まないよう横も縦もばらす（重なると数字が読めなくなる）
					_floaters.append({"txt": ("%d!" % val) if crit else str(val),
							"col": Color(1, 1, 1) if crit else Color(0.93, 0.95, 1.0),
							"side": "enemy", "slot": slot, "t0": _ct,
							"jx": randf_range(-34.0, 34.0), "jy": randf_range(-20.0, 4.0),
							"crit": crit})
					# rt は実時間。白飛びだけは実時間で抜く＝ヒットストップが
					# 「白い塊」を保持しない（止めて見せたいのは のけぞりの姿勢）。
					_slashes.append({"slot": slot, "t0": _ct, "rt": _t})
					if slot < _knock.size():
						# ② のけぞり。会心は倍ちかく押し込む
						_knock[slot] = {"t0": _ct, "mag": 22.0 if crit else 11.0}
					if crit:
						punch(0.26)
					_striker = _next_striker()
					_strike_t = _ct
				else:
					# 被ダメ：盾役（先頭の生存者）の頭上に赤数字＋赤フラッシュ
					_hitstop = maxf(_hitstop, HS_HURT)
					_floaters.append({"txt": "-%d" % val, "col": Color(1.0, 0.42, 0.45), "side": "party",
							"slot": _tank_index(), "t0": _ct, "jx": randf_range(-10.0, 10.0),
							"crit": false})
					_hurt_t = _ct
					var ti := _tank_index()
					if ti >= 0 and ti < _party_hurt.size():
						_party_hurt[ti] = _ct
				while _floaters.size() > FLOAT_MAX:
					_floaters.pop_front()
			"kill":
				# 2.5秒に1回。敵が弾けて、その撃破で入った金（sim の実値）が飛ぶ。
				_on_kill(e)
			"levelup":
				_lv_t = _ct
				_lv_res = String(e.get("res_name", "")) != ""
				punch(0.5 if _lv_res else 0.3)
			"fx":
				_fx_t = _ct
				_bursts.append({"kind": String(e.get("fx", "")), "t0": _ct})
				while _bursts.size() > 4:
					_bursts.pop_front()
			"boss":
				_banter_event("boss", 1.0, true)
			"loot", "door_loot":
				_banter_event("loot", 0.35)
			"gate":
				_banter_event("gate", 0.7)
			"resync":
				_banter_event("wipe", 1.0, true)
			"door":
				_banter_event("door", 0.8)


## 撃破の瞬間。sim の kill イベント（gold / ing / elite / boss）をそのまま画に変える。
## 数字は一切こちらで作らない。出しすぎ防止のため破裂とフロータは上限で切る。
func _on_kill(e: Dictionary) -> void:
	var boss := bool(e.get("boss", false))
	var elite := bool(e.get("elite", false))
	# 破裂の位置＝いま殴っている先頭スロット（居なければ敵スロット先頭の定位置）
	var p := Vector2(size.x * ENEMY_X0, size.y * GROUND_Y)
	if not _enemy_pos.is_empty() and _enemy_pos[0] != null:
		p = _enemy_pos[0]
	# 撃破の予備動作：sim は撃破した瞬間に mobs から消すので、直近フレームの絵を
	# ここで押さえておき「白く飛ぶ→潰れる→破片」の順に見せる（消えただけにしない）。
	var death: Dictionary = {}
	if not _enemy_draw.is_empty() and _enemy_draw[0] != null:
		death = (_enemy_draw[0] as Dictionary).duplicate()
	_hitstop = maxf(_hitstop, HS_BOSS if boss else (HS_ELITE if elite else HS_KILL))
	# 破片は予備動作が終わってから出す（t0 を DEATH_LEAD だけ後ろへ置く）
	_pops.append({"p": p, "t0": _ct + DEATH_LEAD, "t_die": _ct, "rt_die": _t,
			"death": death, "elite": elite, "boss": boss})
	while _pops.size() > POP_MAX:
		_pops.pop_front()
	var g := int(e.get("gold", 0))
	if g > 0:
		_floaters.append({"txt": "+%dG" % g, "col": GOLD, "side": "fixed", "plate": true,
				"pos": p + Vector2(randf_range(-10.0, 18.0), -MOB_H * 0.95),
				"t0": _ct + DEATH_LEAD, "jx": 0.0, "jy": 0.0, "crit": false})
	var ing := String(e.get("ing", ""))
	if ing != "":
		_floaters.append({"txt": "%s+%d" % [String(KuroData.ING_NAMES.get(ing, ing)),
				int(e.get("ing_n", 1))], "col": CYAN, "side": "fixed", "plate": true,
				"pos": p + Vector2(randf_range(-24.0, 6.0), -MOB_H * 1.20),
				"t0": _ct + DEATH_LEAD + 0.14, "jx": 0.0, "jy": 0.0, "crit": false})
	while _floaters.size() > FLOAT_MAX:
		_floaters.pop_front()
	punch(0.55 if boss else (0.30 if elite else 0.20))


## 次に「殴った」ことにする味方（生存者を巡回）。
func _next_striker() -> int:
	if party.is_empty():
		return -1
	for step in party.size():
		var i := (_striker + 1 + step) % party.size()
		if float(party[i]["hp"]) > 0.0:
			return i
	return -1


## 盾役＝隊列先頭の生存者。
func _tank_index() -> int:
	for i in party.size():
		if float(party[i]["hp"]) > 0.0:
			return i
	return 0


func _tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[path]


## 味方チビを GIRL_PIX_H へ事前リサンプルし、α を2値化する（＝ここが唯一の非整数縮小）。
## 描画側は必ず PIX_MULT の整数倍でしか貼らないので、画面上でテクセルは割れない。
## GIRL_PIX_H=56 × PIX_MULT=2 → 112px、敵は MOB_PIX_H=79 × 2 → 158px で密度が揃う。
func _pix_tex(path: String) -> Texture2D:
	if _pix_cache.has(path):
		return _pix_cache[path]
	var t: Texture2D = null
	var src := _tex(path)
	if src != null:
		var img0 := src.get_image()
		if img0 != null:
			img0 = img0.duplicate()
			if img0.is_compressed():
				img0.decompress()
			img0.convert(Image.FORMAT_RGBA8)
			var sh := maxf(img0.get_height(), 1.0)
			var aspect := img0.get_width() / sh
			# ① 下見：いったん GIRL_PIX_H まで落として、絵が縦のどこにどれだけ在るか測る。
			var probe := img0.duplicate()
			probe.resize(maxi(int(round(GIRL_PIX_H * aspect)), 1), GIRL_PIX_H,
					Image.INTERPOLATE_BILINEAR)
			_binarize(probe)
			_strip_matte(probe)
			var p0 := _scan_pads(probe, 0, probe.get_width())
			# ② 本番：「見えている高さ」が GIRL_PIX_H になる寸法へ、元画像から一度だけ落とす。
			#    攻撃コマはキャンバスの下71%にしか描かれておらず、そのまま貼ると
			#    フレーム毎に身長が3割変わる。ここで正規化して整数倍だけで貼れるようにする。
			var vis := maxf(1.0 - p0.x - p0.y, 0.20)
			var nh := maxi(int(round(GIRL_PIX_H / vis)), GIRL_PIX_H)
			var nw := maxi(int(round(nh * aspect)), 1)
			var img := img0
			img.resize(nw, nh, Image.INTERPOLATE_BILINEAR)
			_binarize(img)
			_strip_matte(img)
			var pads := _scan_pads(img, 0, nw)
			# 壊れたフレーム（地が焼かれて抜けなかった／絵が数pxしか無い／横ストリップ）は
			# 使わない。null を返すと呼び出し側が idle_f0 にフォールバックする。
			var opq := 0
			for y in nh:
				for x in nw:
					if img.get_pixel(x, y).a > 0.5:
						opq += 1
			if float(opq) / float(maxi(nw * nh, 1)) > 0.88 \
					or pads.x + pads.y > 0.62 or _is_strip(img, nw):
				_pix_cache[path] = null
				return null
			_pad_cache[path] = pads
			t = ImageTexture.create_from_image(img)
	_pix_cache[path] = t
	return t


## αを2値化（本物のドット絵はソフトエッジを持たない）＋クロマキーの縁を中和する。
## 生成スプライトの縁にはマゼンタ（g がほぼ0で r≒b）が焼き残っており、
## そのまま2値化するとキャラの周りにピンクの輪が出る。暗い無彩色の縁へ置き換える。
func _binarize(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			c.a = 1.0 if c.a > 0.42 else 0.0
			if c.a > 0.0 and c.g < minf(c.r, c.b) * 0.45 and minf(c.r, c.b) > 0.05:
				var v := (c.r + c.g + c.b) * 0.33 * 0.55
				c = Color(v, v, v * 1.15, 1.0)
			img.set_pixel(x, y, c)


## 生成スプライトの一部（kiriko/attack_f5.png など26枚）は「1コマ」の名前で
## 2〜3コマの横ストリップが焼かれている。そのまま貼るとキャラが分身して見えるので弾く。
## 判定：不透明な列のかたまりが2つ以上あり、2番目も幅7px（42px中）以上あるもの。
## 武器の軌跡は細い（2〜5px）ので巻き込まない。弾いたフレームは idle_f0 に落ちる。
func _is_strip(img: Image, w: int) -> bool:
	var h := img.get_height()
	var groups: Array[int] = []
	var run := 0
	for x in w:
		var solid := false
		for y in h:
			if img.get_pixel(x, y).a > 0.42:
				solid = true
				break
		if solid:
			run += 1
		else:
			if run > 0:
				groups.append(run)
			run = 0
	if run > 0:
		groups.append(run)
	if groups.size() < 2:
		return false
	groups.sort()
	return groups[groups.size() - 2] >= maxi(int(w * 0.16), 4)


var _white_cache: Dictionary = {}
var _pad_cache: Dictionary = {}       # key -> Vector2(上余白率, 下余白率)
var _mob_frames: Dictionary = {}      # "<sprite>:<f>" -> 反転済み1コマ Texture2D
var _enemy_top: Array = []            # 敵スロットの見た目の頭y


## 一部の生成フレーム（mil の *_f0 など）は背景（マゼンタ/白）が不透明で焼き込まれており、
## そのまま描くとキャラの後ろに色板が出る。外周リングの支配色を「地」とみなし、
## 縁から連結した同色だけを抜く（キャラ内部の同系色は残る）。
func _strip_matte(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	if w < 6 or h < 6:
		return
	# 不透明領域のバウンディングボックスを求める
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
	# 「地」は矩形なので、bbox の4隅が同色なら焼き込み背景と判定する。
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
	var seed: Color = seeds[best]
	var seen := PackedByteArray()
	seen.resize(w * h)
	# 画像の縁から（透明部分を通って）地の矩形へ到達し、連結した同色だけを抜く
	var q: Array[Vector2i] = []
	for x in w:
		q.append(Vector2i(x, 0))
		q.append(Vector2i(x, h - 1))
	for y in h:
		q.append(Vector2i(0, y))
		q.append(Vector2i(w - 1, y))
	var i := 0
	while i < q.size():
		var p: Vector2i = q[i]
		i += 1
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
			continue
		var key := p.y * w + p.x
		if seen[key] != 0:
			continue
		var c := img.get_pixel(p.x, p.y)
		if c.a > 0.5 and absf(c.r - seed.r) + absf(c.g - seed.g) + absf(c.b - seed.b) > 0.28:
			continue
		seen[key] = 1
		img.set_pixel(p.x, p.y, Color(c.r, c.g, c.b, 0.0))
		q.append(Vector2i(p.x + 1, p.y))
		q.append(Vector2i(p.x - 1, p.y))
		q.append(Vector2i(p.x, p.y + 1))
		q.append(Vector2i(p.x, p.y - 1))


## 画像の x0..x1 列を走査し (上の透明率, 下の透明率) を返す。
## 下の透明率でスプライトを押し下げると靴底が床に着く（浮きの根治）。
func _scan_pads(img: Image, x0: int, x1: int) -> Vector2:
	var h := img.get_height()
	var top := -1
	var bot := -1
	for y in h:
		var solid := false
		for x in range(x0, x1):
			if img.get_pixel(x, y).a > 0.35:
				solid = true
				break
		if solid:
			if top < 0:
				top = y
			bot = y
	if top < 0:
		return Vector2.ZERO
	return Vector2(float(top) / float(h), float(h - 1 - bot) / float(h))


## ヒットフラッシュ／輪郭用の白シルエット（α>0 を白に）。
func _white_tex(path_key: String, src: Texture2D) -> Texture2D:
	if _white_cache.has(path_key):
		return _white_cache[path_key]
	var t: Texture2D = null
	if src != null:
		var img := src.get_image()
		if img != null:
			img = img.duplicate()
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			for y in img.get_height():
				for x in img.get_width():
					var c := img.get_pixel(x, y)
					img.set_pixel(x, y, Color(1, 1, 1, 1.0 if c.a > 0.4 else 0.0))
			t = ImageTexture.create_from_image(img)
	_white_cache[path_key] = t
	return t


## 敵スプライトの1コマ。味方と同じ生成スプライト系
## （assets/generated/sprites/<id>/walk_front.png ＝ 64x96 の4コマ横ストリップ）だけを見る。
## dungeon/frames の 16x16 ドットはフォールバックも含めて完全に廃止。
## 左（味方）を向くよう反転済みのテクスチャを作って返す
## （draw_texture_rect_region は負の幅で反転せず位置がずれるため、画像側で反転する）。
## pix_h ＝「見えている絵の高さ」をここで確定させる（＝事前リサンプル）。
## こうしておけば描画側は常に PIX_MULT の整数倍で貼れる。
func _mob_frame(sprite_name: String, f: int, pix_h: int) -> Texture2D:
	var key := "%s:%d:%d" % [sprite_name, f, pix_h]
	if _mob_frames.has(key):
		return _mob_frames[key]
	var t: Texture2D = null
	var sheet := _tex(MOB_DIR + "%s/walk_front.png" % sprite_name)
	if sheet == null:
		sheet = _tex(MOB_DIR + "mob_drone/walk_front.png")
	if sheet != null:
		var img := sheet.get_image()
		if img != null:
			img = img.duplicate()
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			var fw := int(img.get_width() / MOB_FRAMES)
			var fh := img.get_height()
			var frame := Image.create(fw, fh, false, Image.FORMAT_RGBA8)
			frame.blit_rect(img, Rect2i(fw * clampi(f, 0, MOB_FRAMES - 1), 0, fw, fh), Vector2i.ZERO)
			frame.flip_x()
			# 不透明部の高さを pix_h に合わせて一度だけリサンプルし、以降は整数倍で貼る
			var p0 := _scan_pads(frame, 0, fw)
			var vis := maxf(1.0 - p0.x - p0.y, 0.05) * float(fh)
			var k := float(pix_h) / maxf(vis, 1.0)
			var nw := maxi(int(round(fw * k)), 4)
			var nh := maxi(int(round(fh * k)), 4)
			frame.resize(nw, nh, Image.INTERPOLATE_BILINEAR)
			for y in nh:
				for x in nw:
					var c := frame.get_pixel(x, y)
					c.a = 1.0 if c.a > 0.42 else 0.0   # ソフトエッジを持たせない
					frame.set_pixel(x, y, c)
			_pad_cache[key] = _scan_pads(frame, 0, nw)
			t = ImageTexture.create_from_image(frame)
	_mob_frames[key] = t
	return t


func _mob_key(sprite_name: String, fps := 6.0) -> String:
	return "%s:%d" % [sprite_name, int(_ct * fps) % MOB_FRAMES]


## 足元(feet)基準で「テクスチャの整数倍」に描く。倍率は必ず整数（mult）で、
## 表示サイズはスプライト側のピクセル高さで決める＝テクセルが割れない。
## outline が不透明なら全周の輪郭（被弾フレームの赤だけに使う）。
## rim が真なら上半分に月色のリムライト・下半分に影を置く（敵の立体感）。
## 戻り値は「絵が実際にある」矩形＝頭上UIの吸着先。
## lean は「上体だけを横へずらす量」（px・テクセル単位＝PIX_MULT の倍数で渡す）。
## 歩きの上体と得物の揺れをスプライトを増やさずに作るための最小装置。
func _draw_actor(tex: Texture2D, feet: Vector2, mult: int, pads: Vector2,
		tint := Color(1, 1, 1), outline := Color(0, 0, 0, 0), sil: Texture2D = null,
		rim := false, lean := 0.0) -> Rect2:
	if tex == null:
		return Rect2(feet, Vector2.ZERO)
	var ts := tex.get_size()
	var m := maxi(mult, 1)
	var full_h := ts.y * m
	var w := ts.x * m
	var top := feet.y - full_h + full_h * pads.y
	var r := Rect2(roundf(feet.x - w * 0.5), roundf(top), w, full_h)
	var ot: Texture2D = sil if sil != null else tex
	if rim and ot != null:
		_rim_outline(ot, r, float(m))
	if outline.a > 0.0:
		var o := float(m)
		for ov: Vector2 in [Vector2(o, 0), Vector2(-o, 0), Vector2(0, o), Vector2(0, -o)]:
			_blit(ot, Rect2(r.position + ov, r.size), outline, lean)
	_blit(tex, r, tint, lean)
	return Rect2(r.position.x, r.position.y + full_h * pads.x, r.size.x,
			full_h * maxf(1.0 - pads.x - pads.y, 0.05))


## スプライトを1枚で貼る。lean があるときだけ肩の高さで割って上半身をずらす。
func _blit(t: Texture2D, r: Rect2, col: Color, lean := 0.0) -> void:
	if absf(lean) < 0.5:
		draw_texture_rect(t, r, false, col)
		return
	var ts := t.get_size()
	var cut := floorf(ts.y * 0.42)          # 肩のあたり
	var sh := roundf(r.size.y * (cut / maxf(ts.y, 1.0)))
	draw_texture_rect_region(t, Rect2(r.position + Vector2(roundf(lean), 0),
			Vector2(r.size.x, sh)), Rect2(0, 0, ts.x, cut), col)
	draw_texture_rect_region(t, Rect2(r.position + Vector2(0, sh),
			Vector2(r.size.x, r.size.y - sh)), Rect2(0, cut, ts.x, ts.y - cut), col)


## 輪郭を上下で割る：上半分は月色のリム（光は右上の月から来る）、下半分は影。
## 全周1pxの均一キーラインは「シール」に見えるので使わない。
func _rim_outline(sil: Texture2D, r: Rect2, o: float) -> void:
	var ts := sil.get_size()
	var hy := floorf(ts.y * 0.5)
	var top_src := Rect2(0, 0, ts.x, hy)
	var bot_src := Rect2(0, hy, ts.x, ts.y - hy)
	var top_dst := Rect2(r.position, Vector2(r.size.x, hy * o))
	var bot_dst := Rect2(r.position + Vector2(0, hy * o), Vector2(r.size.x, r.size.y - hy * o))
	for ov: Vector2 in [Vector2(o, -o), Vector2(0, -o), Vector2(o, 0)]:
		draw_texture_rect_region(sil, Rect2(top_dst.position + ov, top_dst.size), top_src, RIM_LIGHT)
	for ov: Vector2 in [Vector2(0, o), Vector2(-o, o), Vector2(-o, 0), Vector2(o, o)]:
		draw_texture_rect_region(sil, Rect2(bot_dst.position + ov, bot_dst.size), bot_src, RIM_SHADOW)


## 描画幅（フレーム全体）を先に知りたいとき用。
func _actor_w(tex: Texture2D, mult: int) -> float:
	return 0.0 if tex == null else tex.get_size().x * float(maxi(mult, 1))


func _draw() -> void:
	var sz := size
	var gy := snappedf(sz.y * GROUND_Y, 2.0)
	var font := get_theme_default_font()
	# カメラ（以降の全描画に効く）。毎フレームの乱数ぶれではなく、方向を持った減衰振動。
	var cam := _shake_amp()
	if absf(cam) > 0.05:
		draw_set_transform(_shake_dir * cam, 0.0, Vector2.ONE)

	_draw_sky(sz, gy)
	_draw_canopy(sz)          # 上端から垂れる構造体＝「下へ潜っている」構図を作る
	_draw_ground(sz, gy)
	# アクター帯を1枚落とす：背景が主役より明るい問題は「主役を上げる」のではなく
	# 「主役の居る帯を落とす」で解く（背景の彩度と輝度を主役より下に置く）。
	draw_polygon(
			PackedVector2Array([Vector2(0, gy - 160.0), Vector2(sz.x, gy - 160.0),
					Vector2(sz.x, gy + 40.0), Vector2(0, gy + 40.0)]),
			PackedColorArray([Color(0.06, 0.03, 0.14, 0.10), Color(0.06, 0.03, 0.14, 0.10),
					Color(0.06, 0.03, 0.14, 0.42), Color(0.06, 0.03, 0.14, 0.42)]))
	_draw_milestones(sz, gy, font)
	_draw_portal(Vector2(58, gy), font)
	_draw_goal(sz, gy)

	# ===== 敵（奥から近づく・左向き・被弾で白フラッシュ＋のけぞり）=====
	# 味方より先に描く＝敵が奥、味方が手前。敵は味方の約1.4倍で構図を支配する。
	_enemy_pos.resize(mobs.size())
	_enemy_top.resize(mobs.size())
	_enemy_draw.resize(mobs.size())
	_knock.resize(maxi(mobs.size(), _knock.size()))
	if in_combat:
		for i in mobs.size():
			var m: Dictionary = mobs[i]
			var boss: bool = bool(m.get("boss", false))
			var ex := float(_enemy_x[i]) if (i < _enemy_x.size() and _enemy_x[i] != null) \
					else sz.x * (ENEMY_X0 - 0.04)
			# 接近の予備動作：奥（小さい・高い・暗い）から手前へ。到達してから初めて構える。
			var app := _approach(i)
			var far := 1.0 - app
			var lunge := 0.0 if far > 0.02 else maxf(0.0, sin(_ct * 4.2 + i * 1.7)) * 9.0
			var feet := Vector2(ex - lunge + _knock_offset(i),
					gy + (0.0 if boss else (i % 2) * 8.0) - far * 26.0)
			_enemy_pos[i] = feet
			# 遠いほど小さく貼る。倍率は PIX_MULT 固定のまま「ピクセル高さ」を段で落とす
			# ＝非整数縮小を持ち込まずに遠近を出す（_draw_incoming と同じ作法）。
			var ph_full := BOSS_PIX_H if boss else MOB_PIX_H
			var ph := ph_full
			if far > 0.02:
				var steps := [int(ph_full * 0.46), int(ph_full * 0.66),
						int(ph_full * 0.84), ph_full]
				ph = int(steps[clampi(int(app * 4.0), 0, 3)])
			var sprite_name := String(m.get("sprite", "mob_drone"))
			var fi := int(_mob_key(sprite_name, 9.0 if far > 0.02 else 5.0).get_slice(":", 1))
			var key := "%s:%d:%d" % [sprite_name, fi, ph]
			var tex := _mob_frame(sprite_name, fi, ph)
			var pads: Vector2 = _pad_cache.get(key, Vector2.ZERO)
			var sil := _white_tex(key, tex)
			var dw := _actor_w(tex, PIX_MULT)
			var dh := (BOSS_H if boss else MOB_H) * (0.4 + 0.6 * app)
			# 敵を明るくするのではなく、敵の後ろを暗くする（局所減光）
			_backdrop_dim(Vector2(feet.x, feet.y - dh * 0.5), dw * 0.8, dh * 0.8)
			# 被弾フレーム（0.1秒）だけ赤の全周キーライン。それ以外は上リム／下影。
			# 白飛びはさらに短く（0.07秒）して ease で抜く＝ヒットストップで
			# 保持されても「白い幽霊」が残らない。
			var hit := false
			var flash := 0.0
			for sl in _slashes:
				if int(sl["slot"]) != i:
					continue
				var ha := _t - float(sl.get("rt", sl["t0"]))
				if ha < 0.12:
					hit = true
					flash = maxf(flash, 1.0 - _e_in_out(clampf(ha / 0.07, 0.0, 1.0)))
					break
			# 奥にいる間は闇に沈めておき、着いた瞬間に色が戻る（＝到着が事件になる）
			var tint := Color(1, 1, 1).lerp(Color(0.30, 0.17, 0.34), far * 0.85)
			var r := _draw_actor(tex, feet, PIX_MULT, pads, tint,
					HIT_LINE if hit else Color(0, 0, 0, 0), sil, true)
			_contact_shadow(feet, dw * 0.62)
			_enemy_draw[i] = {"tex": tex, "sil": sil, "pads": pads, "feet": feet,
					"mult": PIX_MULT, "boss": boss}
			if flash > 0.01 and sil != null:
				_draw_actor(sil, feet, PIX_MULT, pads, Color(1, 1, 1, 0.62 * flash))
			_enemy_top[i] = r.position.y
			# 着地の土煙（定位置に「着いた」ことを床で示す。0.34秒だけ）
			var lt := float(_enemy_land[i]) if (i < _enemy_land.size() and _enemy_land[i] != null) else -9.9
			var lu := (_ct - lt) / 0.34
			if lu >= 0.0 and lu < 1.0:
				var le := _e_out(lu, 2.2)
				_ellipse(feet, Vector2(dw * (0.34 + le * 0.62), 9.0 * (0.5 + le * 0.9)),
						Color(0.72, 0.62, 0.86, 0.26 * (1.0 - le)))
			if far > 0.35:
				continue          # 奥に居る間は弱点もHPバーも出さない（構えるのは寄ってから）
			# 弱点コア：画面最明部を「プレイヤーが見るべき場所」に置く
			_weak_point(Vector2(feet.x, (r.position.y + feet.y) * 0.5), boss)
			var hp0: float = float(_mob_hp0[i]) if i < _mob_hp0.size() else float(m["hp"])
			_draw_enemy_hp(font, Vector2(feet.x, r.position.y - 10.0), 62.0 if boss else 46.0,
					float(m["hp"]) / maxf(hp0, 1.0), int(m["hp"]), boss)
	else:
		_draw_incoming(sz, gy)

	# ===== 隊列（左→右へ行進。戦闘中は停止・殴り手が踏み込む）=====
	_party_pos.resize(party.size())
	_party_hurt.resize(party.size())
	var strike_k := clampf(1.0 - (_ct - _strike_t) / 0.30, 0.0, 1.0)   # 踏み込みの残量
	var hurt_k := clampf(1.0 - (_ct - _hurt_t) / 0.22, 0.0, 1.0)       # 被弾フラッシュの残量
	# 待機の生気：5.6秒に一人ずつ、順番に小さく跳ねる（全員が等速に流れる時間を作らない）
	var beat_i := int(_ct / 5.6)
	var beat_u := fposmod(_ct / 5.6, 1.0) / 0.075
	for i in party.size():
		var p: Dictionary = party[i]
		var id := String(p["id"])
		# 一人ずつ歩調・歩幅・呼吸をずらす。位相は黄金角、テンポは ±9%。
		# 同じ周期で4人が上下すると「行進」に見え、生き物に見えなくなる。
		var gph := float(i) * 2.399963
		var grate := 1.0 + (fposmod(float(i) * 0.618034, 1.0) - 0.5) * 0.18
		var step := _ct * 6.6 * grate + gph
		var bob := 0.0
		var stride := 0.0
		var lean := 0.0
		if in_combat:
			bob = absf(sin(_ct * 3.4 * grate + gph)) * 1.6      # 構え中の呼吸
			lean = 2.0 * signf(sin(_ct * 1.9 * grate + gph))     # 得物の重心移動
		else:
			bob = absf(sin(step)) * (2.6 + 1.1 * fposmod(float(i) * 0.37, 1.0))
			stride = sin(step + PI * 0.5) * 2.4                  # 歩幅（前後の詰め）
			lean = 2.0 * signf(sin(step * 0.5))                  # 上体と得物の揺れ（1テクセル）
			if i == beat_i % maxi(party.size(), 1) and beat_u < 1.0:
				bob += sin(_e_in_out(beat_u) * PI) * 5.0         # 順番に来る小さな跳ね
		# 隊列の呼吸：間隔そのものがゆっくり伸び縮みする（等間隔で固まらせない）
		var breath := sin(_ct * 0.46 + float(i) * 1.73) * 3.6
		var lunge := (maxf(0.0, sin(_ct * 3.8 + i * 0.53)) * 6.0) if in_combat else 0.0
		if i == _striker and strike_k > 0.0:
			lunge += sin(strike_k * PI) * 34.0   # 殴り手の鋭い踏み込み（行って戻る）
		var knock_back := (sin(hurt_k * PI) * 10.0) if (i == _tank_index() and hurt_k > 0.0) else 0.0
		# 後列ほど奥（上）／前列ほど手前（下）＝隊列に奥行きを作る。
		# 身長は変えない（非整数倍になるため）。奥行きは y のオフセットだけで出す。
		var depth := float(i) / maxf(party.size() - 1.0, 1.0)
		var feet := Vector2(PARTY_X0 + _form_x + i * PARTY_GAP + lunge - knock_back
					+ stride + breath,
				gy - bob + 10.0 * depth)
		_party_pos[i] = feet
		var dead: bool = float(p["hp"]) <= 0.0
		var path := "res://assets/generated/sprites/%s/idle_f0.png" % id
		if _anims.has(id):
			path = (_anims[id] as ChibiAnim).current_path()
		var tex := _pix_tex(path)
		if tex == null:
			path = "res://assets/generated/sprites/%s/idle_f0.png" % id
			tex = _pix_tex(path)
		var pads: Vector2 = _pad_cache.get(path, Vector2.ZERO)
		var tint := Color(1, 1, 1)
		if dead:
			tint = Color(0.5, 0.5, 0.58)
		elif i == _tank_index() and hurt_k > 0.0:
			tint = Color(1.0, 1.0 - hurt_k * 0.62, 1.0 - hurt_k * 0.62)   # 被弾の赤フラッシュ
		var dw := _actor_w(tex, PIX_MULT)
		var r := _draw_actor(tex, feet, PIX_MULT, pads, tint, ALLY_LINE, _white_tex(path, tex),
				false, 0.0 if dead else lean)
		_contact_shadow(feet, dw * 0.52)
		# 頭上HPは被弾後0.8秒だけ（常設は下部カードに集約）
		var ht := float(_party_hurt[i]) if _party_hurt[i] != null else -9.9
		var age := _ct - ht
		if not dead and age < 0.8:
			_draw_head_ui(Vector2(feet.x, r.position.y - 8.0), 40.0,
					float(p["hp"]) / maxf(float(p["mhp"]), 1.0), HP_COL,
					clampf(1.0 - age / 0.8, 0.0, 1.0))
		if not dead and in_combat:
			_draw_pips(Vector2(feet.x, r.position.y - 14.0),
					int(p.get("ready", 0)), int(p.get("slots", 0)))
		# 次に動ける味方の頭上に ready 光。画面最明部はここ＝プレイヤーが見るべき場所。
		if not dead and int(p.get("ready", 0)) > 0:
			_ready_light(Vector2(feet.x, r.position.y - 26.0))

	_draw_pops()
	_draw_lv_pillars(sz, gy)
	_draw_combat_fx(sz, gy, font)
	_draw_foreground(sz, gy)
	_draw_bubble(sz, gy, font)
	_draw_vignette(sz)

	if absf(cam) > 0.05:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 会話劇の吹き出し：話者の頭上に白いVNバブル（名前チップ＋しっぽ付き）。
func _draw_bubble(sz: Vector2, gy: float, font: Font) -> void:
	if _bubble.is_empty() or _t < float(_bubble["t0"]):
		return
	var gid := String(_bubble["gid"])
	# 話者の位置（隊列に居なければ中央左）
	var anchor := Vector2(PARTY_X0 + PARTY_GAP * 2.0, gy)
	for i in party.size():
		if String(party[i]["id"]) == gid and i < _party_pos.size() and _party_pos[i] != null:
			anchor = _party_pos[i]
			break
	var g: Dictionary = KuroData.GIRLS.get(gid, {})
	var gcol: Color = g.get("color", Color(1, 1, 1))
	var gname := String(g.get("name", gid))
	var text := String(_bubble["text"])
	# フェード（出0.18s／消0.25s）
	var age := _t - float(_bubble["t0"])
	var a := clampf(age / 0.18, 0.0, 1.0) * clampf((float(_bubble["dur"]) - age) / 0.25, 0.0, 1.0)
	# 寸法（折返しあり・最大幅260）
	var maxw := 260.0
	var tsz := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, maxw, FS_M)
	var bw := minf(tsz.x, maxw) + 24.0
	var bh := tsz.y + 18.0
	var bx := clampf(anchor.x - bw * 0.35, 8.0, sz.x - bw - 8.0)
	var by := anchor.y - GIRL_H - 40.0 - bh   # 頭上UI（バー/ピップ）のさらに上
	var r := Rect2(bx, by, bw, bh)
	# 影→白バブル→話者色の縁→しっぽ
	draw_rect(Rect2(r.position + Vector2(2, 3), r.size), Color(0, 0, 0, 0.30 * a))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.96, 0.97, 1.0, 0.94 * a)
	sb.set_corner_radius_all(9)
	sb.border_color = Color(gcol.r, gcol.g, gcol.b, 0.9 * a)
	sb.set_border_width_all(2)
	draw_style_box(sb, r)
	var tail_x := clampf(anchor.x, bx + 16.0, bx + bw - 16.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(tail_x - 7, by + bh - 1), Vector2(tail_x + 7, by + bh - 1),
		Vector2(anchor.x, by + bh + 12.0)]), Color(0.96, 0.97, 1.0, 0.94 * a))
	# 名前チップ（バブル左上に重ねる）
	var nw := font.get_string_size(gname, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_S).x + 14.0
	var nr := Rect2(bx + 8.0, by - 10.0, nw, 18.0)
	var nsb := StyleBoxFlat.new()
	nsb.bg_color = Color(gcol.r * 0.25, gcol.g * 0.22, gcol.b * 0.28, 0.96 * a)
	nsb.set_corner_radius_all(6)
	nsb.border_color = Color(gcol.r, gcol.g, gcol.b, 0.9 * a)
	nsb.set_border_width_all(1)
	draw_style_box(nsb, nr)
	draw_string(font, Vector2(nr.position.x + 7, nr.position.y + 13), gname,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FS_S, Color(1, 1, 1, a))
	# 本文（ダーク文字＝ネオン夜景の上でも読める）
	draw_multiline_string(font, Vector2(bx + 12.0, by + 22.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, maxw, FS_M, -1, Color(0.09, 0.10, 0.16, a))


## 実体アンカーの戦闘FX：斬撃・スキルバースト・ダメージ数字（対象の頭上に追従）。
func _draw_combat_fx(sz: Vector2, gy: float, font: Font) -> void:
	# 斬撃（対象の胴で白シアンのX＋小リング）
	var i := 0
	while i < _slashes.size():
		var k := (_ct - float(_slashes[i]["t0"])) / 0.20
		if k >= 1.0:
			_slashes.remove_at(i)
			continue
		var slot := int(_slashes[i]["slot"])
		var base: Vector2 = _enemy_pos[slot] if (slot < _enemy_pos.size() and _enemy_pos[slot] != null) 				else Vector2(sz.x * ENEMY_X0, gy)
		var c := base + Vector2(0, -MOB_H * 0.55)
		if slot < _enemy_top.size() and _enemy_top[slot] != null:
			c = Vector2(base.x, (float(_enemy_top[slot]) + base.y) * 0.5)   # 頭と足元の中間＝胴
		# 斬撃は「伸びきってから消える」。伸びは ease-out、消えは後半だけ。
		var ke := _e_out(k, 2.4)
		var a := 1.0 - _e_in_out(clampf((k - 0.35) / 0.65, 0.0, 1.0))
		var ln := 22.0 + 22.0 * ke
		draw_line(c + Vector2(-ln, -ln * 0.6), c + Vector2(ln, ln * 0.6), Color(1, 1, 1, a), 3.0)
		draw_line(c + Vector2(-ln * 0.8, ln * 0.7), c + Vector2(ln * 0.8, -ln * 0.7), Color(CYAN.r, CYAN.g, CYAN.b, a * 0.9), 2.0)
		draw_arc(c, 12.0 + 32.0 * ke, 0, TAU, 20, Color(1, 1, 1, a * 0.5), 2.0)
		i += 1
	# スキルバースト（爆発=橙リング＋破片／雷=ジグザグ落雷／回復・歌=味方から立ち上る粒）
	i = 0
	while i < _bursts.size():
		var kk := (_ct - float(_bursts[i]["t0"])) / 0.45
		if kk >= 1.0:
			_bursts.remove_at(i)
			continue
		var kind := String(_bursts[i]["kind"])
		# 広がりは ease-out、消えは後半に寄せる（等速に膨らんで等速に消えない）
		var k := _e_out(kk, 2.2)
		var a := 1.0 - _e_in_out(clampf((kk - 0.25) / 0.75, 0.0, 1.0))
		# 実体アンカー：敵/味方の実座標に付ける（ハードコード座標は使わない）
		var ec := Vector2(sz.x * ENEMY_X0 + ENEMY_GAP, gy - MOB_H * 0.55)
		if not _enemy_pos.is_empty() and _enemy_pos[0] != null:
			var mid := _enemy_pos.size() / 2
			ec = (_enemy_pos[mid] as Vector2) + Vector2(0, -MOB_H * 0.55)
		var pc := Vector2(PARTY_X0 + PARTY_GAP * 2.0, gy - GIRL_H * 0.5)
		if not _party_pos.is_empty() and _party_pos[0] != null:
			var sx := 0.0
			for pp in _party_pos:
				sx += (pp as Vector2).x
			pc = Vector2(sx / _party_pos.size(), gy - GIRL_H * 0.5)
		match kind:
			"explosion":
				draw_arc(ec, 18.0 + 52.0 * k, 0, TAU, 24, Color(1.0, 0.62, 0.3, a), 4.0)
				for j in 6:
					var ang := TAU * j / 6.0 + k * 1.2
					var d := 16.0 + 46.0 * k
					draw_circle(ec + Vector2(cos(ang), sin(ang) * 0.7) * d, 3.0 * a + 1.0, Color(1.0, 0.75, 0.35, a))
			"lightning":
				var top := Vector2(ec.x + 8.0, ec.y - 210.0)
				var pts := PackedVector2Array()
				for j in 6:
					var tt := j / 5.0
					pts.append(top.lerp(ec, tt) + Vector2(sin(j * 91.7 + _ct * 40.0) * 10.0 * (1.0 - tt), 0))
				for j in 5:
					draw_line(pts[j], pts[j + 1], Color(0.85, 0.95, 1.0, a), 3.0)
				Kit.spot(self, ec, 60.0, Color(0.7, 0.9, 1.0), a * 0.5)
			"heal", "song", "smoke":
				var col := Color(0.5, 1.0, 0.6) if kind == "heal" else (Color(1.0, 0.7, 0.9) if kind == "song" else Color(0.7, 0.7, 0.75))
				for j in 7:
					var jx := fposmod(sin(j * 57.3) * 999.0, 1.0) * PARTY_GAP * 4.0 - PARTY_GAP * 2.0
					var jy := -k * 46.0 - fposmod(j * 13.7, 12.0)
					draw_circle(pc + Vector2(jx, jy), 2.6, Color(col.r, col.g, col.b, a * 0.9))
				Kit.spot(self, pc, 70.0, col, a * 0.3)
		i += 1
	# ダメージ数字。等速で上へ流さない：出た瞬間に大きく跳ね、いったん落ちて戻り、
	# 縮みながら上へ抜けて最後だけ消える（＝「当たった」の時間差の4本目）。
	i = 0
	while i < _floaters.size():
		var fl: Dictionary = _floaters[i]
		var k := (_ct - float(fl["t0"])) / 0.9
		if k >= 1.0:
			_floaters.remove_at(i)
			continue
		if k < 0.0:
			i += 1
			continue
		var slot := int(fl.get("slot", 0))
		var side := String(fl["side"])
		var base := Vector2(sz.x * 0.5, gy)
		if side == "fixed":
			# 撃破の金・素材は「倒れた場所」に置き去りにする（対象はもう居ない）
			base = fl.get("pos", base)
		elif side == "enemy":
			if slot < _enemy_top.size() and _enemy_top[slot] != null and slot < _enemy_pos.size() and _enemy_pos[slot] != null:
				base = Vector2((_enemy_pos[slot] as Vector2).x, float(_enemy_top[slot]) - 26.0)
			else:
				base += Vector2(0, -MOB_H - 26.0)
		else:
			if slot < _party_pos.size() and _party_pos[slot] != null:
				base = _party_pos[slot]
			base += Vector2(0, -GIRL_H - 30.0)
		var crit := bool(fl.get("crit", false))
		var fixed := side == "fixed"
		# 跳ね → 落ち戻り → ゆっくり上へ。3本の別々のイージングの重ね合わせ。
		var hop := _e_out(k / (0.13 if crit else 0.16), 2.6)                  # 一気に上がる
		var settle := sin(_e_in_out(clampf((k - 0.15) / 0.26, 0.0, 1.0)) * PI) # 一度落ちて戻る
		var drift := _e_out(clampf((k - 0.30) / 0.70, 0.0, 1.0), 1.7)         # 後半のゆるい上昇
		var rise := (44.0 if crit else 30.0) * hop - (14.0 if crit else 9.0) * settle \
				- (30.0 if crit else 24.0) * drift
		if fixed:
			rise = 56.0 * _e_out(k, 2.2) - 8.0 * settle   # 報酬は跳ねずに静かに立ち上がる
		# 横も少しだけ散る（同時に3つ出ても数字が重ならない）
		var spread := 0.35 + 0.65 * _e_out(k, 2.0)
		var pos := base + Vector2(float(fl["jx"]) * (1.0 if fixed else spread),
				float(fl.get("jy", 0.0)) - rise)
		var col: Color = fl["col"]
		# 最後まではっきり読ませて、終わりぎわだけ抜く（等速フェードにしない）
		var a := _e_in_out(clampf((1.0 - k) / 0.28, 0.0, 1.0))
		# 出た瞬間だけ大きく→縮む。段は 12/16/22/32/48 の5段しかないので、
		# 連続量を _fs で段へ丸める＝ポップが「コマ落ち」として読める。
		var base_fs := 26.0 if crit else 18.0
		var scale := 1.0 + 0.62 * (1.0 - _e_out(k / 0.20, 2.0)) \
				- 0.22 * _e_out(clampf((k - 0.45) / 0.55, 0.0, 1.0), 1.5)
		var fsize := _fs(base_fs * scale) if not fixed else FS_M
		var txt := String(fl["txt"])
		if crit:
			# 会心は色相を増やさず「白い衝撃線」で差を作る（虹色にしない）
			draw_line(pos + Vector2(-26, -8), pos + Vector2(26, -8), Color(1, 1, 1, a * 0.55), 2.0)
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		if bool(fl.get("plate", false)):
			# 報酬（+G／素材）はネオンの上でも必ず読めるよう黒い下地を敷く
			draw_rect(Rect2(roundf(pos.x - tw * 0.5 - 6.0), roundf(pos.y - fsize + 1.0),
					roundf(tw + 12.0), fsize + 6.0), Color(0.02, 0.02, 0.05, 0.72 * a))
		draw_string(font, pos + Vector2(-tw * 0.5 + 1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0, 0, 0, a * 0.75))
		draw_string(font, pos + Vector2(-tw * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(col.r, col.g, col.b, a))
		i += 1


## 撃破の破裂。敵が消える瞬間に「弾けた」証拠を残す（居なくなっただけにしない）。
## 上限は POP_MAX。2.5秒に1体なので、これ以上残すと床が破片で埋まる。
func _draw_pops() -> void:
	var i := 0
	while i < _pops.size():
		var p: Dictionary = _pops[i]
		var kk := (_ct - float(p["t0"])) / 0.55
		if kk >= 1.0:
			_pops.remove_at(i)
			continue
		var c: Vector2 = p["p"]
		var big := bool(p["boss"])
		var mid := bool(p["elite"])
		var scale := 1.9 if big else (1.35 if mid else 1.0)
		var h := (BOSS_H if big else MOB_H) * 0.5
		var org := c + Vector2(0, -h)
		if kk < 0.0:
			# ── 予備動作。破片より前に「敵が壊れる」ところを見せる ──
			_draw_death(p, _ct - float(p.get("t_die", 0.0)), _t - float(p.get("rt_die", 0.0)))
			i += 1
			continue
		# 破裂は頭が速く尻が長い。等速に広がるリングは花火に見えず「図形」に見える。
		var k := _e_out(kk, 2.3)
		var a := 1.0 - _e_in_out(clampf((kk - 0.25) / 0.75, 0.0, 1.0))
		# 弾けたリング（角丸を使わない作法どおり8角形の輪郭）＋外へ飛ぶ破片
		var rr := (16.0 + 78.0 * k) * scale
		_octagon_ring(org, rr, Color(1.0, 0.95, 0.88, a * 0.9), 3.0)
		_octagon_ring(org, rr * 0.62, Color(1.0, 0.72, 0.42, a * 0.7), 2.0)
		for j in 10:
			var ang := TAU * j / 10.0 + float(int(c.x)) * 0.7
			var d := (12.0 + 86.0 * k) * scale
			# 破片だけは落ちる（重力＝二次曲線）。飛び散って落ちるまでが一続き。
			var q := org + Vector2(cos(ang) * d, sin(ang) * d * 0.72 + kk * kk * 46.0)
			_octagon(q, (5.0 - 3.4 * k) * scale, Color(1.0, 0.94, 0.88, a))
		# 足元に潰れた影（破片が床へ落ちたことを示す）
		_ellipse(Vector2(c.x, c.y), Vector2(56.0 * scale * (0.4 + k), 11.0 * (1.0 - k * 0.6)),
				Color(1.0, 0.86, 0.7, 0.20 * a))
		i += 1


## 撃破の予備動作（DEATH_LEAD 秒）。オクトパストラベラーIIの撃破は
## 「一瞬白く飛ぶ → 潰れる → 破片」の順で、消える前に必ず壊れる工程が挟まる。
## sim は撃破の瞬間に mobs から消すので、直前フレームの絵をここで演じ直す。
## age＝戦闘時計での経過（ヒットストップ中は進まない＝姿勢が保持される）、
## rt＝実時間での経過。白飛びだけは rt で抜く：止めて見せたいのは「壊れかけの姿」で、
## 白い塊をヒットストップの長さぶん居座らせると幽霊にしか見えない。
func _draw_death(p: Dictionary, age: float, rt: float) -> void:
	var d: Dictionary = p.get("death", {})
	if d.is_empty() or d.get("tex") == null:
		return
	var tex: Texture2D = d["tex"]
	var sil: Texture2D = d.get("sil")
	var pads: Vector2 = d.get("pads", Vector2.ZERO)
	var feet: Vector2 = d.get("feet", p["p"])
	var m: int = int(d.get("mult", PIX_MULT))
	var ts := tex.get_size()
	var full_h := ts.y * m
	var w := ts.x * m
	# ② 潰れる。縦に沈んで横へ逃げる（消えるのではなく壊れる）。
	# 前半 0.06 秒は潰さずに保持＝「止まった瞬間」を見せてから壊す。
	var u := _e_out(clampf((age - 0.06) / (DEATH_LEAD - 0.06), 0.0, 1.0), 2.0)
	var hh := full_h * (1.0 - u * 0.86)
	var ww := w * (1.0 + u * 0.52)
	var r := Rect2(roundf(feet.x - ww * 0.5), roundf(feet.y - hh + full_h * pads.y * (1.0 - u)),
			ww, hh)
	var col := Color(1, 1, 1).lerp(Color(1.0, 0.84, 0.58), u)
	draw_texture_rect(tex, r, false, Color(col.r, col.g, col.b, 1.0 - u * 0.25))
	# ① 白飛び（実時間 0.07 秒）。輪郭ごと真っ白に飛ばして「決まった」ことを刻む。
	var fa := 1.0 - _e_in_out(clampf(rt / 0.07, 0.0, 1.0))
	if fa > 0.01 and sil != null:
		for ov: Vector2 in [Vector2(m, 0), Vector2(-m, 0), Vector2(0, m), Vector2(0, -m)]:
			draw_texture_rect(sil, Rect2(r.position + ov, r.size), false, Color(1, 1, 1, fa))
		draw_texture_rect(sil, r, false, Color(1, 1, 1, fa))


## 8角形の輪郭（塗りつぶさないリング）。draw_arc の丸みを持ち込まないための版。
func _octagon_ring(c: Vector2, r: float, col: Color, w: float) -> void:
	if r <= 0.5:
		return
	var pts := PackedVector2Array()
	for i in 9:
		var a := TAU * (i % 8 + 0.5) / 8.0
		pts.append(c + Vector2(cos(a) * r, sin(a) * r * 0.82))
	draw_polyline(pts, col, w)


## 同期率レベルアップ：パーティ全員の足元から光柱が立つ。
## 共鳴の回（Lv3/6/9/12）は太く長く、2倍の時間残る＝25分で4回だけの山。
func _draw_lv_pillars(sz: Vector2, gy: float) -> void:
	var dur := 2.0 if _lv_res else 1.3
	var age := _ct - _lv_t
	if age < 0.0 or age > dur:
		return
	var k := age / dur
	# 立ち上がりも消えも ease-in-out。等速に伸びて等速に消える光は「板」に見える。
	var a := _e_in_out(clampf(age / 0.16, 0.0, 1.0)) * _e_in_out(clampf((dur - age) / 0.55, 0.0, 1.0))
	# 高さは少しだけ行き過ぎてから収まる（伸びきる瞬間に力がある）
	var hgt := (520.0 if _lv_res else 340.0) * (0.16 + 0.84 * _e_back(clampf(age / 0.38, 0.0, 1.0), 0.9))
	var wid := 30.0 if _lv_res else 20.0
	var col := CYAN
	for i in _party_pos.size():
		if _party_pos[i] == null:
			continue
		var f: Vector2 = _party_pos[i]
		# 足元＝濃い／上端＝0 の縦グラデ四角（ハードエッジの出ない安価な光の柱）
		draw_polygon(
				PackedVector2Array([Vector2(f.x - wid * 0.5, f.y - hgt),
						Vector2(f.x + wid * 0.5, f.y - hgt),
						Vector2(f.x + wid, f.y + 6.0), Vector2(f.x - wid, f.y + 6.0)]),
				PackedColorArray([Color(col.r, col.g, col.b, 0.0), Color(col.r, col.g, col.b, 0.0),
						Color(col.r, col.g, col.b, 0.55 * a), Color(col.r, col.g, col.b, 0.55 * a)]))
		draw_rect(Rect2(f.x - 2.0, f.y - hgt * 0.9, 4.0, hgt * 0.9),
				Color(0.92, 1.0, 1.0, 0.55 * a))
		# 足元の輪（床に着いていることを示す）
		_ellipse(f, Vector2(wid * (1.4 + k * 2.2), 10.0 * (1.4 + k * 2.2) * 0.34),
				Color(col.r, col.g, col.b, 0.40 * a))
		# 立ち上る粒
		for j in 5:
			var jy := -fposmod(age * 240.0 + j * 47.0, hgt)
			_octagon(Vector2(f.x + sin(j * 21.7 + age * 4.0) * wid * 0.8, f.y + jy), 2.4,
					Color(0.85, 1.0, 1.0, a * 0.8))
	# 地面全体を走る横一線（全員に同時に起きたことを示す）。走りは ease-out。
	var lw := _e_out(clampf(age / 0.30, 0.0, 1.0), 2.6) * sz.x
	draw_rect(Rect2((sz.x - lw) * 0.5, gy - 2.0, lw, 3.0), Color(col.r, col.g, col.b, 0.7 * a))


## 道中のマイルストーン標識。非戦闘の移動中に「静かな時間」を作らないための最小装置。
## 42（＝階長の10%）ごとに標柱が右から左へ流れ、隊列の足元に深度と残距離を出す。
## 数値はすべて sim の dist から引く。
func _draw_milestones(sz: Vector2, gy: float, font: Font) -> void:
	var ref_x := PARTY_X0 + PARTY_ROAM_X + PARTY_GAP * 2.0
	var span := 42.0                       # 階長 420 の 10%
	var dim := 0.45 if in_combat else 1.0   # 交戦中は主役の邪魔をしない
	var base_i := int(floor(dist / span)) - 1
	for j in 13:
		var pd := float(base_i + j) * span
		if pd < 0.0:
			continue
		var x := snappedf(ref_x + (pd - dist) * 14.0, 2.0)
		if x < -60.0 or x > sz.x + 60.0:
			continue
		var gate := absf(fposmod(pd, KuroData.FLOOR_LEN)) < 1.0
		# 通り過ぎた標識は暗く、まだ先の標識は明るい＝どちらへ進んでいるかが一目で分かる
		var ahead := pd >= dist
		var a := (0.95 if gate else 0.66) * dim * (1.0 if ahead else 0.42)
		var h := 76.0 if gate else 46.0
		var col := PURPLE if gate else CYAN
		# 標柱（黒地＋縞。ネオン背景でも輪郭が消えない）
		draw_rect(Rect2(x - 3.0, gy - h, 6.0, h), Color(0.03, 0.02, 0.07, 0.94 * dim))
		for seg in int(h / 12.0):
			if seg % 2 == 0:
				draw_rect(Rect2(x - 3.0, gy - h + seg * 12.0, 6.0, 6.0),
						Color(col.r, col.g, col.b, a * 0.40))
		draw_rect(Rect2(x - 4.0, gy - h - 2.0, 8.0, 4.0), Color(col.r, col.g, col.b, a))
		_contact_shadow(Vector2(x, gy), 16.0)
		var lbl := KuroData.stage_label(int(pd / KuroData.FLOOR_LEN)) if gate \
				else "%d%%" % int(round(fposmod(pd, KuroData.FLOOR_LEN) / KuroData.FLOOR_LEN * 100.0))
		var tw := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_S).x
		# 標識板は柱の右側に立てる（柱の頭に乗せると隊列の頭上UIとぶつかる）
		var pr := Rect2(snappedf(x + 3.0, 2.0), snappedf(gy - h - 2.0, 2.0), tw + 12.0, 18.0)
		draw_rect(pr, Color(0.02, 0.02, 0.05, 0.86 * dim))
		draw_rect(pr, Color(col.r, col.g, col.b, a * 0.8), false, 1.0)
		draw_string(font, Vector2(pr.position.x + 6.0, pr.position.y + 13.0), lbl,
				HORIZONTAL_ALIGNMENT_LEFT, -1, FS_S, Color(col.r, col.g, col.b, minf(a * 1.3, 1.0)))
	# 足元の距離ルーラー。4.2（=1%）ごとに刻みが流れる＝止まって見える瞬間を作らない。
	# 非戦闘の移動中でも「進んでいる」ことが常に目に入る一番安い装置。
	var ry := gy + 14.0
	draw_rect(Rect2(0, ry, sz.x, 1.0), Color(0.60, 0.66, 0.88, 0.30 * dim))
	var tick := 4.2
	var t0 := floorf(dist / tick) - 40.0
	for j in 90:
		var td: float = (t0 + float(j)) * tick
		var tx := snappedf(ref_x + (td - dist) * 14.0, 1.0)
		if tx < 0.0 or tx > sz.x:
			continue
		var tenth := absf(fposmod(td, tick * 10.0)) < 0.01
		var th := 10.0 if tenth else 5.0
		draw_rect(Rect2(tx, ry - th, 2.0, th), Color(0.02, 0.02, 0.05, 0.7 * dim))
		draw_rect(Rect2(tx, ry - th, 2.0, th - 1.0),
				Color(0.74, 0.82, 1.0, (0.85 if tenth else 0.45) * dim))
	# 隊列の現在位置を指す針（ルーラーのどこに居るかが一目で分かる）
	draw_rect(Rect2(snappedf(ref_x - 2.0, 1.0), ry - 16.0, 4.0, 20.0), Color(0.02, 0.02, 0.05, 0.9))
	draw_rect(Rect2(snappedf(ref_x - 1.0, 1.0), ry - 15.0, 2.0, 18.0),
			Color(CYAN.r, CYAN.g, CYAN.b, 0.95 * dim))

	# 深度と、次のゲートまでの残り
	var fl := int(dist / KuroData.FLOOR_LEN)
	var left := maxf(float(fl + 1) * KuroData.FLOOR_LEN - dist, 0.0)
	var read := "深度 %dm    ゲートまで %dm" % [int(dist), int(left)]
	var rw := font.get_string_size(read, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_S).x
	var rx := snappedf(ref_x - rw * 0.5, 2.0)
	draw_rect(Rect2(rx - 8.0, gy + 20.0, rw + 16.0, 18.0), Color(0.02, 0.02, 0.05, 0.78))
	draw_string(font, Vector2(rx, gy + 33.0), read, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_S,
			Color(0.78, 0.84, 0.96, 0.95))


## 空とネオン都市のパララックス。真っ黒な平面を作らないのが最優先：
## 縦グラデ → 星 → 月と光芒 → 遠景スカイライン → 中景の商店街（実在の看板）→ 粒子。
func _draw_sky(sz: Vector2, gy: float) -> void:
	var pal := _pal()
	var top_c: Color = pal["top"]
	var hor_c: Color = pal["hor"]
	draw_polygon(
			PackedVector2Array([Vector2(0, 0), Vector2(sz.x, 0), Vector2(sz.x, gy), Vector2(0, gy)]),
			PackedColorArray([top_c, top_c, hor_c, hor_c]))
	# 星（決定論・ゆっくり瞬く）。数個だけ白まで振り切って最明部の候補を作る。
	for i in 112:
		var rx := fposmod(sin(i * 91.7) * 43758.5453, 1.0)
		var ry := fposmod(sin(i * 41.3) * 24634.6345, 1.0)
		var tw := 0.35 + 0.3 * sin(_t * (0.8 + rx * 1.6) + i)
		var sp := Vector2(snappedf(rx * sz.x, 2.0), snappedf(60.0 + ry * gy * 0.58, 2.0))
		_octagon(sp, 1.0 + rx * 1.4, Color(0.80, 0.86, 1.0, tw * 0.55))
		if i % 13 == 0:
			_octagon(sp, 1.6, Color(0.86, 0.90, 1.0, tw * 0.8))
	# 靄の帯（空を無地にしない）
	for i in 3:
		var hy := gy * (0.30 + i * 0.14)
		var hh := 26.0 + i * 10.0
		draw_polygon(
				PackedVector2Array([Vector2(0, hy), Vector2(sz.x, hy),
						Vector2(sz.x, hy + hh), Vector2(0, hy + hh)]),
				PackedColorArray([Color(0.42, 0.20, 0.52, 0.0), Color(0.42, 0.20, 0.52, 0.0),
						Color(0.42, 0.20, 0.52, 0.10 + i * 0.03), Color(0.42, 0.20, 0.52, 0.10 + i * 0.03)]))
	# 月（青い月光）＋暈＋光芒。純白の芯は載せない
	# （画面最明部は「プレイヤーが見るべき場所」＝ready光／敵の弱点に予約する）。
	var moon := Vector2(snappedf(sz.x * 0.74, 2.0), snappedf(gy * 0.155, 2.0))
	_glow(moon, 140.0, Color(0.52, 0.70, 1.0), 0.10)
	_disc(moon, 30.0, Color(0.50, 0.60, 0.88, 0.34))
	_disc(moon, 24.0, Color(0.66, 0.73, 0.88, 0.80))
	_draw_shafts(sz, gy, moon)
	# 飛行体（点滅灯）が2機ゆっくり流れる＝空が「生きている」
	for i in 2:
		var ax := fposmod(_t * (9.0 + i * 5.0) + i * 460.0, sz.x + 120.0) - 60.0
		var ay := gy * (0.10 + i * 0.09)
		draw_rect(Rect2(snappedf(ax, 2.0), snappedf(ay, 2.0), 5.0, 2.0), Color(0.70, 0.78, 1.0, 0.5))
		if fposmod(_t * 1.4 + i, 1.0) < 0.45:
			draw_rect(Rect2(snappedf(ax, 2.0), snappedf(ay, 2.0), 2.0, 2.0), Color(1.0, 0.35, 0.35, 0.9))
	# 最遠景（プロシージャルの塔列）：空の空白を埋め、レイヤーの層を1枚増やす
	_draw_far_towers(sz, gy * 0.22, gy * 0.40, 0.08)
	_draw_far_towers(sz, gy * 0.30, gy * 0.54, 0.15)
	# 遠景スカイライン（視差 0.15）
	var far_r := _draw_layer(BG_FAR, sz, gy - 150.0, 0.15,
			Color(0.34, 0.30, 0.52, 0.92))
	_seam_blend(sz, far_r.position.y, Color(0.078, 0.062, 0.28), 0.62)
	# 中景の商店街（視差 0.45・wrap でループ。架空漢字の看板は実在の語で上書き）
	var mid_r := _draw_layer(BG_MID, sz, gy + 6.0, 0.45,
			Color(0.40, 0.35, 0.52, 1.0), true)
	# ── 継ぎ目つぶし ──────────────────────────────────────────────
	# 1) 実際に描かれた矩形の上端を基準に、高さ56pxのグラデ帯を重ねる
	#    （gy 基準の決め打ちだと 260px ずれる。基準は必ず「描いた矩形」）
	_seam_blend(sz, mid_r.position.y, Color(0.11, 0.05, 0.20), 0.78)
	# 2) グラデだけでは直線は消えない。屋根・電線・給水塔のシルエット列で
	#    継ぎ目を跨いで割る。層の境界は「色」ではなく「物」で隠す。
	_draw_far_towers(sz, mid_r.position.y - 104.0, mid_r.position.y + 30.0, 0.45, true)
	_draw_motes(sz, gy)


## 階層ごとのパレット（25分の間に色が変わることが時間経過の唯一の証拠になる）。
func _pal() -> Dictionary:
	return FLOOR_PAL[int(dist / KuroData.FLOOR_LEN) % FLOOR_PAL.size()]


## レイヤー上端のハードエッジを、その上端を中心にした高さ56pxの帯で溶かす。
## 上28px は 0→a、下28px は a→0。両側を同じ色へ引き込むので段差そのものが縮む。
func _seam_blend(sz: Vector2, top_y: float, col: Color, a: float) -> void:
	var y := roundf(top_y)
	draw_polygon(
			PackedVector2Array([Vector2(0, y - 28.0), Vector2(sz.x, y - 28.0),
					Vector2(sz.x, y), Vector2(0, y)]),
			PackedColorArray([Color(col.r, col.g, col.b, 0.0), Color(col.r, col.g, col.b, 0.0),
					Color(col.r, col.g, col.b, a), Color(col.r, col.g, col.b, a)]))
	draw_polygon(
			PackedVector2Array([Vector2(0, y), Vector2(sz.x, y),
					Vector2(sz.x, y + 28.0), Vector2(0, y + 28.0)]),
			PackedColorArray([Color(col.r, col.g, col.b, a), Color(col.r, col.g, col.b, a),
					Color(col.r, col.g, col.b, 0.0), Color(col.r, col.g, col.b, 0.0)]))


## 月からの光芒（夜でも真っ黒にしないための主光源）。
## 上を濃く下を0にした頂点カラーの四角形＝ハードエッジの出ない安価な光の柱。
func _draw_shafts(sz: Vector2, gy: float, moon: Vector2) -> void:
	var a := 0.055 + 0.020 * sin(_t * 0.7)
	var col := Color(0.58, 0.82, 1.0)
	for s: Array in [[moon.x, 20.0, 150.0, 1.0], [moon.x - 78.0, 10.0, 96.0, 0.7],
			[sz.x * 0.17, 12.0, 150.0, 0.55]]:
		var x0: float = s[0]
		var tw: float = s[1]
		var bw: float = s[2]
		var k: float = s[3]
		var top := moon.y if x0 > sz.x * 0.3 else -20.0
		draw_polygon(
				PackedVector2Array([Vector2(x0 - tw, top), Vector2(x0 + tw, top),
						Vector2(x0 + bw, gy), Vector2(x0 - bw * 0.5, gy)]),
				PackedColorArray([Color(col.r, col.g, col.b, a * k), Color(col.r, col.g, col.b, a * k),
						Color(col.r, col.g, col.b, 0.0), Color(col.r, col.g, col.b, 0.0)]))


## 塔列（決定論）。用途は2つ：
##  - 最遠景の層を1枚増やして空を埋める（roofline=false）
##  - レイヤーの継ぎ目を「物」で跨いで割る（roofline=true：屋根・給水塔・電線）
## speed は視差（far 0.15 / mid 0.45 に合わせる）。
func _draw_far_towers(sz: Vector2, top_y: float, base_y: float, speed := 0.15,
		roofline := false) -> void:
	var span := 34.0 if roofline else 48.0
	var scroll := fposmod(dist * 14.0 * speed, span)
	var dark := Color(0.05, 0.03, 0.11, 0.98) if roofline else Color(0.14, 0.07, 0.27, 0.92)
	var lip := Color(0.20, 0.12, 0.34, 0.85) if roofline else Color(0.26, 0.14, 0.44, 0.9)
	var wire_y := base_y - (base_y - top_y) * 0.34
	if roofline:
		# 電線：継ぎ目を斜めに跨ぐ2本（直線の水平エッジを目で追えなくする）
		for w in 2:
			var sag := 14.0 + w * 9.0
			var y0 := wire_y - w * 22.0
			var pts := PackedVector2Array()
			for j in 13:
				var tt := j / 12.0
				pts.append(Vector2(tt * sz.x, y0 + sin(tt * PI) * sag
						+ sin(tt * 6.2 + dist * 0.02) * 3.0))
			draw_polyline(pts, Color(0.04, 0.02, 0.09, 0.85), 2.0)
	for k in range(-1, int(sz.x / span) + 2):
		var rx := fposmod(sin(k * 71.3) * 43758.5453, 1.0)
		var ry := fposmod(sin(k * 13.9) * 24634.6345, 1.0)
		var x := snappedf(k * span - scroll, 2.0)
		var w := snappedf((14.0 + rx * 20.0) if roofline else (22.0 + rx * 22.0), 2.0)
		var h := (base_y - top_y) * ((0.30 + ry * 0.70) if roofline else (0.35 + ry * 0.65))
		var y := snappedf(base_y - h, 2.0)
		draw_rect(Rect2(x, y, w, h), dark)
		draw_rect(Rect2(x, y, w, 2.0), lip)
		if roofline:
			# 給水塔（脚つき）／室外機の塊を屋根の上に乗せる
			if rx > 0.70:
				var tw := w * 0.52
				draw_rect(Rect2(x + w * 0.5 - tw * 0.5, y - 22.0, tw, 16.0), dark)
				draw_rect(Rect2(x + w * 0.5 - tw * 0.5, y - 24.0, tw, 3.0), lip)
				draw_rect(Rect2(x + w * 0.5 - tw * 0.5 + 1.0, y - 6.0, 2.0, 6.0), dark)
				draw_rect(Rect2(x + w * 0.5 + tw * 0.5 - 3.0, y - 6.0, 2.0, 6.0), dark)
			elif ry > 0.55:
				draw_rect(Rect2(x + 3.0, y - 9.0, w - 8.0, 9.0), dark)
			# アンテナ
			if rx > 0.34 and rx <= 0.70:
				draw_rect(Rect2(x + w * 0.5, y - 20.0, 2.0, 20.0), dark)
			continue
		# アンテナと赤い航空障害灯（無地の塊にしない）
		if rx > 0.62:
			draw_rect(Rect2(x + w * 0.5, y - 16.0, 2.0, 16.0), Color(0.22, 0.12, 0.38, 0.9))
			draw_rect(Rect2(x + w * 0.5 - 1.0, y - 18.0, 4.0, 3.0),
					Color(1.0, 0.28, 0.30, 0.35 + 0.45 * maxf(0.0, sin(_t * 1.6 + k))))
		# 窓明かり（数点だけ・ゆっくり明滅／オレンジは使わない）
		for j in 5:
			var wy := y + 8.0 + j * (h / 6.0)
			if wy > base_y - 6.0:
				break
			var lit := fposmod(sin(k * 7.7 + j * 3.1) * 999.0, 1.0)
			if lit > 0.45:
				draw_rect(Rect2(x + 4.0 + fposmod(lit * 31.0, maxf(w - 10.0, 2.0)), wy, 3.0, 3.0),
						Color(0.80, 0.82, 0.72, 0.26 + 0.20 * sin(_t * 0.6 + k + j)))


## 舞う粒子。25分眺める画面に「動いている空気」を足す。
func _draw_motes(sz: Vector2, gy: float) -> void:
	for i in 34:
		var rx := fposmod(sin(i * 12.9898) * 43758.5453, 1.0)
		var rz := fposmod(sin(i * 78.233) * 12345.6789, 1.0)
		var px := fposmod(rx * sz.x + sin(_t * 0.3 + i) * 24.0, sz.x)
		var py := fposmod(gy + 40.0 - (_t * (6.0 + rz * 16.0) + rz * 900.0), gy + 60.0) - 20.0
		_octagon(Vector2(px, py), 1.0 + rz * 2.2, Color(0.72, 0.86, 1.0, 0.10 + rz * 0.28))


## パララックス層。倍率は PIX_MULT（整数）固定で、絵の大きさは
## 事前リサンプル済みアセット側で決める＝ランタイムでテクセルが割れない。
## 戻り値は「実際に描いた矩形」。継ぎ目処理はこの矩形の上端を基準に置く
## （gy などの間接値から逆算すると数百px ずれる）。
func _draw_layer(path: String, sz: Vector2, bottom_y: float, speed: float,
		tint: Color, with_signs := false) -> Rect2:
	var tex := _tex(path)
	if tex == null:
		return Rect2(0, bottom_y, sz.x, 0)
	var ts := tex.get_size() * float(PIX_MULT)
	var scroll := fposmod(dist * 14.0 * speed, ts.x)
	var y := snappedf(bottom_y - ts.y, float(PIX_MULT))
	var x := -snappedf(scroll, float(PIX_MULT))
	while x < sz.x:
		draw_texture_rect(tex, Rect2(x, y, ts.x, ts.y), false, tint)
		if with_signs:
			_draw_signs(Vector2(x, y), ts)
		x += ts.x
	return Rect2(0, y, sz.x, ts.y)


## city_mid に焼かれた「実在しない漢字」の看板を、実在の語のネオン看板で覆う。
## SIGNS は元PNG（720x260）座標なので、実際に描いたタイル矩形から換算する。
## 色相は階層パレットで回す（B1F→B2F で街の色が変わる＝時間が経った証拠）。
func _draw_signs(origin: Vector2, tile: Vector2) -> void:
	var font := get_theme_default_font()
	var sx := tile.x / 720.0
	var sy := tile.y / MID_SRC_H
	var hue := float(_pal()["hue"])
	for s: Dictionary in SIGNS:
		var sr: Rect2 = s["r"]
		# 同じ行に上端・下端が揃うと全幅の横線になる。看板ごとに決定論的にずらす。
		var jit := roundf(fposmod(sin(sr.position.x * 3.7 + sr.position.y) * 999.0, 29.0)) - 14.0
		var r := Rect2(roundf(origin.x + sr.position.x * sx),
				roundf(origin.y + (sr.position.y - MID_SRC_TOP) * sy + jit),
				roundf(sr.size.x * sx), roundf(sr.size.y * sy + jit * 0.5))
		if r.position.x > size.x + 8.0 or r.position.x + r.size.x < -8.0:
			continue
		var col: Color = s["c"]
		if hue > 0.0:
			col = Color.from_hsv(fposmod(col.h + hue, 1.0), col.s * 0.92, col.v)
		_glow(r.get_center(), maxf(r.size.x, r.size.y) * 1.15, col, 0.09)
		draw_rect(r, Color(0.05, 0.03, 0.09, 0.98))
		draw_rect(r, Color(col.r, col.g, col.b, 0.72), false, 2.0)
		var txt := String(s["t"])
		if bool(s["v"]):
			var fs := _fs(r.size.x * 0.80)
			var n := txt.length()
			for k in n:
				var ch := txt[k]
				var cw := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_string(font, Vector2(r.position.x + (r.size.x - cw) * 0.5,
						r.position.y + r.size.y * (k + 0.86) / float(n)), ch,
						HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		else:
			var fs := _fs(minf(r.size.y * 0.70, r.size.x / maxf(txt.length(), 1) * 1.02))
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(r.position.x + (r.size.x - tw) * 0.5,
					r.position.y + (r.size.y + fs * 0.70) * 0.5), txt,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		# ネオン管の芯。純白は使わない（最明部は味方の ready 光と敵の弱点に予約）
		draw_rect(Rect2(r.position.x + 3.0, r.position.y + 3.0,
				minf(14.0, maxf(r.size.x - 6.0, 4.0)), 2.0),
				Color(col.r * 0.6 + 0.35, col.g * 0.6 + 0.35, col.b * 0.6 + 0.35, 0.75))


## 文字サイズを 12/16/22/32/48 の5段へ丸める。段を増やさないための唯一の入口。
func _fs(want: float) -> int:
	var best := FS_S
	var bd := 9e9
	for v in [FS_S, FS_M, FS_L, FS_XL, 48]:
		var d := absf(float(v) - want)
		if d < bd:
			bd = d
			best = int(v)
	return best


## 床。奥＝暗い紫、手前＝濡れたアスファルト。画面下端まで届かせて
## 「正体不明の灰色のもや」と「純黒の帯」を作らない。
func _draw_ground(sz: Vector2, gy: float) -> void:
	var bottom := sz.y
	var depth := bottom - gy
	var near: Color = _pal()["floor"]
	draw_polygon(
			PackedVector2Array([Vector2(0, gy), Vector2(sz.x, gy), Vector2(sz.x, bottom), Vector2(0, bottom)]),
			PackedColorArray([Color(0.09, 0.06, 0.14), Color(0.09, 0.06, 0.14),
					near, near]))
	# 透視ライン（下ほど間隔が広がる）
	for i in range(1, 10):
		var k := float(i) / 10.0
		draw_rect(Rect2(0, snappedf(gy + depth * pow(k, 1.75), 1.0), sz.x, 1.0),
				Color(0.62, 0.52, 0.95, 0.05 + 0.11 * k))
	# 縦の目地（消失点へ収束・進行でスクロール）
	var vp := sz.x * 0.5
	var scroll := fposmod(dist * 14.0, 120.0)
	for k in range(-6, 9):
		var dx := float(k) * 120.0 - scroll
		draw_line(Vector2(snappedf(vp + dx * 0.30, 1.0), gy),
				Vector2(snappedf(vp + dx * 1.60, 1.0), bottom), Color(0.60, 0.50, 0.92, 0.07), 1.0)
	# 手前の濡れた路面の反射（ネオンが伸びる）
	for r: Dictionary in [
			{"x": 0.20, "c": Color(1.0, 0.42, 0.78)},
			{"x": 0.53, "c": Color(0.40, 0.95, 1.0)},
			{"x": 0.84, "c": Color(0.62, 0.55, 1.0)}]:
		var rx := sz.x * float(r["x"])
		var c: Color = r["c"]
		for j in 8:
			var yy := gy + depth * (0.14 + j * 0.105)
			var w := 9.0 + j * 5.0
			draw_rect(Rect2(snappedf(rx - w * 0.5 + sin(_t * 1.3 + j * 0.9) * 3.5, 1.0),
					snappedf(yy, 1.0), w, 3.0), Color(c.r, c.g, c.b, 0.17 * (1.0 - j / 9.0)))
	# 隊列の足元にステージ光（近景のコントラストアンカー）
	var stage_x := PARTY_X0 + PARTY_GAP * 2.0
	for i in 5:
		var k := float(5 - i) / 5.0
		_ellipse(Vector2(stage_x, gy + 10.0), Vector2(200.0 * k, 52.0 * k),
				Color(0.85, 0.80, 1.0, 0.020))
	# 接地ライン（床の上端）＝コントラストのアンカー
	_glow(Vector2(sz.x * 0.5, gy), sz.x * 0.55, PURPLE, 0.05)
	draw_rect(Rect2(0, gy - 2.0, sz.x, 2.0), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.34))
	# 下へ12pxのグラデで溶かす（線は残すが1行の段差にはしない）
	draw_polygon(
			PackedVector2Array([Vector2(0, gy), Vector2(sz.x, gy),
					Vector2(sz.x, gy + 12.0), Vector2(0, gy + 12.0)]),
			PackedColorArray([Color(0.04, 0.02, 0.07, 0.55), Color(0.04, 0.02, 0.07, 0.55),
					Color(0.04, 0.02, 0.07, 0.0), Color(0.04, 0.02, 0.07, 0.0)]))
	for k in 5:
		draw_rect(Rect2(snappedf(fposmod(sz.x * (0.08 + k * 0.21) - dist * 14.0, sz.x), 2.0),
				gy - 3.0, 14.0, 2.0), Color(0.70, 0.74, 0.92, 0.7))


## 近景レイヤー（キャラの手前）。手前を明るくし、ぼけた大粒と軽いビネットを足す。
func _draw_foreground(sz: Vector2, gy: float) -> void:
	var depth := sz.y - gy
	draw_polygon(
			PackedVector2Array([Vector2(0, gy + depth * 0.42), Vector2(sz.x, gy + depth * 0.42),
					Vector2(sz.x, sz.y), Vector2(0, sz.y)]),
			PackedColorArray([Color(0.78, 0.70, 1.0, 0.0), Color(0.78, 0.70, 1.0, 0.0),
					Color(0.78, 0.70, 1.0, 0.10), Color(0.78, 0.70, 1.0, 0.10)]))
	for i in 9:
		var rz := fposmod(sin(i * 33.77) * 9871.23, 1.0)
		var px := fposmod(rz * sz.x + _t * (10.0 + rz * 18.0), sz.x + 40.0) - 20.0
		var py := gy - 130.0 + fposmod(_t * (14.0 + rz * 20.0) + rz * 400.0, depth + 130.0)
		_octagon(Vector2(px, py), 2.5 + rz * 3.5, Color(0.80, 0.90, 1.0, 0.07 + rz * 0.08))
	_draw_props(sz, gy)


## 前景の遮蔽物（電柱・ゴミ箱・フェンス）。視差1.4倍で右から左へ流れる。
## 前景が横切るだけで「移動している」画になる（25分ぶん動かす一番安いネタ）。
func _draw_props(sz: Vector2, gy: float) -> void:
	var span := 300.0
	var scroll := fposmod(dist * 14.0 * 1.4, span)
	for k in range(-1, int(sz.x / span) + 3):
		var rz := fposmod(sin(k * 45.31) * 43758.5453, 1.0)
		var x := snappedf(k * span - scroll, 2.0)
		if x > sz.x + 160.0:
			continue
		# 隊列と敵は画面の左〜中央に立つ。遮蔽物は右へ行くほど濃く、
		# 主役の帯へ入るにつれて消える（黒い板で主役を潰さないための唯一の制御）。
		var a := clampf((x - sz.x * 0.38) / 150.0, 0.0, 1.0)
		if a <= 0.02:
			continue
		var body := Color(STRUCT.r, STRUCT.g, STRUCT.b, a)
		var lip := Color(0.34, 0.30, 0.52, 0.55 * a)   # 縁の1px反射（黒い穴に見せない）
		match int(rz * 3.0) % 3:
			0:  # 電柱（画面上端から地面まで貫く＝最前面のスケール基準）
				draw_rect(Rect2(x, 0.0, 14.0, gy + 34.0), body)
				draw_rect(Rect2(x + 12.0, 0.0, 2.0, gy + 34.0), lip)
				draw_rect(Rect2(x - 26.0, gy - 226.0, 66.0, 6.0), body)
				draw_rect(Rect2(x - 20.0, gy - 176.0, 54.0, 5.0), body)
				draw_rect(Rect2(x + 3.0, gy - 214.0, 3.0, 40.0), Color(0.08, 0.07, 0.15, 0.9 * a))
			1:  # ゴミ箱（2つ・地面に置く）
				for j in 2:
					var bx := x + j * 40.0
					var bh := 52.0 + rz * 14.0
					draw_rect(Rect2(bx, gy + 20.0 - bh, 32.0, bh), body)
					draw_rect(Rect2(bx - 3.0, gy + 14.0 - bh, 38.0, 6.0), Color(0.06, 0.05, 0.12, a))
					draw_rect(Rect2(bx - 3.0, gy + 14.0 - bh, 38.0, 2.0), lip)
					draw_rect(Rect2(bx + 30.0, gy + 20.0 - bh, 2.0, bh), lip)
			_:  # フェンス（金網・隙間から背景が見える）
				var fh := 74.0
				var fy := gy + 22.0 - fh
				draw_rect(Rect2(x, fy, 4.0, fh), body)
				draw_rect(Rect2(x + 118.0, fy, 4.0, fh), body)
				draw_rect(Rect2(x, fy, 122.0, 4.0), body)
				draw_rect(Rect2(x, fy, 122.0, 1.0), lip)
				for j in range(0, 14):
					draw_line(Vector2(x + j * 9.0, fy + 4.0), Vector2(x + j * 9.0 + 22.0, fy + fh),
							Color(STRUCT.r, STRUCT.g, STRUCT.b, 0.50 * a), 1.0)
					draw_line(Vector2(x + j * 9.0 + 22.0, fy + 4.0), Vector2(x + j * 9.0, fy + fh),
							Color(STRUCT.r, STRUCT.g, STRUCT.b, 0.50 * a), 1.0)


## 非戦闘中でも右奥に「近づいてくる影」を置く。右半分を空にせず次の交戦を予告する。
func _draw_incoming(sz: Vector2, gy: float) -> void:
	var names := ["mob_spider", "mob_drone", "mob_slime"]
	# 近づく段階は3段（それぞれ整数倍で貼れるようピクセル高さを離散化する）
	var steps := [34, 48, 68]
	for i in 3:
		var k := fposmod(_t / (13.0 + i * 5.0) + i * 0.37, 1.0)   # 0=遠い 1=近い
		var nm: String = names[i]
		var ph: int = steps[clampi(int(k * 3.0), 0, 2)]
		var fi := int(_mob_key(nm, 4.0 + i).get_slice(":", 1))
		var key := "%s:%d:%d" % [nm, fi, ph]
		var tex := _mob_frame(nm, fi, ph)
		var pads: Vector2 = _pad_cache.get(key, Vector2.ZERO)
		var feet := Vector2(sz.x * (1.02 - k * 0.28), gy - 14.0 + k * 12.0 + i * 2.0)
		var a := 0.35 + k * 0.40
		_draw_actor(tex, feet, 1, pads, Color(0.24, 0.10, 0.26, a))
		_contact_shadow(feet, _actor_w(tex, 1) * 0.5)
		# 赤い眼だけ闇に光る（次の交戦の予告）
		_octagon(Vector2(feet.x, feet.y - ph * 0.62), 1.6 + k * 1.6,
				Color(1.0, 0.25, 0.28, 0.35 + k * 0.5))


## draw_circle の代わり（ドット絵に馴染む8角形）。
func _octagon(c: Vector2, r: float, col: Color) -> void:
	if r <= 0.25:
		return
	var pts := PackedVector2Array()
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		pts.append(c + Vector2(cos(a) * r, sin(a) * r))
	draw_colored_polygon(pts, col)


## 円（月・光点用）。draw_circle より辺数を抑えつつ、8角形ほど角張らせない。
func _disc(c: Vector2, r: float, col: Color) -> void:
	if r <= 0.25:
		return
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(c + Vector2(cos(a) * r, sin(a) * r))
	draw_colored_polygon(pts, col)


## 柔らかい発光（同心円の入れ子）。テクスチャ不要で決定論的。
func _glow(c: Vector2, r: float, col: Color, a: float) -> void:
	for i in 7:
		_disc(c, r * float(7 - i) / 7.0, Color(col.r, col.g, col.b, a * 0.26))


func _ellipse(c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 14:
		var a := TAU * i / 14.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(pts, col)


## 接地。楕円デカールは脚が貫通して破綻するのでやめ、
## 足元 y に接する 1px の水平ハイライト線＋その下に高さ4pxの濃い接触影を置く。
## 「線に乗っている」ほうが「楕円に埋まっている」より確実に接地して見える。
func _contact_shadow(feet: Vector2, w: float) -> void:
	if w <= 2.0:
		return
	var y := roundf(feet.y)
	var x := roundf(feet.x - w * 0.5)
	# 下の接触影（4px・中央が濃い）
	for j in 4:
		var a := 0.62 * (1.0 - j / 4.0)
		var ww := w * (1.0 - j * 0.13)
		draw_rect(Rect2(roundf(feet.x - ww * 0.5), y + 1.0 + j, roundf(ww), 1.0),
				Color(0.02, 0.01, 0.04, a))
	# 足が乗る 1px のハイライト線（床の反射光）
	draw_rect(Rect2(x, y, roundf(w), 1.0), Color(0.72, 0.68, 0.92, 0.38))
	draw_rect(Rect2(x + w * 0.28, y, roundf(w * 0.44), 1.0), Color(0.86, 0.84, 1.0, 0.50))


## 敵の背後だけを落とす局所減光。bbox を1.6倍に広げた矩形へ放射状のグラデを敷く。
## 敵を明るくするのではなく、敵の後ろを暗くすることで存在感を作る。
func _backdrop_dim(center: Vector2, w: float, h: float) -> void:
	var rx := maxf(w, 8.0) * 0.8
	var ry := maxf(h, 8.0) * 0.8
	for i in 7:
		var k := float(7 - i) / 7.0
		_ellipse(center, Vector2(rx * k, ry * k), Color(0.04, 0.02, 0.10, 0.55 * 0.20))


## 次に動ける味方の頭上の ready 光。敵の弱点とならぶ画面最明部。
func _ready_light(c: Vector2) -> void:
	var p := 0.5 + 0.5 * sin(_ct * 2.6)
	_glow(c, 22.0 + 4.0 * p, CYAN, 0.11)
	_octagon(c, 4.0 + 0.8 * p, Color(0.62, 0.96, 1.0, 0.85))
	_octagon(c, 1.8, NEON_CORE)


## 敵の弱点コア。画面の最明部はここ（＝プレイヤーが次に見るべき場所）。
func _weak_point(c: Vector2, boss: bool) -> void:
	var p := 0.5 + 0.5 * sin(_ct * (3.4 if boss else 2.4))
	var r := (6.0 if boss else 4.2) * (1.0 + 0.16 * p)
	_glow(c, r * 6.0, Color(1.0, 0.52, 0.26), 0.10 + 0.06 * p)   # 橙＝敵/危険に予約した色相
	_octagon(c, r * 1.9, Color(1.0, 0.42, 0.20, 0.55 + 0.25 * p))
	_octagon(c, r, Color(1.0, 0.86, 0.70, 0.95))
	_octagon(c, r * 0.62, NEON_CORE)


## 上端から垂れる構造体（配管・鉄骨・ケーブル）。空を「埋める」のではなく構図を変える：
## 画面の上に前景の暗い塊があると「下へ潜っている」感覚が出る。隙間から空を覗かせる。
func _draw_canopy(sz: Vector2) -> void:
	var scroll := fposmod(dist * 14.0, 180.0)
	# 天井の縁（上端に厚みを持たせる）
	draw_polygon(
			PackedVector2Array([Vector2(0, 0), Vector2(sz.x, 0), Vector2(sz.x, 46), Vector2(0, 46)]),
			PackedColorArray([Color(STRUCT.r, STRUCT.g, STRUCT.b, 0.98),
					Color(STRUCT.r, STRUCT.g, STRUCT.b, 0.98),
					Color(STRUCT.r, STRUCT.g, STRUCT.b, 0.86),
					Color(STRUCT.r, STRUCT.g, STRUCT.b, 0.86)]))
	# 鉄骨（斜材つきのトラス）。全幅を貫くが下端はバラバラ＝真っ直ぐな帯を作らない。
	for k in range(-1, int(sz.x / 180.0) + 2):
		var rx := fposmod(sin(k * 27.1) * 43758.5453, 1.0)
		var ry := fposmod(sin(k * 63.7) * 24634.6345, 1.0)
		var x := snappedf(k * 180.0 - scroll, 2.0)
		var bh := 96.0 + ry * 150.0     # 46〜260 の間で高さがばらつく
		draw_rect(Rect2(x, 40.0, 26.0, bh), Color(STRUCT.r, STRUCT.g, STRUCT.b, 0.96))
		draw_rect(Rect2(x, 40.0, 26.0, 2.0), Color(0.10, 0.09, 0.18, 0.7))
		# 斜材（×）
		draw_line(Vector2(x + 2, 46.0), Vector2(x + 24, 46.0 + bh * 0.5),
				Color(STRUCT.r, STRUCT.g, STRUCT.b, 0.9), 3.0)
		draw_line(Vector2(x + 24, 46.0), Vector2(x + 2, 46.0 + bh * 0.5),
				Color(STRUCT.r, STRUCT.g, STRUCT.b, 0.9), 3.0)
		# 配管（太い縦管＋継手のリング）
		var px := x + 62.0 + rx * 54.0
		var ph := 70.0 + rx * 170.0
		draw_rect(Rect2(snappedf(px, 2.0), 30.0, 14.0, ph), Color(STRUCT.r, STRUCT.g, STRUCT.b, 0.97))
		for j in 3:
			var jy := 60.0 + j * (ph / 3.2)
			if jy > 30.0 + ph - 6.0:
				break
			draw_rect(Rect2(snappedf(px - 3.0, 2.0), snappedf(jy, 2.0), 20.0, 5.0),
					Color(0.07, 0.06, 0.13, 0.95))
		# 管の先の小さな警告灯（オレンジ＝危険の色相。ごく小さく）
		if rx > 0.55:
			draw_rect(Rect2(snappedf(px + 4.0, 2.0), snappedf(30.0 + ph, 2.0), 4.0, 4.0),
					Color(1.0, 0.42, 0.22, 0.30 + 0.30 * maxf(0.0, sin(_t * 1.9 + k))))
		# ケーブル（垂れ下がるカテナリ）
		var cx := x + 118.0 + ry * 44.0
		var pts := PackedVector2Array()
		for j in 9:
			var tt := j / 8.0
			pts.append(Vector2(cx + tt * 96.0, 24.0 + sin(tt * PI) * (54.0 + rx * 96.0)))
		draw_polyline(pts, Color(STRUCT.r, STRUCT.g, STRUCT.b, 0.92), 3.0)


## 画面全体のビネット（四隅 α≒0.55）。背景の輝度と彩度を主役より下に押し込む。
func _draw_vignette(sz: Vector2) -> void:
	var a := 0.33
	var wx := sz.x * 0.34
	var wy := sz.y * 0.24
	var c := Color(0.02, 0.01, 0.05)
	# 左右
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(wx, 0), Vector2(wx, sz.y), Vector2(0, sz.y)]),
			PackedColorArray([Color(c.r, c.g, c.b, a), Color(c.r, c.g, c.b, 0.0),
					Color(c.r, c.g, c.b, 0.0), Color(c.r, c.g, c.b, a)]))
	draw_polygon(PackedVector2Array([Vector2(sz.x - wx, 0), Vector2(sz.x, 0),
					Vector2(sz.x, sz.y), Vector2(sz.x - wx, sz.y)]),
			PackedColorArray([Color(c.r, c.g, c.b, 0.0), Color(c.r, c.g, c.b, a),
					Color(c.r, c.g, c.b, a), Color(c.r, c.g, c.b, 0.0)]))
	# 上下
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(sz.x, 0), Vector2(sz.x, wy), Vector2(0, wy)]),
			PackedColorArray([Color(c.r, c.g, c.b, a), Color(c.r, c.g, c.b, a),
					Color(c.r, c.g, c.b, 0.0), Color(c.r, c.g, c.b, 0.0)]))
	draw_polygon(PackedVector2Array([Vector2(0, sz.y - wy), Vector2(sz.x, sz.y - wy),
					Vector2(sz.x, sz.y), Vector2(0, sz.y)]),
			PackedColorArray([Color(c.r, c.g, c.b, 0.0), Color(c.r, c.g, c.b, 0.0),
					Color(c.r, c.g, c.b, a), Color(c.r, c.g, c.b, a)]))


## 接続ポータル（左端・青い渦）＋ステージ章票＋獲得ゴールド。
func _draw_portal(base: Vector2, font: Font) -> void:
	var c := base + Vector2(0, -58.0)
	_glow(c, 90.0, CYAN, 0.16)
	var pr := 30.0 + 2.5 * sin(_t * 2.4)
	draw_arc(c, pr, _t * 1.8, _t * 1.8 + TAU * 0.8, 30, Color(0.35, 0.75, 1.0), 4.0)
	draw_arc(c, pr * 0.62, -_t * 2.6, -_t * 2.6 + TAU * 0.66, 24, CYAN, 3.0)
	_octagon(c, pr * 0.34, Color(0.5, 0.85, 1.0, 0.9))
	_octagon(c, pr * 0.16, Color(0.72, 0.88, 1.0, 0.9))
	_contact_shadow(base, 46.0)
	# 章票 幕-番号（タスクバーヒーロー表記）＋難易度
	var fl := int(dist / KuroData.FLOOR_LEN)
	var dd: Dictionary = KuroData.DIFFICULTIES[clampi(difficulty, 0, KuroData.DIFFICULTIES.size() - 1)]
	var dcol: Color = dd["color"]
	var chip := KuroData.stage_label(fl)
	if difficulty > 0:
		chip += "  %s" % String(dd["name"])
	var cw := font.get_string_size(chip, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_M).x + 24
	var cr := Rect2(snappedf(c.x - cw * 0.5, 2.0), snappedf(c.y - 96.0, 2.0), snappedf(cw, 2.0), 28.0)
	draw_rect(cr, Color(0.04, 0.04, 0.08, 0.92))
	draw_rect(cr, Color(dcol.r, dcol.g, dcol.b, 0.65), false, 1.0)
	draw_string(font, Vector2(cr.position.x + 12, cr.position.y + 20), chip,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FS_M, Color(0.92, 0.94, 1.0))
	# 獲得ゴールド（章票の右）
	if gold_gain > 0:
		var gtxt := "%d" % gold_gain
		var gx := cr.position.x + cr.size.x + 12.0
		_octagon(Vector2(gx + 7, cr.position.y + 14), 7.0, GOLD)
		_octagon(Vector2(gx + 7, cr.position.y + 14), 4.0, Color(1.0, 0.92, 0.6))
		draw_string(font, Vector2(gx + 18, cr.position.y + 20), gtxt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, FS_M, GOLD)


## 階の最奥ゲート（進行85%超で右端に現れて近づく）。
func _draw_goal(sz: Vector2, gy: float) -> void:
	var prog := fposmod(dist, KuroData.FLOOR_LEN) / KuroData.FLOOR_LEN
	if prog < 0.82 or in_combat:
		return
	# 0.82→1.0 で右端から敵スロット奥へ寄ってくる
	var k := (prog - 0.82) / 0.18
	var gx := sz.x + 60.0 - k * (sz.x * 0.22 + 60.0)
	var c := Vector2(gx, gy - 64.0)
	var near_boss := prog > 0.92
	var col := Color(1.0, 0.4, 0.45) if near_boss else PURPLE
	_glow(c, 110.0, col, 0.18)
	var pr := 36.0 + 3.0 * sin(_t * (3.5 if near_boss else 1.8))
	draw_arc(c, pr, -_t * 1.4, -_t * 1.4 + TAU * 0.82, 30, col, 4.0)
	_octagon(c, pr * 0.30, Color(col.r, col.g, col.b, 0.8))
	_octagon(c, pr * 0.13, Color(0.86, 0.80, 1.0, 0.9))
	_contact_shadow(Vector2(gx, gy), 48.0)


## 味方の頭上HP。常設せず、被弾直後の 0.8 秒だけフェードで出す
## （常設のHP/SPは下部カードに一本化）。
func _draw_head_ui(top: Vector2, w: float, hp_ratio: float, col: Color, a: float) -> void:
	if a <= 0.02:
		return
	var r := Rect2(snappedf(top.x - w * 0.5, 2.0), snappedf(top.y - 6.0, 2.0), w, 6.0)
	draw_rect(Rect2(r.position - Vector2(2, 2), r.size + Vector2(4, 4)), Color(0.02, 0.01, 0.03, 0.8 * a))
	var ratio := clampf(hp_ratio, 0.0, 1.0)
	var bar_col := col if ratio > 0.3 else Color(1.0, 0.42, 0.4)
	draw_rect(Rect2(r.position, Vector2(r.size.x * ratio, r.size.y)),
			Color(bar_col.r, bar_col.g, bar_col.b, a))


## 敵の頭上HP：黒下地＋1px外枠＋数値。ネオン背景でも輪郭が消えない。
func _draw_enemy_hp(font: Font, top: Vector2, w: float, ratio: float, hp: int, boss: bool) -> void:
	var h := 8.0 if boss else 6.0
	var r := Rect2(snappedf(top.x - w * 0.5, 2.0), snappedf(top.y - h, 2.0), snappedf(w, 2.0), h)
	draw_rect(Rect2(r.position - Vector2(2, 2), r.size + Vector2(4, 4)), Color(0.02, 0.01, 0.03, 0.88))
	draw_rect(Rect2(r.position - Vector2(1, 1), r.size + Vector2(2, 2)), Color(1, 1, 1, 0.28), false, 1.0)
	var k := clampf(ratio, 0.0, 1.0)
	draw_rect(r, Color(0.20, 0.03, 0.06))
	draw_rect(Rect2(r.position, Vector2(r.size.x * k, r.size.y)), Color(0.95, 0.25, 0.28))
	draw_rect(Rect2(r.position, Vector2(r.size.x * k, 1.0)), Color(1.0, 0.78, 0.78, 0.85))
	var txt := str(maxi(hp, 0))
	var fs := FS_S
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tp := Vector2(snappedf(r.position.x + (r.size.x - tw) * 0.5, 2.0), r.position.y - 5.0)
	draw_string(font, tp + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.85))
	draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.82, 0.82))


## スキルCDピップ（点灯=撃てる）。戦闘中だけ頭上に小さく出す。
func _draw_pips(top: Vector2, ready: int, slots: int) -> void:
	if slots <= 0:
		return
	var px := top.x - (slots * 11.0 - 3.0) * 0.5
	for i in slots:
		var pc := Vector2(snappedf(px + i * 11.0 + 3.0, 2.0), snappedf(top.y, 2.0))
		_octagon(pc, 4.5, Color(0.02, 0.01, 0.04, 0.75))
		_octagon(pc, 3.2, GOLD if i < ready else Color(0.32, 0.33, 0.40))
		if i < ready:
			_octagon(pc, 1.4, NEON_CORE)


## セリフ選択へ渡す文脈。シムの進行度に、表示層しか知らない2つを足す。
##   hour  … 実時刻（深夜に「まだ起きてるんですか」と言えるように）
##   after … 直前の出来事（ボスの直後・全滅の直後に反応できるように）
func _ctx() -> Dictionary:
	var c := {}
	var s := _find_sim()
	if s != null and s.has_method("banter_context"):
		c = s.banter_context()
	c["hour"] = Time.get_datetime_dict_from_system().get("hour", 12)
	c["after"] = _last_event
	return c


## 祖先から KuroSim を持つノードを探す（このビューは sim を直接持たない）。
func _find_sim() -> Variant:
	var n: Node = self
	while n != null:
		if n.get("sim") != null:
			return n.get("sim")
		n = n.get_parent()
	return null
