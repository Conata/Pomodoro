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
const CORE := Color(0.72, 0.80, 0.88, 0.8)       # 罫のアクセント（純白は使わない）

const CARD_H := 76.0
const PORTRAIT := 40.0

# 文字サイズは5段だけ（12 / 16 / 22 / 32 / 48）。dive_side_view と同じ段を使う。
const FS_S := 12
const FS_M := 16
const FS_L := 22
const FS_XL := 32
const FS_H := 48

# ヘッダは3段。上＝操作／中＝同期率（レベルとXPバー）／下＝ランの数字。
# 「常時上がっている数字」を隠さないための固定席で、ここだけは何があっても消えない。
const BAR_H := 52.0     # 操作バー
const SYNC_H := 46.0    # 同期率バンド
const STAT_H := 28.0    # 数字ストリップ
const HEAD_H := BAR_H + SYNC_H + STAT_H

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
	var nf := maxi(1, int(player_lv.replace("B", "").strip_edges()) + 1)
	# 階層が変わった瞬間にバナー（潜航開始の初回だけは「変化」に数えない）
	if _seen_floor and nf != _floor_no:
		_floor_fx = _t
		_floor_label = "B%dF" % nf
	_seen_floor = true
	_floor_no = nf
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

# ── ランの実数（すべて sim から読む。UI側で数字を作り直さない）──────────────
# main.gd の set_data() は固定の項目しか渡してこないので、sim 本体は祖先ノードから
# 引く（読み取り専用。main.gd には一切触らない）。
var _sim: Object = null
var _sync_lv := 1
var _sync_prog := 0.0
var _sync_xp := 0
var _sync_need := 10
var _atk_mult := 1.0
var _res: Array = []          # 取得済み共鳴 [{id, name, desc}]
var _kills := 0
var _gold := 0                # この潜航で稼いだ額（gold - run.gold0）
var _mats := 0
var _boxes := 0

# ── 「数字が動いた」を絶対に見逃させないための状態 ───────────────────────
var _gold_shown := 0.0        # 金だけは指数で追従カウントアップ（一気に飛ばさない）
var _pop: Dictionary = {"kills": -9.9, "gold": -9.9, "mats": -9.9, "boxes": -9.9}
var _chip: Dictionary = {}    # チップ中心座標（箱アイコンの飛び先）
var _xp_tick := -9.9          # XPバーが伸びた時刻（バー頭の閃き）
var _prev_prog := -1.0
var _res_pop := -9.9          # 共鳴アイコンが1つ増えた時刻（ポップ）
var _lv_fx: Dictionary = {}   # レベルアップ演出 {t0, lv, name, desc, atk}
var _floor_fx := -9.9         # 階層バナー
var _floor_label := ""
var _box_fly: Array = []      # 拾った箱が数字チップへ飛ぶ [{t0}]
var _seen_floor := false


# ── イージング（UI も等速で動かさない。ステージ側と同じ3本だけを使う）──
## 速く出て静かに止まる。
static func _e_out(u: float, p := 3.0) -> float:
	return 1.0 - pow(1.0 - clampf(u, 0.0, 1.0), p)


## 立ち上がりも収めも滑らかに。
static func _e_in_out(u: float) -> float:
	var x := clampf(u, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for gid in KuroData.GIRLS:
		_name2id[String(KuroData.GIRLS[gid]["name"])] = gid
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	_poll_sim(delta)
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
	i = 0
	while i < _box_fly.size():
		if _t - float(_box_fly[i]["t0"]) > 0.85:
			_box_fly.remove_at(i)
		else:
			i += 1
	queue_redraw()


## KuroSim 本体を祖先から引く（main.gd の `sim` プロパティ。読み取り専用）。
func _sim_ref() -> Object:
	if _sim != null:
		return _sim
	var n: Node = get_parent()
	while n != null:
		var s: Variant = n.get("sim")
		if s != null:
			_sim = s
			return _sim
		n = n.get_parent()
	return null


## 毎フレーム sim の実値を読む。UI側は「変化した瞬間」を記録するだけで、
## 値そのものは一切こちらで作らない。
func _poll_sim(delta: float) -> void:
	var s := _sim_ref()
	if s == null:
		return
	var run: Dictionary = s.state.get("run", {})
	if not bool(run.get("active", false)):
		return
	_sync_lv = int(s.sync_level())
	_sync_prog = float(s.sync_progress())
	_sync_need = int(s.sync_need(_sync_lv))
	_sync_xp = int(round(_sync_prog * _sync_need))
	_atk_mult = float(s.sync_atk_mult())
	var rn: Array = s.sync_resonances()
	if rn.size() > _res.size():
		_res_pop = _t
	_res = rn
	if not is_equal_approx(_sync_prog, _prev_prog):
		if _sync_prog > _prev_prog:
			_xp_tick = _t
		_prev_prog = _sync_prog
	var k := int(run.get("kills", 0))
	if k != _kills:
		_kills = k
		_pop["kills"] = _t
	var g := int(s.state.get("gold", 0)) - int(run.get("gold0", 0))
	if g != _gold:
		_gold = g
		_pop["gold"] = _t
	var mt := 0
	for v in (run.get("mats", {}) as Dictionary).values():
		mt += int(v)
	if mt != _mats:
		_mats = mt
		_pop["mats"] = _t
	var bx := (run.get("boxes", []) as Array).size()
	if bx != _boxes:
		if bx > _boxes:
			_box_fly.append({"t0": _t})
		_boxes = bx
		_pop["boxes"] = _t
	# 金だけはカウントアップ（数字が回っているのが見える）
	_gold_shown += (float(_gold) - _gold_shown) * (1.0 - exp(-delta * 5.5))
	if absf(_gold_shown - float(_gold)) < 0.6:
		_gold_shown = float(_gold)


## main.gd から潜航中の sim イベントを受け取る。
func add_events(events: Array) -> void:
	for e in events:
		var kind := String(e.get("kind", "log"))
		match kind:
			"levelup":
				# 25分の山。共鳴（Lv3/6/9/12）を取った回は別格の長さで打つ。
				_lv_fx = {"t0": _t, "lv": int(e.get("lv", 0)),
						"name": String(e.get("res_name", "")),
						"desc": String(e.get("res_desc", "")),
						"atk": float(e.get("atk", 1.0))}
			"gate":
				# 階層が上がった瞬間（ボス撃破時のみ起きる）。
				_floor_fx = _t
				_floor_label = "B%dF" % int(e.get("floor", _floor_no))
		var msg := String(e.get("msg", ""))
		if msg == "":
			continue
		# 見せ場（戦利品/扉/記憶/階突破/ボス/レベルアップ）は上部バナーにも昇格
		if kind in ["loot", "door_loot", "door", "memory", "boss"]:
			_banner = {"msg": msg, "col": _kind_col(kind), "t0": _t}
		_log.append({"msg": msg, "col": _kind_col(kind), "life": 7.0})
	while _log.size() > 6:
		_log.pop_front()
	queue_redraw()


## 意味色は3つだけ（金＝報酬 / 赤＝危険 / 無彩色＝それ以外）。虹色にしない。
## 同期率だけは識別色シアン（＝この画面の主軸）。
func _kind_col(kind: String) -> Color:
	match kind:
		"boss", "resync": return DANGER
		"levelup": return CYAN
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
	var bar_h := BAR_H
	var top := _snap(Rect2(0, 0, sz.x, HEAD_H))
	draw_rect(top, Color(0.03, 0.032, 0.055, 0.88))
	draw_rect(Rect2(0, bar_h - 1, sz.x, 1), Color(CYAN.r, CYAN.g, CYAN.b, 0.18))
	draw_rect(Rect2(0, HEAD_H - 1, sz.x, 1), Color(CYAN.r, CYAN.g, CYAN.b, 0.35))
	draw_rect(Rect2(10, HEAD_H - 3, 14, 2), CORE)     # ネオン管の芯

	# 左：階層（B1F）＋探索率。プレースホルダの「プレイヤー」は出さない。
	_txt(font, Vector2(12, 24), "B%dF" % _floor_no, FS_L, TEXT)
	_txt(font, Vector2(12, 44), "探索 %d%%" % int(clampf(player_exp, 0.0, 1.0) * 100.0), FS_S, TEXT_DIM)

	# 中央：残り時間（%02d:%02d の等幅表示）
	if _remain >= 0.0:
		var tm := _mmss(_remain)
		var tw := font.get_string_size(tm, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_XL).x
		_txt(font, Vector2((sz.x - tw) * 0.5, 40), tm, FS_XL, CYAN)

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
		var w := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_M).x + 18.0
		bx -= w + 6.0
		var r := _plate(Rect2(bx, 8, w, 36), col, int(it[3]))
		_hit(r, String(it[1]))
		var lw := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_M).x
		_txt(font, Vector2(r.position.x + (r.size.x - lw) * 0.5, r.position.y + 24), lbl, FS_M,
				TEXT if int(it[3]) == 2 else col)

	_draw_sync_band(sz, font)
	_draw_stat_strip(sz, font)

	# ===== イベントバナー（黒帯・4秒でフェード） ================================
	if not _banner.is_empty():
		var bage := _t - float(_banner["t0"])
		if bage < 4.0:
			var ba := clampf(1.0 - (bage - 3.2) / 0.8, 0.0, 1.0) * clampf(bage / 0.18, 0.0, 1.0)
			var bmsg := String(_banner["msg"])
			var bcol: Color = _banner["col"]
			var bw := minf(font.get_string_size(bmsg, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_M).x + 36, sz.x - 24)
			var br := _snap(Rect2((sz.x - bw) * 0.5, HEAD_H + 10, bw, 34))
			draw_rect(br, Color(0.02, 0.02, 0.04, 0.88 * ba))
			draw_rect(br, Color(bcol.r, bcol.g, bcol.b, 0.5 * ba), false, 1.0)
			draw_string(font, Vector2(br.position.x + 18, br.position.y + 23), bmsg,
					HORIZONTAL_ALIGNMENT_LEFT, int(bw - 32), FS_M, Color(bcol.r, bcol.g, bcol.b, ba))
		else:
			_banner = {}

	# ===== ボスバナー（交戦中のみ・赤の脈動） ===================================
	if boss_name != "":
		var bw2 := font.get_string_size(boss_name, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_L).x + 74
		var br2 := _snap(Rect2((sz.x - bw2) * 0.5, HEAD_H + 52, bw2, 38))
		var bp := 0.5 + 0.5 * sin(_t * 4.0)
		draw_rect(br2, Color(0.14, 0.02, 0.04, 0.92))
		draw_rect(br2, Color(DANGER.r, DANGER.g, DANGER.b, 0.5 + 0.4 * bp), false, 2.0)
		_txt(font, Vector2(br2.position.x + 12, br2.position.y + 25), "BOSS", FS_S, DANGER)
		_txt(font, Vector2(br2.position.x + 58, br2.position.y + 27), boss_name, FS_L, TEXT)

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
		var tw2 := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_M).x
		draw_rect(_snap(Rect2(8, yy - 16, tw2 + 16, 21)), Color(0.02, 0.02, 0.05, 0.62 * fade))
		var col2: Color = e["col"]
		_txt(font, Vector2(16, yy), msg, FS_M, Color(col2.r, col2.g, col2.b, fade))

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
		_txt(font, Vector2(ix, card.position.y + 20), String(d["name"]), FS_M,
				TEXT if not dead else Color(0.55, 0.55, 0.62))
		_txt(font, Vector2(ix, card.position.y + 40), "%d/%d" % [int(hp), int(mhp)], FS_S, TEXT_DIM)
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
		var lw2 := font.get_string_size(lbl2, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_L).x
		_txt(font, Vector2(r3.position.x + (r3.size.x - lw2) * 0.5, r3.position.y + 31), lbl2, FS_L,
				TEXT if ready else TEXT_DIM)
		_hit(r3, "cast")

	_draw_box_fly(sz)
	_draw_floor_banner(sz, font)
	_draw_levelup(sz, font)

	# タップ波紋（角丸/グローなしの矩形）
	for rp in _ripples:
		var k := (_t - float(rp["t0"])) / 0.45
		var pp: Vector2 = rp["p"]
		# 広がりは ease-out、消えは後半に寄せる（指で押した瞬間がいちばん速い）
		var rr := 10.0 + _e_out(k, 2.6) * 34.0
		draw_rect(_snap(Rect2(pp.x - rr, pp.y - rr, rr * 2.0, rr * 2.0)),
				Color(CYAN.r, CYAN.g, CYAN.b,
						0.35 * (1.0 - _e_in_out(clampf((k - 0.2) / 0.8, 0.0, 1.0)))), false, 2.0)


func _hit(rect: Rect2, id: String) -> void:
	_hits.append({"rect": rect, "id": id})


# ══ 同期率バンド（Lv とXPバー・取得済み共鳴） ════════════════════════════
# 25分の潜航で撃破は600〜700体。その積み上がりを1本のバーに束ねて常時見せる。
# バーは lerp で「じわっと」動かさない：sync_progress() をそのまま描くので
# 撃破のたびにカクッと進み、進んだ瞬間だけ頭が閃く（クッキークリッカーの原則）。
func _draw_sync_band(sz: Vector2, font: Font) -> void:
	var y0 := BAR_H
	var lv_age := _t - float(_lv_fx.get("t0", -9.9)) if not _lv_fx.is_empty() else 9.9
	var glow := clampf(1.0 - lv_age / 0.9, 0.0, 1.0)

	# レベル（上がった直後だけ1段大きく＝「上がった」ことを見逃させない）
	var lv_txt := "Lv.%d" % _sync_lv
	var lv_fs := FS_XL if glow > 0.35 else FS_L
	_txt(font, Vector2(12, y0 + 32), lv_txt, lv_fs,
			Color(1, 1, 1) if glow > 0.35 else CYAN)
	_txt(font, Vector2(12, y0 + 44), "同期率", FS_S, TEXT_DIM)

	# 共鳴アイコン列（Lv3/6/9/12 の4枠。取ると1つ増えて、その瞬間ポップする）
	var slots := 4
	var isz := 26.0
	var ix0 := sz.x - 8.0 - slots * (isz + 4.0)
	var res_age := _t - _res_pop
	for i in slots:
		var r := _snap(Rect2(ix0 + i * (isz + 4.0), y0 + 9, isz, isz))
		var got := i < _res.size()
		if got and i == _res.size() - 1 and res_age < 0.6:
			# 増えた瞬間だけ枠が膨らんで戻る
			var e := sin(clampf(res_age / 0.6, 0.0, 1.0) * PI) * 7.0
			r = _snap(Rect2(r.position - Vector2(e, e), r.size + Vector2(e * 2, e * 2)))
		draw_rect(r, Color(0.02, 0.02, 0.05, 0.92))
		draw_rect(r, Color(CYAN.r, CYAN.g, CYAN.b, 0.85 if got else 0.20), false,
				2.0 if got else 1.0)
		if got:
			var nm := String((_res[i] as Dictionary).get("name", ""))
			var ch := nm.substr(3, 1) if nm.length() > 3 else "◆"
			var cw := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_M).x
			_txt(font, Vector2(r.position.x + (r.size.x - cw) * 0.5, r.position.y + r.size.y - 6),
					ch, FS_M, CYAN)
		else:
			draw_rect(Rect2(r.get_center() - Vector2(3, 1), Vector2(6, 2)),
					Color(LINE.r, LINE.g, LINE.b, 0.5))

	# XPバー（撃破ごとにカクッと伸びる。数値も併記して「何回で上がるか」を見せる）
	var bx := 86.0
	var bw := ix0 - 12.0 - bx
	if bw < 60.0:
		return
	var br := _snap(Rect2(bx, y0 + 16, bw, 14))
	draw_rect(Rect2(br.position - Vector2(1, 1), br.size + Vector2(2, 2)), Color(0.02, 0.02, 0.04))
	draw_rect(Rect2(br.position - Vector2(1, 1), br.size + Vector2(2, 2)),
			Color(1, 1, 1, 0.22), false, 1.0)
	draw_rect(br, Color(0.09, 0.11, 0.15))
	# レベルの刻み（次の共鳴までの残りが目で数えられる）
	var k := clampf(_sync_prog, 0.0, 1.0)
	if k > 0.0:
		var fw := roundf(br.size.x * k)
		draw_rect(Rect2(br.position, Vector2(fw, br.size.y)), CYAN)
		draw_rect(Rect2(br.position, Vector2(fw, 1.0)), Color(0.85, 1.0, 1.0, 0.9))
		# 伸びた瞬間だけバーの頭が白く閃く（＝1体倒したことの受領証）
		var tick := 1.0 - _e_out(clampf((_t - _xp_tick) / 0.22, 0.0, 1.0), 1.8)
		if tick > 0.0:
			draw_rect(Rect2(br.position.x + fw - 4.0, br.position.y - 2.0, 6.0, br.size.y + 4.0),
					Color(1, 1, 1, 0.85 * tick))
	# レベルアップ直後はバー全体が光る
	if glow > 0.0:
		draw_rect(br, Color(1, 1, 1, 0.55 * glow))
	var xt := "%d / %d" % [_sync_xp, _sync_need]
	var xw := font.get_string_size(xt, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_S).x
	_txt(font, Vector2(br.get_center().x - xw * 0.5, br.position.y + 11), xt, FS_S, TEXT)
	# 攻撃倍率（レベルが「効いている」ことの証明）
	_txt(font, Vector2(bx, y0 + 44), "攻撃 x%.2f" % _atk_mult, FS_S, TEXT_DIM)


# ══ 数字ストリップ（常時上がっている値を全部見せる） ══════════════════════
# 撃破数／この潜航で稼いだ金／素材／箱。値が変わった瞬間だけ1段大きく描いて戻す。
func _draw_stat_strip(sz: Vector2, font: Font) -> void:
	var y0 := BAR_H + SYNC_H
	draw_rect(Rect2(0, y0, sz.x, 1), Color(CYAN.r, CYAN.g, CYAN.b, 0.14))
	var items := [
		["kills", "撃破", str(_kills), TEXT],
		["gold", "獲得", "%dG" % int(round(_gold_shown)), GOLD],
		["mats", "素材", str(_mats), CYAN],
		["boxes", "箱", str(_boxes), GOLD],
	]
	var x := 12.0
	var cw := (sz.x - 24.0) / float(items.size())
	for it: Array in items:
		var id: String = it[0]
		var age := _t - float(_pop.get(id, -9.9))
		var hot := clampf(1.0 - age / 0.35, 0.0, 1.0)
		var col: Color = it[3]
		_txt(font, Vector2(x, y0 + 20), String(it[1]), FS_S, TEXT_DIM)
		var lw := font.get_string_size(String(it[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, FS_S).x
		var vfs := FS_L if hot > 0.25 else FS_M
		var vcol := Color(1, 1, 1) if hot > 0.25 else col
		_txt(font, Vector2(x + lw + 8.0, y0 + 21), String(it[2]), vfs, vcol)
		_chip[id] = Vector2(x + lw + 18.0, y0 + 14.0)
		x += cw


## 拾った箱が数字チップへ飛ぶ（拾った瞬間が黙っていない）。
func _draw_box_fly(sz: Vector2) -> void:
	var dst: Vector2 = _chip.get("boxes", Vector2(sz.x * 0.8, BAR_H + SYNC_H + 14.0))
	for b in _box_fly:
		var k := clampf((_t - float(b["t0"])) / 0.85, 0.0, 1.0)
		var src := Vector2(sz.x * 0.62, sz.y * 0.58)
		var e := 1.0 - pow(1.0 - k, 3.0)
		var p := src.lerp(dst, e) + Vector2(0, -sin(k * PI) * 90.0)
		var s := 20.0 * (1.0 - k * 0.5)
		var a := 1.0 - pow(k, 3.0)
		draw_rect(_snap(Rect2(p.x - s * 0.5, p.y - s * 0.5, s, s)), Color(0.28, 0.20, 0.10, a))
		draw_rect(_snap(Rect2(p.x - s * 0.5, p.y - s * 0.5, s, s)),
				Color(GOLD.r, GOLD.g, GOLD.b, a), false, 2.0)
		draw_rect(_snap(Rect2(p.x - s * 0.5, p.y - 2.0, s, 3.0)), Color(GOLD.r, GOLD.g, GOLD.b, a))


## 階層が上がった瞬間のバナー（全幅の帯が左右に開いて `B2F` を出す）。
func _draw_floor_banner(sz: Vector2, font: Font) -> void:
	var age := _t - _floor_fx
	if age < 0.0 or age > 2.6:
		return
	var open := _e_out(age / 0.30, 2.6)
	var fade := _e_in_out(clampf((2.6 - age) / 0.5, 0.0, 1.0))
	var h := 96.0
	var y := sz.y * 0.28
	var w := sz.x * open
	draw_rect(_snap(Rect2((sz.x - w) * 0.5, y, w, h)), Color(0.02, 0.03, 0.06, 0.92 * fade))
	draw_rect(_snap(Rect2((sz.x - w) * 0.5, y, w, 2)), Color(CYAN.r, CYAN.g, CYAN.b, 0.9 * fade))
	draw_rect(_snap(Rect2((sz.x - w) * 0.5, y + h - 2, w, 2)),
			Color(CYAN.r, CYAN.g, CYAN.b, 0.9 * fade))
	var ta := clampf((age - 0.22) / 0.20, 0.0, 1.0) * fade
	if ta <= 0.0:
		return
	var lbl := _floor_label if _floor_label != "" else "B%dF" % _floor_no
	var lw := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_H).x
	_txt(font, Vector2((sz.x - lw) * 0.5, y + 68), lbl, FS_H, Color(1, 1, 1, ta))
	var sub := "到達"
	var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_M).x
	_txt(font, Vector2((sz.x - sw) * 0.5, y + 26), sub, FS_M, Color(CYAN.r, CYAN.g, CYAN.b, ta))


# ══ レベルアップ（画面の山） ═══════════════════════════════════════════
# 通常回：一瞬のフラッシュ＋`同期率 Lv.7` がせり上がってフェード（1.8秒）。
# 共鳴回（Lv3/6/9/12）：カードで名前と効果を大きく見せる（3.6秒）。音は main 側。
func _draw_levelup(sz: Vector2, font: Font) -> void:
	if _lv_fx.is_empty():
		return
	var res_name := String(_lv_fx.get("name", ""))
	var has_res := res_name != ""
	var dur := 3.6 if has_res else 1.8
	var age := _t - float(_lv_fx["t0"])
	if age > dur:
		_lv_fx = {}
		return
	# ① 画面全体の一瞬のフラッシュ
	if age < 0.26:
		var f := 1.0 - _e_out(age / 0.26, 1.6)
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.72, 0.95, 1.0, (0.60 if has_res else 0.42) * f))
	# ② 広がる矩形リング（角丸もグローも使わない・この画面の作法どおり）
	var cx := sz.x * 0.5
	var cy := sz.y * 0.42
	for j in 2:
		var rk := clampf((age - j * 0.12) / 0.65, 0.0, 1.0)
		if rk <= 0.0 or rk >= 1.0:
			continue
		var re := _e_out(rk, 2.4)
		var rw := 60.0 + re * sz.x * 0.72
		var rh := rw * 0.42
		draw_rect(_snap(Rect2(cx - rw * 0.5, cy - rh * 0.5, rw, rh)),
				Color(CYAN.r, CYAN.g, CYAN.b,
						0.55 * (1.0 - _e_in_out(clampf((rk - 0.15) / 0.85, 0.0, 1.0)))), false, 3.0)
	# ③ せり上がる大文字
	var txt := "同期率 Lv.%d" % int(_lv_fx.get("lv", 0))
	var rise := 1.0 - pow(1.0 - clampf(age / 0.45, 0.0, 1.0), 3.0)
	var ty := cy + 46.0 - rise * 64.0
	var ta := _e_in_out(clampf((dur - age) / 0.55, 0.0, 1.0)) * _e_in_out(clampf(age / 0.08, 0.0, 1.0))
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_H).x
	draw_rect(_snap(Rect2(cx - tw * 0.5 - 22, ty - 46, tw + 44, 58)),
			Color(0.02, 0.03, 0.06, 0.72 * ta))
	draw_string(font, Vector2(cx - tw * 0.5 + 2, ty + 2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1,
			FS_H, Color(0, 0, 0, 0.7 * ta))
	draw_string(font, Vector2(cx - tw * 0.5, ty), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_H,
			Color(1, 1, 1, ta))
	var atk := "攻撃 x%.2f" % float(_lv_fx.get("atk", 1.0))
	var aw := font.get_string_size(atk, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_M).x
	draw_string(font, Vector2(cx - aw * 0.5, ty + 30), atk, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_M,
			Color(CYAN.r, CYAN.g, CYAN.b, ta))
	if not has_res:
		return
	# ④ 共鳴カード（Lv3/6/9/12 だけ。25分で4回しか出ない＝ここが本当の山）
	var ck := clampf((age - 0.40) / 0.26, 0.0, 1.0)
	if ck <= 0.0:
		return
	var ce := 1.0 - pow(1.0 - ck, 3.0)
	var ca := _e_in_out(clampf((dur - age) / 0.6, 0.0, 1.0))
	var full := Vector2(470.0, 168.0)
	var cs := full * (0.62 + 0.38 * ce)
	var top := cy + 96.0
	var cr := _snap(Rect2(cx - cs.x * 0.5, top - cs.y * 0.5 + 40.0, cs.x, cs.y))
	draw_rect(cr, Color(0.03, 0.05, 0.09, 0.96 * ca))
	draw_rect(cr, Color(CYAN.r, CYAN.g, CYAN.b, 0.95 * ca), false, 3.0)
	draw_rect(_snap(Rect2(cr.position + Vector2(6, 6), cr.size - Vector2(12, 12))),
			Color(CYAN.r, CYAN.g, CYAN.b, 0.30 * ca), false, 1.0)
	# 四隅の切り欠き（カードであることを角丸なしで示す）
	for c: Vector2 in [cr.position, Vector2(cr.end.x - 16, cr.position.y),
			Vector2(cr.position.x, cr.end.y - 4), Vector2(cr.end.x - 16, cr.end.y - 4)]:
		draw_rect(_snap(Rect2(c.x, c.y, 16, 4)), Color(1, 1, 1, 0.8 * ca))
	if ck < 1.0:
		return
	var cap := "共鳴獲得"
	var pw := font.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_S).x
	_txt(font, Vector2(cx - pw * 0.5, cr.position.y + 30), cap, FS_S, Color(GOLD.r, GOLD.g, GOLD.b, ca))
	var nw := font.get_string_size(res_name, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_XL).x
	draw_string(font, Vector2(cx - nw * 0.5 + 2, cr.position.y + 84), res_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FS_XL, Color(0, 0, 0, 0.7 * ca))
	draw_string(font, Vector2(cx - nw * 0.5, cr.position.y + 82), res_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FS_XL, Color(1, 1, 1, ca))
	draw_rect(_snap(Rect2(cx - 60, cr.position.y + 98, 120, 1)), Color(CYAN.r, CYAN.g, CYAN.b, 0.5 * ca))
	var desc := String(_lv_fx.get("desc", ""))
	var dw := font.get_string_size(desc, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_L).x
	_txt(font, Vector2(cx - dw * 0.5, cr.position.y + 130), desc, FS_L, Color(CYAN.r, CYAN.g, CYAN.b, ca))
