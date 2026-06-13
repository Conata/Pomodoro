class_name KuroSim
extends RefCounted
## 黒猫飯店 — エンジン非依存のコアロジック（DESIGN.md v4）。
## 固定ステップ（KuroData.SIM_DT）のキャッチアップシミュレーション。
## 壁時計が要る処理（anchor・日付）は呼び出し側から渡す。テスト容易性のため。
##
## 移植時に壊してはいけない構造：
## - ボス箱は撃破時点で即時バンク（state.boxes 直行）——切断でも失わない
## - 扉・エリート箱（run.boxes）だけがリスク資産
## - ポモドーロ中の全滅は終了せず「緊急再同期」（dist-40から続行）

var state: Dictionary = {}
var rng := SimRNG.new()
var events: Array = []


func _init(p_state: Dictionary = {}) -> void:
	if p_state.is_empty():
		p_state = new_state(int(Time.get_ticks_usec()) & 0xFFFFFFFF)
	state = p_state
	rng.state = int(state["rng_state"])


static func new_state(seed_value: int) -> Dictionary:
	var girls := {}
	for id in KuroData.GIRL_ORDER:
		var first_skill := ""
		for sid in KuroData.SKILL_DB:
			if KuroData.SKILL_DB[sid]["girl"] == id and int(KuroData.SKILL_DB[sid]["unlock"]) == 0:
				first_skill = sid
				break
		girls[id] = {
			"aff": 10, "seen": [],
			"equip": {"weapon": {}, "armor": {}, "trinket": {}},
			"skills_eq": [first_skill],
		}
	return {
		"v": "v3",
		"seed": seed_value,
		"rng_state": seed_value,
		"day": 1,
		"gold": 120,
		"stock": {"dry": 8, "meat": 2, "sea": 2},
		"sign": 0,
		"invites": 0,
		"girls": girls,
		"recipes": {"tantan": 1, "chahan": 1, "wantan": 1, "annin": 1},
		"buffs": [],
		"boxes": [],
		"morning": {"keeper": "kiriko", "menu": ["tantan", "chahan", "wantan", "annin"], "door": "open"},
		"forecast": "旨",
		"crowd_penalty": false,
		"dist": 0.0,
		"checkpoint": 0,
		"best_floor": 0,
		"doors_done": [],
		"run": {
			"active": false, "mode": "quick", "task": "", "duration": 0.0, "elapsed": 0.0,
			"anchor": 0.0, "boxes": [], "mats": 0, "gold0": 0, "kills": 0,
			"resyncs": 0, "door_pending": 0.0, "banked": 0,
		},
		"hp": {},
		"in_combat": false,
		"mobs": [],
		"next_enc": 0.0,
		"pending_night": {},
		"scrap": 0,
		"inventory": [],
		"next_item_id": 1,
		"renov": ["start"],
		"pets": [],
		"chest_progress": 0.0,
		"cds": {},
		"daily": {"date": "", "runs": 0, "claimed": false},
		"streak": 0,
		"weekly": {},
		"ship": {"stock": [], "rotated": 0.0},
		"stats": {"days": 0, "focus_min": 0.0, "dives": 0},
		"last_seen": 0.0,
	}


func sync_rng() -> void:
	state["rng_state"] = rng.state


func drain_events() -> Array:
	var out := events
	events = []
	return out


func _emit(kind: String, msg: String, data: Dictionary = {}) -> void:
	var e := {"kind": kind, "msg": msg}
	e.merge(data)
	events.append(e)


# --- 派生値 ------------------------------------------------------------------


func divers() -> Array:
	var out := []
	for id in KuroData.GIRL_ORDER:
		if id != state["morning"]["keeper"]:
			out.append(id)
	return out


func aff(id: String) -> int:
	return int(state["girls"][id]["aff"])


func add_aff(id: String, amount: int) -> void:
	state["girls"][id]["aff"] = clampi(aff(id) + amount, 0, 100)


func renov_bonus(key: String) -> float:
	var total := 0.0
	for id in state["renov"]:
		var eff: Dictionary = KuroData.RENOV_NODES[id]["effect"]
		if eff.has(key):
			total += float(eff[key])
	return total


func pet_bonus(key: String) -> float:
	var total := 0.0
	for id in state["pets"]:
		var eff: Dictionary = KuroData.PETS[id]["effect"]
		if eff.has(key):
			total += float(eff[key])
	return total


func _affix_total(id: String, key: String) -> float:
	var v := 0.0
	for slot in state["girls"][id]["equip"]:
		var it: Dictionary = state["girls"][id]["equip"][slot]
		if it.is_empty():
			continue
		for a in it["affixes"]:
			if a["t"] == key:
				v += float(a["v"])
	return v


func _affix_party(key: String) -> float:
	var v := 0.0
	for id in KuroData.GIRL_ORDER:
		v += _affix_total(id, key)
	return v


func girl_atk(id: String) -> float:
	var base: float = float(KuroData.GIRLS[id]["atk"]) * KuroData.girl_mult(aff(id))
	if id == "kiriko":
		base *= 1.4  # 高クリティカルの期待値
	var add := 0.0
	for slot in state["girls"][id]["equip"]:
		var it: Dictionary = state["girls"][id]["equip"][slot]
		if not it.is_empty():
			add += float(it["base"]) * float(SimItems.SLOTS[it["slot"]]["atk"])
	var pct := renov_bonus("atk") + _affix_total(id, "atk") * 0.01
	return (base + add) * (1.0 + pct)


func girl_maxhp(id: String) -> float:
	var base: float = float(KuroData.GIRLS[id]["hp"]) * KuroData.girl_mult(aff(id))
	var add := 0.0
	for slot in state["girls"][id]["equip"]:
		var it: Dictionary = state["girls"][id]["equip"][slot]
		if not it.is_empty():
			add += float(it["base"]) * float(SimItems.SLOTS[it["slot"]]["hp"])
	var pct := renov_bonus("hp") + _affix_total(id, "hp") * 0.01
	return (base + add) * (1.0 + pct)


func current_floor() -> int:
	return int(float(state["dist"]) / KuroData.FLOOR_LEN)


func gold_mult() -> float:
	return (1.10 if "err404" in state["buffs"] else 1.0) \
			* (1.0 + renov_bonus("gold") + pet_bonus("gold") + _affix_party("gold") * 0.01)


func mat_chance() -> float:
	return 0.10 + (0.08 if "nono" in state["buffs"] else 0.0) \
			+ renov_bonus("mat") + pet_bonus("mat") + _affix_party("mat") * 0.01


func discover_chance() -> float:
	return 0.08 + pet_bonus("discover")


func crit_mult() -> float:
	return 1.0 + renov_bonus("crit") + _affix_party("crit") * 0.01


func dive_speed() -> float:
	return KuroData.DIVE_SPEED * (1.0 + renov_bonus("spd") + _affix_party("spd") * 0.01)


func sign_total() -> int:
	return int(state["sign"]) + int(renov_bonus("sign"))


func skill_slots() -> int:
	return 1 + int(renov_bonus("skill_slot"))


func known_skills(id: String) -> Array:
	var out := []
	for sid in KuroData.SKILL_DB:
		var def: Dictionary = KuroData.SKILL_DB[sid]
		if def["girl"] == id and aff(id) >= KuroData.SKILL_UNLOCK_AFF[int(def["unlock"])]:
			out.append(sid)
	return out


func equip_skill(id: String, skill_id: String) -> bool:
	var eq: Array = state["girls"][id]["skills_eq"]
	if skill_id in eq:
		eq.erase(skill_id)
		return true
	if eq.size() >= skill_slots() or not skill_id in known_skills(id):
		return false
	eq.append(skill_id)
	return true


# --- ダイブ ------------------------------------------------------------------


## mode: "quick"（80秒）/ "pomo"（minutes分）
func start_run(mode: String, minutes: float, anchor: float, task: String = "") -> void:
	state["dist"] = maxf(float(state["dist"]), int(state["checkpoint"]) * KuroData.FLOOR_LEN)
	state["run"] = {
		"active": true, "mode": mode, "task": task,
		"duration": KuroData.QUICK_SEC if mode == "quick" else minutes * 60.0,
		"elapsed": 0.0, "anchor": anchor,
		"boxes": [], "mats": {"dry": 0, "meat": 0, "sea": 0},
		"gold0": int(state["gold"]), "kills": 0,
		"resyncs": 0, "door_pending": 0.0, "banked": 0,
	}
	state["hp"] = {}
	for id in divers():
		state["hp"][id] = girl_maxhp(id)
	state["in_combat"] = false
	state["mobs"] = []
	state["next_enc"] = float(state["dist"]) + rng.randf_range(KuroData.ENC_MIN, KuroData.ENC_MAX)
	state["cds"] = {}
	state["stats"]["dives"] = int(state["stats"]["dives"]) + 1
	_emit("log", "同期開始。%s が深層へ潜る" % "・".join(_diver_names()))


func _diver_names() -> Array[String]:
	var names: Array[String] = []
	for id in divers():
		names.append(KuroData.GIRLS[id]["name"])
	return names


func step(dt: float) -> void:
	var run: Dictionary = state["run"]
	if not run["active"]:
		return
	run["elapsed"] = float(run["elapsed"]) + dt
	_tick_chests(dt)
	if float(run["door_pending"]) > 0.0:
		run["door_pending"] = float(run["door_pending"]) - dt
		if float(run["door_pending"]) <= 0.0:
			resolve_door(state["morning"]["door"] == "open")
	elif state["in_combat"]:
		_combat_step(dt)
	else:
		_travel_step(dt)
	_quantize()
	if float(run["elapsed"]) >= float(run["duration"]):
		_end_run(false)


const QUANT := 0.0001


## 蓄積する浮動小数を毎ステップ固定グリッドへスナップする。
## JSON往復で double の最下位ビットがずれても次のステップで自己修復し、
## セーブ復元後も決定論が保たれる（テスト save で担保）。
func _quantize() -> void:
	state["dist"] = snappedf(float(state["dist"]), QUANT)
	state["next_enc"] = snappedf(float(state["next_enc"]), QUANT)
	state["chest_progress"] = snappedf(float(state["chest_progress"]), QUANT)
	var run: Dictionary = state["run"]
	run["elapsed"] = snappedf(float(run["elapsed"]), QUANT)
	run["door_pending"] = snappedf(float(run["door_pending"]), QUANT)
	for id in state["hp"]:
		state["hp"][id] = snappedf(float(state["hp"][id]), QUANT)
	for id in state["cds"]:
		for sid in state["cds"][id]:
			state["cds"][id][sid] = snappedf(float(state["cds"][id][sid]), QUANT)
	for m in state["mobs"]:
		m["hp"] = snappedf(float(m["hp"]), QUANT)


## 箱はプレイ時間で蓄積（8分毎、改装で短縮）。ぜんまいで自動開封。
func _tick_chests(dt: float) -> void:
	var interval := KuroData.CHEST_INTERVAL * (1.0 - minf(renov_bonus("chest_interval"), 0.5))
	state["chest_progress"] = float(state["chest_progress"]) + dt
	while float(state["chest_progress"]) >= interval:
		state["chest_progress"] = float(state["chest_progress"]) - interval
		var grade := rng.randi(2)
		if renov_bonus("auto_chest") > 0.0:
			state["boxes"].append(grade)
			var r := open_box()
			_emit("log", "ぜんまいが箱を開けた: %s" % r.get("text", ""))
		else:
			state["run"]["boxes"].append(grade)
			_emit("log", "潜行の合間に%sを拾った" % KuroData.BOX_NAMES[grade])


func _travel_step(dt: float) -> void:
	var dist := float(state["dist"])
	var new_dist := dist + dive_speed() * dt
	var fl := current_floor()
	var door_pos := (fl + KuroData.DOOR_AT) * KuroData.FLOOR_LEN
	var gate := float(fl + 1) * KuroData.FLOOR_LEN
	if dist < door_pos and new_dist >= door_pos and not fl in state["doors_done"]:
		state["doors_done"].append(fl)
		state["dist"] = door_pos
		if state["run"]["mode"] == "quick":
			# 12秒の決断バナー。同期時間は+12秒補償
			state["run"]["door_pending"] = KuroData.DOOR_BANNER_SEC
			state["run"]["duration"] = float(state["run"]["duration"]) + KuroData.DOOR_BANNER_SEC
			_emit("door", "増築された扉がある。")
		else:
			# ポモドーロは朝の方針で自動解決——作業を中断させない
			resolve_door(state["morning"]["door"] == "open")
	elif new_dist >= gate - 2.0:
		state["dist"] = gate - 2.0
		_spawn_pack(true)
	elif new_dist >= float(state["next_enc"]):
		state["dist"] = new_dist
		_spawn_pack(false)
	else:
		state["dist"] = new_dist
		_regen(dt)


## 扉の解決。open=true で踏み込む。
func resolve_door(open: bool) -> void:
	state["run"]["door_pending"] = 0.0
	if not open:
		_emit("log", "扉は見なかったことにした")
		return
	var r := rng.randf()
	if r < 0.5:
		var grade := 1 + rng.randi(2)
		state["run"]["boxes"].append(grade)
		_emit("door_loot", "扉の奥に%s。回収（未送付＝リスク資産）" % KuroData.BOX_NAMES[grade])
	elif r < 0.8:
		var ing := String(KuroData.BIOMES[current_floor() % KuroData.BIOMES.size()]["ing"])
		var mats := 3 + rng.randi(3)
		state["run"]["mats"][ing] = int(state["run"]["mats"][ing]) + mats
		_emit("door_loot", "扉の奥は食料庫だった。%s+%d" % [KuroData.ING_NAMES[ing], mats])
	else:
		for id in state["hp"]:
			state["hp"][id] = float(state["hp"][id]) * 0.75
		_emit("log", "罠だ。全員が薄く削られた")


func _regen(dt: float) -> void:
	for id in state["hp"]:
		var mx := girl_maxhp(id)
		if float(state["hp"][id]) > 0.0 and float(state["hp"][id]) < mx:
			state["hp"][id] = minf(mx, float(state["hp"][id]) + mx * 0.04 * dt)


func _spawn_pack(boss: bool) -> void:
	var fl := current_floor()
	var sc := KuroData.depth_scale(fl)
	var biome: Dictionary = KuroData.BIOMES[fl % KuroData.BIOMES.size()]
	var mobs := []
	if boss:
		mobs.append({
			"name": "欠落した%sの主" % biome["name"],
			"hp": 220.0 * sc, "max_hp": 220.0 * sc, "atk": 7.0 * sc,
			"boss": true, "elite": false, "sprite": String(biome["boss"]),
		})
		_emit("boss", "階の最奥。欠落ボスが待っている")
	else:
		var n := 2 + rng.randi(2)
		var elite := rng.chance(0.18)
		for i in n:
			var hp := 22.0 * sc * rng.randf_range(0.85, 1.15)
			mobs.append({
				"name": "断片", "hp": hp, "max_hp": hp, "atk": 1.8 * sc,
				"boss": false, "elite": false,
				"sprite": String(biome["mobs"][rng.randi(biome["mobs"].size())]),
			})
		if elite:
			var ehp := 60.0 * sc
			mobs.append({
				"name": "肥大した断片", "hp": ehp, "max_hp": ehp, "atk": 3.0 * sc,
				"boss": false, "elite": true,
				"sprite": String(biome["mobs"][0]),
			})
	state["mobs"] = mobs
	state["in_combat"] = true


func _alive_divers() -> Array:
	var out := []
	for id in divers():
		if float(state["hp"].get(id, 0.0)) > 0.0:
			out.append(id)
	return out


func _combat_step(dt: float) -> void:
	var alive := _alive_divers()
	if alive.is_empty():
		return
	# 装備スキル（CD制・自動発動）
	for id in alive:
		if not state["cds"].has(id):
			state["cds"][id] = {}
		for sid in state["girls"][id]["skills_eq"]:
			var cd := float(state["cds"][id].get(sid, 0.0)) - dt
			state["cds"][id][sid] = cd
			if cd <= 0.0 and _cast_skill(id, String(sid)):
				state["cds"][id][sid] = float(KuroData.SKILL_DB[sid]["cd"])
				if state["mobs"].is_empty():
					return
	# パーティDPS（会心は期待値で適用）
	var dps := 0.0
	for id in alive:
		dps += girl_atk(id)
	dps *= crit_mult()
	# ムゥの歌（たまに全体回復）
	if "muu" in alive and rng.chance(0.06 * dt / 0.2):
		for id in alive:
			state["hp"][id] = minf(girl_maxhp(id), float(state["hp"][id]) + girl_maxhp(id) * 0.18)
		_emit("fx", "", {"fx": "song"})
	# ミルの守護回復（最も削れた仲間を癒やす）
	if "mil" in alive:
		var low := ""
		var worst := 1.0
		for id in alive:
			var ratio := float(state["hp"][id]) / girl_maxhp(id)
			if ratio < worst:
				worst = ratio
				low = id
		if low != "" and worst < 0.9:
			state["hp"][low] = minf(girl_maxhp(low), float(state["hp"][low]) + girl_maxhp(low) * 0.03 * dt)
	_damage_mobs(dps * dt)
	if state["mobs"].is_empty():
		return
	# 敵攻撃は盾（隊列順の先頭＝ミルがいれば必ずミル）へ。守護で被弾-25%
	var matk := 0.0
	for m in state["mobs"]:
		matk += float(m["atk"])
	var tank: String = alive[0]
	var dmg := matk * dt * (0.75 if tank == "mil" else 1.0)
	state["hp"][tank] = float(state["hp"][tank]) - dmg
	if float(state["hp"][tank]) <= 0.0:
		state["hp"][tank] = 0.0
		_emit("log", "%s の同期が乱れた…" % KuroData.GIRLS[tank]["name"])
		if _alive_divers().is_empty():
			_wipe()


func _cast_skill(id: String, sid: String) -> bool:
	var def: Dictionary = KuroData.SKILL_DB[sid]
	var atk := girl_atk(id)
	match String(def["kind"]):
		"hit":
			if state["mobs"].is_empty():
				return false
			_damage_mobs(atk * float(def["power"]))
			return true
		"aoe":
			if state["mobs"].is_empty():
				return false
			_emit("fx", "", {"fx": "lightning" if def["girl"] == "kiriko" else "explosion"})
			var per := atk * float(def["power"])
			for m in state["mobs"].duplicate():
				m["hp"] = float(m["hp"]) - per
			_sweep_dead_mobs()
			return true
		"heal_one":
			var low := ""
			var worst := 0.92
			for gid in _alive_divers():
				var ratio := float(state["hp"][gid]) / girl_maxhp(gid)
				if ratio < worst:
					worst = ratio
					low = gid
			if low == "":
				return false
			state["hp"][low] = minf(girl_maxhp(low), float(state["hp"][low]) + girl_maxhp(low) * float(def["power"]))
			return true
		"heal_all":
			var any := false
			for gid in _alive_divers():
				var mx := girl_maxhp(gid)
				if float(state["hp"][gid]) < mx * 0.98:
					state["hp"][gid] = minf(mx, float(state["hp"][gid]) + mx * float(def["power"]))
					any = true
			if any:
				_emit("fx", "", {"fx": "song"})
			return any
		"shield_all":
			# シールドは「次の被弾を軽減」扱い：全員を回復で代替し、盾を厚く
			for gid in _alive_divers():
				state["hp"][gid] = minf(girl_maxhp(gid), float(state["hp"][gid]) + girl_maxhp(gid) * float(def["power"]) * 0.6)
			return true
	return false


func _sweep_dead_mobs() -> void:
	var mobs: Array = state["mobs"]
	var i := 0
	while i < mobs.size():
		if float(mobs[i]["hp"]) <= 0.0:
			var m: Dictionary = mobs[i]
			mobs.remove_at(i)
			_on_mob_killed(m)
		else:
			i += 1
	if mobs.is_empty() and state["in_combat"]:
		_end_combat()


func _damage_mobs(amount: float) -> void:
	var mobs: Array = state["mobs"]
	while amount > 0.0 and not mobs.is_empty():
		var m: Dictionary = mobs[0]
		m["hp"] = float(m["hp"]) - amount
		if float(m["hp"]) <= 0.0:
			amount = -float(m["hp"])
			mobs.remove_at(0)
			_on_mob_killed(m)
		else:
			amount = 0.0
	if mobs.is_empty() and state["in_combat"]:
		_end_combat()


func _on_mob_killed(m: Dictionary) -> void:
	var sc := KuroData.depth_scale(current_floor())
	var run: Dictionary = state["run"]
	run["kills"] = int(run["kills"]) + 1
	var g := int(3.0 * sc * gold_mult() * (10.0 if m["boss"] else (3.0 if m["elite"] else 1.0)))
	state["gold"] = int(state["gold"]) + g
	if rng.chance(mat_chance()):
		var ing := String(KuroData.BIOMES[current_floor() % KuroData.BIOMES.size()]["ing"])
		run["mats"][ing] = int(run["mats"][ing]) + 1
	if rng.chance(discover_chance()) or m["boss"]:
		_acquire_item(SimItems.roll(rng, current_floor(), _next_id()))
	if m["elite"]:
		var grade := rng.randi(2)  # 木〜鉄
		run["boxes"].append(grade)
		_emit("loot", "肥大した断片が%sを落とした" % KuroData.BOX_NAMES[grade])
	if m["boss"]:
		# ボス箱は即時バンク——切断でも失わない（戻さないこと）
		var grade := 2 + (1 if current_floor() >= 5 else 0)
		state["boxes"].append(grade)
		run["banked"] = int(run["banked"]) + 1
		_emit("fx", "", {"fx": "explosion"})


func _end_combat() -> void:
	state["in_combat"] = false
	var fl := current_floor()
	var gate := float(fl + 1) * KuroData.FLOOR_LEN
	if absf(float(state["dist"]) - (gate - 2.0)) < 0.5:
		state["dist"] = gate + 2.0
		state["checkpoint"] = fl + 1
		state["best_floor"] = maxi(int(state["best_floor"]), fl + 1)
		_emit("gate", "欠落を埋めた。B%dFへ——ボス箱は送付済み" % (fl + 2))
	for id in divers():
		if float(state["hp"].get(id, 0.0)) <= 0.0:
			state["hp"][id] = girl_maxhp(id) * 0.35
	state["next_enc"] = float(state["dist"]) + rng.randf_range(KuroData.ENC_MIN, KuroData.ENC_MAX)


func _wipe() -> void:
	state["in_combat"] = false
	state["mobs"] = []
	var run: Dictionary = state["run"]
	if run["mode"] == "pomo":
		# 緊急再同期——作業時間を理不尽に奪わない
		var fl_start := float(current_floor()) * KuroData.FLOOR_LEN
		state["dist"] = maxf(fl_start, float(state["dist"]) - KuroData.RESYNC_BACK)
		for id in divers():
			state["hp"][id] = girl_maxhp(id) * 0.6
		run["resyncs"] = int(run["resyncs"]) + 1
		state["next_enc"] = float(state["dist"]) + rng.randf_range(KuroData.ENC_MIN, KuroData.ENC_MAX)
		_emit("resync", "全滅——緊急再同期。少し戻って続行する")
	else:
		_emit("resync", "全滅——切断された")
		_end_run(true)


## 撤退（ポモドーロ放棄）＝切断扱い。ストリークも失う。
func abandon_run() -> void:
	if state["run"]["active"]:
		_end_run(true)


## 完走の記録（デイリー3完走・ストリーク・週間グラフ）。日付は呼び出し側が渡す。
func register_completion(date: String, minutes: float) -> void:
	if String(state["daily"]["date"]) != date:
		state["daily"] = {"date": date, "runs": 0, "claimed": false}
	state["daily"]["runs"] = int(state["daily"]["runs"]) + 1
	state["streak"] = int(state["streak"]) + 1
	state["weekly"][date] = float(state["weekly"].get(date, 0.0)) + minutes


func claim_daily() -> bool:
	if int(state["daily"]["runs"]) >= 3 and not state["daily"]["claimed"]:
		state["daily"]["claimed"] = true
		state["gold"] = int(state["gold"]) + 500
		_emit("log", "デイリー達成。タオ爺のご祝儀 +500G")
		return true
	return false


func _end_run(disconnected: bool) -> void:
	var run: Dictionary = state["run"]
	run["active"] = false
	state["in_combat"] = false
	state["mobs"] = []
	run["door_pending"] = 0.0
	var mats: Dictionary = run["mats"]
	var lost_boxes: int = run["boxes"].size()
	if disconnected:
		for ing in mats:
			mats[ing] = int(int(mats[ing]) / 2.0)
		run["boxes"] = []
		state["crowd_penalty"] = true  # 翌夜の客足-40%
		state["streak"] = 0
	else:
		for grade in run["boxes"]:
			state["boxes"].append(int(grade))
		lost_boxes = 0
	var mats_total := 0
	for ing in mats:
		state["stock"][ing] = int(state["stock"][ing]) + int(mats[ing])
		mats_total += int(mats[ing])
	var minutes := float(run["elapsed"]) / 60.0
	if run["mode"] == "pomo":
		state["stats"]["focus_min"] = float(state["stats"]["focus_min"]) + minutes
	_emit("run_complete", "", {"summary": {
		"mode": run["mode"], "task": run["task"], "minutes": minutes,
		"gold": int(state["gold"]) - int(run["gold0"]), "kills": int(run["kills"]),
		"mats": mats_total, "mats_by": mats.duplicate(),
		"boxes": state["boxes"].size(), "lost": lost_boxes,
		"floor": current_floor(), "resyncs": int(run["resyncs"]),
		"disconnected": disconnected,
	}})


# --- 夜のクイック精算（closeDay）---------------------------------------------
## 完全に計算式。朝の編成が夜の三行に返ってくる。


func close_day() -> Dictionary:
	var keeper: String = state["morning"]["keeper"]
	var menu: Array = state["morning"]["menu"]
	var forecast: String = state["forecast"]
	var synergies: Array[String] = []
	# 仕込み：店番適性×好感度
	var apt := float(KuroData.GIRLS[keeper]["keeper_apt"])
	var prep := int((9.0 + 5.0 * apt) * KuroData.girl_mult(aff(keeper)))
	# 客数 =(8+看板)×フラグ補正
	var customers := 8 + sign_total()
	if "tao" in state["buffs"]:
		customers += 2
	if int(state["invites"]) > 0:
		customers += 3 * int(state["invites"])
		state["invites"] = 0
	if keeper == "muu":
		customers += 4
		synergies.append("店内ライブ")
	var tastes := {}
	for id in menu:
		var t: String = KuroData.RECIPES[id]["taste"]
		tastes[t] = int(tastes.get(t, 0)) + 1
	for t in tastes:
		if int(tastes[t]) >= 3:
			customers += 3
			synergies.append("ご当地フェア")
			break
	var penalized: bool = state["crowd_penalty"]
	if penalized:
		customers = int(customers * 0.6)
		state["crowd_penalty"] = false
	if keeper == "yuzuki":
		prep = int(prep * 1.35)
		synergies.append("解析いらずの仕込み")
	var price_mult := 1.0
	if keeper == "mil":
		price_mult *= 1.10
		synergies.append("静かな給仕")
	if tastes.size() >= 4:
		price_mult *= 1.15
		synergies.append("フルコース")
	if keeper == "kiriko":
		synergies.append("解析仕込み")
	# 自動調理：獲ってきた素材が、今夜つくれるものを決める
	var stock: Dictionary = state["stock"]
	var capacity := mini(customers, prep)
	var served := 0
	var counts := {}
	var night_gold := 0
	var matched := 0
	var sold_tastes := {}
	for i in capacity:
		var pool := []
		for id in menu:
			if int(stock.get(KuroData.RECIPES[id]["ing"], 0)) <= 0:
				continue  # 素材切れの皿は出せない
			var w := 1.0 + (2.0 if KuroData.RECIPES[id]["taste"] == forecast else 0.0)
			for k in int(w * 2.0):
				pool.append(id)
		if pool.is_empty():
			break
		var dish: String = pool[rng.randi(pool.size())]
		var ing: String = KuroData.RECIPES[dish]["ing"]
		stock[ing] = int(stock[ing]) - 1
		served += 1
		var star := int(state["recipes"].get(dish, 1))
		var taste: String = KuroData.RECIPES[dish]["taste"]
		var is_match := taste == forecast or keeper == "kiriko"
		if taste == forecast:
			matched += 1
		var price := KuroData.recipe_price(dish, star) * price_mult * (1.2 if is_match else 1.0)
		night_gold += int(price * gold_mult())
		counts[dish] = int(counts.get(dish, 0)) + 1
		sold_tastes[taste] = true
	state["gold"] = int(state["gold"]) + night_gold
	# 好感度：ダイブ同行+2／店番+1／好物の味が売れた夜+2
	for id in divers():
		add_aff(id, 2)
	add_aff(keeper, 1)
	for id in KuroData.GIRL_ORDER:
		if sold_tastes.get(KuroData.GIRLS[id]["fav"], false):
			add_aff(id, 2)
	# 特注→住民ストーリー発火→永続バフ
	var story := ""
	for dish in counts:
		var recipe: Dictionary = KuroData.RECIPES[dish]
		if recipe.has("resident") and not recipe["resident"] in state["buffs"]:
			state["buffs"].append(recipe["resident"])
			var res: Dictionary = KuroData.RESIDENTS[recipe["resident"]]
			story = "%s\n（%s）" % [res["story"], res["buff"]]
			break
	# 三行
	var top := ""
	var top_n := 0
	for dish in counts:
		if int(counts[dish]) > top_n:
			top_n = int(counts[dish])
			top = String(KuroData.RECIPES[dish]["name"])
	var line1 := "客%d人、%d皿。%s" % [customers, served,
			("%sが一番出た" % top) if top != "" else "今夜は静かだった"]
	if penalized:
		line1 += "（切断の噂で客足が遠い）"
	elif served < customers:
		line1 += "（素材が尽きた）"
	var line2 := "売上 +%dG — 予報『%s』%d皿的中%s" % [night_gold, forecast, matched,
			("／" + "・".join(synergies)) if not synergies.is_empty() else ""]
	var line3 := _flavor_line(keeper)
	var night := {
		"lines": [line1, line2, line3], "gold": night_gold, "served": served,
		"story": story, "talk_done": false,
	}
	state["pending_night"] = night
	return night


func _flavor_line(keeper: String) -> String:
	var pools := {
		"mil": [
			"ミルは皿を誤差0.3mmで重ねた。静かな夜。",
			"ミルが「またのご来店を、事実として待っています」と見送った。",
		],
		"yuzuki": [
			"ユズキのまかないが、今日も誰かを席に座らせた。",
			"ユズキが「food は逃げない、座れって」と常連を叱っていた。",
		],
		"muu": [
			"ムゥの鼻歌で、客の箸が一瞬止まった。悪くない夜。",
			"ムゥが「これ配信していい？」と聞き、全員に断られていた。",
		],
		"kiriko": [
			"キリコがレシートの裏に数式を書いていた。たぶん大丈夫。",
			"キリコ曰く、今夜の換気扇は「良い周波数」らしい。",
		],
	}
	var pool: Array = pools[keeper]
	var line: String = pool[rng.randi(pool.size())]
	if rng.chance(0.25):
		line += " 黒猫はカウンターの端で目を閉じている。"
	return line


## 翌朝へ。予報を更新。
func next_morning() -> void:
	state["day"] = int(state["day"]) + 1
	state["forecast"] = KuroData.TASTES[rng.randi(KuroData.TASTES.size())]
	state["pending_night"] = {}
	state["stats"]["days"] = int(state["stats"]["days"]) + 1


# --- 箱・会話・闇市 -----------------------------------------------------------


## 箱を1つ開ける。drop table: レシピ50/設備15/欠片25/招待状10
func open_box() -> Dictionary:
	if state["boxes"].is_empty():
		return {}
	var grade := int(state["boxes"].pop_front())
	if renov_bonus("chest_quality") > 0.0:
		grade = mini(3, grade + 1)  # 目利き：中身が1段豪華に
	var r := rng.randf()
	if r < KuroData.DROP_RECIPE:
		var pool := []
		for id in KuroData.RECIPES:
			var special: bool = KuroData.RECIPES[id].has("resident")
			if special and grade < 2:
				continue  # 特注は銀箱以上から
			pool.append(id)
		var id: String = pool[rng.randi(pool.size())]
		var star := int(state["recipes"].get(id, 0))
		if star >= 3:
			var refund := int(KuroData.RECIPES[id]["base"])
			state["gold"] = int(state["gold"]) + refund
			return {"kind": "gold", "grade": grade, "text": "%s（☆3済み）→ %dGに換金" % [KuroData.RECIPES[id]["name"], refund]}
		state["recipes"][id] = star + 1
		var label := "新レシピ" if star == 0 else "☆%d に強化" % (star + 1)
		return {"kind": "recipe", "grade": grade, "id": id,
			"text": "レシピ「%s」 %s" % [KuroData.RECIPES[id]["name"], label]}
	elif r < KuroData.DROP_RECIPE + KuroData.DROP_EQUIP:
		state["sign"] = int(state["sign"]) + 1
		return {"kind": "equip", "grade": grade, "text": "設備が増えた。看板+1（客数が増える）"}
	elif r < KuroData.DROP_RECIPE + KuroData.DROP_EQUIP + KuroData.DROP_SHARD:
		var id2: String = KuroData.GIRL_ORDER[rng.randi(KuroData.GIRL_ORDER.size())]
		add_aff(id2, 10)
		return {"kind": "shard", "grade": grade, "girl": id2,
			"text": "記憶の欠片… %s の目が少し揺れた（♥+10）" % KuroData.GIRLS[id2]["name"]}
	else:
		state["invites"] = int(state["invites"]) + 1
		return {"kind": "invite", "grade": grade, "text": "招待状。翌夜の客が増える（+3）"}


## 今夜話せる相手（1夜1人）。aff 15/45/80 の未読シーン。
func available_talk() -> Dictionary:
	if state["pending_night"].is_empty() or state["pending_night"].get("talk_done", false):
		return {}
	for id in KuroData.GIRL_ORDER:
		var seen: Array = state["girls"][id]["seen"]
		for tier in KuroData.TALK_THRESHOLDS.size():
			if not tier in seen and aff(id) >= KuroData.TALK_THRESHOLDS[tier]:
				return {"girl": id, "tier": tier}
	return {}


func complete_talk(girl: String, tier: int) -> void:
	state["girls"][girl]["seen"].append(tier)
	add_aff(girl, 6)
	if not state["pending_night"].is_empty():
		state["pending_night"]["talk_done"] = true


## 闇市。idx は KuroData.MARKET のインデックス。
func market_buy(idx: int) -> Dictionary:
	var item: Dictionary = KuroData.MARKET[idx]
	if int(state["gold"]) < int(item["price"]):
		return {}
	state["gold"] = int(state["gold"]) - int(item["price"])
	match String(item["id"]):
		"recipe":
			var pool := []
			for id in KuroData.RECIPES:
				if not KuroData.RECIPES[id].has("resident") and int(state["recipes"].get(id, 0)) < 3:
					pool.append(id)
			if pool.is_empty():
				state["gold"] = int(state["gold"]) + int(item["price"])
				return {}
			var id3: String = pool[rng.randi(pool.size())]
			state["recipes"][id3] = int(state["recipes"].get(id3, 0)) + 1
			return {"text": "写本入手: %s ☆%d" % [KuroData.RECIPES[id3]["name"], int(state["recipes"][id3])]}
		"mats":
			for ing in KuroData.INGS:
				state["stock"][ing] = int(state["stock"][ing]) + 2
			return {"text": "素材箱: 乾物・肉・海鮮 +2ずつ"}
		"invite":
			state["invites"] = int(state["invites"]) + 1
			return {"text": "招待状を仕入れた（翌夜 客+3）"}
	return {}


# --- 装備（TBH準拠）----------------------------------------------------------


func _next_id() -> int:
	var id := int(state["next_item_id"])
	state["next_item_id"] = id + 1
	return id


## 拾得時は自動装着（そのスロットのスコアが最も低い子へ。改善しないなら倉庫）。
func _acquire_item(item: Dictionary) -> void:
	var best_gain := 0.0
	var best_id := ""
	for id in KuroData.GIRL_ORDER:
		var cur: Dictionary = state["girls"][id]["equip"][item["slot"]]
		var cur_score := 0.0 if cur.is_empty() else float(cur["score"])
		var gain := float(item["score"]) - cur_score
		if gain > best_gain:
			best_gain = gain
			best_id = id
	if best_id != "":
		var old: Dictionary = state["girls"][best_id]["equip"][item["slot"]]
		state["girls"][best_id]["equip"][item["slot"]] = item
		if not old.is_empty():
			state["inventory"].append(old)
		_emit("loot", "%s が %s を装着" % [KuroData.GIRLS[best_id]["name"], SimItems.display_name(item)])
	else:
		state["inventory"].append(item)
	_trim_inventory()


func _trim_inventory() -> void:
	var inv: Array = state["inventory"]
	if inv.size() <= 120:
		return
	inv.sort_custom(func(a, b): return float(a["score"]) < float(b["score"]))
	while inv.size() > 120:
		state["scrap"] = int(state["scrap"]) + SimItems.salvage_value(inv.pop_front())


func _find_inventory(item_id: int) -> int:
	for i in state["inventory"].size():
		if int(state["inventory"][i]["id"]) == item_id:
			return i
	return -1


func equip_from_inventory(item_id: int, girl_id: String) -> bool:
	var i := _find_inventory(item_id)
	if i < 0:
		return false
	var item: Dictionary = state["inventory"][i]
	state["inventory"].remove_at(i)
	var old: Dictionary = state["girls"][girl_id]["equip"][item["slot"]]
	state["girls"][girl_id]["equip"][item["slot"]] = item
	if not old.is_empty():
		state["inventory"].append(old)
	return true


func salvage_item(item_id: int) -> int:
	var i := _find_inventory(item_id)
	if i < 0:
		return 0
	var dust := SimItems.salvage_value(state["inventory"][i])
	state["inventory"].remove_at(i)
	state["scrap"] = int(state["scrap"]) + dust
	return dust


## 一括分解：誰の装備改善にもならない品をまとめて廃材に。
func bulk_salvage() -> Dictionary:
	var keep := []
	var count := 0
	var dust := 0
	for it in state["inventory"]:
		var useful := false
		for id in KuroData.GIRL_ORDER:
			var cur: Dictionary = state["girls"][id]["equip"][it["slot"]]
			if cur.is_empty() or float(cur["score"]) < float(it["score"]):
				useful = true
				break
		if useful:
			keep.append(it)
		else:
			count += 1
			dust += SimItems.salvage_value(it)
	state["inventory"] = keep
	state["scrap"] = int(state["scrap"]) + dust
	return {"count": count, "dust": dust}


## 合成：同グレード3つ→上位1つ（スコアの低い順に消費）。
func synthesize_all() -> int:
	var made := 0
	for grade in range(SimItems.GRADES.size() - 1):
		while true:
			var same := []
			for it in state["inventory"]:
				if int(it["grade"]) == grade:
					same.append(it)
			if same.size() < 3:
				break
			same.sort_custom(func(a, b): return float(a["score"]) < float(b["score"]))
			for k in 3:
				state["inventory"].erase(same[k])
			var item := SimItems.roll_graded(rng, int(state["best_floor"]), _next_id(), grade + 1)
			_emit("loot", "合成成功: %s" % SimItems.display_name(item))
			_acquire_item(item)
			made += 1
	return made


## 刻印：廃材50でアフィックス再抽選（倉庫内のみ）。
func reroll_item(item_id: int) -> bool:
	if int(state["scrap"]) < SimItems.REROLL_COST:
		return false
	var i := _find_inventory(item_id)
	if i < 0:
		return false
	state["scrap"] = int(state["scrap"]) - SimItems.REROLL_COST
	SimItems.reroll_affixes(rng, state["inventory"][i])
	return true


# --- 改装ツリー ---------------------------------------------------------------


func renov_available(id: String) -> bool:
	if id in state["renov"]:
		return false
	for p in KuroData.RENOV_NODES[id]["prev"]:
		if p in state["renov"]:
			return true
	return KuroData.RENOV_NODES[id]["prev"].is_empty()


func unlock_renov(id: String) -> bool:
	if not renov_available(id):
		return false
	var cost := int(KuroData.RENOV_NODES[id]["cost"])
	if int(state["gold"]) < cost:
		return false
	state["gold"] = int(state["gold"]) - cost
	state["renov"].append(id)
	_emit("log", "改装「%s」（%s）" % [KuroData.RENOV_NODES[id]["name"], KuroData.RENOV_NODES[id]["desc"]])
	return true


# --- 交易船・オフライン --------------------------------------------------------


## 10分毎に在庫入替。now は unix 秒。
func maybe_rotate_ship(now: float) -> void:
	var ship: Dictionary = state["ship"]
	if not ship["stock"].is_empty() and now - float(ship["rotated"]) < KuroData.SHIP_ROTATE_SEC:
		return
	ship["rotated"] = now
	var stock := []
	for i in 2:
		var it := SimItems.roll(rng, int(state["best_floor"]) + 2, _next_id(), 0.5)
		stock.append({"type": "item", "item": it, "price": int(float(it["score"]) * 14.0)})
	for pid in KuroData.PETS:
		if not pid in state["pets"] and rng.chance(0.34):
			stock.append({"type": "pet", "pet": pid, "price": int(KuroData.PETS[pid]["cost"])})
			break
	ship["stock"] = stock


func buy_ship(idx: int) -> bool:
	var stock: Array = state["ship"]["stock"]
	if idx < 0 or idx >= stock.size():
		return false
	var entry: Dictionary = stock[idx]
	if int(state["gold"]) < int(entry["price"]):
		return false
	state["gold"] = int(state["gold"]) - int(entry["price"])
	if entry["type"] == "pet":
		state["pets"].append(entry["pet"])
		_emit("log", "%s が店に住み着いた（%s）" % [KuroData.PETS[entry["pet"]]["name"], KuroData.PETS[entry["pet"]]["desc"]])
	else:
		_acquire_item(entry["item"])
	stock.remove_at(idx)
	return true


## 安息（改装ノード）：閉店中の収入。上限8時間。
func apply_offline(now: float) -> Dictionary:
	var last := float(state["last_seen"])
	state["last_seen"] = now
	if last <= 0.0 or renov_bonus("offline") <= 0.0:
		return {}
	var away := clampf(now - last, 0.0, KuroData.OFFLINE_CAP_SEC)
	if away < 120.0:
		return {}
	var sc := KuroData.depth_scale(int(state["best_floor"]))
	var g := int(away * 0.4 * sc * gold_mult())
	var per := int(away / 1500.0)
	state["gold"] = int(state["gold"]) + g
	for ing in KuroData.INGS:
		state["stock"][ing] = int(state["stock"][ing]) + per
	return {"away": away, "gold": g, "mats": per * KuroData.INGS.size()}


# --- 朝の設定 ----------------------------------------------------------------


func set_keeper(id: String) -> void:
	state["morning"]["keeper"] = id


func menu_limit() -> int:
	return 4 + int(renov_bonus("menu_slot"))


func stock_total() -> int:
	var t := 0
	for ing in state["stock"]:
		t += int(state["stock"][ing])
	return t


func toggle_menu(id: String) -> bool:
	var menu: Array = state["morning"]["menu"]
	if id in menu:
		menu.erase(id)
		return true
	if menu.size() >= menu_limit():
		return false
	if int(state["recipes"].get(id, 0)) <= 0:
		return false
	menu.append(id)
	return true
