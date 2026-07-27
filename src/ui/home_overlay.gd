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

# バンタ（掛け合い）設定
const HOME_CAST := ["mil", "yuzuki", "muu", "kiriko", "doctor", "nurse"]
const BANTER_INTERVAL := 6.0   # 秒：次のセリフまでのインターバル
const EXCHANGE_STEP  := 3.2    # 秒：掛け合いの1行表示時間

const STRIP_H := 60.0   # 最下部 HD-2D フィールド帯の高さ（FieldStrip と一致させる）
const FOOTER_H := 58.0   # 最下部フッターナビバーの高さ（旧版のボトムタブを踏襲）

# 各主要機能へのフッターナビ（旧 main_legacy の 店/メンバー/工房/市場/経営 を踏襲）。
# id は main.gd の _on_home_action(id) に届く。
const NAV := [
	{"id": "home",       "icon": "家", "label": "ホーム",   "col": CYAN},
	{"id": "member",     "icon": "仲", "label": "メンバー", "col": PINK},
	{"id": "market",     "icon": "市", "label": "市場",     "col": GOLD},
	{"id": "management", "icon": "店", "label": "経営",     "col": PURPLE},
	{"id": "workshop",   "icon": "工", "label": "工房",     "col": CYAN},
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
var _banter_t   := 0.0
var _banter_q: Array = []
var _banter_rng := RandomNumberGenerator.new()


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
			action_pressed.emit(String(h["id"]))
			accept_event()
			return


func _hit(rect: Rect2, id: String) -> void:
	_hits.append({"rect": rect, "id": id})


## ホームのVN窓にバンタ（掛け合い/独り言）を1行進める。
## _banter_q が空なら新しいセリフ/掛け合いをピック。
func _advance_banter() -> void:
	if not _banter_q.is_empty():
		var ln: Array = _banter_q.pop_front()
		var gid := String(ln[0])
		speaker = String((KuroData.GIRLS.get(gid, {}) as Dictionary).get("name", gid))
		line = String(ln[1])
		return
	# 30% 確率で掛け合い、70% で独り言
	if _banter_rng.randf() < 0.3:
		var ex := Banter.pick_exchange(HOME_CAST, _banter_rng)
		if not ex.is_empty():
			# Array(x) は参照をそのまま返すので duplicate 必須
			# （const の掛け合いデータに pop_front すると Nil が返り続ける）
			_banter_q = (ex["lines"] as Array).duplicate()
			_advance_banter()
			return
	var pick := Banter.pick("idle", HOME_CAST, _banter_rng)
	if pick.is_empty():
		return
	var gid := String(pick["girl"])
	speaker = String((KuroData.GIRLS.get(gid, {}) as Dictionary).get("name", gid))
	line = String(pick["text"])


func _panel(rect: Rect2, bg: Color, border: Color, radius := 10.0, bw := 1.5) -> void:
	Kit.panel(self, rect, bg, border, radius, bw)


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
	_prep_card(font, sz, vy0 - 70 - 10)   # 朝の仕込みカード（CTAの直上）
	var cta := Rect2(sz.x * 0.5 - 145, vy0 - 70, 290, 56)
	_hit(cta, "pomodoro")
	var pulse := 0.5 + 0.5 * sin(_t * 2.5)
	Kit.cta(self, cta, Color(PINK.r * 0.22, PINK.g * 0.16, PINK.b * 0.24, 0.96), PINK, pulse)
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

	# ===== 最下部：フィールドへの導線 =====
	# 以前はここに 168px の HD-2D フィールド帯（FieldStrip）を敷いていたが、
	# 実機では一度も合成されず「黒い帯」のままだったので高さを詰めた。
	# フィールドへは店先の探索ポータル（右）から入る。
	var fy := sz.y - STRIP_H
	draw_rect(Rect2(0, fy, sz.x, 2), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.6))

	# ===== 最下部：各主要機能へのフッターナビ =====
	_footer(font, sz)
	Kit.ripples(self, _ripples, _t)


## 朝の仕込みカード：予報・店番・扉・献立と「今夜の見込み」を出撃前に見せる。
## 店番と扉はその場でタップ変更（3タップの儀式）、献立は経営パネルへ。
## デイブザダイバーの「今日の獲物が今夜の品書き」——因果を潜る前に提示する。
func _prep_card(font: Font, sz: Vector2, y_bottom: float) -> void:
	if sim == null:
		return
	var h := 96.0
	var r := Rect2(16, y_bottom - h, sz.x - 32, h)
	_panel(r, Color(0.04, 0.04, 0.08, 0.86), Color(GOLD.r, GOLD.g, GOLD.b, 0.4), 12)
	var fc: Dictionary = sim.forecast_night()
	var m: Dictionary = sim.state["morning"]
	# 見出し＋予報（右上）
	_txt(font, Vector2(r.position.x + 14, r.position.y + 22), "今日の仕込み", 13, GOLD)
	var fst := "予報『%s』" % String(fc["forecast"])
	var fw := font.get_string_size(fst, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	_txt(font, Vector2(r.end.x - fw - 14, r.position.y + 22), fst, 14, CYAN)
	# 行1：店番／扉（タップで変更）＋献立（タップで経営へ）
	var y1 := r.position.y + 30
	var x := r.position.x + 12
	var keeper := String(m["keeper"])
	var kname := String((KuroData.GIRLS.get(keeper, {}) as Dictionary).get("name", keeper))
	x = _chip(font, Vector2(x, y1), "店番 %s ▸" % kname, PINK, "keeper_next")
	var door_open: bool = String(m["door"]) == "open"
	x = _chip(font, Vector2(x, y1), "扉 %s ▸" % ("開ける" if door_open else "見送る"),
			CYAN if door_open else TEXT_DIM, "door")
	var menu: Array = m["menu"]
	x = _chip(font, Vector2(x, y1), "献立 %d品 ▸" % menu.size(), PURPLE, "management")
	# 行2：見込み（客・皿・金）と売り逃し警告
	var y2 := r.position.y + 82
	var line2 := "見込み  客%d・%d皿・約%dG" % [int(fc["customers"]), int(fc["served"]), int(fc["gold"])]
	_txt(font, Vector2(r.position.x + 14, y2), line2, 15, TEXT)
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
		var ww := font.get_string_size(warn, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var wr := Rect2(r.end.x - ww - 22, y2 - 18, ww + 16, 26)
		if goto_fl >= 0:
			_hit(wr, "restock:%d" % goto_fl)   # タップ＝その階を選択してマップへ
		_txt(font, Vector2(wr.position.x + 8, y2), warn, 14, Color(1.0, 0.5, 0.45))
	_hit(r, "prep_card")   # 余白タップは経営パネルへ（上の個別チップが優先）


## 仕込みカードの小チップを1つ描き、次のX座標を返す。
func _chip(font: Font, pos: Vector2, label: String, col: Color, id: String) -> float:
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 20
	var cr := Rect2(pos.x, pos.y, w, 30)
	_hit(cr, id)
	_panel(cr, Color(col.r * 0.16, col.g * 0.14, col.b * 0.18, 0.9), Color(col.r, col.g, col.b, 0.55), 8, 1.2)
	_txt(font, Vector2(pos.x + 10, pos.y + 21), label, 14, col.lerp(TEXT, 0.35))
	return pos.x + w + 8


## 各主要機能へつながるフッターナビバー（旧版のボトムタブを踏襲）。
## 等幅セルにアイコン＋ラベルを並べ、タップで action_pressed(id) を発火。
func _footer(font: Font, sz: Vector2) -> void:
	var fy := sz.y - FOOTER_H
	draw_rect(Rect2(0, fy, sz.x, FOOTER_H), Color(0.03, 0.03, 0.06, 0.95))
	draw_rect(Rect2(0, fy, sz.x, 1.5), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.55))
	var n := NAV.size()
	var cw := sz.x / float(n)
	for i in n:
		var e: Dictionary = NAV[i]
		var x0 := cw * i
		var id := String(e["id"])
		_hit(Rect2(x0, fy, cw, FOOTER_H), id)
		var col: Color = e["col"]
		var active := id == active_nav
		if active:
			draw_rect(Rect2(x0, fy, cw, FOOTER_H), Color(col.r, col.g, col.b, 0.10))
			draw_rect(Rect2(x0, fy, cw, 2.0), col)
			Kit.spot(self, Vector2(x0 + cw * 0.5, fy + FOOTER_H * 0.55), cw * 0.72, col, 0.22)   # アクティブの上辺ハイライト
		var gcol := col if active else Color(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.9)
		var cx := x0 + cw * 0.5
		var glyph := String(e["icon"])
		var gw := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		_txt(font, Vector2(cx - gw * 0.5, fy + 28), glyph, 22, gcol)
		var label := String(e["label"])
		var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		_txt(font, Vector2(cx - lw * 0.5, fy + 48), label, 11, gcol)
