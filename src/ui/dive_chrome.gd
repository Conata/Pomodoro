class_name DiveChrome
extends Control
## 探索ビューの配信UI（チロップ）。ポスト処理レイヤーの「上」に重ね、
## カラグレ/ブルーム/DoFの影響を受けずに常にクッキリ描く。
## 座標系は探索ステージ（dive_frame）と一致させる（main が毎フレーム位置/サイズを合わせる）。

const VIEWERS_BASE := 8200

const MAX_CAMS := 4  # 最大ワイプ数（メンバー数に合わせて自動で増減）
const CAM_GAP := 8.0

var sim: KuroSim = null
var dive: DiveView = null
var morning_mode := false          # true のとき MORNING 食事ワイプを表示
var _cams: Array = []  # FaceCam × MAX_CAMS
var _last_bubble_key := ""  # "girl_id|text" 変化検出用


func _ready() -> void:
	for i in MAX_CAMS:
		var cam := FaceCam.new()
		cam.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cam.visible = false
		add_child(cam)
		_cams.append(cam)


func _process(_delta: float) -> void:
	if sim == null:
		for cam in _cams:
			cam.visible = false
		if visible:
			queue_redraw()
		return

	if morning_mode:
		# MORNING：全キャラが食事中ワイプとして右下に並ぶ
		_update_cams(KuroData.GIRL_ORDER, "", true)
	elif dive != null and sim.state["run"]["active"]:
		# DIVE：潜行メンバーが配信ワイプとして並ぶ
		var bubble_girl := ""
		var bubble_text := ""
		if not dive._bubble.is_empty():
			bubble_girl = String(dive._bubble.get("girl", ""))
			bubble_text = String(dive._bubble.get("text", ""))
		# 新しいセリフが来たら対象キャラのワイプにフォネムシーケンスを渡す
		var bubble_key := bubble_girl + "|" + bubble_text
		if bubble_key != _last_bubble_key:
			_last_bubble_key = bubble_key
			if not bubble_text.is_empty():
				for cam in _cams:
					var fc := cam as FaceCam
					if fc.girl_id == bubble_girl:
						fc.start_speech(bubble_text)
		_update_cams(sim.divers(), bubble_girl, false)
	else:
		for cam in _cams:
			cam.visible = false

	if visible:
		queue_redraw()


func _update_cams(members: Array, bubble_girl: String, is_eating: bool) -> void:
	var n := mini(members.size(), MAX_CAMS)
	var max_w := clampf(size.x * 0.26, 96.0, 168.0)
	var avail := size.x * 0.70 - CAM_GAP * maxf(n - 1, 0)
	var w := minf(max_w, avail / maxf(n, 1))
	var h := w * 1.14
	for i in MAX_CAMS:
		var cam: FaceCam = _cams[i]
		if i < n:
			var gid := String(members[i])
			cam.girl_id = gid
			# wipe は右端に並ぶ。i=0が最右端→左向き、i>0は左寄り→右向きで画面内を向く
			cam.flip_h  = (i == 0)
			cam.eating = is_eating
			cam.speaking = (not is_eating) and gid == bubble_girl
			cam.size = Vector2(w, h)
			cam.position = Vector2(
				size.x - 12.0 - (i + 1) * w - i * CAM_GAP,
				size.y - h - 12.0)
			cam.visible = true
		else:
			cam.visible = false


func _draw() -> void:
	if sim == null or dive == null:
		return
	if not sim.state["run"]["active"]:
		return
	var sz := size
	var font := get_theme_default_font()
	var fl := sim.current_floor()
	var biome: Dictionary = KuroData.BIOMES[fl % KuroData.BIOMES.size()]
	var dist := float(sim.state["dist"])
	var in_combat: bool = sim.state["in_combat"]
	_draw_stream_chrome(sz, font, fl, biome, dist, in_combat)
	_draw_minimap(sz, font, fl, dist)
	_draw_dialog_log(sz, font)


## 配信チロップ：左上=階層/探索率、右上=LIVE+配信名+視聴/いいね、
## 中央上=残り時間（配信タイマー）、左下=REC。
func _draw_stream_chrome(sz: Vector2, font: Font, fl: int, biome: Dictionary,
		dist: float, in_combat: bool) -> void:
	var pad := 12.0
	var pct := int(fmod(dist, KuroData.FLOOR_LEN) / KuroData.FLOOR_LEN * 100.0)
	draw_string(font, Vector2(pad, 26), "B%dF %s" % [fl + 1, String(biome["name"])],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, DS.TEXT)
	draw_string(font, Vector2(pad, 46), "探索率 %d%%" % pct,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.85, 1.0, 0.85))
	# 右上：LIVE バッジ＋配信タイトル
	var streamer := "ムュウ"
	var ds := sim.divers()
	if not ds.is_empty() and KuroData.GIRLS.has(ds[0]):
		streamer = String(KuroData.GIRLS[ds[0]]["name"])
	var title := "%sの都市伝説LIVE" % streamer
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	if fposmod(dive.pulse, 1.4) < 1.1:
		draw_circle(Vector2(sz.x - pad - tw - 50.0, 22), 5.0, Color(1.0, 0.2, 0.25))
	draw_string(font, Vector2(sz.x - pad - tw - 40.0, 27), "LIVE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.35, 0.4))
	draw_string(font, Vector2(sz.x - pad - tw, 27), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, DS.TEXT)
	# 視聴者数・いいね（distベースで緩く増える＋ゆらぎ）
	var viewers := VIEWERS_BASE + int(dist * 1.1) + int(40.0 * sin(dive.pulse * 0.7))
	var likes := viewers * 26 / 10
	var stat := "視聴 %s ・ いいね %s" % [_fmt_comma(viewers), _fmt_k(likes)]
	var sw := font.get_string_size(stat, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, Vector2(sz.x - pad - sw, 48), stat,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.9, 1.0, 0.85))
	# 中央上：残り時間（配信タイマー）
	if dive.remaining >= 0.0:
		var t := _mmss(dive.remaining)
		var tsz := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 32)
		draw_string(font, Vector2((sz.x - tsz.x) * 0.5 + 1, 43), t,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(0, 0, 0, 0.5))
		draw_string(font, Vector2((sz.x - tsz.x) * 0.5, 42), t,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 32, DS.ACCENT)
	# 左下：REC（掛け合いログの上）
	var ry := sz.y - 124.0
	if fposmod(dive.pulse, 1.2) < 0.9:
		draw_circle(Vector2(pad + 6, ry - 5), 5.0, Color(1.0, 0.2, 0.25))
	draw_string(font, Vector2(pad + 16, ry), "REC", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.5, 0.55))
	if in_combat:
		draw_string(font, Vector2(pad + 64, ry), "交戦中", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.6, 0.65))


## 左上のミニマップ。階層の進行をノード列で表す。
func _draw_minimap(sz: Vector2, font: Font, fl: int, dist: float) -> void:
	var w := sz.x * 0.28
	var h := maxf(46.0, sz.y * 0.11)
	var x := 12.0
	var y := 64.0
	draw_rect(Rect2(x, y, w, h), Color(0.03, 0.04, 0.08, 0.55))
	draw_rect(Rect2(x, y, w, h), Color(0.4, 0.85, 1.0, 0.25), false, 1.0)
	var cells := 6
	var prog := fmod(dist, KuroData.FLOOR_LEN) / KuroData.FLOOR_LEN
	var cur := clampi(int(prog * cells), 0, cells - 1)
	var cw := w / float(cells + 1)
	var cy := y + h * 0.46
	for k in cells:
		var cx := x + cw * (k + 1)
		if k > 0:
			draw_line(Vector2(x + cw * k, cy), Vector2(cx, cy), Color(0.4, 0.7, 1.0, 0.4), 1.5)
		if k == cur:
			draw_circle(Vector2(cx, cy), 4.5 + 1.5 * sin(dive.pulse * 4.0), Color(0.4, 1.0, 0.85))
		elif k < cur:
			draw_circle(Vector2(cx, cy), 3.5, Color(0.5, 0.8, 1.0, 0.7))
		else:
			draw_circle(Vector2(cx, cy), 3.0, Color(0.4, 0.5, 0.7, 0.4))
	draw_string(font, Vector2(x + 6, y + h - 6), "MAP B%dF" % (fl + 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.8, 1.0, 0.7))


## 左下の掛け合いログ（直近4行・下ほど新しく濃い）。
func _draw_dialog_log(sz: Vector2, font: Font) -> void:
	var pad := 12.0
	var fs := 16
	var lh := 22.0
	var dlog: Array = dive._dialog
	var n := dlog.size()
	if n == 0:
		return
	var y0 := sz.y - 16.0 - n * lh
	draw_rect(Rect2(0, y0 - 8, sz.x * 0.64, n * lh + 12), Color(0.02, 0.02, 0.05, 0.5))
	for i in n:
		var d: Dictionary = dlog[i]
		var who := String(d["who"])
		if KuroData.GIRLS.has(d["who"]):
			who = String(KuroData.GIRLS[d["who"]]["name"])
		var y := y0 + i * lh + 16.0
		var alpha := lerpf(0.55, 1.0, float(i + 1) / float(n))
		var col: Color = d["col"]
		draw_string(font, Vector2(pad + 2, y), who, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(col.r, col.g, col.b, alpha))
		var nw := font.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(pad + 2 + nw, y), "「%s」" % String(d["text"]),
				HORIZONTAL_ALIGNMENT_LEFT, int(sz.x * 0.60 - nw), fs, Color(0.92, 0.95, 1.0, alpha))


func _fmt_comma(v: int) -> String:
	var s := str(v)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out


func _fmt_k(v: int) -> String:
	return ("%.1fK" % (v / 1000.0)) if v >= 1000 else str(v)


func _mmss(sec: float) -> String:
	var s := int(ceil(sec))
	return "%02d:%02d" % [int(s / 60.0), s % 60]


## 指定キャラのワイプに表情を設定する（main._pump_events から呼ぶ）。
## duration 秒後に自動で neutral に戻る。
func set_expr(girl_id: String, expr: String, duration: float = 1.8) -> void:
	for cam in _cams:
		if (cam as FaceCam).girl_id == girl_id:
			(cam as FaceCam).set_expression(expr, duration)
			return
