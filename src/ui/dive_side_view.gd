class_name DiveSideView
extends Control
## 潜航の横スクロールステージ（タスクバーヒーロー型）。
## 構図：左＝接続ポータル＋ステージ章票、中央左＝隊列（チビキャラが右へ行進）、
## 右＝敵がスライドイン、下＝石畳の帯、奥＝ネオン都市のパララックス。
## 頭上にHPミニバー＋スキルCDピップ。main.gd が毎フレーム set_view() で駆動する。

const GROUND_Y := 0.70      # 地面ラインの画面比
const BAND_H := 118.0       # 石畳帯の高さ
const BG_SCALE := 1.6       # 都市パララックスの拡大率（空の余白を埋める）
const PARTY_X0 := 132.0     # 隊列先頭のx
const PARTY_GAP := 58.0     # 隊列間隔
const ENEMY_X0 := 0.66      # 敵スロット先頭（画面比）
const ENEMY_GAP := 62.0
const GIRL_H := 84.0        # 味方の表示身長(px)
const GIRL_PIX_H := 32      # 味方スプライトのピクセル化高さ（敵ドットと画素密度を揃える）
const MOB_H := 78.0         # 雑魚の表示身長(px)
const BOSS_H := 148.0       # ボスの表示身長(px)

const PINK := Color(1.0, 0.36, 0.72)
const CYAN := Color(0.35, 0.92, 1.0)
const PURPLE := Color(0.66, 0.4, 1.0)
const GOLD := Color(1.0, 0.82, 0.4)
const HP_COL := Color(0.45, 0.9, 0.5)

# set_view() で main.gd から毎フレーム
var dist := 0.0
var in_combat := false
var party: Array = []       # [{id, hp, mhp, ready, slots}]
var mobs: Array = []        # [{sprite, hp, boss}]
var gold_gain := 0

var _t := 0.0
var _anims: Dictionary = {}       # girl_id -> ChibiAnim
var _tex_cache: Dictionary = {}   # path -> Texture2D|null
var _pix_cache: Dictionary = {}   # path -> ピクセル化済み Texture2D|null（タスクバーヒーロー密度）
var _enemy_x: Array = []          # 敵スロットの現在x（右からスライドイン）
var _mob_hp0: Array = []          # 敵スロットの初期HP（バー比率用）
var _last_mob_count := 0
var _shake := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	for id in _anims:
		(_anims[id] as ChibiAnim).tick(delta)
	if _shake > 0.004:
		_shake = maxf(0.0, _shake - delta * 1.5)
	queue_redraw()


## 戦闘のカメラシェイク（main の punch 互換）。
func punch(mag := 0.3) -> void:
	_shake = maxf(_shake, mag)


## main.gd から毎フレーム：sim の実データを流し込む。
func set_view(d: Dictionary) -> void:
	dist = float(d.get("dist", dist))
	in_combat = bool(d.get("in_combat", false))
	party = d.get("party", [])
	mobs = d.get("mobs", [])
	gold_gain = int(d.get("gold_gain", gold_gain))
	# 隊列アニメの用意＆パラメーター更新（戦闘中は攻撃を周期リトリガー）
	for i in party.size():
		var id := String(party[i]["id"])
		if not _anims.has(id):
			_anims[id] = ChibiAnim.new(id)
		var dead: bool = float(party[i]["hp"]) <= 0.0
		var atk_pulse := in_combat and fposmod(_t + i * 0.53, 1.7) < 1.15
		(_anims[id] as ChibiAnim).update_params(0.0 if in_combat else 1.0, atk_pulse, false, dead)
	# 敵スロット：新しい群れが来たらスライドイン＆初期HPを記録
	if mobs.size() > _last_mob_count:
		for i in mobs.size():
			if i >= _enemy_x.size():
				_enemy_x.append(size.x + 60.0 + i * 40.0)
				_mob_hp0.append(float(mobs[i]["hp"]))
			elif i >= _last_mob_count:
				_enemy_x[i] = size.x + 60.0 + i * 40.0
				_mob_hp0[i] = float(mobs[i]["hp"])
	_last_mob_count = mobs.size()
	for i in mini(mobs.size(), _mob_hp0.size()):
		_mob_hp0[i] = maxf(_mob_hp0[i], float(mobs[i]["hp"]))


func _tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[path]


## 味方チビをタスクバーヒーロー密度へ落とす：縮小→α2値化→ニアレスト拡大。
## 高精細チビ(144x192)と16-32pxの敵ドットの解像度ミスマッチを消し、画面の画素を統一する。
func _pix_tex(path: String) -> Texture2D:
	if _pix_cache.has(path):
		return _pix_cache[path]
	var t: Texture2D = null
	var src := _tex(path)
	if src != null:
		var img := src.get_image()
		if img != null:
			img = img.duplicate()
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			var w := maxi(int(round(img.get_width() * float(GIRL_PIX_H) / maxf(img.get_height(), 1.0))), 1)
			img.resize(w, GIRL_PIX_H, Image.INTERPOLATE_BILINEAR)
			# αを2値化（本物のドット絵はソフトエッジを持たない）
			for y in img.get_height():
				for x in w:
					var c := img.get_pixel(x, y)
					c.a = 1.0 if c.a > 0.42 else 0.0
					img.set_pixel(x, y, c)
			t = ImageTexture.create_from_image(img)
	_pix_cache[path] = t
	return t


## 敵テクスチャ（idle/run 4コマ・dungeon frames）。
func _mob_tex(sprite_name: String, anim: String, fps := 6.0) -> Texture2D:
	var f := int(_t * fps) % 4
	var tex := _tex("res://assets/third_party/dungeon/frames/%s_%s_anim_f%d.png" % [sprite_name, anim, f])
	if tex == null:
		tex = _tex("res://assets/third_party/dungeon/frames/%s_anim_f%d.png" % [sprite_name, f])
	if tex == null:
		tex = _tex("res://assets/third_party/dungeon/frames/goblin_%s_anim_f%d.png" % [anim, f])
	return tex


## 高さ target_h で足元(feet)基準に描く。flip=true で左向き。
func _draw_actor(tex: Texture2D, feet: Vector2, target_h: float, flip := false, tint := Color(1, 1, 1)) -> Rect2:
	if tex == null:
		return Rect2(feet, Vector2.ZERO)
	var ts := tex.get_size()
	var s := target_h / maxf(ts.y, 1.0)
	var w := ts.x * s
	var r := Rect2(feet.x - w * 0.5, feet.y - target_h, w, target_h)
	if flip:
		draw_texture_rect(tex, Rect2(r.position.x + w, r.position.y, -w, target_h), false, tint)
	else:
		draw_texture_rect(tex, r, false, tint)
	return r


func _draw() -> void:
	var sz := size
	var gy := sz.y * GROUND_Y
	var font := get_theme_default_font()
	# シェイク（以降の全描画に効く）
	if _shake > 0.004:
		draw_set_transform(Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * 14.0, 0.0, Vector2.ONE)

	_draw_sky(sz, gy)
	_draw_ground(sz, gy)
	_draw_portal(Vector2(64, gy), font)
	_draw_goal(sz, gy)

	# ===== 隊列（左→右へ行進。戦闘中は停止して攻撃モーション）=====
	for i in party.size():
		var p: Dictionary = party[i]
		var id := String(p["id"])
		var bob := 0.0 if in_combat else absf(sin(_t * 7.0 + i * 1.1)) * 3.0
		var lunge := (maxf(0.0, sin(_t * 3.8 + i * 0.53)) * 10.0) if in_combat else 0.0
		var feet := Vector2(PARTY_X0 + i * PARTY_GAP + lunge, gy - bob)
		var dead: bool = float(p["hp"]) <= 0.0
		var tex: Texture2D = null
		if _anims.has(id):
			tex = _pix_tex((_anims[id] as ChibiAnim).current_path())
		if tex == null:
			tex = _pix_tex("res://assets/generated/sprites/%s/idle_f0.png" % id)
		var tint := Color(0.5, 0.5, 0.58) if dead else Color(1, 1, 1)
		# 接地影
		_blob_shadow(feet, 20.0)
		var r := _draw_actor(tex, feet, GIRL_H, false, tint)
		if not dead:
			_draw_head_ui(Vector2(feet.x, r.position.y - 8.0), 36.0,
					float(p["hp"]) / maxf(float(p["mhp"]), 1.0), HP_COL,
					int(p.get("ready", 0)), int(p.get("slots", 0)))

	# ===== 敵（右からスライドイン・左向き）=====
	if in_combat:
		for i in mobs.size():
			var m: Dictionary = mobs[i]
			var boss: bool = bool(m.get("boss", false))
			var slot_x := sz.x * ENEMY_X0 + i * ENEMY_GAP + (26.0 if boss else 0.0)
			if i < _enemy_x.size():
				_enemy_x[i] = lerpf(float(_enemy_x[i]), slot_x, 0.10)
			var ex := float(_enemy_x[i]) if i < _enemy_x.size() else slot_x
			var arriving := absf(ex - slot_x) > 8.0
			var lunge := 0.0 if arriving else maxf(0.0, sin(_t * 4.2 + i * 1.7)) * 9.0
			var feet := Vector2(ex - lunge, gy)
			var h := BOSS_H if boss else MOB_H
			_blob_shadow(feet, 26.0 if boss else 16.0)
			var tex := _mob_tex(String(m.get("sprite", "goblin")), "run" if arriving else "idle")
			var r := _draw_actor(tex, feet, h, true)
			var hp0: float = float(_mob_hp0[i]) if i < _mob_hp0.size() else float(m["hp"])
			_draw_head_ui(Vector2(feet.x, r.position.y - 8.0), 46.0 if boss else 32.0,
					float(m["hp"]) / maxf(hp0, 1.0), Color(1.0, 0.42, 0.4), 0, 0)

	if _shake > 0.004:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 空とネオン都市のパララックス（dist でスクロール・戦闘中は自然停止）。
func _draw_sky(sz: Vector2, gy: float) -> void:
	# 空の縦グラデ（深い紺→地平の紫）
	draw_rect(Rect2(0, 0, sz.x, gy), Color(0.03, 0.03, 0.08))
	var pts := PackedVector2Array([Vector2(0, gy - 260), Vector2(sz.x, gy - 260), Vector2(sz.x, gy), Vector2(0, gy)])
	draw_polygon(pts, PackedColorArray([Color(0.03, 0.03, 0.08, 0.0), Color(0.03, 0.03, 0.08, 0.0),
			Color(0.12, 0.05, 0.16, 1.0), Color(0.12, 0.05, 0.16, 1.0)]))
	# 星（決定論・ゆっくり瞬く）
	for i in 46:
		var rx := fposmod(sin(i * 91.7) * 43758.5453, 1.0)
		var ry := fposmod(sin(i * 41.3) * 24634.6345, 1.0)
		var tw := 0.35 + 0.3 * sin(_t * (0.8 + rx * 1.6) + i)
		draw_circle(Vector2(rx * sz.x, ry * (gy - BG_SCALE * 300.0)), 1.2 + rx, Color(0.8, 0.85, 1.0, tw * 0.5))
	# 月（薄い暈）
	Kit.spot(self, Vector2(sz.x * 0.78, gy - BG_SCALE * 330.0), 90.0, Color(0.7, 0.8, 1.0), 0.10)
	draw_circle(Vector2(sz.x * 0.78, gy - BG_SCALE * 330.0), 26.0, Color(0.85, 0.9, 1.0, 0.22))
	# パララックス（都市シルエットを拡大タイル）
	_draw_layer("res://assets/generated/bg/city_far.png", sz, gy, 0.35, Color(0.5, 0.45, 0.7, 0.55))
	_draw_layer("res://assets/generated/bg/city_mid.png", sz, gy, 1.0, Color(0.65, 0.55, 0.85, 0.8))


func _draw_layer(path: String, sz: Vector2, gy: float, speed: float, tint: Color) -> void:
	var tex := _tex(path)
	if tex == null:
		return
	var ts := tex.get_size() * BG_SCALE
	var scroll := fposmod(dist * 14.0 * speed, ts.x)
	var y := gy - ts.y
	var x := -scroll
	while x < sz.x:
		draw_texture_rect(tex, Rect2(x, y, ts.x, ts.y), false, tint)
		x += ts.x


## 石畳の帯（決定論ノイズで丸石を敷く）＋ネオンの縁。
func _draw_ground(sz: Vector2, gy: float) -> void:
	draw_rect(Rect2(0, gy, sz.x, BAND_H), Color(0.07, 0.07, 0.11))
	draw_rect(Rect2(0, gy + BAND_H, sz.x, sz.y - gy - BAND_H), Color(0.04, 0.04, 0.07))
	var scroll := dist * 14.0
	var cols := int(sz.x / 34.0) + 3
	for row in 3:
		var ry := gy + 14.0 + row * 40.0
		for c in cols:
			var wx := c * 34.0 + fposmod(-scroll, 34.0) - 34.0 + (17.0 if row % 2 == 1 else 0.0)
			var seed_i := int(floor((c * 34.0 + scroll) / 34.0)) * 3 + row
			var rr := fposmod(sin(seed_i * 127.1) * 43758.5453, 1.0)
			var tone := 0.10 + rr * 0.05
			_ellipse(Vector2(wx, ry), Vector2(19.0, 13.0), Color(tone, tone, tone + 0.045))
	# ネオンの縁（上辺）
	draw_rect(Rect2(0, gy - 2.0, sz.x, 2.5), Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.55))
	Kit.spot(self, Vector2(sz.x * 0.5, gy), sz.x * 0.6, PURPLE, 0.05)


func _ellipse(c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 14:
		var a := TAU * i / 14.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(pts, col)


func _blob_shadow(feet: Vector2, r: float) -> void:
	_ellipse(feet + Vector2(0, 3), Vector2(r, r * 0.32), Color(0, 0, 0, 0.35))


## 接続ポータル（左端・青い渦）＋ステージ章票＋獲得ゴールド。
func _draw_portal(base: Vector2, font: Font) -> void:
	var c := base + Vector2(0, -52.0)
	Kit.spot(self, c, 66.0, CYAN, 0.18)
	var pr := 30.0 + 2.5 * sin(_t * 2.4)
	draw_arc(c, pr, _t * 1.8, _t * 1.8 + TAU * 0.8, 30, Color(0.35, 0.75, 1.0), 4.0)
	draw_arc(c, pr * 0.62, -_t * 2.6, -_t * 2.6 + TAU * 0.66, 24, CYAN, 3.0)
	draw_circle(c, pr * 0.34, Color(0.5, 0.85, 1.0, 0.9))
	_blob_shadow(base, 20.0)
	# 章票 B{階}-{節}
	var fl := int(dist / KuroData.FLOOR_LEN) + 1
	var seg := int(fposmod(dist, KuroData.FLOOR_LEN) / (KuroData.FLOOR_LEN / 3.0)) + 1
	var chip := "B%d-%d" % [fl, seg]
	var cw := font.get_string_size(chip, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 24
	var cr := Rect2(c.x - cw * 0.5, c.y - 96.0, cw, 30.0)
	Kit.panel(self, cr, Color(0.05, 0.05, 0.09, 0.9), Color(1, 1, 1, 0.18), 15.0, 1.0)
	draw_string(font, Vector2(cr.position.x + 12, cr.position.y + 21), chip,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.92, 0.94, 1.0))
	# 獲得ゴールド（章票の右）
	if gold_gain > 0:
		var gtxt := "%d" % gold_gain
		var gx := cr.position.x + cw + 12.0
		draw_circle(Vector2(gx + 7, cr.position.y + 15), 7.0, GOLD)
		draw_circle(Vector2(gx + 7, cr.position.y + 15), 4.5, Color(1.0, 0.92, 0.6))
		draw_string(font, Vector2(gx + 18, cr.position.y + 21), gtxt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, GOLD)


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
	Kit.spot(self, c, 80.0, col, 0.2)
	var pr := 36.0 + 3.0 * sin(_t * (3.5 if near_boss else 1.8))
	draw_arc(c, pr, -_t * 1.4, -_t * 1.4 + TAU * 0.82, 30, col, 4.0)
	draw_circle(c, pr * 0.3, Color(col.r, col.g, col.b, 0.8))
	_blob_shadow(Vector2(gx, gy), 22.0)


## 頭上UI：HPミニバー＋スキルCDピップ（点灯=撃てる）。
func _draw_head_ui(top: Vector2, w: float, hp_ratio: float, col: Color, ready: int, slots: int) -> void:
	var r := Rect2(top.x - w * 0.5, top.y - 5.0, w, 5.0)
	draw_rect(Rect2(r.position - Vector2(1, 1), r.size + Vector2(2, 2)), Color(0, 0, 0, 0.6))
	var ratio := clampf(hp_ratio, 0.0, 1.0)
	var bar_col := col if ratio > 0.3 else Color(1.0, 0.42, 0.4)
	draw_rect(Rect2(r.position, Vector2(r.size.x * ratio, r.size.y)), bar_col)
	# スキルピップ（味方のみ・装備枠ぶん並べ、撃てる数だけ点灯）
	if slots > 0:
		var px := top.x - (slots * 12.0 - 4.0) * 0.5
		for i in slots:
			var lit := i < ready
			var pc := Vector2(px + i * 12.0 + 4.0, top.y - 14.0)
			draw_circle(pc, 5.0, Color(0, 0, 0, 0.6))
			draw_circle(pc, 4.0, GOLD if lit else Color(0.35, 0.36, 0.42))
			if lit:
				draw_circle(pc, 2.0, Color(1.0, 0.95, 0.75))
