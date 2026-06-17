class_name SimItems
extends RefCounted
## 装備品（TBH実仕様：グレード7段階 × アフィックス0〜3個）。
## 拾得時は自動装着（スコア比較）、分解で廃材、刻印（廃材50）で再抽選、
## 同グレード3つで合成→上位1つ。

const GRADES := [
	{"name": "粗末", "mult": 1.0, "color": Color(0.55, 0.6, 0.7)},
	{"name": "普通", "mult": 1.4, "color": Color(0.8, 0.85, 0.95)},
	{"name": "上質", "mult": 2.0, "color": Color(0.45, 0.9, 0.6)},
	{"name": "精錬", "mult": 3.0, "color": Color(0.45, 0.7, 1.0)},
	{"name": "英雄", "mult": 4.5, "color": Color(0.8, 0.5, 1.0)},
	{"name": "伝説", "mult": 7.0, "color": Color(1.0, 0.7, 0.3)},
	{"name": "星界", "mult": 11.0, "color": Color(0.5, 1.0, 0.95)},
]

const SLOTS := {
	"weapon": {"name": "武器", "atk": 1.0, "hp": 0.0},
	"armor": {"name": "防具", "atk": 0.0, "hp": 5.0},
	"trinket": {"name": "装飾", "atk": 0.4, "hp": 2.0},
}

# アフィックス値は%ポイント
const AFFIXES := {
	"atk": {"name": "攻", "min": 4, "max": 12},
	"hp": {"name": "体", "min": 4, "max": 12},
	"spd": {"name": "速", "min": 2, "max": 6},
	"gold": {"name": "金", "min": 3, "max": 10},
	"mat": {"name": "材", "min": 2, "max": 6},
	"crit": {"name": "会", "min": 2, "max": 8},
}

const REROLL_COST := 50  # 刻印＝廃材50


static func roll(rng: SimRNG, floor_idx: int, id_num: int, quality_bonus: float = 0.0) -> Dictionary:
	return roll_graded(rng, floor_idx, id_num, _roll_grade(rng, floor_idx, quality_bonus))


static func roll_graded(rng: SimRNG, floor_idx: int, id_num: int, grade: int) -> Dictionary:
	var slot_keys: Array = SLOTS.keys()
	var slot: String = slot_keys[rng.randi(slot_keys.size())]
	var mult: float = GRADES[grade]["mult"]
	var base := snappedf(mult * (5.0 + floor_idx * 1.8) * rng.randf_range(0.85, 1.15), 0.1)
	# EQUIP_DB から表示名テンプレートを選択
	var tpl_keys: Array = KuroData.EQUIP_BY_SLOT[slot]
	var tpl: String = tpl_keys[rng.randi(tpl_keys.size())]
	var item := {
		"id": id_num, "slot": slot, "grade": grade, "base": base,
		"tpl": tpl,
		"affixes": _roll_affixes(rng, _roll_affix_count(rng, grade)),
	}
	# 英雄(4)以上はソケット枠を持つ（容量は socket_capacity 参照）。
	if grade >= 4:
		item["sockets"] = []
	item["score"] = score(item)
	return item


# ソケット枠数：英雄(4)で1枠、伝説(5)以上で2枠。
static func socket_capacity(grade: int) -> int:
	if grade >= 5:
		return 2
	if grade >= 4:
		return 1
	return 0


static func reroll_affixes(rng: SimRNG, item: Dictionary) -> void:
	item["affixes"] = _roll_affixes(rng, maxi(1, item["affixes"].size()))
	item["score"] = score(item)


static func score(item: Dictionary) -> float:
	var s: float = float(item["base"]) * 2.0
	for a in item["affixes"]:
		s += float(a["v"])
	# 嵌めたソケット宝石（slot 別ステ）もスコアに反映。
	for gem_key in item.get("sockets", []):
		var slot_stats: Dictionary = KuroData.SOCKET_GEMS.get(gem_key, {}).get(item["slot"], {})
		for v in slot_stats.values():
			s += float(v)
	return snappedf(s, 0.1)


# 装備の合計ステを集計（base/score＋アフィックス＋ソケット宝石）。比較表示用。
static func stat_summary(item: Dictionary) -> Dictionary:
	var sum := {"base": 0.0, "score": 0.0, "atk": 0, "hp": 0, "spd": 0, "gold": 0, "mat": 0, "crit": 0}
	if item.is_empty():
		return sum
	sum["base"] = float(item.get("base", 0.0))
	sum["score"] = float(item.get("score", 0.0))
	for a in item.get("affixes", []):
		sum[a["t"]] = int(sum.get(a["t"], 0)) + int(a["v"])
	for gem_key in item.get("sockets", []):
		var slot_stats: Dictionary = KuroData.SOCKET_GEMS.get(gem_key, {}).get(item.get("slot", ""), {})
		for k in slot_stats:
			sum[k] = int(sum.get(k, 0)) + int(slot_stats[k])
	return sum


static func display_name(item: Dictionary) -> String:
	var tpl_id: String = item.get("tpl", "")
	var n: String
	if KuroData.EQUIP_DB.has(tpl_id):
		n = KuroData.EQUIP_DB[tpl_id]["name"]
	else:
		n = "【%s】%s" % [GRADES[int(item["grade"])]["name"], SLOTS[item["slot"]]["name"]]
	if int(item["grade"]) >= 4:
		n += " ★"
	if not item["affixes"].is_empty():
		n += " +%d" % item["affixes"].size()
	return n


static func affix_text(item: Dictionary) -> String:
	var parts: Array[String] = []
	for a in item["affixes"]:
		parts.append("%s+%d%%" % [AFFIXES[a["t"]]["name"], int(a["v"])])
	return " ".join(parts)


static func salvage_value(item: Dictionary) -> int:
	var g := int(item["grade"])
	return 1 + g * 2 + (4 if g >= 4 else 0)


static func _roll_grade(rng: SimRNG, floor_idx: int, quality_bonus: float) -> int:
	var p := clampf(0.30 + floor_idx * 0.015 + quality_bonus * 0.1, 0.30, 0.55)
	var grade := 0
	while grade < GRADES.size() - 1 and rng.chance(p):
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
	var keys: Array = AFFIXES.keys()
	var affixes := []
	for i in count:
		var t: String = keys[rng.randi(keys.size())]
		var spec: Dictionary = AFFIXES[t]
		affixes.append({"t": t, "v": rng.randi_range(int(spec["min"]), int(spec["max"]))})
	return affixes
