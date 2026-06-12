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
	if not parsed is Dictionary or parsed.get("v", "") != "v3":
		return {}
	return normalize(parsed)


static func normalize(s: Dictionary) -> Dictionary:
	for key in ["gold", "stock", "sign", "invites", "day", "checkpoint", "best_floor", "rng_state", "seed"]:
		if s.has(key):
			s[key] = int(s[key])
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
		for key in ["mats", "gold0", "kills", "resyncs", "banked"]:
			s["run"][key] = int(s["run"].get(key, 0))
	return s
