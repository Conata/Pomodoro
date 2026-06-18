class_name DiveOverlay
extends Control
## 潜航（戦闘）画面の 2D UI。HD-2D の戦闘ステージ（パーティ手前・敵奥）の上に重ねる。
## 戦闘はオート（KuroSim が自動進行）なので、プレイヤーが操作するのは
## 「戻る（撤退）／浮上（早期終了）／早送り」だけ。攻撃コマンド等は持たない。
## 主役は“残り時間”——ポモドーロ＝現実の集中時間がそのまま潜行時間だから。
## タップで command_pressed を発火（main.gd / KuroSim 側で接続）。

signal command_pressed(id: String)

# 色は DS（唯一の真実）から引く。画面固有のローカル定義は持たない。
const PANEL_BG := DS.SURFACE
const PINK := DS.PINK
const CYAN := DS.CYAN
const PURPLE := DS.PURPLE
const GOLD := DS.GOLD
const HP_COL := DS.HP
const TEXT := DS.TEXT
const TEXT_DIM := DS.TEXT_2

# ── 表示データ（main.gd / KuroSim から set_data()。既定はプレースホルダ）──
var party: Array = [
	{"name": "ミル", "hp": 320, "mhp": 420},
	{"name": "ユズキ", "hp": 280, "mhp": 360},
	{"name": "ムュウ", "hp": 300, "mhp": 400},
	{"name": "レイカ", "hp": 210, "mhp": 450},
]
var depth := "B1"             # 今いる階層
var party_hp := 1.0           # パーティ総HP比 0〜1
var floor_prog := 0.4         # 階の踏破率 0〜1
var remain_sec := 1500        # 残り秒
var is_pomo := true           # ポモドーロ集中か（false=クイック仕入れ）
var in_combat := false        # 戦闘中フラグ（AUTOバッジの色に使う）
var speed_mult := 1           # 早送り倍率（≫ボタン表示用）

var _t := 0.0
var _hits: Array = []


## main.gd / KuroSim から実データを流し込む。
func set_data(d: Dictionary) -> void:
	for k in d:
		if k in self:
			set(k, d[k])
	queue_redraw()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)


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
			command_pressed.emit(String(h["id"]))
			accept_event()
			return


func _hit(rect: Rect2, id: String) -> void:
	_hits.append({"rect": rect, "id": id})


# 描画の実体は DS に集約。各画面は self を渡すだけの薄いラッパー。
func _panel(rect: Rect2, bg: Color, border: Color, radius := 10.0, bw := 1.5) -> void:
	DS.panel(self, rect, bg, border, radius, bw)


func _txt(font: Font, pos: Vector2, s: String, size: int, col: Color, ha := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	DS.txt(self, font, pos, s, size, col, ha, w)


func _tw(font: Font, s: String, size: int) -> float:
	return DS.tw(font, s, size)


func _bar(rect: Rect2, ratio: float, col: Color) -> void:
	DS.bar(self, rect, ratio, col)


func _mmss(sec: int) -> String:
	var s := maxi(sec, 0)
	return "%d:%02d" % [s / 60, s % 60]


func _draw() -> void:
	var sz := size
	var font := get_theme_default_font()
	_hits.clear()

	# ===== トップ：残り時間（主役）＝この潜航の“長さ”そのもの =====
	var bar_h := 84.0
	_panel(Rect2(8, 8, sz.x - 16, bar_h), PANEL_BG, Color(CYAN.r, CYAN.g, CYAN.b, 0.4), 12)
	# 左：今いる階層
	_txt(font, Vector2(22, 34), "深層", 13, TEXT_DIM)
	_txt(font, Vector2(22, 62), depth, 28, GOLD)
	# 中央：残り時間（大きく）。ラベルで集中/クイックを明示
	var mode_label := "集中のこり" if is_pomo else "仕入れのこり"
	var clock := _mmss(remain_sec)
	var cx := sz.x * 0.5
	_txt(font, Vector2(cx - _tw(font, mode_label, 13) * 0.5, 30), mode_label, 13, TEXT_DIM)
	_txt(font, Vector2(cx - _tw(font, clock, 40) * 0.5, 70), clock, 40, TEXT)

	# 右：操作（戻る＝撤退／浮上＝早期終了／≫＝早送り）。実際に効くのはこれだけ。
	var bx := sz.x - 20
	for it in [["戻る", "home", Color(1.0, 0.5, 0.5)], ["浮上", "finish", GOLD], ["≫%d" % speed_mult, "fast", CYAN]]:
		var lbl: String = it[0]
		var col: Color = it[2]
		var w := _tw(font, lbl, 15) + 18
		bx -= w + 8
		_hit(Rect2(bx, 22, w, 40), String(it[1]))
		_panel(Rect2(bx, 22, w, 40), Color(col.r * 0.18, col.g * 0.16, col.b * 0.2, 0.92), col, 8, 1.5)
		_txt(font, Vector2(bx + 9, 48), lbl, 15, col)

	# 階の踏破バー（トップバー直下の薄い線）
	_bar(Rect2(16, bar_h + 12, sz.x - 32, 6), floor_prog, PURPLE)

	# ===== 中央：オート探索バッジ（“操作不要・集中を続けて”を明示） =====
	var badge := "⟳ オートで探索中" if in_combat else "⟳ オートで進行中"
	var sub := "あなたは集中を。深層は仲間が進める。" if is_pomo else "そのまま見守ろう。"
	var bw := maxf(_tw(font, badge, 16), _tw(font, sub, 12)) + 40
	var by := bar_h + 40
	var bcol := PINK if in_combat else CYAN
	var pulse := 0.5 + 0.5 * sin(_t * 2.0)
	_panel(Rect2(cx - bw * 0.5, by, bw, 56), Color(0.05, 0.05, 0.10, 0.7),
			Color(bcol.r, bcol.g, bcol.b, 0.35 + 0.25 * pulse), 12)
	_txt(font, Vector2(cx - _tw(font, badge, 16) * 0.5, by + 24), badge, 16, bcol)
	_txt(font, Vector2(cx - _tw(font, sub, 12) * 0.5, by + 44), sub, 12, TEXT_DIM)

	# ===== 下部：パーティHP（実データ・操作なし） =====
	var foot_h := 128.0
	var fy := sz.y - foot_h
	_panel(Rect2(0, fy, sz.x, foot_h), Color(0.03, 0.035, 0.07, 0.92), Color(PINK.r, PINK.g, PINK.b, 0.3), 0, 1)
	# 見出し＋総HP
	_txt(font, Vector2(16, fy + 26), "パーティ", 14, CYAN)
	_txt(font, Vector2(96, fy + 26), "総HP %d%%" % int(party_hp * 100.0), 13, HP_COL)

	# パーティカード（人数ぶん横並び。SPは廃止＝simに無いステを出さない）
	var cy := fy + 40
	var n := maxi(party.size(), 1)
	var cw := (sz.x - 24) / float(n)
	for i in party.size():
		var d: Dictionary = party[i]
		var px := 12 + i * cw
		var alive: bool = float(d["hp"]) > 0.0
		var ratio := float(d["hp"]) / maxf(float(d["mhp"]), 1.0)
		_panel(Rect2(px + 3, cy, cw - 6, 72),
				Color(0.08, 0.07, 0.12, 0.92) if alive else Color(0.12, 0.05, 0.06, 0.92),
				Color(PINK.r, PINK.g, PINK.b, 0.3) if alive else Color(1.0, 0.4, 0.4, 0.5), 8)
		_txt(font, Vector2(px + 12, cy + 24), String(d["name"]), 14, TEXT if alive else Color(1.0, 0.55, 0.55))
		_bar(Rect2(px + 12, cy + 36, cw - 30, 10), ratio, HP_COL if alive else Color(0.5, 0.2, 0.2))
		var hp_txt := "%d/%d" % [int(d["hp"]), int(d["mhp"])] if alive else "再同期待ち"
		_txt(font, Vector2(px + 12, cy + 62), hp_txt, 11, TEXT_DIM)
