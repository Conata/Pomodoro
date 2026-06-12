class_name SaveGame
extends RefCounted
## セーブ/ロード。key 名は HTML版と同じ pomohero-v7 系（DESIGN.md セーブ）。
## JSON経由で int が float になるため、ロード時に既知フィールドを正規化する。

const PATH := "user://pomohero-v7.json"


static func save_state(state: Dictionary) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("セーブに失敗: " + PATH)
		return
	f.store_string(JSON.stringify(state))
	f.close()


static func load_state() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary or parsed.get("v", "") != "v7":
		return {}
	return normalize(parsed)


static func normalize(s: Dictionary) -> Dictionary:
	for key in ["gold", "stardust", "chests", "next_item_id", "checkpoint", "best_layer", "streak", "rng_state", "seed"]:
		if s.has(key):
			s[key] = int(s[key])
	if s.has("daily"):
		s["daily"]["runs"] = int(s["daily"].get("runs", 0))
	if s.has("stats"):
		s["stats"]["runs"] = int(s["stats"].get("runs", 0))
	if s.has("run"):
		for key in ["gold0", "items", "kills", "deaths"]:
			s["run"][key] = int(s["run"].get(key, 0))
	for h in s.get("heroes", []):
		_normalize_hero(h)
	_normalize_items(s.get("inventory", []))
	for entry in s.get("ship", {}).get("stock", []):
		entry["price"] = int(entry.get("price", 0))
		if entry.has("item"):
			_normalize_item(entry["item"])
	return s


static func _normalize_hero(h: Dictionary) -> void:
	h["lv"] = int(h.get("lv", 1))
	for slot in h.get("equip", {}):
		var it: Dictionary = h["equip"][slot]
		if not it.is_empty():
			_normalize_item(it)


static func _normalize_items(items: Array) -> void:
	for it in items:
		_normalize_item(it)


static func _normalize_item(it: Dictionary) -> void:
	it["id"] = int(it.get("id", 0))
	it["grade"] = int(it.get("grade", 0))
	for a in it.get("affixes", []):
		a["v"] = int(a.get("v", 0))
