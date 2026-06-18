class_name HomeOverlay
extends Control
## ホーム画面（黒猫飯店）の 2D UI チロー。シネマティック構成：
##   上＝最小トップバー（≡/猫/設定/ベル）、右＝探索入口ポータル、
##   下＝VN風セリフ窓、最下部＝HD-2D フィールド帯の枠＋コンパス。
## 背後に DinerStage（店内ジオラマ）＋ FieldStrip（パーティ/敵のピクセル帯）が見える。
## タップで action_pressed(id) を発火（main.gd 側で画面遷移/ロジックに接続）。

signal action_pressed(id: String)

# 色は DS（唯一の真実）から引く。画面固有のローカル定義は持たない。
const PANEL_BG := DS.SURFACE
const PINK := DS.PINK
const CYAN := DS.CYAN
const PURPLE := DS.PURPLE
const GOLD := DS.GOLD
const TEXT := DS.TEXT
const TEXT_DIM := DS.TEXT_2

const STRIP_H := 168.0   # 最下部 HD-2D フィールド帯の高さ（FieldStrip と一致させる）
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

var _t := 0.0
var _hits: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)


func set_data(d: Dictionary) -> void:
	for k in d:
		if k in self:
			set(k, d[k])
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
			action_pressed.emit(String(h["id"]))
			accept_event()
			return


func _hit(rect: Rect2, id: String) -> void:
	_hits.append({"rect": rect, "id": id})


# 描画の実体は DS に集約。各画面は self を渡すだけの薄いラッパー。
func _panel(rect: Rect2, bg: Color, border: Color, radius := 10.0, bw := 1.5) -> void:
	DS.panel(self, rect, bg, border, radius, bw)


func _txt(font: Font, pos: Vector2, s: String, size: int, col: Color, ha := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	DS.txt(self, font, pos, s, size, col, ha, w)


func _icon(font: Font, c: Vector2, r: float, label: String, col: Color, id: String) -> void:
	_panel(Rect2(c - Vector2(r, r), Vector2(r * 2, r * 2)), Color(0.05, 0.05, 0.09, 0.85), col, r, 1.5)
	var w := DS.tw(font, label, 15)
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
	var pc := Vector2(sz.x - 56, sz.y * 0.42)
	_hit(Rect2(pc.x - 52, pc.y - 56, 104, 186), "depart")
	# うっすら枠
	_panel(Rect2(pc.x - 50, pc.y - 54, 100, 184), Color(0.05, 0.03, 0.10, 0.45), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.5), 14)
	var pr := 34.0
	draw_circle(pc, pr + 8, Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.12))
	draw_arc(pc, pr, _t * 1.2, _t * 1.2 + TAU * 0.78, 36, PURPLE, 3.0)
	draw_circle(pc, pr * 0.34, Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.85))
	# 縦書き「仕入れへ」（深層へ食材を獲りに行く＝仕入れ）
	var vy := pc.y + pr + 14.0
	for ch in "仕入れへ":
		_txt(font, Vector2(pc.x - 9, vy), ch, 17, PINK)
		vy += 22.0
	# クイックダイブだと分かる注記（集中CTAとの違いを明示）
	vy += 2.0
	for ch2 in "80秒":
		_txt(font, Vector2(pc.x - 7, vy), ch2, 12, TEXT_DIM)
		vy += 16.0

	# ===== ポモドーロ集中ボタン（主役CTA・VN窓の上） =====
	var vh := 96.0
	var vy0 := sz.y - STRIP_H - vh - 8
	var cta := Rect2(sz.x * 0.5 - 150, vy0 - 78, 300, 64)
	_hit(cta, "pomodoro")
	var pulse := 0.5 + 0.5 * sin(_t * 2.5)
	_panel(cta, Color(PINK.r * 0.22, PINK.g * 0.16, PINK.b * 0.24, 0.96),
			Color(PINK.r, PINK.g, PINK.b, 0.6 + 0.3 * pulse), 16, 2.0)
	var ct := "▶  集中する（25分）"
	var ctw := DS.tw(font, ct, 19)
	_txt(font, Vector2(cta.position.x + (cta.size.x - ctw) * 0.5, cta.position.y + 30), ct, 19, TEXT)
	var ctsub := "じっくり潜る・本編"
	var ctsw := DS.tw(font, ctsub, 12)
	_txt(font, Vector2(cta.position.x + (cta.size.x - ctsw) * 0.5, cta.position.y + 52), ctsub, 12, TEXT_DIM)

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

	# ===== 最下部：HD-2D フィールド帯の枠＋コンパス =====
	var fy := sz.y - STRIP_H
	# 上辺のネオンライン
	draw_rect(Rect2(0, fy, sz.x, 2), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.6))
	# フィールドのタップ領域はフッターと重ならないよう上側だけにする
	_hit(Rect2(0, fy, sz.x, STRIP_H - FOOTER_H), "field")
	# フィールド帯のラベル（ここは店先の“眺め”。タップで仕入れへ）
	_txt(font, Vector2(18, fy + 22), "店先のながめ", 13, Color(CYAN.r, CYAN.g, CYAN.b, 0.85))
	var hint := "タップで仕入れへ →"
	var hw := DS.tw(font, hint, 12)
	_txt(font, Vector2(sz.x - 18 - hw, fy + 22), hint, 12, TEXT_DIM)

	# ===== 最下部：各主要機能へのフッターナビ =====
	_footer(font, sz)


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
			draw_rect(Rect2(x0, fy, cw, 2.0), col)   # アクティブの上辺ハイライト
		var gcol := col if active else Color(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.9)
		var cx := x0 + cw * 0.5
		var glyph := String(e["icon"])
		var gw := DS.tw(font, glyph, 22)
		_txt(font, Vector2(cx - gw * 0.5, fy + 28), glyph, 22, gcol)
		var label := String(e["label"])
		var lw := DS.tw(font, label, 11)
		_txt(font, Vector2(cx - lw * 0.5, fy + 48), label, 11, gcol)
