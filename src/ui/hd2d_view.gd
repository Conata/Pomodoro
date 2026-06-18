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
# 画面テーマ（シーンから @export で切替）。
#   "cyberpunk"＝ネオン路地の探索/戦闘  "home"＝黒猫飯店のジオラマ  "nature"＝Kenney 中庭(PoC)
@export var stage_theme: String = "cyberpunk"

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
var _enemy_nodes: Array = []           # 潜航の敵プール（set_dive_state で出し入れ）
var _npc_sprites: Array[Sprite3D] = []
var _npc_anims: Array[ChibiAnim] = []
var _npc_base: Array = []      # home の徘徊：基準位置
var _npc_pos: Array = []        # home の徘徊：現在位置
var _npc_target: Array = []     # home の徘徊：目標位置
var _npc_flip: Array = []
var _npc_shadow: Array = []     # home の徘徊：影（追従）
var _intro_t := 0.0            # カメラ導入（ズームイン）の経過
var _tex_cache := {}
var _pulse := 0.0
# オクトラ風：ワールドが主人公の周りを回る回転カメラ＋ズーム（SimpleHD2D 参考）
var _cam_yaw := 0.0                # 現在のヨー角（rad）
var _cam_yaw_target := 0.0         # Q/E で ±90° 刻みの目標
var _cam_dist := 9.0
var _cam_dist_target := 9.0
var _force_moving := false         # スクショ撮影用：入力なしでも歩行アニメを再生
var _cam_height := CAM_HEIGHT       # カメラ高さ（俯瞰アングル時に上げる）
var _cam_target_override = null      # Vector3 指定で注視点を固定（home の据置構図用）


func _ready() -> void:
	# 配置は親/シーン側の anchors に従う（フルレクト指定が無ければ自分でフル）。
	if get_anchor(SIDE_RIGHT) == 0.0 and get_anchor(SIDE_BOTTOM) == 0.0:
		set_anchors_preset(Control.PRESET_FULL_RECT)
	# テーマ別カメラ：home は店先を見るので低い角度（見下ろしを弱める）
	if stage_theme == "home":
		_player_pos = Vector3(0, 0, 2.6)   # 主人公はパーティテーブル（VN窓に被らない位置へ）
		_cam_target_override = Vector3(0, 0.8, 0.2)  # カウンター/バーを主役に
		_cam_height = 6.0
		_cam_dist = 12.0
		_cam_dist_target = 12.0
	elif stage_theme == "dive":
		# 戦闘：パーティ手前(z+)・敵奥(z-)。下部UIに隠れないようパーティを少し奥へ。
		_player_pos = Vector3(0, 0, 2.4)   # 主人公はパーティ中央
		_cam_target_override = Vector3(0, 1.0, 1.2)
		_cam_height = 6.5
		_cam_dist = 11.5
		_cam_dist_target = 11.5
	elif stage_theme == "strip":
		# 横帯：パーティ左(-X)・敵右(+X)。中央に間合いを取り対峙感を出す
		_player_pos = Vector3(-4.6, 0, 0.4)  # 主人公はパーティ左端
		_cam_target_override = Vector3(0.2, 0.9, 0.2)
		_cam_height = 2.8
		_cam_dist = 5.6
		_cam_dist_target = 5.6
	_build_viewport()
	_build_world()
	_build_player()
	_build_npcs()
	_build_vignette()
	# home：導入はズームアウトから開始（_process がターゲット距離へ寄っていく＝ズームイン）
	if stage_theme == "home":
		_cam_dist = _cam_dist_target * 2.4
		var look: Vector3 = _cam_target_override if _cam_target_override != null else _player_pos
		_cam.position = look + Basis(Vector3.UP, _cam_yaw) * Vector3(0, _cam_height * 1.5, _cam_dist)
		_cam.look_at(look + Vector3(0, 1.0, 0), Vector3.UP)
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
	match stage_theme:
		"cyberpunk", "dive", "strip": _build_env_cyberpunk()
		"home": _build_env_home()
		_: _build_env_nature()

	# ── 地面 ──
	_build_ground_tiles()

	# ── 小物（テーマで切替）──
	match stage_theme:
		"cyberpunk":
			_build_props_cyberpunk()
			_build_particles()
		"home":
			_build_props_home()
			_build_particles()
		"dive":
			_build_props_cyberpunk()
			_build_particles()
			_build_enemies()
		"strip":
			_build_props_strip()
		_:
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


## 地面。cyberpunk はキットの Platform 天面をタイル状に敷いて「キット由来の床」にする
## （隙間/光漏れ防止に暗いベース板を一枚下に敷く）。nature/フォールバックは PlaneMesh。
func _build_ground_tiles() -> void:
	# ベース板（必ず一枚。cyberpunk は暗い濡れアスファルト、nature は草）
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(GROUND_HALF * 2.0 + 8.0, GROUND_HALF * 2.0 + 8.0)
	plane.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_texture = _make_ground_texture()
	gmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	gmat.uv1_scale = Vector3(18.0, 18.0, 1.0)
	if _is_dark():
		gmat.roughness = 0.28
		gmat.metallic = 0.25
	else:
		gmat.roughness = 0.92
	plane.material_override = gmat
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sub.add_child(plane)

	# cyberpunk/home/dive：キットの Platform_4x4 天面を床タイルとして敷く（キット由来の床）。
	# 多数個別インスタンスは重いので MultiMesh で 1 ドローコール化（最適化）。
	# メッシュとマテリアルを取り出し、濡れた金属に調整した material_override を当てる
	# （でないと既定材質が落ちて水色化する）。
	if _is_dark():
		var src := _meshinst_from_glb(CYBER_DIR + "platforms/Platform_4x4.gltf")
		if src != null and src.mesh != null:
			var mat: Material = src.get_active_material(0)
			var wet: StandardMaterial3D = (mat.duplicate() if mat is StandardMaterial3D else StandardMaterial3D.new())
			wet.metallic = 0.45
			wet.roughness = 0.18
			var step := 4.0
			var xs := range(-2, 3)
			var zs := range(-3, 3)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = src.mesh
			mm.instance_count = xs.size() * zs.size()
			var idx := 0
			for ix in xs:
				for iz in zs:
					mm.set_instance_transform(idx, Transform3D(Basis(), Vector3(ix * step, 0.0, iz * step - 2.0)))
					idx += 1
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = wet
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_sub.add_child(mmi)
			src.queue_free()
		# ベース板も濡れ感を強める
		gmat.roughness = 0.16
		gmat.metallic = 0.5


## glb から最初の MeshInstance3D を取り出す（MultiMesh のメッシュ／マテリアル取得用）。
## 取り出したノードはツリーに属さないので、使用後に queue_free すること。
func _meshinst_from_glb(path: String) -> MeshInstance3D:
	var ps := load(path)
	if ps == null:
		return null
	var root := (ps as PackedScene).instantiate()
	var found := _find_meshinst(root)
	if found != null and found.get_parent() != null:
		found.get_parent().remove_child(found)
	root.queue_free()
	return found


func _find_meshinst(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return node as MeshInstance3D
	for c in node.get_children():
		var m := _find_meshinst(c)
		if m != null:
			return m
	return null


## 暗い夜の路面系テーマ（cyberpunk/home/dive/strip）か。
func _is_dark() -> bool:
	return stage_theme in ["cyberpunk", "home", "dive", "strip"]


## 地面テクスチャ。テーマで草緑／濡れアスファルトを切替。
func _make_ground_texture() -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var cyber := _is_dark()
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

	# ── ネオン看板（キットの Sign を発光させる。balance: 白飛びを避け 2.4〜2.6）──
	_add_gltf(P + "Sign_1.gltf", Vector3(-3.8, 3.4, -7.6), 2.8, 0, 2.6)
	_add_gltf(P + "Sign_3.gltf", Vector3(3.6, 3.8, -7.8), 2.8, 0, 2.6)
	_add_gltf(P + "Sign_2.gltf", Vector3(0.8, 4.4, -8.4), 2.6, 0, 2.6)
	_add_gltf(P + "Sign_4.gltf", Vector3(-1.4, 2.6, -7.4), 2.4, 0, 2.4)
	_add_gltf(P + "Sign_Corner_1.gltf", Vector3(5.6, 2.8, -6.6), 2.3, -25, 2.6)
	_add_gltf(P + "Sign_Corner_2.gltf", Vector3(-5.6, 2.8, -6.0), 2.3, 25, 2.6)
	_add_gltf(P + "Sign_Small_2.gltf", Vector3(-2.8, 1.8, -6.2), 2.2, 10, 2.4)
	_add_gltf(P + "Sign_Small_3.gltf", Vector3(2.8, 1.8, -6.0), 2.2, -10, 2.4)
	# 中景にも看板を足して密度を上げる（プレイヤー左右）
	_add_gltf(P + "Sign_Small_1.gltf", Vector3(-5.4, 1.6, -3.2), 2.0, 30, 2.4)
	_add_gltf(P + "Sign_Corner_3.gltf", Vector3(5.4, 1.8, -1.5), 2.0, -30, 2.6)
	_add_gltf(P + "Sign_4.gltf", Vector3(-4.8, 1.4, 1.0), 1.8, 40, 2.4)

	# ── 中景〜手前の密度（パイプ/ケーブル/AC/コンピュータ/アンテナ）──
	_add_gltf(P + "Pipe_2.gltf", Vector3(-4.2, 0.4, -1.0), 1.4, 0)
	_add_gltf(P + "Pipe_1.gltf", Vector3(4.0, 0.4, -2.0), 1.4, 90)
	_add_gltf(P + "Cable_Small.gltf", Vector3(2.0, 4.0, -8.6), 1.4, 0)
	_add_gltf(P + "AC.gltf", Vector3(5.2, 0.6, -4.0), 1.1, -20)
	_add_gltf(P + "Computer.gltf", Vector3(-5.0, 0.5, -0.5), 1.1, 25)
	_add_gltf(P + "Antenna_2.gltf", Vector3(-2.0, 2.6, -9.4), 1.3, 0)

	# ── レール/フェンス/ドア（通りの境界と手前）──
	_add_gltf(P + "Door.gltf", Vector3(-5.6, 0.0, -3.6), 2.2, 18)
	_add_gltf(P + "Door.gltf", Vector3(5.6, 0.0, -3.0), 2.2, -18)
	_add_gltf(P + "Rail_Long.gltf", Vector3(-3.4, 0.0, 5.0), 1.6, 0)
	_add_gltf(P + "Rail_Long.gltf", Vector3(3.4, 0.0, 5.0), 1.6, 0)
	_add_gltf(P + "Rail_Short.gltf", Vector3(-5.0, 0.0, 3.0), 1.5, 90)
	_add_gltf(P + "Rail_Short.gltf", Vector3(5.0, 0.0, 3.0), 1.5, 90)
	_add_gltf(P + "Fence.gltf", Vector3(-1.6, 0.0, 6.2), 1.8, 0)
	_add_gltf(P + "Fence.gltf", Vector3(0.0, 0.0, 6.2), 1.8, 0)
	_add_gltf(P + "Fence.gltf", Vector3(1.6, 0.0, 6.2), 1.8, 0)

	# ── 通りを染めるネオンの点光源（看板/街灯の位置に合わせ密に）──
	_neon_light(Vector3(-3.8, 2.6, -6.8), NEON_MAGENTA, 4.0, 9.0)
	_neon_light(Vector3(3.8, 2.8, -7.0), NEON_CYAN, 4.0, 9.0)
	_neon_light(Vector3(0.0, 3.2, -8.0), NEON_CYAN, 3.0, 9.0)
	_neon_light(Vector3(-4.8, 2.0, -2.0), NEON_RED, 3.0, 8.0)
	_neon_light(Vector3(4.8, 2.0, -0.5), NEON_MAGENTA, 3.0, 8.0)
	_neon_light(Vector3(-4.6, 1.6, 1.0), NEON_CYAN, 2.4, 7.0)
	_neon_light(Vector3(1.5, 1.6, 3.0), NEON_CYAN, 2.2, 7.0)


## ホーム（黒猫飯店）の環境。設計の肝＝「店内の暖色 × 窓の外の冷たいネオン都市」の寒暖対比。
## 暖色の店内環境光＋弱い夜空。ネオンは _build_props_home の発光＋OmniLight が担う。
func _build_env_home() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.06)  # 夜
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.34, 0.28, 0.24)  # 暖色寄りの環境光（店内）
	env.ambient_light_energy = 0.5
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.10, 0.12, 0.22)
	env.fog_density = 0.02
	var we := WorldEnvironment.new()
	we.environment = env
	_sub.add_child(we)

	# 店内を照らす暖色の弱いキーライト（影あり）
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50.0, -20.0, 0.0)
	key.light_energy = 0.7
	key.light_color = Color(1.0, 0.82, 0.6)
	key.shadow_enabled = true
	key.shadow_blur = 1.5
	_sub.add_child(key)


## ホーム（黒猫飯店）のジオラマ。カウンター＋暖色の店内＋赤提灯＋ネオン「黒猫飯店」、
## 窓の外はサイバーパンクキットの冷たいネオン都市。寒暖対比で店を主役にする。
func _build_props_home() -> void:
	const NEON_RED := Color(1.0, 0.2, 0.16)
	const NEON_CYAN := Color(0.2, 0.9, 1.0)
	const NEON_MAGENTA := Color(1.0, 0.2, 0.7)
	const WARM := Color(1.0, 0.66, 0.34)
	var P := CYBER_DIR + "platforms/"

	# ── 窓の外：冷たいネオン都市（奥）──
	_add_gltf(P + "Platform_4x4.gltf", Vector3(-6.4, 4.0, -11.0), 2.0, 0)
	_add_gltf(P + "Platform_4x4.gltf", Vector3(6.4, 4.4, -11.4), 2.1, 0)
	_add_gltf(P + "Platform_4x2.gltf", Vector3(0.0, 5.0, -12.0), 2.0, 0)
	_add_gltf(P + "Sign_1.gltf", Vector3(-4.4, 3.6, -9.6), 2.6, 0, 2.6)
	_add_gltf(P + "Sign_3.gltf", Vector3(4.4, 3.8, -9.8), 2.6, 0, 2.6)
	_add_gltf(P + "Sign_Corner_1.gltf", Vector3(6.0, 2.8, -8.6), 2.2, -25, 2.6)
	_add_gltf(P + "Antenna_1.gltf", Vector3(-5.4, 5.6, -10.6), 1.6, 0)
	_add_gltf(P + "AC_Stacked.gltf", Vector3(5.6, 1.8, -8.8), 1.3, -15)
	_neon_light(Vector3(-4.2, 2.8, -8.6), NEON_MAGENTA, 3.0, 9.0)
	_neon_light(Vector3(4.2, 2.8, -8.8), NEON_CYAN, 3.0, 9.0)

	# ── 店先「黒猫飯店」：カウンター＋暖色の店内＋赤い看板 ──
	# カウンター（横長の台）
	_add_box(Vector3(0.0, 0.55, -1.2), Vector3(7.0, 1.1, 1.0), Color(0.16, 0.10, 0.08), 0.5)
	_add_box(Vector3(0.0, 1.15, -1.2), Vector3(7.2, 0.12, 1.2), Color(0.28, 0.18, 0.12), 0.4)  # 天板
	# 背後の店内壁（暖色で発光させて「店内の灯り」）
	_add_box(Vector3(0.0, 1.8, -3.6), Vector3(8.0, 3.6, 0.4), Color(0.18, 0.10, 0.06), 0.6)
	_emissive_box(Vector3(0.0, 1.7, -3.35), Vector3(6.4, 2.0, 0.1), WARM, 1.2)  # 暖色の店内窓
	# ピンクのネオン看板「黒猫飯店」（カウンター上・店の主役サイン）
	const PINK := Color(1.0, 0.32, 0.72)
	_emissive_box(Vector3(0.0, 3.5, -2.6), Vector3(4.8, 0.9, 0.2), PINK, 3.4)
	_emissive_box(Vector3(-2.9, 3.0, -2.4), Vector3(0.42, 1.7, 0.18), PINK, 2.8)  # タテ看板
	_emissive_box(Vector3(2.9, 3.0, -2.4), Vector3(0.42, 1.7, 0.18), NEON_CYAN, 2.6)  # 対のシアン
	# 赤提灯を店先に吊るす（中華）
	for x in [-3.4, -2.0, -0.7, 0.7, 2.0, 3.4]:
		_emissive_box(Vector3(x, 2.7, -0.4), Vector3(0.42, 0.6, 0.42), NEON_RED, 2.6)
	# 「千客万来」の赤い札（黒猫飯店サインの下）
	_emissive_box(Vector3(0.0, 2.45, -2.5), Vector3(1.7, 0.46, 0.15), NEON_RED, 2.4)

	# ── カウンター裏の酒瓶棚（バーらしさ。色とりどりの小瓶＋棚板）──
	var bottle_cols := [
		Color(0.95, 0.6, 0.3), Color(0.4, 0.85, 0.6), Color(0.85, 0.4, 0.55),
		Color(0.5, 0.65, 0.95), Color(0.95, 0.82, 0.4),
	]
	_add_box(Vector3(0.0, 1.30, -3.2), Vector3(7.6, 0.06, 0.3), Color(0.22, 0.14, 0.09), 0.5)  # 棚板
	_add_box(Vector3(0.0, 1.86, -3.2), Vector3(7.6, 0.06, 0.3), Color(0.22, 0.14, 0.09), 0.5)
	for row in 2:
		var sy := 1.5 + row * 0.56
		for i in 9:
			_emissive_box(Vector3(-3.6 + i * 0.9, sy, -3.12), Vector3(0.15, 0.4, 0.12),
					bottle_cols[i % bottle_cols.size()], 1.4)

	# ── パーティテーブル（光る紫＝編成卓）。VN窓に被らないよう奥めに小さく ──
	const PURPLE := Color(0.65, 0.3, 1.0)
	_add_box(Vector3(0.0, 0.30, 2.6), Vector3(2.4, 0.6, 1.4), Color(0.10, 0.08, 0.14), 0.4)  # 卓本体
	_emissive_box(Vector3(0.0, 0.62, 2.6), Vector3(2.1, 0.12, 1.1), PURPLE, 2.6)  # 天面の発光
	_neon_light(Vector3(0.0, 1.3, 2.6), PURPLE, 3.2, 5.5)  # 卓からの紫光

	# ── 店内の暖色光（カウンター裏）＋提灯＋窓外のネオンで寒暖対比 ──
	_neon_light(Vector3(0.0, 2.0, -2.8), WARM, 4.0, 8.0)
	_neon_light(Vector3(-2.6, 2.4, -0.4), NEON_RED, 1.8, 5.0)
	_neon_light(Vector3(2.6, 2.4, -0.4), PINK, 1.8, 5.0)


## 紫の炎モンスター1体（暗い球体＋発光コア＋点光源＋接地影）。
func _spawn_enemy(e: Vector3, scl: float = 1.0) -> Node3D:
	var col := Color(0.72, 0.25, 1.0)
	var root := Node3D.new()
	root.position = e
	_sub.add_child(root)
	# 本体（暗い球＋紫発光）
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.7 * scl
	sm.height = 1.5 * scl
	mi.mesh = sm
	mi.position = Vector3(0, 0.85 * scl, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.08, 0.03, 0.12)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 1.8
	mi.material_override = m
	root.add_child(mi)
	# 炎コア（発光ボックス）
	var core := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.8, 0.5) * scl
	core.mesh = bm
	core.position = Vector3(0, 1.9 * scl, 0)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = col
	cm.emission_enabled = true
	cm.emission = col
	cm.emission_energy_multiplier = 3.0
	core.material_override = cm
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	# 点光源
	var o := OmniLight3D.new()
	o.position = Vector3(0, 1.2 * scl, 0)
	o.light_color = col
	o.light_energy = 3.2
	o.omni_range = 6.5
	root.add_child(o)
	# 接地影
	var sh := _make_blob_mesh(1.5 * scl)
	sh.position = Vector3(0, 0.03, 0)
	root.add_child(sh)
	return root


## ブロブ影メッシュ（ツリー未追加・呼び出し側で add_child）。
func _make_blob_mesh(w: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(w, w)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _get_blob_tex()
	m.albedo_color = Color(0, 0, 0, 0.55)
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## 潜航の敵プール（最大数を奥に並べ、最初は非表示。set_dive_state で出し入れ）。
func _build_enemies() -> void:
	var slots := [
		Vector3(0.0, 0, -2.6), Vector3(-2.9, 0, -3.4), Vector3(2.9, 0, -3.2),
		Vector3(-1.5, 0, -4.2), Vector3(1.5, 0, -4.4),
	]
	for e in slots:
		var node := _spawn_enemy(e)
		node.visible = false
		_enemy_nodes.append(node)


## main から毎フレーム：sim の mob 数＆戦闘中フラグで敵の出し入れを同期。
func set_dive_state(mob_count: int, in_combat: bool) -> void:
	for i in _enemy_nodes.size():
		_enemy_nodes[i].visible = in_combat and i < mob_count


## 横帯（フィールド）の小物：左右に足場、右に宝箱、奥に薄くネオン、右(+X)に敵を横並び。
func _build_props_strip() -> void:
	var P := CYBER_DIR + "platforms/"
	# 奥のネオン（薄く）
	_add_gltf(P + "Sign_1.gltf", Vector3(-2.0, 2.2, -4.0), 2.2, 0, 2.2)
	_add_gltf(P + "Sign_3.gltf", Vector3(2.2, 2.4, -4.2), 2.2, 0, 2.2)
	_neon_light(Vector3(0, 2.2, -3.6), Color(0.3, 0.85, 1.0), 2.5, 8.0)
	# 左右の足場（味方／敵が乗る台。中央に間合い＝対峙の溝）
	_add_box(Vector3(-3.4, -0.15, 0.4), Vector3(4.6, 0.3, 2.6), Color(0.10, 0.10, 0.16), 0.5)
	_add_box(Vector3(3.8, -0.15, 0.4), Vector3(4.4, 0.3, 2.6), Color(0.12, 0.08, 0.14), 0.5)
	_emissive_box(Vector3(-3.4, 0.02, 1.62), Vector3(4.4, 0.04, 0.1), Color(0.3, 0.8, 1.0), 1.8)  # 味方足場の縁
	_emissive_box(Vector3(3.8, 0.02, 1.62), Vector3(4.2, 0.04, 0.1), Color(0.9, 0.3, 0.8), 1.8)   # 敵足場の縁
	# 右端の宝箱（金の発光箱）
	_add_box(Vector3(6.0, 0.35, 0.3), Vector3(0.7, 0.6, 0.6), Color(0.25, 0.16, 0.05), 0.4)
	_emissive_box(Vector3(6.0, 0.62, 0.3), Vector3(0.66, 0.16, 0.56), Color(1.0, 0.8, 0.3), 2.2)
	# 敵（右に横並び・やや小さめ）
	for e in [Vector3(2.6, 0, 0.2), Vector3(3.9, 0, 0.6), Vector3(5.1, 0, 0.1)]:
		_spawn_enemy(e, 0.8)


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
func _add_gltf(res_path: String, pos: Vector3, scale: float = 1.0, yaw_deg: float = 0.0, glow_energy: float = 0.0) -> Node3D:
	var ps := load(res_path)
	if ps == null:
		return null
	var inst := (ps as PackedScene).instantiate() as Node3D
	if inst == null:
		return null
	inst.position = pos
	inst.scale = Vector3(scale, scale, scale)
	inst.rotation_degrees = Vector3(0, yaw_deg, 0)
	_sub.add_child(inst)
	_enable_shadows(inst)
	if glow_energy > 0.0:
		_make_glow(inst, glow_energy)
	return inst


## モデルの各サーフェスを濡れた金属面に（ネオンの映り込み＝低roughness＋metallic）。
func _make_wet(node: Node, metallic: float, roughness: float) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var msh := mi.mesh
		if msh != null:
			for s in msh.get_surface_count():
				var base: Material = mi.get_active_material(s)
				var m: StandardMaterial3D = (base.duplicate() if base is StandardMaterial3D else StandardMaterial3D.new())
				m.metallic = metallic
				m.roughness = roughness
				mi.set_surface_override_material(s, m)
	for c in node.get_children():
		_make_wet(c, metallic, roughness)


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
	if _is_dark():
		_player_light = OmniLight3D.new()
		_player_light.light_color = Color(1.0, 0.92, 0.85)
		_player_light.light_energy = 1.4
		_player_light.omni_range = 5.0
		_player_light.shadow_enabled = false
		_sub.add_child(_player_light)


# ホーム（黒猫飯店）のキャラ配置：店番（カウンター裏 z=-2.6）＋パーティ（手前の紫テーブル z≈3-4）。
const HOME_NPCS := [
	{"id": "nurse",  "pos": Vector3(-2.4, 0.0, -2.6), "flip": false},  # 店番
	{"id": "mil",    "pos": Vector3(0.0, 0.0, -2.6),  "flip": false},  # 店番（店長）
	{"id": "muu",    "pos": Vector3(2.4, 0.0, -2.6),  "flip": false},  # 店番
	{"id": "doctor", "pos": Vector3(-2.1, 0.0, 2.2),  "flip": false},  # パーティ
	{"id": "yuzuki", "pos": Vector3(2.1, 0.0, 2.2),   "flip": false},  # パーティ
]


# 潜航（戦闘）のパーティ配置：手前(z≈3〜5)に横並び。主人公は別途 _player_pos。
const DIVE_NPCS := [
	{"id": "mil",    "pos": Vector3(-2.8, 0.0, 2.2), "flip": false},
	{"id": "nurse",  "pos": Vector3(2.8, 0.0, 2.2),  "flip": false},
	{"id": "doctor", "pos": Vector3(1.5, 0.0, 3.0),  "flip": false},
]


# 横帯（フィールド）のパーティ配置：左(-X)に横並び。主人公は別途 _player_pos。
const STRIP_NPCS := [
	{"id": "mil",    "pos": Vector3(-3.6, 0.0, 0.2), "flip": false},
	{"id": "nurse",  "pos": Vector3(-2.6, 0.0, 0.6), "flip": false},
	{"id": "doctor", "pos": Vector3(-1.7, 0.0, 0.2), "flip": false},
]


func _build_npcs() -> void:
	var roster: Array = NPCS
	if stage_theme == "home":
		roster = HOME_NPCS
	elif stage_theme == "dive":
		roster = DIVE_NPCS
	elif stage_theme == "strip":
		roster = STRIP_NPCS
	for d in roster:
		var anim := ChibiAnim.new(String(d["id"]))
		var spr := _make_billboard()
		var base_pos: Vector3 = d["pos"]
		spr.position = base_pos + Vector3(0, _sprite_half_h(), 0)
		spr.flip_h = bool(d["flip"])
		_sub.add_child(spr)
		_npc_sprites.append(spr)
		_npc_anims.append(anim)
		_npc_base.append(base_pos)
		_npc_pos.append(base_pos)
		_npc_target.append(base_pos)
		_npc_flip.append(bool(d["flip"]))
		# 足元のブロブシャドウ（home は徘徊に追従させる）
		_npc_shadow.append(_add_blob_shadow(base_pos))


## 足元の楕円ソフトシャドウ。ビルボードは光源視点で薄くなり落ち影が不安定なため、
## HD-2D の定番どおり板の影テクスチャを地面に寝かせて確実に接地させる。
var _blob_tex: Texture2D = null

func _add_blob_shadow(pos: Vector3, w: float = 1.5) -> MeshInstance3D:
	var mi := _make_blob_mesh(w)
	mi.position = pos + Vector3(0, 0.03, 0)
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


## キャラの手続き的な揺れ（idle=呼吸のゆっくり上下／移動=歩行バウンス）。
## スプライトが単一フレームでも生命感を出す。phase でキャラごとに位相をずらす。
func _char_bob(moving: bool, phase: float) -> float:
	var t := float(Time.get_ticks_msec()) / 1000.0
	if moving:
		return absf(sin(t * 9.0 + phase)) * 0.055   # 歩行バウンス（常に上向き）
	return sin(t * 2.2 + phase) * 0.03               # 待機の呼吸


func _process(delta: float) -> void:
	_pulse += delta

	# ── 入力（WASD / 矢印）でプレイヤー移動。カメラ相対（奥行き=Z-, 横=X）──
	# home はジオラマなのでオーナーは動かさない（店番として固定）。
	var iv := Vector2.ZERO
	if stage_theme != "home":
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): iv.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): iv.y += 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): iv.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): iv.x += 1.0
	var moving := iv != Vector2.ZERO
	var player_move := Vector3.ZERO
	if moving:
		# カメラ相対移動（カメラを回しても W=画面奥 のまま操作できる）
		var basis := Basis(Vector3.UP, _cam_yaw)
		var fwd := basis * Vector3(0, 0, -1)
		var right := basis * Vector3(1, 0, 0)
		player_move = (fwd * -iv.y + right * iv.x).normalized()
		_player_pos.x = clampf(_player_pos.x + player_move.x * MOVE_SPEED * delta, -GROUND_HALF, GROUND_HALF)
		_player_pos.z = clampf(_player_pos.z + player_move.z * MOVE_SPEED * delta, -GROUND_HALF, GROUND_HALF)

	# ── プレイヤーの描画（前後=walk_front/back・横=run side view・停止=idle）──
	var p_used := false
	if moving:
		var dr := _walk_dir(player_move)
		_player_flip = bool(dr[1])
		if dr[0] != "side":
			var w := _walk_texture(PLAYER_ID, "walk_" + String(dr[0]))
			if w["tex"] != null:
				_apply_walk(_player, w)
				_player.flip_h = _player_flip
				p_used = true
	if not p_used:
		_reset_billboard(_player)
		_player_anim.update_params(1.0 if (moving or _force_moving) else 0.0)
		_player_anim.tick(delta)
		_player.texture = _tex(_player_anim.current_path())
		_player.flip_h = _player_flip
	_player.position = _player_pos + Vector3(0, _sprite_half_h() + _char_bob(moving or _force_moving, 0.0), 0)
	if _player_light != null:
		_player_light.position = _player_pos + Vector3(0, 2.2, 0.8)
	if _player_shadow != null:
		_player_shadow.position = _player_pos + Vector3(0, 0.03, 0)

	# ── NPC：home は基準位置の周りを徘徊（方向別歩行）、それ以外は待機 ──
	var wander := stage_theme == "home"
	for i in _npc_sprites.size():
		var nmoving := false
		var nmove := Vector3.ZERO
		if wander:
			var to: Vector3 = _npc_target[i] - _npc_pos[i]
			to.y = 0.0
			if to.length() < 0.2:
				# 新しい目標を基準位置の近くから選ぶ（たまに少し止まる）
				if randf() < 0.7:
					_npc_target[i] = _npc_base[i] + Vector3(randf_range(-1.3, 1.3), 0, randf_range(-1.0, 1.0))
			else:
				nmove = to.normalized()
				_npc_pos[i] += nmove * 0.9 * delta
				nmoving = true
			if i < _npc_shadow.size() and _npc_shadow[i] != null:
				_npc_shadow[i].position = _npc_pos[i] + Vector3(0, 0.03, 0)
		# 待機/歩行のアイドルモーション（呼吸の上下＋歩行バウンス）を全 NPC に適用
		_npc_sprites[i].position = _npc_pos[i] + Vector3(0, _sprite_half_h() + _char_bob(nmoving, float(i) * 0.7), 0)
		if nmoving:
			var dr := _walk_dir(nmove)
			_npc_sprites[i].flip_h = bool(dr[1])   # 左右反転（side や素材無しでも効く）
			if dr[0] != "side":
				var w := _walk_texture(_npc_anims[i].char_id, "walk_" + String(dr[0]))
				if w["tex"] != null:
					_apply_walk(_npc_sprites[i], w)
					continue
		_reset_billboard(_npc_sprites[i])
		_npc_anims[i].update_params(1.0 if nmoving else 0.0)  # 横/素材無しは run、停止は idle
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
	# 注視点：通常はプレイヤー追従、home は固定注視点（据置構図）
	var look: Vector3 = _cam_target_override if _cam_target_override != null else _player_pos
	var offset := Basis(Vector3.UP, _cam_yaw) * Vector3(0, _cam_height, _cam_dist)
	var target := look + offset
	if instant:
		_cam.position = target
	else:
		_cam.position = _cam.position.lerp(target, 0.18)
	_cam.look_at(look + Vector3(0, 1.0, 0), Vector3.UP)


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


## 単純ロード（フォールバックなし）。方向別スプライト存在判定に使う。
func _tex_opt(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[path]


## カメラ相対の移動方向 → [向き, 左右反転]。向き ∈ {"front","back","side"}。
## カメラへ向かう＝正面、離れる＝背面、横移動＝side（既存 run=side view を使う）。
func _walk_dir(world_move: Vector3) -> Array:
	var basis := Basis(Vector3.UP, _cam_yaw)
	var into_screen := basis * Vector3(0, 0, -1)   # W で進む向き＝カメラから見て奥
	var right := basis * Vector3(1, 0, 0)
	var m := world_move.normalized()
	var fd := m.dot(into_screen)   # >0: 奥へ＝背面 / <0: 手前へ＝正面
	var rd := m.dot(right)
	var dir := "side"
	if fd > 0.45:
		dir = "back"
	elif fd < -0.45:
		dir = "front"
	return [dir, rd < 0.0]


var _walk_count_cache: Dictionary = {}

## <id>/<anim>_f<n>.png の連番数（キャッシュ）。0 なら未生成。
func _walk_count(id: String, anim: String) -> int:
	var key := id + "/" + anim
	if _walk_count_cache.has(key):
		return _walk_count_cache[key]
	var n := 0
	while ResourceLoader.exists(SPRITE_DIR + "%s/%s_f%d.png" % [id, anim, n]):
		n += 1
	_walk_count_cache[key] = n
	return n


## 指定アニメ（walk_front / walk_back）の現フレーム {tex, ph}。連番が在れば返す。
## 無ければ tex=null（呼び出し側が run/idle にフォールバック）。
## ※既存の walk_front.png（別解像度シート）は使わない（_f<n> 連番のみ）。
func _walk_texture(id: String, anim: String) -> Dictionary:
	var n := _walk_count(id, anim)
	if n == 0:
		return {"tex": null}
	var fr := int(Time.get_ticks_msec() / 140) % n   # ~7fps
	return {"tex": _tex_opt(SPRITE_DIR + "%s/%s_f%d.png" % [id, anim, fr]), "ph": PIXEL_SIZE}


## 方向別歩行スプライトをビルボードに適用（flip は呼び出し側で設定）。
func _apply_walk(spr: Sprite3D, w: Dictionary) -> void:
	spr.texture = w["tex"]
	spr.vframes = 1
	spr.hframes = 1
	spr.frame = 0
	spr.pixel_size = float(w["ph"])


## ビルボードを通常（単一フレーム・既定 pixel_size）に戻す。
func _reset_billboard(spr: Sprite3D) -> void:
	if spr.hframes != 1 or spr.pixel_size != PIXEL_SIZE:
		spr.hframes = 1
		spr.vframes = 1
		spr.frame = 0
		spr.pixel_size = PIXEL_SIZE
