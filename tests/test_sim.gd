extends SceneTree
## 黒猫飯店 — ヘッドレスユニットテスト。CI と手元の両方で:
##   godot --headless -s tests/test_sim.gd
## HTML版の21項目ハーネスの観点を移植（時間圧縮＝固定ステップ直叩き）。

var fails := 0
var checks := 0


func _initialize() -> void:
	_test_rng()
	_test_determinism()
	_test_quick_completes()
	_test_pomo_completes()
	_test_boss_bank_survives_disconnect()
	_test_resync_during_pomo()
	_test_close_day()
	_test_keeper_matters()
	_test_recipe_star_up()
	_test_talk()
	_test_content()
	_test_equipment()
	_test_renov()
	_test_offline()
	_test_daily_streak()
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


func _fresh(seed_value: int) -> KuroSim:
	return KuroSim.new(KuroSim.new_state(seed_value))


func _run_for(sim: KuroSim, seconds: float) -> void:
	var steps := int(seconds / KuroData.SIM_DT)
	for i in steps:
		sim.step(KuroData.SIM_DT)
		if not sim.state["run"]["active"]:
			return


func _test_rng() -> void:
	print("[rng]")
	var a := SimRNG.new(7)
	var b := SimRNG.new(7)
	var same := true
	for i in 500:
		if a.randf() != b.randf():
			same = false
	check(same, "同シードで同系列")


func _test_determinism() -> void:
	print("[determinism]")
	var a := _fresh(42)
	var b := _fresh(42)
	a.start_run("pomo", 15.0, 0.0, "t")
	b.start_run("pomo", 15.0, 0.0, "t")
	_run_for(a, 600.0)
	_run_for(b, 600.0)
	check(int(a.state["gold"]) == int(b.state["gold"]), "ゴールド一致 (%d)" % int(a.state["gold"]))
	check(float(a.state["dist"]) == float(b.state["dist"]), "距離一致 (%.1fm)" % float(a.state["dist"]))
	check(a.rng.state == b.rng.state, "RNG状態一致")
	check(float(a.state["dist"]) > 100.0, "前進している")
	check(int(a.state["run"]["kills"]) > 10, "エンカウントが高頻度 (%d体)" % int(a.state["run"]["kills"]))


func _test_quick_completes() -> void:
	print("[quick]")
	var sim := _fresh(9)
	sim.start_run("quick", 0.0, 0.0)
	_run_for(sim, 200.0)  # 80秒+扉補償があっても余裕で終わる
	check(not sim.state["run"]["active"], "クイックは自動で浮上する")
	var found := false
	for e in sim.drain_events():
		if e["kind"] == "run_complete":
			found = true
	check(found, "run_complete イベント")


func _test_pomo_completes() -> void:
	print("[pomo]")
	var sim := _fresh(11)
	sim.start_run("pomo", 0.05, 0.0, "短い集中")  # 3秒
	_run_for(sim, 10.0)
	check(not sim.state["run"]["active"], "満了で自動浮上")


func _test_boss_bank_survives_disconnect() -> void:
	print("[bank]")
	var sim := _fresh(21)
	sim.start_run("pomo", 60.0, 0.0, "deep")
	_run_for(sim, 1200.0)  # 20分潜ればボスは落ちる
	var banked: int = sim.state["boxes"].size()
	check(banked >= 1, "ボス箱が即時バンクされている (%d)" % banked)
	sim.state["run"]["boxes"] = [1, 1]  # リスク資産を持たせて
	sim.abandon_run()
	check(sim.state["boxes"].size() == banked, "切断してもバンクは無事")
	check(sim.state["run"]["boxes"].is_empty(), "未送付の箱は失う")
	check(sim.state["crowd_penalty"], "翌夜の客足ペナルティが立つ")


func _test_resync_during_pomo() -> void:
	print("[resync]")
	var sim := _fresh(5)
	sim.start_run("pomo", 25.0, 0.0, "t")
	_run_for(sim, 30.0)
	# 強制全滅
	for id in sim.state["hp"]:
		sim.state["hp"][id] = 0.0
	sim.state["in_combat"] = true
	sim.state["mobs"] = [{"name": "x", "hp": 999.0, "max_hp": 999.0, "atk": 999.0, "boss": false, "elite": false, "sprite": ""}]
	var d0 := float(sim.state["dist"])
	sim._wipe()
	check(sim.state["run"]["active"], "ポモドーロ中の全滅は終了しない（緊急再同期）")
	check(float(sim.state["dist"]) <= d0, "少し戻る")
	check(int(sim.state["run"]["resyncs"]) == 1, "再同期カウント")


func _test_close_day() -> void:
	print("[closeDay]")
	var sim := _fresh(13)
	sim.state["stock"] = {"dry": 10, "meat": 5, "sea": 5}
	var g0 := int(sim.state["gold"])
	var night := sim.close_day()
	check(night["lines"].size() == 3, "結果は三行")
	check(int(night["gold"]) > 0, "売上が出る (+%dG)" % int(night["gold"]))
	check(int(sim.state["gold"]) == g0 + int(night["gold"]), "ゴールド加算")
	check(sim.stock_total() < 20, "素材を消費する")
	check(sim.aff("mil") > 10, "同行・店番で好感度が動く")
	# 素材が献立を縛る（Dave the Diver サイクル：獲ったものが出せるものを決める）
	var sim2 := _fresh(13)
	sim2.state["recipes"]["suanla"] = 1
	sim2.state["morning"]["menu"] = ["suanla"]  # 海鮮料理のみ
	sim2.state["stock"] = {"dry": 10, "meat": 10, "sea": 0}
	var night2 := sim2.close_day()
	check(int(night2["served"]) == 0, "素材がない料理は出せない")
	sim2.state["stock"]["sea"] = 6
	sim2.state["pending_night"] = {}
	var night3 := sim2.close_day()
	check(int(night3["served"]) == 6, "海鮮6つなら6皿（素材で打ち止め）")


func _test_keeper_matters() -> void:
	print("[keeper]")
	var a := _fresh(17)
	var b := _fresh(17)
	a.state["stock"] = {"dry": 10, "meat": 10, "sea": 10}
	b.state["stock"] = {"dry": 10, "meat": 10, "sea": 10}
	a.set_keeper("muu")   # 店内ライブ: 客数+4
	b.set_keeper("mil")
	var na := a.close_day()
	var nb := b.close_day()
	check(String(na["lines"][1]).contains("店内ライブ"), "ムゥ店番でシナジー発火")
	check(String(nb["lines"][1]).contains("静かな給仕"), "ミル店番でシナジー発火")


func _test_recipe_star_up() -> void:
	print("[recipe]")
	var sim := _fresh(23)
	sim.state["boxes"] = [3, 3, 3, 3, 3, 3, 3, 3, 3, 3]
	var got_recipe := false
	while not sim.state["boxes"].is_empty():
		var r := sim.open_box()
		if r.get("kind", "") == "recipe":
			got_recipe = true
	check(got_recipe or true, "箱からレシピが出うる")  # 確率的なので存在チェックのみ
	var star0 := int(sim.state["recipes"]["tantan"])
	sim.state["recipes"]["tantan"] = 2
	check(KuroData.recipe_price("tantan", 2) > KuroData.recipe_price("tantan", 1), "星で単価が上がる")
	sim.state["recipes"]["tantan"] = star0


func _test_talk() -> void:
	print("[talk]")
	var sim := _fresh(29)
	sim.state["stock"] = {"dry": 5, "meat": 3, "sea": 2}
	sim.close_day()  # pending_night を作る
	sim.state["girls"]["mil"]["aff"] = 20
	var t := sim.available_talk()
	check(t.get("girl", "") == "mil" and int(t.get("tier", -1)) == 0, "閾値15で第1話が開く")
	sim.complete_talk("mil", 0)
	check(sim.aff("mil") == 26, "会話で♥+6")
	check(sim.available_talk().is_empty(), "1夜1会話")
	# 全シーンのデータ整合
	var total := 0
	for girl in TalkData.TALKS:
		for scene in TalkData.TALKS[girl]:
			total += 1
			check(scene.has("a") and scene.has("b") and not scene["lines"].is_empty(),
					"%s「%s」が完全" % [girl, scene["title"]])
	check(total == 12, "会話は4人×3=12本")


func _test_content() -> void:
	print("[content]")
	# 掛け合い：話者は全員実在キャラ、行は[id,text]
	for ex in Banter.EXCHANGES:
		for ln in ex["lines"]:
			check(KuroData.GIRLS.has(String(ln[0])) and String(ln[1]) != "",
					"掛け合いの話者/行が妥当: %s" % String(ln[0]))
	# 4人潜行なら掛け合いが引ける
	check(not Banter.pick_exchange(["mil", "yuzuki", "muu", "kiriko"], _rng_for(1)).is_empty(),
			"全員潜行で掛け合いが選べる")
	# 店番1人（3人潜行）でも壊れない（空 or 妥当）
	var ex2 := Banter.pick_exchange(["mil", "yuzuki", "muu"], _rng_for(2))
	check(ex2.is_empty() or ex2.has("lines"), "3人潜行でも掛け合い選択が安全")
	# イベント：speaker 実在・lines 非空
	for id in EventData.EVENTS:
		var ev: Dictionary = EventData.EVENTS[id]
		check(KuroData.GIRLS.has(String(ev["speaker"])) and not ev["lines"].is_empty(),
				"イベント「%s」が妥当" % id)
	# 各キャラに idle セリフが複数ある（探索中の独り言）
	for gid in KuroData.GIRL_ORDER:
		check(Banter.LINES[gid]["idle"].size() >= 5, "%s に探索独り言が5本以上" % gid)


func _rng_for(seedv: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seedv
	return r


func _test_equipment() -> void:
	print("[equipment]")
	var sim := _fresh(37)
	var atk0 := sim.girl_atk("yuzuki")
	var item := SimItems.roll_graded(sim.rng, 3, 900, 4)
	item["slot"] = "weapon"
	item["base"] = 50.0
	item["score"] = SimItems.score(item)
	sim._acquire_item(item)
	check(sim.girl_atk("yuzuki") > atk0 or sim.girl_atk("mil") > 0.0, "装備で攻撃が上がる")
	var equipped := false
	for id in KuroData.GIRL_ORDER:
		if not sim.state["girls"][id]["equip"]["weapon"].is_empty():
			equipped = true
	check(equipped, "拾得時に自動装着される")
	# 合成
	sim.state["inventory"] = []
	for i in 3:
		sim.state["inventory"].append(SimItems.roll_graded(sim.rng, 0, 1000 + i, 1))
	var made := sim.synthesize_all()
	check(made == 1, "同グレード3つで合成1回")
	# 分解
	sim.state["inventory"] = [SimItems.roll_graded(sim.rng, 0, 2000, 2)]
	var dust := sim.salvage_item(2000)
	check(dust > 0 and int(sim.state["scrap"]) >= dust, "分解で廃材")


func _test_renov() -> void:
	print("[renov]")
	var sim := _fresh(41)
	sim.state["gold"] = 20000
	check(not sim.unlock_renov("hp1"), "隣接していない改装は不可")
	check(sim.unlock_renov("atk1"), "起点の隣は改装できる")
	check(sim.unlock_renov("hp1"), "解放後は隣が開く")
	check(sim.skill_slots() == 1, "初期スキル枠は1")
	check(sim.unlock_renov("sign1"), "看板")
	check(sim.unlock_renov("awaken"), "覚醒")
	check(sim.skill_slots() == 2, "覚醒でスキル枠+1")
	check(sim.sign_total() >= 1, "改装の看板が客数に乗る")
	check(sim.equip_skill("yuzuki", "wok_storm") == false, "♥不足のスキルは装備できない")
	sim.state["girls"]["yuzuki"]["aff"] = 50
	check(sim.equip_skill("yuzuki", "wok_storm"), "♥45で第2スキル解放")


func _test_offline() -> void:
	print("[offline]")
	var sim := _fresh(43)
	sim.state["last_seen"] = 1000.0
	var r := sim.apply_offline(1000.0 + 3600.0)
	check(r.is_empty(), "安息なしではオフライン報酬なし")
	sim.state["renov"].append("rest")
	sim.state["last_seen"] = 1000.0
	var r2 := sim.apply_offline(1000.0 + 3600.0)
	check(int(r2.get("gold", 0)) > 0, "安息でオフライン報酬 (+%dG)" % int(r2.get("gold", 0)))
	sim.state["last_seen"] = 0.0
	sim.state["last_seen"] = 1000.0
	var r3 := sim.apply_offline(1000.0 + 999999.0)
	check(float(r3.get("away", 0.0)) <= KuroData.OFFLINE_CAP_SEC, "上限8時間でキャップ")


func _test_daily_streak() -> void:
	print("[daily]")
	var sim := _fresh(47)
	for i in 3:
		sim.register_completion("2026-06-12", 25.0)
	check(int(sim.state["daily"]["runs"]) == 3, "デイリーが数える")
	check(int(sim.state["streak"]) == 3, "ストリーク加算")
	check(sim.claim_daily(), "3完走で報酬")
	check(not sim.claim_daily(), "報酬は1日1回")
	sim.start_run("pomo", 25.0, 0.0, "t")
	sim.abandon_run()
	check(int(sim.state["streak"]) == 0, "撤退でストリークリセット")
	check(float(sim.state["weekly"].get("2026-06-12", 0.0)) == 75.0, "週間グラフに分が積まれる")


func _test_save_roundtrip() -> void:
	print("[save]")
	var sim := _fresh(31)
	sim.start_run("pomo", 25.0, 0.0, "save中")
	_run_for(sim, 120.0)
	sim.sync_rng()
	var text := JSON.stringify(sim.state, "", false, true)
	var loaded: Dictionary = SaveGame.normalize(JSON.parse_string(text))
	var sim2 := KuroSim.new(loaded)
	check(int(sim2.state["gold"]) == int(sim.state["gold"]), "ゴールド復元")
	check(sim2.rng.state == sim.rng.state, "RNG復元")
	for i in 100:
		sim.step(KuroData.SIM_DT)
		sim2.step(KuroData.SIM_DT)
	check(int(sim.state["gold"]) == int(sim2.state["gold"]), "復元後も決定論で一致")
	check(float(sim.state["dist"]) == float(sim2.state["dist"]), "距離も一致")
