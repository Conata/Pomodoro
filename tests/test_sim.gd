extends SceneTree
## ヘッドレスのユニットテスト。CI と手元の両方で:
##   godot --headless -s tests/test_sim.gd
## DESIGN.md「ロジックはエンジン非依存の純関数に抽出 → ユニットテスト」に対応。
## （GUT 導入までは依存ゼロのこのランナーで回す）

var fails := 0
var checks := 0


func _initialize() -> void:
	_test_rng_determinism()
	_test_rune_adjacency()
	_test_sim_determinism()
	_test_run_completes_at_duration()
	_test_abandon_penalty()
	_test_synthesize()
	_test_save_roundtrip()
	if fails == 0:
		print("ALL %d CHECKS PASSED" % checks)
	else:
		print("%d/%d CHECKS FAILED" % [fails, checks])
	quit(1 if fails > 0 else 0)


func check(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("  ok: " + label)
	else:
		fails += 1
		printerr("FAIL: " + label)


func _fresh(seed_value: int) -> GameSim:
	return GameSim.new(GameSim.new_state(seed_value))


func _test_rng_determinism() -> void:
	print("[rng]")
	var a := SimRNG.new(12345)
	var b := SimRNG.new(12345)
	var same := true
	var in_range := true
	for i in 1000:
		var x := a.randf()
		if x != b.randf():
			same = false
		if x < 0.0 or x >= 1.0:
			in_range = false
	check(same, "同シードで同系列")
	check(in_range, "randf は [0,1)")
	check(SimRNG.new(1).next_u32() != SimRNG.new(2).next_u32(), "異シードで異なる")


func _test_rune_adjacency() -> void:
	print("[rune]")
	var sim := _fresh(7)
	sim.state["gold"] = 10000
	check(not sim.unlock_rune("hp1"), "隣接していないノードは解放できない")
	check(sim.unlock_rune("atk1"), "起点の隣は解放できる")
	check(sim.unlock_rune("hp1"), "解放後は隣が開く")
	check(int(sim.state["gold"]) == 10000 - 250 - 700, "ゴールドが正しく減る")
	check(not sim.unlock_rune("atk1"), "二重解放は不可")
	check(sim.party_limit() == 1, "初期パーティは1人")
	sim.state["gold"] = 10000
	check(sim.unlock_rune("cmd1"), "指揮Ⅰ解放")
	check(sim.party_limit() == 2, "指揮Ⅰでヒーロー枠+1")
	check(sim.skill_slots() == 1, "初期スキル枠は1")
	check(sim.unlock_rune("awaken"), "覚醒解放")
	check(sim.skill_slots() == 2, "覚醒でスキル枠+1")


func _test_sim_determinism() -> void:
	print("[determinism]")
	var a := _fresh(42)
	var b := _fresh(42)
	a.start_run("test", 25.0, 0.0)
	b.start_run("test", 25.0, 0.0)
	for i in 4500:  # 15分ぶん
		a.step(GameData.SIM_DT)
		b.step(GameData.SIM_DT)
	check(int(a.state["gold"]) == int(b.state["gold"]), "ゴールド一致 (%d)" % int(a.state["gold"]))
	check(float(a.state["distance"]) == float(b.state["distance"]), "距離一致 (%.1fm)" % float(a.state["distance"]))
	check(int(a.state["run"]["kills"]) == int(b.state["run"]["kills"]), "討伐数一致 (%d)" % int(a.state["run"]["kills"]))
	check(a.rng.state == b.rng.state, "RNG状態一致")
	check(int(a.state["gold"]) > 0, "15分で報酬が出ている")
	check(float(a.state["distance"]) > 0.0, "前進している")


func _test_run_completes_at_duration() -> void:
	print("[completion]")
	var sim := _fresh(9)
	sim.start_run("短い集中", 0.1, 0.0)  # 6秒
	for i in 40:
		sim.step(GameData.SIM_DT)
	check(not sim.state["run"]["active"], "満了で自動完走する")
	var found := false
	for e in sim.drain_events():
		if e["kind"] == "run_complete":
			found = true
	check(found, "run_complete イベントが出る")
	sim.register_completion("2026-06-12", 0.1)
	check(int(sim.state["streak"]) == 1, "ストリークが増える")
	check(int(sim.state["daily"]["runs"]) == 1, "デイリーが数える")


func _test_abandon_penalty() -> void:
	print("[abandon]")
	var sim := _fresh(11)
	sim.state["gold"] = 1000
	sim.state["streak"] = 5
	sim.start_run("途中でやめる", 25.0, 0.0)
	for i in 100:
		sim.step(GameData.SIM_DT)
	sim.abandon_run()
	check(int(sim.state["streak"]) == 0, "撤退でストリークリセット")
	check(int(sim.state["gold"]) <= int(1000 * 0.9) + 200, "撤退でゴールド損失（10%）")
	check(not sim.state["run"]["active"], "セッション終了")


func _test_synthesize() -> void:
	print("[synthesize]")
	var sim := _fresh(13)
	for i in 3:
		var it := SimItems.roll_graded(sim.rng, 0, 1000 + i, 2)
		sim.state["inventory"].append(it)
	var made := sim.synthesize_all()
	check(made == 1, "同グレード3つで1回合成")
	var has_higher := false
	for it in sim.state["inventory"]:
		if int(it["grade"]) == 3:
			has_higher = true
	check(has_higher, "上位グレードができる")
	check(sim.state["inventory"].size() == 1, "素材3つは消える")


func _test_save_roundtrip() -> void:
	print("[save]")
	var sim := _fresh(21)
	sim.state["gold"] = 4242
	sim.start_run("save中", 25.0, 0.0)
	for i in 1500:
		sim.step(GameData.SIM_DT)
	sim.sync_rng()
	var text := JSON.stringify(sim.state)
	var loaded: Dictionary = SaveGame.normalize(JSON.parse_string(text))
	var sim2 := GameSim.new(loaded)
	check(int(sim2.state["gold"]) == int(sim.state["gold"]), "ゴールド復元")
	check(sim2.rng.state == sim.rng.state, "RNG復元")
	check(sim2.state["heroes"].size() == sim.state["heroes"].size(), "ヒーロー復元")
	check(int(sim2.state["heroes"][0]["lv"]) == int(sim.state["heroes"][0]["lv"]), "レベル復元（int正規化）")
	# 復元後も同じように進む
	for i in 100:
		sim.step(GameData.SIM_DT)
		sim2.step(GameData.SIM_DT)
	check(int(sim.state["gold"]) == int(sim2.state["gold"]), "復元後も決定論で一致")
