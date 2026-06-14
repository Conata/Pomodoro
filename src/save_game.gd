class_name SaveGame
extends RefCounted
## セーブ/ロード。key は HTML 版と同じ kuroneko-v3 系（DESIGN.md セーブ）。
## JSON 経由で int が float になるため、ロード時に既知フィールドを正規化する。

const PATH := "user://kuroneko-v3.json"


static func save_state(state: Dictionary) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("セーブに失敗: " + PATH)
		return
	# full_precision=true: 浮動小数を正確に保存しないと、復元後に
	# 蓄積カウンタ（dist/chest_progress/cd）がずれて決定論が壊れる
	f.store_string(JSON.stringify(state, "", false, true))
	f.close()


static func load_state() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary or parsed.get("v", "") != "v3":
		return {}
	return normalize(parsed)


static func normalize(s: Dictionary) -> Dictionary:
	for key in ["gold", "sign", "invites", "day", "checkpoint", "best_floor",
			"rng_state", "seed", "scrap", "next_item_id", "streak", "shards"]:
		if s.has(key):
			s[key] = int(s[key])
	if not s.has("shards"):
		s["shards"] = 0
	# 素材：旧セーブ（無個性カウント）からの移行も吸収
	if s.get("stock") is float or s.get("stock") is int:
		s["stock"] = {"dry": int(s["stock"]), "meat": 0, "sea": 0}
	elif s.get("stock") is Dictionary:
		for ing in ["dry", "meat", "sea"]:
			s["stock"][ing] = int(s["stock"].get(ing, 0))
	else:
		s["stock"] = {"dry": 8, "meat": 2, "sea": 2}
	if s.has("daily"):
		s["daily"]["runs"] = int(s["daily"].get("runs", 0))
	_normalize_items(s.get("inventory", []))
	for entry in s.get("ship", {}).get("stock", []):
		entry["price"] = int(entry.get("price", 0))
		if entry.has("item"):
			_normalize_item(entry["item"])
	var boxes := []
	for g in s.get("boxes", []):
		boxes.append(int(g))
	s["boxes"] = boxes
	for id in s.get("girls", {}):
		s["girls"][id]["aff"] = int(s["girls"][id].get("aff", 10))
		var seen := []
		for t in s["girls"][id].get("seen", []):
			seen.append(int(t))
		s["girls"][id]["seen"] = seen
		if not s["girls"][id].has("equip"):
			s["girls"][id]["equip"] = {"weapon": {}, "armor": {}, "trinket": {}}
		if not s["girls"][id].has("skills_eq"):
			s["girls"][id]["skills_eq"] = []
		if not s["girls"][id].has("tree"):
			s["girls"][id]["tree"] = []
		for slot in s["girls"][id]["equip"]:
			if not s["girls"][id]["equip"][slot].is_empty():
				_normalize_item(s["girls"][id]["equip"][slot])
	for id in s.get("recipes", {}):
		s["recipes"][id] = int(s["recipes"][id])
	var doors := []
	for d in s.get("doors_done", []):
		doors.append(int(d))
	s["doors_done"] = doors
	if s.has("run"):
		var rb := []
		for g in s["run"].get("boxes", []):
			rb.append(int(g))
		s["run"]["boxes"] = rb
		for key in ["gold0", "kills", "resyncs", "banked"]:
			s["run"][key] = int(s["run"].get(key, 0))
		if s["run"].get("mats") is Dictionary:
			for ing in ["dry", "meat", "sea"]:
				s["run"]["mats"][ing] = int(s["run"]["mats"].get(ing, 0))
		else:
			s["run"]["mats"] = {"dry": int(s["run"].get("mats", 0)), "meat": 0, "sea": 0}
	# v4初期セーブ（装備システム導入前）との互換
	for key_def in [["scrap", 0], ["next_item_id", 1], ["streak", 0], ["chest_progress", 0.0]]:
		if not s.has(key_def[0]):
			s[key_def[0]] = key_def[1]
	if not s.has("inventory"):
		s["inventory"] = []
	if not s.has("renov"):
		s["renov"] = ["start"]
	if not s.has("pets"):
		s["pets"] = []
	if not s.has("cds"):
		s["cds"] = {}
	if not s.has("daily"):
		s["daily"] = {"date": "", "runs": 0, "claimed": false}
	if not s.has("weekly"):
		s["weekly"] = {}
	if not s.has("ship"):
		s["ship"] = {"stock": [], "rotated": 0.0}
	if not s.has("events_seen"):
		s["events_seen"] = []
	if not s.has("memories"):
		s["memories"] = []
	return s


static func _normalize_items(items: Array) -> void:
	for it in items:
		_normalize_item(it)


static func _normalize_item(it: Dictionary) -> void:
	it["id"] = int(it.get("id", 0))
	it["grade"] = int(it.get("grade", 0))
	for a in it.get("affixes", []):
		a["v"] = int(a.get("v", 0))
