class_name GameSim
extends RefCounted
## エンジン非依存のコアロジック。固定ステップ（GameData.SIM_DT）の
## キャッチアップシミュレーションで進む——タブ非アクティブでも進行が正確
## であること（DESIGN.md タイマー実装）はこの構造が担保する。
## 壁時計に依存する処理（日付・交易船・オフライン報酬）は now/date を
## 引数で受け取る。テストから時間を注入できるようにするため。

var state: Dictionary = {}
var rng := SimRNG.new()
var events: Array = []


func _init(p_state: Dictionary = {}) -> void:
	if p_state.is_empty():
		p_state = new_state(int(Time.get_ticks_usec()) & 0xFFFFFFFF)
	state = p_state
	rng.state = int(state["rng_state"])
	if state["heroes"].is_empty():
		state["heroes"].append(_make_hero("warrior"))


static func new_state(seed_value: int) -> Dictionary:
	return {
		"v": "v7",
		"seed": seed_value,
		"rng_state": seed_value,
		"gold": 0,
		"stardust": 0,
		"chests": 0,
		"chest_progress": 0.0,
		"next_item_id": 1,
		"heroes": [],
		"inventory": [],
		"runes": ["start"],
		"pets": [],
		"bless": {"atk": 0.0, "hp": 0.0, "spd": 0.0, "gold": 0.0, "xp": 0.0},
		"distance": 0.0,
		"checkpoint": 0,
		"best_layer": 0,
		"run": {
			"active": false, "task": "", "duration": 0.0, "elapsed": 0.0,
			"anchor": 0.0, "gold0": 0, "items": 0, "kills": 0, "deaths": 0, "dist0": 0.0,
		},
		"in_combat": false,
		"mobs": [],
		"next_encounter": 50.0,
		"pending_blessing": {},
		"retreat_cd": 0.0,
		"daily": {"date": "", "runs": 0, "claimed": false},
		"streak": 0,
		"weekly": {},
		"ship": {"stock": [], "rotated": 0.0},
		"stats": {"focus_min": 0.0, "runs": 0},
		"last_seen": 0.0,
	}


## 保存前に必ず呼ぶ。RNG内部状態を state に書き戻す。
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


# --- 派生ステータス ---------------------------------------------------------


func rune_bonus(key: String) -> float:
	var total := 0.0
	for id in state["runes"]:
		var eff: Dictionary = GameData.RT_NODES[id]["effect"]
		if eff.has(key):
			total += float(eff[key])
	return total


func pet_bonus(key: String) -> float:
	var total := 0.0
	for id in state["pets"]:
		var eff: Dictionary = GameData.PETS[id]["effect"]
		if eff.has(key):
			total += float(eff[key])
	return total


func bless_bonus(key: String) -> float:
	return float(state["bless"].get(key, 0.0))


func _affix_party(key: String) -> float:
	var v := 0.0
	for h in state["heroes"]:
		for slot in h["equip"]:
			var it: Dictionary = h["equip"][slot]
			if it.is_empty():
				continue
			for a in it["affixes"]:
				if a["t"] == key:
					v += float(a["v"])
	return v


func party_limit() -> int:
	return 1 + int(rune_bonus("party"))


func skill_slots() -> int:
	return 1 + int(rune_bonus("skill_slot"))


func gold_mult() -> float:
	return 1.0 + rune_bonus("gold") + pet_bonus("gold") + bless_bonus("gold") + _affix_party("gold") * 0.01


func xp_mult() -> float:
	return 1.0 + rune_bonus("xp") + pet_bonus("xp") + bless_bonus("xp") + _affix_party("xp") * 0.01


func crit_chance() -> float:
	return 0.05 + rune_bonus("crit") + _affix_party("crit") * 0.01


func discover_chance() -> float:
	return 0.12 + pet_bonus("discover") * 0.4


func party_speed() -> float:
	return 8.0 * (1.0 + rune_bonus("spd") + bless_bonus("spd") + _affix_party("spd") * 0.01)


func hero_atk(h: Dictionary) -> float:
	var base: float = float(GameData.CLASSES[h["cls"]]["atk"]) * (1.0 + 0.12 * (int(h["lv"]) - 1))
	var add := 0.0
	var pct := bless_bonus("atk") + rune_bonus("atk")
	for slot in h["equip"]:
		var it: Dictionary = h["equip"][slot]
		if it.is_empty():
			continue
		add += float(it["base"]) * float(GameData.SLOTS[it["slot"]]["atk"])
		for a in it["affixes"]:
			if a["t"] == "atk":
				pct += float(a["v"]) * 0.01
	return (base + add) * (1.0 + pct)


func hero_maxhp(h: Dictionary) -> float:
	var base: float = float(GameData.CLASSES[h["cls"]]["hp"]) * (1.0 + 0.10 * (int(h["lv"]) - 1))
	var add := 0.0
	var pct := bless_bonus("hp") + rune_bonus("hp")
	for slot in h["equip"]:
		var it: Dictionary = h["equip"][slot]
		if it.is_empty():
			continue
		add += float(it["base"]) * float(GameData.SLOTS[it["slot"]]["hp"])
		for a in it["affixes"]:
			if a["t"] == "hp":
				pct += float(a["v"]) * 0.01
	return (base + add) * (1.0 + pct)


func known_skills(h: Dictionary) -> Array:
	var out := []
	for id in GameData.SKILL_DB:
		var def: Dictionary = GameData.SKILL_DB[id]
		if def["cls"] == h["cls"] and int(h["lv"]) >= int(def["lv"]):
			out.append(id)
	return out


func current_layer() -> int:
	return int(state["distance"] / GameData.LAYER_LENGTH)


func _make_hero(cls: String) -> Dictionary:
	var h := {
		"name": GameData.HERO_NAMES[rng.randi(GameData.HERO_NAMES.size())],
		"cls": cls,
		"lv": 1,
		"xp": 0.0,
		"hp": 0.0,
		"shield": 0.0,
		"equip": {"weapon": {}, "armor": {}, "trinket": {}},
		"skills_eq": [],
		"cds": {},
	}
	for id in GameData.SKILL_DB:
		if GameData.SKILL_DB[id]["cls"] == cls and int(GameData.SKILL_DB[id]["lv"]) == 1:
			h["skills_eq"].append(id)
			break
	h["hp"] = hero_maxhp(h)
	return h


# --- セッション制御 ----------------------------------------------------------


## minutes=0 は放置モード（手動帰還まで継続）。
func start_run(task: String, minutes: float, anchor: float) -> void:
	state["distance"] = maxf(float(state["distance"]), state["checkpoint"] * GameData.LAYER_LENGTH)
	state["run"] = {
		"active": true,
		"task": task,
		"duration": minutes * 60.0,
		"elapsed": 0.0,
		"anchor": anchor,
		"gold0": int(state["gold"]),
		"items": 0,
		"kills": 0,
		"deaths": 0,
		"dist0": float(state["distance"]),
	}
	state["in_combat"] = false
	state["mobs"] = []
	state["retreat_cd"] = 0.0
	state["next_encounter"] = float(state["distance"]) + 30.0 + rng.randf() * 40.0
	for h in state["heroes"]:
		h["hp"] = hero_maxhp(h)
		h["shield"] = 0.0
	_emit("log", "「%s」に出発。パーティが潜り始めた" % task)


func step(dt: float) -> void:
	var run: Dictionary = state["run"]
	if not run["active"]:
		return
	run["elapsed"] = float(run["elapsed"]) + dt
	_tick_chests(dt)
	_tick_blessing(dt)
	if float(state["retreat_cd"]) > 0.0:
		state["retreat_cd"] = float(state["retreat_cd"]) - dt
	elif state["in_combat"]:
		_combat_step(dt)
	else:
		_travel_step(dt)
	if float(run["duration"]) > 0.0 and float(run["elapsed"]) >= float(run["duration"]):
		finish_run()


## 完走（ポモドーロ満了 or 放置モードの手動帰還）。
func finish_run() -> Dictionary:
	var run: Dictionary = state["run"]
	run["active"] = false
	state["in_combat"] = false
	state["mobs"] = []
	state["pending_blessing"] = {}
	var summary := {
		"task": run["task"],
		"minutes": float(run["elapsed"]) / 60.0,
		"gold": int(state["gold"]) - int(run["gold0"]),
		"kills": int(run["kills"]),
		"items": int(run["items"]),
		"deaths": int(run["deaths"]),
		"dist": float(state["distance"]) - float(run["dist0"]),
		"layer": current_layer(),
	}
	_emit("run_complete", "完走！", {"summary": summary})
	return summary


## 撤退（タスク放棄）: 連続記録リセット＋ゴールド損失。
func abandon_run() -> void:
	var run: Dictionary = state["run"]
	run["active"] = false
	state["in_combat"] = false
	state["mobs"] = []
	state["pending_blessing"] = {}
	state["streak"] = 0
	var loss := int(int(state["gold"]) * 0.1)
	state["gold"] = int(state["gold"]) - loss
	_emit("abandon", "撤退した… ストリークは失われ、%dG を落とした" % loss)


## 完走の記録（日付は呼び出し側＝壁時計側が渡す）。
func register_completion(date: String, minutes: float) -> void:
	if state["daily"]["date"] != date:
		state["daily"] = {"date": date, "runs": 0, "claimed": false}
	state["daily"]["runs"] = int(state["daily"]["runs"]) + 1
	state["streak"] = int(state["streak"]) + 1
	state["weekly"][date] = float(state["weekly"].get(date, 0.0)) + minutes
	state["stats"]["focus_min"] = float(state["stats"]["focus_min"]) + minutes
	state["stats"]["runs"] = int(state["stats"]["runs"]) + 1


func claim_daily() -> bool:
	if int(state["daily"]["runs"]) >= 3 and not state["daily"]["claimed"]:
		state["daily"]["claimed"] = true
		state["gold"] = int(state["gold"]) + 500
		_emit("log", "デイリー達成報酬 +500G")
		return true
	return false


# --- 進軍・戦闘 --------------------------------------------------------------


func _travel_step(dt: float) -> void:
	var new_dist: float = float(state["distance"]) + party_speed() * dt
	var gate := float(current_layer() + 1) * GameData.LAYER_LENGTH
	if new_dist >= gate - 2.0:
		state["distance"] = gate - 2.0
		_spawn_pack(true)
	elif new_dist >= float(state["next_encounter"]):
		state["distance"] = new_dist
		_spawn_pack(false)
	else:
		state["distance"] = new_dist
		_regen(dt)


func _regen(dt: float) -> void:
	for h in state["heroes"]:
		var mx := hero_maxhp(h)
		if float(h["hp"]) > 0.0 and float(h["hp"]) < mx:
			h["hp"] = minf(mx, float(h["hp"]) + mx * 0.05 * dt)


func _spawn_pack(boss: bool) -> void:
	var layer := current_layer()
	var s := GameData.area_scale(layer)
	var biome: Dictionary = GameData.BIOMES[layer % GameData.BIOMES.size()]
	var mobs := []
	if boss:
		mobs.append({
			"name": "%sの主" % biome["name"],
			"hp": 350.0 * s, "max_hp": 350.0 * s, "atk": 9.0 * s, "boss": true,
			"sprite": String(biome.get("boss", "")),
		})
		_emit("log", "ボスゲート！ 「%sの主」が立ちはだかる" % biome["name"])
	else:
		var n := 2 + rng.randi(3)
		var sprites: Array = biome.get("mobs", [])
		for i in n:
			var hp := 26.0 * s * rng.randf_range(0.8, 1.2)
			mobs.append({
				"name": "%sの魔物" % biome["name"],
				"hp": hp, "max_hp": hp, "atk": 2.2 * s, "boss": false,
				"sprite": "" if sprites.is_empty() else String(sprites[rng.randi(sprites.size())]),
			})
	state["mobs"] = mobs
	state["in_combat"] = true


func _combat_step(dt: float) -> void:
	var heroes: Array = state["heroes"]
	# スキル: 自動発動
	for h in heroes:
		if float(h["hp"]) <= 0.0:
			continue
		for id in h["skills_eq"]:
			var cd := float(h["cds"].get(id, 0.0)) - dt
			h["cds"][id] = cd
			if cd <= 0.0 and _cast_skill(h, id):
				h["cds"][id] = float(GameData.SKILL_DB[id]["cd"])
				if state["mobs"].is_empty():
					return
	# 通常攻撃: パーティDPSを先頭の敵へ。会心は期待値で適用
	var dps := 0.0
	for h in heroes:
		if float(h["hp"]) > 0.0:
			dps += hero_atk(h)
	_damage_mobs(dps * (1.0 + crit_chance()) * dt)
	if state["mobs"].is_empty():
		return
	# 敵の攻撃: 先頭の生存ヒーローが受ける（シールド優先）
	var matk := 0.0
	for m in state["mobs"]:
		matk += float(m["atk"])
	var tank := _first_alive()
	if tank.is_empty():
		return
	var dmg := matk * dt
	var sh := float(tank["shield"])
	if sh > 0.0:
		var used := minf(sh, dmg)
		tank["shield"] = sh - used
		dmg -= used
	tank["hp"] = float(tank["hp"]) - dmg
	if float(tank["hp"]) <= 0.0:
		tank["hp"] = 0.0
		state["run"]["deaths"] = int(state["run"]["deaths"]) + 1
		_emit("log", "%s が倒れた…" % tank["name"])
		if _first_alive().is_empty():
			_wipe()


func _first_alive() -> Dictionary:
	for h in state["heroes"]:
		if float(h["hp"]) > 0.0:
			return h
	return {}


func _cast_skill(h: Dictionary, id: String) -> bool:
	var def: Dictionary = GameData.SKILL_DB[id]
	var atk := hero_atk(h)
	match String(def["kind"]):
		"hit", "gold_hit":
			if state["mobs"].is_empty():
				return false
			_damage_mobs(atk * float(def["power"]))
			if def["kind"] == "gold_hit":
				var g := int(2.0 * GameData.area_scale(current_layer()) * gold_mult())
				state["gold"] = int(state["gold"]) + g
			return true
		"aoe":
			if state["mobs"].is_empty():
				return false
			_emit("fx", "", {"fx": "lightning" if id == "chain" else "explosion"})
			var per := atk * float(def["power"])
			for m in state["mobs"].duplicate():
				m["hp"] = float(m["hp"]) - per
			_sweep_dead_mobs()
			return true
		"heal_one":
			var target := _most_wounded()
			if target.is_empty():
				return false
			target["hp"] = minf(hero_maxhp(target), float(target["hp"]) + hero_maxhp(target) * float(def["power"]))
			return true
		"heal_all":
			var any := false
			for ally in state["heroes"]:
				var mx := hero_maxhp(ally)
				if float(ally["hp"]) > 0.0 and float(ally["hp"]) < mx:
					ally["hp"] = minf(mx, float(ally["hp"]) + mx * float(def["power"]))
					any = true
			return any
		"shield_all":
			for ally in state["heroes"]:
				if float(ally["hp"]) > 0.0:
					ally["shield"] = float(ally["shield"]) + hero_maxhp(ally) * float(def["power"])
			return true
	return false


func _most_wounded() -> Dictionary:
	var target := {}
	var worst := 1.0
	for h in state["heroes"]:
		if float(h["hp"]) <= 0.0:
			continue
		var ratio := float(h["hp"]) / hero_maxhp(h)
		if ratio < worst and ratio < 0.95:
			worst = ratio
			target = h
	return target


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


func _on_mob_killed(m: Dictionary) -> void:
	var s := GameData.area_scale(current_layer())
	var boss: bool = m["boss"]
	var g := int(5.0 * s * gold_mult() * (12.0 if boss else 1.0))
	state["gold"] = int(state["gold"]) + g
	state["run"]["kills"] = int(state["run"]["kills"]) + 1
	var xp := 8.0 * s * xp_mult() * (10.0 if boss else 1.0)
	for h in state["heroes"]:
		if float(h["hp"]) > 0.0:
			_grant_xp(h, xp)
	if boss or rng.chance(discover_chance()):
		_acquire_item(SimItems.roll(rng, current_layer(), _next_id()))
	if boss:
		state["chests"] = int(state["chests"]) + 1
		if rune_bonus("auto_chest") > 0.0:
			_open_one_chest()


func _end_combat() -> void:
	var was_boss := false
	state["in_combat"] = false
	var layer := current_layer()
	var gate := float(layer + 1) * GameData.LAYER_LENGTH
	if absf(float(state["distance"]) - (gate - 2.0)) < 0.5:
		was_boss = true
	for h in state["heroes"]:
		if float(h["hp"]) <= 0.0:
			h["hp"] = hero_maxhp(h) * 0.35
	if was_boss:
		state["distance"] = gate + 2.0
		state["checkpoint"] = layer + 1
		state["best_layer"] = maxi(int(state["best_layer"]), layer + 1)
		_emit("gate", "ゲート突破！ 第%d層へ（チェックポイント更新）" % (layer + 2))
	state["next_encounter"] = float(state["distance"]) + 30.0 + rng.randf() * 40.0


func _wipe() -> void:
	state["in_combat"] = false
	state["mobs"] = []
	state["distance"] = int(state["checkpoint"]) * GameData.LAYER_LENGTH
	state["retreat_cd"] = 8.0
	state["next_encounter"] = float(state["distance"]) + 50.0
	for h in state["heroes"]:
		h["hp"] = hero_maxhp(h) * 0.5
		h["shield"] = 0.0
	_emit("wipe", "全滅！ チェックポイント（第%d層）から再出発…" % (int(state["checkpoint"]) + 1))


# --- 経験値・加護 ------------------------------------------------------------


func _grant_xp(h: Dictionary, amount: float) -> void:
	h["xp"] = float(h["xp"]) + amount
	while float(h["xp"]) >= GameData.xp_needed(int(h["lv"])):
		h["xp"] = float(h["xp"]) - GameData.xp_needed(int(h["lv"]))
		h["lv"] = int(h["lv"]) + 1
		h["hp"] = hero_maxhp(h)
		_emit("level", "%s が Lv%d に！" % [h["name"], int(h["lv"])])
		_queue_blessing(h["name"])


func _queue_blessing(hero_name: String) -> void:
	if not state["pending_blessing"].is_empty():
		choose_blessing(0)
	var opts := []
	while opts.size() < 3:
		var i := rng.randi(GameData.BLESSINGS.size())
		if not i in opts:
			opts.append(i)
	state["pending_blessing"] = {"opts": opts, "timer": GameData.BLESSING_TIMEOUT, "hero": hero_name}
	_emit("blessing", "加護を選ぼう（15秒で自動選択）")


func _tick_blessing(dt: float) -> void:
	if state["pending_blessing"].is_empty():
		return
	var pb: Dictionary = state["pending_blessing"]
	pb["timer"] = float(pb["timer"]) - dt
	if float(pb["timer"]) <= 0.0:
		choose_blessing(0)


func choose_blessing(idx: int) -> void:
	var pb: Dictionary = state["pending_blessing"]
	if pb.is_empty():
		return
	var opt := int(pb["opts"][clampi(idx, 0, 2)])
	var b: Dictionary = GameData.BLESSINGS[opt]
	state["bless"][b["id"]] = float(state["bless"][b["id"]]) + float(b["val"])
	state["pending_blessing"] = {}
	_emit("blessing_done", "%s を得た（%s）" % [b["name"], b["desc"]])


# --- 宝箱 --------------------------------------------------------------------


func _tick_chests(dt: float) -> void:
	var interval := GameData.CHEST_INTERVAL * (1.0 - minf(rune_bonus("chest_interval"), 0.5))
	state["chest_progress"] = float(state["chest_progress"]) + dt
	while float(state["chest_progress"]) >= interval:
		state["chest_progress"] = float(state["chest_progress"]) - interval
		state["chests"] = int(state["chests"]) + 1
		_emit("log", "宝箱を見つけた！")
		if rune_bonus("auto_chest") > 0.0:
			_open_one_chest()


func open_chests() -> void:
	while int(state["chests"]) > 0:
		_open_one_chest()


func _open_one_chest() -> void:
	if int(state["chests"]) <= 0:
		return
	state["chests"] = int(state["chests"]) - 1
	var quality := rune_bonus("chest_quality")
	var s := GameData.area_scale(int(state["best_layer"]))
	var r := rng.randf()
	if r < 0.5:
		var g := int((40.0 + rng.randf() * 30.0) * s * gold_mult() * (1.0 + quality))
		state["gold"] = int(state["gold"]) + g
		_emit("log", "箱から %dG！" % g)
	elif r < 0.8:
		_acquire_item(SimItems.roll(rng, int(state["best_layer"]), _next_id(), quality))
	else:
		var dust := 5 + rng.randi(11) + int(quality * 10.0)
		state["stardust"] = int(state["stardust"]) + dust
		_emit("log", "箱から星屑 +%d" % dust)


# --- 装備・倉庫 --------------------------------------------------------------


func _next_id() -> int:
	var id := int(state["next_item_id"])
	state["next_item_id"] = id + 1
	return id


## 拾得時は自動装着（スコア比較で最も改善の大きいヒーローへ）。
func _acquire_item(item: Dictionary) -> void:
	state["run"]["items"] = int(state["run"]["items"]) + 1
	var best_gain := 0.0
	var best_idx := -1
	var heroes: Array = state["heroes"]
	for i in heroes.size():
		var cur: Dictionary = heroes[i]["equip"][item["slot"]]
		var cur_score := 0.0 if cur.is_empty() else float(cur["score"])
		var gain := float(item["score"]) - cur_score
		if gain > best_gain:
			best_gain = gain
			best_idx = i
	if best_idx >= 0:
		var old: Dictionary = heroes[best_idx]["equip"][item["slot"]]
		heroes[best_idx]["equip"][item["slot"]] = item
		if not old.is_empty():
			state["inventory"].append(old)
		_emit("loot", "%s が %s を装備" % [heroes[best_idx]["name"], SimItems.display_name(item)])
	else:
		state["inventory"].append(item)
		_emit("loot", "%s を入手" % SimItems.display_name(item))
	_trim_inventory()


func _trim_inventory() -> void:
	var inv: Array = state["inventory"]
	if inv.size() <= 150:
		return
	inv.sort_custom(func(a, b): return float(a["score"]) < float(b["score"]))
	while inv.size() > 150:
		var it: Dictionary = inv.pop_front()
		state["stardust"] = int(state["stardust"]) + SimItems.salvage_value(it)


func _find_inventory(item_id: int) -> int:
	var inv: Array = state["inventory"]
	for i in inv.size():
		if int(inv[i]["id"]) == item_id:
			return i
	return -1


## 休憩中の手動上書き装備。
func equip_from_inventory(item_id: int, hero_idx: int) -> bool:
	var i := _find_inventory(item_id)
	if i < 0 or hero_idx < 0 or hero_idx >= state["heroes"].size():
		return false
	var item: Dictionary = state["inventory"][i]
	state["inventory"].remove_at(i)
	var h: Dictionary = state["heroes"][hero_idx]
	var old: Dictionary = h["equip"][item["slot"]]
	h["equip"][item["slot"]] = item
	if not old.is_empty():
		state["inventory"].append(old)
	h["hp"] = minf(float(h["hp"]), hero_maxhp(h))
	return true


func salvage_item(item_id: int) -> int:
	var i := _find_inventory(item_id)
	if i < 0:
		return 0
	var dust := SimItems.salvage_value(state["inventory"][i])
	state["inventory"].remove_at(i)
	state["stardust"] = int(state["stardust"]) + dust
	return dust


## 一括分解: どのヒーローの装備改善にもならない品をまとめて星屑に。
func bulk_salvage() -> Dictionary:
	var inv: Array = state["inventory"]
	var keep := []
	var count := 0
	var dust := 0
	for it in inv:
		var useful := false
		for h in state["heroes"]:
			var cur: Dictionary = h["equip"][it["slot"]]
			if cur.is_empty() or float(cur["score"]) < float(it["score"]):
				useful = true
				break
		if useful:
			keep.append(it)
		else:
			count += 1
			dust += SimItems.salvage_value(it)
	state["inventory"] = keep
	state["stardust"] = int(state["stardust"]) + dust
	return {"count": count, "dust": dust}


## 合成: 同グレード3つ → 上位グレード1つ（スコアの低いものから消費）。
func synthesize_all() -> int:
	var made := 0
	for grade in range(GameData.GRADES.size() - 1):
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
			var item := SimItems.roll_graded(rng, int(state["best_layer"]), _next_id(), grade + 1)
			_emit("loot", "合成成功！ %s" % SimItems.display_name(item))
			state["inventory"].append(item)
			made += 1
	return made


## 刻印: 星屑50でアフィックス再抽選。
func reroll_item(item_id: int) -> bool:
	if int(state["stardust"]) < GameData.REROLL_COST:
		return false
	var i := _find_inventory(item_id)
	if i < 0:
		return false
	state["stardust"] = int(state["stardust"]) - GameData.REROLL_COST
	SimItems.reroll_affixes(rng, state["inventory"][i])
	_emit("log", "刻印した: %s %s" % [SimItems.display_name(state["inventory"][i]), SimItems.affix_text(state["inventory"][i])])
	return true


# --- ルーン・雇用 ------------------------------------------------------------


func rune_available(id: String) -> bool:
	if id in state["runes"]:
		return false
	for p in GameData.RT_NODES[id]["prev"]:
		if p in state["runes"]:
			return true
	return false


func unlock_rune(id: String) -> bool:
	if not rune_available(id):
		return false
	var cost := int(GameData.RT_NODES[id]["cost"])
	if int(state["gold"]) < cost:
		return false
	state["gold"] = int(state["gold"]) - cost
	state["runes"].append(id)
	_emit("log", "ルーン「%s」を解放（%s）" % [GameData.RT_NODES[id]["name"], GameData.RT_NODES[id]["desc"]])
	return true


func hire_cost() -> int:
	return int(800 * pow(4.0, state["heroes"].size() - 1))


func hire_hero() -> bool:
	if state["heroes"].size() >= party_limit():
		return false
	var cost := hire_cost()
	if int(state["gold"]) < cost:
		return false
	state["gold"] = int(state["gold"]) - cost
	var used := []
	for h in state["heroes"]:
		used.append(h["cls"])
	var candidates := []
	for cls in GameData.CLASSES:
		if not cls in used:
			candidates.append(cls)
	if candidates.is_empty():
		candidates = GameData.CLASSES.keys()
	var hero := _make_hero(candidates[rng.randi(candidates.size())])
	state["heroes"].append(hero)
	_emit("log", "%s（%s）が仲間になった！" % [hero["name"], GameData.CLASSES[hero["cls"]]["name"]])
	return true


func equip_skill(hero_idx: int, skill_id: String) -> bool:
	var h: Dictionary = state["heroes"][hero_idx]
	if skill_id in h["skills_eq"]:
		h["skills_eq"].erase(skill_id)
		return true
	if h["skills_eq"].size() >= skill_slots():
		return false
	if not skill_id in known_skills(h):
		return false
	h["skills_eq"].append(skill_id)
	return true


# --- 交易船・ペット ----------------------------------------------------------


## 10分毎に在庫入替。now は unix 秒。
func maybe_rotate_ship(now: float) -> void:
	var ship: Dictionary = state["ship"]
	if not ship["stock"].is_empty() and now - float(ship["rotated"]) < GameData.SHIP_ROTATE_SEC:
		return
	ship["rotated"] = now
	var stock := []
	for i in 3:
		var it := SimItems.roll(rng, int(state["best_layer"]) + 2, _next_id(), 0.5)
		stock.append({"type": "item", "item": it, "price": int(float(it["score"]) * 14.0)})
	for pid in GameData.PETS:
		if not pid in state["pets"] and rng.chance(0.34):
			stock.append({"type": "pet", "pet": pid, "price": int(GameData.PETS[pid]["cost"])})
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
		_emit("log", "%s を迎え入れた！" % GameData.PETS[entry["pet"]]["name"])
	else:
		_acquire_item(entry["item"])
	stock.remove_at(idx)
	return true


# --- オフライン報酬（安息） --------------------------------------------------


func apply_offline(now: float) -> Dictionary:
	var last := float(state["last_seen"])
	state["last_seen"] = now
	if last <= 0.0 or rune_bonus("offline") <= 0.0:
		return {}
	var away := clampf(now - last, 0.0, GameData.OFFLINE_CAP_SEC)
	if away < 120.0:
		return {}
	var s := GameData.area_scale(int(state["best_layer"]))
	var g := int(away * 0.5 * s * gold_mult())
	var xp := away * 0.4 * s * xp_mult()
	state["gold"] = int(state["gold"]) + g
	for h in state["heroes"]:
		_grant_xp(h, xp / state["heroes"].size())
	if not state["pending_blessing"].is_empty():
		choose_blessing(0)
	return {"away": away, "gold": g}


# --- ヒントバー（単一の推奨のみ。優先: 箱→スキル→最安ルーン→雇用） ----------


func hint() -> Dictionary:
	if int(state["chests"]) > 0:
		return {"tab": "inventory", "msg": "宝箱が %d 個。開けよう" % int(state["chests"])}
	for i in state["heroes"].size():
		var h: Dictionary = state["heroes"][i]
		if h["skills_eq"].size() < skill_slots():
			for id in known_skills(h):
				if not id in h["skills_eq"]:
					return {"tab": "party", "msg": "%s に「%s」を装備できる" % [h["name"], GameData.SKILL_DB[id]["name"]]}
	var cheapest := ""
	var cheapest_cost := 0
	for id in GameData.RT_NODES:
		if rune_available(id):
			var cost := int(GameData.RT_NODES[id]["cost"])
			if int(state["gold"]) >= cost and (cheapest == "" or cost < cheapest_cost):
				cheapest = id
				cheapest_cost = cost
	if cheapest != "":
		return {"tab": "runes", "msg": "ルーン「%s」を解放できる（%dG）" % [GameData.RT_NODES[cheapest]["name"], cheapest_cost]}
	if state["heroes"].size() < party_limit() and int(state["gold"]) >= hire_cost():
		return {"tab": "party", "msg": "新しいヒーローを雇える（%dG）" % hire_cost()}
	return {}
