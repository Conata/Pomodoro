class_name ChibiAnim
## Unityちゃんピクセルアートパック Vol.2 の設計思想を Godot に移植。
##
## Unity の構造対応:
##   Base Animator Controller  → このクラスのステートマシン（全キャラ共通）
##   Animator Override Controller → char_id でスプライトフォルダを切り替え（キャラ固有クリップ）
##   スクリプト（StandardActionsSceneSpriteController 等）→ 呼び出し元が update_params() を叩くだけ
##
## 使い方:
##   var anim := ChibiAnim.new("mil")
##   # 毎フレーム: アニメーターにパラメーターを渡す（Unity の SetFloat/SetBool に相当）
##   anim.update_params(speed=1.0, in_combat=false, is_hurt=false, is_dead=false)
##   anim.tick(delta, pulse)
##   # 描画時: 現在フレームのテクスチャパスを取得
##   var path := anim.current_path()

# ────────────────────────────────────────────────────────
# アニメーション定義（Base Controller のクリップスロット相当）
# Unity の "Speed" "IsCrouch" 等のパラメーター名に対応するステート遷移条件
# ────────────────────────────────────────────────────────

## 全ステートの定義（優先度順・先が高優先）
## anim_name は assets/generated/sprites/<char_id>/<anim_name>_f<n>.png のキー
const STATES: Array[Dictionary] = [
	# 高優先（割り込み可）
	{"name": "die",         "loop": false, "fps": 4.0},
	{"name": "hurt",        "loop": false, "fps": 8.0},
	{"name": "attack",      "loop": false, "fps": 8.0},
	{"name": "jump_attack", "loop": false, "fps": 8.0},
	# 移動系
	{"name": "dash",        "loop": false, "fps": 8.0},
	{"name": "double_jump", "loop": false, "fps": 8.0},
	{"name": "jump",        "loop": true,  "fps": 4.0},
	{"name": "wall_slide",  "loop": true,  "fps": 4.0},
	{"name": "climb",       "loop": true,  "fps": 6.0},
	{"name": "run",         "loop": true,  "fps": 8.0},
	# スキル
	{"name": "skill1",      "loop": false, "fps": 8.0},
	{"name": "skill2",      "loop": false, "fps": 8.0},
	{"name": "skill3",      "loop": false, "fps": 8.0},
	{"name": "acquire",     "loop": false, "fps": 8.0},
	# ベース
	{"name": "idle",        "loop": true,  "fps": 4.0},
]

# ────────────────────────────────────────────────────────
# パラメーター（Unity の Animator Parameters 相当）
# ────────────────────────────────────────────────────────
var speed: float = 0.0          # 水平移動速度（0=停止 1=歩行 2=走行）
var in_combat: bool = false      # 戦闘中（attack に遷移）
var is_hurt: bool = false        # 被弾（hurt に割り込み）
var is_dead: bool = false        # 死亡（die に割り込み・最優先）
var is_airborne: bool = false    # 空中（jump/double_jump/wall_slide）
var is_double_jump: bool = false # 二段ジャンプ中
var is_wall_slide: bool = false  # 壁ずり
var is_climbing: bool = false    # 梯子昇降
var is_dashing: bool = false     # ダッシュ
var skill_index: int = 0         # 1/2/3 でスキル発動、0=なし
var is_acquiring: bool = false   # アイテム取得

# ────────────────────────────────────────────────────────
# 内部状態
# ────────────────────────────────────────────────────────
var char_id: String = ""
var _state: String = "idle"
var _frame: int = 0
var _elapsed: float = 0.0
# インスタンスローカルのフレーム数キャッシュ。
# static にするとエディタセッション内で旧値が残り "idle f9" のようなズレが起きるため非 static。
var _cache: Dictionary = {}


func _init(id: String) -> void:
	char_id = id
	_state = "idle"


# ────────────────────────────────────────────────────────
# update_params() — Unity の SetFloat/SetBool 群に相当
# 呼び出し元はパラメーターを渡すだけ。どのステートに遷移するかはこのクラスが決める。
# ────────────────────────────────────────────────────────
func update_params(
	p_speed: float = 0.0,
	p_in_combat: bool = false,
	p_is_hurt: bool = false,
	p_is_dead: bool = false,
	p_is_airborne: bool = false,
	p_is_double_jump: bool = false,
	p_is_wall_slide: bool = false,
	p_is_climbing: bool = false,
	p_is_dashing: bool = false,
	p_skill: int = 0,
	p_is_acquiring: bool = false,
) -> void:
	speed = p_speed
	in_combat = p_in_combat
	is_hurt = p_is_hurt
	is_dead = p_is_dead
	is_airborne = p_is_airborne
	is_double_jump = p_is_double_jump
	is_wall_slide = p_is_wall_slide
	is_climbing = p_is_climbing
	is_dashing = p_is_dashing
	skill_index = p_skill
	is_acquiring = p_is_acquiring


# ────────────────────────────────────────────────────────
# tick() — Unity の Update() 内でパラメーターを元に SetXxx を呼ぶ処理 + ステートマシン更新
# ────────────────────────────────────────────────────────
func tick(delta: float) -> void:
	var next := _resolve_state()
	if next != _state:
		_state = next
		_frame = 0
		_elapsed = 0.0

	var fps := _state_fps(_state)
	_elapsed += delta
	var total := _get_frame_count(char_id, _state)
	if total > 0:
		_frame = int(_elapsed * fps) % total if _state_loop(_state) else \
				mini(int(_elapsed * fps), total - 1)


# ────────────────────────────────────────────────────────
# current_path() — 描画側が使うテクスチャパス
# Unity の Animator.GetCurrentAnimatorStateInfo() 的な役割
# ────────────────────────────────────────────────────────
func current_path() -> String:
	return "res://assets/generated/sprites/%s/%s_f%d.png" % [char_id, _state, _frame]


## 現在のアニメーション状態名（デバッグ用）
func current_state() -> String:
	return _state


## アニメーションが終端フレームに達しているか（非ループステートの終了判定）
func is_finished() -> bool:
	if _state_loop(_state):
		return false
	var total := _get_frame_count(char_id, _state)
	if total <= 0:
		return true
	return int(_elapsed * _state_fps(_state)) >= total


# ────────────────────────────────────────────────────────
# 内部ヘルパー
# ────────────────────────────────────────────────────────

## ステートマシン遷移ロジック（Unity の Transition Conditions 相当）
## 優先度: die > hurt > skill > attack > dash > jump系 > climb > run > idle
func _resolve_state() -> String:
	# 非ループ中は割り込み条件（die/hurt のみ）がなければ完了まで維持
	if not _state_loop(_state) and not is_finished():
		if _state != "die" and _state != "hurt":
			# 高優先割り込み
			if is_dead:
				return "die"
			if is_hurt:
				return "hurt"
		return _state  # 現在ステートを継続

	# 優先度順に遷移先を決定
	if is_dead:
		return "die"
	if is_hurt:
		return "hurt"
	if skill_index == 1 and _has_anim("skill1"):
		return "skill1"
	if skill_index == 2 and _has_anim("skill2"):
		return "skill2"
	if skill_index == 3 and _has_anim("skill3"):
		return "skill3"
	if is_acquiring and _has_anim("acquire"):
		return "acquire"
	if in_combat:
		if is_airborne and _has_anim("jump_attack"):
			return "jump_attack"
		return "attack"
	if is_dashing and _has_anim("dash"):
		return "dash"
	if is_double_jump and _has_anim("double_jump"):
		return "double_jump"
	if is_wall_slide and _has_anim("wall_slide"):
		return "wall_slide"
	if is_airborne and _has_anim("jump"):
		return "jump"
	if is_climbing and _has_anim("climb"):
		return "climb"
	if speed > 0.1:
		return "run"
	return "idle"


func _has_anim(anim: String) -> bool:
	return _get_frame_count(char_id, anim) > 0


func _get_frame_count(id: String, anim: String) -> int:
	var key := id + "/" + anim
	if _cache.has(key):
		return _cache[key]
	var n := 0
	while ResourceLoader.exists("res://assets/generated/sprites/%s/%s_f%d.png" % [id, anim, n]):
		n += 1
	_cache[key] = n
	return n


func _state_fps(s: String) -> float:
	for st: Dictionary in STATES:
		if st["name"] == s:
			return float(st["fps"])
	return 6.0


func _state_loop(s: String) -> bool:
	for st: Dictionary in STATES:
		if st["name"] == s:
			return bool(st["loop"])
	return true
