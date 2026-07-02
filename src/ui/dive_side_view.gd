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

# ── 実体アンカーの戦闘FX（ダメージ数字・斬撃・被弾・スキルバースト）──
var _party_pos: Array = []   # 直近フレームの味方足元（floaterの追従先）
var _enemy_pos: Array = []   # 直近フレームの敵足元
var _floaters: Array = []    # {txt, col, side, slot, t0, jx}
var _slashes: Array = []     # 敵への斬撃 {slot, t0}
var _hurt_t := -9.9          # 盾役の被弾時刻（赤フラッシュ＋ノックバック）
var _bursts: Array = []      # スキルバースト {kind, t0}
var _striker := -1           # 直近で「殴った」味方（踏み込み演出）
var _strike_t := -9.9
var _knock: Array = []       # 敵スロットのノックバック残量

# ── 会話劇（戦闘・道中の掛け合い吹き出し。Banter 駆動）──
var _bubble: Dictionary = {}       # 表示中の吹き出し {gid, text, t0, dur}
var _bubble_q: Array = []          # 掛け合いの残り行 [[gid, text], ...]
var _banter_rng := RandomNumberGenerator.new()
var _banter_wait := 3.0            # 次の自発バンターまでの秒
var _banter_cd: Dictionary = {}    # カテゴリ別クールダウン（最終発話時刻）
var _was_combat := false


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
					var ex := Banter.pick_exchange(cast, _banter_rng)
					if not ex.is_empty():
						_start_exchange(ex)
				else:
					var pick := Banter.pick("combat" if in_combat else "idle", cast, _banter_rng)
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
		var ex := Banter.pick_exchange(cast, _banter_rng)
		if not ex.is_empty():
			_banter_cd[cat] = _t
			_bubble = {}
			_start_exchange(ex)
			return
	var pick := Banter.pick(cat, cast, _banter_rng)
	if pick.is_empty():
		return
	_banter_cd[cat] = _t
	if interrupt:
		_bubble_q = []
	_bubble = {}
	_say(String(pick["girl"]), String(pick["text"]))
	_banter_wait = maxf(_banter_wait, 5.0)


## 戦闘のカメラシェイク（main の punch 互換）。
func punch(mag := 0.3) -> void:
	_shake = maxf(_shake, mag)


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


## main.gd から潜航イベントを受け取り、実体に紐づくFXへ変換する。
## 「誰が殴って→誰に当たって→いくら出たか」の因果を1画面で読めるようにする。
func add_events(events: Array) -> void:
	for e in events:
		match String(e.get("kind", "")):
			"dmg_pop":
				var val := int(e.get("val", 0))
				if String(e.get("at", "enemy")) == "enemy":
					# 与ダメ：殴り手（生存味方を巡回）が踏み込み、対象の敵に斬撃＋数字
					var slot := randi() % maxi(mobs.size(), 1)
					_floaters.append({"txt": "%d" % val, "col": GOLD, "side": "enemy",
							"slot": slot, "t0": _t, "jx": randf_range(-14.0, 14.0)})
					_slashes.append({"slot": slot, "t0": _t})
					if slot < _knock.size():
						_knock[slot] = 10.0
					_striker = _next_striker()
					_strike_t = _t
				else:
					# 被ダメ：盾役（先頭の生存者）の頭上に赤数字＋赤フラッシュ
					_floaters.append({"txt": "-%d" % val, "col": Color(1.0, 0.42, 0.45), "side": "party",
							"slot": _tank_index(), "t0": _t, "jx": randf_range(-10.0, 10.0)})
					_hurt_t = _t
				while _floaters.size() > 14:
					_floaters.pop_front()
			"fx":
				_bursts.append({"kind": String(e.get("fx", "")), "t0": _t})
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


var _white_cache: Dictionary = {}
var _top_frac_cache: Dictionary = {}  # sprite_name -> 透明ヘッドルーム比（バー/数字の吸着用）
var _enemy_top: Array = []            # 敵スロットの見た目の頭y（used_rect補正済み）


## スプライトの「実際に絵がある領域」の上端比率（idle f0 で代表）。
func _top_frac(sprite_name: String) -> float:
	if _top_frac_cache.has(sprite_name):
		return _top_frac_cache[sprite_name]
	var frac := 0.0
	var tex := _mob_tex(sprite_name, "idle")
	if tex != null:
		var img := tex.get_image()
		if img != null:
			img = img.duplicate()
			if img.is_compressed():
				img.decompress()
			var used := img.get_used_rect()
			if used.size.y > 0:
				frac = float(used.position.y) / float(img.get_height())
	_top_frac_cache[sprite_name] = frac
	return frac

## ヒットフラッシュ用の白シルエット（α>0 を白に）。小さな敵ドットなので安価。
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

	# ===== 隊列（左→右へ行進。戦闘中は停止・殴り手が踏み込む）=====
	_party_pos.resize(party.size())
	var strike_k := clampf(1.0 - (_t - _strike_t) / 0.30, 0.0, 1.0)   # 踏み込みの残量
	var hurt_k := clampf(1.0 - (_t - _hurt_t) / 0.22, 0.0, 1.0)       # 被弾フラッシュの残量
	for i in party.size():
		var p: Dictionary = party[i]
		var id := String(p["id"])
		var bob := 0.0 if in_combat else absf(sin(_t * 7.0 + i * 1.1)) * 3.0
		var lunge := (maxf(0.0, sin(_t * 3.8 + i * 0.53)) * 6.0) if in_combat else 0.0
		if i == _striker and strike_k > 0.0:
			lunge += sin(strike_k * PI) * 34.0   # 殴り手の鋭い踏み込み（行って戻る）
		var knock_back := (sin(hurt_k * PI) * 10.0) if (i == _tank_index() and hurt_k > 0.0) else 0.0
		var feet := Vector2(PARTY_X0 + i * PARTY_GAP + lunge - knock_back, gy - bob)
		_party_pos[i] = feet
		var dead: bool = float(p["hp"]) <= 0.0
		var tex: Texture2D = null
		if _anims.has(id):
			tex = _pix_tex((_anims[id] as ChibiAnim).current_path())
		if tex == null:
			tex = _pix_tex("res://assets/generated/sprites/%s/idle_f0.png" % id)
		var tint := Color(1, 1, 1)
		if dead:
			tint = Color(0.5, 0.5, 0.58)
		elif i == _tank_index() and hurt_k > 0.0:
			tint = Color(1.0, 1.0 - hurt_k * 0.62, 1.0 - hurt_k * 0.62)   # 被弾の赤フラッシュ
		# 接地影
		_blob_shadow(feet, 20.0)
		var r := _draw_actor(tex, feet, GIRL_H, false, tint)
		if not dead:
			_draw_head_ui(Vector2(feet.x, r.position.y - 8.0), 36.0,
					float(p["hp"]) / maxf(float(p["mhp"]), 1.0), HP_COL,
					int(p.get("ready", 0)), int(p.get("slots", 0)))

	# ===== 敵（右からスライドイン・左向き・被弾で白フラッシュ＋ノックバック）=====
	_enemy_pos.resize(mobs.size())
	_enemy_top.resize(mobs.size())
	_knock.resize(maxi(mobs.size(), _knock.size()))
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
			var kn := float(_knock[i]) if _knock[i] != null else 0.0
			if kn > 0.05:
				_knock[i] = kn * 0.82   # ノックバックの減衰
			var feet := Vector2(ex - lunge + kn, gy)
			_enemy_pos[i] = feet
			var h := BOSS_H if boss else MOB_H
			_blob_shadow(feet, 26.0 if boss else 16.0)
			var sprite_name := String(m.get("sprite", "goblin"))
			var tex := _mob_tex(sprite_name, "run" if arriving else "idle")
			var r := _draw_actor(tex, feet, h, true)
			# 直近で斬られた敵は白くフラッシュ
			for sl in _slashes:
				if int(sl["slot"]) == i and _t - float(sl["t0"]) < 0.12:
					var wt := _white_tex(sprite_name, tex)
					if wt != null:
						_draw_actor(wt, feet, h, true, Color(1, 1, 1, 0.85))
					break
			var hp0: float = float(_mob_hp0[i]) if i < _mob_hp0.size() else float(m["hp"])
			# 透明ヘッドルームを除いた「見た目の頭」にバーを吸着
			var head_y := r.position.y + r.size.y * _top_frac(sprite_name)
			_enemy_top[i] = head_y
			_draw_head_ui(Vector2(feet.x, head_y - 8.0), 46.0 if boss else 32.0,
					float(m["hp"]) / maxf(hp0, 1.0), Color(1.0, 0.42, 0.4), 0, 0)

	_draw_combat_fx(sz, gy, font)
	_draw_bubble(sz, gy, font)

	if _shake > 0.004:
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
	var tsz := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, maxw, 13)
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
	var nw := font.get_string_size(gname, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 14.0
	var nr := Rect2(bx + 8.0, by - 10.0, nw, 18.0)
	var nsb := StyleBoxFlat.new()
	nsb.bg_color = Color(gcol.r * 0.25, gcol.g * 0.22, gcol.b * 0.28, 0.96 * a)
	nsb.set_corner_radius_all(6)
	nsb.border_color = Color(gcol.r, gcol.g, gcol.b, 0.9 * a)
	nsb.set_border_width_all(1)
	draw_style_box(nsb, nr)
	draw_string(font, Vector2(nr.position.x + 7, nr.position.y + 13), gname,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, a))
	# 本文（ダーク文字＝ネオン夜景の上でも読める）
	draw_multiline_string(font, Vector2(bx + 12.0, by + 22.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, maxw, 13, -1, Color(0.09, 0.10, 0.16, a))


## 実体アンカーの戦闘FX：斬撃・スキルバースト・ダメージ数字（対象の頭上に追従）。
func _draw_combat_fx(sz: Vector2, gy: float, font: Font) -> void:
	# 斬撃（対象の胴で白シアンのX＋小リング）
	var i := 0
	while i < _slashes.size():
		var k := (_t - float(_slashes[i]["t0"])) / 0.20
		if k >= 1.0:
			_slashes.remove_at(i)
			continue
		var slot := int(_slashes[i]["slot"])
		var base: Vector2 = _enemy_pos[slot] if (slot < _enemy_pos.size() and _enemy_pos[slot] != null) 				else Vector2(sz.x * ENEMY_X0, gy)
		var c := base + Vector2(0, -MOB_H * 0.55)
		if slot < _enemy_top.size() and _enemy_top[slot] != null:
			c = Vector2(base.x, (float(_enemy_top[slot]) + base.y) * 0.5)   # 頭と足元の中間＝胴
		var a := 1.0 - k
		var ln := 26.0 + 14.0 * k
		draw_line(c + Vector2(-ln, -ln * 0.6), c + Vector2(ln, ln * 0.6), Color(1, 1, 1, a), 3.0)
		draw_line(c + Vector2(-ln * 0.8, ln * 0.7), c + Vector2(ln * 0.8, -ln * 0.7), Color(CYAN.r, CYAN.g, CYAN.b, a * 0.9), 2.0)
		draw_arc(c, 14.0 + 26.0 * k, 0, TAU, 20, Color(1, 1, 1, a * 0.5), 2.0)
		i += 1
	# スキルバースト（爆発=橙リング＋破片／雷=ジグザグ落雷／回復・歌=味方から立ち上る粒）
	i = 0
	while i < _bursts.size():
		var k := (_t - float(_bursts[i]["t0"])) / 0.45
		if k >= 1.0:
			_bursts.remove_at(i)
			continue
		var kind := String(_bursts[i]["kind"])
		var a := 1.0 - k
		var ec := Vector2(sz.x * ENEMY_X0 + ENEMY_GAP, gy - MOB_H * 0.55)
		var pc := Vector2(PARTY_X0 + PARTY_GAP * 2.0, gy - GIRL_H * 0.5)
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
					pts.append(top.lerp(ec, tt) + Vector2(sin(j * 91.7 + _t * 40.0) * 10.0 * (1.0 - tt), 0))
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
	# ダメージ数字（対象の頭上に追従・上昇フェード）
	i = 0
	while i < _floaters.size():
		var fl: Dictionary = _floaters[i]
		var k := (_t - float(fl["t0"])) / 0.9
		if k >= 1.0:
			_floaters.remove_at(i)
			continue
		var slot := int(fl["slot"])
		var base := Vector2(sz.x * 0.5, gy)
		if String(fl["side"]) == "enemy":
			if slot < _enemy_top.size() and _enemy_top[slot] != null and slot < _enemy_pos.size() and _enemy_pos[slot] != null:
				base = Vector2((_enemy_pos[slot] as Vector2).x, float(_enemy_top[slot]) - 26.0)
			else:
				base += Vector2(0, -MOB_H - 26.0)
		else:
			if slot < _party_pos.size() and _party_pos[slot] != null:
				base = _party_pos[slot]
			base += Vector2(0, -GIRL_H - 30.0)
		var e := 1.0 - pow(1.0 - k, 2.0)
		var pos := base + Vector2(float(fl["jx"]), -e * 34.0)
		var col: Color = fl["col"]
		var a := 1.0 - k * k
		var fsize := 22 if k < 0.18 else 19   # 出た瞬間だけ大きく（ポップ感）
		var txt := String(fl["txt"])
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		draw_string(font, pos + Vector2(-tw * 0.5 + 1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0, 0, 0, a * 0.75))
		draw_string(font, pos + Vector2(-tw * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(col.r, col.g, col.b, a))
		i += 1


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
