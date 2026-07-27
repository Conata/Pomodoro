class_name MenuOverlay
extends Control
## 各主要機能（メンバー／市場／経営／工房）のメニュー画面。
## フッターナビでパネルを切替え、ホームと同じ世界観の 2D UI を _draw で描く。
## KuroSim を参照して描画し、状態変更はすべて action_pressed(id) で main.gd へ委譲する
## （id にパラメータを ":" 区切りで載せる。例 "buy:0" / "renov:gold1" / "keeper:muu"）。

signal action_pressed(id: String)

const PINK := Color(1.0, 0.36, 0.72)
const CYAN := Color(0.35, 0.92, 1.0)
const PURPLE := Color(0.66, 0.4, 1.0)
const GOLD := DS.GOLD          # 状態色・獲得
const GREEN := DS.SUCCESS      # 状態色・成功
const TEXT := Color(0.96, 0.95, 0.98)
const TEXT_DIM := Color(0.75, 0.76, 0.84)
const BG := Color(0.05, 0.05, 0.08, 1.0)

const HEADER_H := 84.0
const FOOTER_H := 58.0
# 外側マージンは全画面で 16（DS.SP_4）。12/14/20 の場当たりは置かない。
const M := DS.SP_4

# フッターナビ（home_overlay と揃える）。
const NAV := [
	{"id": "home",       "icon": "家", "label": "ホーム",   "col": CYAN},
	{"id": "member",     "icon": "仲", "label": "メンバー", "col": PINK},
	{"id": "market",     "icon": "市", "label": "市場",     "col": GOLD},
	{"id": "management", "icon": "店", "label": "経営",     "col": PURPLE},
	{"id": "workshop",   "icon": "工", "label": "工房",     "col": CYAN},
]
const PANEL_TITLES := {
	"map": "深層マップ — ステージ選択",
	"member": "メンバー — 編成・育成",
	"market": "市場 — 闇市と交易船",
	"management": "経営 — 今夜の仕込み",
	"renov": "経営 — 改装ツリー",
	"workshop": "工房 — Cube 装備加工",
}
# パネル毎の背景アートとアクセント（世界観の奥行き。Kit.backdrop で敷く）
const PANEL_BG_ART := {
	"map": "res://assets/generated/scene/dungeon.png",
	"member": "res://assets/generated/scene/restaurant.png",
	"market": "res://assets/generated/scene/street.png",
	# management / renov は背景アートを持たない。shop_interior.png は看板と垂れ幕に
	# 実在しない漢字（「秸乄たっリ」等）が描かれており、日本語話者には一目で偽物と分かる。
	# 素材を等倍で描き直すまでは無地の地の方が良い（この2画面はUIで埋まっている）。
	"workshop": "res://assets/generated/bg/interior.png",
}
const PANEL_ACCENT := {
	"map": CYAN, "member": PINK, "market": GOLD, "management": PURPLE, "renov": PURPLE, "workshop": CYAN,
}

var sim = null                 # KuroSim 参照（main.gd が bind() で渡す）
var panel := "member"          # 表示中のパネル
var _sel_girl := "mil"         # メンバー画面で選択中の子
var _work_view := "storage"     # 工房: storage / bag
var _work_item_id := -1         # 工房で選択中の装備ID
var _work_gem := "em_core"      # 工房で選択中のソケット素材
var _toast := ""
var _toast_t := 0.0
var _panel_t := 9.0            # パネル切替からの経過秒（登場トランジション用）
var _t := 0.0
var _hits: Array = []
var _ripples: Array = []   # タップ波紋（Kit.ripples）
var _tex: Dictionary = {}      # アイコン/立ち絵テクスチャのキャッシュ（path -> Texture2D|null）
# ── フィードバック（クッキークリッカーの原則：動いた値は必ず画面が言う）──
var _fx: Dictionary = {}       # 数値カウントアップの台帳（Kit.num）
var _floats: Array = []        # 差分フロート（+18G が上へ流れて消える）
var _flies: Array = []         # 飛ぶ数値（所持金の出入り＝支払いが目に見える）
var _press: Dictionary = {}    # 直近の押下（rect と時刻）＝押下状態の3状態目
var _last_tap := Vector2(360.0, 640.0)
var _gold_pos := Vector2(560.0, 68.0)
var _chg := ""                 # 直近の仕込み操作（「店番 → ユズキ」等）
var _chg_t := -99.0
var _chg_d := 0.0              # その操作で純益がいくら動いたか
var _burst: Dictionary = {}    # 解放バースト（改装ノードid -> 時刻）
var _own_renov: Dictionary = {}   # 改装の所持状態キャッシュ（解放の瞬間を捕まえる）
var _stat_cache: Dictionary = {}  # 各員の攻/HP（装備の付け替え量を出すため）

# ── シートの開閉（visible の即時切替を、モーションのある開閉に置き換える）──
# main.gd は `_menu_overlay.visible = true/false` で畳む。そこへ手を入れずに動きを付ける
# ため、可視性の通知を捕まえて自分で開閉を演じる：
#   開く   奥から迫り上がる。ヘッダ→中身→フッターの順に 45ms ずつずれる（ease-out）
#   閉じる 逆再生しない。全部まとめて一息で落とす（開く時間の半分）
# 閉じ始めた瞬間に入力は下へ通す＝演出でユーザーを待たせない。
const OPEN_DUR := 0.30
const CLOSE_DUR := 0.15
const ENTER_STEP := 0.05   # パネル内スタガーの1段（50ms）
const ENTER_DUR := 0.32    # 1要素が立ち上がる時間
const ENTER_ROWS := 6      # ワイプが想定する段数

var _sheet := "closed"     # closed / opening / open / closing
var _sheet_t := 9.0
var _vis_guard := false    # visible を自分で書き換える間の再入防止
var _xf_now := Vector2.ZERO   # いまの描画原点（押下の沈み込みが基準にする）
var _sink_ofs := Vector2.ZERO # いま掛かっている押下の沈み込み（入れ子の復元用）
var _c_ofs := Vector2.ZERO    # 中身レイヤのオフセット（シート開閉ぶん）
var _enter_i := 0             # 描画中に消費するスタガー番号
var _nav: Dictionary = {}     # フッター選択インジケータの追従台帳（Kit.nav_slide）
var _selbar: Dictionary = {}  # メンバー6人チップの選択帯の追従台帳（同上）
var _selg_t := -99.0          # メンバー詳細カードの切替時刻（差し替えにモーションを付ける）
var _selg_dir := 1.0          # その切替がどちらへ動いたか（＋右／−左）
const SELG_DUR := 0.30        # 詳細カードが滑り込む時間
var _toast_age := 9.0         # トースト表示開始からの経過秒（出入りのモーション用）


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)


## main.gd の visible 切替を「開閉モーション」に翻訳する。
## 畳まれた（visible=false）ら一度だけ差し戻し、閉じるモーションを演じてから本当に消す。
func _notification(what: int) -> void:
	if what != NOTIFICATION_VISIBILITY_CHANGED or _vis_guard or not is_inside_tree():
		return
	if visible:
		_sheet = "opening"
		_sheet_t = 0.0
		_toast_age = 9.0
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_process(true)
	elif _sheet != "closed":
		_sheet = "closing"
		_sheet_t = 0.0
		_vis_guard = true
		visible = true
		_vis_guard = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE   # 閉じ始めたら操作は下の世界へ


func _finish_close() -> void:
	_sheet = "closed"
	modulate.a = 1.0
	_vis_guard = true
	visible = false
	_vis_guard = false
	mouse_filter = Control.MOUSE_FILTER_STOP


func bind(sim_ref) -> void:
	sim = sim_ref
	queue_redraw()


func set_panel(id: String) -> void:
	if _sheet == "closing":
		# 閉じ始めた直後に開き直された。visible は既に true なので可視性の通知は来ない
		# ＝ここで拾わないと、開いたそばから畳まれる。
		_sheet = "opening"
		_sheet_t = 0.0
		mouse_filter = Control.MOUSE_FILTER_STOP
	if panel != id:
		_panel_t = 0.0
	panel = id
	queue_redraw()


func set_toast(s: String) -> void:
	_toast = s
	_toast_t = 2.6
	_toast_age = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return   # 常駐シート：閉じている間は再描画を止める
	_t += delta
	_panel_t += delta
	_sheet_t += delta
	_toast_age += delta
	if _toast_t > 0.0:
		_toast_t -= delta
	# シートの淡入淡出（部位ごとのずれは _draw 側の平行移動が受け持つ）
	match _sheet:
		"opening":
			modulate.a = Kit.out_quart(_sheet_t / 0.15)
			if _sheet_t >= OPEN_DUR:
				_sheet = "open"
				modulate.a = 1.0
		"closing":
			modulate.a = 1.0 - Kit.in_cubic(_sheet_t / CLOSE_DUR)
			if _sheet_t >= CLOSE_DUR:
				_finish_close()
				return
	queue_redraw()


# ── 入力・描画ヘルパー ────────────────────────────────────────────────────────

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
			var id := String(h["id"])
			_note_change(id)
			if id.begins_with("_"):
				_local(id)            # 純UI操作（選択など）はその場で処理
			else:
				action_pressed.emit(id)
			accept_event()
			return


## 画面内だけで完結する操作（選択ハイライトなど）。
func _local(id: String) -> void:
	if id.begins_with("_selg:"):
		var nxt := id.substr(6)
		if nxt != _sel_girl:
			# 詳細カードは瞬間差し替えしない。選択が動いた向きから滑り込ませる
			var ids: Array = KuroData.GIRL_ORDER
			_selg_dir = 1.0 if ids.find(nxt) >= ids.find(_sel_girl) else -1.0
			_selg_t = _t
		_sel_girl = nxt
		queue_redraw()
	elif id.begins_with("_panel:"):
		if panel != id.substr(7):
			_panel_t = 0.0
		panel = id.substr(7)
		queue_redraw()
	elif id.begins_with("_work:"):
		_work_view = id.substr(6)
		_work_item_id = -1
		queue_redraw()
	elif id.begins_with("_selitem:"):
		_work_item_id = int(id.substr(9))
		queue_redraw()
	elif id.begins_with("_selgem:"):
		_work_gem = id.substr(8)
		queue_redraw()


func _hit(rect: Rect2, id: String) -> void:
	_hits.append({"rect": rect, "id": id})


## 朝の仕込み操作を覚えておき、「何を変えたら純益がいくら動いたか」を言えるようにする。
## 実際の差分は sim の見込みから読む（ここでは名前だけ控える）。
func _note_change(id: String) -> void:
	var parts := id.split(":")
	match parts[0]:
		"keeper":
			if parts.size() > 1:
				_chg = "店番 → %s" % String(KuroData.GIRLS[parts[1]]["name"])
		"door":
			_chg = "扉 → %s" % ("見送る" if String(sim.state["morning"]["door"]) == "open" else "踏み込む")
		"menu":
			if parts.size() > 1:
				_chg = "献立 → %s" % String(KuroData.RECIPES[parts[1]]["name"])
		_:
			return
	_chg_t = _t
	_chg_d = 0.0


## 数値を1つ描く：カウントアップ＋変化した瞬間の拡大＋差分フロート。
## 値は必ず sim から来たものを渡す（UI 側で式を作り直さない）。戻り値は描いた幅。
func _num(font: Font, pos: Vector2, key: String, v: float, size: int, col: Color,
		gain := DS.SUCCESS, drop := DS.DANGER, suffix := "", float_it := true) -> float:
	var n: Dictionary = Kit.num(_fx, key, v, _t)
	var s := "%d" % int(round(float(n["v"])))
	Kit.num_draw(self, font, pos, s, size, col, float(n["pop"]))
	var w := _tw(font, s, size)
	var d := float(n["d"])
	# フロートは数値の右肩から上がる（上の行の文字に被せない）
	if float_it and absf(d) >= 1.0:
		Kit.float_add(_floats, Vector2(pos.x + w + 8.0, pos.y - 4.0),
				"%s%d%s" % ["+" if d > 0.0 else "-", int(absf(round(d))), suffix],
				gain if d > 0.0 else drop, _t)
	return w


# ── 見込みのキャッシュ ────────────────────────────────────────────────────
# forecast_night() は献立を全皿ぶん回すので軽くはない。ところが描画は即時モードで、
# 店番6人ぶんの比較（_keeper_profits）と罰の前後（_forecast_base）を合わせて
# **毎フレーム最大9回**呼んでいた。入力が変わらない限り結果は同じなので、
# 入力から署名を作って変化したときだけ計算し直す。
# 署名にはプレイヤーの操作で動くものを入れる（店番・扉・献立・予報・日・所持金・
# 在庫・切断フラグ・連続日数）。改装や好感度は所持金か日が必ず動くので拾える。
var _fc_sig := ""
var _fc_cache: Dictionary = {}
var _fc_base_cache: Dictionary = {}
var _kp_cache: Dictionary = {}


func _fc_signature() -> String:
	var m: Dictionary = sim.state["morning"]
	var st: Dictionary = sim.state["stock"]
	return "%s|%s|%s|%s|%d|%d|%d,%d,%d|%s|%d" % [
		String(m.get("keeper", "")), String(m.get("door", "")),
		",".join(PackedStringArray(m.get("menu", []))),
		String(sim.state.get("forecast", "")),
		int(sim.state.get("day", 0)), int(sim.state.get("gold", 0)),
		int(st.get("dry", 0)), int(st.get("meat", 0)), int(st.get("sea", 0)),
		str(bool(sim.state.get("crowd_penalty", false))),
		int(sim.state.get("streak", 0)),
	]


## 署名が変わっていたらキャッシュを捨てる。各アクセサの先頭で呼ぶ。
func _fc_invalidate() -> void:
	var sig := _fc_signature()
	if sig != _fc_sig:
		_fc_sig = sig
		_fc_cache = {}
		_fc_base_cache = {}
		_kp_cache = {}


## 今夜の見込み（キャッシュ付き）。描画中はこれを使い、sim を直接叩かない。
func _forecast() -> Dictionary:
	_fc_invalidate()
	if _fc_cache.is_empty():
		_fc_cache = sim.forecast_night()
	return _fc_cache


## 切断ペナルティが「無かった場合」の見込みを sim 自身に計算させる。
## UI 側で 0.6 を割り戻すと式が二重管理になるので、フラグを一瞬倒して読む。
func _forecast_base() -> Dictionary:
	_fc_invalidate()
	if not _fc_base_cache.is_empty():
		return _fc_base_cache
	_fc_base_cache = _forecast_base_uncached()
	return _fc_base_cache


func _forecast_base_uncached() -> Dictionary:
	sim.state["crowd_penalty"] = false
	var b: Dictionary = sim.forecast_night()
	sim.state["crowd_penalty"] = true
	return b


## 「その子を店番にしたら今夜の純益はいくらか」を、店番の数だけ sim に計算させる。
## 適性だけでは決まらない（シナジー×献立×予報）ことを、数字の差分で見せるための材料。
func _keeper_profits() -> Dictionary:
	_fc_invalidate()
	if not _kp_cache.is_empty():
		return _kp_cache
	var m: Dictionary = sim.state["morning"]
	var cur := String(m["keeper"])
	var out := {}
	for id in KuroData.GIRL_ORDER:
		m["keeper"] = id
		var f: Dictionary = sim.forecast_night()
		out[id] = int(f["gold"]) - int(f["served"]) * MAT_COST
	m["keeper"] = cur
	_kp_cache = out
	return out


## 全員の攻/HPを見張り、装備の付け替えで変わったら変化量をその場（指の下）に出す。
func _watch_stats() -> void:
	for gid in KuroData.GIRL_ORDER:
		var atk := float(sim.girl_atk(gid))
		var hp := float(sim.girl_maxhp(gid))
		var prev: Array = _stat_cache.get(gid, [])
		_stat_cache[gid] = [atk, hp]
		if prev.is_empty() or _panel_t < 0.6:
			continue
		var da := atk - float(prev[0])
		var dh := hp - float(prev[1])
		if absf(da) < 0.5 and absf(dh) < 0.5:
			continue
		var parts: Array[String] = [String(KuroData.GIRLS[gid]["name"])]
		if absf(da) >= 0.5:
			parts.append("攻%s%d" % ["+" if da > 0.0 else "-", int(absf(da))])
		if absf(dh) >= 0.5:
			parts.append("HP%s%d" % ["+" if dh > 0.0 else "-", int(absf(dh))])
		Kit.float_add(_floats, _last_tap + Vector2(-40.0, -16.0), " ".join(parts),
				DS.SUCCESS if (da + dh) >= 0.0 else DS.DANGER, _t)


## 所持金の出入りを「飛ぶ数値」で財布と操作点の間に飛ばす。
func _watch_gold() -> void:
	var g := float(int(sim.state["gold"]))
	var seen := float(_fx.get("gold_seen", g))
	# 開いた直後（＝閉じている間に動いた分）は飛ばさない。指の位置が古いので嘘になる。
	if _panel_t < 0.6:
		_fx["gold_seen"] = g
		return
	if absf(g - seen) >= 1.0:
		var d := g - seen
		if d > 0.0:
			Kit.fly_add(_flies, _last_tap, _gold_pos, "+%dG" % int(d), GOLD, _t)
		else:
			Kit.fly_add(_flies, _gold_pos, _last_tap, "-%dG" % int(-d), DS.DANGER, _t)
	_fx["gold_seen"] = g


# ── モーションの下ごしらえ（原点の平行移動だけで動かす）──────────────────
# 原則：動かすのは「見た目」だけで、_hit() に積む当たり矩形は最終位置のまま。
# ＝アニメーション中にタップしても、指の下にある物が必ず反応する（待たせない）。

## 描画原点を置き直す（Kit.num_draw の復帰先も同時に更新される）。
func _set_xf(v: Vector2) -> void:
	_xf_now = v
	Kit.set_xf(self, v)


## 中身の要素を1つ「遅らせて」出す。各パネルがセクションの先頭で呼ぶ。
## 呼ぶたびに番号が進む＝上から順に ENTER_STEP ずつ連鎖する（同時に出さない）。
func _stag() -> void:
	var i := _enter_i
	_enter_i += 1
	if _panel_t >= ENTER_DUR + ENTER_STEP * i:
		_set_xf(_c_ofs)
		return
	var k := Kit.stag(_panel_t, i, ENTER_STEP, ENTER_DUR)
	_set_xf(_c_ofs + Vector2(0.0, (1.0 - k) * 34.0))


## 押されている矩形なら、いま沈んでいる量（px）。押した直後に沈み、離すと行き過ぎて戻る。
func _sink(r: Rect2) -> Vector2:
	if _press.is_empty():
		return Vector2.ZERO
	var pr: Rect2 = _press["rect"]
	if not pr.position.is_equal_approx(r.position) or not pr.size.is_equal_approx(r.size):
		return Vector2.ZERO
	var s := Kit.press_sink(_t - float(_press["t0"]))
	return Vector2.ZERO if is_zero_approx(s) else Vector2(0.0, s)


## 押下の沈み込みを、この矩形に属する描画すべてに掛ける。必ず _end_sink() で戻す。
## 入れ子（行の中のボタン）でも壊れないよう、直前のオフセットを返す＝
##     var pv := _begin_sink(r) ... _end_sink(pv)
func _begin_sink(r: Rect2) -> Vector2:
	var prev := _sink_ofs
	var s := _sink(r)
	if s != Vector2.ZERO:
		_sink_ofs = s
		Kit.set_xf(self, _xf_now + s)
	return prev


func _end_sink(prev := Vector2.ZERO) -> void:
	_sink_ofs = prev
	Kit.set_xf(self, _xf_now + prev)


## 面はすべて斜めカット（Kit.slab_panel）。角丸は全画面から外した。
func _panel(rect: Rect2, bg: Color, border: Color, bw := 1.5) -> void:
	Kit.slab_panel(self, rect, bg, border, -1.0, bw)


## 角丸／円が要る箇所だけの逃げ道。斜めカットに寄せた中で、改装ツリーのノードは
## 円であることに意味がある（ツリーの節点は方向を持たない）ので形を残す。
func _round_panel(rect: Rect2, bg: Color, border: Color, radius := 10.0, bw := 1.5) -> void:
	Kit.panel(self, rect, bg, border, radius, bw)


## 文字。ドロップシャドウ（1,1のにじみ）ではなく暗色アウトラインで抜く。
## 反転面の暗色文字（識別色のベタ板の上）にはアウトラインを掛けない＝滲ませない。
func _txt(font: Font, pos: Vector2, s: String, size: int, col: Color, ha := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	if col.r * 0.299 + col.g * 0.587 + col.b * 0.114 > 0.3:
		draw_string_outline(font, pos, s, ha, w, size, 3, Color(0.02, 0.02, 0.04, 0.92))
	draw_string(font, pos, s, ha, w, size, col)


func _tw(font: Font, s: String, size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## アセットをキャッシュ付きで取得（無ければ null）。
func _icon(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]


## アイコンを rect 内にアスペクト維持で描く。存在すれば true（呼び出し側の文字fallback判定用）。
## plated=true で共通の暗い丸皿バックプレートを敷き、不透明な生成アイコンは地色を抜く
## （白地の正方形が画面の最明部になる事故を止める）。
func _draw_icon(path: String, rect: Rect2, modulate := Color(1, 1, 1, 1), plated := false) -> bool:
	var tex := Kit.cutout_tex(path) if plated else _icon(path)
	if tex == null:
		return false
	var ts := tex.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return false
	if plated:
		Kit.plate(self, rect.get_center(), maxf(rect.size.x, rect.size.y) * 0.62,
				Color(modulate.r, modulate.g, modulate.b, 0.5))
	var scale := minf(rect.size.x / ts.x, rect.size.y / ts.y)
	var dst := ts * scale
	var pos := rect.position + (rect.size - dst) * 0.5
	draw_texture_rect(tex, Rect2(pos, dst), false, modulate)
	return true


## 小さな操作チップ（識別色の輪郭＋本文）。斜めの板で統一する。
## 押されている間は板ごと数px沈む（_begin_sink）＝面が指の下へ入り込む。
func _chip(font: Font, r: Rect2, label: String, col: Color, id: String) -> void:
	var pv := _begin_sink(r)
	var sk := DS.skew(r.size.y)
	Kit.slab(self, r, Color(col.r * 0.22, col.g * 0.18, col.b * 0.26, 0.95), sk)
	Kit.slab_edge(self, r, Color(col.r, col.g, col.b, 0.85), sk, 1.5)
	_txt(font, Vector2(r.position.x + (r.size.x - _tw(font, label, DS.T_BODY)) * 0.5 + 4.0,
			r.position.y + r.size.y * 0.5 + 6.0), label, DS.T_BODY, DS.TEXT)
	_end_sink(pv)
	_hit(r, id)


## ラベル付きボタン。enabled=false は灰色＆非ヒット。字は本文か小見出しの2段だけ。
func _btn(font: Font, rect: Rect2, label: String, col: Color, id: String, enabled := true,
		size := DS.T_BODY) -> void:
	var c := col if enabled else Color(0.4, 0.4, 0.45)
	var pv := _begin_sink(rect)
	_panel(rect, Color(c.r * 0.18, c.g * 0.16, c.b * 0.2, 0.92),
			Color(c.r, c.g, c.b, 0.8 if enabled else 0.4))
	var w := _tw(font, label, size)
	_txt(font, Vector2(rect.position.x + (rect.size.x - w) * 0.5 + 3.0,
			rect.position.y + rect.size.y * 0.5 + size * 0.38), label, size, TEXT if enabled else TEXT_DIM)
	_end_sink(pv)
	if enabled:
		_hit(rect, id)


func _bar(rect: Rect2, frac: float, col: Color) -> void:
	Kit.bar(self, rect, frac, col)


# ── 画面の骨格（6画面で同じ段・同じ送り・同じ結び方）──────────────────────
# 経営（_draw_management）の密度を基準にする。どの画面も
#   ①見出し＝T_HEAD の黒板（送り 56）
#   ②本文＝面のある帯／カード
#   ③下端に「結論ブロック」を固定し、間の一覧を可変で伸ばす
# の3点で組む。これを守る限り、画面の縦が空くことはない。
const SEC_ADV := 56.0     # 見出し板（T_HEAD+16=48）＋下の余白 8
const CONC_HEAD := 48.0   # 結論ブロックの黒板の高さ


## セクション見出し。全画面で同じ段（T_HEAD）・同じ幅・同じ送り。
## 戻り値＝本文の開始 y。
func _sec(font: Font, y: float, w: float, label: String, accent: Color, note := "") -> float:
	Kit.header(self, font, Vector2(M, y), label, accent, w, DS.T_HEAD, note)
	return y + SEC_ADV


## 結論ブロックの見出し（傾いた黒板＋識別色の柱）。経営の「今夜の三行精算」と同じ形。
## 戻り値＝本文（面）の矩形。
func _conc(font: Font, r: Rect2, title: String, note: String, ac: Color) -> Rect2:
	var head := Rect2(r.position.x, r.position.y, r.size.x, CONC_HEAD)
	Kit.slab(self, Rect2(head.position.x + 7.0, head.position.y + 6.0, head.size.x - 7.0, head.size.y),
			Color(ac.r, ac.g, ac.b, 0.5), 10.0)
	Kit.slab(self, head, Color(DS.INK.r, DS.INK.g, DS.INK.b, 0.97), 10.0)
	Kit.slab(self, Rect2(head.position.x + 8.0, head.position.y, 9.0, head.size.y), ac, 10.0)
	_txt(font, Vector2(head.position.x + 30.0, head.position.y + 34.0), title, DS.T_HEAD, DS.PAPER)
	if note != "":
		_txt(font, Vector2(head.end.x - _tw(font, note, DS.T_MICRO) - 20.0, head.position.y + 32.0),
				note, DS.T_MICRO, Color(ac.r, ac.g, ac.b, 0.95))
	var body := Rect2(r.position.x, r.position.y + CONC_HEAD, r.size.x, r.size.y - CONC_HEAD)
	Kit.slab(self, body, Color(0.03, 0.028, 0.05, 0.92), 10.0)
	Kit.hatch(self, body.grow(-6.0), Color(ac.r, ac.g, ac.b, 0.05), 22.0, 7.0)
	return body


## 結論ブロックの一行（ラベル小・数値 T_SUB・単位小）。戻り値＝次の x。
func _stat(font: Font, pos: Vector2, label: String, key: String, v: float, unit: String,
		col := DS.PAPER, lw := 0.0) -> float:
	_txt(font, pos, label, DS.T_MICRO, DS.TEXT_2)
	var x := pos.x + (lw if lw > 0.0 else _tw(font, label, DS.T_MICRO) + 10.0)
	var w := _num(font, Vector2(x, pos.y), key, v, DS.T_SUB, col, DS.SUCCESS, DS.DANGER, "", false)
	x += w + 4.0
	if unit != "":
		_txt(font, Vector2(x, pos.y), unit, DS.T_MICRO, DS.TEXT_2)
		x += _tw(font, unit, DS.T_MICRO)
	return x


## 状態の一行（結論ブロックの帯）。緑＝順調／赤＝危険／識別色＝ただの注記。
func _strip(font: Font, r: Rect2, text: String, col: Color) -> void:
	Kit.slab(self, r, Color(col.r * 0.20, col.g * 0.18, col.b * 0.22, 0.95), 8.0)
	Kit.slab_edge(self, r, Color(col.r, col.g, col.b, 0.7), 8.0, 1.5)
	draw_circle(Vector2(r.position.x + 22.0, r.position.y + r.size.y * 0.5), 5.0, col)
	_txt(font, Vector2(r.position.x + 38.0, r.position.y + r.size.y * 0.5 + 6.0), text, DS.T_MICRO, col)


## 2択のセグメント（左右で別々の id を送る版）。工房の 倉庫／バッグ に使う。
func _segment2(font: Font, r: Rect2, a: String, b: String, first: bool,
		id_a: String, id_b: String, ac: Color) -> void:
	var half := r.size.x * 0.5
	var labels := [a, b]
	var ids := [id_a, id_b]
	for i in 2:
		var cell := Rect2(r.position.x + i * half, r.position.y, half - (4.0 if i == 0 else 0.0), r.size.y)
		var on := (i == 0) == first
		var pv := _begin_sink(cell)
		if on:
			Kit.slab(self, Rect2(cell.position.x + 5.0, cell.position.y + 6.0, cell.size.x - 5.0, cell.size.y),
					Color(0, 0, 0, 0.72), 10.0)
			Kit.slab(self, cell, ac, 10.0)
		else:
			Kit.slab(self, cell, Color(0.03, 0.028, 0.05, 0.88), 10.0)
			Kit.slab_edge(self, cell, Color(1, 1, 1, 0.14), 10.0, 1.0)
		var lbl := String(labels[i])
		_txt(font, Vector2(cell.position.x + (cell.size.x - _tw(font, lbl, DS.T_SUB)) * 0.5,
				cell.position.y + r.size.y * 0.5 + 9.0), lbl, DS.T_SUB, DS.on(ac) if on else DS.TEXT_2)
		_end_sink(pv)
		if not on:
			_hit(cell, String(ids[i]))


func _draw() -> void:
	var sz := size
	var font := get_theme_default_font()
	_hits.clear()
	_set_xf(Vector2.ZERO)   # 拡大描画が戻る先を自分の座標系に固定する
	var accent: Color = PANEL_ACCENT.get(panel, PURPLE)

	# ── シートの開閉：部位ごとに 45ms ずつずらす（同時に出さない）─────────
	# 開く＝ヘッダが上から降り、中身が下から迫り上がり、フッターが最後に着く。
	# 閉じる＝逆再生ではなく、全部まとめて短く落とす（開く時間の半分）。
	var hk := 1.0
	var ck := 1.0
	var fk := 1.0
	var closing := _sheet == "closing"
	if _sheet == "opening":
		hk = Kit.stag(_sheet_t, 0, 0.045, 0.26)
		ck = Kit.stag(_sheet_t, 1, 0.045, 0.28)
		fk = Kit.stag(_sheet_t, 2, 0.045, 0.24)
	elif closing:
		var d := Kit.in_cubic(_sheet_t / CLOSE_DUR)
		hk = 1.0 - d
		ck = 1.0 - d
		fk = 1.0 - d
	var h_ofs := Vector2(0.0, -(1.0 - hk) * (HEADER_H + 10.0))
	_c_ofs = Vector2(0.0, (1.0 - ck) * (46.0 if closing else 84.0))
	var f_ofs := Vector2(0.0, (1.0 - fk) * (FOOTER_H + 8.0))

	# パネルを切り替えると背景アートも入れ替わる。素で差し替えるとカットが割れるので、
	# 切替直後だけ一段暗く沈めてから戻す（暗転を挟むと別の絵でも一枚に繋がって見える）。
	var dip := 1.0 - Kit.out_cubic(_panel_t / 0.22)
	if sim != null and bool(sim.state["run"]["active"]):
		# 潜航中の寄り道：背景絵は敷かず暗幕だけ＝下で戦い続けるステージが透ける
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.02, 0.05, 0.84 + 0.12 * dip))
	else:
		Kit.backdrop(self, sz, String(PANEL_BG_ART.get(panel, "")), accent, 0.64 + 0.30 * dip)

	_set_xf(h_ofs)
	_draw_header(font, sz)
	_set_xf(Vector2.ZERO)
	if sim != null:
		_watch_stats()
		_watch_gold()
		_enter_i = 0
		_set_xf(_c_ofs)
		match panel:
			"map": _draw_map(font, sz)
			"member": _draw_member(font, sz)
			"market": _draw_market(font, sz)
			"management": _draw_management(font, sz)
			"renov": _draw_renov(font, sz)
			"workshop": _draw_workshop(font, sz)
		_set_xf(Vector2.ZERO)
		_draw_enter_wipe(sz, accent)
	_set_xf(f_ofs)
	_draw_footer(font, sz)
	_set_xf(Vector2.ZERO)
	Kit.vignette(self, sz)
	_draw_toast(font, sz)
	# 触った結果のフィードバック（押下→波紋→数値の増減）は最前面に置く
	if not _press.is_empty():
		var prk := 1.0 - (_t - float(_press["t0"])) / Kit.PRESS_LIFE
		if prk <= 0.0:
			_press = {}
		else:
			Kit.press(self, _press["rect"], accent, prk)
	Kit.ripples(self, _ripples, _t)
	Kit.flies(self, font, _flies, _t)
	Kit.floats(self, font, _floats, _t)


## パネル登場の暗幕。上から下へ引いていき、引き際に識別色の線が走る。
## 各セクションの平行移動（_stag）と合わせて「行が上から順に現れる」を作る。
func _draw_enter_wipe(sz: Vector2, accent: Color) -> void:
	var span := ENTER_DUR + ENTER_STEP * ENTER_ROWS
	if _panel_t >= span:
		return
	var k := Kit.out_quart(_panel_t / span)
	var top := HEADER_H + 2.0
	var bot := sz.y - FOOTER_H
	var wy := top + (bot - top) * k
	draw_rect(Rect2(0, wy, sz.x, bot - wy), Color(0.02, 0.02, 0.05, 0.72 * (1.0 - k * 0.4)))
	draw_rect(Rect2(0, wy - 2.0, sz.x, 2.0), Color(accent.r, accent.g, accent.b, 0.7 * (1.0 - k)))


func _draw_header(font: Font, sz: Vector2) -> void:
	draw_rect(Rect2(0, 0, sz.x, HEADER_H), Color(DS.INK.r, DS.INK.g, DS.INK.b, 0.97))
	Kit.hatch(self, Rect2(0, 0, sz.x, HEADER_H), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.07), 26.0, 9.0)
	draw_rect(Rect2(0, HEADER_H - 3.0, sz.x, 3.0), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.85))
	# 戻る（潜航中＝編成の寄り道なら「潜航へ復帰」。残り時間はアンカーから実時間で計算）
	var title_x := M + 108.0 + DS.SP_4
	if sim != null and bool(sim.state["run"]["active"]):
		var run: Dictionary = sim.state["run"]
		var remain := maxf(float(run["duration"]) \
				- (Time.get_unix_time_from_system() - float(run["anchor"])), 0.0)
		var lbl := "▼ %d:%02d 潜航へ" % [int(remain / 60.0), int(remain) % 60]
		var bw := _tw(font, lbl, DS.T_BODY) + 30
		var pulse := 0.5 + 0.5 * sin(_t * 3.0)
		_btn(font, Rect2(M, 22, bw, 40), lbl, GOLD.lerp(Color(1.0, 0.55, 0.4), pulse), "resume_dive")
		title_x = M + bw + DS.SP_4
	else:
		_btn(font, Rect2(M, 22, 108, 40), "← 店へ", PURPLE, "home")
	# タイトル。パネルを変えたら黙って差し替わらず、左から滑り込んで薄く入る
	# （ヘッダは動かないので、切替を言うのはこの1行の役目）。
	var tk := Kit.out_quart(_panel_t / 0.30)
	var title := String(PANEL_TITLES.get(panel, ""))
	_txt(font, Vector2(title_x - (1.0 - tk) * 26.0, 40), title, DS.T_SUB,
			Color(DS.PAPER.r, DS.PAPER.g, DS.PAPER.b, 0.15 + 0.85 * tk))
	# 走り際の識別色の線（タイトルの下を一度だけ横切る）
	if tk < 1.0:
		var tw := _tw(font, title, DS.T_SUB)
		var acc: Color = PANEL_ACCENT.get(panel, PURPLE)
		draw_rect(Rect2(title_x - (1.0 - tk) * 26.0, 48.0, tw * tk, 2.0),
				Color(acc.r, acc.g, acc.b, 0.9 * (1.0 - tk)))
	# 日数・所持金・欠片。書式・色・ケースは DS.draw_hud が1箇所で決める
	# （ホームのトップバーとまったく同じ物が出る）。所持金の差分は「飛ぶ数値」が運ぶ。
	if sim != null:
		_gold_pos = DS.draw_hud(self, font, Rect2(0, HEADER_H * 0.5, sz.x, HEADER_H * 0.5),
				sim.state, _fx, _t)


# ── 深層マップ（ステージ制・タスクバーヒーロー準拠）──────────────────────────

func _draw_map(font: Font, sz: Vector2) -> void:
	var y := HEADER_H + 12.0
	var diff := int(sim.state.get("difficulty", 0))

	_stag()
	# 難易度セレクタ（4段。前難易度で第1幕突破が解放条件）
	y = _sec(font, y, sz.x - M * 2.0, "難易度", GOLD)
	var dw := (sz.x - M * 2 - DS.SP_2 * 3) / 4.0
	for d in KuroData.DIFFICULTIES.size():
		var dd: Dictionary = KuroData.DIFFICULTIES[d]
		var r := Rect2(M + d * (dw + DS.SP_2), y, dw, 62)
		var unlocked: bool = sim.diff_unlocked(d)
		var active := d == diff
		var col: Color = dd["color"]
		if not unlocked:
			col = Color(0.4, 0.4, 0.46)
		var pv := _begin_sink(r)
		_panel(r, Color(col.r * 0.18, col.g * 0.16, col.b * 0.2, 0.94),
				col if active else Color(col.r, col.g, col.b, 0.35), 2.0 if active else 1.0)
		if active:
			Kit.spot(self, r.get_center(), dw * 0.7, col, 0.20)
		var nm := String(dd["name"])
		_txt(font, Vector2(r.position.x + (dw - _tw(font, nm, DS.T_BODY)) * 0.5 + 3.0, r.position.y + 26),
				nm, DS.T_BODY, TEXT if unlocked else TEXT_DIM)
		var sub := ("×%.1f" % float(dd["mult"])) if unlocked else "第1幕突破"
		_txt(font, Vector2(r.position.x + (dw - _tw(font, sub, DS.T_MICRO)) * 0.5 + 1.0, r.position.y + 48),
				sub, DS.T_MICRO, col if unlocked else TEXT_DIM)
		_end_sink(pv)
		if unlocked:
			_hit(r, "diff:%d" % d)
	y += 76

	_stag()
	# ステージ一覧（最前線の前後を窓表示。クリア済みは周回可）
	var cleared: int = sim.stage_cleared(diff)
	var frontier := cleared + 1
	var sel := int(sim.state.get("stage_sel", -1))
	if sel < 0 or sel > frontier:
		sel = frontier
	y = _sec(font, y, sz.x - M * 2.0, "ステージ", CYAN, "クリア済みは周回できる")
	var first := maxi(0, frontier - 3)
	if first > 0:
		_txt(font, Vector2(M + DS.SP_2, y + 16), "… %d-1 までクリア済み" % (int(first / float(KuroData.ACT_LEN)) + 1),
				DS.T_MICRO, TEXT_DIM)
		y += 28
	for fl in range(first, frontier + 2):
		var r := Rect2(M, y, sz.x - M * 2, 62)
		var unlocked: bool = fl <= frontier
		var is_cleared := fl <= cleared
		var is_sel := fl == sel
		var biome: Dictionary = KuroData.BIOMES[fl % KuroData.BIOMES.size()]
		var bcol: Color = biome["color"]
		var row_col := CYAN if is_sel else (Color(bcol.r * 2.2, bcol.g * 2.2, bcol.b * 2.2) if unlocked else Color(0.35, 0.35, 0.4))
		var pv := _begin_sink(r)
		_panel(r, Color(0.05, 0.06, 0.10, 0.93 if unlocked else 0.6),
				Color(row_col.r, row_col.g, row_col.b, 0.85 if is_sel else 0.4), 2.0 if is_sel else 1.0)
		# 章票
		var chip := KuroData.stage_label(fl)
		_txt(font, Vector2(r.position.x + 18, y + 38), chip, DS.T_SUB, TEXT if unlocked else TEXT_DIM)
		# バイオーム＋落ちる素材（店の需要から行き先を選べるように）
		var bx := r.position.x + 96.0
		draw_circle(Vector2(bx, y + 25), 5.0, Color(bcol.r * 2.0, bcol.g * 2.0, bcol.b * 2.0) if unlocked else TEXT_DIM)
		_txt(font, Vector2(bx + 14, y + 30), String(biome["name"]), DS.T_BODY, TEXT if unlocked else TEXT_DIM)
		if unlocked:
			var ing := String(biome["ing"])
			var itag := String(KuroData.ING_NAMES.get(ing, ing))
			var ix := bx + 22.0 + _tw(font, String(biome["name"]), DS.T_BODY)
			var icol: Color = {"dry": GOLD, "meat": Color(1.0, 0.55, 0.45), "sea": CYAN}.get(ing, TEXT_DIM)
			var tagr := Rect2(ix, y + 12, _tw(font, itag, DS.T_MICRO) + 20, 24)
			Kit.slab(self, tagr, Color(icol.r * 0.16, icol.g * 0.14, icol.b * 0.16, 0.9), DS.SKEW_MIN)
			Kit.slab_edge(self, tagr, Color(icol.r, icol.g, icol.b, 0.5), DS.SKEW_MIN, 1.0)
			_txt(font, Vector2(ix + 11, y + 30), itag, DS.T_MICRO, icol)
		# ボス（心象語）と推奨戦力
		var psyche: String = KuroData.PSYCHE[fl % KuroData.PSYCHE.size()]
		var power := int(KuroData.depth_scale(fl) * float(KuroData.DIFFICULTIES[diff]["mult"]) * 10.0)
		_txt(font, Vector2(bx + 14, y + 52), ("BOSS『%s』 ・ 戦力%d" % [psyche, power]) if unlocked else "？？？",
				DS.T_MICRO, TEXT_DIM)
		# 状態
		var st := "未開放"
		var stc := TEXT_DIM
		if is_sel:
			st = "▶ 出撃"
			stc = CYAN
		elif is_cleared:
			st = "✓ 済"
			stc = GREEN
		elif unlocked:
			st = "最前線"
			stc = GOLD
		_txt(font, Vector2(r.end.x - _tw(font, st, DS.T_BODY) - 20, y + 38), st, DS.T_BODY, stc)
		_end_sink(pv)
		if unlocked:
			_hit(r, "stage:%d" % fl)
		y += 70

	_stag()
	# 出撃ボタン（フッターの上）
	var sortie := Rect2(M, sz.y - FOOTER_H - 140, sz.x - M * 2, 56)
	# 待機中の生気はこの1箇所だけ。常時揺れる sin ではなく心拍（静か→短い二拍）
	var pulse := Kit.heartbeat(_t)
	var spv := _begin_sink(sortie)
	Kit.cta(self, sortie, Color(PINK.r * 0.22, PINK.g * 0.16, PINK.b * 0.24, 0.96), PINK, pulse)
	var sl := "▶ %s に集中して潜る（25分）" % KuroData.stage_label(sel)
	_txt(font, Vector2(sortie.position.x + (sortie.size.x - _tw(font, sl, DS.T_SUB)) * 0.5 + 4.0,
			sortie.position.y + 38), sl, DS.T_SUB, TEXT)
	_end_sink(spv)
	_hit(sortie, "sortie_pomo")
	_btn(font, Rect2(M, sz.y - FOOTER_H - 72, sz.x - M * 2, 44), "クイック仕入れ（80秒）", CYAN, "sortie_quick")


# ── メンバー ─────────────────────────────────────────────────────────────────

func _draw_member(font: Font, sz: Vector2) -> void:
	var ids: Array = KuroData.GIRL_ORDER
	var ac := PINK                     # この画面の識別色（他の有彩色は状態色だけ）
	var w := sz.x - M * 2.0
	var top := HEADER_H
	var bot := sz.y - FOOTER_H
	# 斜めの地紋：経営と同じく、無情報の平面を作らない
	Kit.hatch(self, Rect2(0, top, sz.x, bot - top), Color(ac.r, ac.g, ac.b, 0.05), 26.0, 9.0)
	var y := top + 12.0

	_stag()
	# ① 6人チップ ---------------------------------------------------------
	var n := ids.size()
	var gap := float(DS.SP_2)
	var cw := (w - gap * (n - 1)) / float(n)
	# 「選ぶ」にも固有のモーションを持たせる：選択の帯は隣の子へ滑って、少し行き過ぎて座る。
	# 枠の色も移動中は前の子と混ざる＝どこからどこへ移ったかが見える。
	var si := maxi(ids.find(_sel_girl), 0)
	var sc: Color = KuroData.GIRLS[ids[si]]["color"]
	var sl: Dictionary = Kit.nav_slide(_selbar, float(M) + si * (cw + gap), sc, _t)
	var sx := float(sl["x"])
	var scol: Color = sl["col"]
	for i in n:
		var id: String = ids[i]
		var g0: Dictionary = KuroData.GIRLS[id]
		var r := Rect2(M + i * (cw + gap), y, cw, 76.0)
		var col: Color = g0["color"]
		var near := clampf(1.0 - absf(sx - r.position.x) / (cw + gap), 0.0, 1.0)
		var active := near > 0.5
		var pv := _begin_sink(r)
		_panel(r, Color(col.r * 0.16, col.g * 0.16, col.b * 0.2, 0.95),
				Color(col.r, col.g, col.b, 0.35).lerp(col, Kit.out_cubic(near)), 1.0 + near)
		# 顔アイコン（無ければ名前のみ）
		var drew := _draw_icon("res://assets/generated/face/%s/neutral_open.png" % id,
				Rect2(r.position.x + (cw - 40.0) * 0.5, r.position.y + 6.0, 40.0, 40.0),
				Color(1, 1, 1, 1.0 if active else 0.8))
		var nm := String(g0["name"])
		var ny := r.position.y + (66.0 if drew else 46.0)
		_txt(font, Vector2(r.position.x + (cw - _tw(font, nm, DS.T_MICRO)) * 0.5 + 2.0, ny), nm,
				DS.T_MICRO, TEXT if active else TEXT_DIM)
		_end_sink(pv)
		_hit(r, "_selg:" + id)
	var sstretch := (1.0 - Kit.out_cubic(float(sl["k"]))) * cw * 0.5
	draw_rect(Rect2(sx - sstretch * 0.5, y, cw + sstretch, 3.0), scol)
	y += 88.0

	var gid := _sel_girl
	_stag()
	# ② 詳細カード -------------------------------------------------------
	_mb_card(font, Rect2(M, y, w, 180.0), gid, ac)
	y += 192.0

	_stag()
	# ③ 装備3枠（今まで画面に無かった事実。工房への導線も兼ねる）---------
	y = _sec(font, y, w, "装備", ac, "タップで工房へ")
	_mb_gear(font, Rect2(M, y, w, 92.0), gid)
	y += 108.0

	# ⑥ 下端固定：編成の見立て（この画面の結論。経営の三行精算と同じ置き方）
	var conc_h := 160.0
	var conc_top := bot - 12.0 - conc_h

	# ④⑤ は残りを行数で分け合う＝どの子を選んでも画面の縦を使い切る
	var eq: Array = sim.state["girls"][gid]["skills_eq"]
	var known: Array = sim.known_skills(gid)
	var nodes: Array = KuroData.GIRL_TREES.get(gid, [])
	var srow := maxi(int((known.size() + 1) / 2), 1)
	var tn := maxi(nodes.size(), 1)
	var region := maxf(conc_top - 16.0 - y - SEC_ADV * 2.0 - 16.0, 220.0)
	var h1 := region * float(srow) / float(srow + tn)
	var h2 := region - h1

	_stag()
	# ④ スキル（装備枠）--------------------------------------------------
	y = _sec(font, y, w, "スキル", ac, "装備 %d/%d　タップで着脱" % [eq.size(), sim.skill_slots()])
	var half := (w - DS.SP_2) * 0.5
	var srh := (h1 - float(DS.SP_2) * (srow - 1)) / float(srow)
	var odd_last := known.size() % 2 == 1
	for i in known.size():
		var sid: String = known[i]
		var def: Dictionary = KuroData.SKILL_DB[sid]
		# 端数の1枚は幅いっぱいに伸ばす（右側に無情報の平面を残さない）
		var cwid := w if (odd_last and i == known.size() - 1) else half
		var r := Rect2(M + (i % 2) * (half + DS.SP_2), y + int(i / 2) * (srh + DS.SP_2), cwid, srh)
		var on: bool = sid in eq
		var pv := _begin_sink(r)
		_panel(r, Color(0.08, 0.08, 0.12, 0.95), ac if on else Color(0.4, 0.42, 0.5, 0.6),
				2.0 if on else 1.0)
		# スキルアイコン（doctor/nurse 等は未用意 → テキストのみ）
		var has_icon := _draw_icon("res://assets/generated/skill/%s.png" % sid,
				Rect2(r.position.x + 12.0, r.position.y + (srh - 36.0) * 0.5, 36.0, 36.0),
				Color(1, 1, 1, 1.0 if on else 0.7))
		var stx := r.position.x + (58.0 if has_icon else 18.0)
		_txt(font, Vector2(stx, r.position.y + srh * 0.5 - 2.0), String(def["name"]), DS.T_BODY,
				TEXT if on else TEXT_DIM)
		_txt(font, Vector2(stx, r.position.y + srh * 0.5 + 22.0),
				"CD%.0fs　%s" % [float(def["cd"]), ("装備中" if on else "タップで装備")],
				DS.T_MICRO, ac if on else TEXT_DIM)
		_end_sink(pv)
		_hit(r, "skill:%s:%s" % [gid, sid])
	if known.is_empty():
		var er := Rect2(M, y, w, h1)
		_panel(er, Color(0.05, 0.05, 0.08, 0.86), Color(0.4, 0.42, 0.5, 0.4))
		_txt(font, Vector2(er.position.x + 24.0, er.position.y + er.size.y * 0.5 + 6.0),
				"まだ技を覚えていない。育成で解放する。", DS.T_BODY, TEXT_DIM)
	y += h1 + 16.0

	_stag()
	# ⑤ 育成ツリー（記憶の欠片）------------------------------------------
	y = _sec(font, y, w, "育成", ac, "記憶の欠片 %d 個で解放" % int(sim.state["shards"]))
	var owned: Array = sim.state["girls"][gid].get("tree", [])
	var trh := (h2 - float(DS.SP_2) * (tn - 1)) / float(tn)
	for i in nodes.size():
		var node: Dictionary = nodes[i]
		var nid := String(node["id"])
		var r := Rect2(M, y + i * (trh + DS.SP_2), w, trh)
		var is_owned: bool = nid in owned
		var avail: bool = sim.tree_available(gid, nid)
		var border := GREEN if is_owned else (ac if avail else Color(0.35, 0.35, 0.4, 0.5))
		_panel(r, Color(0.07, 0.07, 0.1, 0.9), border)
		# 左端の縦帯＝その段の状態（解放済／今買える／まだ）
		Kit.slab(self, Rect2(r.position.x + 6.0, r.position.y + 6.0, 8.0, r.size.y - 12.0),
				Color(border.r, border.g, border.b, 0.95 if (is_owned or avail) else 0.4), 3.0)
		var mid := r.position.y + r.size.y * 0.5
		_txt(font, Vector2(r.position.x + 28.0, mid - 2.0), String(node["name"]), DS.T_BODY,
				TEXT if (is_owned or avail) else TEXT_DIM)
		_txt(font, Vector2(r.position.x + 28.0, mid + 22.0), _effect_label(node["effect"]),
				DS.T_MICRO, TEXT_DIM)
		var cost := int(node["cost"])
		if is_owned:
			_txt(font, Vector2(r.end.x - _tw(font, "解放済", DS.T_MICRO) - 24.0, mid + 6.0), "解放済",
					DS.T_MICRO, GREEN)
		elif avail:
			_btn(font, Rect2(r.end.x - 132.0, mid - 21.0, 120.0, 42.0), "欠片%d" % cost, ac,
					"tree:%s:%s" % [gid, nid], int(sim.state["shards"]) >= cost)
		else:
			var req := int(node.get("req_aff", 0))
			var why := "♥%d必要" % req if sim.aff(gid) < req else "前の段が未解放"
			_txt(font, Vector2(r.end.x - _tw(font, why, DS.T_MICRO) - 24.0, mid - 2.0), why,
					DS.T_MICRO, Color(0.6, 0.6, 0.66))
			_txt(font, Vector2(r.end.x - _tw(font, "欠片%d" % cost, DS.T_MICRO) - 24.0, mid + 22.0),
					"欠片%d" % cost, DS.T_MICRO, TEXT_DIM)

	_stag()
	_mb_ledger(font, Rect2(M, conc_top, w, conc_h), gid, ac)


## メンバー詳細カード。切替は瞬間差し替えではなく、動いた向きから滑り込ませる
## （帯だけが動いて中身が黙って入れ替わる、をやめる）。
func _mb_card(font: Font, card: Rect2, gid: String, ac: Color) -> void:
	var g: Dictionary = KuroData.GIRLS[gid]
	var col: Color = g["color"]
	var y := card.position.y
	var mk := Kit.out_quart((_t - _selg_t) / SELG_DUR)
	_panel(card, Color(0.06, 0.06, 0.1, 0.92), Color(col.r, col.g, col.b, 0.5))
	if mk < 1.0:
		Kit.set_xf(self, _xf_now + Vector2((1.0 - mk) * 46.0 * _selg_dir, 0.0))
	# 立ち絵（左・無ければテキストだけ左寄せ）
	var has_portrait := _draw_icon("res://assets/portraits/%s.png" % gid,
			Rect2(card.position.x + 14.0, y + 8.0, 92.0, 164.0))
	var tx := card.position.x + (120.0 if has_portrait else 24.0)
	_txt(font, Vector2(tx, y + 48.0), String(g["name"]), DS.T_HEAD, col)
	_txt(font, Vector2(tx, y + 74.0), String(g["role"]), DS.T_MICRO, TEXT_DIM)
	# ステータス（装備を替えたら、その場で数字が動いて差分が流れる）
	_txt(font, Vector2(tx, y + 118.0), "攻", DS.T_MICRO, TEXT_DIM)
	_num(font, Vector2(tx + 36.0, y + 118.0), "atk_" + gid, float(int(sim.girl_atk(gid))), DS.T_SUB,
			Color(1.0, 0.6, 0.45))
	_txt(font, Vector2(tx + 132.0, y + 118.0), "HP", DS.T_MICRO, TEXT_DIM)
	_num(font, Vector2(tx + 176.0, y + 118.0), "hp_" + gid, float(int(sim.girl_maxhp(gid))), DS.T_SUB, GREEN)
	# 好感度バー
	_txt(font, Vector2(tx, y + 158.0), "♥", DS.T_MICRO, ac)
	var bar_w := card.end.x - 100.0 - (tx + 28.0)
	_bar(Rect2(tx + 28.0, y + 143.0, bar_w, 18.0), sim.aff(gid) / 100.0, ac)
	var aw := _num(font, Vector2(card.end.x - 96.0, y + 158.0), "aff_" + gid, float(sim.aff(gid)),
			DS.T_BODY, ac)
	_txt(font, Vector2(card.end.x - 96.0 + aw, y + 158.0), "/100", DS.T_MICRO, TEXT_DIM)
	# 右上：今夜の役どころ（店番は1人だけ＝ここが賭けの起点）
	var is_keeper := String(sim.state["morning"]["keeper"]) == gid
	var role := "今夜 店番" if is_keeper else "今夜 潜航"
	var br := Rect2(card.end.x - 20.0 - (_tw(font, role, DS.T_MICRO) + 26.0), y + 22.0,
			_tw(font, role, DS.T_MICRO) + 26.0, 28.0)
	if is_keeper:
		Kit.slab(self, br, ac, 6.0)
		_txt(font, Vector2(br.position.x + 14.0, br.position.y + 20.0), role, DS.T_MICRO, DS.INK)
	else:
		Kit.slab_edge(self, br, Color(1, 1, 1, 0.28), 6.0, 1.0)
		_txt(font, Vector2(br.position.x + 14.0, br.position.y + 20.0), role, DS.T_MICRO, TEXT_DIM)
	# 店番シナジー（右上）
	var syn := "店番 %s" % String(g["synergy"])
	_txt(font, Vector2(card.end.x - _tw(font, syn, DS.T_MICRO) - 20.0, y + 74.0), syn, DS.T_MICRO, GOLD)
	var sdesc := String(g["synergy_desc"])
	_txt(font, Vector2(card.end.x - _tw(font, sdesc, DS.T_MICRO) - 20.0, y + 98.0), sdesc, DS.T_MICRO, TEXT_DIM)
	# 次に開くもの（好感度と育成が噛んでいることを1行で言う）
	var nxt := _mb_next(gid)
	if nxt != "":
		_txt(font, Vector2(card.end.x - _tw(font, nxt, DS.T_MICRO) - 20.0, y + 122.0), nxt,
				DS.T_MICRO, Color(0.62, 0.62, 0.7))
	# 切替中の暗幕（面の色で伏せて、滑りながら現れる）
	if mk < 1.0:
		Kit.set_xf(self, _xf_now)
		Kit.slab(self, card.grow(-2.0), Color(0.06, 0.06, 0.1, (1.0 - mk) * 0.98), DS.skew(card.size.y))


## 次に開く育成ノードを1行で。無ければ空文字。
func _mb_next(gid: String) -> String:
	var owned: Array = sim.state["girls"][gid].get("tree", [])
	for node in KuroData.GIRL_TREES.get(gid, []):
		if String(node["id"]) in owned:
			continue
		var req := int(node.get("req_aff", 0))
		if sim.aff(gid) < req:
			return "次：♥%d で %s" % [req, String(node["name"])]
		return "次：欠片%d で %s" % [int(node["cost"]), String(node["name"])]
	return "育成はすべて解放済"


## 装備3枠（武器・防具・装飾）。ここでは外さない＝加工は工房に集約する。
func _mb_gear(font: Font, area: Rect2, gid: String) -> void:
	var eq: Dictionary = sim.state["girls"][gid]["equip"]
	var slots := ["weapon", "armor", "trinket"]
	var gap := 10.0
	var cw := (area.size.x - gap * 2.0) / 3.0
	for i in 3:
		var sid: String = slots[i]
		var it: Dictionary = eq.get(sid, {})
		var r := Rect2(area.position.x + i * (cw + gap), area.position.y, cw, area.size.y)
		var has: bool = not it.is_empty()
		var col: Color = KuroData.equip_grade_color(int(it.get("grade", 0))) if has \
				else Color(0.4, 0.4, 0.46)
		var pv := _begin_sink(r)
		_panel(r, Color(0.05, 0.055, 0.08, 0.93), Color(col.r, col.g, col.b, 0.7 if has else 0.35))
		_txt(font, Vector2(r.position.x + 16.0, r.position.y + 26.0),
				String(SimItems.SLOTS[sid]["name"]), DS.T_MICRO, TEXT_DIM)
		if has:
			_draw_icon("res://assets/generated/equip/%s.png" % sid,
					Rect2(r.end.x - 44.0, r.position.y + 8.0, 32.0, 32.0), col)
			_txt(font, Vector2(r.position.x + 16.0, r.position.y + 56.0), SimItems.display_name(it),
					DS.T_BODY, col)
			_txt(font, Vector2(r.position.x + 16.0, r.position.y + 80.0),
					"score %.1f" % float(it.get("score", 0.0)), DS.T_MICRO, TEXT_DIM)
		else:
			_txt(font, Vector2(r.position.x + 16.0, r.position.y + 58.0), "空き", DS.T_SUB, TEXT_DIM)
			_txt(font, Vector2(r.position.x + 16.0, r.position.y + 80.0), "工房で付ける", DS.T_MICRO, TEXT_DIM)
		_end_sink(pv)
		_hit(r, "_panel:workshop")


## 編成の見立て（この画面の結論）。潜るのは店番以外、という事実を数字で置く。
func _mb_ledger(font: Font, r: Rect2, gid: String, ac: Color) -> void:
	var body := _conc(font, r, "編成の見立て", "店番以外が潜る", ac)
	var divers: Array = sim.divers()
	var atk := 0.0
	var hp := 0.0
	for d in divers:
		atk += sim.girl_atk(d)
		hp += sim.girl_maxhp(d)
	var x := body.position.x + 24.0
	var y1 := body.position.y + 36.0
	_stat(font, Vector2(x, y1), "潜航", "mb_div", float(divers.size()), "人")
	_stat(font, Vector2(x + 152.0, y1), "合計攻", "mb_atk", atk, "")
	_stat(font, Vector2(x + 336.0, y1), "総HP", "mb_hp", hp, "")
	_stat(font, Vector2(x + 528.0, y1), "技枠", "mb_slot", float(sim.skill_slots()), "")
	var keeper := String(sim.state["morning"]["keeper"])
	var kg: Dictionary = KuroData.GIRLS[keeper]
	var msg := "店番は %s ／ %s。残り %d 人で潜る。" % [String(kg["name"]),
			String(kg["synergy_desc"]), divers.size()]
	var col := ac
	if gid == keeper:
		msg = "%s は今夜の店番。潜航には出ない。" % String(kg["name"])
		col = GOLD
	_strip(font, Rect2(body.position.x + 12.0, body.end.y - 54.0, body.size.x - 24.0, 42.0), msg, col)


func _effect_label(eff: Dictionary) -> String:
	if eff.has("skill"):
		# ノード名が既に技名なので、ここでは「何が増えるか」を言う（写しにしない）
		var sk: Dictionary = KuroData.SKILL_DB[eff["skill"]]
		return "技を覚える　CD%.0fs" % float(sk["cd"])
	var parts: Array = []
	for k in eff:
		var nm := String({"atk": "攻", "hp": "HP", "crit": "会心"}.get(k, k))
		parts.append("%s+%d%%" % [nm, int(float(eff[k]) * 100)])
	return "・".join(parts)


# ── 市場 ─────────────────────────────────────────────────────────────────────

## 闇市の品書き。KuroData.MARKET は名前と値段しか持たないので、
## 「何のために買うのか」を画面が言えるように、表示語（札の一文字と一行説明）だけ置く。
const MARKET_NOTE := {
	"recipe": ["写", "献立の幅が広がる。重複すれば星が上がり単価も上がる。"],
	"mats": ["箱", "乾・肉・海が +2 ずつ。今夜の皿数にそのまま効く。"],
	"invite": ["状", "翌夜の客 +3。看板が育つまでの繋ぎ。"],
}


func _draw_market(font: Font, sz: Vector2) -> void:
	var s: Dictionary = sim.state
	var ac := GOLD                     # この画面の識別色（値札の色＝市場の色）
	var w := sz.x - M * 2.0
	var top := HEADER_H
	var bot := sz.y - FOOTER_H
	Kit.hatch(self, Rect2(0, top, sz.x, bot - top), Color(ac.r, ac.g, ac.b, 0.05), 26.0, 9.0)
	var fc: Dictionary = _forecast()
	var y := top + 12.0

	_stag()
	# ① 在庫（3種を同じ大きさのカードで。数だけでなく「今夜どう効くか」も言う）
	y = _sec(font, y, w, "在庫", ac, "潜って獲る／闇市で買う")
	_mk_stock(font, Rect2(M, y, w, 128.0), s, fc)
	y += 144.0

	# ④ 下端固定：仕入れの見立て（この画面の結論）
	var conc_h := 196.0
	var conc_top := bot - 12.0 - conc_h

	# ②③ は残りを分け合う。停泊していない夜も、面で埋めて背景を露出させない。
	var ship: Array = s["ship"]["stock"]
	var region := maxf(conc_top - 16.0 - y - SEC_ADV * 2.0 - 16.0, 240.0)
	var w2 := maxf(float(ship.size()), 1.4)
	var h1 := region * 3.0 / (3.0 + w2)
	var h2 := region - h1
	var gap := 10.0

	_stag()
	# ② 闇市（固定3品）
	y = _sec(font, y, w, "闇市", ac, "いつでも同じ棚")
	var rh := (h1 - gap * 2.0) / 3.0
	for i in KuroData.MARKET.size():
		_mk_row(font, Rect2(M, y + i * (rh + gap), w, rh), i, s)
	y += h1 + 16.0

	_stag()
	# ③ 交易船（10分毎ローテ・装備/ペット）
	y = _sec(font, y, w, "交易船", ac, "10分毎に入替")
	if ship.is_empty():
		_mk_ship_empty(font, Rect2(M, y, w, h2), s)
	else:
		var rh2 := (h2 - gap * (ship.size() - 1)) / float(ship.size())
		for i in ship.size():
			_mk_ship_row(font, Rect2(M, y + i * (rh2 + gap), w, rh2), i, s)

	_stag()
	_mk_ledger(font, Rect2(M, conc_top, w, conc_h), s, fc)


## 在庫3種。素材も「増えたら跳ねる」＝買った瞬間に数字が動くのが見える。
func _mk_stock(font: Font, area: Rect2, s: Dictionary, fc: Dictionary) -> void:
	var gap := 10.0
	var cw := (area.size.x - gap * 2.0) / 3.0
	var menu: Array = s["morning"]["menu"]
	var out: Array = fc["out"]
	for i in KuroData.INGS.size():
		var ing: String = KuroData.INGS[i]
		var r := Rect2(area.position.x + i * (cw + gap), area.position.y, cw, area.size.y)
		var uses := 0
		for rid in menu:
			if String(KuroData.RECIPES[rid]["ing"]) == ing:
				uses += 1
		var gone: bool = ing in out
		var col := DS.DANGER if gone else (CYAN if uses > 0 else Color(0.45, 0.46, 0.54))
		_panel(r, Color(0.05, 0.06, 0.08, 0.93), Color(col.r, col.g, col.b, 0.55))
		_draw_icon("res://assets/generated/ing/%s.png" % ing,
				Rect2(r.position.x + 14.0, r.position.y + 12.0, 44.0, 44.0), Color(1, 1, 1, 1), true)
		_txt(font, Vector2(r.position.x + 70.0, r.position.y + 42.0),
				String(KuroData.ING_NAMES[ing]), DS.T_BODY, TEXT)
		var nw := _num(font, Vector2(r.position.x + 16.0, r.position.y + 94.0), "stock_" + ing,
				float(int(s["stock"][ing])), DS.T_HEAD, TEXT)
		_txt(font, Vector2(r.position.x + 20.0 + nw, r.position.y + 94.0), "個", DS.T_MICRO, TEXT_DIM)
		var note := "今夜は使わない"
		if gone:
			note = "▲ 今夜で尽きる"
		elif uses > 0:
			note = "今夜 %d 品に使う" % uses
		_txt(font, Vector2(r.position.x + 16.0, r.position.y + 118.0), note, DS.T_MICRO, col)


## 市場の1行（闇市・交易船で同じ型）。札／品名／説明／値段／買う。
## 高さが足りない時は段を小さくせず、行数だけ落として値段を1行目へ寄せる
## （＝入りきらない情報は段階表示にする。字の段は 16/24/32/48 のまま）。
func _mk_card(font: Font, r: Rect2, glyph: String, icon: String, title: String, sub: String,
		price: int, key: String, col: Color, can: bool, id: String, lack: int) -> void:
	_panel(r, Color(0.06, 0.06, 0.075, 0.92), Color(col.r, col.g, col.b, 0.5 if can else 0.25))
	# 札（黒板に一文字／装備はスロット絵）＝品物の顔。経営の予報板と同じ作り。
	var gs := clampf(r.size.y - 24.0, 44.0, 64.0)
	var g := Rect2(r.position.x + 16.0, r.position.y + (r.size.y - gs) * 0.5, gs, gs)
	Kit.slab(self, g, Color(DS.INK.r, DS.INK.g, DS.INK.b, 0.95), 8.0)
	Kit.slab_edge(self, g, Color(col.r, col.g, col.b, 0.5), 8.0, 1.5)
	if icon == "" or not _draw_icon(icon, g.grow(-12.0), col):
		_txt(font, Vector2(g.position.x + (gs - _tw(font, glyph, DS.T_HEAD)) * 0.5 + 4.0,
				g.position.y + gs * 0.5 + 12.0), glyph, DS.T_HEAD, col)
	var tx := g.end.x + 16.0
	var bw := 132.0
	var btn := Rect2(r.end.x - 16.0 - bw, r.position.y + (r.size.y - 56.0) * 0.5, bw, 56.0)
	var pcol := GOLD if can else Color(0.55, 0.5, 0.42)
	var mid := r.position.y + r.size.y * 0.5
	if r.size.y >= 108.0:
		_txt(font, Vector2(tx, r.position.y + 38.0), title, DS.T_SUB, col if can else TEXT_DIM)
		_txt(font, Vector2(tx, r.position.y + 64.0), sub, DS.T_MICRO, TEXT_DIM)
		var py := r.end.y - 20.0
		var pw := _num(font, Vector2(tx, py), key, float(price), DS.T_SUB, pcol,
				DS.SUCCESS, DS.DANGER, "", false)
		_txt(font, Vector2(tx + pw + 4.0, py), "G", DS.T_MICRO, TEXT_DIM)
		if lack > 0:
			_txt(font, Vector2(tx + pw + 26.0, py), "%dG 足りない" % lack, DS.T_MICRO, DS.DANGER)
	else:
		# 2行に畳む：値段は品名と同じ行の右端（ボタンの手前）へ
		var ps := "%dG" % price
		var px := btn.position.x - 16.0 - _tw(font, ps, DS.T_SUB)
		_txt(font, Vector2(tx, mid - 4.0), title, DS.T_SUB, col if can else TEXT_DIM)
		var pw2 := _num(font, Vector2(px, mid - 4.0), key, float(price), DS.T_SUB, pcol,
				DS.SUCCESS, DS.DANGER, "", false)
		_txt(font, Vector2(px + pw2 + 2.0, mid - 4.0), "G", DS.T_MICRO, TEXT_DIM)
		var s2 := sub
		if lack > 0:
			s2 = "%s　／　%dG 足りない" % [sub, lack] if sub != "" else "%dG 足りない" % lack
		_txt(font, Vector2(tx, mid + 22.0), s2, DS.T_MICRO, DS.DANGER if lack > 0 else TEXT_DIM)
	_btn(font, btn, "買う", col, id, can, DS.T_SUB)


## 闇市の1行。
func _mk_row(font: Font, r: Rect2, i: int, s: Dictionary) -> void:
	var it: Dictionary = KuroData.MARKET[i]
	var price := int(it["price"])
	var can: bool = int(s["gold"]) >= price
	var note: Array = MARKET_NOTE.get(String(it["id"]), ["品", ""])
	_mk_card(font, r, String(note[0]), "", String(it["name"]), String(note[1]), price,
			"mk_p%d" % i, GOLD, can, "buy:%d" % i, maxi(price - int(s["gold"]), 0))


## 交易船の1行（装備／ペット）。等級色は「稀少さ」という事実なので残す。
func _mk_ship_row(font: Font, r: Rect2, i: int, s: Dictionary) -> void:
	var entry: Dictionary = s["ship"]["stock"][i]
	var price := int(entry["price"])
	var can: bool = int(s["gold"]) >= price
	var label := ""
	var sub := ""
	var icon := ""
	var col := GOLD
	if entry["type"] == "pet":
		var pet: Dictionary = KuroData.PETS[entry["pet"]]
		label = String(pet["name"])
		sub = "住み着く ・ %s" % String(pet["desc"])
		col = PINK
	else:
		var item: Dictionary = entry["item"]
		var grade := int(item["grade"])
		label = SimItems.display_name(item)
		sub = "%s ・ score %.1f" % [String(SimItems.GRADES[grade]["name"]), float(item["score"])]
		var af := SimItems.affix_text(item)
		if af != "":
			sub += " ・ " + af
		icon = "res://assets/generated/equip/%s.png" % String(item["slot"])
		col = KuroData.equip_grade_color(grade)
	_mk_card(font, r, "獣", icon, label, sub, price, "ship_p%d" % i, col, can, "ship:%d" % i,
			maxi(price - int(s["gold"]), 0))


## 停泊していない夜。空白ではなく「次はいつ・何が来るか」を置く（画面は必ず閉じる）。
func _mk_ship_empty(font: Font, r: Rect2, s: Dictionary) -> void:
	var ac := GOLD
	_panel(r, Color(0.04, 0.05, 0.08, 0.9), Color(ac.r, ac.g, ac.b, 0.28))
	Kit.hatch(self, r.grow(-6.0), Color(ac.r, ac.g, ac.b, 0.05), 22.0, 7.0)
	_txt(font, Vector2(r.position.x + 24.0, r.position.y + 44.0), "今は停泊していない。", DS.T_SUB, TEXT_DIM)
	var left := maxf(KuroData.SHIP_ROTATE_SEC
			- (Time.get_unix_time_from_system() - float(s["ship"]["rotated"])), 0.0)
	var wt := "次の入替まで %d:%02d" % [int(left / 60.0), int(left) % 60]
	_txt(font, Vector2(r.end.x - _tw(font, wt, DS.T_BODY) - 24.0, r.position.y + 44.0), wt,
			DS.T_BODY, ac)
	var ly := r.position.y + 82.0
	for line in ["・棚には装備が2つ並ぶ（潜航より当たりが早い）",
			"・稀にペットが混じる（永続の売上・素材ボーナス）",
			"・10分ごとに棚ごと入れ替わる"]:
		if ly > r.end.y - 12.0:
			break
		_txt(font, Vector2(r.position.x + 24.0, ly), line, DS.T_MICRO, Color(0.62, 0.62, 0.7))
		ly += 26.0


## 仕入れの見立て（この画面の結論）。今夜の皿と財布を1枚に閉じる。
func _mk_ledger(font: Font, r: Rect2, s: Dictionary, fc: Dictionary) -> void:
	var ac := GOLD
	var body := _conc(font, r, "仕入れの見立て", "今夜ぶん", ac)
	var x := body.position.x + 24.0
	var y1 := body.position.y + 36.0
	_stat(font, Vector2(x, y1), "在庫", "mk_tot", float(sim.stock_total()), "個")
	_stat(font, Vector2(x + 168.0, y1), "今夜出す", "mk_served", float(int(fc["served"])), "皿")
	var short_n := int(fc["short"])
	_stat(font, Vector2(x + 380.0, y1), "売り逃し", "mk_short", float(short_n), "皿",
			DS.DANGER if short_n > 0 else DS.PAPER)
	var y2 := y1 + 38.0
	_stat(font, Vector2(x, y2), "所持金", "mk_gold", float(int(s["gold"])), "G", GOLD)
	_stat(font, Vector2(x + 260.0, y2), "素材箱", "mk_box", float(int(int(s["gold"]) / 100)), "回ぶん")
	_stat(font, Vector2(x + 480.0, y2), "看板", "mk_sign", float(sim.sign_total()), "")
	var names: Array = []
	for ing in fc["out"]:
		names.append(String(KuroData.ING_NAMES.get(ing, ing)))
	var msg := "素材は足りている。今夜は棚を見るだけでいい。"
	var col := DS.SUCCESS
	if short_n > 0:
		msg = "▲ %s が尽きて %d 皿を売り逃す。潜るか素材箱を買う。" % [
				"・".join(names) if not names.is_empty() else "素材", short_n]
		col = DS.DANGER
	elif not names.is_empty():
		msg = "今夜で %s を使い切る。明日の仕込みには仕入れが要る。" % "・".join(names)
		col = ac
	_strip(font, Rect2(body.position.x + 12.0, body.end.y - 54.0, body.size.x - 24.0, 42.0), msg, col)


# ── 経営 ─────────────────────────────────────────────────────────────────────

## 素材1個の原価。闇市の「素材箱（乾・肉・海 +2ずつ）」100G ÷ 6個 から引く。
const MAT_COST := 17
const PAD := 16.0


func _draw_management(font: Font, sz: Vector2) -> void:
	var s: Dictionary = sim.state
	var m: Dictionary = s["morning"]
	var ac := PURPLE                       # この画面の支配色（他の有彩色は出さない）
	var w := sz.x - PAD * 2.0
	var top := HEADER_H
	var bot := sz.y - FOOTER_H
	# 斜めの地紋：無情報の平面を作らない
	Kit.hatch(self, Rect2(0, top, sz.x, bot - top), Color(ac.r, ac.g, ac.b, 0.055), 26.0, 9.0)

	var fc: Dictionary = _forecast()
	var pen: bool = bool(s.get("crowd_penalty", false))
	var base: Dictionary = _forecast_base() if pen else fc
	var taste := String(s["forecast"])
	var tcol: Color = KuroData.TASTE_COLORS.get(taste, ac)
	# 今夜の純益は「この画面の結論」。値の変化はここで捕まえ、操作の手応えに使う。
	var profit := int(fc["gold"]) - int(fc["served"]) * MAT_COST
	var pn: Dictionary = Kit.num(_fx, "profit", float(profit), _t)
	if absf(float(pn["d"])) >= 1.0:
		_chg_d = float(pn["d"])
		if _t - _chg_t > 1.2:
			_chg = "仕込みが変わった"      # 改装解放など、チップ以外で動いた時
		_chg_t = _t

	_stag()
	# ① 今夜の予報 -------------------------------------------------------
	var y := top + 12.0
	_mg_forecast(font, Rect2(PAD, y, w, 96.0), taste, tcol, fc, base, pen)
	y += 104.0
	# ①-b 切断の罰（あるときだけ、赤い板で名指しする）
	if pen:
		_mg_penalty(font, Rect2(PAD, y, w, 34.0), fc, base)
		y += 42.0

	_stag()
	# ② 店番（適性と純益の2軸で選ぶ）-------------------------------------
	y = _sec(font, y, w, "店番", ac, "適性だけでは決まらない")
	_mg_keepers(font, Rect2(PAD, y, w, 240.0), m, _keeper_profits())
	y += 248.0
	# 直近の操作が純益をいくら動かしたか（賭けを組んでいる実感）
	_mg_change(font, Rect2(PAD, y, w, 32.0), m)
	y += 40.0

	_stag()
	# ③ 扉の方針 ---------------------------------------------------------
	var door_y := y
	y = _sec(font, y, w, "扉", ac, "潜航中の扉をどう扱うか")
	_chip(font, Rect2(sz.x - PAD - 168.0, door_y + 8.0, 168.0, 32.0), "改装ツリー ▸", ac, "_panel:renov")
	var door_open: bool = String(m["door"]) == "open"
	_mg_segment(font, Rect2(PAD, y, w, 56.0), "踏み込む", "見送る", door_open, "door", ac)
	y += 64.0

	_stag()
	# ④ 献立デッキ -------------------------------------------------------
	var menu: Array = m["menu"]
	y = _sec(font, y, w, "献立", ac, "%d/%d 皿　タップで出し入れ" % [menu.size(), sim.menu_limit()])
	var settle_top := bot - 276.0
	_mg_deck(font, Rect2(PAD, y, w, settle_top - 16.0 - y), s, menu, taste)

	_stag()
	# ⑤ 今夜の三行精算（この画面の結論。画面最大の文字はここ）-------------
	_mg_settle(font, Rect2(PAD, settle_top, w, 276.0), fc, base, pen, door_open, pn)


## 予報の帯：傾いた黒板に、味の一文字を反転面で叩き込む。
## 客見込みは罰の前後を並べて出す（黙って 8→5 に差し替わらない）。
func _mg_forecast(font: Font, r: Rect2, taste: String, tcol: Color, fc: Dictionary,
		base: Dictionary, pen: bool) -> void:
	var ac := PURPLE
	Kit.slab(self, Rect2(r.position.x + 8.0, r.position.y + 8.0, r.size.x - 8.0, r.size.y),
			Color(ac.r, ac.g, ac.b, 0.85), 12.0)
	Kit.slab(self, r, Color(DS.INK.r, DS.INK.g, DS.INK.b, 0.97), 12.0)
	# 味の一文字（反転面）
	var g := Rect2(r.position.x + 20.0, r.position.y + 16.0, 64.0, 64.0)
	Kit.slab(self, g, tcol, 8.0)
	_txt(font, Vector2(g.position.x + (g.size.x - _tw(font, taste, DS.T_DISPLAY)) * 0.5 + 4.0,
			g.position.y + 52.0), taste, DS.T_DISPLAY, DS.INK)
	var tx := r.position.x + 104.0
	_txt(font, Vector2(tx, r.position.y + 34.0), "今夜の予報", DS.T_MICRO, Color(tcol.r, tcol.g, tcol.b, 0.95))
	_txt(font, Vector2(tx, r.position.y + 68.0), "『%s』が高く売れる" % taste, DS.T_SUB, DS.PAPER)
	# 数値は等幅で大きく（白のみ）。変わったら必ず動く。
	var x1 := r.end.x - 232.0
	_txt(font, Vector2(x1, r.position.y + 34.0), "看板", DS.T_MICRO, DS.TEXT_2)
	_num(font, Vector2(x1, r.position.y + 68.0), "sign", float(sim.sign_total()), DS.T_SUB, DS.PAPER)
	var x2 := r.end.x - 132.0
	_txt(font, Vector2(x2, r.position.y + 34.0), "客見込み", DS.T_MICRO, DS.TEXT_2)
	if pen:
		# 罰の前の数字を取り消し線で残し、赤い減少マークで今の数字へ繋ぐ
		var bx := x2
		bx += Kit.struck(self, font, Vector2(bx, r.position.y + 68.0),
				"%d" % int(base["customers"]), DS.T_BODY, DS.TEXT_MUTE) + 6.0
		_txt(font, Vector2(bx, r.position.y + 68.0), "▼", DS.T_MICRO, DS.DANGER)
		bx += _tw(font, "▼", DS.T_MICRO) + 4.0
		bx += _num(font, Vector2(bx, r.position.y + 68.0), "fc_cust", float(int(fc["customers"])),
				DS.T_SUB, DS.DANGER)
		_txt(font, Vector2(bx + 2.0, r.position.y + 68.0), "人", DS.T_MICRO, DS.TEXT_2)
	else:
		var cw := _num(font, Vector2(x2, r.position.y + 68.0), "fc_cust", float(int(fc["customers"])),
				DS.T_SUB, DS.PAPER)
		_txt(font, Vector2(x2 + cw + 2.0, r.position.y + 68.0), "人", DS.T_MICRO, DS.TEXT_2)


## 切断の罰（今夜だけ効く）。赤い板に、削られた量と削られた売上を書く。
func _mg_penalty(font: Font, r: Rect2, fc: Dictionary, base: Dictionary) -> void:
	Kit.slab(self, r, DS.DANGER, 8.0)
	var ink := DS.on(DS.DANGER)
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	Kit.slab_edge(self, r, Color(1, 1, 1, 0.25 + 0.3 * pulse), 8.0, 1.5)
	draw_string(font, Vector2(r.position.x + 16.0, r.position.y + 23.0),
			"▼ 昨夜の切断 ─ 客足 -40%", HORIZONTAL_ALIGNMENT_LEFT, -1, DS.T_BODY, ink)
	var lost := int(base["gold"]) - int(fc["gold"])
	var tail := "客 %d人 → %d人　売上 -%dG" % [int(base["customers"]), int(fc["customers"]), maxi(lost, 0)]
	draw_string(font, Vector2(r.end.x - _tw(font, tail, DS.T_BODY) - 16.0, r.position.y + 23.0),
			tail, HORIZONTAL_ALIGNMENT_LEFT, -1, DS.T_BODY, ink)


## 店番6枚（3×2）。適性（1軸目）とシナジー＋今夜の純益差（2軸目）を同じ大きさで並べる。
## 「最適」は宣言しない。適性最高／純益最高を別々に示し、判断はプレイヤーへ返す。
func _mg_keepers(font: Font, area: Rect2, m: Dictionary, prof: Dictionary) -> void:
	var ac := PURPLE
	var ids: Array = KuroData.GIRL_ORDER
	var per := 3
	var gap := 8.0
	var cw := (area.size.x - gap * (per - 1)) / float(per)
	var ch := (area.size.y - gap) * 0.5
	var cur := String(m["keeper"])
	var now_p := int(prof.get(cur, 0))
	var best_apt := 0.0
	var best_p := -99999
	for id in ids:
		best_apt = maxf(best_apt, float(KuroData.GIRLS[id]["keeper_apt"]))
		best_p = maxi(best_p, int(prof.get(id, 0)))
	for i in ids.size():
		var id: String = ids[i]
		var g: Dictionary = KuroData.GIRLS[id]
		var r := Rect2(area.position.x + (i % per) * (cw + gap),
				area.position.y + int(i / per) * (ch + gap), cw, ch)
		var active := id == cur
		var apt := float(g["keeper_apt"])
		var apt_best := apt >= best_apt - 0.001
		var p := int(prof.get(id, 0))
		var p_best := p >= best_p
		_begin_sink(r)   # 押されている間はカードごと沈む
		if active:
			Kit.slab(self, Rect2(r.position.x + 5.0, r.position.y + 6.0, r.size.x - 5.0, r.size.y),
					Color(0, 0, 0, 0.72), 8.0)
			Kit.slab(self, r, ac, 8.0)
		else:
			Kit.slab(self, r, Color(0.03, 0.028, 0.05, 0.92), 8.0)
			Kit.slab_edge(self, r, Color(1, 1, 1, 0.16), 8.0, 1.0)
		var fg := DS.on(ac) if active else DS.TEXT
		var sub := Color(fg.r, fg.g, fg.b, 0.72)
		# ── 上段：2つの「最高」を別々のバッジで（片方だけを正解にしない）
		if apt_best:
			var br := Rect2(r.position.x + 8.0, r.position.y + 3.0, 76.0, 22.0)
			Kit.slab(self, br, DS.SUCCESS, 5.0)
			_txt(font, Vector2(br.position.x + 8.0, br.position.y + 17.0), "適性最高", DS.T_MICRO, DS.INK)
		if p_best:
			var br2 := Rect2(r.end.x - 84.0, r.position.y + 3.0, 76.0, 22.0)
			Kit.slab(self, br2, GOLD, 5.0)
			_txt(font, Vector2(br2.position.x + 8.0, br2.position.y + 17.0), "純益最高", DS.T_MICRO, DS.INK)
		# ── 顔・名前
		_draw_icon("res://assets/generated/face/%s/neutral_open.png" % id,
				Rect2(r.position.x + 10.0, r.position.y + 30.0, 44.0, 44.0),
				Color(1, 1, 1, 1.0 if active else 0.85), true)
		_txt(font, Vector2(r.position.x + 62.0, r.position.y + 52.0), String(g["name"]), DS.T_BODY, fg)
		# ── 今夜の純益（この子にしたらいくらになるか／今の子との差）
		var dv := "%dG" % p if active else "%s%dG" % ["+" if p - now_p >= 0 else "-", absi(p - now_p)]
		var dc := fg if active else (DS.SUCCESS if p > now_p else (DS.DANGER if p < now_p else sub))
		_txt(font, Vector2(r.end.x - _tw(font, dv, DS.T_BODY) - 10.0, r.position.y + 52.0), dv, DS.T_BODY, dc)
		# ── 適性（1軸目）
		_txt(font, Vector2(r.position.x + 62.0, r.position.y + 78.0), "適性", DS.T_MICRO, sub)
		var vt := "%d%%" % int(apt * 100.0)
		var vc := (DS.on(ac) if active else DS.SUCCESS) if apt_best else fg
		_txt(font, Vector2(r.position.x + 106.0, r.position.y + 78.0), vt,
				DS.T_SUB if apt_best else DS.T_BODY, vc)
		Kit.bar(self, Rect2(r.position.x + 10.0, r.position.y + 86.0, cw - 20.0, 6.0),
				clampf((apt - 0.6) / 0.9, 0.05, 1.0),
				(DS.INK if active else DS.SUCCESS) if apt_best else
				(Color(DS.INK.r, DS.INK.g, DS.INK.b, 0.8) if active else Color(ac.r, ac.g, ac.b, 0.9)))
		# ── シナジー（2軸目）：全員ぶんを同じ大きさで並べる
		_txt(font, Vector2(r.position.x + 10.0, r.position.y + 108.0), String(g["synergy_desc"]),
				DS.T_MICRO, sub)
		_end_sink()
		_hit(r, "keeper:" + id)


## 直近の仕込み操作と、それが今夜の純益をいくら動かしたか。
## 何も触っていない時は、選んでいる店番のシナジーを出す（帯を空けない）。
func _mg_change(font: Font, r: Rect2, m: Dictionary) -> void:
	var ac := PURPLE
	var fresh := _chg != "" and (_t - _chg_t) < 4.0
	var col := Color(ac.r, ac.g, ac.b, 0.92)
	if fresh and absf(_chg_d) >= 1.0:
		col = DS.SUCCESS if _chg_d > 0.0 else DS.DANGER
	Kit.slab(self, r, col, 8.0)
	var ink := DS.on(col)
	if fresh:
		var k := clampf(1.0 - (_t - _chg_t) / 4.0, 0.0, 1.0)
		Kit.slab_edge(self, r, Color(1, 1, 1, 0.35 * k), 8.0, 1.5)
		draw_string(font, Vector2(r.position.x + 20.0, r.position.y + 23.0), _chg,
				HORIZONTAL_ALIGNMENT_LEFT, -1, DS.T_BODY, ink)
		var d := "純益 %s%dG" % ["+" if _chg_d >= 0.0 else "-", int(absf(_chg_d))]
		if absf(_chg_d) < 1.0:
			d = "純益 変わらず"
		draw_string(font, Vector2(r.end.x - _tw(font, d, DS.T_BODY) - 20.0, r.position.y + 23.0), d,
				HORIZONTAL_ALIGNMENT_LEFT, -1, DS.T_BODY, ink)
	else:
		var kg: Dictionary = KuroData.GIRLS[m["keeper"]]
		draw_string(font, Vector2(r.position.x + 20.0, r.position.y + 23.0),
				"%s ／ %s ＝ %s" % [String(kg["name"]), String(kg["synergy"]), String(kg["synergy_desc"])],
				HORIZONTAL_ALIGNMENT_LEFT, -1, DS.T_BODY, ink)


## 全幅の2択セグメント（選択側だけが面の反転）。
func _mg_segment(font: Font, r: Rect2, a: String, b: String, first: bool, id: String, ac: Color) -> void:
	var half := r.size.x * 0.5
	var labels := [a, b]
	for i in 2:
		var cell := Rect2(r.position.x + i * half, r.position.y, half - (4.0 if i == 0 else 0.0), r.size.y)
		var on := (i == 0) == first
		if on:
			Kit.slab(self, Rect2(cell.position.x + 5.0, cell.position.y + 6.0, cell.size.x - 5.0, cell.size.y),
					Color(0, 0, 0, 0.72), 10.0)
			Kit.slab(self, cell, ac, 10.0)
		else:
			Kit.slab(self, cell, Color(0.03, 0.028, 0.05, 0.88), 10.0)
			Kit.slab_edge(self, cell, Color(1, 1, 1, 0.14), 10.0, 1.0)
		var lbl := String(labels[i])
		var col := DS.on(ac) if on else DS.TEXT_2
		_txt(font, Vector2(cell.position.x + (cell.size.x - _tw(font, lbl, DS.T_SUB)) * 0.5,
				cell.position.y + r.size.y * 0.5 + 9.0), lbl, DS.T_SUB, col)
	_hit(r, id)


## 献立カード（縦型：丸皿アイコン＋料理名＋メタ行）。左端4pxの縦帯＝味。
func _mg_deck(font: Font, area: Rect2, s: Dictionary, menu: Array, taste: String) -> void:
	var ac := PURPLE
	var owned: Array = []
	for rid in KuroData.RECIPES:
		if int(s["recipes"].get(rid, 0)) > 0:
			owned.append(rid)
	if owned.is_empty():
		_txt(font, Vector2(area.position.x + 8.0, area.position.y + 32.0), "レシピがまだ無い。", DS.T_BODY, DS.TEXT_2)
		return
	# 品数に応じて列を決め、端数の行は幅を伸ばして埋める（右側に穴を作らない）
	var per := 2 if owned.size() <= 4 else 3
	var gap := 10.0
	var cw := (area.size.x - gap * (per - 1)) / float(per)
	var rows := int(ceil(owned.size() / float(per)))
	var ch := clampf((area.size.y - gap * (rows - 1)) / float(rows), 76.0, 140.0)
	var max_rows := maxi(int((area.size.y + gap) / (76.0 + gap)), 1)
	var shown := owned.size()
	if rows > max_rows:
		rows = max_rows
		shown = rows * per
		ch = clampf((area.size.y - gap * (rows - 1)) / float(rows), 76.0, 140.0)
	var tall := ch >= 112.0
	var total := mini(shown, owned.size())
	var last_row := int((total - 1) / per)
	var last_n := total - last_row * per
	var last_cw := (area.size.x - gap * (last_n - 1)) / float(last_n)
	for i in total:
		var rid: String = owned[i]
		var rec: Dictionary = KuroData.RECIPES[rid]
		var row := int(i / per)
		# 端数の行はカードを伸ばして幅いっぱいに（無情報の平面を残さない）
		var this_w := cw if row < last_row else last_cw
		var r := Rect2(area.position.x + (i % per) * (this_w + gap),
				area.position.y + row * (ch + gap), this_w, ch)
		var on: bool = rid in menu
		var rc: Color = KuroData.TASTE_COLORS[rec["taste"]]
		var hit: bool = String(rec["taste"]) == taste
		if on:
			Kit.slab(self, Rect2(r.position.x + 5.0, r.position.y + 6.0, r.size.x - 5.0, r.size.y),
					Color(0, 0, 0, 0.72), 8.0)
			Kit.slab(self, r, ac, 8.0)
		else:
			Kit.slab(self, r, Color(0.03, 0.028, 0.05, 0.92), 8.0)
			Kit.slab_edge(self, r, Color(1, 1, 1, 0.16), 8.0, 1.0)
		# 味は枠線ではなく左端の縦帯へ（予報と同じ色＝結びつき）
		Kit.slab(self, Rect2(r.position.x + 4.0, r.position.y + 4.0, 16.0, r.size.y - 8.0), DS.INK, 4.0)
		Kit.slab(self, Rect2(r.position.x + 7.0, r.position.y + 7.0, 10.0, r.size.y - 14.0),
				Color(rc.r, rc.g, rc.b, 1.0 if hit else 0.45), 3.0)
		var fg := DS.on(ac) if on else DS.TEXT
		var sub := DS.on(ac) if on else DS.TEXT_2
		var nm := String(rec["name"])
		var star := int(s["recipes"].get(rid, 1))
		var meta := "☆%d　%dG" % [star, int(rec["base"])]
		var path := "res://assets/generated/food/%s.png" % rid
		var mid := r.position.x + 20.0 + (this_w - 20.0) * 0.5
		if cw >= 280.0:      # 行ごとに型を変えない（列幅で一律に決める）
			# 幅広：皿を左に、名とメタを中、単価を右端に（数値は等幅で大きく）
			var iy := r.position.y + ch * 0.5
			_draw_icon(path, Rect2(r.position.x + 34.0, iy - 36.0, 72.0, 72.0),
					Color(1, 1, 1, 1.0 if on else 0.8), true)
			_txt(font, Vector2(r.position.x + 126.0, iy + 2.0), nm, DS.T_SUB, fg)
			_txt(font, Vector2(r.position.x + 126.0, iy + 28.0),
					"%s ・ ☆%d" % [String(rec["taste"]), star], DS.T_MICRO, sub)
			var pv := "%dG" % int(rec["base"])
			_txt(font, Vector2(r.end.x - _tw(font, pv, DS.T_SUB) - 20.0, iy + 10.0), pv, DS.T_SUB, fg)
		elif tall:
			_draw_icon(path, Rect2(mid - 30.0, r.position.y + 12.0, 60.0, 60.0),
					Color(1, 1, 1, 1.0 if on else 0.8), true)
			_txt(font, Vector2(mid - _tw(font, nm, DS.T_SUB) * 0.5, r.position.y + 102.0), nm, DS.T_SUB, fg)
			_txt(font, Vector2(mid - _tw(font, meta, DS.T_MICRO) * 0.5, r.position.y + 126.0),
					meta, DS.T_MICRO, sub)
		else:
			_draw_icon(path, Rect2(r.position.x + 28.0, r.position.y + (ch - 40.0) * 0.5, 40.0, 40.0),
					Color(1, 1, 1, 1.0 if on else 0.8), true)
			_txt(font, Vector2(r.position.x + 76.0, r.position.y + ch * 0.5), nm, DS.T_BODY, fg)
			_txt(font, Vector2(r.position.x + 76.0, r.position.y + ch * 0.5 + 20.0), meta, DS.T_MICRO, sub)
		if hit:
			var br := Rect2(r.end.x - 54.0, r.position.y + 4.0, 48.0, 20.0)
			Kit.slab(self, br, rc, 5.0)
			_txt(font, Vector2(br.position.x + 8.0, br.position.y + 16.0), "予報", DS.T_MICRO, DS.INK)
		_hit(r, "menu:" + rid)
	if shown < owned.size():
		_txt(font, Vector2(area.position.x + 4.0, area.end.y + 14.0),
				"…他 %d 品" % (owned.size() - shown), DS.T_MICRO, DS.TEXT_2)


## 今夜の三行精算（見込み）。この画面の結論を、画面最大の文字で置く。
## すべての数値は Kit.num で追いかける＝朝の操作が「いくら動いたか」で返ってくる。
func _mg_settle(font: Font, r: Rect2, fc: Dictionary, base: Dictionary, pen: bool,
		door_open: bool, pn: Dictionary) -> void:
	var ac := PURPLE
	var served := int(fc["served"])
	var revenue := int(fc["gold"])
	var cost := served * MAT_COST
	var profit := revenue - cost
	# 見出しの黒板
	var head := Rect2(r.position.x, r.position.y, r.size.x, 48.0)
	Kit.slab(self, Rect2(head.position.x + 7.0, head.position.y + 6.0, head.size.x - 7.0, head.size.y),
			Color(ac.r, ac.g, ac.b, 0.5), 10.0)
	Kit.slab(self, head, Color(DS.INK.r, DS.INK.g, DS.INK.b, 0.97), 10.0)
	Kit.slab(self, Rect2(head.position.x + 8.0, head.position.y, 9.0, head.size.y), ac, 10.0)
	_txt(font, Vector2(head.position.x + 30.0, head.position.y + 34.0), "今夜の三行精算", DS.T_HEAD, DS.PAPER)
	var note := "見込み"
	_txt(font, Vector2(head.end.x - _tw(font, note, DS.T_MICRO) - 20.0, head.position.y + 32.0),
			note, DS.T_MICRO, Color(ac.r, ac.g, ac.b, 0.95))
	# 面
	var body := Rect2(r.position.x, r.position.y + 48.0, r.size.x, r.size.y - 48.0)
	Kit.slab(self, body, Color(0.03, 0.028, 0.05, 0.92), 10.0)
	Kit.hatch(self, body.grow(-6.0), Color(ac.r, ac.g, ac.b, 0.05), 22.0, 7.0)
	var x := body.position.x + 24.0
	# 一行目：客と皿（客は罰を受けていれば赤＋元の値）
	var y1 := body.position.y + 36.0
	# 明細の数字はカウントと拡大だけ（フロートは結論＝純益に集約し、行を汚さない）
	_txt(font, Vector2(x, y1), "客", DS.T_MICRO, DS.TEXT_2)
	var cwid := _num(font, Vector2(x + 28.0, y1), "st_cust", float(int(fc["customers"])), DS.T_SUB,
			DS.DANGER if pen else DS.PAPER, DS.SUCCESS, DS.DANGER, "", false)
	_txt(font, Vector2(x + 32.0 + cwid, y1), "人", DS.T_MICRO, DS.TEXT_2)
	if pen:
		_txt(font, Vector2(x + 52.0 + cwid, y1), "▼%d" % maxi(int(base["customers"]) - int(fc["customers"]), 0),
				DS.T_MICRO, DS.DANGER)
	var x2 := x + 148.0
	_txt(font, Vector2(x2, y1), "出す皿", DS.T_MICRO, DS.TEXT_2)
	var swid := _num(font, Vector2(x2 + 76.0, y1), "st_served", float(served), DS.T_SUB, DS.PAPER,
			DS.SUCCESS, DS.DANGER, "", false)
	_txt(font, Vector2(x2 + 80.0 + swid, y1), "皿", DS.T_MICRO, DS.TEXT_2)
	var x3 := body.end.x - 148.0
	_txt(font, Vector2(x3, y1), "仕込み", DS.T_MICRO, DS.TEXT_2)
	_num(font, Vector2(x3 + 76.0, y1), "st_prep", float(int(fc["prep"])), DS.T_SUB, DS.TEXT,
			DS.SUCCESS, DS.DANGER, "", false)
	# 二行目：売上と原価
	var y2 := y1 + 36.0
	_txt(font, Vector2(x, y2), "売上", DS.T_MICRO, DS.TEXT_2)
	_txt(font, Vector2(x + 52.0, y2), "+", DS.T_MICRO, DS.TEXT_2)
	var rw := _num(font, Vector2(x + 66.0, y2), "st_rev", float(revenue), DS.T_SUB, DS.PAPER,
			GOLD, DS.DANGER, "G", false)
	_txt(font, Vector2(x + 68.0 + rw, y2), "G", DS.T_MICRO, DS.TEXT_2)
	_txt(font, Vector2(x2, y2), "原価", DS.T_MICRO, DS.TEXT_2)
	_txt(font, Vector2(x2 + 52.0, y2), "-", DS.T_MICRO, DS.DANGER)
	var cw2 := _num(font, Vector2(x2 + 66.0, y2), "st_cost", float(cost), DS.T_SUB, DS.DANGER,
			DS.DANGER, DS.SUCCESS, "G", false)
	_txt(font, Vector2(x2 + 68.0 + cw2, y2), "G", DS.T_MICRO, DS.DANGER)
	_txt(font, Vector2(x3, y2), "単価", DS.T_MICRO, DS.TEXT_2)
	var uw := _num(font, Vector2(x3 + 66.0, y2), "st_unit", float(int(revenue / float(maxi(served, 1)))),
			DS.T_SUB, DS.TEXT, GOLD, DS.DANGER, "G", false)
	_txt(font, Vector2(x3 + 68.0 + uw, y2), "G", DS.T_MICRO, DS.TEXT_2)
	# 三行目：純益（面の反転・画面最大）。旧値→新値をカウントし、差分を上へ流す。
	var pcol := ac if profit >= 0 else DS.DANGER
	var slab := Rect2(body.position.x + 8.0, y2 + 20.0, body.size.x - 16.0, 76.0)
	# 待機中の生気はこの画面で1箇所だけ。結論（純益）が静かに脈を打つ。
	# 常時揺らさず、心拍の瞬間だけ下敷きの光がふくらむ。
	var beat := Kit.heartbeat(_t)
	Kit.spot(self, slab.get_center(), slab.size.x * 0.5, pcol, 0.05 + 0.13 * beat)
	Kit.slab(self, Rect2(slab.position.x + 7.0, slab.position.y + 7.0, slab.size.x - 7.0, slab.size.y),
			Color(0, 0, 0, 0.75), 12.0)
	Kit.slab(self, slab, pcol, 12.0)
	var pink := DS.on(pcol)
	_txt(font, Vector2(slab.position.x + 26.0, slab.position.y + 34.0), "純益", DS.T_SUB, pink)
	_txt(font, Vector2(slab.position.x + 26.0, slab.position.y + 60.0),
			"浮上したら手元に残る", DS.T_MICRO, Color(pink.r, pink.g, pink.b, 0.8))
	var shown_p := int(round(float(pn["v"])))
	var pv := "%s%dG" % ["+" if shown_p >= 0 else "-", absi(shown_p)]
	var ppos := Vector2(slab.end.x - _tw(font, pv, DS.T_DISPLAY) - 32.0, slab.position.y + 56.0)
	Kit.num_draw(self, font, ppos, pv, DS.T_DISPLAY, pink, float(pn["pop"]))
	var pd := float(pn["d"])
	if absf(pd) >= 1.0:
		Kit.float_add(_floats, ppos + Vector2(0.0, -46.0),
				"%s%dG" % ["+" if pd > 0.0 else "-", int(absf(pd))],
				DS.SUCCESS if pd > 0.0 else DS.DANGER, _t)
	# 補足2行（素材切れ・扉の方針）
	var ny := slab.end.y + 24.0
	var short_n := int(fc["short"])
	var out: Array = fc["out"]
	var names: Array = []
	for ing in out:
		names.append(String(KuroData.ING_NAMES.get(ing, ing)))
	if short_n > 0:
		_txt(font, Vector2(x, ny), "▲ 素材切れで %d 皿を売り逃す（%s）" % [
				short_n, "・".join(names) if not names.is_empty() else "在庫不足"], DS.T_MICRO, DS.DANGER)
	elif not names.is_empty():
		_txt(font, Vector2(x, ny), "● 今夜で %s を使い切る。明日の仕入れが要る。" % "・".join(names),
				DS.T_MICRO, DS.TEXT_2)
	else:
		_txt(font, Vector2(x, ny), "● 素材は足りている。仕込みも客数に届く。", DS.T_MICRO, DS.SUCCESS)
	_txt(font, Vector2(x, ny + 24.0), ("● 扉：踏み込む＝箱50% / 素材+3〜5が30% / 罠20%"
			if door_open else "● 扉：見送る＝取り分は増えないが、誰も削られない"), DS.T_MICRO, DS.TEXT_2)


# ── 工房（Cube: 装備加工）────────────────────────────────────────────────────

func _draw_workshop(font: Font, sz: Vector2) -> void:
	var s: Dictionary = sim.state
	var ac := CYAN                     # この画面の識別色
	var w := sz.x - M * 2.0
	var top := HEADER_H
	var bot := sz.y - FOOTER_H
	Kit.hatch(self, Rect2(0, top, sz.x, bot - top), Color(ac.r, ac.g, ac.b, 0.05), 26.0, 9.0)
	var y := top + 12.0

	_stag()
	# ① 資源バンド（倉庫・バッグ・廃材）----------------------------------
	_wk_band(font, Rect2(M, y, w, 96.0), s, ac)
	y += 108.0

	var list: Array = s["storage"] if _work_view == "storage" else s["inventory"]
	var where := "倉庫" if _work_view == "storage" else "バッグ"

	_stag()
	# ② 見る場所（倉庫／バッグ）------------------------------------------
	y = _sec(font, y, w, "装備", ac, "%s %d 件　タップで選ぶ" % [where, list.size()])
	_segment2(font, Rect2(M, y, w, 52.0), "倉庫", "バッグ", _work_view == "storage",
			"_work:storage", "_work:bag", ac)
	y += 64.0

	_stag()
	# ③ 一括操作 ---------------------------------------------------------
	_wk_bulk(font, Rect2(M, y, w, 48.0), s)
	y += 60.0

	# ⑤ 詳細は下端固定。必要な高さを先に決め、残りを一覧に配る（縦を使い切る）
	var det_min := 240.0
	if _work_view == "storage":
		det_min = 300.0
		if not list.is_empty():
			var head_it: Dictionary = list[0]
			for it0 in list:
				if int(it0["id"]) == _work_item_id:
					head_it = it0
			if SimItems.socket_capacity(int(head_it["grade"])) > 0:
				det_min = 424.0
	var gap := 10.0
	var avail := bot - 12.0 - y
	var n_show := mini(list.size(), 6)
	var row_h := 0.0
	while n_show > 1:
		row_h = (avail - det_min - 16.0 - gap * (n_show - 1)) / float(n_show)
		if row_h >= 64.0:
			break
		n_show -= 1
	if n_show == 1:
		row_h = clampf(avail - det_min - 16.0, 64.0, 112.0)
	row_h = clampf(row_h, 64.0, 112.0)
	var used := 0.0
	if n_show > 0:
		used = row_h * n_show + gap * (n_show - 1)

	_stag()
	# ④ 装備一覧 ---------------------------------------------------------
	# 選択は先に決める（未選択なら先頭が選ばれている＝行にも枠が出る）
	var sel_id := _work_item_id
	var has_sel := false
	for it0 in list:
		if int(it0["id"]) == sel_id:
			has_sel = true
	if not has_sel and not list.is_empty():
		sel_id = int((list[0] as Dictionary)["id"])
	var selected := {}
	var selected_idx := -1
	for i in n_show:
		var it: Dictionary = list[i]
		var iid := int(it["id"])
		if iid == sel_id:
			selected = it
			selected_idx = i
		_wk_row(font, Rect2(M, y + i * (row_h + gap), w, row_h), it, iid == sel_id)
	if list.is_empty():
		var er := Rect2(M, y, w, maxf(used, 96.0))
		_panel(er, Color(0.05, 0.05, 0.08, 0.86), Color(0.4, 0.42, 0.5, 0.4))
		_txt(font, Vector2(er.position.x + 24.0, er.position.y + er.size.y * 0.5 + 6.0),
				"%s は空。潜航・交易船・箱で装備が入る。" % where, DS.T_BODY, TEXT_DIM)
		used = er.size.y
	elif n_show < list.size():
		_txt(font, Vector2(M + 8.0, y + used - 6.0), "…他 %d 件" % (list.size() - n_show),
				DS.T_MICRO, TEXT_DIM)

	var det_top := y + used + 16.0
	if selected.is_empty() and not list.is_empty():
		selected = list[0]
		selected_idx = 0
	_stag()
	_wk_detail(font, Rect2(M, det_top, w, bot - 12.0 - det_top), selected, selected_idx, _work_view, ac)


## 資源バンド。倉庫・バッグ・廃材は「分解した瞬間に跳ねる」生きた数値で置く。
func _wk_band(font: Font, r: Rect2, s: Dictionary, ac: Color) -> void:
	_panel(r, Color(0.045, 0.06, 0.08, 0.94), Color(ac.r, ac.g, ac.b, 0.4))
	var y := r.position.y + 46.0
	var x := r.position.x + 24.0
	var xw := _stat(font, Vector2(x, y), "倉庫", "wk_store",
			float((s["storage"] as Array).size()), "/%d" % KuroData.STORAGE_MAX, ac)
	x = maxf(xw + 40.0, r.position.x + 240.0)
	xw = _stat(font, Vector2(x, y), "バッグ", "wk_bag",
			float((s["inventory"] as Array).size()), "/%d" % KuroData.BAG_MAX, ac)
	x = maxf(xw + 40.0, r.position.x + 460.0)
	_stat(font, Vector2(x, y), "廃材", "wk_scrap", float(int(s["scrap"])), "", GREEN)
	_txt(font, Vector2(r.position.x + 24.0, r.position.y + 76.0),
			"Cube ＝ 倉庫・分解・合成・刻印・装飾をここに集約する。", DS.T_MICRO, TEXT_DIM)


## 一括操作。見る場所によって並びが変わる（同じ大きさの板で揃える）。
func _wk_bulk(font: Font, r: Rect2, s: Dictionary) -> void:
	var gap := 10.0
	if _work_view == "storage":
		var cw := (r.size.x - gap) * 0.5
		_btn(font, Rect2(r.position.x, r.position.y, cw, r.size.y), "同格3つを合成", CYAN,
				"synth_storage")
		_btn(font, Rect2(r.position.x + cw + gap, r.position.y, cw, r.size.y), "不要をまとめて分解",
				DS.DANGER, "bulk_salvage_storage")
	else:
		var cw2 := (r.size.x - gap * 2.0) / 3.0
		_btn(font, Rect2(r.position.x, r.position.y, cw2, r.size.y), "全て倉庫へ", CYAN, "bag_all",
				not (s["inventory"] as Array).is_empty())
		_btn(font, Rect2(r.position.x + cw2 + gap, r.position.y, cw2, r.size.y), "合成", CYAN,
				"synth_bag")
		_btn(font, Rect2(r.position.x + (cw2 + gap) * 2.0, r.position.y, cw2, r.size.y), "不要分解",
				DS.DANGER, "bulk_salvage_bag")


## 一覧の1行。等級色は「稀少さ」という事実なので残す（有彩色の追加ではない）。
func _wk_row(font: Font, r: Rect2, it: Dictionary, active: bool) -> void:
	var grade := int(it["grade"])
	var col: Color = KuroData.equip_grade_color(grade)
	var pv := _begin_sink(r)
	_panel(r, Color(0.06, 0.065, 0.09, 0.95), col if active else Color(col.r, col.g, col.b, 0.38),
			2.0 if active else 1.0)
	Kit.slab(self, Rect2(r.position.x + 6.0, r.position.y + 6.0, 8.0, r.size.y - 12.0),
			Color(col.r, col.g, col.b, 0.95 if active else 0.5), 3.0)
	var mid := r.position.y + r.size.y * 0.5
	var tx := r.position.x + 28.0
	if _draw_icon("res://assets/generated/equip/%s.png" % String(it["slot"]),
			Rect2(r.position.x + 26.0, mid - 20.0, 40.0, 40.0), col):
		tx = r.position.x + 78.0
	_txt(font, Vector2(tx, mid - 2.0), SimItems.display_name(it), DS.T_BODY, col)
	_txt(font, Vector2(tx, mid + 22.0), "%s ・ score %.1f" % [
			String(SimItems.GRADES[grade]["name"]), float(it["score"])], DS.T_MICRO, TEXT_DIM)
	var af := SimItems.affix_text(it)
	if af != "":
		_txt(font, Vector2(r.end.x - _tw(font, af, DS.T_MICRO) - 20.0, mid + 6.0), af,
				DS.T_MICRO, TEXT_DIM)
	_end_sink(pv)
	_hit(r, "_selitem:%d" % int(it["id"]))


## 選択中の装備の詳細と加工。下端固定の結論ブロック（経営の三行精算と同じ置き方）。
## 操作は下から積む＝上に空きが出ても、押す場所は必ず同じ高さに座る。
func _wk_detail(font: Font, r: Rect2, item: Dictionary, idx: int, source: String, ac: Color) -> void:
	if item.is_empty():
		var body0 := _conc(font, r, "装備なし", "", ac)
		_txt(font, Vector2(body0.position.x + 24.0, body0.position.y + 44.0),
				"潜航・交易船・箱で装備が入る。", DS.T_SUB, TEXT_DIM)
		_txt(font, Vector2(body0.position.x + 24.0, body0.position.y + 78.0),
				"ここで刻印（廃材で付け直し）・分解・合成・装飾ができる。", DS.T_MICRO, TEXT_DIM)
		return
	var grade := int(item["grade"])
	var col: Color = KuroData.equip_grade_color(grade)
	var body := _conc(font, r, SimItems.display_name(item),
			"score %.1f" % float(item["score"]), col)
	var x := body.position.x + 24.0
	var sum: Dictionary = SimItems.stat_summary(item)
	_txt(font, Vector2(x, body.position.y + 32.0), "%s ／ %s ／ base %.1f" % [
			String(SimItems.GRADES[grade]["name"]), String(SimItems.SLOTS[item["slot"]]["name"]),
			float(sum["base"])], DS.T_MICRO, TEXT_DIM)
	# ステの内訳（2段×3列。段は本文サイズ1つだけ）
	var cols := (body.size.x - 48.0) / 3.0
	var rows := [[["攻", "atk"], ["体", "hp"], ["速", "spd"]], [["金", "gold"], ["材", "mat"], ["会", "crit"]]]
	for ri in 2:
		for ci in 3:
			var e: Array = rows[ri][ci]
			var v := int(sum[e[1]])
			var px := x + ci * cols
			var py := body.position.y + 68.0 + ri * 30.0
			_txt(font, Vector2(px, py), String(e[0]), DS.T_MICRO, TEXT_DIM)
			_txt(font, Vector2(px + 34.0, py), "+%d%%" % v, DS.T_BODY, TEXT if v > 0 else TEXT_DIM)
	# ── 操作は下から積む
	var by := body.end.y - 12.0
	if source == "bag":
		var cw := (body.size.x - 48.0 - 10.0) * 0.5
		_btn(font, Rect2(x, by - 56.0, cw, 56.0), "倉庫へ", CYAN, "bag_store:%d" % int(item["id"]))
		_btn(font, Rect2(x + cw + 10.0, by - 56.0, cw, 56.0), "分解", DS.DANGER,
				"salvage_bag:%d" % int(item["id"]))
		return
	var cap := SimItems.socket_capacity(grade)
	var sockets: Array = item.get("sockets", [])
	if cap > 0:
		# 装飾ソケット（英雄以上だけが持つ）
		_btn(font, Rect2(x, by - 52.0, (body.size.x - 48.0 - 10.0) * 0.5, 52.0), "嵌める", GREEN,
				"socket_storage:%d:%s" % [idx, _work_gem], cap > sockets.size())
		_btn(font, Rect2(x + (body.size.x - 48.0 + 10.0) * 0.5, by - 52.0,
				(body.size.x - 48.0 - 10.0) * 0.5, 52.0), "外す", Color(0.55, 0.56, 0.62),
				"remove_gem:%d:0" % idx, not sockets.is_empty())
		by -= 60.0
		var gems: Array = KuroData.SOCKET_GEMS.keys()
		var gw := (body.size.x - 48.0 - 30.0) / 4.0
		for i in mini(gems.size(), 4):
			var gem: String = gems[i]
			var on := gem == _work_gem
			_btn(font, Rect2(x + i * (gw + 10.0), by - 48.0, gw, 48.0),
					String(KuroData.SOCKET_GEMS[gem]["name"]).substr(0, 4),
					GOLD if on else Color(0.55, 0.56, 0.62), "_selgem:%s" % gem, not on)
		by -= 56.0
		_txt(font, Vector2(x, by - 6.0), "装飾ソケット %d/%d" % [sockets.size(), cap], DS.T_MICRO, TEXT_DIM)
		by -= 22.0
	# 装備先（6人。誰に着けるかは1列で見せる）
	var ids: Array = KuroData.GIRL_ORDER
	var bw := (body.size.x - 48.0 - 40.0) / 6.0
	for i in mini(ids.size(), 6):
		var gid: String = ids[i]
		_btn(font, Rect2(x + i * (bw + 8.0), by - 52.0, bw, 52.0), String(KuroData.GIRLS[gid]["name"]),
				KuroData.GIRLS[gid]["color"], "equip_storage:%d:%s" % [int(item["id"]), gid])
	by -= 60.0
	_txt(font, Vector2(x, by - 6.0), "装備先", DS.T_MICRO, TEXT_DIM)
	by -= 22.0
	# 刻印・分解
	var aw := (body.size.x - 48.0 - 10.0) * 0.5
	_btn(font, Rect2(x, by - 56.0, aw, 56.0), "刻印（廃材%d）" % SimItems.REROLL_COST, CYAN,
			"reroll_storage:%d" % int(item["id"]), int(sim.state["scrap"]) >= SimItems.REROLL_COST)
	_btn(font, Rect2(x + aw + 10.0, by - 56.0, aw, 56.0), "分解", DS.DANGER,
			"salvage_storage:%d" % int(item["id"]))


# ── 経営サブビュー（改装ツリー・マップ）──────────────────────────────────────

func _draw_renov(font: Font, sz: Vector2) -> void:
	var s: Dictionary = sim.state
	var ac := PURPLE
	var w := sz.x - M * 2.0
	var top := HEADER_H
	var bot := sz.y - FOOTER_H
	Kit.hatch(self, Rect2(0, top, sz.x, bot - top), Color(ac.r, ac.g, ac.b, 0.05), 26.0, 9.0)
	var y := top + 12.0
	_btn(font, Rect2(M, y, 176.0, 44.0), "← 仕込みへ", ac, "_panel:management")
	_txt(font, Vector2(M + 192.0, y + 30.0), "ゴールドで解放・隣接から伸ばす", DS.T_MICRO, TEXT_DIM)
	y += 56.0

	# 下端固定：改装の効き目（この画面の結論）
	var conc_h := 200.0
	var conc_top := bot - 12.0 - conc_h

	# ツリーは残りの領域いっぱいに置く。節点は方向を持たない＝円のまま中央に組む。
	var area := Rect2(M, y, w, maxf(conc_top - 16.0 - y, 320.0))
	var nodes: Dictionary = KuroData.RENOV_NODES
	var cell := minf(104.0, minf((area.size.x - 76.0) / 6.0, (area.size.y - 76.0) / 6.0))
	var rad := clampf(cell * 0.34, 22.0, 34.0)
	var ox := area.position.x + area.size.x * 0.5
	var oy := area.position.y + area.size.y * 0.5

	# 解放の瞬間を捕まえる（一覧が書き換わるだけ、にしない）
	var first_pass := not _own_renov.has("__seen")
	for nid in nodes:
		var had: bool = bool(_own_renov.get(nid, false))
		var has: bool = nid in s["renov"]
		_own_renov[nid] = has
		if has and not had and not first_pass:
			_burst[nid] = _t
	_own_renov["__seen"] = true

	_stag()
	# 接続線（prev → node）。解放直後は前提ノードから光が流れて「線が繋がる」。
	for nid in nodes:
		var node: Dictionary = nodes[nid]
		var np: Array = node["pos"]
		var to := Vector2(ox + float(np[0]) * cell, oy + float(np[1]) * cell)
		for p in node["prev"]:
			var pp: Array = nodes[p]["pos"]
			var fr := Vector2(ox + float(pp[0]) * cell, oy + float(pp[1]) * cell)
			var owned_link: bool = (nid in s["renov"]) and (p in s["renov"])
			var k := -1.0
			if _burst.has(nid) and owned_link:
				k = (_t - float(_burst[nid])) / Kit.BURST_LIFE
			Kit.wire(self, fr, to, ac, owned_link, k)

	# ノード（円＝ツリーの節点。値札は円の外へ出し、字は本文の段のまま置く）
	for nid in nodes:
		var node: Dictionary = nodes[nid]
		var np: Array = node["pos"]
		var c := Vector2(ox + float(np[0]) * cell, oy + float(np[1]) * cell)
		var is_owned: bool = nid in s["renov"]
		var avail: bool = sim.renov_available(nid)
		var can: bool = avail and int(s["gold"]) >= int(node["cost"])
		var col := GREEN if is_owned else (GOLD if can else (ac if avail else Color(0.4, 0.4, 0.46)))
		var r := Rect2(c - Vector2(rad, rad), Vector2(rad * 2.0, rad * 2.0))
		_round_panel(r, Color(col.r * 0.16, col.g * 0.16, col.b * 0.2, 0.96), col, rad,
				2.0 if (is_owned or avail) else 1.0)
		var lit := is_owned or avail
		var has_icon := _draw_icon("res://assets/generated/renov/%s.png" % nid,
				Rect2(c.x - rad * 0.62, c.y - rad * 0.66, rad * 1.24, rad * 1.24),
				Color(1, 1, 1, 1.0 if lit else 0.4))
		if not has_icon:
			var nm := String(node["name"]).substr(0, 3)
			_txt(font, Vector2(c.x - _tw(font, nm, DS.T_MICRO) * 0.5, c.y + 6.0), nm, DS.T_MICRO,
					TEXT if lit else TEXT_DIM)
		# 値札は円の下（円の中に数字を押し込んで字を潰さない）
		if is_owned:
			_txt(font, Vector2(c.x - _tw(font, "済", DS.T_MICRO) * 0.5, c.y + rad + 20.0), "済",
					DS.T_MICRO, GREEN)
		elif int(node["cost"]) > 0:
			var cs := "%dG" % int(node["cost"])
			_txt(font, Vector2(c.x - _tw(font, cs, DS.T_MICRO) * 0.5, c.y + rad + 20.0), cs,
					DS.T_MICRO, GOLD if can else TEXT_DIM)
		# 今買えるノードは呼吸する（押せる場所が黙っていない）
		if can:
			Kit.spot(self, c, rad * 1.9, GOLD, 0.10 + 0.10 * Kit.heartbeat(_t))
		# 解放の瞬間：光の輪が拡がる
		if _burst.has(nid):
			var bk := (_t - float(_burst[nid])) / Kit.BURST_LIFE
			if bk >= 1.0:
				_burst.erase(nid)
			else:
				Kit.burst(self, c, rad, GREEN, bk)
		if avail:
			_hit(r, "renov:" + nid)

	_stag()
	_rv_ledger(font, Rect2(M, conc_top, w, conc_h), ac)


## 改装の効き目（この画面の結論）。解放したらここが跳ねて差分が流れる。
func _rv_ledger(font: Font, r: Rect2, ac: Color) -> void:
	var body := _conc(font, r, "改装の効き目", "いま効いている分", ac)
	var x := body.position.x + 24.0
	var y1 := body.position.y + 36.0
	_stat(font, Vector2(x, y1), "攻", "renov_atk", sim.renov_bonus("atk") * 100.0, "%")
	_stat(font, Vector2(x + 152.0, y1), "HP", "renov_hp", sim.renov_bonus("hp") * 100.0, "%")
	_stat(font, Vector2(x + 304.0, y1), "金", "renov_gold", sim.renov_bonus("gold") * 100.0, "%", GOLD)
	_stat(font, Vector2(x + 456.0, y1), "看板", "renov_sign", float(sim.sign_total()), "")
	var y2 := y1 + 38.0
	_stat(font, Vector2(x, y2), "献立枠", "renov_menu", float(sim.menu_limit()), "皿")
	_stat(font, Vector2(x + 210.0, y2), "技枠", "renov_slot", float(sim.skill_slots()), "")
	_stat(font, Vector2(x + 380.0, y2), "所持金", "renov_g", float(int(sim.state["gold"])), "G", GOLD)
	_strip(font, Rect2(body.position.x + 12.0, body.end.y - 54.0, body.size.x - 24.0, 42.0),
			"緑＝解放済 ／ 金＝今買える ／ 紫＝前提達成 ／ 灰＝未開放", ac)


# ── フッター・トースト ────────────────────────────────────────────────────────

## フッターナビ。選択インジケータは瞬間移動させず、隣のセルへ滑って（少し行き過ぎて）座る。
func _draw_footer(font: Font, sz: Vector2) -> void:
	var fy := sz.y - FOOTER_H
	draw_rect(Rect2(0, fy, sz.x, FOOTER_H), Color(0.03, 0.03, 0.06, 0.97))
	draw_rect(Rect2(0, fy, sz.x, 1.5), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.55))
	var n := NAV.size()
	var cw := sz.x / float(n)
	# 選択セルの位置と色を先に決め、追従値を1つだけ引く（描くのはセルの下ではなく上）
	var ai := 0
	for i in n:
		var nid := String((NAV[i] as Dictionary)["id"])
		if nid == panel or (panel == "renov" and nid == "management"):
			ai = i
			break
	var acol: Color = (NAV[ai] as Dictionary)["col"]
	var slide: Dictionary = Kit.nav_slide(_nav, cw * ai, acol, _t)
	var ix := float(slide["x"])
	var icol: Color = slide["col"]
	# 走っている間は少し伸びる（速度が形に出る＝ただの瞬間移動にしない）
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
		# 文字の色は「インジケータがどれだけ自分の上に来ているか」で混ぜる＝色も滑る
		var near := clampf(1.0 - absf(ix - x0) / cw, 0.0, 1.0)
		var gcol := Color(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.9).lerp(col, Kit.out_cubic(near))
		var cx := x0 + cw * 0.5
		var glyph := String(e["icon"])
		var gy := fy + 30.0 - near * 2.0   # 選ばれている側だけ1〜2px持ち上がる
		_txt(font, Vector2(cx - _tw(font, glyph, DS.T_SUB) * 0.5, gy), glyph, DS.T_SUB, gcol)
		var label := String(e["label"])
		_txt(font, Vector2(cx - _tw(font, label, DS.T_MICRO) * 0.5, fy + 50), label, DS.T_MICRO, gcol)


## トースト。出る時は下から突き上げて行き過ぎ、消える時は落として短く消す。
func _draw_toast(font: Font, sz: Vector2) -> void:
	if _toast_t <= 0.0 or _toast == "":
		return
	var enter := Kit.out_back(_toast_age / 0.26, 2.4)   # 出：行き過ぎて座る
	var exit_k := Kit.in_cubic(1.0 - clampf(_toast_t / 0.32, 0.0, 1.0))  # 去：加速して落ちる
	var a := clampf(_toast_age / 0.12, 0.0, 1.0) * (1.0 - exit_k)
	if a <= 0.001:
		return
	var dy := (1.0 - enter) * 44.0 + exit_k * 22.0
	var w := _tw(font, _toast, DS.T_BODY) + 40
	var r := Rect2((sz.x - w) * 0.5, sz.y - FOOTER_H - 60 + dy, w, 40)
	Kit.slab(self, r, Color(DS.INK.r, DS.INK.g, DS.INK.b, 0.95 * a), 10.0)
	Kit.slab_edge(self, r, Color(PINK.r, PINK.g, PINK.b, 0.8 * a), 10.0, 2.0)
	_txt(font, Vector2(r.position.x + 22, r.position.y + 27), _toast, DS.T_BODY, Color(TEXT.r, TEXT.g, TEXT.b, a))
