class_name SaveGame
extends RefCounted
## セーブ/ロード。key は HTML 版と同じ kuroneko-v3 系（DESIGN.md セーブ）。
## JSON 経由で int が float になるため、ロード時に既知フィールドを正規化する。

const PATH := "user://kuroneko-v3.json"

# ── 音の設定 ────────────────────────────────────────────────────────────────
# スライダーはこのプロジェクトに無いので、音量は5段の段階選択で持つ。
# ここは「何を保存するか」だけを決める。実際にどう鳴らすか（バスの dB）は
# main.gd の _apply_audio() が1箇所で受け持つ。
const AUDIO_STEPS := [0, 25, 50, 75, 100]
const AUDIO_DEFAULT := {"sfx": 100, "bgm": 75, "mute": false}


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
			"rng_state", "seed", "scrap", "next_item_id", "streak", "shards",
			"workshop_level"]:
		if s.has(key):
			s[key] = int(s[key])
	if not s.has("shards"):
		s["shards"] = 0
	# 工房レベル（1=分解 / 2=合成 / 3=刻印 / 4=装飾 / 5=精錬）。既定は Lv1。
	if not s.has("workshop_level"):
		s["workshop_level"] = 1
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
	# 新規追加キャラがセーブに無い場合、デフォルト値で補完
	if not s.has("girls"):
		s["girls"] = {}
	for id in KuroData.GIRL_ORDER:
		if not s["girls"].has(id):
			var first_skill := ""
			for sid in KuroData.SKILL_DB:
				if KuroData.SKILL_DB[sid]["girl"] == id and int(KuroData.SKILL_DB[sid]["unlock"]) == 0:
					first_skill = sid
					break
			s["girls"][id] = {
				"aff": 10, "seen": [],
				"equip": {"weapon": {}, "armor": {}, "trinket": {}},
				"skills_eq": [first_skill],
				"tree": [],
			}
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
	for key_def in [["scrap", 0], ["next_item_id", 1], ["streak", 0], ["chest_progress", 0.0],
			["manual_skill", false], ["difficulty", 0], ["stage_sel", -1]]:
		if not s.has(key_def[0]):
			s[key_def[0]] = key_def[1]
	if not s.has("inventory"):
		s["inventory"] = []
	if not s.has("storage"):
		s["storage"] = []
	_normalize_items(s.get("storage", []))
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
	if not s.has("finale_pick"):
		s["finale_pick"] = ""
	if not s.has("memories"):
		s["memories"] = []
	if not s.get("stage_clear") is Dictionary:
		s["stage_clear"] = {}
	for d in 4:
		s["stage_clear"][str(d)] = int((s["stage_clear"] as Dictionary).get(str(d), -1))
	s["difficulty"] = int(s.get("difficulty", 0))
	s["stage_sel"] = int(s.get("stage_sel", -1))
	normalize_audio(s)   # 音の設定が無い古いセーブでも既定値で通す
	return s


## 音の設定を既定値で補い、段階に吸着させて返す（戻り値＝正規化後の辞書）。
## normalize から呼ぶほか、main.gd が新規開始時にも直接呼ぶ
## （新規状態は KuroSim.new_state が作り、normalize を通らないため）。
## JSON 経由で int が float になる・型が壊れている・未知の値が入っている、の
## どれでも落ちないこと＝ここに来る値は一切信用しない。
static func normalize_audio(s: Dictionary) -> Dictionary:
	var raw: Dictionary = s["audio"] if s.get("audio") is Dictionary else {}
	var a := {
		"sfx": audio_snap(raw.get("sfx", AUDIO_DEFAULT["sfx"]), int(AUDIO_DEFAULT["sfx"])),
		"bgm": audio_snap(raw.get("bgm", AUDIO_DEFAULT["bgm"]), int(AUDIO_DEFAULT["bgm"])),
		"mute": _audio_bool(raw.get("mute", AUDIO_DEFAULT["mute"])),
	}
	s["audio"] = a
	return a


## 真偽値の復元。bool("yes") は Godot 4 に存在せず落ちるので、型を見てから畳む。
static func _audio_bool(v: Variant) -> bool:
	if v is bool:
		return v
	if v is int or v is float:
		return float(v) != 0.0
	if v is String:
		return String(v).to_lower() in ["true", "1", "yes", "on"]
	return false


## 任意の値を AUDIO_STEPS のいずれかへ吸着（範囲外は最寄りの段、数値でなければ既定）。
static func audio_snap(v: Variant, def := 100) -> int:
	var n := def
	if v is int or v is float:
		n = int(round(float(v)))
	elif v is String and (v as String).is_valid_float():
		n = int(round(float(v)))
	var best: int = AUDIO_STEPS[0]
	for step in AUDIO_STEPS:
		if absi(int(step) - n) < absi(best - n):
			best = int(step)
	return best


static func _normalize_items(items: Array) -> void:
	for it in items:
		_normalize_item(it)


static func _normalize_item(it: Dictionary) -> void:
	it["id"] = int(it.get("id", 0))
	it["grade"] = int(it.get("grade", 0))
	# base は SimItems が使う float。str 変換しない
	if it.has("base") and it["base"] is String:
		it["base"] = float(it["base"])
	# tpl = EQUIP_DB テンプレートキー（表示名用）
	if it.has("tpl"):
		it["tpl"] = str(it["tpl"])
	for a in it.get("affixes", []):
		a["v"] = int(a.get("v", 0))
