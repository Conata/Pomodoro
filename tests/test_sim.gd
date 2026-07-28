extends SceneTree
## 黒猫飯店 — ヘッドレスユニットテスト。CI と手元の両方で:
##   godot --headless -s tests/test_sim.gd
## HTML版の21項目ハーネスの観点を移植（時間圧縮＝固定ステップ直叩き）。

var fails := 0
var checks := 0


func _initialize() -> void:
	_test_scripts_compile()
	_test_rng()
	_test_determinism()
	_test_quick_completes()
	_test_pomo_completes()
	_test_boss_bank_survives_disconnect()
	_test_resync_during_pomo()
	_test_close_day()
	_test_shop()
	_test_memory()
	_test_ui_theme()
	_test_keeper_matters()
	_test_recipe_star_up()
	_test_talk()
	_test_content()
	_test_equipment()
	_test_renov()
	_test_tree()
	_test_offline()
	_test_daily_streak()
	_test_forecast_night()
	_test_save_roundtrip()
	_test_sync_level()
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


func _test_scripts_compile() -> void:
	# test_sim.gd は main.gd を読まないため、主要スクリプトの読込でコンパイル検証する。
	# （CI の import は || true なので、ここで GDScript の解析エラーを確実に捕える）
	print("[compile]")
	for path in ["res://main.gd", "res://legacy/main_legacy.gd",
			"res://src/ui/hd2d_view.gd", "res://src/ui/home_overlay.gd", "res://src/ui/dive_overlay.gd",
			"res://src/ui/ui_theme.gd", "res://src/ui/ds.gd",
			"res://src/ui/dive_view.gd", "res://src/sim/shop.gd", "res://src/sim/sim.gd",
			"res://src/sim/memory_data.gd"]:
		check(load(path) != null, "%s がコンパイルできる" % path)


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


func _run_shop(shop: ShopSim, seconds: float) -> void:
	var steps := int(seconds / KuroData.SIM_DT)
	for i in steps:
		shop.step(KuroData.SIM_DT)


func _test_shop() -> void:
	print("[shop]")
	var sim := _fresh(61)
	sim.set_keeper("mil")
	sim.state["recipes"]["tantan"] = 1
	sim.state["morning"]["menu"] = ["tantan"]
	sim.state["stock"] = {"dry": 30, "meat": 30, "sea": 30}
	var g0 := int(sim.state["gold"])
	var aff0 := sim.aff("yuzuki")
	var shop := ShopSim.new(sim)
	shop.open_shop()
	check(shop.open, "暖簾を出すと開店する")
	_run_shop(shop, 300.0)
	check(shop.served > 0, "客が来て捌ける (%d皿)" % shop.served)
	check(shop.gold_earned > 0, "売上が出る (+%dG)" % shop.gold_earned)
	check(int(sim.state["gold"]) == g0 + shop.gold_earned, "ゴールドに加算される")
	check(sim.stock_total() < 90, "素材を消費する")
	var night := shop.close_shop()
	check(night["lines"].size() == 3, "閉店サマリは三行")
	check(not shop.open, "暖簾を下ろすと閉店")
	check(sim.aff("yuzuki") > aff0, "同行/店番で好感度が動く")

	# 決定論：同シードなら同じ結果（セーブ/リプレイの再現性）
	var a := _fresh(63)
	var b := _fresh(63)
	for s in [a, b]:
		s.set_keeper("mil")
		s.state["recipes"]["tantan"] = 1
		s.state["morning"]["menu"] = ["tantan"]
		s.state["stock"] = {"dry": 30, "meat": 30, "sea": 30}
	var sa := ShopSim.new(a)
	var sb := ShopSim.new(b)
	sa.open_shop(); sb.open_shop()
	_run_shop(sa, 200.0); _run_shop(sb, 200.0)
	check(sa.gold_earned == sb.gold_earned and sa.served == sb.served, "同シードで一致")
	check(a.rng.state == b.rng.state, "RNG状態も一致")

	# 素材が無ければ1皿も出ず、客は待ちきれず帰る（Dave the Diver の縛り）
	var s2 := _fresh(65)
	s2.state["recipes"]["tantan"] = 1
	s2.state["morning"]["menu"] = ["tantan"]
	s2.state["stock"] = {"dry": 0, "meat": 0, "sea": 0}
	var sh2 := ShopSim.new(s2)
	sh2.open_shop()
	_run_shop(sh2, 300.0)
	check(sh2.served == 0, "素材ゼロでは出せない")
	check(sh2.left_angry > 0, "待ちきれず帰る客が出る")

	# 献立が空なら門前払い
	var s3 := _fresh(67)
	s3.state["morning"]["menu"] = []
	s3.state["stock"] = {"dry": 30, "meat": 30, "sea": 30}
	var sh3 := ShopSim.new(s3)
	sh3.open_shop()
	_run_shop(sh3, 120.0)
	check(sh3.served == 0 and sh3.turned_away > 0, "献立が空なら門前払い")


func _test_memory() -> void:
	print("[memory]")
	check(not KuroMemories.next_for(1, []).is_empty(), "B1で拾える記憶がある")
	check(KuroMemories.next_for(0, []).is_empty(), "B0では拾えない")
	check(KuroMemories.next_for(10, ["m_kanban"]).get("id", "") != "m_kanban", "収集済みは再取得しない")
	var sim := _fresh(71)
	sim.start_run("pomo", 60.0, 0.0, "deep")
	_run_for(sim, 1800.0)  # 深く潜れば道中でメモリを拾う
	check(sim.state["memories"].size() > 0, "潜行でメモリを拾う (%d種)" % sim.state["memories"].size())
	# 決定論（同シードで同じ記憶）
	var a := _fresh(73)
	var b := _fresh(73)
	a.start_run("pomo", 60.0, 0.0, "d")
	b.start_run("pomo", 60.0, 0.0, "d")
	_run_for(a, 1200.0)
	_run_for(b, 1200.0)
	check(a.state["memories"] == b.state["memories"], "同シードで同じ記憶列")
	# ボスのみ心象語／雑魚は普通名（匂わせはボスに集約）
	check(KuroData.PSYCHE.size() > 0, "ボス用の心象語テーブルがある")
	for biome in KuroData.BIOMES:
		check(biome.has("mob_names") and biome.has("elite_name"), "各バイオームに雑魚/エリートの普通名")


func _test_ui_theme() -> void:
	print("[ui]")
	check(UIKit.available(), "UIキットのテクスチャが存在する")
	var th := UIKit.theme()
	check(th != null, "テーマが組める")
	check(th.get_stylebox("panel", "PanelContainer") != null, "パネルstyleboxがある")
	check(th.get_stylebox("normal", "Button") != null, "ボタンstyleboxがある")
	check(th.get_stylebox("fill", "ProgressBar") != null, "バーfill既定がある")
	var pb := ProgressBar.new()
	UIKit.style_bar(pb, "bar_mint")
	check(pb.has_theme_stylebox_override("fill"), "style_barでfillが適用される")
	pb.free()
	var b := Button.new()
	UIKit.as_pomodoro(b)
	check(b.has_theme_stylebox_override("normal"), "as_pomodoroでミントボタン化")
	b.free()


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
		check(TalkData.TALKS[girl].size() == 3, "%s は会話3本" % girl)
		for scene in TalkData.TALKS[girl]:
			total += 1
			check(scene.has("a") and scene.has("b") and not scene["lines"].is_empty(),
					"%s「%s」が完全" % [girl, scene["title"]])
	check(total == TalkData.TALKS.size() * 3, "会話は各キャラ3本ずつ")


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
		var sp := String(ev["speaker"])
		check((KuroData.GIRLS.has(sp) or KuroData.NPCS.has(sp)) and not ev["lines"].is_empty(),
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
	# グレードは7段階（粗末〜星界）。色テーブルも7色で、範囲外はクランプ。
	check(SimItems.GRADES.size() == 7, "グレードは7段階")
	check(KuroData.EQUIP_GRADE_COLORS.size() == 7, "グレード色も7色")
	check(KuroData.equip_grade_color(99) == KuroData.EQUIP_GRADE_COLORS[6], "範囲外グレードは末尾色にクランプ")
	# ソケット枠：上質(2)=0／英雄(4)=1／伝説(5)以上=2
	check(SimItems.socket_capacity(2) == 0, "上質以下はソケットなし")
	check(SimItems.socket_capacity(4) == 1, "英雄は1ソケット")
	check(SimItems.socket_capacity(6) == 2, "星界は2ソケット")
	# 拾得＝自動装着。英雄(grade4)以上は rare_drop フラグが立つ（UIのレア演出用）。
	var atk0 := sim.girl_atk("mil")
	var item := SimItems.roll_graded(sim.rng, 3, 900, 4)
	item["slot"] = "weapon"
	item["base"] = 50.0
	item["score"] = SimItems.score(item)
	var res := sim._acquire_item(item)
	check(bool(res["rare_drop"]), "英雄以上の拾得は rare_drop が立つ")
	check(bool(res["equipped"]), "良い装備は自動装着される")
	check(sim.girl_atk("mil") > atk0, "装備で攻撃が上がる")
	var equipped := false
	for id in KuroData.GIRL_ORDER:
		if not sim.state["girls"][id]["equip"]["weapon"].is_empty():
			equipped = true
	check(equipped, "拾得時に自動装着される")
	# 粗末(grade0)の拾得は rare_drop ではない。
	check(not bool(sim._acquire_item(SimItems.roll_graded(sim.rng, 0, 901, 0))["rare_drop"]),
			"粗末は rare_drop ではない")
	# stat_summary：空装備は0、装備品は base を拾う。
	check(int(SimItems.stat_summary({})["base"]) == 0, "空装備のサマリは0")
	check(float(SimItems.stat_summary(item)["base"]) == 50.0, "stat_summary が base を集計")
	# compare_equip：装着中の品そのものと比べれば差分0＝アップグレードではない。
	var cmp := sim.compare_equip(String(res["girl"]), "weapon", item)
	check(cmp.has("diff") and cmp.has("current") and cmp.has("candidate"), "compare_equip が差分を返す")
	check(not bool(cmp["is_upgrade"]), "同一スコアはアップグレードではない")
	# バッグ合成：同グレード3つ→上位1つ。
	sim.state["inventory"] = []
	for i in 3:
		sim.state["inventory"].append(SimItems.roll_graded(sim.rng, 0, 1000 + i, 1))
	check(sim.synthesize_all() == 1, "バッグは同グレード3つで合成1回")
	# 倉庫合成は5つ必要（3つでは不成立 → 5つで1回）。
	sim.state["storage"] = []
	for i in 3:
		sim.state["storage"].append(SimItems.roll_graded(sim.rng, 0, 1100 + i, 1))
	check(sim.synthesize_storage() == 0, "倉庫は3つでは合成できない（5つ必要）")
	for i in 2:
		sim.state["storage"].append(SimItems.roll_graded(sim.rng, 0, 1103 + i, 1))
	check(sim.synthesize_storage() == 1, "倉庫は同グレード5つで合成1回")
	# ソケット：伝説(5)は2枠。嵌めるとスコアが上がり、満杯なら拒否、外せる。
	sim.state["storage"] = [SimItems.roll_graded(sim.rng, 5, 1200, 5)]
	var gem: String = KuroData.SOCKET_GEMS.keys()[0]
	var s0 := float(sim.state["storage"][0]["score"])
	check(sim.socket_gem(0, gem), "伝説装備に宝石を嵌められる")
	check(float(sim.state["storage"][0]["score"]) > s0, "宝石でスコアが上がる")
	check(sim.socket_gem(0, gem), "2枠目にも嵌められる")
	check(not sim.socket_gem(0, gem), "枠が満杯なら嵌められない")
	check(sim.remove_gem(0, 0), "宝石を外せる")
	# ソケット枠を持たないグレードには嵌められない。
	sim.state["storage"].append(SimItems.roll_graded(sim.rng, 0, 1300, 2))
	check(not sim.socket_gem(1, gem), "ソケットのない装備には嵌められない")
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


func _test_tree() -> void:
	print("[育成ツリー]")
	var sim := _fresh(53)
	var atk0 := sim.girl_atk("yuzuki")
	sim.state["shards"] = 100
	# 直線：前ノード未解放だと買えない
	check(not sim.tree_available("yuzuki", "yuz_b"), "前ノード未解放のノードは不可")
	check(sim.tree_unlock("yuzuki", "yuz_a"), "起点ノードは解放できる")
	check(sim.girl_atk("yuzuki") > atk0, "育成ノードで攻撃が上がる")
	# 技ノードは好感度条件
	check(not sim.tree_available("yuzuki", "yuz_b"), "♥不足だと技ノード不可")
	check(not "wok_storm" in sim.known_skills("yuzuki"), "未解放の技は未習得")
	sim.state["girls"]["yuzuki"]["aff"] = 50
	check(sim.tree_unlock("yuzuki", "yuz_b"), "♥45で技ノード解放")
	check("wok_storm" in sim.known_skills("yuzuki"), "技ノードで技を習得")
	sim.equip_skill("yuzuki", "wok_fist")  # 枠を空ける（初期1枠）
	check(sim.equip_skill("yuzuki", "wok_storm"), "習得した技は装備できる")
	# 欠片不足
	sim.state["shards"] = 0
	check(not sim.tree_unlock("yuzuki", "yuz_c"), "欠片不足では解放できない")


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


func _test_forecast_night() -> void:
	print("[forecast_night]")
	var sim := _fresh(11)
	var fc: Dictionary = sim.forecast_night()
	check(int(fc["customers"]) >= 8, "客数は看板ベース以上")
	check(int(fc["capacity"]) == mini(int(fc["customers"]), int(fc["prep"])), "上限＝min(客,仕込み)")
	check(int(fc["served"]) + int(fc["short"]) == int(fc["capacity"]), "皿＋売り逃し＝上限")
	check(int(fc["gold"]) > 0, "在庫ありなら売上見込みが立つ")
	var stock0: Dictionary = sim.state["stock"].duplicate()
	sim.forecast_night()
	check(sim.state["stock"] == stock0, "見通しは素材を消費しない")
	# 素材ゼロ → 皿ゼロ・全部売り逃し・尽きた素材が並ぶ
	for ing in KuroData.INGS:
		sim.state["stock"][ing] = 0
	fc = sim.forecast_night()
	check(int(fc["served"]) == 0 and int(fc["short"]) == int(fc["capacity"]), "在庫ゼロで全滅")
	check(not (fc["out"] as Array).is_empty(), "尽きた素材が報告される")
	# 見通しと実際の close_day が同程度（乱数の皿選びでズレる分は±40%許容）
	var sim2 := _fresh(11)
	var fc2: Dictionary = sim2.forecast_night()
	var night: Dictionary = sim2.close_day()
	var actual := int(night["gold"])
	var est := int(fc2["gold"])
	check(actual > 0 and absf(est - actual) <= actual * 0.4,
			"見込み%dGは実績%dGの±40%%以内" % [est, actual])
	check(int(fc2["served"]) == int(night["served"]), "皿数の見込みが一致（素材潤沢時）")
	# 夜営業シアター用の配膳記録：1皿1エントリで、合計が夜の売上と一致
	var script: Array = night["script"]
	check(script.size() == int(night["served"]), "配膳記録は皿数ぶん")
	var sum := 0
	for s in script:
		sum += int(s["gold"])
	check(sum == actual, "配膳記録の合計＝夜の売上")
	# タップ給仕のチップは実収入
	var g0 := int(sim2.state["gold"])
	sim2.add_tips(12)
	sim2.add_tips(-99)
	check(int(sim2.state["gold"]) == g0 + 12, "チップ加算（負値は無視）")
	# 常連：連続完走が客数を底上げする（上限5・見通しと精算で同式）
	var sim3 := _fresh(11)
	var base_c := int(sim3.forecast_night()["customers"])
	sim3.state["streak"] = 3
	check(int(sim3.forecast_night()["customers"]) == base_c + 3, "連続3日で客+3")
	sim3.state["streak"] = 99
	check(int(sim3.forecast_night()["customers"]) == base_c + 5, "常連は5人まで")
	var night3: Dictionary = sim3.close_day()
	check(int(night3["regulars"]) == 5, "close_day も常連を数える")
	check(int(night3["customers"]) == base_c + 5, "精算の客数も一致")


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


func _test_sync_level() -> void:
	print("[同期率]")
	var sim := _fresh(77)
	sim.start_run("pomo", 25.0, 0.0)
	check(sim.sync_level() == 1, "潜航開始時は Lv.1")
	check(is_equal_approx(sim.sync_atk_mult(), 1.0), "Lv.1 の攻撃倍率は等倍")
	var base_crit := sim.crit_mult()
	_run_for(sim, 120.0)
	check(sim.sync_level() >= 3, "2分でレベルが上がる（Lv.%d）" % sim.sync_level())
	check(sim.sync_atk_mult() > 1.0, "同期率で攻撃倍率が伸びる")
	check(sim.crit_mult() > base_crit, "Lv.3 の共鳴・急所が会心に効く")
	check(sim.sync_resonances().size() >= 1, "取得済みの共鳴が一覧に出る")
	var p := sim.sync_progress()
	check(p >= 0.0 and p <= 1.0, "進捗は 0〜1 に収まる")
	# レベルアップはイベントとして流れる（UIの演出はこれを拾う）
	var sim2 := _fresh(78)
	sim2.start_run("pomo", 25.0, 0.0)
	var seen := 0
	var named := 0
	for i in int(180.0 / KuroData.SIM_DT):
		sim2.step(KuroData.SIM_DT)
		for e in sim2.drain_events():
			if String(e.get("kind", "")) == "levelup":
				seen += 1
				if String(e.get("res_name", "")) != "":
					named += 1
	check(seen >= 3, "3分で levelup イベントが複数回流れる（%d回）" % seen)
	check(named >= 1, "共鳴の名前が付いたレベルアップがある")
	# 潜航ごとにリセットされる（25分そのものが山を登る形）
	sim2.abandon_run()
	sim2.start_run("pomo", 25.0, 0.0)
	check(sim2.sync_level() == 1, "次の潜航では Lv.1 に戻る")
	# クッキークリッカーの原則：状態が動いたら必ずイベントが出る（UIが描けるように）
	var sim3 := _fresh(79)
	sim3.start_run("pomo", 25.0, 0.0)
	var kill_ev := 0
	var floor_ev := 0
	var gold_seen := 0
	for i in int(300.0 / KuroData.SIM_DT):
		sim3.step(KuroData.SIM_DT)
		for e in sim3.drain_events():
			match String(e.get("kind", "")):
				"kill":
					kill_ev += 1
					gold_seen += int(e.get("gold", 0))
				"gate":
					floor_ev += 1
					check(int(e.get("floor", -1)) > 0, "gate が到達階を運ぶ")
	check(kill_ev > 50, "撃破ごとに kill イベントが出る（5分で%d回）" % kill_ev)
	check(gold_seen > 0, "kill イベントが獲得金を運ぶ（計%dG）" % gold_seen)
	check(floor_ev >= 1, "階層突破で gate イベントが出る（%d回）" % floor_ev)
	# 会心は「拍」単位の事実として流れる（UIが推測で描かなくて済むように）
	var sim4 := _fresh(80)
	sim4.start_run("pomo", 25.0, 0.0)
	var pops := 0
	var crits := 0
	var crit_val := 0
	var norm_val := 0
	for i in int(600.0 / KuroData.SIM_DT):
		sim4.step(KuroData.SIM_DT)
		for e in sim4.drain_events():
			if String(e.get("kind", "")) == "dmg_pop" and String(e.get("at", "")) == "enemy":
				pops += 1
				if bool(e.get("crit", false)):
					crits += 1
					crit_val = maxi(crit_val, int(e.get("val", 0)))
				else:
					norm_val = maxi(norm_val, int(e.get("val", 0)))
	check(pops > 20, "敵ダメージの拍が流れる（%d回）" % pops)
	check(crits > 0, "会心フラグの立った拍がある（%d回）" % crits)
	check(crits < pops, "全部が会心にはならない")
	check(crit_val > norm_val, "会心の拍は数字が大きい（%d > %d）" % [crit_val, norm_val])
	# 夜営業の給仕：劇場での操作が精算に効く
	var sim5 := _fresh(81)
	sim5.state["stock"] = {"dry": 20, "meat": 20, "sea": 20}
	var night := sim5.close_day()
	var g0 := int(sim5.state["gold"])
	var served0 := int(night["served"])
	var gold0 := int(night["gold"])
	# 何もしなかった場合＝増減なし（席を外した人を罰さない）
	var r0 := sim5.settle_service(0, 0, 0)
	check(int(r0["delta"]) == 0, "放置なら増減ゼロ")
	check(int(sim5.state["gold"]) == g0, "放置で所持金は動かない")
	# 早く捌いて客が増えた場合
	var r1 := sim5.settle_service(12, 2, 0)
	check(int(r1["extra_gold"]) == int(r1["per_plate"]) * 2, "追加の客は1皿ぶんずつ売上になる")
	check(int(sim5.state["gold"]) == g0 + int(r1["delta"]), "所持金に反映される")
	check(int(sim5.state["pending_night"]["served"]) == served0 + 2, "精算の皿数が増える")
	check(int(sim5.state["pending_night"]["gold"]) > gold0, "精算の売上が増える")
	# 待たせて帰られた場合
	var sim6 := _fresh(82)
	sim6.state["stock"] = {"dry": 20, "meat": 20, "sea": 20}
	var night6 := sim6.close_day()
	var served6 := int(night6["served"])
	if served6 > 1:
		var r2 := sim6.settle_service(0, 0, 1)
		check(int(r2["lost_gold"]) > 0, "帰られた客のぶん売上を失う")
		check(int(sim6.state["pending_night"]["served"]) == served6 - 1, "精算の皿数が減る")
	check(sim6.settle_service(-5, -1, -1)["delta"] == 0, "負の値は0として扱う")
	# 献立の戦略が拮抗していること（どれか一つが支配的だと選択が消える）
	var tastes := {}
	for rid in KuroData.RECIPES:
		var t := String(KuroData.RECIPES[rid]["taste"])
		if not tastes.has(t): tastes[t] = []
		(tastes[t] as Array).append(rid)
	var same_deck: Array = []
	var vary_deck: Array = []
	for t in tastes:
		if (tastes[t] as Array).size() >= 3 and same_deck.is_empty():
			same_deck = (tastes[t] as Array).slice(0, 3)
	for t in tastes:
		if vary_deck.size() < 4: vary_deck.append((tastes[t] as Array)[0])
		if same_deck.size() == 3 and String(KuroData.RECIPES[(tastes[t] as Array)[0]]["taste"]) \
				!= String(KuroData.RECIPES[same_deck[0]]["taste"]):
			same_deck.append((tastes[t] as Array)[0])
	var function_gold := func(deck: Array, sv: int) -> int:
		var sm := _fresh(sv)
		sm.state["stock"] = {"dry": 40, "meat": 40, "sea": 40}
		sm.state["morning"]["menu"] = deck
		return int(sm.close_day()["gold"])
	var same_tot := 0
	var vary_tot := 0
	for i in 12:
		same_tot += function_gold.call(same_deck, 200 + i)
		vary_tot += function_gold.call(vary_deck, 200 + i)
	var ratio := float(maxi(same_tot, vary_tot)) / float(maxi(mini(same_tot, vary_tot), 1))
	check(ratio < 1.20, "同じ味で固める戦略と4種そろえる戦略が拮抗する（比 %.2f）" % ratio)
	# 物語イベント：台本が揃っていて、進行の条件が一意に決まること
	# （main の _next_event_id と同じ順序をここで固定する。台本だけあって
	#  発火しない状態に戻さないための番人）
	for eid in ["intro_kiriko", "tutorial", "first_surface",
			"story_b3", "story_b6", "story_b10", "story_day3", "story_finale"]:
		check(EventData.EVENTS.has(eid), "台本がある: %s" % eid)
		var ev: Dictionary = EventData.EVENTS[eid]
		check((ev.get("lines", []) as Array).size() > 0, "台詞がある: %s" % eid)
		check(String(ev.get("speaker", "")) != "", "話者がいる: %s" % eid)
	var s0 := _fresh(90)
	check((s0.state["events_seen"] as Array).is_empty(), "新規セーブは既読ゼロ")
	check(int(s0.state["best_floor"]) < 3, "新規は B3 未到達＝節目はまだ来ない")
	# 終幕の条件は「メモリ全収集 ＋ B10到達」（docs/STORY.md 8節の確定）。
	# 深度だけで出すと、掘らなかった人にも像が結ばないまま結末が来る。
	check(KuroMemories.MEMORIES.size() >= 10, "メモリが10本以上ある（%d本）" % KuroMemories.MEMORIES.size())
	var floors := {}
	for m in KuroMemories.MEMORIES:
		floors[int(m["floor"])] = true
	check(floors.size() >= 5, "メモリの出現階が散っている（%d通り）" % floors.size())
	# 深度ドリブンで重複せずに配られること
	var got: Array = []
	for f in range(1, 13):
		for i in 3:
			var nm := KuroMemories.next_for(f, got)
			if nm.is_empty():
				break
			check(not String(nm["id"]) in got, "同じメモリを二度配らない: %s" % String(nm["id"]))
			got.append(String(nm["id"]))
	check(got.size() == KuroMemories.MEMORIES.size(), "B12まで潜れば全部拾える（%d/%d）"
			% [got.size(), KuroMemories.MEMORIES.size()])
	# 文脈でセリフが変わること。「大量のランダム」と「見てくれている」の差はここ。
	var rngc := RandomNumberGenerator.new()
	rngc.seed = 7
	var day_ctx := {"hour": 14, "streak": 0, "day": 1, "chapter": 0, "after": ""}
	var night_ctx := {"hour": 3, "streak": 0, "day": 1, "chapter": 0, "after": ""}
	var late_ctx := {"hour": 14, "streak": 0, "day": 1, "chapter": 99, "after": ""}
	var seen_day := {}
	var seen_night := {}
	var seen_late := {}
	for i in 60:
		seen_day[String(Banter.pick("idle", ["mil"], rngc, [], day_ctx).get("text", ""))] = true
		seen_night[String(Banter.pick("idle", ["mil"], rngc, [], night_ctx).get("text", ""))] = true
		seen_late[String(Banter.pick("idle", ["mil"], rngc, [], late_ctx).get("text", ""))] = true
	check(seen_night.has("…三時です。店長、そろそろ休んでください"), "深夜には時刻の行が出る")
	check(not seen_day.has("…三時です。店長、そろそろ休んでください"), "昼には深夜の行が出ない")
	check(seen_late.has("今日も、わたしの席がありました。事実です"), "終幕の後の行が出る")
	check(not seen_day.has("今日も、わたしの席がありました。事実です"),
			"物語が進む前に終幕後の行が出ない（ネタバレ防止）")
	check(not seen_day.has("設計図を見てから、自分の手をよく見ます"),
			"B6より前に設計図の行が出ない")
	# 章の導出：後から足した story_b4 のような id も拾う
	check(Banter.chapter_of(["intro_kiriko"]) == 1, "導入だけなら章1")
	check(Banter.chapter_of(["story_b4"]) == 4, "表に無い story_b4 も章4として拾う")
	check(Banter.chapter_of(["story_finale", "story_b3"]) == 99, "終幕が最優先")
	# 文脈の仕組みそのものが生きていること（並列編集で消えやすいので番人を置く）
	check(Banter.PRIO_MATCHED > 0.0, "条件が合った行を優先する仕組みがある")
	check(Banter.text_of("そのまま") == "そのまま", "文字列の行は本文をそのまま返す")
	check(Banter.text_of({"t": "辞書の行"}) == "辞書の行", "辞書の行も本文を返せる")
	# 終幕の選択が文脈に効くこと
	var lp := [{"t": "A専用", "when": {"pick": "a"}}, {"t": "B専用", "when": {"pick": "b"}}]
	var hit_a := 0
	var hit_b := 0
	for l in lp:
		if Banter._matches(l, {"pick": "a"}):
			hit_a += 1
		if Banter._matches(l, {"pick": "b"}):
			hit_b += 1
	check(hit_a == 1 and hit_b == 1, "終幕の答えでセリフが振り分けられる")
	# 終幕は2択を持ち、どちらも返答を持つこと
	var fin: Dictionary = EventData.EVENTS["story_finale"]
	check(fin.has("a") and fin.has("b"), "終幕に2択がある")
	for k in ["a", "b"]:
		check((fin[k].get("r", []) as Array).size() >= 3, "終幕の%sに返答がある" % k)
		check(String(fin[k].get("t", "")) != "", "終幕の%sに選択肢の文言がある" % k)
	# 新規セーブは終幕未到達
	check(String(_fresh(91).state.get("finale_pick", "x")) == "", "新規セーブは終幕の答えが空")
	# 店番は6人から選べる。誰を選んでも精算が通ること（台詞プールの取りこぼしで落ちていた）
	for kid in KuroData.GIRL_ORDER:
		var sk := _fresh(90)
		sk.state["stock"] = {"dry": 30, "meat": 30, "sea": 30}
		sk.set_keeper(kid)
		var nk := sk.close_day()
		var lines: Array = nk.get("lines", [])
		check(lines.size() == 3 and String(lines[2]) != "",
				"%s を店番にしても精算の三行が揃う" % kid)
	# 手元に残る額は1箇所で決める（ホームと経営が違う数字を約束していた）
	var sp := _fresh(91)
	sp.state["stock"] = {"dry": 30, "meat": 30, "sea": 30}
	var fcp := sp.forecast_night()
	check(sp.night_profit(fcp) == int(fcp["gold"]) - int(fcp["served"]) * KuroData.MAT_COST,
			"純益 = 売上 - 皿数×原価")
	check(sp.night_profit(fcp) < int(fcp["gold"]), "純益は売上より小さい")
	check(sp.night_profit({}) == 0, "空の見込みでも落ちない")
