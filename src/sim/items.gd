class_name SimItems
extends RefCounted
## 装備品の生成・評価。グレード7段階 × アフィックス0〜3個。
## スコアは自動装着（拾得時の比較）と倉庫の比較バッジに使う。


static func roll(rng: SimRNG, layer: int, id_num: int, quality_bonus: float = 0.0) -> Dictionary:
	var grade := _roll_grade(rng, layer, quality_bonus)
	return roll_graded(rng, layer, id_num, grade)


## グレードを固定して生成（合成用）。
static func roll_graded(rng: SimRNG, layer: int, id_num: int, grade: int) -> Dictionary:
	var slot_keys: Array = GameData.SLOTS.keys()
	var slot: String = slot_keys[rng.randi(slot_keys.size())]
	var mult: float = GameData.GRADES[grade]["mult"]
	var base := snappedf(mult * (6.0 + layer * 2.0) * rng.randf_range(0.85, 1.15), 0.1)
	var item := {
		"id": id_num,
		"slot": slot,
		"grade": grade,
		"base": base,
		"affixes": _roll_affixes(rng, _roll_affix_count(rng, grade)),
	}
	item["score"] = score(item)
	return item


## 刻印: 星屑でアフィックスを再抽選（個数は最低1を保証）。
static func reroll_affixes(rng: SimRNG, item: Dictionary) -> void:
	var count: int = maxi(1, item["affixes"].size())
	item["affixes"] = _roll_affixes(rng, count)
	item["score"] = score(item)


static func score(item: Dictionary) -> float:
	var s: float = float(item["base"]) * 2.0
	for a in item["affixes"]:
		s += float(a["v"])
	return snappedf(s, 0.1)


static func grade_name(item: Dictionary) -> String:
	return GameData.GRADES[int(item["grade"])]["name"]


static func display_name(item: Dictionary) -> String:
	var slot_name: String = GameData.SLOTS[item["slot"]]["name"]
	var n := "【%s】%s" % [grade_name(item), slot_name]
	if not item["affixes"].is_empty():
		n += " +%d" % item["affixes"].size()
	return n


static func affix_text(item: Dictionary) -> String:
	var parts: Array[String] = []
	for a in item["affixes"]:
		parts.append("%s+%d%%" % [GameData.AFFIXES[a["t"]]["name"], int(a["v"])])
	return " ".join(parts)


static func salvage_value(item: Dictionary) -> int:
	var g := int(item["grade"])
	return 1 + g * 2 + (4 if g >= 4 else 0)


static func _roll_grade(rng: SimRNG, layer: int, quality_bonus: float) -> int:
	var p := clampf(0.30 + layer * 0.012 + quality_bonus * 0.1, 0.30, 0.55)
	var grade := 0
	while grade < GameData.GRADES.size() - 1 and rng.chance(p):
		grade += 1
	return grade


static func _roll_affix_count(rng: SimRNG, grade: int) -> int:
	var r := rng.randf()
	var count := 0
	if r >= 0.92:
		count = 3
	elif r >= 0.75:
		count = 2
	elif r >= 0.45:
		count = 1
	if grade >= 4:
		count = maxi(count, 1)
	return count


static func _roll_affixes(rng: SimRNG, count: int) -> Array:
	var keys: Array = GameData.AFFIXES.keys()
	var affixes := []
	for i in count:
		var t: String = keys[rng.randi(keys.size())]
		var spec: Dictionary = GameData.AFFIXES[t]
		affixes.append({"t": t, "v": rng.randi_range(int(spec["min"]), int(spec["max"]))})
	return affixes
