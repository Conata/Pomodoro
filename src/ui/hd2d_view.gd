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
# 画面テーマ。"cyberpunk"＝黒猫飯店の世界観（ネオン中華）。"nature"＝Kenney 中庭（PoC）。
const THEME := "cyberpunk"

# 中庭に立たせる NPC：{id, 位置, 向き}
const NPCS := [
	{"id": "doctor", "pos": Vector3(-2.6, 0.0, -2.0), "flip": false},
	{"id": "nurse",  "pos": Vector3(2.6, 0.0, -2.0),  "flip": true},
	{"id": "mil",    "pos": Vector3(-3.4, 0.0, 3.0),  "flip": false},
	{"id": "muu",    "pos": Vector3(3.4, 0.0, 3.5),   "flip": true},
	{"id": "yuzuki", "pos": Vector3(1.2, 0.0, -5.5),  "flip": false},
]

const CAM_HEIGHT := 8.0            # カメラの高さ（高/距離 で見下ろし角が決まる ≈ 42°）
const CAM_DIST_MIN := 6.0
const CAM_DIST_MAX := 14.0

var _sub: SubViewport
var _cam: Camera3D
var _player: Sprite3D
var _player_pos := Vector3(0, 0, 4.0)
var _player_anim: ChibiAnim
var _player_flip := false
var _player_light: OmniLight3D = null  # 主人公追従のキーライト（cyberpunk のみ）
var _player_shadow: MeshInstance3D = null  # 主人公追従のブロブシャドウ
var _npc_sprites: Array[Sprite3D] = []
var _npc_anims: Array[ChibiAnim] = []
var _tex_cache := {}
var _pulse := 0.0
# オクトラ風：ワールドが主人公の周りを回る回転カメラ＋ズーム（SimpleHD2D 参考）
var _cam_yaw := 0.0                # 現在のヨー角（rad）
var _cam_yaw_target := 0.0         # Q/E で ±90° 刻みの目標
var _cam_dist := 9.0
var _cam_dist_target := 9.0
var _force_moving := false         # スクショ撮影用：入力なしでも歩行アニメを再生
var _cam_height := CAM_HEIGHT       # カメラ高さ（俯瞰アングル時に上げる）


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_viewport()
	_build_world()
	_build_player()
	_build_npcs()
	_build_vignette()
	set_process(true)
	set_process_input(true)


## Q/E でカメラを 90° 回転、R/F でズーム（押した瞬間だけ反応・リピート無視）。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q: _cam_yaw_target -= PI * 0.5
			KEY_E: _cam_yaw_target += PI * 0.5
			KEY_R: _cam_dist_target = clampf(_cam_dist_target - 2.0, CAM_DIST_MIN, CAM_DIST_MAX)
			KEY_F: _cam_dist_target = clampf(_cam_dist_target + 2.0, CAM_DIST_MIN, CAM_DIST_MAX)


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
	# ── 環境・太陽光（テーマで切替）──
	if THEME == "cyberpunk":
		_build_env_cyberpunk()
	else:
		_build_env_nature()

	# ── 地面 ──
	_build_ground_tiles()

	# ── 小物（テーマで切替）──
	if THEME == "cyberpunk":
		_build_props_cyberpunk()
		_build_particles()  # 漂うボクセル粒子で空気の粒子感
	else:
		_build_props()

	# ── カメラ（傾けた見下ろし・perspective）──
	_cam = Camera3D.new()
	_cam.fov = 42.0
	_cam.current = true
	# 被写界深度（tilt-shift風）。手前と奥をぼかしてミニチュア感＝HD-2Dの決め手。
	# ※ DOF は Forward+ / Mobile レンダラでのみ有効（GL Compatibility では無視される）。
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = 16.0
	attrs.dof_blur_far_transition = 6.0
	attrs.dof_blur_near_enabled = true
	attrs.dof_blur_near_distance = 4.0
	attrs.dof_blur_near_transition = 3.0
	attrs.dof_blur_amount = 0.12
	_cam.attributes = attrs
	_sub.add_child(_cam)
	_update_camera(true)


## 昼の自然光（Kenney 中庭 PoC 用）。空＋暖色環境光＋太陽。
func _build_env_nature() -> void:
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
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.60, 0.55)
	env.ambient_light_energy = 0.55
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_sub.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	_sub.add_child(sun)


## サイバーパンクの夜（黒猫飯店の世界観）。暗い空＋弱い青い月光＋ネオンの強い glow＋フォグ。
## ネオン本体は _build_props_cyberpunk() の発光マテリアル＋OmniLight3D が担う。
func _build_env_cyberpunk() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.025, 0.03, 0.06)  # 深い藍の夜
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.24, 0.27, 0.42)  # 弱く青い環境光
	env.ambient_light_energy = 0.5
	# ネオンを滲ませる強めの glow（HDR 閾値で発光面だけ光らせる）
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.18
	env.glow_hdr_threshold = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# 奥行きの霧（ネオンの色を空気に乗せる）
	env.fog_enabled = true
	env.fog_light_color = Color(0.10, 0.13, 0.26)
	env.fog_density = 0.025
	var we := WorldEnvironment.new()
	we.environment = env
	_sub.add_child(we)

	# 弱い青白い月光（キャラのシルエットと接地影のために最低限）
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-58.0, -28.0, 0.0)
	moon.light_energy = 0.45
	moon.light_color = Color(0.55, 0.65, 0.95)
	moon.shadow_enabled = true
	moon.shadow_blur = 1.5
	_sub.add_child(moon)


## 地面（PlaneMesh ＋ 自前のやわらかいタイル質感）。色を完全に制御できるので
## テーマ（自然/サイバーパンク等）に合わせて調整しやすい。
func _build_ground_tiles() -> void:
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(GROUND_HALF * 2.0 + 8.0, GROUND_HALF * 2.0 + 8.0)
	plane.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_texture = _make_ground_texture()
	gmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	gmat.uv1_scale = Vector3(18.0, 18.0, 1.0)
	if THEME == "cyberpunk":
		# 濡れたアスファルト：暗く・つるっとさせてネオンの映り込み（スペキュラ）を出す
		gmat.roughness = 0.28
		gmat.metallic = 0.25
	else:
		gmat.roughness = 0.92
	plane.material_override = gmat
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sub.add_child(plane)


## 地面テクスチャ。テーマで草緑／濡れアスファルトを切替。
func _make_ground_texture() -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var cyber := THEME == "cyberpunk"
	for y in n:
		for x in n:
			var checker := ((x / 16) + (y / 16)) % 2 == 0
			var base: Color
			if cyber:
				base = Color(0.06, 0.07, 0.10) if checker else Color(0.05, 0.055, 0.085)
			else:
				base = Color(0.40, 0.50, 0.30) if checker else Color(0.36, 0.46, 0.27)
			var j := (float((x * 7 + y * 13) % 17) / 17.0 - 0.5) * 0.04
			img.set_pixel(x, y, Color(base.r + j, base.g + j, base.b + j))
	return ImageTexture.create_from_image(img)


func _add_box(pos: Vector3, sz: Vector3, col: Color, rough: float = 0.9, yaw: float = 0.0) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees = Vector3(0, yaw, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	mi.material_override = m
	_sub.add_child(mi)


## 発光する箱（ネオン看板/提灯）。emission を glow_hdr_threshold 超えまで上げて滲ませる。
func _emissive_box(pos: Vector3, sz: Vector3, col: Color, energy: float = 3.0, yaw: float = 0.0) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees = Vector3(0, yaw, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sub.add_child(mi)


## 漂うボクセル粒子（小さな発光キューブ）。空気の粒子感＝HD-2Dのアトモスフィア。
## CPUParticles3D なのでどのレンダラでも動く（GL Compatibility 可）。
func _build_particles() -> void:
	var cube := BoxMesh.new()
	cube.size = Vector3(0.06, 0.06, 0.06)  # 小さなボクセル
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.7, 0.95, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.6, 0.9, 1.0)
	m.emission_energy_multiplier = 2.2  # glow に拾わせて発光させる
	m.vertex_color_use_as_albedo = true
	cube.material = m

	var p := CPUParticles3D.new()
	p.mesh = cube
	p.amount = 150
	p.lifetime = 7.0
	p.preprocess = 4.0  # 最初から空間に散らばった状態で開始
	p.randomness = 1.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(GROUND_HALF, 3.0, GROUND_HALF)
	p.direction = Vector3(0, 1, 0)
	p.spread = 25.0
	p.gravity = Vector3(0.2, 0.25, 0.0)  # ゆっくり上方へ漂う
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.5
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.6
	# 明滅（生成時に色のばらつき：シアン〜白〜淡橙）
	p.color = Color(0.8, 0.95, 1.0, 0.9)
	p.position = Vector3(0, 2.5, -1.0)
	_sub.add_child(p)


## ネオンの点光源（濡れた路面・キャラ周辺を色で染める）。
func _neon_light(pos: Vector3, col: Color, energy: float, rng: float) -> void:
	var o := OmniLight3D.new()
	o.position = pos
	o.light_color = col
	o.light_energy = energy
	o.omni_range = rng
	_sub.add_child(o)


## サイバーパンクの通り。プロップは Quaternius Cyberpunk Game Kit（CC0）の実モデルのみで構成。
## 自前の発光ボックス（提灯/看板）は使わず、キットの Sign/Light を発光させてネオンにする。
## 照明（ネオン点光源・キーライト）・粒子・影は描画要素として別途。
func _build_props_cyberpunk() -> void:
	const NEON_CYAN := Color(0.2, 0.9, 1.0)
	const NEON_MAGENTA := Color(1.0, 0.2, 0.7)
	const NEON_RED := Color(1.0, 0.25, 0.2)
	var P := CYBER_DIR + "platforms/"

	# ── 奥のビル群：プラットフォームブロックを積んで壁面に（top=y0で下に伸びる形状）──
	_add_gltf(P + "Platform_4x4.gltf", Vector3(-6.2, 3.6, -10.2), 1.9, 0)
	_add_gltf(P + "Platform_4x4.gltf", Vector3(6.2, 4.2, -10.6), 2.0, 0)
	_add_gltf(P + "Platform_4x2.gltf", Vector3(0.0, 4.8, -11.2), 1.9, 0)
	_add_gltf(P + "Platform_2x2.gltf", Vector3(-3.4, 2.2, -9.4), 1.5, 0)
	_add_gltf(P + "Platform_2x2.gltf", Vector3(3.6, 2.4, -9.6), 1.5, 0)
	# 中景の段差（プレイヤーの左右に低いブロック）
	_add_gltf(P + "Platform_4x1.gltf", Vector3(-5.6, 0.9, -4.0), 1.4, 0)
	_add_gltf(P + "Platform_4x1.gltf", Vector3(5.6, 0.9, -3.0), 1.4, 0)

	# ── ビル上のディテール（AC/アンテナ/TV/コンピュータ/パイプ/ケーブル）──
	_add_gltf(P + "AC.gltf", Vector3(-6.6, 1.5, -8.6), 1.3, 20)
	_add_gltf(P + "AC_Stacked.gltf", Vector3(6.6, 1.7, -8.8), 1.3, -15)
	_add_gltf(P + "AC_Side.gltf", Vector3(-3.2, 1.4, -8.8), 1.2, 0)
	_add_gltf(P + "Antenna_1.gltf", Vector3(-5.2, 5.6, -10.0), 1.7, 0)
	_add_gltf(P + "Antenna_2.gltf", Vector3(4.8, 6.6, -10.4), 1.7, 0)
	_add_gltf(P + "Pipe_1.gltf", Vector3(0.2, 0.6, -8.4), 1.6, 0)
	_add_gltf(P + "Pipe_2.gltf", Vector3(-1.8, 0.5, -8.6), 1.4, 90)
	_add_gltf(P + "Cable_Long.gltf", Vector3(0.0, 5.2, -9.6), 1.8, 0)
	_add_gltf(P + "Cable_Thick.gltf", Vector3(2.4, 4.6, -9.4), 1.6, 20)
	_add_gltf(P + "Computer_Large.gltf", Vector3(3.6, 1.0, -7.8), 1.4, -20)
	_add_gltf(P + "Computer.gltf", Vector3(-3.8, 1.0, -7.6), 1.3, 15)
	_add_gltf(P + "TV_1.gltf", Vector3(-4.4, 1.2, -7.4), 1.4, 18, 2.5)   # 発光
	_add_gltf(P + "TV_3.gltf", Vector3(4.4, 1.2, -7.2), 1.4, -18, 2.5)   # 発光

	# ── 街灯（通りの左右・発光）──
	_add_gltf(P + "Light_Street_1.gltf", Vector3(-4.8, 0.0, -2.0), 1.7, 30, 2.2)
	_add_gltf(P + "Light_Street_2.gltf", Vector3(4.8, 0.0, 0.5), 1.7, -30, 2.2)
	_add_gltf(P + "Light_Square.gltf", Vector3(-2.2, 3.0, -8.0), 1.6, 0, 3.0)
	_add_gltf(P + "Light_Square.gltf", Vector3(2.2, 3.0, -8.0), 1.6, 0, 3.0)

	# ── ネオン看板（キットの Sign を発光させる。タテヨコ混在で密度）──
	_add_gltf(P + "Sign_1.gltf", Vector3(-3.8, 3.4, -7.6), 2.8, 0, 3.2)
	_add_gltf(P + "Sign_3.gltf", Vector3(3.6, 3.8, -7.8), 2.8, 0, 3.2)
	_add_gltf(P + "Sign_2.gltf", Vector3(0.8, 4.4, -8.4), 2.6, 0, 3.2)
	_add_gltf(P + "Sign_4.gltf", Vector3(-1.4, 2.6, -7.4), 2.4, 0, 3.2)
	_add_gltf(P + "Sign_Corner_1.gltf", Vector3(5.6, 2.8, -6.6), 2.3, -25, 3.2)
	_add_gltf(P + "Sign_Corner_2.gltf", Vector3(-5.6, 2.8, -6.0), 2.3, 25, 3.2)
	_add_gltf(P + "Sign_Small_2.gltf", Vector3(-2.8, 1.8, -6.2), 2.2, 10, 3.2)
	_add_gltf(P + "Sign_Small_3.gltf", Vector3(2.8, 1.8, -6.0), 2.2, -10, 3.2)

	# ── レール/フェンス/ドア（通りの境界と店先）──
	_add_gltf(P + "Door.gltf", Vector3(-5.4, 0.0, -3.6), 2.2, 18)
	_add_gltf(P + "Door.gltf", Vector3(5.4, 0.0, -3.0), 2.2, -18)
	_add_gltf(P + "Rail_Long.gltf", Vector3(-3.4, 0.0, 5.0), 1.6, 0)
	_add_gltf(P + "Rail_Long.gltf", Vector3(3.4, 0.0, 5.0), 1.6, 0)
	_add_gltf(P + "Fence.gltf", Vector3(-1.6, 0.0, 6.0), 1.8, 0)
	_add_gltf(P + "Fence.gltf", Vector3(1.6, 0.0, 6.0), 1.8, 0)

	# ── 通りを染めるネオンの点光源（看板/街灯の位置に合わせる）──
	_neon_light(Vector3(-3.8, 2.6, -6.8), NEON_MAGENTA, 4.0, 9.0)
	_neon_light(Vector3(3.8, 2.8, -7.0), NEON_CYAN, 4.0, 9.0)
	_neon_light(Vector3(0.0, 3.2, -8.0), NEON_CYAN, 3.0, 9.0)
	_neon_light(Vector3(-4.8, 2.4, -2.0), NEON_RED, 2.8, 8.0)
	_neon_light(Vector3(4.8, 2.4, 0.5), NEON_MAGENTA, 2.8, 8.0)
	_neon_light(Vector3(1.5, 1.6, 3.0), NEON_CYAN, 2.2, 7.0)


const KENNEY_DIR := "res://assets/third_party/kenney_naturekit/models/"

## Kenney Nature Kit の glTF モデルを 1 体配置。base が y=0 のモデル前提。
## 木は約 1.7 ユニット高なので scale 2.5 でキャラ（約2.3）を見下ろす高さになる。
func _add_model(model_name: String, pos: Vector3, scale: float = 1.0, yaw_deg: float = 0.0) -> void:
	var ps := load(KENNEY_DIR + model_name + ".glb")
	if ps == null:
		return
	var inst := (ps as PackedScene).instantiate() as Node3D
	if inst == null:
		return
	inst.position = pos
	inst.scale = Vector3(scale, scale, scale)
	inst.rotation_degrees = Vector3(0, yaw_deg, 0)
	_sub.add_child(inst)
	_enable_shadows(inst)


## 取り込んだモデルの全 MeshInstance3D に影を落とさせる（接地感）。
func _enable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for c in node.get_children():
		_enable_shadows(c)


const CYBER_DIR := "res://assets/third_party/cyberpunk_kit/"

## 任意の glTF/glb モデルを配置（パス直指定）。glow_energy>0 でテクスチャを自発光させ
## ネオン看板を光らせる（emission に albedo テクスチャを流用）。
func _add_gltf(res_path: String, pos: Vector3, scale: float = 1.0, yaw_deg: float = 0.0, glow_energy: float = 0.0) -> void:
	var ps := load(res_path)
	if ps == null:
		return
	var inst := (ps as PackedScene).instantiate() as Node3D
	if inst == null:
		return
	inst.position = pos
	inst.scale = Vector3(scale, scale, scale)
	inst.rotation_degrees = Vector3(0, yaw_deg, 0)
	_sub.add_child(inst)
	_enable_shadows(inst)
	if glow_energy > 0.0:
		_make_glow(inst, glow_energy)


## モデルの各サーフェスを複製マテリアルにして自発光を付与（ネオン化）。
func _make_glow(node: Node, energy: float) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var msh := mi.mesh
		if msh != null:
			for s in msh.get_surface_count():
				var base: Material = mi.get_active_material(s)
				var m: StandardMaterial3D = (base.duplicate() if base is StandardMaterial3D else StandardMaterial3D.new())
				m.emission_enabled = true
				m.emission_energy_multiplier = energy
				if m.albedo_texture != null:
					m.emission_texture = m.albedo_texture  # 模様のまま光らせる
					m.emission = Color(1, 1, 1)
				else:
					m.emission = m.albedo_color
				mi.set_surface_override_material(s, m)
	for c in node.get_children():
		_make_glow(c, energy)


## 中庭のレイアウト。Kenney Nature Kit（CC0）で木・柵・岩・茂み・花・石畳を配置。
func _build_props() -> void:
	# 木立：縦画面は横が狭いので中央寄り(x≈±4)＆大きめ(約3.5倍=キャラの倍以上)に。
	# 奥(z<0)に大きく、手前(z>0)はやや小さく＝奥行き感。
	_add_model("tree_default", Vector3(-4.5, 0, -8), 3.8, 20)
	_add_model("tree_oak", Vector3(4.5, 0, -8.5), 3.6, -30)
	_add_model("tree_pineTallA", Vector3(-1.5, 0, -10), 4.2, 0)
	_add_model("tree_default_fall", Vector3(2.0, 0, -10.5), 3.4, 40)  # 秋色アクセント
	_add_model("tree_thin", Vector3(-6.0, 0, -4), 3.2, 15)
	_add_model("tree_oak", Vector3(6.0, 0, -3), 3.0, 120)
	_add_model("tree_default_fall", Vector3(-5.0, 0, 7), 2.6, 200)    # 手前は小さめ
	_add_model("tree_default", Vector3(5.0, 0, 7.5), 2.6, 90)

	# 背景の柵（奥の境界。1ユニット幅を 1.5 倍で並べる）
	for i in range(-3, 4):
		_add_model("fence_simple", Vector3(i * 1.5, 0, -9.0), 1.5, 0)

	# 中央の石畳パス（プレイヤーの通り道）
	for z in range(-4, 7):
		_add_model("ground_pathTile", Vector3(0, 0.02, z * 1.0), 1.0, 0)

	# 岩・石（中景のアクセント。パスを避けて左右に）
	_add_model("rock_largeA", Vector3(-3.5, 0, 3), 1.8, 40)
	_add_model("rock_largeC", Vector3(3.8, 0, 2.5), 1.6, 200)
	_add_model("stone_smallB", Vector3(-2.6, 0, 5.5), 1.4, 0)

	# 茂み・草・花（足元の密度。パスの左右に寄せる）
	for d in [
		{"m": "plant_bushLarge", "p": Vector3(-3.0, 0, -2), "s": 1.8},
		{"m": "plant_bushDetailed", "p": Vector3(3.2, 0, -3), "s": 1.8},
		{"m": "grass_large", "p": Vector3(-1.6, 0, 1), "s": 1.8},
		{"m": "grass_large", "p": Vector3(1.8, 0, 4.5), "s": 1.8},
		{"m": "flower_redA", "p": Vector3(-2.2, 0, 2.2), "s": 2.0},
		{"m": "flower_yellowB", "p": Vector3(1.8, 0, -1), "s": 2.0},
		{"m": "flower_purpleC", "p": Vector3(2.6, 0, 1.5), "s": 2.0},
		{"m": "mushroom_redGroup", "p": Vector3(-3.4, 0, -4), "s": 1.8},
	]:
		_add_model(String(d["m"]), d["p"], float(d["s"]), 0)


func _build_player() -> void:
	_player_anim = ChibiAnim.new(PLAYER_ID)
	_player = _make_billboard()
	_sub.add_child(_player)
	_player_shadow = _add_blob_shadow(_player_pos)
	# 主人公に追従する控えめなキーライト（暗い夜でも主役を読めるように）。
	if THEME == "cyberpunk":
		_player_light = OmniLight3D.new()
		_player_light.light_color = Color(1.0, 0.92, 0.85)
		_player_light.light_energy = 1.4
		_player_light.omni_range = 5.0
		_player_light.shadow_enabled = false
		_sub.add_child(_player_light)


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
		# 足元のブロブシャドウ（ビルボードの落ち影は不安定なので明示的に接地影を置く）
		_add_blob_shadow(base_pos)


## 足元の楕円ソフトシャドウ。ビルボードは光源視点で薄くなり落ち影が不安定なため、
## HD-2D の定番どおり板の影テクスチャを地面に寝かせて確実に接地させる。
var _blob_tex: Texture2D = null

func _add_blob_shadow(pos: Vector3, w: float = 1.5) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := PlaneMesh.new()  # XZ 平面（法線+Y）＝地面に寝た板
	q.size = Vector2(w, w)
	mi.mesh = q
	mi.position = pos + Vector3(0, 0.03, 0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _get_blob_tex()
	m.albedo_color = Color(0, 0, 0, 0.55)
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED  # z-fight 回避
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sub.add_child(mi)
	return mi


## 中心が濃く外周が透明になる放射状の影テクスチャ。
func _get_blob_tex() -> Texture2D:
	if _blob_tex != null:
		return _blob_tex
	var n := 48
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x - c, y - c).length() / c
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a  # 中心を濃く、外周をなだらかに
			img.set_pixel(x, y, Color(0, 0, 0, a))
	_blob_tex = ImageTexture.create_from_image(img)
	return _blob_tex


## 共通のビルボード Sprite3D を生成（Y 固定ビルボード＝直立したまま常にカメラを向く）。
func _make_billboard() -> Sprite3D:
	var spr := Sprite3D.new()
	spr.pixel_size = PIXEL_SIZE
	spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	# shaded=true でシーンライト（ネオン/月光）を受け、環境に馴染ませる。
	# Y固定ビルボードは法線がカメラ向きに回るので、周囲の OmniLight がキャラを染める。
	spr.shaded = true
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
		# カメラ相対移動（カメラを回しても W=画面奥 のまま操作できる）
		var basis := Basis(Vector3.UP, _cam_yaw)
		var fwd := basis * Vector3(0, 0, -1)
		var right := basis * Vector3(1, 0, 0)
		var world_move := (fwd * -iv.y + right * iv.x).normalized()
		_player_pos.x = clampf(_player_pos.x + world_move.x * MOVE_SPEED * delta, -GROUND_HALF, GROUND_HALF)
		_player_pos.z = clampf(_player_pos.z + world_move.z * MOVE_SPEED * delta, -GROUND_HALF, GROUND_HALF)
		# 画面上の左右で向きを反転（カメラの右ベクトルとの内積で判定）
		var screen_x := world_move.dot(right)
		if absf(screen_x) > 0.01:
			_player_flip = screen_x < 0.0

	# ── プレイヤーのアニメ更新（歩行/待機）と描画 ──
	_player_anim.update_params(1.0 if (moving or _force_moving) else 0.0)
	_player_anim.tick(delta)
	_player.texture = _tex(_player_anim.current_path())
	_player.flip_h = _player_flip
	_player.position = _player_pos + Vector3(0, _sprite_half_h(), 0)
	if _player_light != null:
		_player_light.position = _player_pos + Vector3(0, 2.2, 0.8)
	if _player_shadow != null:
		_player_shadow.position = _player_pos + Vector3(0, 0.03, 0)

	# ── NPC は待機モーション ──
	for i in _npc_sprites.size():
		_npc_anims[i].update_params(0.0)
		_npc_anims[i].tick(delta)
		_npc_sprites[i].texture = _tex(_npc_anims[i].current_path())

	_update_camera(false)


## カメラをプレイヤーの斜め後ろ上方に追従させる（HD-2D の見下ろしアングル）。
## ヨー（Q/E）とズーム（R/F）を補間し、プレイヤーの周りを周回する。
func _update_camera(instant: bool) -> void:
	if instant:
		_cam_yaw = _cam_yaw_target
		_cam_dist = _cam_dist_target
	else:
		_cam_yaw = lerp_angle(_cam_yaw, _cam_yaw_target, 0.12)
		_cam_dist = lerpf(_cam_dist, _cam_dist_target, 0.12)
	var offset := Basis(Vector3.UP, _cam_yaw) * Vector3(0, _cam_height, _cam_dist)
	var target := _player_pos + offset
	if instant:
		_cam.position = target
	else:
		_cam.position = _cam.position.lerp(target, 0.18)
	_cam.look_at(_player_pos + Vector3(0, 1.0, 0), Vector3.UP)


## 画面端を暗く落とすヴィネットを 3D 描画の上に重ねる。
func _build_vignette() -> void:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/ui/hd2d_vignette.gdshader")
	mat.set_shader_parameter("strength", 0.55)
	mat.set_shader_parameter("radius", 0.9)
	rect.material = mat
	add_child(rect)


func _tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
		if t == null:
			t = load(SPRITE_DIR + PLAYER_ID + "/idle_f0.png") if ResourceLoader.exists(SPRITE_DIR + PLAYER_ID + "/idle_f0.png") else null
		_tex_cache[path] = t
	return _tex_cache[path]
