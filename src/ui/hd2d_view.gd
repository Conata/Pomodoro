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

## キャラのビルボードを置く描画レイヤー（装飾ライトの照射対象から外すため）。
const CHAR_LAYER := 2
const CHAR_LAYER_MASK := 1 << (CHAR_LAYER - 1)
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
const CAM_DIST_MAX := 26.0

var _sub: SubViewport
var _cam: Camera3D
var _player: Sprite3D
var _player_pos := Vector3(0, 0, 4.0)
var _player_anim: ChibiAnim
var _player_flip := false
var _player_light: OmniLight3D = null  # 主人公追従のキーライト（cyberpunk のみ）
var _player_shadow: MeshInstance3D = null  # 主人公追従のブロブシャドウ
var _player_rim: Sprite3D = null   # ネオンのリム発光（環境光に馴染ませる）
var _player_refl: Sprite3D = null  # 濡れ床への擬似反射
var _enemy_nodes: Array = []           # 潜航の敵プール（set_dive_state で出し入れ）
var _enemy_base: Array = []            # 敵プールの基準位置（戦闘の踏み込み用）
var _combat := false                   # 戦闘中（敵の踏み込みモーション）
var _shake := 0.0                      # カメラシェイク残量（punch() で加算）
var _npc_sprites: Array[Sprite3D] = []
var _npc_anims: Array[ChibiAnim] = []
var _npc_base: Array = []      # home の徘徊：基準位置
var _npc_pos: Array = []        # home の徘徊：現在位置
var _npc_target: Array = []     # home の徘徊：目標位置
var _npc_flip: Array = []
var _npc_rig: Array = []        # キャラ固有のモーション定数（_make_rig）
var _npc_body: Array = []       # 体のバネ状態 {y, vy, x, vx}＝重心の遅れ
var _npc_state: Array = []      # 徘徊のステート "wait"/"turn"/"walk"/"settle"
var _npc_timer: Array = []      # ステートの残り時間（秒）
var _npc_spd: Array = []        # 現在の歩行速度（加減速で慣性を出す）
var _npc_cycle: Array = []      # 歩行サイクル位相（進んだ距離で進む＝足が滑らない）
var _npc_dir: Array = []        # 直近の進行方向（向き変えの予備動作に使う）
var _npc_lean: Array = []       # 予備動作の傾き量（-1..1）
var _npc_shadow: Array = []     # home の徘徊：影（追従）
var _npc_rim: Array = []        # 各 NPC のリム発光（無効時 null）
var _npc_refl: Array = []       # 各 NPC の擬似反射（無効時 null）
var _npc_ids: Array = []        # ロスターの girl id（配置更新・会話マーカー用）
var _renov_built: Dictionary = {}   # 建立済みの改装プロップ（node id -> true）
var _talk_label: Label3D = null     # 会話できる子の頭上「！」
# リム発光／擬似反射の設定（テーマ別に _ready で決定）
var _rim_on := true
var _rim_col := Color(0.45, 0.85, 1.0, 0.22)
var _refl_on := false
var _refl_col := Color(0.5, 0.7, 1.0, 0.30)
var _intro_t := 0.0            # カメラ導入（ズームイン）の経過秒
var _intro_from := 0.0         # 導入開始時のカメラ距離
var _intro_active := false     # 導入中はイージング曲線で距離を直接決める
const INTRO_TIME := 2.6        # 導入の尺（秒）
var _tex_cache := {}
var _pulse := 0.0              # 全モーションの基準時計（delta 積算＝フレームレート非依存）
var _player_rig := {}          # 主人公のモーション定数
var _player_body := {"y": 0.0, "vy": 0.0, "x": 0.0, "vx": 0.0}
var _player_cycle := 0.0       # 主人公の歩行サイクル位相
var _player_spd := 0.0         # 主人公の現在速度（停止時の慣性用）
var _lanterns: Array = []      # 提灯の振り子 {node, w, ph, amp, w2, ph2, core, cw, cph}
var _flickers: Array = []      # 明滅する発光面 {mat, base, kind, w, ph}
# オクトラ風：ワールドが主人公の周りを回る回転カメラ＋ズーム（SimpleHD2D 参考）
var _cam_yaw := 0.0                # 現在のヨー角（rad）
var _cam_yaw_target := 0.0         # Q/E で ±90° 刻みの目標
var _cam_dist := 9.0
var _cam_dist_target := 9.0
var _force_moving := false         # スクショ撮影用：入力なしでも歩行アニメを再生
var _cam_height := CAM_HEIGHT       # カメラ高さ（俯瞰アングル時に上げる）
var _cam_target_override = null      # Vector3 指定で注視点を固定（home の据置構図用）
var _cam_base := Vector3.ZERO        # 揺れを足す前のカメラ位置（揺れが次フレームへ蓄積しないように）
var _mouse_dragging := false         # 右/中ボタンでドラッグ中フラグ
const CAM_DRAG_SENSITIVITY := 0.006  # rad/px：右ドラッグでヨー回転


func _ready() -> void:
	# 配置は親/シーン側の anchors に従う（フルレクト指定が無ければ自分でフル）。
	if get_anchor(SIDE_RIGHT) == 0.0 and get_anchor(SIDE_BOTTOM) == 0.0:
		set_anchors_preset(Control.PRESET_FULL_RECT)
	# テーマ別リム発光／擬似反射：濡れた夜の街は反射＋冷色リム、店は暖色リム、自然はリム無し
	match stage_theme:
		"home":
			# リム発光は use_hdr_2d 下で半透明ビルボードが不透明な板として焼ける不具合が出る
			# （スプライトの透明部分がピンクの矩形になる）ため home では使わない。
			_rim_on = false; _refl_on = false
		"cyberpunk", "dive", "strip":
			_rim_col = Color(0.45, 0.85, 1.0, 0.22); _refl_on = true
		_:
			_rim_on = false; _refl_on = false
	# テーマ別カメラ：home は店先を見るので低い角度（見下ろしを弱める）
	if stage_theme == "home":
		# 下部UI（仕込みカード＋CTA＋VN窓）が約480px を占めるので、キャラは奥へ寄せ、
		# 注視点を上げてディオラマの重心を画面の上寄りに置く。手前に出すとUIに脚を食われる。
		_player_pos = Vector3(0, 0, 1.6)   # 主人公はパーティテーブル
		_cam_target_override = Vector3(0, 1.35, -0.3)  # カウンター/バーを主役に
		_cam_height = 5.2
		_cam_dist = 13.5
		_cam_dist_target = 13.5
	elif stage_theme == "dive":
		# 戦闘：パーティ手前(z+)・敵奥(z-)。下部UIに隠れないようパーティを少し奥へ。
		_player_pos = Vector3(0, 0, 2.4)   # 主人公はパーティ中央
		_cam_target_override = Vector3(0, 1.0, 1.2)
		_cam_height = 6.5
		_cam_dist = 11.5
		_cam_dist_target = 11.5
	elif stage_theme == "strip":
		# 横帯：パーティ左(-X)・敵右(+X)。中央に間合いを取り対峙感を出す
		# 横帯は 720x110 前後の極端な横長。カメラを低く寄せないと、画の大半が
		# 足場の上の空間になり「黒い帯」に見える。キャラの胸から下で切る構図にする。
		_player_pos = Vector3(-3.4, 0, 0.4)  # 主人公はパーティ左端
		_cam_target_override = Vector3(0.4, 1.15, 0.3)
		_cam_height = 1.5
		_cam_dist = 7.2
		_cam_dist_target = 7.2
	_build_viewport()
	_build_world()
	_build_player()
	_build_npcs()
	_build_vignette()
	# home：導入はズームアウトから開始し、尺を決めたイージングで寄せる（_update_camera）
	if stage_theme == "home":
		_cam_dist = _cam_dist_target * 2.4
		_intro_from = _cam_dist
		_intro_t = 0.0
		_intro_active = true
		var look: Vector3 = _cam_target_override if _cam_target_override != null else _player_pos
		_cam.position = look + Basis(Vector3.UP, _cam_yaw) * Vector3(0, _cam_height * 1.5, _cam_dist)
		_cam.look_at(look + Vector3(0, 1.0, 0), Vector3.UP)
	set_process(true)
	set_process_input(true)


## カメラ操作：Q/E で 90° 回転、R/F でズーム（キーボード）。
## 右クリック/中クリックドラッグでヨー回転、スクロールホイールでズーム（マウス）。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q: _cam_yaw_target -= PI * 0.5
			KEY_E: _cam_yaw_target += PI * 0.5
			KEY_R: _cam_dist_target = clampf(_cam_dist_target - 2.0, CAM_DIST_MIN, CAM_DIST_MAX)
			KEY_F: _cam_dist_target = clampf(_cam_dist_target + 2.0, CAM_DIST_MIN, CAM_DIST_MAX)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_mouse_dragging = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				_cam_dist_target = clampf(_cam_dist_target - 1.5, CAM_DIST_MIN, CAM_DIST_MAX)
			MOUSE_BUTTON_WHEEL_DOWN:
				_cam_dist_target = clampf(_cam_dist_target + 1.5, CAM_DIST_MIN, CAM_DIST_MAX)
	elif event is InputEventMouseMotion and _mouse_dragging:
		var motion := event as InputEventMouseMotion
		_cam_yaw_target += motion.relative.x * CAM_DRAG_SENSITIVITY


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
	# HDR で描く。これが無いと RGBA8(LDR) に直接焼かれ、emission energy > 1.0 の指定が
	# すべて純白へのクリップに化ける（ネオンが色を失って白い板になる）。
	_sub.use_hdr_2d = true
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


func _add_box(pos: Vector3, sz: Vector3, col: Color, rough: float = 0.9, yaw: float = 0.0,
		grain: float = 0.0) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees = Vector3(0, yaw, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	# grain > 0 で木目テクスチャを貼る。無地の直方体は「Blender初日の白箱」に見えるので、
	# 面積の大きい什器（カウンター・棚板・壁）には必ず素地を入れる。
	if grain > 0.0:
		m.albedo_texture = _get_wood_tex()
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.uv1_scale = Vector3(sz.x * grain, sz.y * grain, sz.z * grain)
	mi.material_override = m
	_sub.add_child(mi)


## 木目テクスチャ（手続き生成・32x32）。縦の板目と節を薄く入れた白木のグレースケール。
## albedo_color に乗算されるので、色は呼び出し側の col が決める。
var _wood_tex: ImageTexture = null

func _get_wood_tex() -> ImageTexture:
	if _wood_tex != null:
		return _wood_tex
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			# 板の継ぎ目（8px ごと）＋板ごとにずらした縦の木目
			var plank := int(x / 8)
			var seam := 1 if (x % 8 == 0) else 0
			var g := 1.0
			g -= 0.22 * float(seam)
			g += sin(float(y) * 0.9 + float(plank) * 2.3) * 0.05
			g += (float((x * 13 + y * 7) % 11) / 11.0 - 0.5) * 0.07
			var knot := absf(sin(float(y) * 0.35 + float(plank))) > 0.985
			if knot:
				g -= 0.18
			g = clampf(g, 0.55, 1.15)
			img.set_pixel(x, y, Color(g, g * 0.985, g * 0.96))
	_wood_tex = ImageTexture.create_from_image(img)
	return _wood_tex


## 発光する箱（ネオン看板/提灯）。emission を glow_hdr_threshold 超えまで上げて滲ませる。
## emission は最大チャンネルで正規化してから energy を掛ける。col をそのまま入れると
## 暗いチャンネルまで一緒に持ち上がり、明るくするほど白に寄って「色の無いネオン」になる。
func _emissive_box(pos: Vector3, sz: Vector3, col: Color, energy: float = 3.0, yaw: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees = Vector3(0, yaw, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = col * 0.22   # 本体は暗い色板。光っているのは emission の側
	m.emission_enabled = true
	var peak := maxf(maxf(col.r, col.g), col.b)
	m.emission = col / maxf(peak, 0.001)   # 純色に正規化（彩度を保つ）
	m.emission_energy_multiplier = energy
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sub.add_child(mi)
	return mi


## 発光面を明滅させる登録。kind で癖を変える：
##   "hum"   … 蛍光管のわずかな唸り（±3%）。看板の地の面に。
##   "buzz"  … 接触不良のネオン。時々ふっと落ちて細かく戻る。1〜2枚だけに使う。
##   "pulse" … ゆっくりした息づかい（±12%）。店内の窓明かり・編成卓の縁。
## 位相と周期は呼び出し側でばらすこと（全部同じ周期で光ると安っぽい）。
func _flicker(mi: MeshInstance3D, kind: String, period: float, phase: float) -> void:
	if mi == null:
		return
	var m := mi.material_override as StandardMaterial3D
	if m == null:
		return
	_flickers.append({"mat": m, "base": m.emission_energy_multiplier,
			"kind": kind, "w": TAU / maxf(period, 0.05), "ph": phase})


## 明滅の更新。同じ位相に揃わないよう、各要素は自前の周期と位相で回す。
func _update_flickers() -> void:
	var t := _pulse
	for f in _flickers:
		var m: StandardMaterial3D = f["mat"]
		var p: float = t * float(f["w"]) + float(f["ph"])
		var k := 1.0
		match String(f["kind"]):
			"hum":
				# 周期の異なる2波の重ね（一定のうねりに聞こえないように）
				k = 1.0 + 0.030 * sin(p) + 0.018 * sin(p * 2.7 + 1.1)
			"buzz":
				# 大半は安定。1周期のごく短い区間だけ落ちて、細かくばたついて戻る
				var u := fposmod(p / TAU, 1.0)
				k = 1.0 + 0.02 * sin(p * 3.1)
				if u < 0.07:
					var v := u / 0.07
					k *= lerpf(0.28, 1.0, v * v) + 0.16 * sin(v * 47.0)
			"pulse":
				# ゆっくり息をする光。山を鋭く谷を長くして機械的な sin から外す
				k = 1.0 + 0.12 * sin(p + 0.5 * sin(p))
			_:
				k = 1.0
		m.emission_energy_multiplier = float(f["base"]) * k




## 円柱の小物（蒸籠・丼・鍋）。箱ばかりだと什器がすべて同じ形に見えるので、
## 曲面を混ぜてシルエットに変化を出す。
func _add_cylinder(pos: Vector3, radius: float, height: float, col: Color,
		rough: float = 0.8) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius * 0.94
	cm.height = height
	cm.radial_segments = 12
	cm.rings = 1
	mi.mesh = cm
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	mi.material_override = m
	_sub.add_child(mi)


## 赤提灯1個（紡錘形の胴＋上下の口金＋吊り紐＋白い芯）。
## 発光する箱は「光る板」にしか見えないので、シルエットで提灯だと分かる形にする。
## 吊り紐の上端を支点にした Node3D の下にぶら下げ、_process で振り子として揺らす
## （揺れは _update_lanterns。1本ずつ周期と位相を変える）。
func _add_lantern(pos: Vector3, col: Color) -> void:
	const PIVOT_Y := 0.63          # 紐の上端＝支点。ここを軸に振れる
	var pivot := Node3D.new()
	pivot.position = pos + Vector3(0, PIVOT_Y, 0)
	_sub.add_child(pivot)
	var o := Vector3(0, -PIVOT_Y, 0)   # 支点から見た「元の pos」

	# 胴：カプセルを縦に潰して紡錘形に
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.24
	cm.height = 0.62
	cm.radial_segments = 10
	cm.rings = 4
	body.mesh = cm
	body.position = o
	body.scale = Vector3(1.0, 0.78, 1.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = col * 0.25
	m.emission_enabled = true
	var peak := maxf(maxf(col.r, col.g), col.b)
	m.emission = col / maxf(peak, 0.001)
	m.emission_energy_multiplier = 1.25
	m.roughness = 0.7
	body.material_override = m
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(body)
	# 上下の黒い口金（提灯の輪郭を締める）
	for dy in [0.28, -0.28]:
		_child_box(pivot, o + Vector3(0, dy, 0), Vector3(0.16, 0.06, 0.16), Color(0.06, 0.03, 0.03))
	# 吊り紐
	_child_box(pivot, o + Vector3(0, 0.46, 0), Vector3(0.03, 0.34, 0.03), Color(0.10, 0.06, 0.05))
	# 芯：小さく強い白。夜の画で一番明るい点になる
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.10
	sm.radial_segments = 8
	sm.rings = 4
	core.mesh = sm
	core.position = o
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.3, 0.15, 0.12)
	cmat.emission_enabled = true
	cmat.emission = Color(1.0, 0.93, 0.86)
	cmat.emission_energy_multiplier = 6.0
	core.material_override = cmat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(core)

	# 揺れの定数。位置から決定的に散らす（隣り合う提灯が同位相で揃うのを避ける）。
	var r := RandomNumberGenerator.new()
	r.seed = absi(hash("lantern%.2f_%.2f" % [pos.x, pos.z]))
	_lanterns.append({
		"node": pivot,
		"w": TAU / r.randf_range(3.4, 5.3),      # 主振動の周期（秒）。互いに整数比にならない範囲
		"ph": r.randf_range(0.0, TAU),
		"amp": r.randf_range(0.062, 0.115),      # 最大 3.6〜6.6°（止まって見える提灯を作らない）
		"w2": TAU / r.randf_range(4.7, 7.9),     # 奥行き方向はさらに遅く＝円を描くように振れる
		"ph2": r.randf_range(0.0, TAU),
		"core": cmat,
		"core_e": 6.0,
		"cw": r.randf_range(4.1, 6.9),           # 灯芯のゆらぎ
		"cph": r.randf_range(0.0, TAU),
	})


## 親ノードのローカル座標に置く無地の箱（提灯の部品用）。
func _child_box(parent: Node3D, pos: Vector3, sz: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.7
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## 提灯の揺れと灯芯のゆらぎ。振り子は「端で遅く、下で速い」ので、単純な sin ではなく
## 位相変調で端の溜めを作る。奥行き方向は別周期にして、真横往復に見えないようにする。
func _update_lanterns() -> void:
	var t := _pulse
	for l in _lanterns:
		var n: Node3D = l["node"]
		var p: float = t * float(l["w"]) + float(l["ph"])
		var a: float = float(l["amp"])
		n.rotation.z = sin(p + 0.35 * sin(p)) * a
		n.rotation.x = sin(t * float(l["w2"]) + float(l["ph2"])) * a * 0.5
		# 灯芯：ろうそくのゆらぎ。3つの無関係な周期を足して繰り返しを感じさせない
		var c: StandardMaterial3D = l["core"]
		var cp: float = t * float(l["cw"]) + float(l["cph"])
		var f := 1.0 + 0.11 * sin(cp) + 0.06 * sin(cp * 2.31 + 1.7) + 0.035 * sin(cp * 0.43)
		c.emission_energy_multiplier = float(l["core_e"]) * f


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
	# 装飾ライトはキャラを照らさない。Y固定ビルボードは法線がカメラを向くので
	# 近くの点光源をまともに受けて白飛びする（とくに白衣・白ドレス）。
	# キャラは CHAR_LAYER に置き、キーライトと環境光と主人公用ライトだけで陰影を作る。
	o.light_cull_mask = ~CHAR_LAYER_MASK
	_sub.add_child(o)


## 中心が濃く外周へなだらかに消える白いソフト円（湯気/リム/反射に流用）。
var _soft_tex: Texture2D = null

func _get_soft_tex() -> Texture2D:
	if _soft_tex != null:
		return _soft_tex
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) * 0.5
	for y in n:
		for x in n:
			var dd := Vector2(x - c, y - c).length() / c
			var a := clampf(1.0 - dd, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)  # smoothstep でふんわり
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_soft_tex = ImageTexture.create_from_image(img)
	return _soft_tex


## 立ち上る湯気/蒸気（鍋・蒸籠・路面の排気）。柔らかい白い粒が昇りながら膨らんで消える。
## CPUParticles3D なのでどのレンダラでも動く（GL Compatibility 可）。
func _build_steam(pos: Vector3, extents: Vector3, col: Color, amount: int = 22, rise: float = 1.0) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.7)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD  # 暗い夜に淡く光って馴染む
	m.albedo_texture = _get_soft_tex()
	m.albedo_color = col
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	quad.material = m

	var p := CPUParticles3D.new()
	p.mesh = quad
	p.position = pos
	p.amount = amount
	p.lifetime = 3.6
	p.preprocess = 3.0
	p.randomness = 1.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3(0, 1, 0)
	p.spread = 12.0
	p.gravity = Vector3(0.05, 0.55 * rise, 0.0)
	p.initial_velocity_min = 0.25 * rise
	p.initial_velocity_max = 0.7 * rise
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.35))
	sc.add_point(Vector2(1.0, 1.6))
	p.scale_amount_curve = sc
	var g := Gradient.new()
	g.set_offset(0, 0.0); g.set_color(0, Color(col.r, col.g, col.b, 0.0))
	g.add_point(0.25, Color(col.r, col.g, col.b, 0.8))
	g.set_offset(g.get_point_count() - 1, 1.0)
	g.set_color(g.get_point_count() - 1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = g
	_sub.add_child(p)


## 縦に伸びるソフトな光芒テクスチャ（上=明 → 下=減衰、左右端もなだらかに消える）。
var _shaft_tex: Texture2D = null

func _get_shaft_tex() -> Texture2D:
	if _shaft_tex != null:
		return _shaft_tex
	var w := 32
	var h := 96
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var vy := float(y) / float(h - 1)
		var va := clampf(1.0 - vy, 0.0, 1.0)
		va = va * va                       # 上ほど明るく、下へ二次で減衰
		for x in w:
			var ux := absf(float(x) / float(w - 1) - 0.5) * 2.0
			var ha := clampf(1.0 - ux, 0.0, 1.0)
			ha = ha * ha * (3.0 - 2.0 * ha)  # 左右端をなだらかに
			img.set_pixel(x, y, Color(1, 1, 1, va * ha))
	_shaft_tex = ImageTexture.create_from_image(img)
	return _shaft_tex


## 光芒（ゴッドレイ）。ネオン看板や窓から差す埃っぽい光の筋を、加算の板で擬似的に。
func _light_shaft(pos: Vector3, sz: Vector2, col: Color, yaw_deg: float = 0.0, tilt_deg: float = 0.0) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = sz
	mi.mesh = q
	mi.position = pos
	mi.rotation_degrees = Vector3(tilt_deg, yaw_deg, 0.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = _get_shaft_tex()
	m.albedo_color = col
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sub.add_child(mi)


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

	# ── 光芒（看板/街灯から差す埃っぽい光の筋）──
	_light_shaft(Vector3(-3.8, 2.4, -6.6), Vector2(2.2, 5.0), Color(NEON_MAGENTA.r, NEON_MAGENTA.g, NEON_MAGENTA.b, 0.16), 8, 8)
	_light_shaft(Vector3(3.8, 2.6, -6.8), Vector2(2.2, 5.2), Color(NEON_CYAN.r, NEON_CYAN.g, NEON_CYAN.b, 0.16), -8, 8)
	_light_shaft(Vector3(0.0, 3.0, -7.8), Vector2(2.6, 6.0), Color(NEON_CYAN.r, NEON_CYAN.g, NEON_CYAN.b, 0.12), 0, 6)

	# ── 路面の排気/スチーム（手前と中景。サイバーパンクの定番）──
	_build_steam(Vector3(-3.4, 0.1, 1.6), Vector3(0.5, 0.1, 0.4), Color(0.55, 0.8, 1.0, 0.5), 18, 1.1)
	_build_steam(Vector3(3.0, 0.1, -0.6), Vector3(0.5, 0.1, 0.4), Color(0.9, 0.55, 0.85, 0.45), 16, 1.0)
	_build_steam(Vector3(0.4, 0.1, 3.2), Vector3(0.6, 0.1, 0.4), Color(0.7, 0.9, 1.0, 0.4), 14, 0.9)


## ホーム（黒猫飯店）の環境。設計の肝＝「店内の暖色 × 窓の外の冷たいネオン都市」の寒暖対比。
## 暖色の店内環境光＋弱い夜空。ネオンは _build_props_home の発光＋OmniLight が担う。
func _build_env_home() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.06)  # 夜
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.34, 0.28, 0.24)  # 暖色寄りの環境光（店内）
	env.ambient_light_energy = 0.10
	env.glow_enabled = true
	# HDR 描画（use_hdr_2d）前提。閾値1.0＝「1を超えた分だけ」滲ませ、加算合成で色を残す。
	# SOFTLIGHT（既定）はハローを白へ寄せるのでネオンの色が死ぬ。
	env.glow_intensity = 0.55
	env.glow_bloom = 0.10
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set("glow_levels/4", true)   # 小さい光芯
	env.set("glow_levels/5", true)   # 広い色ハロー
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.8   # 3.0 だとロールオフが強すぎて提灯の芯まで灰色に潰れる
	# 空気遠近：奥のネオン街を沈ませて主役（店先）を前に出す
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.06, 0.13)
	env.fog_density = 0.05
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 1.0
	# 夜の露出：全体を少し締め、ネオンの彩度を取り戻す
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.18
	env.adjustment_brightness = 1.0   # 暗さは環境光で作る。ポストで落とすと階調ごと失う
	env.adjustment_saturation = 1.30
	var we := WorldEnvironment.new()
	we.environment = env
	_sub.add_child(we)

	# 店内を照らす暖色の弱いキーライト（影あり）
	var key := DirectionalLight3D.new()
	# カメラは +Z から見るので、左上手前から差す光にすると影が手前の床へ伸びて読める
	key.rotation_degrees = Vector3(-38.0, 35.0, 0.0)
	key.light_energy = 1.25
	key.light_color = Color(1.0, 0.82, 0.6)
	key.shadow_enabled = true
	key.shadow_blur = 0.6
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	key.directional_shadow_max_distance = 30.0
	key.shadow_normal_bias = 0.3
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
	_add_gltf(P + "Sign_1.gltf", Vector3(-4.4, 3.6, -9.6), 2.6, 0, 1.0)
	_add_gltf(P + "Sign_3.gltf", Vector3(4.4, 3.8, -9.8), 2.6, 0, 1.0)
	_add_gltf(P + "Sign_Corner_1.gltf", Vector3(6.0, 2.8, -8.6), 2.2, -25, 1.0)
	_add_gltf(P + "Antenna_1.gltf", Vector3(-5.4, 5.6, -10.6), 1.6, 0)
	_add_gltf(P + "AC_Stacked.gltf", Vector3(5.6, 1.8, -8.8), 1.3, -15)
	_neon_light(Vector3(-4.2, 2.8, -8.6), NEON_MAGENTA, 1.3, 7.0)
	_neon_light(Vector3(4.2, 2.8, -8.8), NEON_CYAN, 1.3, 7.0)

	# ── 店先「黒猫飯店」：カウンター＋暖色の店内＋赤い看板 ──
	# カウンター（横長の台）
	_add_box(Vector3(0.0, 0.55, -1.2), Vector3(7.0, 1.1, 1.0), Color(0.16, 0.10, 0.08), 0.5, 0.0, 0.9)
	_add_box(Vector3(0.0, 1.15, -1.2), Vector3(7.2, 0.12, 1.2), Color(0.28, 0.18, 0.12), 0.4, 0.0, 0.9)  # 天板
	# 背後の店内壁（暖色で発光させて「店内の灯り」）
	_add_box(Vector3(0.0, 1.8, -3.6), Vector3(8.0, 3.6, 0.4), Color(0.18, 0.10, 0.06), 0.6, 0.0, 0.7)
	# 暖色の店内窓。中で人が働いている体でゆっくり息をさせる（面が一番大きいので周期は長め）
	_flicker(_emissive_box(Vector3(0.0, 1.7, -3.35), Vector3(6.4, 2.0, 0.1), WARM, 0.35),
			"pulse", 9.3, 0.0)
	# ピンクのネオン看板「黒猫飯店」（カウンター上・店の主役サイン）
	# 発光は看板の"面"を光らせるだけに留め（強すぎると白飛びして文字が消える）、
	# 店名は Label3D で面の手前に置く。看板に文字が無いと「作りかけ」に見えるため。
	const PINK := Color(1.0, 0.32, 0.72)
	_add_box(Vector3(0.0, 3.5, -2.62), Vector3(4.9, 1.0, 0.22), Color(0.10, 0.03, 0.07), 0.5)  # 看板の枠
	# 主役サインは安定させる（ここが暴れると画の芯がぶれる）。管の唸りぶんだけ揺らす
	_flicker(_emissive_box(Vector3(0.0, 3.5, -2.6), Vector3(4.8, 0.9, 0.2), PINK, 0.55),
			"hum", 2.9, 0.0)
	_sign_text("黒猫飯店", Vector3(0.0, 3.5, -2.46), 0.62, Color(2.4, 1.9, 2.3))
	# 左のタテ看板だけ接触不良にする（1枚だけ壊れているのが下町の夜。全部やると安っぽい）
	_flicker(_emissive_box(Vector3(-2.9, 3.0, -2.4), Vector3(0.42, 1.7, 0.18), PINK, 0.5),
			"buzz", 6.7, 1.4)  # タテ看板
	_sign_text("酒", Vector3(-2.9, 3.32, -2.28), 0.30, Color(2.2, 1.8, 2.2))
	_sign_text("麺", Vector3(-2.9, 2.72, -2.28), 0.30, Color(2.2, 1.8, 2.2))
	# 対のシアンは健全な管。左とは周期も位相も別にして「対で点滅」を避ける
	_flicker(_emissive_box(Vector3(2.9, 3.0, -2.4), Vector3(0.42, 1.7, 0.18), NEON_CYAN, 0.5),
			"hum", 4.3, 2.6)  # 対のシアン
	_sign_text("点", Vector3(2.9, 3.32, -2.28), 0.30, Color(1.7, 2.3, 2.4))
	_sign_text("心", Vector3(2.9, 2.72, -2.28), 0.30, Color(1.7, 2.3, 2.4))
	# 赤提灯を店先に吊るす（中華）。箱ではなく紡錘形＋上下の黒い口金＋吊り紐で「提灯の形」にし、
	# 中心に白に近い芯を仕込む（画面で最も明るい点を意図的に作る＝夜の絵の基準点）。
	for x in [-3.4, -2.0, -0.7, 0.7, 2.0, 3.4]:
		_add_lantern(Vector3(x, 2.7, -0.4), NEON_RED)
	# 「千客万来」の赤い札（黒猫飯店サインの下）
	_flicker(_emissive_box(Vector3(0.0, 2.45, -2.5), Vector3(1.7, 0.46, 0.15), NEON_RED, 0.45),
			"hum", 3.7, 0.9)
	_sign_text("千客萬来", Vector3(0.0, 2.45, -2.40), 0.26, Color(2.2, 1.9, 1.4))

	# ── カウンター裏の酒瓶棚（バーらしさ。色とりどりの小瓶＋棚板）──
	var bottle_cols := [
		Color(0.95, 0.6, 0.3), Color(0.4, 0.85, 0.6), Color(0.85, 0.4, 0.55),
		Color(0.5, 0.65, 0.95), Color(0.95, 0.82, 0.4),
	]
	_add_box(Vector3(0.0, 1.30, -3.2), Vector3(7.6, 0.06, 0.3), Color(0.22, 0.14, 0.09), 0.5, 0.0, 1.2)  # 棚板
	_add_box(Vector3(0.0, 1.86, -3.2), Vector3(7.6, 0.06, 0.3), Color(0.22, 0.14, 0.09), 0.5, 0.0, 1.2)
	for row in 2:
		var sy := 1.5 + row * 0.56
		for i in 9:
			_emissive_box(Vector3(-3.6 + i * 0.9, sy, -3.12), Vector3(0.15, 0.4, 0.12),
					bottle_cols[i % bottle_cols.size()], 0.45)

	# ── パーティテーブル（光る紫＝編成卓）。VN窓に被らないよう奥めに小さく ──
	const PURPLE := Color(0.65, 0.3, 1.0)
	_add_box(Vector3(0.0, 0.30, 2.6), Vector3(2.4, 0.6, 1.4), Color(0.10, 0.08, 0.14), 0.4)  # 卓本体
	_add_box(Vector3(0.0, 0.62, 2.6), Vector3(2.1, 0.12, 1.1), Color(0.07, 0.05, 0.10), 0.4)  # 天面
	# 編成卓の縁。手前と奥をわずかにずらして息をさせる（左右対称に光ると板に見える）
	_flicker(_emissive_box(Vector3(0.0, 0.62, 3.14), Vector3(2.1, 0.05, 0.06), PURPLE, 1.4),
			"pulse", 5.1, 0.0)  # 縁だけ光らせる
	_flicker(_emissive_box(Vector3(0.0, 0.62, 2.06), Vector3(2.1, 0.05, 0.06), PURPLE, 1.4),
			"pulse", 6.2, 2.2)
	# 卓からの紫光。編成卓の縁のすぐ脇にパーティが立つ＝一番キャラに近い点光源なので、
	# 歩いて寄ったときに白飛びしない強さに抑える（面の発光で明るさは足りている）。
	_neon_light(Vector3(0.0, 1.3, 2.6), PURPLE, 2.4, 5.2)

	# ── 店内の暖色光（カウンター裏）＋提灯＋窓外のネオンで寒暖対比 ──
	_neon_light(Vector3(0.0, 2.0, -2.8), WARM, 1.8, 5.5)
	_neon_light(Vector3(-2.6, 2.4, -0.4), NEON_RED, 1.8, 5.0)
	_neon_light(Vector3(2.6, 2.4, -0.4), PINK, 1.8, 5.0)

	# ── カウンター上の什器（蒸籠の山・丼・中華鍋）──
	# 面が空いていると「置いただけの台」に見える。湯気の出どころを実体として置く。
	for i in 3:   # 蒸籠を3段重ね（左）
		_add_cylinder(Vector3(-2.2, 1.28 + i * 0.17, -1.1), 0.30, 0.15,
				Color(0.42, 0.30, 0.17), 0.85)
	for i in 2:   # 蒸籠2段（右）
		_add_cylinder(Vector3(2.2, 1.28 + i * 0.17, -1.1), 0.30, 0.15,
				Color(0.42, 0.30, 0.17), 0.85)
	_add_cylinder(Vector3(0.0, 1.30, -1.1), 0.34, 0.16, Color(0.10, 0.09, 0.10), 0.5)  # 中華鍋
	for x in [-1.15, -0.55, 0.55, 1.15]:   # 客前の丼
		_add_cylinder(Vector3(x, 1.26, -0.85), 0.16, 0.10, Color(0.86, 0.84, 0.80), 0.6)

	# ── 厨房の湯気（鍋・蒸籠から立ち上る。中華飯店の象徴）──
	_build_steam(Vector3(-2.2, 1.2, -1.1), Vector3(0.45, 0.05, 0.25), Color(1.0, 0.85, 0.6, 0.5), 16, 1.0)
	_build_steam(Vector3(0.0, 1.2, -1.1), Vector3(0.5, 0.05, 0.25), Color(1.0, 0.9, 0.7, 0.55), 18, 1.05)
	_build_steam(Vector3(2.2, 1.2, -1.1), Vector3(0.45, 0.05, 0.25), Color(1.0, 0.85, 0.6, 0.5), 16, 1.0)

	# ── 光芒（店内の暖色窓 → 手前へ、窓外ネオン → 室内へ）──
	_light_shaft(Vector3(0.0, 1.9, -3.0), Vector2(5.0, 3.2), Color(WARM.r, WARM.g, WARM.b, 0.12), 0, -10)
	_light_shaft(Vector3(-4.2, 2.6, -8.8), Vector2(2.0, 5.0), Color(NEON_MAGENTA.r, NEON_MAGENTA.g, NEON_MAGENTA.b, 0.14), 10, 6)
	_light_shaft(Vector3(4.2, 2.6, -9.0), Vector2(2.0, 5.0), Color(NEON_CYAN.r, NEON_CYAN.g, NEON_CYAN.b, 0.14), -10, 6)


## 看板の文字（3D空間に置く Label3D）。プロジェクトのドット字体を使い、
## 縁取りを付けてネオンの滲みに負けないようにする。
func _sign_text(text: String, pos: Vector3, size: float, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = load("res://assets/fonts/DotGothic16-Regular.ttf")
	l.font_size = 96
	l.pixel_size = size / 96.0
	l.modulate = col
	l.outline_size = 14
	l.outline_modulate = Color(0.08, 0.01, 0.05, 0.92)
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.shaded = false
	l.double_sided = false
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	l.position = pos
	_sub.add_child(l)


## 紫の炎モンスター1体（暗い球体＋発光コア＋点光源＋接地影）。
func _spawn_enemy(e: Vector3, scl: float = 1.0) -> Node3D:
	# パーティと同じピクセルビルボード。テクスチャは _apply_enemy_sprite で差し替え。
	var root := Node3D.new()
	root.position = e
	root.set_meta("base_scl", scl)
	_sub.add_child(root)
	var spr := _make_billboard()
	spr.name = "Spr"
	root.add_child(spr)
	# 妖しい紫の点光源（敵の存在感・ネオンに馴染む）
	var o := OmniLight3D.new()
	o.position = Vector3(0, 1.2 * scl, 0)
	o.light_color = Color(0.72, 0.25, 1.0)
	o.light_energy = 1.5
	o.omni_range = 5.0
	root.add_child(o)
	# 接地影
	var sh := _make_blob_mesh(1.3 * scl)
	sh.position = Vector3(0, 0.03, 0)
	root.add_child(sh)
	_apply_enemy_sprite(root, "goblin", false)   # 既定（strip の飾り敵にも絵が付く）
	return root


var _mob_tex_cache: Dictionary = {}

## 敵スプライトのテクスチャ解決（dungeon frames 優先→生成スプライト→goblin）。
func _enemy_tex(sprite_name: String) -> Texture2D:
	if not _mob_tex_cache.has(sprite_name):
		var t: Texture2D = null
		for p in ["res://assets/third_party/dungeon/frames/%s_idle_anim_f0.png" % sprite_name,
				"res://assets/third_party/dungeon/frames/%s_anim_f0.png" % sprite_name,
				"res://assets/generated/sprites/%s/idle_f0.png" % sprite_name,
				"res://assets/generated/sprites/%s/walk_front.png" % sprite_name]:
			if ResourceLoader.exists(p):
				t = load(p)
				break
		_mob_tex_cache[sprite_name] = t
	return _mob_tex_cache[sprite_name]


## 敵ノードへスプライトを適用：足元接地＋目標身長へスケール（ボスは大型）。
func _apply_enemy_sprite(root: Node3D, sprite_name: String, big: bool) -> void:
	var spr := root.get_node_or_null("Spr") as Sprite3D
	if spr == null:
		return
	var tex := _enemy_tex(sprite_name)
	if tex == null:
		tex = _enemy_tex("goblin")
	if tex == null:
		return
	var base := float(root.get_meta("base_scl", 1.0))
	var target_h := (2.4 if big else 1.35) * base
	if spr.texture == tex and absf(spr.position.y - target_h * 0.5) < 0.01:
		return
	spr.texture = tex
	var sc := target_h / maxf(tex.get_size().y * PIXEL_SIZE, 0.01)
	spr.scale = Vector3.ONE * sc
	spr.position = Vector3(0, target_h * 0.5, 0)


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
	m.albedo_color = Color(0.02, 0.0, 0.04, 0.78)
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
		_enemy_base.append(e)


## main から毎フレーム：sim の mob 数＆戦闘中フラグで敵の出し入れを同期。
func set_dive_state(mob_count: int, in_combat: bool, has_boss := false, sprites: Array = []) -> void:
	_combat = in_combat
	for i in _enemy_nodes.size():
		var vis := in_combat and i < mob_count
		_enemy_nodes[i].visible = vis
		if vis and i < sprites.size() and String(sprites[i]) != "":
			_apply_enemy_sprite(_enemy_nodes[i], String(sprites[i]), has_boss and i == 0)


## 戦闘のカメラシェイクを加算（被弾・スキルFXで main から）。
func punch(mag := 0.3) -> void:
	_shake = maxf(_shake, mag)


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
	# 帯を照らすキーライト。これが無いとスプライトが環境光だけになり、
	# 帯全体が「黒い枠」に見える（実際そうなっていた）。
	_neon_light(Vector3(-2.0, 1.8, 1.6), Color(0.85, 0.92, 1.0), 3.0, 6.0)   # 味方側
	_neon_light(Vector3(3.6, 1.8, 1.6), Color(1.0, 0.55, 0.85), 2.4, 6.0)    # 敵側


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
	_player_rig = _make_rig(PLAYER_ID, 0)
	_player = _make_billboard()
	_sub.add_child(_player)
	if _rim_on:
		_player_rim = _make_aura(_rim_col, false)
		_sub.add_child(_player_rim)
	if _refl_on:
		_player_refl = _make_aura(_refl_col, true)
		_sub.add_child(_player_refl)
	_player_shadow = _add_blob_shadow(_player_pos)
	# 主人公に追従する控えめなキーライト（暗い夜でも主役を読めるように）。
	if _is_dark():
		_player_light = OmniLight3D.new()
		_player_light.light_color = Color(1.0, 0.92, 0.85)
		_player_light.light_energy = 1.4
		_player_light.omni_range = 5.0
		_player_light.shadow_enabled = false
		_player_light.light_cull_mask = 0xFFFFFFFF   # 主役を読ませるライトなのでキャラも照らす
		_sub.add_child(_player_light)


# ホーム（黒猫飯店）のキャラ配置：店番（カウンター裏 z=-2.6）＋パーティ（手前の紫テーブル z≈3-4）。
const HOME_NPCS := [
	{"id": "nurse",  "pos": Vector3(-2.4, 0.0, -2.6), "flip": false},  # 店番
	{"id": "mil",    "pos": Vector3(0.0, 0.0, -2.6),  "flip": false},  # 店番（店長）
	{"id": "muu",    "pos": Vector3(2.4, 0.0, -2.6),  "flip": false},  # 店番
	{"id": "doctor", "pos": Vector3(-1.5, 0.0, 1.4),  "flip": false},  # パーティ
	{"id": "yuzuki", "pos": Vector3(1.5, 0.0, 1.4),   "flip": false},  # パーティ
]


# 潜航（戦闘）のパーティ配置：手前(z≈3〜5)に横並び。主人公は別途 _player_pos。
const DIVE_NPCS := [
	{"id": "mil",    "pos": Vector3(-2.8, 0.0, 2.2), "flip": false},
	{"id": "nurse",  "pos": Vector3(2.8, 0.0, 2.2),  "flip": false},
	{"id": "doctor", "pos": Vector3(1.5, 0.0, 3.0),  "flip": false},
]


# 横帯（フィールド）のパーティ配置：左(-X)に横並び。主人公は別途 _player_pos。
const STRIP_NPCS := [
	{"id": "mil",    "pos": Vector3(-2.5, 0.0, 0.2), "flip": false},
	{"id": "nurse",  "pos": Vector3(-1.6, 0.0, 0.6), "flip": false},
	{"id": "doctor", "pos": Vector3(-0.7, 0.0, 0.2), "flip": false},
]


func _build_npcs() -> void:
	var roster: Array = NPCS
	if stage_theme == "home":
		roster = HOME_NPCS
	elif stage_theme == "dive":
		roster = DIVE_NPCS
	elif stage_theme == "strip":
		roster = STRIP_NPCS
	_build_npc_roster(roster)


## ロスター（[{id, pos, flip}]）から NPC ビルボード一式を構築する。
func _build_npc_roster(roster: Array) -> void:
	for d in roster:
		var idx := _npc_ids.size()
		_npc_ids.append(String(d["id"]))
		var rig := _make_rig(String(d["id"]), idx)
		# 歩き回る範囲は立ち位置で決める。カウンター裏(z<-1)の店番は横長の調理台に沿って
		# 大きく動き、編成卓に集まっている面々は互いにぶつからない程度しか動かない。
		var bp: Vector3 = d["pos"]
		rig["roam_x"] = 1.15 if bp.z < -1.0 else 0.55
		rig["roam_z"] = 0.26 if bp.z < -1.0 else 0.16
		_npc_rig.append(rig)
		_npc_body.append({"y": 0.0, "vy": 0.0, "x": 0.0, "vx": 0.0})
		_npc_state.append("wait")
		# 最初の待ちをキャラごとにずらす（全員が同じ瞬間に歩き出すと群像に見えない）
		_npc_timer.append(float(rig["stagger"]) + 0.4)
		_npc_spd.append(0.0)
		_npc_cycle.append(randf())     # 歩き出しのコマ位置も揃えない
		_npc_dir.append(Vector3(1, 0, 0))
		_npc_lean.append(0.0)
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
		# リム発光／擬似反射（テーマで有効化。無効時は null を並べて添字を揃える）
		var rim: Sprite3D = null
		if _rim_on:
			rim = _make_aura(_rim_col, false)
			_sub.add_child(rim)
		_npc_rim.append(rim)
		var refl: Sprite3D = null
		if _refl_on:
			refl = _make_aura(_refl_col, true)
			_sub.add_child(refl)
		_npc_refl.append(refl)
		# 足元のブロブシャドウ（home は徘徊に追従させる）
		_npc_shadow.append(_add_blob_shadow(base_pos))


# ── ホームの経営状態反映（⑤ ゲーム状態がディオラマに見える）─────────────────

# 編成卓まわりの立ち位置（主人公 kiriko は _player_pos=中央にいるので空けてある）
const TABLE_SLOTS := [Vector3(-1.5, 0, 1.4), Vector3(1.5, 0, 1.4),
		Vector3(-0.9, 0, 2.2), Vector3(0.9, 0, 2.2), Vector3(0, 0, 2.9)]


## 経営状態をディオラマへ反映する（main.gd が HOME 表示時と朝の操作後に呼ぶ）。
##   keeper: 店番（カウンター中央に立つ）／divers: 潜行メンバー（編成卓へ）
##   renov: 解放済み改装ノード（見た目プロップを一度だけ建てる）
##   talk: 今夜会話できる子（頭上に「！」）
func set_home_state(d: Dictionary) -> void:
	if stage_theme != "home":
		return
	var keeper := String(d.get("keeper", ""))
	var divers: Array = d.get("divers", [])
	var roster: Array = []
	if keeper != "" and keeper != PLAYER_ID:
		roster.append({"id": keeper, "pos": Vector3(0, 0, -2.6), "flip": false})
	var ti := 0
	for id in divers:
		if String(id) == PLAYER_ID or ti >= TABLE_SLOTS.size():
			continue   # 主人公は _player としてすでに立っている
		roster.append({"id": id, "pos": TABLE_SLOTS[ti], "flip": false})
		ti += 1
	var ids: Array = []
	for r in roster:
		ids.append(String(r["id"]))
	if ids != _npc_ids:
		_clear_npcs()
		_build_npc_roster(roster)
	for nid in d.get("renov", []):
		if not _renov_built.has(nid):
			_renov_built[nid] = true
			_build_renov_prop(String(nid))
	_set_talk_marker(String(d.get("talk", "")))


## NPC ビルボード一式（本体・リム・反射・影）を破棄して配列を空にする。
func _clear_npcs() -> void:
	_talk_label = null   # スプライトの子なので一緒に消える
	for arr in [_npc_sprites, _npc_rim, _npc_refl, _npc_shadow]:
		for n in arr:
			if n != null and is_instance_valid(n):
				n.queue_free()
	_npc_sprites = []
	_npc_anims = []
	_npc_base = []
	_npc_pos = []
	_npc_target = []
	_npc_flip = []
	_npc_rim = []
	_npc_refl = []
	_npc_shadow = []
	_npc_ids = []
	_npc_rig = []
	_npc_body = []
	_npc_state = []
	_npc_timer = []
	_npc_spd = []
	_npc_cycle = []
	_npc_dir = []
	_npc_lean = []


## 会話できる子の頭上に金の「！」を出す（id 空なら消すだけ）。
func _set_talk_marker(id: String) -> void:
	if _talk_label != null and is_instance_valid(_talk_label):
		_talk_label.queue_free()
	_talk_label = null
	var i := _npc_ids.find(id)
	if i < 0 or i >= _npc_sprites.size():
		return
	_talk_label = Label3D.new()
	_talk_label.text = "！"
	_talk_label.font_size = 72
	_talk_label.pixel_size = 0.008
	_talk_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_talk_label.modulate = Color(1.0, 0.82, 0.4)
	_talk_label.outline_size = 16
	_talk_label.outline_modulate = Color(0.05, 0.03, 0.0, 0.9)
	_talk_label.no_depth_test = true
	_talk_label.position = Vector3(0, _sprite_half_h() + 0.55, 0)
	_npc_sprites[i].add_child(_talk_label)


## 会話マーカーの跳ね。跳び上がりは速く、落下は重力どおり加速し、着地して少し溜める
## （等速の上下だと「点滅する記号」にしか見えない）。
func _update_talk_marker() -> void:
	if _talk_label == null or not is_instance_valid(_talk_label):
		return
	var u := fposmod(_pulse * 0.85, 1.0)
	var h := 0.0
	if u < 0.30:
		h = sin(u / 0.30 * PI * 0.5)          # 蹴り上げ：初速が最大
	elif u < 0.62:
		var v := (u - 0.30) / 0.32
		h = 1.0 - v * v                        # 落下：二次で加速
	_talk_label.position.y = _sprite_half_h() + 0.55 + h * 0.20


## 改装ノードの見た目プロップ。解放時に一度だけ建てる（改装は不可逆）。
func _build_renov_prop(id: String) -> void:
	match id:
		"sign1":   # ネオン看板：店先両脇に追加のタテ看板＋灯り
			_emissive_box(Vector3(3.9, 3.2, -2.0), Vector3(0.4, 1.6, 0.18), Color(0.2, 0.9, 1.0), 3.0)
			_emissive_box(Vector3(-3.9, 3.2, -2.0), Vector3(0.4, 1.6, 0.18), Color(1.0, 0.32, 0.72), 3.0)
			_neon_light(Vector3(3.9, 3.0, -1.6), Color(0.2, 0.9, 1.0), 2.2, 5.0)
		"sign2":   # 増築：2階の窓明かり（店が縦に育つ）
			for x in [-2.4, 0.0, 2.4]:
				_emissive_box(Vector3(x, 4.6, -3.4), Vector3(1.2, 0.7, 0.15), Color(1.0, 0.66, 0.34), 1.6)
		"kitchen": # 厨房拡張：湯気の列が増え、鍋あかりが強くなる
			_build_steam(Vector3(-1.1, 1.2, -1.1), Vector3(0.4, 0.05, 0.25), Color(1.0, 0.88, 0.65, 0.5), 14, 1.1)
			_build_steam(Vector3(1.1, 1.2, -1.1), Vector3(0.4, 0.05, 0.25), Color(1.0, 0.88, 0.65, 0.5), 14, 1.1)
			_neon_light(Vector3(0.0, 1.6, -1.1), Color(1.0, 0.6, 0.3), 1.6, 4.0)
		"rest":    # 安息：店先の火鉢（閉店中も温かい）
			_add_box(Vector3(4.6, 0.25, 1.6), Vector3(0.8, 0.5, 0.8), Color(0.15, 0.10, 0.08), 0.7)
			_emissive_box(Vector3(4.6, 0.55, 1.6), Vector3(0.5, 0.12, 0.5), Color(1.0, 0.45, 0.15), 2.2)
			_neon_light(Vector3(4.6, 1.0, 1.6), Color(1.0, 0.5, 0.2), 1.8, 3.5)
		"gold3":   # 老舗の貫禄：金の扁額
			_emissive_box(Vector3(0.0, 4.15, -2.6), Vector3(2.6, 0.5, 0.15), Color(1.0, 0.82, 0.4), 2.4)
		"awaken":  # 覚醒：編成卓から立ちのぼる紫の光柱
			_light_shaft(Vector3(0.0, 1.6, 2.6), Vector2(2.2, 3.4), Color(0.65, 0.3, 1.0, 0.16), 0, 0)


## 足元の楕円ソフトシャドウ。ビルボードは光源視点で薄くなり落ち影が不安定なため、
## HD-2D の定番どおり板の影テクスチャを地面に寝かせて確実に接地させる。
var _blob_tex: Texture2D = null

func _add_blob_shadow(pos: Vector3, w: float = 1.05) -> MeshInstance3D:
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
	spr.layers = CHAR_LAYER_MASK   # 装飾ライトの cull mask から外れるレイヤー
	spr.double_sided = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD  # 影を落とし、輪郭をくっきり
	spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return spr


## リム発光／擬似反射に使う半透明ビルボード（Y固定・非影・常時手前）。
## Sprite3D は加算ブレンドを持たないので、低アルファのアルファブレンドで淡く乗せる。
func _make_aura(tint: Color, flip_v: bool) -> Sprite3D:
	var s := Sprite3D.new()
	s.pixel_size = PIXEL_SIZE
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.shaded = false
	s.double_sided = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED  # 半透明（DISCARD だとアルファが効かない）
	s.modulate = tint
	s.flip_v = flip_v
	s.no_depth_test = true
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return s


## 本体ビルボードに rim/refl ビルボードのテクスチャ・フレーム・位置を毎フレーム同期。
## refl は足元(y=0)を軸に上下ミラー（flip_v）して濡れ床の反射に見せる。
func _sync_aura(main: Sprite3D, aura: Sprite3D, is_refl: bool) -> void:
	if aura == null:
		return
	aura.visible = main.visible
	aura.texture = main.texture
	aura.hframes = main.hframes
	aura.vframes = main.vframes
	aura.frame = main.frame
	aura.flip_h = main.flip_h
	if is_refl:
		aura.pixel_size = main.pixel_size
		aura.position = Vector3(main.position.x, -main.position.y + 0.04, main.position.z)
	else:
		aura.pixel_size = main.pixel_size * 1.05   # わずかに大きくして縁に色を滲ませる
		aura.position = main.position


func _sprite_half_h() -> float:
	# 144x192 の標準フレーム前提。足元を地面に合わせるための中心オフセット。
	return 192.0 * PIXEL_SIZE * 0.5


# ────────────────────────────────────────────────────────
# キャラの手続きモーション
#   立っているだけでも「呼吸・重心の左右移動・遅れて追いつく体」が見えること、
#   歩きは「踏み込みで沈み、抜きで浮く」重さがあること、が狙い。
#   周期・振幅・位相は全部キャラごとに変える（全員同じ sin で揺れると人形に見える）。
# ────────────────────────────────────────────────────────

## キャラ固有のモーション定数。id から決定的に作るので実行ごとに変わらない。
## 周期どうしが整数比にならない範囲を選び、時間が経っても全員が揃わないようにする。
func _make_rig(id: String, idx: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = absi(hash(id)) + idx * 7919
	return {
		"breath_w": TAU / r.randf_range(3.3, 4.9),   # 呼吸：3.3〜4.9 秒で1回
		"breath_a": r.randf_range(0.020, 0.038),
		"breath_ph": r.randf_range(0.0, TAU),
		"sway_w": TAU / r.randf_range(6.1, 9.7),     # 重心の左右移動：呼吸よりずっと遅い
		"sway_a": r.randf_range(0.018, 0.040),
		"sway_ph": r.randf_range(0.0, TAU),
		"step_len": r.randf_range(0.60, 0.78),       # 歩幅（m）。1サイクル＝2歩ぶん
		"walk_a": r.randf_range(0.054, 0.078),       # 踏み込みの上下動
		"speed": r.randf_range(0.70, 1.02),          # 巡航速度（m/s）
		"wait_min": r.randf_range(1.8, 3.4),
		"wait_max": r.randf_range(5.0, 9.0),
		"turn_t": r.randf_range(0.22, 0.36),         # 向き変えの予備動作の尺
		"stagger": r.randf_range(0.0, 3.5),          # 最初の待ち（全員同時に歩き出さない）
	}


## 待機の呼吸。等速の sin ではなく位相変調で「すっと吸って、長く吐く」非対称にする。
func _breath(rig: Dictionary, t: float) -> float:
	var p: float = t * float(rig["breath_w"]) + float(rig["breath_ph"])
	return sin(p + 0.55 * sin(p))


## 待機の重心移動（左右）。周期の違う2波を重ねて往復パターンを読ませない。
func _sway(rig: Dictionary, t: float) -> float:
	var p: float = t * float(rig["sway_w"]) + float(rig["sway_ph"])
	return sin(p) * 0.78 + sin(p * 0.47 + 1.3) * 0.22


## 歩行の上下動。cycle は 1.0 で 2 歩ぶん。
## 接地(0.0)で最下 → 抜き(0.45)で最上 → 落下は二次で加速して踏み込む、という非対称カーブ。
## 接地直後には膝が曲がるぶんの沈み込みを足す（これが無いと「浮いて滑る」歩きになる）。
func _foot_bob(cycle: float) -> float:
	var u := fposmod(cycle * 2.0, 1.0)   # 1歩ぶんに正規化
	var h := 0.0
	if u < 0.45:
		h = sin(u / 0.45 * PI * 0.5)     # 上がる側：初速が速く、頂点で減速
	else:
		var v := (u - 0.45) / 0.55
		h = 1.0 - v * v                  # 落ちる側：重力どおり加速して着地
	if u < 0.14:
		h -= 0.34 * (1.0 - u / 0.14)     # 着地の沈み込み（踏み込みの重さ）
	return h


## バネで体を目標へ追従させる（重心の遅れ・停止時の余韻）。
## 直に代入すると「値がそのまま画になる」＝機械的に見えるので、必ずここを通す。
## dt は 1/30 で頭打ちにする（重い1フレームでバネが発散しないように）。
func _spring(body: Dictionary, key: String, vkey: String, target: float,
		stiff: float, damp_r: float, delta: float) -> float:
	var dt := minf(delta, 1.0 / 30.0)
	var v: float = float(body[vkey])
	var x: float = float(body[key])
	v += ((target - x) * stiff - v * damp_r) * dt
	x += v * dt
	body[vkey] = v
	body[key] = x
	return x


## 接地影。本体の上下動ぶん動かさない（動かすと接地が外れて宙に浮く）。
## 代わりに浮いたぶん縮めて薄くし、沈み込んだぶん広げて濃くする＝影が高さを語る。
func _place_shadow(mi: MeshInstance3D, ground: Vector3, lift: float) -> void:
	if mi == null or not is_instance_valid(mi):
		return
	mi.position = ground + Vector3(0, 0.03, 0)
	var k := clampf(1.0 - lift * 2.6, 0.60, 1.18)
	mi.scale = Vector3(k, 1.0, k)
	var m := mi.material_override as StandardMaterial3D
	if m != null:
		var c := m.albedo_color
		m.albedo_color = Color(c.r, c.g, c.b, clampf(0.78 * k, 0.30, 0.92))


## フレームレート非依存の減衰率。delta が変わっても同じ追従感になる。
func _damp(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * minf(delta, 0.1))


## home の徘徊。「目的地へ等速で寄り、着いた瞬間に止まる」のをやめ、
##   待つ → 向き直る（予備動作）→ 加速して歩く → 減速して着地の余韻
## の4状態にする。最初の待ちを rig["stagger"] でずらすので全員同時には歩き出さない。
func _tick_wander(i: int, delta: float) -> void:
	var rig: Dictionary = _npc_rig[i]
	var pos: Vector3 = _npc_pos[i]
	var spd: float = float(_npc_spd[i])
	var timer: float = float(_npc_timer[i]) - delta
	match String(_npc_state[i]):
		"wait":
			_npc_spd[i] = move_toward(spd, 0.0, 6.0 * delta)
			_npc_lean[i] = move_toward(float(_npc_lean[i]), 0.0, 3.0 * delta)
			if timer <= 0.0:
				# 次の目的地は「カウンターに沿った横移動」を主にする。
				# 前後歩きのスプライトは1枚しか無く、奥/手前へ歩かせると絵が止まったまま
				# 床を滑る（＝一番目につく破綻）ので、横歩きの連番が使える向きへ寄せる。
				var b: Vector3 = _npc_base[i]
				var rx: float = float(rig["roam_x"])
				var rz: float = float(rig["roam_z"])
				var nt := b + Vector3(randf_range(-rx, rx), 0.0, randf_range(-rz, rz))
				if (nt - pos).length() < rx * 0.45:
					# 近すぎる目的地はその場の小刻みな揺れにしか見えないので、反対側へ振る
					nt = b + Vector3(-signf(pos.x - b.x + 0.001) * randf_range(rx * 0.55, rx), 0.0, nt.z - b.z)
				_npc_target[i] = nt
				_npc_state[i] = "turn"
				_npc_timer[i] = float(rig["turn_t"])
			else:
				_npc_timer[i] = timer
		"turn":
			# 予備動作：進行方向へ体を先に振ってから歩き出す。向きの反転は弧の頂点で行う
			# （足が先に出て顔が後から向く＝予備動作の無い切り替えを避ける）。
			var tt: float = maxf(float(rig["turn_t"]), 0.01)
			var p := clampf(1.0 - timer / tt, 0.0, 1.0)
			var d: Vector3 = (_npc_target[i] as Vector3) - pos
			d.y = 0.0
			var nd := d.normalized() if d.length() > 0.01 else Vector3(1, 0, 0)
			_npc_lean[i] = sin(p * PI) * signf(nd.x if absf(nd.x) > 0.001 else 1.0)
			_npc_spd[i] = move_toward(spd, 0.0, 8.0 * delta)
			if p >= 0.5:
				_npc_dir[i] = nd
			if timer <= 0.0:
				_npc_state[i] = "walk"
				_npc_timer[i] = 8.0     # 保険：詰まっても8秒で切り上げる
			else:
				_npc_timer[i] = timer
		"walk":
			var to: Vector3 = (_npc_target[i] as Vector3) - pos
			to.y = 0.0
			var dist := to.length()
			var dir := to.normalized() if dist > 0.001 else Vector3(_npc_dir[i])
			_npc_dir[i] = dir
			# 到着 0.6m 手前から落としていく（着いた瞬間に止まると人形が消えたように見える）
			var cruise: float = float(rig["speed"])
			var want := cruise * clampf(dist / 0.6, 0.20, 1.0)
			_npc_spd[i] = move_toward(spd, want, (2.6 if want > spd else 3.6) * delta)
			_npc_pos[i] = pos + dir * float(_npc_spd[i]) * delta
			_npc_lean[i] = move_toward(float(_npc_lean[i]), 0.0, 2.5 * delta)
			if dist < 0.10 or timer <= 0.0:
				_npc_state[i] = "settle"
				_npc_timer[i] = 0.28
			else:
				_npc_timer[i] = timer
		_:   # "settle" 着地の余韻。速度をゼロへ落としきってから待機に戻す
			_npc_spd[i] = move_toward(spd, 0.0, 4.5 * delta)
			_npc_pos[i] = pos + Vector3(_npc_dir[i]) * float(_npc_spd[i]) * delta
			_npc_lean[i] = move_toward(float(_npc_lean[i]), 0.0, 3.0 * delta)
			if timer <= 0.0:
				_npc_state[i] = "wait"
				_npc_timer[i] = randf_range(float(rig["wait_min"]), float(rig["wait_max"]))
			else:
				_npc_timer[i] = timer


func _process(delta: float) -> void:
	_pulse += delta

	# ── 入力（WASD / 矢印）──
	# home はカメラ注視点のパン、それ以外はプレイヤー移動。
	var iv := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): iv.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): iv.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): iv.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): iv.x += 1.0
	# home：WASD で注視点パン（カメラ方向相対）
	if stage_theme == "home" and iv != Vector2.ZERO and _cam_target_override != null:
		var basis := Basis(Vector3.UP, _cam_yaw)
		var fwd   := basis * Vector3(0, 0, -1)
		var right  := basis * Vector3(1, 0, 0)
		var move   := (fwd * -iv.y + right * iv.x).normalized() * 5.0 * delta
		_cam_target_override = (_cam_target_override as Vector3) + move
		var ct := _cam_target_override as Vector3
		_cam_target_override = Vector3(clampf(ct.x, -10.0, 10.0), ct.y, clampf(ct.z, -12.0, 8.0))
		iv = Vector2.ZERO  # プレイヤー移動には使わない
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

	# ── プレイヤー：速度に慣性を入れる（歩き出しと止まりぎわを線形にしない）──
	var p_want := MOVE_SPEED if moving else 0.0
	# 踏み出しは速く、止まるのは少し粘る（体重が乗っている感じ）
	_player_spd = move_toward(_player_spd, p_want, (26.0 if moving else 15.0) * delta)
	var p_walking := _player_spd > 0.08 or _force_moving
	# 歩行サイクルは「進んだ距離 ÷ 歩幅」で進める。速度が上がれば歩調も上がり、
	# 止まればコマも止まる。時計で割るとその場足踏みになる（従来の 140ms 固定がそれ）。
	var p_step: float = float(_player_rig.get("step_len", 0.7))
	var p_ref := _player_spd if _player_spd > 0.08 else (MOVE_SPEED * 0.55 if _force_moving else 0.0)
	_player_cycle += p_ref * delta / maxf(p_step * 2.0, 0.1)

	var p_used := false
	if p_walking and player_move != Vector3.ZERO:
		var dr := _walk_dir(player_move)
		_player_flip = bool(dr[1])
		var anim_key := "walk" if dr[0] == "side" else "walk_" + String(dr[0])
		var w := _walk_texture(PLAYER_ID, anim_key, _player_cycle)
		if w["tex"] != null:
			_apply_walk(_player, w)
			_player.flip_h = _player_flip
			p_used = true
	if not p_used:
		_reset_billboard(_player)
		_player_anim.speed_scale = 1.0 + _player_spd / MOVE_SPEED * 0.6
		_player_anim.update_params(1.0 if p_walking else 0.0)
		_player_anim.tick(delta)
		_player.texture = _tex(_player_anim.current_path())
		_player.flip_h = _player_flip
	# 目標の体の高さ／左右ぶれ：歩いていれば踏み込み、止まっていれば呼吸＋重心移動
	var p_run := clampf(_player_spd / MOVE_SPEED, 0.0, 1.0)
	var p_ty := lerpf(_breath(_player_rig, _pulse) * float(_player_rig["breath_a"]),
			_foot_bob(_player_cycle) * float(_player_rig["walk_a"]), p_run)
	var p_tx := _sway(_player_rig, _pulse) * float(_player_rig["sway_a"]) * (1.0 - p_run)
	# バネを通して「体が遅れて追いつく」ようにする（止まった瞬間に一度沈んで戻る）
	var p_y := _spring(_player_body, "y", "vy", p_ty, 150.0, 16.0, delta)
	var p_x := _spring(_player_body, "x", "vx", p_tx, 60.0, 12.0, delta)
	_player.position = _player_pos + Vector3(p_x, _sprite_half_h() + p_y, 0)
	if _player_light != null:
		_player_light.position = _player_pos + Vector3(0, 2.2, 0.8)
	_place_shadow(_player_shadow, _player_pos, p_y)

	# ── NPC：home は基準位置の周りを徘徊（待つ→向き直る→歩く→止まる）、それ以外は待機 ──
	var wander := stage_theme == "home"
	for i in _npc_sprites.size():
		var rig: Dictionary = _npc_rig[i]
		var nmove: Vector3 = _npc_dir[i]
		if wander:
			_tick_wander(i, delta)
			nmove = _npc_dir[i]
		var spd: float = float(_npc_spd[i])
		var nmoving := spd > 0.05
		# 歩幅で割ってサイクルを進める（速度に歩調が連動する）
		_npc_cycle[i] = float(_npc_cycle[i]) + spd * delta / maxf(float(rig["step_len"]) * 2.0, 0.1)
		var run := clampf(spd / maxf(float(rig["speed"]), 0.01), 0.0, 1.0)
		# 目標オフセット：歩行の踏み込み ⇄ 待機の呼吸をブレンド。
		# 予備動作中(lean≠0)は進行方向へ体を先に傾ける＝「行くぞ」が読める。
		var ty := lerpf(_breath(rig, _pulse) * float(rig["breath_a"]),
				_foot_bob(float(_npc_cycle[i])) * float(rig["walk_a"]), run)
		var lean: float = float(_npc_lean[i])
		ty -= absf(lean) * 0.012          # 予備動作は少し腰を落とす
		var tx := _sway(rig, _pulse) * float(rig["sway_a"]) * (1.0 - run) + lean * 0.055
		var body: Dictionary = _npc_body[i]
		var by := _spring(body, "y", "vy", ty, 150.0, 16.0, delta)
		var bx := _spring(body, "x", "vx", tx, 60.0, 12.0, delta)
		var ground: Vector3 = _npc_pos[i]
		_npc_sprites[i].position = ground + Vector3(bx, _sprite_half_h() + by, 0)
		if i < _npc_shadow.size():
			_place_shadow(_npc_shadow[i], ground, by)
		if nmoving and nmove != Vector3.ZERO:
			var dr := _walk_dir(nmove)
			_npc_sprites[i].flip_h = bool(dr[1])
			var anim_key := "walk" if dr[0] == "side" else "walk_" + String(dr[0])
			var w := _walk_texture(_npc_anims[i].char_id, anim_key, float(_npc_cycle[i]))
			if w["tex"] != null:
				_apply_walk(_npc_sprites[i], w)
				continue
		_reset_billboard(_npc_sprites[i])
		_npc_anims[i].speed_scale = 1.0 + run * 0.6
		_npc_anims[i].update_params(1.0 if nmoving else 0.0)  # テクスチャ無しは run、停止は idle
		_npc_anims[i].tick(delta)
		_npc_sprites[i].texture = _tex(_npc_anims[i].current_path())

	# ── リム発光／擬似反射を本体ビルボードへ同期（テクスチャ/フレーム/位置）──
	_sync_aura(_player, _player_rim, false)
	_sync_aura(_player, _player_refl, true)
	for i in _npc_sprites.size():
		_sync_aura(_npc_sprites[i], _npc_rim[i] if i < _npc_rim.size() else null, false)
		_sync_aura(_npc_sprites[i], _npc_refl[i] if i < _npc_refl.size() else null, true)

	# ── 環境（提灯の振り子・ネオンの明滅・会話マーカー）──
	_update_lanterns()
	_update_flickers()
	_update_talk_marker()

	_update_camera(false)


## カメラをプレイヤーの斜め後ろ上方に追従させる（HD-2D の見下ろしアングル）。
## ヨー（Q/E）とズーム（R/F）を補間し、プレイヤーの周りを周回する。
func _update_camera(instant: bool) -> void:
	var delta := get_process_delta_time()
	var height := _cam_height
	if instant:
		_cam_yaw = _cam_yaw_target
		_cam_dist = _cam_dist_target
	elif _intro_active:
		# 導入のズームイン。lerp の指数減衰は「最初だけ速くて延々止まらない」ので、
		# 尺を決めた ease-out で寄せ、寄りきる手前でわずかに行き過ぎて戻す（カメラの余韻）。
		_intro_t += delta
		var u := clampf(_intro_t / INTRO_TIME, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - u, 3.0)
		e += sin(u * PI) * u * u * 0.055
		_cam_dist = lerpf(_intro_from, _cam_dist_target, e)
		height = lerpf(_cam_height * 1.5, _cam_height, e)
		_cam_yaw = lerp_angle(_cam_yaw, _cam_yaw_target, _damp(7.0, delta))
		if u >= 1.0:
			_intro_active = false
	else:
		# フレームレート非依存の減衰（60fps でも 30fps でも同じ寄り方になる）
		_cam_yaw = lerp_angle(_cam_yaw, _cam_yaw_target, _damp(7.5, delta))
		_cam_dist = lerpf(_cam_dist, _cam_dist_target, _damp(4.5, delta))
	# 注視点：通常はプレイヤー追従、home は固定注視点（据置構図）
	var look: Vector3 = _cam_target_override if _cam_target_override != null else _player_pos
	var offset := Basis(Vector3.UP, _cam_yaw) * Vector3(0, height, _cam_dist)
	var target := look + offset
	# 追従は「揺れを含まない位置」に対して行う。_cam.position（揺れ込み）を毎フレーム
	# lerp の起点にすると、揺れが減衰しきらずに次のフレームへ積み上がって暴れる。
	if instant or _intro_active:
		_cam_base = target           # 導入中は曲線をそのまま出す（二重に鈍らせない）
	else:
		_cam_base = _cam_base.lerp(target, _damp(6.5, delta))
	_cam.position = _cam_base
	# 据置構図の微細な揺れ＝「カメラを構えている人の呼吸」。
	# 周期の違う波を重ね、往復していると気づかれない程度（画面上 2〜4px）に留める。
	var look_off := Vector3.ZERO
	if not instant and _cam_target_override != null:
		var s := clampf(_intro_t / INTRO_TIME, 0.0, 1.0)   # 導入が済むほど強く効かせる
		_cam.position += Vector3(
			(sin(_pulse * 0.37) * 0.026 + sin(_pulse * 0.83 + 1.9) * 0.010),
			(sin(_pulse * 0.29 + 0.7) * 0.020 + sin(_pulse * 0.61 + 2.4) * 0.008),
			sin(_pulse * 0.23 + 2.1) * 0.016) * s
		look_off = Vector3(sin(_pulse * 0.19 + 1.2) * 0.016, sin(_pulse * 0.31) * 0.012, 0.0) * s
	# カメラシェイク（punch() 加算・線形減衰）
	if _shake > 0.004:
		_cam.position += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * _shake * 0.16
		_shake = maxf(0.0, _shake - delta * 1.4)
	_cam.look_at(look + look_off + Vector3(0, 1.0, 0), Vector3.UP)
	# 戦闘中：敵が手前へ踏み込む。踏み込みは速く、戻りは遅い（等速の往復にしない）
	if _combat:
		for i in _enemy_nodes.size():
			if _enemy_nodes[i].visible and i < _enemy_base.size():
				var u2 := fposmod(_pulse * 0.62 + i * 0.37, 1.0)
				var lunge := (1.0 - pow(1.0 - u2 / 0.22, 2.0)) if u2 < 0.22 else \
						maxf(0.0, 1.0 - (u2 - 0.22) / 0.55)
				(_enemy_nodes[i] as Node3D).position = (_enemy_base[i] as Vector3) + Vector3(0, 0, lunge * 0.4)


## 画面端を暗く落とすヴィネットを 3D 描画の上に重ねる。
## 全画面ポスト処理（擬似ティルトシフト DoF ＋ ヴィネット）。
## 3D を描く SubViewportContainer の上に重ね、hint_screen_texture で読んでぼかす。
func _build_vignette() -> void:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/ui/hd2d_post.gdshader")
	# テーマ別に焦点帯を調整：home は主役(カウンター)が画面中央やや上、
	# strip(横帯)は左右対峙で中央、それ以外は見下ろし構図で中央やや下。
	var focus := 0.52
	var fsize := 0.16
	var blur := 3.4
	if stage_theme == "home":
		focus = 0.46
		fsize = 0.18
	elif stage_theme == "strip":
		focus = 0.5
		fsize = 0.22
		blur = 1.8
	mat.set_shader_parameter("focus_center", focus)
	mat.set_shader_parameter("focus_size", fsize)
	mat.set_shader_parameter("blur_strength", blur)
	mat.set_shader_parameter("vig_strength", 0.5)
	mat.set_shader_parameter("vig_radius", 0.92)
	rect.material = mat
	add_child(rect)


## テクスチャ読込（欠番はフォールバック）。
## フォールバック先は idle_f1。idle_f0 は他コマと別絵（2頭身のちび絵＝UIの顔素材）なので、
## ここに落ちると等身の違うキャラが立つ。
func _tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
		if t == null:
			var fb := SPRITE_DIR + PLAYER_ID + "/idle_f1.png"
			t = load(fb) if ResourceLoader.exists(fb) else null
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


## 指定アニメ（walk / walk_front / walk_back）の現フレーム {tex, ph}。連番が在れば返す。
## 無ければ tex=null（呼び出し側が run/idle にフォールバック）。
## ※既存の walk_front.png（別解像度シート）は使わない（_f<n> 連番のみ）。
##
## コマ送りは時計ではなく cycle（＝進んだ距離 ÷ 歩幅）で決める。
## 時計で割ると (1) 速度が変わってもコマ速度が変わらない (2) 全キャラが同じコマになり
## 行進しているように見える、の2つが同時に起きる（従来の 140ms 固定がまさにそれ）。
func _walk_texture(id: String, anim: String, cycle: float) -> Dictionary:
	var n := _walk_count(id, anim)
	if n == 0:
		return {"tex": null}
	var fr := int(fposmod(cycle, 1.0) * float(n)) % n
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
