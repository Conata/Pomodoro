extends SceneTree
## 一時：潜航画面の3局面（道中・交戦・ボス）を撮る。合成データを直接流し込む。

const OUT := "res://_out/bench/"

var scr: Control
var stage: Control
var ov: Control
var _f := 0
var _phase := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	scr = load("res://dive_screen.tscn").instantiate()
	get_root().add_child(scr)
	stage = scr.get_node("Stage")
	ov = scr.get_node("Overlay")


func _party() -> Array:
	return [
		{"id": "mil", "hp": 320.0, "mhp": 420.0, "ready": 2, "slots": 3},
		{"id": "nurse", "hp": 280.0, "mhp": 360.0, "ready": 1, "slots": 2},
		{"id": "kiriko", "hp": 300.0, "mhp": 400.0, "ready": 3, "slots": 3},
		{"id": "doctor", "hp": 210.0, "mhp": 450.0, "ready": 0, "slots": 2},
	]


func _ov_data(fl: String, remain: int, boss := "") -> Dictionary:
	return {
		"party": [
			{"name": "ミル", "hp": 320, "mhp": 420, "sp": 80, "msp": 100},
			{"name": "ナース", "hp": 280, "mhp": 360, "sp": 60, "msp": 100},
			{"name": "キリコ", "hp": 300, "mhp": 400, "sp": 100, "msp": 100},
			{"name": "ドクター", "hp": 210, "mhp": 450, "sp": 70, "msp": 100},
		],
		"player_lv": fl, "player_hp": 0.72, "player_exp": 0.44,
		"quest_text": "仕入れ中  残り %d秒" % remain,
		"speed_mult": 1, "manual_skill": false, "skill_label": "",
		"boss_name": boss,
	}


func _setup(phase: int) -> void:
	match phase:
		0:  # 道中（B1F・序盤）
			stage.set_view({"dist": 130.0, "in_combat": false, "party": _party(),
					"mobs": [], "gold_gain": 42, "diff": 0})
			ov.set_data(_ov_data("B0", 1420))
		1:  # 交戦（B2F・中盤）
			stage.set_view({"dist": 640.0, "in_combat": true, "party": _party(),
					"mobs": [{"sprite": "mob_spider", "hp": 120.0, "boss": false},
							{"sprite": "mob_drone", "hp": 90.0, "boss": false},
							{"sprite": "mob_slime", "hp": 60.0, "boss": false}],
					"gold_gain": 188, "diff": 1})
			ov.set_data(_ov_data("B1", 840))
			stage.add_events([{"kind": "dmg_pop", "val": 214, "at": "enemy"}])
		2:  # ボス（B3F・終盤）
			stage.set_view({"dist": 1240.0, "in_combat": true, "party": _party(),
					"mobs": [{"sprite": "boss_core", "hp": 900.0, "boss": true},
							{"sprite": "elite_guard", "hp": 240.0, "boss": false}],
					"gold_gain": 410, "diff": 2})
			ov.set_data(_ov_data("B2", 210, "深層の門番"))


func _shot(nm: String) -> void:
	get_root().get_texture().get_image().save_png(OUT + nm + ".png")
	print("shot: ", nm)


func _process(_d: float) -> bool:
	_f += 1
	# 各局面：セット→45フレーム進めて（スライドイン収束）撮る
	var names := ["d2_walk", "d2_combat", "d2_boss"]
	var step := 60
	var idx := int(_f / step)
	if _f % step == 1 and idx < 3:
		_phase = idx
		_setup(idx)
	if _f % step == 0 and idx >= 1 and idx <= 3:
		_shot(names[idx - 1])
	if idx >= 3 and _f % step == 0:
		quit(0)
		return true
	# 交戦・ボスは毎フレーム set_view して敵をスロットへ寄せる
	if _f % step > 1 and idx < 3:
		_setup(idx)
	return false
