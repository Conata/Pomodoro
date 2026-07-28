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
const GOLD := DS.GOLD                    # 状態色・獲得（DS と同じ物を使う）
const TEXT := Color(0.96, 0.95, 0.98)
const TEXT_DIM := Color(0.75, 0.76, 0.84)

# 外側マージンは全画面で 16（DS.SP_4）。場当たりの 12/14/20 は置かない。
const M := DS.SP_4

# バンタ（掛け合い）設定
const HOME_CAST := ["mil", "yuzuki", "muu", "kiriko", "doctor", "nurse"]
const BANTER_INTERVAL := 6.0   # 秒：次のセリフまでのインターバル
const EXCHANGE_STEP  := 3.2    # 秒：掛け合いの1行表示時間

const STRIP_H := 60.0   # 最下部 HD-2D フィールド帯の高さ（FieldStrip と一致させる）
const FOOTER_H := 58.0   # 最下部フッターナビバーの高さ（旧版のボトムタブを踏襲）
const TOPBAR_H := 84.0   # トップバー（経営シートのヘッダと同じ高さ・同じ作法）

# 各主要機能へのフッターナビ（旧 main_legacy の 店/メンバー/工房/市場/経営 を踏襲）。
# id は main.gd の _on_home_action(id) に届く。
const NAV := [
	{"id": "home",       "icon": "家", "label": "ホーム",   "col": CYAN},
	{"id": "member",     "icon": "仲", "label": "メンバー", "col": PINK},
	{"id": "market",     "icon": "市", "label": "市場",     "col": GOLD},
	{"id": "management", "icon": "店", "label": "経営",     "col": PURPLE},
	{"id": "workshop",   "icon": "工", "label": "工房",     "col": CYAN},
	{"id": "memory",     "icon": "記", "label": "記憶",     "col": PURPLE},
]

# ── 表示データ（main.gd から set_data()）──
var speaker := "フユキ"
var line := "「後悔が騒いでるね。奥に潜って、静かにしてあげる。」"
var day_gold := "Day 1   金 120"
var active_nav := "home"   # フッターでハイライトする現在地（ホーム画面では home）

var sim = null   # KuroSim 参照（main.gd が bind() で渡す）。仕込みカードの実データ用
var _t := 0.0
var _hits: Array = []
var _ripples: Array = []   # タップ波紋（Kit.ripples）
# ── フィードバック（クッキークリッカーの原則：動いた値は必ず画面が言う）──
var _fx: Dictionary = {}   # 数値カウントアップの台帳（Kit.num）
var _floats: Array = []    # 差分フロート（+120G が上へ流れて消える）
var _flies: Array = []     # 飛ぶ数値（所持金の出入り）
var _press: Dictionary = {}   # 直近の押下（rect と時刻）＝押下状態の3状態目
var _last_tap := Vector2(360.0, 640.0)
var _gold_pos := Vector2(120.0, 38.0)
var _banter_t   := 0.0
var _banter_q: Array = []
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

# ── 登場（画面遷移に乗る）─────────────────────────────────────────────
# main.gd の暗幕は 0.32s で明ける。こちらはそれに合わせて、上から順に
# 50ms ずつずれて所定の位置へ着く（暗幕が明けた時にはもう動き終わっている）。
const ENTER_STEP := 0.05
const ENTER_DUR := 0.34
var _enter_i := 0
var _xf_now := Vector2.ZERO
var _nav: Dictionary = {}   # フッター選択インジケータの追従台帳（Kit.nav_slide）


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)


func bind(sim_ref) -> void:
	sim = sim_ref
	queue_redraw()


func set_data(d: Dictionary) -> void:
	for k in d:
		if k in self:
			set(k, d[k])
	# 外部から line が差し込まれたら話者をリセットしてバンタインターバルも再起動
	if d.has("line") and not d.has("speaker"):
		speaker = "店主"
	_banter_t = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _last_event != "" and _t - _last_event_t > LAST_EVENT_SEC:
		_last_event = ""
	_banter_t += delta
	var interval := EXCHANGE_STEP if not _banter_q.is_empty() else BANTER_INTERVAL
	if _banter_t >= interval:
		_banter_t = 0.0
		_advance_banter()
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
			_last_tap = p
			_press = {"rect": h["rect"], "t0": _t}   # 押した場所が一瞬光る
			action_pressed.emit(String(h["id"]))
			accept_event()
			return


func _hit(rect: Rect2, id: String) -> void:
	_hits.append({"rect": rect, "id": id})


## 数値を1つ描く：カウントアップ＋変化した瞬間の拡大＋差分フロート。
## 値は必ず sim から来たものを渡す（UI 側で式を作り直さない）。
func _num(font: Font, pos: Vector2, key: String, v: float, size: int, col: Color,
		gain := GOLD, drop := DS.DANGER) -> float:
	var n: Dictionary = Kit.num(_fx, key, v, _t)
	var s := "%d" % int(round(float(n["v"])))
	Kit.num_draw(self, font, pos, s, size, col, float(n["pop"]))
	var d := float(n["d"])
	if absf(d) >= 1.0:
		Kit.float_add(_floats, Vector2(pos.x, pos.y - size * 0.7),
				"%s%d" % ["+" if d > 0.0 else "-", int(absf(round(d)))],
				gain if d > 0.0 else drop, _t)
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## 数値に添える単位（小さく・灰）。戻り値は幅。
func _unit(font: Font, x: float, y: float, s: String) -> float:
	_txt(font, Vector2(x, y), s, DS.T_MICRO, TEXT_DIM)
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, DS.T_MICRO).x


## 切断ペナルティが「無かった場合」の見込みを sim 自身に計算させる。
## UI 側で 0.6 を割り戻すと式が二重管理になるので、フラグを一瞬倒して読む。
func _forecast_base() -> Dictionary:
	sim.state["crowd_penalty"] = false
	var b: Dictionary = sim.forecast_night()
	sim.state["crowd_penalty"] = true
	return b


## ホームのVN窓にバンタ（掛け合い/独り言）を1行進める。
## _banter_q が空なら新しいセリフ/掛け合いをピック。
func _advance_banter() -> void:
	if not _banter_q.is_empty():
		var ln: Array = _banter_q.pop_front()
		var gid := String(ln[0])
		speaker = String((KuroData.GIRLS.get(gid, {}) as Dictionary).get("name", gid))
		line = String(ln[1])
		_note_said(gid, line)
		return
	# 30% 確率で掛け合い、70% で独り言
	if _banter_rng.randf() < 0.3:
		var ex := Banter.pick_exchange(HOME_CAST, _banter_rng, _banter_recent)
		if not ex.is_empty():
			# Array(x) は参照をそのまま返すので duplicate 必須
			# （const の掛け合いデータに pop_front すると Nil が返り続ける）
			_banter_q = (ex["lines"] as Array).duplicate()
			_advance_banter()
			return
	var pick := Banter.pick("idle", HOME_CAST, _banter_rng, _banter_recent, _ctx())
	if pick.is_empty():
		return
	var gid := String(pick["girl"])
	speaker = String((KuroData.GIRLS.get(gid, {}) as Dictionary).get("name", gid))
	line = String(pick["text"])
	_note_said(gid, line)


## しゃべった本文を直近履歴へ積む（新しいものが先頭）。
func _note_said(gid: String, text: String) -> void:
	_banter_recent.push_front({"girl": gid, "text": text})
	while _banter_recent.size() > BANTER_RECENT_MAX:
		_banter_recent.pop_back()


# ── モーションの下ごしらえ（原点の平行移動だけで動かす）──────────────────
# 動かすのは見た目だけ。_hit() に積む当たり矩形は最終位置のまま置く
# ＝登場アニメーションの最中にタップしても、指の下の物が必ず反応する。

func _set_xf(v: Vector2) -> void:
	_xf_now = v
	Kit.set_xf(self, v)


## 画面の要素を1つ「遅らせて」出す。上から順に呼ぶ＝ENTER_STEP ずつ連鎖する。
func _stag() -> void:
	var i := _enter_i
	_enter_i += 1
	if _t >= ENTER_DUR + ENTER_STEP * i:
		_set_xf(Vector2.ZERO)
		return
	var k := Kit.stag(_t, i, ENTER_STEP, ENTER_DUR)
	_set_xf(Vector2(0.0, (1.0 - k) * 30.0))


## 押されている矩形なら、いま沈んでいる量（px）。離すと 0 を通り越して戻る。
func _sink(r: Rect2) -> Vector2:
	if _press.is_empty():
		return Vector2.ZERO
	var pr: Rect2 = _press["rect"]
	if not pr.position.is_equal_approx(r.position) or not pr.size.is_equal_approx(r.size):
		return Vector2.ZERO
	var s := Kit.press_sink(_t - float(_press["t0"]))
	return Vector2.ZERO if is_zero_approx(s) else Vector2(0.0, s)


func _begin_sink(r: Rect2) -> void:
	var s := _sink(r)
	if s != Vector2.ZERO:
		Kit.set_xf(self, _xf_now + s)


func _end_sink() -> void:
	Kit.set_xf(self, _xf_now)


## 面はすべて斜めカット（Kit.slab_panel）。角丸は使わない＝経営パネルと同じ作法。
func _panel(rect: Rect2, bg: Color, border: Color, bw := 1.5) -> void:
	Kit.slab_panel(self, rect, bg, border, -1.0, bw)


func _txt(font: Font, pos: Vector2, s: String, size: int, col: Color, ha := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string_outline(font, pos, s, ha, w, size, 3, Color(0.02, 0.02, 0.04, 0.9))
	draw_string(font, pos, s, ha, w, size, col)


func _tw(font: Font, s: String, size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## トップバーの入口チップ。x から置いて、次の x を返す（斜めの板＋押し込み）。
func _icon(font: Font, x: float, label: String, col: Color, id: String) -> float:
	var w := _tw(font, label, DS.T_BODY) + 28.0
	var rect := Rect2(x, 22.0, w, 40.0)
	_begin_sink(rect)
	_panel(rect, Color(col.r * 0.16, col.g * 0.14, col.b * 0.18, 0.92), Color(col.r, col.g, col.b, 0.7))
	_txt(font, Vector2(x + (w - _tw(font, label, DS.T_BODY)) * 0.5 + 3.0, 48.0), label, DS.T_BODY, TEXT)
	_end_sink()
	_hit(rect, id)
	return x + w + DS.SP_2


func _draw() -> void:
	var sz := size
	var font := get_theme_default_font()
	_hits.clear()
	_enter_i = 0
	_set_xf(Vector2.ZERO)   # 拡大描画が戻る先を自分の座標系に固定する

	# ===== トップバー（黒い帯＋斜めの地紋。経営シートのヘッダと同じ作法） =====
	_stag()
	var tb := Rect2(0, 0, sz.x, TOPBAR_H)
	draw_rect(tb, Color(DS.INK.r, DS.INK.g, DS.INK.b, 0.94))
	Kit.hatch(self, tb, Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.07), 26.0, 9.0)
	draw_rect(Rect2(0, TOPBAR_H - 3.0, sz.x, 3.0), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.85))
	var bx := float(M)
	bx = _icon(font, bx, "≡", PINK, "menu")
	bx = _icon(font, bx, "報", GOLD, "bell")
	bx = _icon(font, bx, "設定", CYAN, "settings")
	_icon(font, bx, "猫", PINK, "cat")
	# HUD は経営シートのヘッダと同じ位置・同じ書式（帯の下半分に右詰め）
	_topbar_wallet(font, Rect2(0, TOPBAR_H * 0.5, sz.x, TOPBAR_H * 0.5))

	_stag()
	# ===== キリコの依頼（長期目標。常にそこにある小さな面） =====
	_quest_card(font, sz)

	_stag()
	# ===== 探索入口ポータル（右端・縦書き＋紫の渦） =====
	var pc := Vector2(sz.x - 56, sz.y * 0.47)
	_hit(Rect2(pc.x - 52, pc.y - 56, 104, 170), "depart")
	# うっすら枠
	_panel(Rect2(pc.x - 50, pc.y - 54, 100, 168), Color(0.05, 0.03, 0.10, 0.45), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.5))
	var pr := 38.0 + 3.0 * sin(_t * 2.2)
	draw_circle(pc, pr + 8, Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.12))
	draw_arc(pc, pr, _t * 1.6, _t * 1.6 + TAU * 0.78, 36, PURPLE, 3.0)
	draw_arc(pc, pr * 0.6, -_t * 2.2, -_t * 2.2 + TAU * 0.62, 28, PINK, 2.5)
	draw_circle(pc, pr * 0.34, Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.85))
	# 縦書き「仕入れへ」（深層へ食材を獲りに行く＝仕入れ）
	var vy := pc.y + pr + 16.0
	for ch in "仕入れへ":
		_txt(font, Vector2(pc.x - 9, vy), ch, DS.T_BODY, PINK)
		vy += 22.0

	_stag()
	# ===== ポモドーロ集中ボタン（主役CTA・VN窓の上） =====
	var vh := 100.0
	var vy0 := sz.y - STRIP_H - vh - DS.SP_2
	_prep_card(font, sz, vy0 - 70 - DS.SP_2)   # 朝の仕込みカード（CTAの直上）
	_stag()                               # CTA は仕込みカードより一拍あとに着く
	var cta := Rect2(sz.x * 0.5 - 180, vy0 - 70, 360, 56)
	_hit(cta, "pomodoro")
	# 待機中の生気はこの1箇所だけ。常時揺れる sin ではなく心拍（静か→短い二拍）
	var pulse := Kit.heartbeat(_t)
	_begin_sink(cta)
	Kit.cta(self, cta, Color(PINK.r * 0.22, PINK.g * 0.16, PINK.b * 0.24, 0.96), PINK, pulse)
	var ct := "▶  集中する（25分）"
	_txt(font, Vector2(cta.position.x + (cta.size.x - _tw(font, ct, DS.T_SUB)) * 0.5 + 4.0,
			cta.position.y + 38), ct, DS.T_SUB, TEXT)
	_end_sink()

	_stag()
	# ===== VN セリフ窓（フィールド帯の上） =====
	_panel(Rect2(M, vy0, sz.x - M * 2, vh), Color(0.04, 0.04, 0.08, 0.88), Color(PINK.r, PINK.g, PINK.b, 0.5))
	# 名前タグ（斜めの板・幅は名前に合わせる）
	var tag := Rect2(M + DS.SP_3, vy0 - 15.0, _tw(font, speaker, DS.T_BODY) + 32.0, 30.0)
	_panel(tag, Color(0.10, 0.05, 0.10, 0.96), Color(PINK.r, PINK.g, PINK.b, 0.8))
	_txt(font, Vector2(tag.position.x + 16.0, vy0 + 7), speaker, DS.T_BODY, PINK)
	# ボイスアイコン
	draw_circle(Vector2(tag.end.x + 14.0, vy0), 8, Color(CYAN.r, CYAN.g, CYAN.b, 0.85))
	# 本文
	_txt(font, Vector2(M + 22, vy0 + 52), line, DS.T_BODY, TEXT, HORIZONTAL_ALIGNMENT_LEFT, sz.x - M * 2 - 40)
	# 送りインジケータ
	if fmod(_t, 1.0) < 0.6:
		_txt(font, Vector2(sz.x - M - 28, vy0 + vh - 14), "▼", DS.T_MICRO, PINK)

	# ===== 最下部：フィールドへの導線 =====
	# 以前はここに 168px の HD-2D フィールド帯（FieldStrip）を敷いていたが、
	# 実機では一度も合成されず「黒い帯」のままだったので高さを詰めた。
	# フィールドへは店先の探索ポータル（右）から入る。
	var fy := sz.y - STRIP_H
	draw_rect(Rect2(0, fy, sz.x, 2), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.6))

	_stag()
	# ===== 最下部：各主要機能へのフッターナビ =====
	_footer(font, sz)
	_set_xf(Vector2.ZERO)
	# ===== 触った結果のフィードバック（押下→波紋→数値の増減） =====
	if not _press.is_empty():
		var pk := 1.0 - (_t - float(_press["t0"])) / Kit.PRESS_LIFE
		if pk <= 0.0:
			_press = {}
		else:
			Kit.press(self, _press["rect"], PINK, pk)
	Kit.ripples(self, _ripples, _t)
	Kit.flies(self, font, _flies, _t)
	Kit.floats(self, font, _floats, _t)


## トップバーの財布。書式・色・ケースは DS.draw_hud が1箇所で決める
## （経営シートのヘッダとまったく同じ物が出る）。
func _topbar_wallet(font: Font, bar: Rect2) -> void:
	if sim == null:
		_txt(font, Vector2(bar.end.x - M - _tw(font, day_gold, DS.T_BODY),
				bar.position.y + bar.size.y * 0.5 + 8.0), day_gold, DS.T_BODY, GOLD)
		return
	_gold_pos = DS.draw_hud(self, font, bar, sim.state, _fx, _t)
	var g := float(int(sim.state["gold"]))
	# 所持金の出入りは「飛ぶ数値」で財布と操作点をつなぐ
	var seen := float(_fx.get("gold_seen", g))
	if absf(g - seen) >= 1.0:
		var d := g - seen
		if d > 0.0:
			Kit.fly_add(_flies, _last_tap, _gold_pos, "+%dG" % int(d), GOLD, _t)
		else:
			Kit.fly_add(_flies, _gold_pos, _last_tap, "-%dG" % int(-d), DS.DANGER, _t)
	_fx["gold_seen"] = g


## キリコの依頼（STORY.md 5節＝店モードに置く長期目標）。
## ホームは世界を見せる画面なので、3Dディオラマ（看板・カウンター・皆の立ち位置）と
## 既存の仕込みカード／CTA／VN帯には触れない。トップバー直下・左肩の空だけを借りる。
## 進捗は記憶の収集率だけで示し、UI 側で物語を足さない。タップで記憶タブへ。
func _quest_card(font: Font, sz: Vector2) -> void:
	if sim == null:
		return
	var seen: Array = sim.state.get("events_seen", [])
	if not ("intro_kiriko" in seen):
		return   # まだ頼まれていない夜には出さない（依頼より先に依頼板は出さない）
	var total: int = KuroMemories.MEMORIES.size()
	var got := (sim.state["memories"] as Array).size()
	var done: bool = "story_finale" in seen
	var r := Rect2(M, TOPBAR_H + DS.SP_3, 348.0, 86.0)
	_begin_sink(r)
	_panel(r, Color(0.04, 0.03, 0.08, 0.86), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.55))
	_txt(font, Vector2(r.position.x + 16.0, r.position.y + 26.0), "キリコの依頼", DS.T_MICRO, PURPLE)
	var st := "応えた" if done else "まだ応えられない"
	_txt(font, Vector2(r.end.x - _tw(font, st, DS.T_MICRO) - 16.0, r.position.y + 26.0), st,
			DS.T_MICRO, DS.SUCCESS if done else TEXT_DIM)
	_txt(font, Vector2(r.position.x + 16.0, r.position.y + 52.0), "「私を、殺してほしいの」", DS.T_BODY, TEXT)
	# 進捗＝記憶の収集率。数字とバーだけ（言葉で説明を足さない）
	var ly := r.end.y - 14.0
	_txt(font, Vector2(r.position.x + 16.0, ly), "記憶", DS.T_MICRO, TEXT_DIM)
	var nx := r.position.x + 16.0 + _tw(font, "記憶", DS.T_MICRO) + DS.SP_2
	nx += _num(font, Vector2(nx, ly), "q_mem", float(got), DS.T_BODY, PURPLE) + 2.0
	nx += _unit(font, nx, ly, "/%d" % total) + DS.SP_3
	Kit.bar(self, Rect2(nx, ly - 12.0, maxf(r.end.x - 46.0 - nx, 24.0), 12.0),
			float(got) / float(total), PURPLE)
	_txt(font, Vector2(r.end.x - 30.0, ly), "▸", DS.T_BODY, PURPLE)
	_end_sink()
	_hit(r, "memory")   # 当たりは最終位置のまま（登場アニメ中でも指の下が反応する）


## 朝の仕込みカード：予報・店番・扉・献立と「今夜の見込み」を出撃前に見せる。
## 店番と扉はその場でタップ変更（3タップの儀式）、献立は経営パネルへ。
## デイブザダイバーの「今日の獲物が今夜の品書き」——因果を潜る前に提示する。
func _prep_card(font: Font, sz: Vector2, y_bottom: float) -> void:
	if sim == null:
		return
	var pen: bool = bool(sim.state.get("crowd_penalty", false))
	var h := 132.0 if pen else 100.0
	var r := Rect2(M, y_bottom - h, sz.x - M * 2, h)
	var edge := DS.DANGER if pen else GOLD
	_begin_sink(r)
	_panel(r, Color(0.04, 0.04, 0.08, 0.88), Color(edge.r, edge.g, edge.b, 0.55 if pen else 0.4))
	_end_sink()
	var fc: Dictionary = sim.forecast_night()
	var m: Dictionary = sim.state["morning"]
	# 見出し＋予報（右上）
	_txt(font, Vector2(r.position.x + 20, r.position.y + 24), "今日の仕込み", DS.T_BODY, GOLD)
	var fst := "予報『%s』" % String(fc["forecast"])
	var fw := _tw(font, fst, DS.T_BODY)
	_txt(font, Vector2(r.end.x - fw - 20, r.position.y + 24), fst, DS.T_BODY, CYAN)
	# ペナルティ帯：昨夜の切断が今日の客足をいくら削ったかを、赤い板で名指しする
	if pen:
		var base: Dictionary = _forecast_base()
		var pr := Rect2(r.position.x + DS.SP_3, r.position.y + 32.0, r.size.x - DS.SP_3 * 2, 30.0)
		Kit.slab(self, pr, DS.DANGER, DS.skew(pr.size.y))
		var ink := DS.on(DS.DANGER)
		draw_string(font, Vector2(pr.position.x + 16.0, pr.position.y + 21.0),
				"▼ 昨夜の切断 ─ 客足 -40%", HORIZONTAL_ALIGNMENT_LEFT, -1, DS.T_BODY, ink)
		# 「8人 → 5人」。元の値は取り消し線で残す（黙って減らさない）
		var bx := pr.end.x - 122.0
		bx += Kit.struck(self, font, Vector2(bx, pr.position.y + 21.0),
				"%d人" % int(base.get("customers", fc["customers"])), DS.T_BODY,
				Color(ink.r, ink.g, ink.b, 0.62), ink, false) + 8.0
		draw_string(font, Vector2(bx, pr.position.y + 21.0), "→", HORIZONTAL_ALIGNMENT_LEFT, -1, DS.T_BODY, ink)
		bx += _tw(font, "→", DS.T_BODY) + 8.0
		draw_string(font, Vector2(bx, pr.position.y + 21.0), "%d人" % int(fc["customers"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, DS.T_BODY, ink)
	# 行1：店番／扉（タップで変更）＋献立（タップで経営へ）
	var y1 := r.position.y + (68.0 if pen else 34.0)
	var x := r.position.x + DS.SP_3
	var keeper := String(m["keeper"])
	var kname := String((KuroData.GIRLS.get(keeper, {}) as Dictionary).get("name", keeper))
	x = _chip(font, Vector2(x, y1), "店番 %s ▸" % kname, PINK, "keeper_next")
	var door_open: bool = String(m["door"]) == "open"
	x = _chip(font, Vector2(x, y1), "扉 %s ▸" % ("開ける" if door_open else "見送る"),
			CYAN if door_open else TEXT_DIM, "door")
	var menu: Array = m["menu"]
	x = _chip(font, Vector2(x, y1), "献立 %d品 ▸" % menu.size(), PURPLE, "management")
	# 行2：見込み（客・皿・金）。数字は動いたら必ずカウントし、差分を上へ流す
	var y2 := r.end.y - 16.0
	var nx := r.position.x + 20.0
	_txt(font, Vector2(nx, y2), "見込み", DS.T_MICRO, TEXT_DIM)
	nx += _tw(font, "見込み", DS.T_MICRO) + DS.SP_4
	nx += _num(font, Vector2(nx, y2), "cust", float(int(fc["customers"])), DS.T_BODY,
			DS.DANGER if pen else TEXT) + 2.0
	nx += _unit(font, nx, y2, "人") + DS.SP_3
	nx += _num(font, Vector2(nx, y2), "served", float(int(fc["served"])), DS.T_BODY, TEXT) + 2.0
	nx += _unit(font, nx, y2, "皿") + DS.SP_3
	# 見出しの金額は「手元に残る額」＝純益。ここを売上にすると、経営パネルの
	# 三行精算（純益）と違う数字を同じ夜について約束することになる。
	nx += _unit(font, nx, y2, "手取り") + DS.SP_2
	nx += _num(font, Vector2(nx, y2), "gain", float(int(sim.night_profit(fc))), DS.T_SUB, GOLD) + DS.SP_2
	nx += _unit(font, nx, y2, "G")
	if int(fc["short"]) > 0:
		var outs: Array = fc["out"]
		var lack := ""
		for i in outs.size():
			lack += ("・" if i > 0 else "") + String(KuroData.ING_NAMES.get(outs[i], outs[i]))
		# 足りない素材が獲れる、開放済みで一番深い階を推す（バイオーム＝素材）
		var want := String(outs[0])
		var goto_fl := -1
		var frontier: int = sim.stage_cleared(int(sim.state.get("difficulty", 0))) + 1
		for f in range(frontier, -1, -1):
			if String(KuroData.BIOMES[f % KuroData.BIOMES.size()]["ing"]) == want:
				goto_fl = f
				break
		var warn := "⚠ %s切れ（%d皿売り逃し）" % [lack, int(fc["short"])]
		if goto_fl >= 0:
			warn += " → %s へ ▸" % KuroData.stage_label(goto_fl)
		var ww := _tw(font, warn, DS.T_MICRO)
		var wr := Rect2(r.end.x - ww - 26, y2 - 20, ww + DS.SP_4, 28)
		if goto_fl >= 0:
			_hit(wr, "restock:%d" % goto_fl)   # タップ＝その階を選択してマップへ
		_txt(font, Vector2(Kit.sunk(wr, _press, _t).position.x + DS.SP_2, y2), warn, DS.T_MICRO, DS.DANGER)
	_hit(r, "prep_card")   # 余白タップは経営パネルへ（上の個別チップが優先）


## 仕込みカードの小チップを1つ描き、次のX座標を返す。
## 押されている間はチップごと数px沈む（押し込み→戻りのオーバーシュートは Kit.press_sink）。
func _chip(font: Font, pos: Vector2, label: String, col: Color, id: String) -> float:
	var w := _tw(font, label, DS.T_BODY) + 26.0
	var cr := Rect2(pos.x, pos.y, w, 34)
	_hit(cr, id)
	_begin_sink(cr)
	_panel(cr, Color(col.r * 0.16, col.g * 0.14, col.b * 0.18, 0.92), Color(col.r, col.g, col.b, 0.65), 1.2)
	_txt(font, Vector2(pos.x + 13, pos.y + 24), label, DS.T_BODY, col.lerp(TEXT, 0.35))
	_end_sink()
	return pos.x + w + DS.SP_2


## 各主要機能へつながるフッターナビバー（旧版のボトムタブを踏襲）。
## 等幅セルにアイコン＋ラベルを並べ、タップで action_pressed(id) を発火。
func _footer(font: Font, sz: Vector2) -> void:
	var fy := sz.y - FOOTER_H
	draw_rect(Rect2(0, fy, sz.x, FOOTER_H), Color(0.03, 0.03, 0.06, 0.95))
	draw_rect(Rect2(0, fy, sz.x, 1.5), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.55))
	var n := NAV.size()
	var cw := sz.x / float(n)
	# 選択インジケータは瞬間移動させない。目標セルへ滑って、少し行き過ぎて座る
	# （メニュー側のフッターと同じ台帳・同じ曲線を使う）。
	var ai := 0
	for i in n:
		if String((NAV[i] as Dictionary)["id"]) == active_nav:
			ai = i
			break
	var acol: Color = (NAV[ai] as Dictionary)["col"]
	var slide: Dictionary = Kit.nav_slide(_nav, cw * ai, acol, _t)
	var ix := float(slide["x"])
	var icol: Color = slide["col"]
	var stretch := (1.0 - Kit.out_cubic(float(slide["k"]))) * cw * 0.34
	draw_rect(Rect2(ix, fy, cw, FOOTER_H), Color(icol.r, icol.g, icol.b, 0.10))
	draw_rect(Rect2(ix - stretch * 0.5, fy, cw + stretch, 2.0), icol)
	Kit.spot(self, Vector2(ix + cw * 0.5, fy + FOOTER_H * 0.55), cw * 0.72, icol, 0.22)
	for i in n:
		var e: Dictionary = NAV[i]
		var x0 := cw * i
		var id := String(e["id"])
		_hit(Rect2(x0, fy, cw, FOOTER_H), id)
		var col: Color = e["col"]
		# 文字色は「インジケータがどれだけ自分の上に来たか」で混ぜる＝色も一緒に滑る
		var near := clampf(1.0 - absf(ix - x0) / cw, 0.0, 1.0)
		var gcol := Color(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.9).lerp(col, Kit.out_cubic(near))
		var cx := x0 + cw * 0.5
		var glyph := String(e["icon"])
		# 字の段・位置ともメニューシートのフッターと完全に同じにする（同じ物は同じ形）
		_txt(font, Vector2(cx - _tw(font, glyph, DS.T_SUB) * 0.5, fy + 30.0 - near * 2.0), glyph, DS.T_SUB, gcol)
		var label := String(e["label"])
		_txt(font, Vector2(cx - _tw(font, label, DS.T_MICRO) * 0.5, fy + 50), label, DS.T_MICRO, gcol)


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
func _find_sim():
	var n: Node = self
	while n != null:
		if n.get("sim") != null:
			return n.get("sim")
		n = n.get_parent()
	return null
