class_name Hd2dView
extends Control
## HD-2D 探索画面プロトタイプ。
## 「3D 空間 ＋ 2D ドット絵ビルボード」というオクトラ/ポケモン ピクセルリメイク風の表現。
##
## 構成:
##   SubViewportContainer ─ SubViewport(3D)
##     ├ WorldEnvironment（空・環境光・ゆるい glow）
##     ├ DirectionalLight3D（影）
##     ├ 地面（PlaneMesh + タイルテクスチャ）と小物（ベンチ/植木）
##     ├ プレイヤー billboard（Sprite3D, ChibiAnim 駆動・WASD/矢印で歩行）
##     └ NPC billboard 群（中庭に立つ仲間たち）
##
## 既存の dive_view（Control の 2D _draw）とは独立。F6 で hd2d_test.tscn を直接実行して評価する。
## GL Compatibility でも動くよう、重い後処理（SSAO/DOF）は使わず glow のみ控えめに使う。

const SPRITE_DIR := "res://assets/generated/sprites/"
const PLAYER_ID := "kiriko"
const PIXEL_SIZE := 0.012          # Sprite3D の 1px = 何ワールド単位か（144x192 → 約1.7x2.3）
const MOVE_SPEED := 4.0            # ワールド単位/秒
const GROUND_HALF := 14.0          # 地面の半径（移動制限）

# 中庭に立たせる NPC：{id, 位置, 向き}
const NPCS := [
	{"id": "doctor", "pos": Vector3(-4.0, 0.0, -3.0), "flip": false},
	{"id": "nurse",  "pos": Vector3(4.0, 0.0, -3.0),  "flip": true},
	{"id": "mil",    "pos": Vector3(-6.0, 0.0, 2.0),  "flip": false},
	{"id": "muu",    "pos": Vector3(6.0, 0.0, 2.0),   "flip": true},
	{"id": "yuzuki", "pos": Vector3(0.0, 0.0, -6.5),  "flip": false},
]

var _sub: SubViewport
var _cam: Camera3D
var _player: Sprite3D
var _player_pos := Vector3(0, 0, 4.0)
var _player_anim: ChibiAnim
var _player_flip := false
var _npc_sprites: Array[Sprite3D] = []
var _npc_anims: Array[ChibiAnim] = []
var _tex_cache := {}
var _pulse := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_viewport()
	_build_world()
	_build_player()
	_build_npcs()
	set_process(true)
	set_process_input(true)


func _build_viewport() -> void:
	var vpc := SubViewportContainer.new()
	vpc.stretch = true
	vpc.set_anchors_preset(Control.PRESET_FULL_RECT)
	vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vpc)

	_sub = SubViewport.new()
	_sub.own_world_3d = true
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub.msaa_3d = Viewport.MSAA_2X
	_sub.positional_shadow_atlas_size = 2048
	vpc.add_child(_sub)


func _build_world() -> void:
	# ── 環境（空・環境光・ゆるい glow で HD-2D の柔らかい光）──
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.45, 0.62, 0.85)
	sky_mat.sky_horizon_color = Color(0.80, 0.85, 0.90)
	sky_mat.ground_horizon_color = Color(0.75, 0.78, 0.78)
	sky_mat.ground_bottom_color = Color(0.55, 0.55, 0.58)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.05
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var we := WorldEnvironment.new()
	we.environment = env
	_sub.add_child(we)

	# ── 太陽光（影あり・斜め上から）──
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -40.0, 0.0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	_sub.add_child(sun)

	# ── 地面（タイルテクスチャを敷いた平面）──
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(GROUND_HALF * 2.0 + 4.0, GROUND_HALF * 2.0 + 4.0)
	plane.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_texture = _make_tile_texture()
	gmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	gmat.uv1_scale = Vector3(16.0, 16.0, 1.0)
	gmat.roughness = 0.95
	plane.material_override = gmat
	_sub.add_child(plane)

	# ── 小物（植木・ベンチ風のボックス）で奥行きを出す ──
	_add_box(Vector3(-3.0, 0.4, 0.0), Vector3(1.2, 0.8, 4.0), Color(0.55, 0.42, 0.30))  # ベンチ
	_add_box(Vector3(3.0, 0.4, 0.0), Vector3(1.2, 0.8, 4.0), Color(0.55, 0.42, 0.30))
	_add_box(Vector3(0.0, 0.5, -9.0), Vector3(10.0, 1.0, 1.0), Color(0.62, 0.66, 0.70))  # 奥の塀
	for p in [Vector3(-8, 0, -8), Vector3(8, 0, -8), Vector3(-9, 0, 5), Vector3(9, 0, 5)]:
		_add_box(p + Vector3(0, 0.6, 0), Vector3(1.6, 1.2, 1.6), Color(0.30, 0.55, 0.32))  # 植木

	# ── カメラ（傾けた見下ろし・perspective）──
	_cam = Camera3D.new()
	_cam.fov = 42.0
	_cam.current = true
	_sub.add_child(_cam)
	_update_camera(true)


## チェッカー＋ノイズの簡易タイルテクスチャをコードで生成（外部アセット不要）。
func _make_tile_texture() -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var checker := ((x / 16) + (y / 16)) % 2 == 0
			var base := Color(0.52, 0.60, 0.42) if checker else Color(0.46, 0.54, 0.38)
			# 軽いざらつき
			var j := (float((x * 7 + y * 13) % 17) / 17.0 - 0.5) * 0.06
			img.set_pixel(x, y, Color(base.r + j, base.g + j, base.b + j))
	return ImageTexture.create_from_image(img)


func _add_box(pos: Vector3, sz: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	mi.material_override = m
	_sub.add_child(mi)


func _build_player() -> void:
	_player_anim = ChibiAnim.new(PLAYER_ID)
	_player = _make_billboard()
	_sub.add_child(_player)


func _build_npcs() -> void:
	for d in NPCS:
		var anim := ChibiAnim.new(String(d["id"]))
		var spr := _make_billboard()
		var base_pos: Vector3 = d["pos"]
		spr.position = base_pos + Vector3(0, _sprite_half_h(), 0)
		spr.flip_h = bool(d["flip"])
		_sub.add_child(spr)
		_npc_sprites.append(spr)
		_npc_anims.append(anim)


## 共通のビルボード Sprite3D を生成（Y 固定ビルボード＝直立したまま常にカメラを向く）。
func _make_billboard() -> Sprite3D:
	var spr := Sprite3D.new()
	spr.pixel_size = PIXEL_SIZE
	spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	spr.shaded = false
	spr.double_sided = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD  # 影を落とし、輪郭をくっきり
	spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return spr


func _sprite_half_h() -> float:
	# 144x192 の標準フレーム前提。足元を地面に合わせるための中心オフセット。
	return 192.0 * PIXEL_SIZE * 0.5


func _process(delta: float) -> void:
	_pulse += delta

	# ── 入力（WASD / 矢印）でプレイヤー移動。カメラ相対（奥行き=Z-, 横=X）──
	var iv := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): iv.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): iv.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): iv.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): iv.x += 1.0
	var moving := iv != Vector2.ZERO
	if moving:
		iv = iv.normalized()
		_player_pos.x = clampf(_player_pos.x + iv.x * MOVE_SPEED * delta, -GROUND_HALF, GROUND_HALF)
		_player_pos.z = clampf(_player_pos.z + iv.y * MOVE_SPEED * delta, -GROUND_HALF, GROUND_HALF)
		if absf(iv.x) > 0.01:
			_player_flip = iv.x < 0.0  # 左移動で左向き

	# ── プレイヤーのアニメ更新（歩行/待機）と描画 ──
	_player_anim.update_params(1.0 if moving else 0.0)
	_player_anim.tick(delta)
	_player.texture = _tex(_player_anim.current_path())
	_player.flip_h = _player_flip
	_player.position = _player_pos + Vector3(0, _sprite_half_h(), 0)

	# ── NPC は待機モーション ──
	for i in _npc_sprites.size():
		_npc_anims[i].update_params(0.0)
		_npc_anims[i].tick(delta)
		_npc_sprites[i].texture = _tex(_npc_anims[i].current_path())

	_update_camera(false)


## カメラをプレイヤーの斜め後ろ上方に追従させる（HD-2D の見下ろしアングル）。
func _update_camera(instant: bool) -> void:
	var target := _player_pos + Vector3(0, 6.5, 7.5)  # 上 6.5・後ろ 7.5
	if instant:
		_cam.position = target
	else:
		_cam.position = _cam.position.lerp(target, 0.12)
	_cam.look_at(_player_pos + Vector3(0, 1.0, 0), Vector3.UP)


func _tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
		if t == null:
			t = load(SPRITE_DIR + PLAYER_ID + "/idle_f0.png") if ResourceLoader.exists(SPRITE_DIR + PLAYER_ID + "/idle_f0.png") else null
		_tex_cache[path] = t
	return _tex_cache[path]
