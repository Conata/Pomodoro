extends SceneTree
## バランス計測。数値で経済カーブを出すのでチューニングが当て推量にならない。
##   godot --headless -s tools/balance_report.gd
## 主要ノブは src/sim/data.gd（KuroData）と sim.gd の closeDay/_on_mob_killed。
## ここを変えたらこのレポートを回して 25分/7日 の傾きを見る。

func _initialize() -> void:
	print("=== 黒猫飯店 バランスレポート ===")
	_dive_yield(15.0)
	_dive_yield(25.0)
	_dive_yield(50.0)
	_seven_days()
	_skill_dps()
	quit(0)


## 1回の潜行（分）の収穫を複数シードで平均。
func _dive_yield(minutes: float) -> void:
	var samples := 12
	var gold := 0.0; var mats := 0.0; var floor_d := 0.0; var kills := 0.0; var boxes := 0.0
	for s in samples:
		var sim := KuroSim.new(KuroSim.new_state(1000 + s))
		var g0 := int(sim.state["gold"])
		sim.start_run("pomo", minutes, 0.0, "t")
		var steps := int(minutes * 60.0 / KuroData.SIM_DT)
		for i in steps:
			sim.step(KuroData.SIM_DT)
			if not sim.state["run"]["active"]:
				break
		var sm: Dictionary = {}
		for e in sim.drain_events():
			if e["kind"] == "run_complete":
				sm = e["summary"]
		gold += int(sm.get("gold", int(sim.state["gold"]) - g0))
		mats += int(sm.get("mats", 0))
		floor_d += int(sm.get("floor", 0))
		kills += int(sm.get("kills", 0))
		boxes += sim.state["boxes"].size()
	var n := float(samples)
	print("\n[%d分ダイブ x%d平均]" % [int(minutes), samples])
	print("  +%dG  素材%.1f  討伐%.1f体  到達B%.1fF  箱%.1f" % [
		int(gold / n), mats / n, kills / n, floor_d / n + 1.0, boxes / n])


## 25分×1日（潜行→精算）を7日回した累計。
func _seven_days() -> void:
	var sim := KuroSim.new(KuroSim.new_state(777))
	print("\n[7日耐久 25分/日]")
	for day in range(1, 8):
		sim.start_run("pomo", 25.0, 0.0, "t")
		for i in int(25.0 * 60.0 / KuroData.SIM_DT):
			sim.step(KuroData.SIM_DT)
			if not sim.state["run"]["active"]:
				break
		sim.drain_events()
		sim.close_day()
		var stock := sim.stock_total()
		print("  Day%d: 金%d  素材%d  最深B%dF  箱%d" % [
			day, int(sim.state["gold"]), stock, int(sim.state["best_floor"]) + 1, sim.state["boxes"].size()])
		sim.next_morning()


## スキルの実効DPS目安（好感度50時）。
func _skill_dps() -> void:
	print("\n[スキル係数（power×CD）]")
	for sid in KuroData.SKILL_DB:
		var d: Dictionary = KuroData.SKILL_DB[sid]
		var per_sec := float(d["power"]) / float(d["cd"]) if d["kind"] in ["hit", "aoe"] else 0.0
		print("  %-12s %s power%.1f/CD%.0f = %.2f/s %s" % [
			d["name"], d["kind"], float(d["power"]), float(d["cd"]), per_sec,
			"fx:" + String(d.get("fx", "—"))])
