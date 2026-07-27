class_name DiveOverlay
extends Control
## 潜航（戦闘）画面の 2D UI。ステージ（dive_side_view）の上に重ねる。
##
## 設計方針（オクトパストラベラーII の戦闘UIに寄せる）:
##  - 色は基調シアン1色。破壊的動作（浮上・戻る）だけ赤。他は無彩色の枠。
##  - 重みは3段階（主要=塗り＋枠 / 副次=枠のみ / 補助=テキストのみ）。
##  - HPの重複表示をやめ、常設のHP/SPは下部カードにだけ置く（顔＋数値つき）。
##  - 角丸とグローを使わない。座標は 2px グリッドに吸着してドット絵と密度を揃える。

signal command_pressed(id: String)

const PANEL_BG := Color(0.04, 0.045, 0.075, 0.90)
const LINE := Color(0.55, 0.60, 0.70, 0.45)      # 無彩色の罫（副次UI）
const CYAN := Color(0.35, 0.92, 1.0)             # 基調色（主要UI）
const DANGER := Color(1.0, 0.38, 0.42)           # 破壊的動作だけ
const GOLD := Color(1.0, 0.82, 0.4)
const HP_COL := Color(0.42, 0.90, 0.52)
const SP_COL := Color(0.40, 0.70, 1.0)
const TEXT := Color(0.96, 0.95, 0.98)
const TEXT_DIM := Color(0.70, 0.73, 0.80)
const CORE := Color(0.95, 1.0, 1.0)              # ネオン管の芯（画面の最明部）

const CARD_H := 76.0
const PORTRAIT := 40.0

# ── 表示データ（main.gd / KuroSim から set_data() で差し込む。既定はプレースホルダ）──
var party: Array = [
	{"name": "ミル", "hp": 320, "mhp": 420, "sp": 80, "msp": 100},
	{"name": "ナース", "hp": 280, "mhp": 360, "sp": 60, "msp": 100},
	{"name": "キリコ", "hp": 300, "mhp": 400, "sp": 100, "msp": 100},
	{"name": "ドクター", "hp": 210, "mhp": 450, "sp": 70, "msp": 100},
]
var player_lv := "B0"
var player_hp := 1.0          # 0〜1
var player_exp := 0.63        # 0〜1（階層の探索率）
var quest_text := ""
var speed_mult := 1           # 早送り倍率（≫ボタン表示用）
var manual_skill := false     # 手動スキルモード（DESIGN.md未決分岐の実験フラグ）
var skill_label := ""         # 次に撃てるスキル名（空＝準備中）
var boss_name := ""           # 交戦中のボス名（バナー表示・空＝非表示）

var _floor_no := 1            # 1始まりの階層（B1F 表記。0階は存在しない）
var _remain := -1.0           # 集中の残り秒（mm:ss 表示）


## main.gd / KuroSim から実データを流し込む。
## 階層と残り時間は文字列で来るので、ここで数値に直して表記を統一する
## （"B0" → B1F、"残り 1498秒" → 24:58）。
func set_data(d: Dictionary) -> void:
	for k in d:
		if k in self:
			set(k, d[k])
	_floor_no = maxi(1, int(player_lv.replace("B", "").strip_edges()) + 1)
	var m := RegEx.create_from_string("(\\d+)\\s*秒").search(quest_text)
	_remain = float(m.get_string(1)) if m != null else -1.0
	queue_redraw()

var _t := 0.0
var _hits: Array = []
var _ripples: Array = []      # タップ波紋（自前描画・角丸/グローなし）
var _log: Array = []          # 探索イベントのフィード [{msg, col, life}]
var _banner: Dictionary = {}  # 上部イベントバナー {msg, col, t0}（宝箱/扉/記憶/階突破）
var _face_cache: Dictionary = {}  # girl_id -> 48px ポートレート
var _name2id: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for gid in KuroData.GIRLS:
		_name2id[String(KuroData.GIRLS[gid]["name"])] = gid
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	# イベントフィードの寿命を減衰させ、古い行から消す
	for e in _log:
		e["life"] = float(e["life"]) - delta
	while not _log.is_empty() and float(_log[0]["life"]) <= 0.0:
		_log.pop_front()
	var i := 0
	while i < _ripples.size():
		if _t - float(_ripples[i]["t0"]) > 0.45:
			_ripples.remove_at(i)
		else:
			i += 1
	queue_redraw()


## main.gd から潜航中の sim イベントを受け取る。
func add_events(events: Array) -> void:
	for e in events:
		var msg := String(e.get("msg", ""))
		if msg == "":
			continue
		var kind := String(e.get("kind", "log"))
		# 見せ場（戦利品/扉/記憶/階突破/ボス）は上部バナーにも昇格
		if kind in ["loot", "door_loot", "door", "gate", "memory", "boss"]:
			_banner = {"msg": msg, "col": _kind_col(kind), "t0": _t}
		_log.append({"msg": msg, "col": _kind_col(kind), "life": 7.0})
	while _log.size() > 6:
		_log.pop_front()
	queue_redraw()


## 意味色は3つだけ（金＝報酬 / 赤＝危険 / 無彩色＝それ以外）。虹色にしない。
func _kind_col(kind: String) -> Color:
	match kind:
		"boss", "resync": return DANGER
		"door", "door_loot", "loot", "gate", "memory": return GOLD
		_: return TEXT_DIM


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
			_ripples.append({"p": p, "t0": _t})
			command_pressed.emit(String(h["id"]))
			accept_event()
			return


# ── 描画プリミティブ（角丸なし・2pxグリッド吸着・外グローなし）──────────

func _snap(r: Rect2) -> Rect2:
	return Rect2(snappedf(r.position.x, 2.0), snappedf(r.position.y, 2.0),
			snappedf(r.size.x, 2.0), snappedf(r.size.y, 2.0))


## 3段階の重み：weight 2=主要（塗り＋枠）／1=副次（枠のみ）／0=補助（下地のみ）。
func _plate(rect: Rect2, accent: Color, weight := 1) -> Rect2:
	var r := _snap(rect)
	match weight:
		2:
			draw_rect(r, Color(accent.r * 0.20, accent.g * 0.22, accent.b * 0.26, 0.95))
			draw_rect(r, accent, false, 2.0)
		1:
			draw_rect(r, PANEL_BG)
			draw_rect(r, Color(accent.r, accent.g, accent.b, 0.55), false, 1.0)
		_:
			draw_rect(r, PANEL_BG)
	return r


func _txt(font: Font, pos: Vector2, s: String, size: int, col: Color) -> void:
	var p := Vector2(snappedf(pos.x, 2.0), snappedf(pos.y, 2.0))
	draw_string(font, p + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.65))
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _txt_r(font: Font, right_x: float, y: float, s: String, size: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_txt(font, Vector2(right_x - w, y), s, size, col)


## バー：黒下地＋1px外枠＋塗り＋上辺1pxのハイライト。ネオン背景でも輪郭が消えない。
func _bar(rect: Rect2, ratio: float, col: Color) -> void:
	var r := _snap(rect)
	draw_rect(Rect2(r.position - Vector2(1, 1), r.size + Vector2(2, 2)), Color(0.02, 0.02, 0.04, 0.95))
	draw_rect(Rect2(r.position - Vector2(1, 1), r.size + Vector2(2, 2)), Color(1, 1, 1, 0.22), false, 1.0)
	draw_rect(r, Color(0.10, 0.11, 0.14))
	var k := clampf(ratio, 0.0, 1.0)
	if k <= 0.0:
		return
	var c := col if k > 0.28 else DANGER
	draw_rect(Rect2(r.position, Vector2(r.size.x * k, r.size.y)), c)
	draw_rect(Rect2(r.position, Vector2(r.size.x * k, 1.0)),
			Color(minf(c.r + 0.4, 1.0), minf(c.g + 0.4, 1.0), minf(c.b + 0.4, 1.0), 0.75))


## 顔ポートレート（idle_f0 の頭部を 44px へニアレスト縮小して 1:1 で貼る）。
func _face(gid: String) -> Texture2D:
	if _face_cache.has(gid):
		return _face_cache[gid]
	var t: Texture2D = null
	var path := "res://assets/generated/sprites/%s/idle_f0.png" % gid
	if ResourceLoader.exists(path):
		var src: Texture2D = load(path)
		var img := src.get_image()
		if img != null:
			img = img.duplicate()
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			_strip_matte(img)   # 一部フレームは背景（マゼンタ/白）が焼き込まれている
			var head := Image.create(72, 72, false, Image.FORMAT_RGBA8)
			head.blit_rect(img, Rect2i(34, 0, 72, 72), Vector2i.ZERO)
			head.resize(int(PORTRAIT), int(PORTRAIT), Image.INTERPOLATE_NEAREST)
			t = ImageTexture.create_from_image(head)
	_face_cache[gid] = t
	return t


## 生成スプライトの一部フレームは背景（マゼンタ/白）が不透明で焼き込まれている。
## 不透明領域の bbox 4隅が同色なら「地」とみなし、縁から連結した同色を抜く。
func _strip_matte(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
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
	if x1 - x0 < 6 or y1 - y0 < 6:
		return
	var counts := {}
	var seeds := {}
	for p: Vector2i in [Vector2i(x0 + 1, y0 + 1), Vector2i(x1 - 1, y0 + 1),
			Vector2i(x0 + 1, y1 - 1), Vector2i(x1 - 1, y1 - 1)]:
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


func _mmss(sec: float) -> String:
	var s := maxi(int(ceil(sec)), 0)
	return "%02d:%02d" % [int(s / 60.0), s % 60]


func _draw() -> void:
	var sz := size
	var font := get_theme_default_font()
	_hits.clear()

	# ===== トップバー：階層／残り時間／操作 =====================================
	var bar_h := 52.0
	var top := _snap(Rect2(0, 0, sz.x, bar_h))
	draw_rect(top, Color(0.03, 0.032, 0.055, 0.88))
	draw_rect(Rect2(0, bar_h - 1, sz.x, 1), Color(CYAN.r, CYAN.g, CYAN.b, 0.35))
	draw_rect(Rect2(10, bar_h - 3, 14, 2), CORE)     # ネオン管の芯

	# 左：階層（B1F）＋探索率。プレースホルダの「プレイヤー」は出さない。
	_txt(font, Vector2(12, 24), "B%dF" % _floor_no, 20, TEXT)
	_txt(font, Vector2(12, 44), "探索 %d%%" % int(clampf(player_exp, 0.0, 1.0) * 100.0), 13, TEXT_DIM)

	# 中央：残り時間（%02d:%02d の等幅表示）
	if _remain >= 0.0:
		var tm := _mmss(_remain)
		var tw := font.get_string_size(tm, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		_txt(font, Vector2((sz.x - tw) * 0.5, 38), tm, 30, CYAN)

	# 右：主要=倍速（塗り）／副次=技・編成（枠）／破壊=浮上・戻る（赤）
	var bx := sz.x - 8.0
	for it in [
			["戻る", "home", DANGER, 1],
			["浮上", "finish", DANGER, 1],
			["編成", "loadout", LINE, 1],
			["技:手動" if manual_skill else "技:自動", "toggle_manual", LINE, 1],
			["≫%d" % speed_mult, "fast", CYAN, 2]]:
		var lbl: String = it[0]
		var col: Color = it[2]
		var w := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 18.0
		bx -= w + 6.0
		var r := _plate(Rect2(bx, 8, w, 36), col, int(it[3]))
		_hit(r, String(it[1]))
		var lw := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		_txt(font, Vector2(r.position.x + (r.size.x - lw) * 0.5, r.position.y + 24), lbl, 15,
				TEXT if int(it[3]) == 2 else col)

	# ===== イベントバナー（黒帯・4秒でフェード） ================================
	if not _banner.is_empty():
		var bage := _t - float(_banner["t0"])
		if bage < 4.0:
			var ba := clampf(1.0 - (bage - 3.2) / 0.8, 0.0, 1.0) * clampf(bage / 0.18, 0.0, 1.0)
			var bmsg := String(_banner["msg"])
			var bcol: Color = _banner["col"]
			var bw := minf(font.get_string_size(bmsg, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 36, sz.x - 24)
			var br := _snap(Rect2((sz.x - bw) * 0.5, bar_h + 10, bw, 34))
			draw_rect(br, Color(0.02, 0.02, 0.04, 0.88 * ba))
			draw_rect(br, Color(bcol.r, bcol.g, bcol.b, 0.5 * ba), false, 1.0)
			draw_string(font, Vector2(br.position.x + 18, br.position.y + 23), bmsg,
					HORIZONTAL_ALIGNMENT_LEFT, int(bw - 32), 16, Color(bcol.r, bcol.g, bcol.b, ba))
		else:
			_banner = {}

	# ===== ボスバナー（交戦中のみ・赤の脈動） ===================================
	if boss_name != "":
		var bw2 := font.get_string_size(boss_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 74
		var br2 := _snap(Rect2((sz.x - bw2) * 0.5, bar_h + 52, bw2, 38))
		var bp := 0.5 + 0.5 * sin(_t * 4.0)
		draw_rect(br2, Color(0.14, 0.02, 0.04, 0.92))
		draw_rect(br2, Color(DANGER.r, DANGER.g, DANGER.b, 0.5 + 0.4 * bp), false, 2.0)
		_txt(font, Vector2(br2.position.x + 12, br2.position.y + 25), "BOSS", 13, DANGER)
		_txt(font, Vector2(br2.position.x + 58, br2.position.y + 26), boss_name, 18, TEXT)

	# ===== 下部：パーティカード（顔＋数値＋HP/SP） ==============================
	var foot_h := (CARD_H + 24.0 + 58.0) if manual_skill else (CARD_H + 24.0)
	var fy := sz.y - foot_h
	draw_rect(Rect2(0, fy, sz.x, foot_h), Color(0.025, 0.03, 0.05, 0.94))
	draw_rect(Rect2(0, fy, sz.x, 1), Color(CYAN.r, CYAN.g, CYAN.b, 0.35))
	draw_rect(Rect2(sz.x - 24, fy, 14, 2), CORE)     # ネオン管の芯

	# ===== イベントフィード（カードの上・新しいものほど下） ======================
	var feed_bottom := fy - 12.0
	for i in _log.size():
		var e: Dictionary = _log[_log.size() - 1 - i]
		var yy := feed_bottom - i * 22.0
		var fade := clampf(float(e["life"]) / 1.5, 0.0, 1.0) * (1.0 - i * 0.16)
		if fade <= 0.02:
			continue
		var msg := String(e["msg"])
		var tw2 := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_rect(_snap(Rect2(8, yy - 16, tw2 + 16, 21)), Color(0.02, 0.02, 0.05, 0.62 * fade))
		var col2: Color = e["col"]
		_txt(font, Vector2(16, yy), msg, 15, Color(col2.r, col2.g, col2.b, fade))

	var cy := fy + 12.0
	var cw := (sz.x - 16.0) / maxi(party.size(), 1)
	for i in party.size():
		var d: Dictionary = party[i]
		var card := _snap(Rect2(8 + i * cw + 3, cy, cw - 6, CARD_H))
		var hp := float(d["hp"])
		var mhp := maxf(float(d["mhp"]), 1.0)
		var ratio := hp / mhp
		var dead := hp <= 0.0
		draw_rect(card, Color(0.055, 0.06, 0.09, 0.95))
		# 低HPだけ赤枠、それ以外は無彩色の細枠（虹色にしない）
		draw_rect(card, DANGER if (ratio <= 0.28 and not dead) else Color(LINE.r, LINE.g, LINE.b, 0.40),
				false, 1.0)
		# 顔（ポートレート・1:1 で貼る）
		var pr := Rect2(card.position.x + 6, card.position.y + 6, PORTRAIT, PORTRAIT)
		draw_rect(Rect2(pr.position - Vector2(1, 1), pr.size + Vector2(2, 2)), Color(0.02, 0.02, 0.04))
		var gid := String(_name2id.get(String(d["name"]), ""))
		var face := _face(gid) if gid != "" else null
		if face != null:
			draw_texture_rect(face, pr, false, Color(1, 1, 1) if not dead else Color(0.45, 0.45, 0.52))
		draw_rect(Rect2(pr.position - Vector2(1, 1), pr.size + Vector2(2, 2)),
				Color(1, 1, 1, 0.18), false, 1.0)
		# 名前と HP 数値（顔の右。バーは名前の下でカード全幅を使う＝数字が読める）
		var ix := pr.end.x + 6.0
		_txt(font, Vector2(ix, card.position.y + 20), String(d["name"]), 14,
				TEXT if not dead else Color(0.55, 0.55, 0.62))
		_txt(font, Vector2(ix, card.position.y + 40), "%d/%d" % [int(hp), int(mhp)], 13, TEXT_DIM)
		var bar_x := card.position.x + 6.0
		var bar_w := card.size.x - 12.0
		_bar(Rect2(bar_x, card.position.y + 50, bar_w, 10), ratio, HP_COL)
		var sp := float(d.get("sp", 0))
		var msp := maxf(float(d.get("msp", 1)), 1.0)
		_bar(Rect2(bar_x, card.position.y + 65, bar_w, 6), sp / msp, SP_COL)

	# スキルボタン1個（手動モードのみ）。観賞モードでは何も出さない。
	if manual_skill:
		var ready := skill_label != ""
		var r3 := _snap(Rect2(12, cy + CARD_H + 8, sz.x - 24, 46))
		var lbl2 := ("▶ %s" % skill_label) if ready else "スキル準備中…"
		_plate(r3, CYAN if ready else LINE, 2 if ready else 0)
		var lw2 := font.get_string_size(lbl2, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		_txt(font, Vector2(r3.position.x + (r3.size.x - lw2) * 0.5, r3.position.y + 30), lbl2, 18,
				TEXT if ready else TEXT_DIM)
		_hit(r3, "cast")

	# タップ波紋（角丸/グローなしの矩形）
	for rp in _ripples:
		var k := (_t - float(rp["t0"])) / 0.45
		var pp: Vector2 = rp["p"]
		var rr := 10.0 + k * 34.0
		draw_rect(_snap(Rect2(pp.x - rr, pp.y - rr, rr * 2.0, rr * 2.0)),
				Color(CYAN.r, CYAN.g, CYAN.b, 0.35 * (1.0 - k)), false, 2.0)


func _hit(rect: Rect2, id: String) -> void:
	_hits.append({"rect": rect, "id": id})
