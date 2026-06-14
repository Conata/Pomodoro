class_name ShopSim
extends RefCounted
## お店モード（放置＝非集中時）の接客ライブ・シミュレーション。
## close_day() の一括精算（客数=8+看板／capacity=min(客,仕込み)／味マッチ単価1.2倍／
## 店番シナジー／好感度）を、時間進行に作り替えたもの。デイブ・ザ・ダイバー的：
## 客が時間とともに来店→注文→調理→会計し、素材切れと待たせ過ぎが収益を縛る。
##
## 決定論：乱数は sim.rng を使うので、セーブ/リプレイの再現性を壊さない。
## ロジックのみ（エンジン非依存）。ビューは src/ui/shop_view.gd（別途）。

# 1 サービス窓 = この秒数で「8+看板」人を捌くのが基準（close_day と釣り合う）。
const SERVICE_WINDOW := 300.0
const PATIENCE := 75.0      # 待てる秒数（超えると帰る）
const COOK_MIN := 4.0       # 1 皿の最短調理秒
const COOK_MAX := 40.0

var sim                      # KuroSim
var open := false
var elapsed := 0.0
var _spawn_acc := 0.0

# サービス・パラメータ（開店時に close_day と同式で確定）
var demand := 8             # 想定客数（到着レートの基），= 8 + 看板 + フラグ
var prep := 9              # 仕込み能力（throughput の基）
var price_mult := 1.0
var synergies: Array[String] = []
var arrival_interval := 30.0
var cook_time := 15.0
var cook_slots := 1
var keeper := "mil"
var forecast := ""

# 進行状態
var queue: Array = []       # 客 {id,state,dish,wait,cook_left}
var _next_id := 0
var served := 0
var turned_away := 0
var left_angry := 0
var gold_earned := 0
var matched := 0
var counts := {}            # dish -> 杯数
var _sold_tastes := {}
var _events: Array = []


func _init(kuro_sim) -> void:
	sim = kuro_sim


## 暖簾を出す。close_day と同じ式でサービス・パラメータを確定する。
func open_shop() -> void:
	var st: Dictionary = sim.state
	keeper = String(st["morning"]["keeper"])
	forecast = String(st["forecast"])
	var menu: Array = st["morning"]["menu"]
	synergies = []

	# 仕込み：店番適性×好感度（close_day と同式）
	var apt := float(KuroData.GIRLS[keeper]["keeper_apt"])
	prep = int((9.0 + 5.0 * apt) * KuroData.girl_mult(sim.aff(keeper)))
	# 客数 =(8+看板)×フラグ補正
	demand = 8 + sim.sign_total()
	if "tao" in st["buffs"]:
		demand += 2
	if int(st["invites"]) > 0:
		demand += 3 * int(st["invites"])
		st["invites"] = 0
	if keeper == "muu":
		demand += 4
		synergies.append("店内ライブ")
	var tastes := {}
	for id in menu:
		var t: String = KuroData.RECIPES[id]["taste"]
		tastes[t] = int(tastes.get(t, 0)) + 1
	for t in tastes:
		if int(tastes[t]) >= 3:
			demand += 3
			synergies.append("ご当地フェア")
			break
	if st["crowd_penalty"]:
		demand = int(demand * 0.6)
		st["crowd_penalty"] = false
	if keeper == "yuzuki":
		prep = int(prep * 1.35)
		synergies.append("解析いらずの仕込み")
	price_mult = 1.0
	if keeper == "mil":
		price_mult *= 1.10
		synergies.append("静かな給仕")
	if tastes.size() >= 4:
		price_mult *= 1.15
		synergies.append("フルコース")
	if keeper == "kiriko":
		synergies.append("解析仕込み")

	demand = maxi(demand, 1)
	prep = maxi(prep, 1)
	arrival_interval = clampf(SERVICE_WINDOW / float(demand), 2.0, 90.0)
	cook_time = clampf(SERVICE_WINDOW / float(prep), COOK_MIN, COOK_MAX)
	cook_slots = 1 + (1 if prep >= 15 else 0) + (1 if prep >= 25 else 0)

	open = true
	elapsed = 0.0
	_spawn_acc = arrival_interval  # 開店直後に最初の一人
	queue.clear()
	served = 0; turned_away = 0; left_angry = 0; gold_earned = 0; matched = 0
	counts = {}; _sold_tastes = {}; _events.clear()
	_emit({"kind": "open", "demand": demand, "prep": prep, "synergies": synergies.duplicate()})


## 1 ステップ進める（dt 秒）。固定ステップで呼ぶ（KuroData.SIM_DT 推奨）。
func step(dt: float) -> void:
	if not open:
		return
	elapsed += dt
	# 来店
	_spawn_acc += dt
	while _spawn_acc >= arrival_interval:
		_spawn_acc -= arrival_interval
		_spawn()
	# 調理の進行
	for c in queue:
		if c["state"] == "cook":
			c["cook_left"] -= dt
			if c["cook_left"] <= 0.0:
				_finish(c)
	_compact()
	# 空き調理枠を待ち客へ割り当て（FIFO・素材があるものだけ）
	var cooking := 0
	for c in queue:
		if c["state"] == "cook":
			cooking += 1
	var free := cook_slots - cooking
	for c in queue:
		if free <= 0:
			break
		if c["state"] != "wait":
			continue
		var dish := _pick_cookable()
		if dish == "":
			break  # 今は何も作れない（素材切れ）。待ち客は待機継続
		c["dish"] = dish
		c["state"] = "cook"
		c["cook_left"] = cook_time
		var ing: String = KuroData.RECIPES[dish]["ing"]
		sim.state["stock"][ing] = int(sim.state["stock"][ing]) - 1
		free -= 1
		_emit({"kind": "order", "id": c["id"], "dish": dish})
	# 待ちくたびれて帰る
	for c in queue:
		if c["state"] == "wait":
			c["wait"] += dt
			if c["wait"] > PATIENCE:
				c["state"] = "gone"
				left_angry += 1
				_emit({"kind": "leave", "id": c["id"]})
	_compact()


## 長時間の離席を一気に進める（catch-up）。上限内でループ。
func fast_forward(seconds: float, dt := 0.25) -> void:
	var n := int(min(seconds, SERVICE_WINDOW * 4.0) / dt)
	for i in n:
		step(dt)


func _spawn() -> void:
	# 出せる料理が献立に1つも無い（在庫以前にメニュー空）なら門前払い
	if sim.state["morning"]["menu"].is_empty():
		turned_away += 1
		_emit({"kind": "turn_away"})
		return
	var c := {"id": _next_id, "state": "wait", "dish": "", "wait": 0.0, "cook_left": 0.0}
	_next_id += 1
	queue.append(c)
	_emit({"kind": "arrive", "id": c["id"]})


## 今つくれる料理を予報重みで1つ選ぶ（close_day の pool と同じ重み付け）。
func _pick_cookable() -> String:
	var menu: Array = sim.state["morning"]["menu"]
	var stock: Dictionary = sim.state["stock"]
	var pool := []
	for id in menu:
		if int(stock.get(KuroData.RECIPES[id]["ing"], 0)) <= 0:
			continue
		var w := 1.0 + (2.0 if KuroData.RECIPES[id]["taste"] == forecast else 0.0)
		for k in int(w * 2.0):
			pool.append(id)
	if pool.is_empty():
		return ""
	return pool[sim.rng.randi(pool.size())]


func _finish(c: Dictionary) -> void:
	var dish: String = c["dish"]
	c["state"] = "done"
	served += 1
	var star := int(sim.state["recipes"].get(dish, 1))
	var taste: String = KuroData.RECIPES[dish]["taste"]
	var is_match := taste == forecast or keeper == "kiriko"
	if taste == forecast:
		matched += 1
	var price := KuroData.recipe_price(dish, star) * price_mult * (1.2 if is_match else 1.0)
	var g := int(price * sim.gold_mult() * KuroData.NIGHT_GOLD_SCALE * sim.gain_mult())
	gold_earned += g
	sim.state["gold"] = int(sim.state["gold"]) + g
	counts[dish] = int(counts.get(dish, 0)) + 1
	_sold_tastes[taste] = true
	_emit({"kind": "served", "id": c["id"], "dish": dish, "gold": g})


func _compact() -> void:
	var keep := []
	for c in queue:
		if c["state"] == "wait" or c["state"] == "cook":
			keep.append(c)
	queue = keep


## 暖簾を下ろす。close_day と同じ後処理（好感度・住民ストーリー）＋三行サマリ。
func close_shop() -> Dictionary:
	open = false
	# 好感度：ダイブ同行+2／店番+1／好物の味が売れた夜+2
	for id in sim.divers():
		sim.add_aff(id, 2)
	sim.add_aff(keeper, 1)
	for id in KuroData.GIRL_ORDER:
		if _sold_tastes.get(KuroData.GIRLS[id]["fav"], false):
			sim.add_aff(id, 2)
	# 特注→住民ストーリー発火→永続バフ
	var story := ""
	for dish in counts:
		var recipe: Dictionary = KuroData.RECIPES[dish]
		if recipe.has("resident") and not recipe["resident"] in sim.state["buffs"]:
			sim.state["buffs"].append(recipe["resident"])
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
	var line1 := "客%d人、%d皿。%s" % [served + left_angry + turned_away, served,
			("%sが一番出た" % top) if top != "" else "今夜は静かだった"]
	if left_angry > 0:
		line1 += "（%d人は待ちきれず帰った）" % left_angry
	var line2 := "売上 +%dG — 予報『%s』%d皿的中%s" % [gold_earned, forecast, matched,
			("／" + "・".join(synergies)) if not synergies.is_empty() else ""]
	var night := {
		"lines": [line1, line2, ""], "gold": gold_earned, "served": served,
		"left": left_angry, "story": story, "talk_done": false,
	}
	sim.state["pending_night"] = night
	return night


func drain_events() -> Array:
	var e := _events
	_events = []
	return e


func _emit(ev: Dictionary) -> void:
	_events.append(ev)
