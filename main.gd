extends Control
## 黒猫飯店 — メインUI（DESIGN.md v4 / WORLD.md 準拠）。
## 1日のループ：朝30秒（編成・献立・扉方針）→ ダイブ（クイック80秒 or
## ポモドーロ15/25/50分）→ 浮上と同時に三行精算 → 箱開封 → 会話 → 翌朝。
## タイマーは unix 秒アンカー＋固定ステップのキャッチアップ
## （タブ非アクティブでも正確。壊すと製品価値が消える部分）。

enum Phase { MORNING, DIVE, CAMP, NIGHT }  # CAMP=休憩(焚き火)。旧CLOSEを転用

# デザインシステム（src/ui/ds.gd）から引く。色・型・間隔の唯一の真実は DS。
const COL_BG := DS.BG
const COL_PANEL := DS.SURFACE
const COL_EDGE := DS.ACCENT
const COL_TEXT := DS.TEXT
const COL_DIM := DS.TEXT_2
const COL_ACCENT := DS.ACCENT       # 識別色（シアン）= この店のアイデンティティ
const COL_WARM := DS.WARM           # 店番・ネオン看板の暖色アクセント
const TYPE_SMALL := DS.T_MICRO
const TYPE_BODY := DS.T_BODY
const TYPE_SUB := DS.T_SUB
const TYPE_HEAD := DS.T_HEAD
const TYPE_DISPLAY := DS.T_DISPLAY
const SP_1 := DS.SP_1
const SP_2 := DS.SP_2
const SP_3 := DS.SP_3
const SP_4 := DS.SP_4

var sim: KuroSim
var phase: int = Phase.MORNING
var dive_minutes := 25.0
var dive_mode := "pomo"
var save_accum := 0.0
var log_count := 0
var pending_confirm := Callable()
var result_summary := {}
var night_data := {}
var shop: ShopSim = null          # お店モードのライブ接客（NIGHT中に稼働）
var shop_status: Label            # 「営業中 …」のライブ表示

var header_panel: PanelContainer
var header_bar: HBoxContainer
var dive: DiveView
var dive_frame: PanelContainer
var dive_chrome: DiveChrome        # ポスト処理の上に重ねる配信UI（常にクッキリ）
var post_bbc: BackBufferCopy       # 探索ステージのスクリーンコピー
var post_fx: ColorRect             # カラグレ/ブルーム/DoFのポスト処理オーバーレイ
var post_mat: ShaderMaterial
var content_box: BoxContainer     # 縦(モバイル)/横(PC)で並びを切替える responsive 容器
var stage_col: VBoxContainer      # 左：店先/潜行ビュー＋タイマー
var panel_col: VBoxContainer      # 右：操作パネル＋タブ
var talk_view: TalkView
var timer_box: VBoxContainer
var timer_label: Label
var status_label: Label
var morning_panel: Control
var morning_box: VBoxContainer
var home_scene: VBoxContainer      # 店の主役＝店内シーン（イラスト）
var store_top: VBoxContainer       # 営業ライブ＋依頼＋本日の献立（動的）
var ops_box: VBoxContainer         # 経営：箱/会話/闇市/交易船/好感度（動的）
var girls_box: VBoxContainer
var menu_box: VBoxContainer
var menu_title: Label
var stock_row: HBoxContainer
var door_btn: Button
var task_edit: LineEdit
var mode_group := ButtonGroup.new()
var forecast_label: Label
var dive_panel: VBoxContainer
var dive_party_row: HBoxContainer  # 潜行中の育成導線（配信を観ながら装備/スキル）
var log_label: RichTextLabel
var dive_info: Label              # 探索の最小情報HUD（探索率/現在地/遭遇）
var door_row: HBoxContainer
var boss_banner: PanelContainer   # ボス遭遇バナー（スプライト＋名前）
var boss_banner_tex: TextureRect
var abandon_btn: Button
var close_panel: Control
var close_text: Label
var tabs: Control
var inv_box: VBoxContainer
var member_box: VBoxContainer     # メンバー一覧（各キャラの詳細・育成への導線）
var memo_box: VBoxContainer        # 記憶（道中で拾うメモリ＝短文小説）
var renov_view: RenovView
var renov_info: Label
var stats_box: VBoxContainer
var _tab_content: Control         # タブページを重ねるレイヤー
var _tab_footer: HBoxContainer    # フッターアイコンバー
var _tab_pages: Array = []        # 各ページ(Control)の配列
var _tab_buttons: Array = []      # フッターボタンの配列
var _tab_active := 0              # 現在選択中のタブインデックス
var ui_accum := 0.0
var offline_note := ""
var banter_rng := RandomNumberGenerator.new()
var banter_timer := 0.0
var banter_next := 6.0
var _ex_queue: Array = []  # 掛け合いの残り行
var _ex_timer := 0.0
var confirm: ConfirmationDialog
var status_overlay: Control
var status_portrait: PortraitRect
var status_name: Label
var market_overlay: Control        # 闇市専用全画面ページ
var market_content: VBoxContainer  # 闇市商品リスト（購入後に差し替え）
var ship_overlay: Control          # 交易船専用全画面ページ
var ship_content: VBoxContainer    # 交易船在庫リスト（購入後に差し替え）
var ship_overlay_label: Label      # 交易船のカウントダウンラベル（オーバーレイ内）
var formation_overlay: VBoxContainer  # 編成・献立専用全画面ページ
var management_overlay: VBoxContainer # 経営専用全画面ページ
var box_overlay: VBoxContainer        # 箱開封専用全画面ページ
var box_overlay_content: VBoxContainer # 箱リスト（開封後に差し替え）
var mgmt_banner_sub: Label            # ホームのバナーに表示する状態サマリ
var footer_nav: HBoxContainer         # ボトムナビバー（ホーム/メンバー/市場/経営）
var footer_btns: Dictionary = {}      # page_id → Button（アクティブ状態の強調に使う）
var home_day_lbl: Label               # ホーム画面の日数ラベル
var home_gold_lbl: Label              # ホーム画面のゴールドラベル
var home_box_badge: Label             # ホーム：経営アイコンの箱カウントバッジ
var home_speech_lbl: Label            # ホーム：会話吹き出し（キャラアイコン右）
var home_char_badges: Dictionary = {} # girl_id → Label（！バッジ）
var home_face_cams: Dictionary = {}   # girl_id → FaceCam（口パク）
var _formation_sel: String = ""       # 編成画面で選択中のキャラ
var status_head: VBoxContainer
var status_body: VBoxContainer
var bgm: AudioStreamPlayer       # 店テーマ（Abstraction CC0）
var bgm_dive: AudioStreamPlayer  # 潜行ドローン（手続き生成）
var bgm_battle: AudioStreamPlayer  # 戦闘レイヤー（手続き生成）
var sfx_pool: Array[AudioStreamPlayer] = []
var sfx_next := 0
var sfx_cache := {}


func _ready() -> void:
	banter_rng.randomize()
	var saved := SaveGame.load_state()
	sim = KuroSim.new(saved)
	_build_ui()
	var now0 := Time.get_unix_time_from_system()
	var offline := sim.apply_offline(now0)
	if not offline.is_empty():
		offline_note = "【安息】閉店中に +%dG・素材+%d（離席%d分）\n" % [
			int(offline["gold"]), int(offline["mats"]), int(float(offline["away"]) / 60.0)]
	sim.maybe_rotate_ship(now0)
	if sim.state["run"]["active"]:
		phase = Phase.DIVE  # 集中中に閉じても復帰できる
	else:
		_open_store(false)  # 起動時は店モード（店は常時営業）
	_pump_events()
	_apply_phase()
	_refresh_all()
	# 初回：コールドオープン（キリコの依頼）→ 終わったらチュートリアルへ連結。
	if not "intro_kiriko" in sim.state["events_seen"]:
		_maybe_event("intro_kiriko")
	else:
		_maybe_event("tutorial")


## 未読イベントなら再生する。発火条件を増やすのはここに1行。
func _maybe_event(id: String) -> void:
	if id in sim.state["events_seen"] or not EventData.EVENTS.has(id):
		return
	if talk_view.visible:
		return
	var ev: Dictionary = EventData.EVENTS[id]
	talk_view.play(ev, String(ev["speaker"]), {"kind": "event", "id": id})


## 物語の芯：深度・日数の節目で1本ずつ発火（休憩=夜/朝の安全な場で）。
## 条件を足すのはこの表に1行。先頭の未読・条件成立を1つだけ出す。
func _check_story_events() -> void:
	var floor_reached := int(sim.state["best_floor"]) + 1
	var day := int(sim.state["day"])
	var mem_all: bool = sim.state.get("memories", []).size() >= KuroMemories.MEMORIES.size()
	var milestones := [
		["story_b3", floor_reached >= 3],
		["story_b6", floor_reached >= 6],
		["story_b10", floor_reached >= 10],
		["story_day3", day >= 3],
		# 真エンド級：記憶を拾いきり、深部まで届いた人へ（メモリ収集率がカギ）
		["story_finale", mem_all and floor_reached >= 10],
	]
	for m in milestones:
		if bool(m[1]) and not String(m[0]) in sim.state["events_seen"]:
			_maybe_event(String(m[0]))
			return  # 1回に1本だけ


## シーン（会話/イベント）完了時の共通処理。
func _on_scene_finished(meta: Dictionary) -> void:
	match String(meta.get("kind", "")):
		"talk":
			sim.complete_talk(String(meta["girl"]), int(meta["tier"]))
			_sfx("ui_equip")
			_save(Time.get_unix_time_from_system())
			_refresh_all()
		"event":
			if not meta["id"] in sim.state["events_seen"]:
				sim.state["events_seen"].append(meta["id"])
				_save(Time.get_unix_time_from_system())
			# コールドオープンが終わったら、続けて操作チュートリアルへ。
			if String(meta["id"]) == "intro_kiriko":
				_maybe_event("tutorial")


func _process(delta: float) -> void:
	var now := Time.get_unix_time_from_system()
	_update_bgm(delta)
	if phase == Phase.DIVE:
		_catch_up(now)
		save_accum += delta
		if save_accum >= 20.0:
			save_accum = 0.0
			_save(now)
		# 掛け合い再生中はそれを優先、無ければ何もない時間の独り言
		if not _ex_queue.is_empty():
			_ex_timer -= delta
			if _ex_timer <= 0.0:
				var ln: Array = _ex_queue.pop_front()
				_say(String(ln[0]), String(ln[1]))
				_ex_timer = 2.4
		else:
			banter_timer += delta
			if banter_timer >= banter_next:
				banter_timer = 0.0
				banter_next = banter_rng.randf_range(5.0, 9.0)
				_idle_banter()
	# 店モード：接客をライブ進行（客が時間とともに来店→注文→会計）
	if phase == Phase.MORNING and shop != null and shop.open:
		shop.step(delta)
		for e in shop.drain_events():
			_on_shop_event(e)
	_update_clock(now)
	_update_overlays()
	ui_accum += delta
	if ui_accum >= 1.0:
		ui_accum = 0.0
		_refresh_header()
		if phase == Phase.MORNING:
			if shop != null and shop.open and shop_status != null and is_instance_valid(shop_status):
				shop_status.text = _shop_line()
			var before := float(sim.state["ship"]["rotated"])
			sim.maybe_rotate_ship(now)
			if float(sim.state["ship"]["rotated"]) != before:
				_refresh_morning()
			elif ship_overlay != null and ship_overlay.visible \
					and ship_overlay_label != null and is_instance_valid(ship_overlay_label):
				ship_overlay_label.text = _ship_head(now)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if sim != null:
			_save(Time.get_unix_time_from_system())


# --- シミュレーション駆動 ----------------------------------------------------


func _catch_up(now: float) -> void:
	var run: Dictionary = sim.state["run"]
	if not run["active"]:
		return
	var target := now - float(run["anchor"])
	var steps := mini(int((target - float(run["elapsed"])) / KuroData.SIM_DT), 200000)
	for i in steps:
		sim.step(KuroData.SIM_DT)
		if not run["active"]:
			break
	_pump_events()


func _pump_events() -> void:
	for e in sim.drain_events():
		match String(e["kind"]):
			"run_complete":
				result_summary = e["summary"]
				_on_run_complete()
			"door":
				_sfx("ui_confirm")
				_log(e["msg"])
				door_row.visible = true
				_banter("door")
			"door_loot":
				_sfx("chest_open")
				_log(e["msg"])
			"gate":
				_sfx("enemy_death")
				dive.spawn_fx("explosion", "enemy")
				_log(e["msg"])
				_banter("gate")
				if boss_banner != null:
					boss_banner.visible = false
			"boss":
				_log(e["msg"])
				_banter("boss")
				_show_boss_banner()
			"resync":
				_sfx("damage")
				dive.spawn_fx("smoke", "party")
				_log(e["msg"])
				_banter("wipe")
			"loot":
				_log(e["msg"])
				if banter_rng.randf() < 0.3:
					_banter("loot")
			"level":
				_sfx("thunder")
				dive.spawn_fx("lightning", "party")
				_log(e["msg"])
				_banter("levelup")
			"fx":
				var fxn := String(e.get("fx", ""))
				dive.spawn_fx(fxn, FxData.side_of(fxn))  # 出す側もFxData定義に従う
			"dmg_pop":
				dive.spawn_damage(int(e.get("val", 0)), String(e.get("at", "enemy")))
			"expr":
				# 戦闘表情：詠唱/被弾イベントをワイプに反映
				if dive_chrome != null:
					dive_chrome.set_expr(String(e.get("girl", "")),
							String(e.get("expr", "neutral")), 1.8)
			"memory":
				# 拾うのは軽く（表層はカジュアル）。読むのは「記憶」タブで任意。
				_sfx("teleport")
				_log("[color=#cdb4db]%s[/color]" % String(e["msg"]))
				_notify(String(e["msg"]))
			_:
				_log(e["msg"])


# --- 掛け合い（潜行中のキャラのセリフ）---------------------------------------


func _banter(cat: String) -> void:
	var line := Banter.pick(cat, sim.divers(), banter_rng)
	if not line.is_empty():
		_say(String(line["girl"]), String(line["text"]))
		banter_timer = 0.0  # 直後の独り言と被らせない


## 何もない時間：戦況に応じて combat/boss/idle を喋る。
## 平時は4割で二人の掛け合いを始める（無ければ独り言）。
func _idle_banter() -> void:
	if phase != Phase.DIVE:
		return
	var cat := "idle"
	for m in sim.state["mobs"]:
		if m["boss"]:
			cat = "boss"
			break
	if cat == "idle" and sim.state["in_combat"]:
		cat = "combat"
	if cat == "idle" and banter_rng.randf() < 0.55:
		var ex := Banter.pick_exchange(sim.divers(), banter_rng)
		if not ex.is_empty():
			_ex_queue = ex["lines"].duplicate()
			_ex_timer = 0.0
			return
	_banter(cat)


func _say(gid: String, text: String) -> void:
	dive.say(gid, text)
	_log("[color=#9fd8ff]%s[/color]「%s」" % [KuroData.GIRLS[gid]["name"], text])


func _on_run_complete() -> void:
	door_row.visible = false
	_ex_queue.clear()
	var disconnected: bool = result_summary.get("disconnected", false)
	_sfx("ui_denied" if disconnected else "teleport")
	if not disconnected and result_summary.get("mode", "") == "pomo":
		sim.register_completion(Time.get_date_string_from_system(), float(result_summary["minutes"]))
		_notify("浮上。%d分の集中、おつかれさま" % int(result_summary["minutes"]))
	# 浮上 → そのまま開店（店モードへ直行）。HP回復し、戦利品が店の弾になる。
	var mats_by: Dictionary = result_summary.get("mats_by", {})
	if not mats_by.is_empty():
		_notify("収穫: 乾物%d 肉%d 海鮮%d" % [
			int(mats_by.get("dry", 0)), int(mats_by.get("meat", 0)), int(mats_by.get("sea", 0))])
	_rest_heal()
	_open_store(true)  # 翌日へ＝店を開け直す（探索後は開店へ）
	if bgm != null and not bgm.playing:
		bgm.play()
	_save(Time.get_unix_time_from_system())
	_apply_phase()
	_refresh_all()
	_check_story_events()


## 営業中のライブ表示用の一行。
func _shop_line() -> String:
	if shop == null:
		return ""
	var waiting := 0
	for c in shop.queue:
		if c["state"] == "wait":
			waiting += 1
	var came: int = shop.served + shop.left_angry + shop.turned_away
	return "営業中 — 客%d・%d皿・+%dG（待ち%d）" % [came, shop.served, shop.gold_earned, waiting]


## 接客イベントを音で返す（提供＝会計音／離脱＝不満音）。
func _on_shop_event(e: Dictionary) -> void:
	match String(e["kind"]):
		"served":
			_sfx("ui_buy")
		"leave":
			_sfx("ui_denied")


# --- フェーズ遷移 ------------------------------------------------------------


func _on_depart() -> void:
	if sim.state["morning"]["menu"].is_empty():
		_log("献立が空だ。せめて一品")
		return
	var now := Time.get_unix_time_from_system()
	_request_notify_permission()
	_sfx("ui_confirm")
	if bgm != null and not bgm.playing:
		bgm.play()
	# 集中へ＝店を一旦締める（営業を確定して好感度・住民ストーリーを反映）
	if shop != null and shop.open:
		shop.close_shop()
		shop = null
	var task := task_edit.text.strip_edges()
	sim.start_run(dive_mode, dive_minutes, now, task if task != "" else "集中セッション")
	phase = Phase.DIVE
	log_label.clear()
	log_count = 0
	_ex_queue.clear()
	banter_timer = 0.0
	banter_next = 3.5
	_pump_events()
	_banter("start")
	_save(now)
	_apply_phase()
	_refresh_all()


func _on_abandon_pressed() -> void:
	_ask("本当に撤退する？\n切断扱い：素材半減・未送付の箱を失う・翌夜の客足が減る\n（ボス箱は送付済みなので無事）", _on_abandon_confirmed)


func _on_abandon_confirmed() -> void:
	_catch_up(Time.get_unix_time_from_system())
	sim.abandon_run()
	_pump_events()


## 休憩（焚き火）：パーティのHPを全回復する。
func _rest_heal() -> void:
	for id in KuroData.GIRL_ORDER:
		sim.state["hp"][id] = sim.girl_maxhp(id)


## 店モードに入る（店は常時営業＝ShopSim を開く）。
## advance_day=true で前営業を締めて翌日へ（好感度・住民ストーリー確定）。
func _open_store(advance_day: bool) -> void:
	if advance_day:
		if shop != null and shop.open:
			var summary := shop.close_shop()
			if not summary["lines"].is_empty():
				_notify(String(summary["lines"][0]))
		sim.next_morning()
		night_data = {}
	if shop == null or not shop.open:
		shop = ShopSim.new(sim)
		shop.open_shop()
	if sim.state["pending_night"].is_empty():
		sim.state["pending_night"] = {"lines": [], "gold": 0, "served": 0, "story": "", "talk_done": false}
	phase = Phase.MORNING


## 休憩（焚き火）→ 店に戻る（翌日へ＝営業を締めて再開）。
func _on_return_to_store() -> void:
	_open_store(true)
	_sfx("ui_confirm")
	if bgm != null and not bgm.playing:
		bgm.play()
	_save(Time.get_unix_time_from_system())
	_apply_phase()
	_refresh_all()
	_check_story_events()  # 節目の物語


func _apply_phase() -> void:
	var diving := phase == Phase.DIVE
	dive_panel.visible = diving
	close_panel.visible = phase == Phase.CAMP
	# 潜行中は「都市伝説LIVE」配信ビューを全画面に。ヘッダ／大タイマーは畳み、
	# 探索率・残り時間・掛け合いはビュー内のチロップで描く（モック準拠）。
	# MORNING はキャラ全画面。フローティングバッジが代替するためヘッダ不要
	header_panel.visible = phase == Phase.CAMP
	timer_box.visible = false
	dive_info.visible = not diving
	log_label.visible = not diving
	# stage_col（DiveView）は潜行中のみ。ホーム画面ではキャラ全画面で DiveView 不要。
	stage_col.visible = diving
	# 探索のポスト処理＋配信UI（潜行中のみ）。シェイダ未ロード時はチロップのみ。
	if post_bbc != null:
		post_bbc.visible = diving and post_mat != null
		post_fx.visible = diving and post_mat != null
	if dive_chrome != null:
		# ホーム画面では full portrait を使うので FaceCam ワイプは潜行中のみ
		dive_chrome.morning_mode = false
		dive_chrome.visible = diving
	if diving:
		dive.custom_minimum_size = Vector2(0, 300)
		dive_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_fill_dive_party()  # 潜行メンバーの育成導線を埋める
	else:
		dive.custom_minimum_size = Vector2(0, 92)
		dive_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# 店モード(MORNING)だけタブを表示。探索/休憩中は隠す。
	# オーバーレイが開いたままフェーズ変化した場合も強制クローズ。
	for ov in [management_overlay, box_overlay, formation_overlay, market_overlay, ship_overlay]:
		if ov != null and ov.visible:
			ov.visible = false
	tabs.visible = phase == Phase.MORNING
	if phase != Phase.DIVE:
		door_row.visible = false
	_relayout()  # 縦のステージ/パネル拡張をフェーズに追従


## 探索の最小情報（探索率／現在地＝バイオーム・階／遭遇＝人格名）。
func _dive_info_text() -> String:
	var s := sim.state
	var fl: int = sim.current_floor()
	var biome: Dictionary = KuroData.BIOMES[fl % KuroData.BIOMES.size()]
	var pct: int = int(fmod(float(s["dist"]), KuroData.FLOOR_LEN) / KuroData.FLOOR_LEN * 100.0)
	var enc := "道中"
	if s["in_combat"] and not s["mobs"].is_empty():
		enc = String(s["mobs"][0]["name"])
	return "探索率 %d%%　｜　現在地：%s B%dF　｜　遭遇：%s" % [pct, String(biome["name"]), fl + 1, enc]


func _update_clock(now: float) -> void:
	var run: Dictionary = sim.state["run"]
	var title := "黒猫飯店"
	match phase:
		Phase.DIVE:
			var rem := maxf(0.0, float(run["duration"]) - (now - float(run["anchor"])))
			timer_label.text = _mmss(rem)
			dive.remaining = rem  # 配信タイマー（ビュー内チロップ）
			if dive_info != null:
				dive_info.text = _dive_info_text()
			if run["mode"] == "pomo":
				status_label.text = String(run["task"])
				title = "%s ▼ %s" % [_mmss(rem), run["task"]]
			else:
				status_label.text = "クイック同期中"
				title = "%s ▼ クイック" % _mmss(rem)
			abandon_btn.visible = run["mode"] == "pomo"
		Phase.MORNING:
			timer_label.text = "営業中" if (shop != null and shop.open) else "黒猫飯店"
			status_label.text = "Day %d ｜ 灯りをつけて、皆が戻る。" % int(sim.state["day"])
		Phase.CAMP:
			timer_label.text = "休憩"
			status_label.text = "焚き火を囲む。"
	DisplayServer.window_set_title(title)


func _mmss(sec: float) -> String:
	var s := int(ceil(sec))
	return "%02d:%02d" % [int(s / 60.0), s % 60]


# --- UI構築 ------------------------------------------------------------------


func _build_ui() -> void:
	# 画像ベース(9-patch)テーマを優先。生成テクスチャ未インポート時は DS(flat) へ。
	theme = UIKit.theme() if UIKit.available() else DS.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # 生成アイコンをドットのまま拡大
	# ── 全面背景（ベタ塗り → 店内/キャラ画像で上書き）
	var bgrect := ColorRect.new()
	bgrect.color = COL_BG
	bgrect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bgrect)
	var _bg_path := "res://assets/art/home_bg.png"
	if not ResourceLoader.exists(_bg_path):
		_bg_path = "res://assets/generated/bg/interior.png"
	if ResourceLoader.exists(_bg_path):
		var bgtex := TextureRect.new()
		bgtex.set_anchors_preset(Control.PRESET_FULL_RECT)
		bgtex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bgtex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bgtex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		bgtex.texture = load(_bg_path)
		bgtex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bgtex)
	# 全体ディム（UI を読みやすくする）
	var dim_rect := ColorRect.new()
	dim_rect.color = Color(0.0, 0.0, 0.0, 0.45)
	dim_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim_rect)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		root.add_theme_constant_override(m, 0)
	add_child(root)
	var main_box := VBoxContainer.new()
	main_box.add_theme_constant_override("separation", 0)
	root.add_child(main_box)

	header_panel = PanelContainer.new()
	# ヘッダーは半透明（背景画像が透けて見える）
	var header_sb := StyleBoxFlat.new()
	header_sb.bg_color = Color(0.0, 0.0, 0.0, 0.62)
	header_sb.set_content_margin_all(DS.SP_2)
	header_panel.add_theme_stylebox_override("panel", header_sb)
	header_bar = HBoxContainer.new()
	header_bar.add_theme_constant_override("separation", DS.SP_4)
	header_panel.add_child(header_bar)
	main_box.add_child(header_panel)

	# 縦(モバイル)/横(PC)で並びを切替える responsive コンテナ。
	# 縦＝ステージの下にパネルを積む。横＝ステージ(左)とパネル(右)を並べる。
	content_box = BoxContainer.new()
	content_box.vertical = true
	content_box.add_theme_constant_override("separation", 0)
	content_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_box.add_child(content_box)
	stage_col = VBoxContainer.new()
	stage_col.add_theme_constant_override("separation", 0)
	content_box.add_child(stage_col)
	panel_col = VBoxContainer.new()
	panel_col.add_theme_constant_override("separation", 0)
	panel_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_box.add_child(panel_col)

	# 店先バナー（待機中）／潜行画面（ダイブ中）。高さはフェーズで可変
	dive = DiveView.new()
	dive.sim = sim
	dive.custom_minimum_size = Vector2(0, 92)
	dive.clip_contents = true
	dive_frame = PanelContainer.new()
	dive_frame.add_theme_stylebox_override("panel", _banner_style())
	dive_frame.add_child(dive)
	dive_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	stage_col.add_child(dive_frame)

	# タイマー帯（潜行中のみ表示）
	timer_box = VBoxContainer.new()
	timer_box.add_theme_constant_override("separation", 0)
	timer_label = _label("--:--", TYPE_DISPLAY)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_box.add_child(timer_label)
	status_label = _label("", TYPE_BODY, COL_DIM)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_box.add_child(status_label)
	stage_col.add_child(timer_box)

	_build_dive_panel(panel_col)
	# フッターバー付きタブ容器（tabs = wrapper VBox）
	tabs = VBoxContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_constant_override("separation", 0)
	panel_col.add_child(tabs)
	_tab_content = Control.new()
	_tab_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_content.clip_contents = true
	tabs.add_child(_tab_content)
	_build_morning(_tab_content)  # 「店」タブ（ホーム＋営業中を統合）
	_build_member_tab()
	_build_memory_tab()
	_build_inventory_tab()
	_build_renov_tab()
	_build_stats_tab()
	_build_tab_footer()
	_build_close()
	_build_post_fx()  # 配信ポスト処理＋チロップ（モーダルより先＝下に積む）

	talk_view = TalkView.new()
	talk_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	talk_view.visible = false
	talk_view.finished.connect(_on_scene_finished)
	add_child(talk_view)

	confirm = ConfirmationDialog.new()
	confirm.ok_button_text = "OK"
	confirm.cancel_button_text = "やめる"
	confirm.confirmed.connect(_on_confirmed)
	add_child(confirm)
	_build_status_overlay()
	_build_formation_overlay()
	_build_management_overlay()
	_build_box_overlay()
	_build_market_overlay()
	_build_ship_overlay()
	_build_audio()
	get_viewport().size_changed.connect(_relayout)
	_relayout()


## 探索ステージ専用のポスト処理（カラグレ/ブルーム/擬似DoF）＋その上の配信UI。
## BackBufferCopy → ColorRect(shader) → DiveChrome の順で全UIの最前面に積む。
func _build_post_fx() -> void:
	post_bbc = BackBufferCopy.new()
	post_bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	post_bbc.visible = false
	add_child(post_bbc)
	post_fx = ColorRect.new()
	post_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	post_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_fx.visible = false
	var sh: Shader = load("res://src/ui/dive_post.gdshader")
	if sh != null:
		post_mat = ShaderMaterial.new()
		post_mat.shader = sh
		post_fx.material = post_mat
	add_child(post_fx)
	dive_chrome = DiveChrome.new()
	dive_chrome.sim = sim
	dive_chrome.dive = dive
	dive_chrome.set_anchors_preset(Control.PRESET_TOP_LEFT)
	dive_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dive_chrome.visible = false
	add_child(dive_chrome)


## 探索ステージの矩形にポスト処理／配信UIを合わせる（毎フレーム）。
func _update_overlays() -> void:
	if dive_frame == null:
		return
	var r := dive_frame.get_global_rect()
	if dive_chrome != null and dive_chrome.visible:
		if dive_chrome.morning_mode and stage_col != null:
			# MORNING：home_bg のある stage_col エリア全体を基準にする
			var sr := stage_col.get_global_rect()
			dive_chrome.position = sr.position
			dive_chrome.size = sr.size
		else:
			dive_chrome.position = r.position
			dive_chrome.size = r.size
	if post_mat != null and post_fx != null and post_fx.visible:
		var vp := get_viewport_rect().size
		if vp.x > 0.0 and vp.y > 0.0:
			var amin := r.position / vp
			var amax := (r.position + r.size) / vp
			post_mat.set_shader_parameter("area", Vector4(amin.x, amin.y, amax.x, amax.y))
			post_mat.set_shader_parameter("focus_y", amin.y + (amax.y - amin.y) * 0.46)
			post_mat.set_shader_parameter("focus_band", (amax.y - amin.y) * 0.17)


## 画面比で縦(モバイル)/横(PC)を切替える。横ならステージとパネルを左右に。
func _relayout() -> void:
	if content_box == null:
		return
	var sz := get_viewport_rect().size
	var landscape := sz.x > sz.y * 1.25
	content_box.vertical = not landscape
	# ホーム画面（MORNING）では stage_col は非表示なので panel_col がフル幅/高さを取る
	if landscape:
		stage_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stage_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
		stage_col.size_flags_stretch_ratio = 1.4
		panel_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel_col.size_flags_stretch_ratio = 1.0
	else:
		# 縦：潜行中はステージ(配信ビュー)を全画面に、操作列だけ下に。待機中はパネル拡張。
		stage_col.size_flags_horizontal = Control.SIZE_FILL
		stage_col.size_flags_vertical = Control.SIZE_EXPAND_FILL if phase == Phase.DIVE else Control.SIZE_SHRINK_BEGIN
		stage_col.size_flags_stretch_ratio = 1.0
		panel_col.size_flags_horizontal = Control.SIZE_FILL
		panel_col.size_flags_vertical = Control.SIZE_SHRINK_END if phase == Phase.DIVE else Control.SIZE_EXPAND_FILL
		panel_col.size_flags_stretch_ratio = 1.0


## TBH の英雄画面のような、高解像度キャラ＋装備＋スキルの詳細。
func _build_status_overlay() -> void:
	status_overlay = Control.new()
	status_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	status_overlay.visible = false
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.04, 0.03, 0.88)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	status_overlay.add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 20)
	status_overlay.add_child(margin)
	var card := PanelContainer.new()
	margin.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	# 上段：ポートレート＋名前/ステータス
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	status_portrait = PortraitRect.new()
	status_portrait.custom_minimum_size = Vector2(170, 230)
	top.add_child(status_portrait)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	status_name = _label("", TYPE_HEAD, COL_TEXT)
	info.add_child(status_name)
	status_head = VBoxContainer.new()
	status_head.add_theme_constant_override("separation", 4)
	info.add_child(status_head)
	top.add_child(info)
	box.add_child(top)
	# 下段：装備・スキル・育成ツリー（スクロール）
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	status_body = VBoxContainer.new()
	status_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_body.add_theme_constant_override("separation", 5)
	scroll.add_child(status_body)
	box.add_child(scroll)
	var close := _button("閉じる", _close_status, TYPE_SUB)
	close.custom_minimum_size = Vector2(0, 50)
	box.add_child(close)
	add_child(status_overlay)


## 店モードの立ち絵タップ → そのキャラの詳細・スキルツリーを開く（導線）。
func _on_portrait_input(event: InputEvent, id: String) -> void:
	var tapped: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed)
	if tapped:
		_open_status(id)


func _open_status(id: String) -> void:
	if not status_overlay.visible:
		_sfx("ui_confirm")
	var s := sim.state
	var g: Dictionary = KuroData.GIRLS[id]
	status_portrait.girl_id = id
	status_name.text = String(g["name"])
	_clear(status_head)
	status_head.add_child(_label(String(g["role"]), TYPE_BODY, COL_WARM))
	var hearts: int = clampi(int(round(sim.aff(id) / 20.0)), 0, 5)
	status_head.add_child(_label("♥".repeat(hearts) + "♡".repeat(5 - hearts) + "  好感度 %d/100" % sim.aff(id),
			TYPE_BODY, Color("e88fb0")))
	status_head.add_child(_label("攻撃 %d　最大HP %d" % [int(sim.girl_atk(id)), int(sim.girl_maxhp(id))], TYPE_BODY))
	var fav := _label("好物 %s ／ 店番：%s" % [g["fav"], g["synergy"]], TYPE_SMALL, COL_DIM)
	fav.autowrap_mode = TextServer.AUTOWRAP_OFF
	status_head.add_child(fav)
	_clear(status_body)
	# 装備（3枠）。拾った装備をその場でセット（潜行中もOK）
	status_body.add_child(_section("装備　拾った物をセット"))
	for slot in ["weapon", "armor", "trinket"]:
		status_body.add_child(_equip_slot_row(id, slot))
	# スキルツリー（記憶の欠片で解放）＝グリッドのノードカード
	status_body.add_child(_section("スキルツリー　記憶の欠片 %d" % int(s["shards"])))
	var tree_grid := GridContainer.new()
	tree_grid.columns = 2
	tree_grid.add_theme_constant_override("h_separation", SP_2)
	tree_grid.add_theme_constant_override("v_separation", SP_2)
	for node in KuroData.GIRL_TREES.get(id, []):
		tree_grid.add_child(_skill_node_card(id, node))
	status_body.add_child(tree_grid)
	# スキル（装備/外し）。枠は覚醒で増える
	status_body.add_child(_section("スキル（装備枠 %d）" % sim.skill_slots()))
	var sk_flow := HFlowContainer.new()
	sk_flow.add_theme_constant_override("h_separation", 5)
	sk_flow.add_theme_constant_override("v_separation", 5)
	for sid in sim.known_skills(id):
		var def: Dictionary = KuroData.SKILL_DB[sid]
		var equipped: bool = sid in s["girls"][id]["skills_eq"]
		var sk := _button(("★" if equipped else "") + String(def["name"]), _on_status_skill.bind(id, String(sid)), TYPE_SMALL)
		if not equipped and s["girls"][id]["skills_eq"].size() >= sim.skill_slots():
			sk.disabled = true
		sk_flow.add_child(sk)
	status_body.add_child(sk_flow)
	status_overlay.visible = true


## 装備スロット1行：現在の装備＋倉庫の候補（このスロットのスコア上位3）を装備ボタンで。
## 拾った装備を「店に戻らず」その場でセットできる＝潜行中の育成導線。
func _equip_slot_row(id: String, slot: String) -> VBoxContainer:
	var s := sim.state
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", SP_1)
	var slot_name: String = SimItems.SLOTS[slot]["name"]
	var cur: Dictionary = s["girls"][id]["equip"][slot]
	var cur_score := 0.0
	var slot_icon := _gen_tex("equip/" + slot)
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 4)
	if slot_icon != null:
		header_row.add_child(_icon_rect(slot_icon, 20))
	if cur.is_empty():
		var lbl := _label("%s： —" % slot_name, TYPE_SMALL, Color(1, 1, 1, 0.45))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header_row.add_child(lbl)
	else:
		cur_score = float(cur["score"])
		var cl := _label("%s： %s %s" % [slot_name, SimItems.display_name(cur), SimItems.affix_text(cur)],
				TYPE_SMALL, SimItems.GRADES[int(cur["grade"])]["color"])
		cl.autowrap_mode = TextServer.AUTOWRAP_OFF
		cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header_row.add_child(cl)
	box.add_child(header_row)
	# 倉庫からこのスロットの候補（スコア上位3）
	var cands: Array = []
	for it in s["inventory"]:
		if String(it["slot"]) == slot:
			cands.append(it)
	cands.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	var shown := mini(cands.size(), 3)
	for k in shown:
		var it: Dictionary = cands[k]
		var diff := float(it["score"]) - cur_score
		var badge := ("▲+%d" % int(diff)) if diff > 0.0 else ("▼%d" % int(diff))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", SP_1)
		var nl := _label("　%s %s %s" % [SimItems.display_name(it), SimItems.affix_text(it), badge],
				TYPE_SMALL, SimItems.GRADES[int(it["grade"])]["color"])
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.autowrap_mode = TextServer.AUTOWRAP_OFF
		line.add_child(nl)
		var b := _button("装備", _on_status_equip.bind(int(it["id"]), id), TYPE_SMALL)
		if diff > 0.0 and UIKit.available():
			UIKit.as_primary(b)
		line.add_child(b)
		box.add_child(line)
	if shown == 0 and cur.is_empty():
		box.add_child(_label("　倉庫にこの枠の装備なし。潜って拾おう", TYPE_SMALL, COL_DIM))
	return box


func _on_status_equip(item_id: int, girl_id: String) -> void:
	if sim.equip_from_inventory(item_id, girl_id):
		_sfx("ui_equip")
		_save(Time.get_unix_time_from_system())
		_refresh_header()
		if inv_box != null:
			_refresh_inventory()
		_open_status(girl_id)  # 再描画


## スキルツリーの1ノードをカードで（精神世界＝紫。解放済/可能/ロックで色分け）。
func _skill_node_card(id: String, node: Dictionary) -> PanelContainer:
	var s := sim.state
	var owned: bool = node["id"] in s["girls"][id].get("tree", [])
	var avail: bool = sim.tree_available(id, String(node["id"]))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_sb())
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", SP_1)
	var head_col := (UIKit.ACCENT if UIKit.available() else DS.ACCENT) if owned else (COL_TEXT if avail else COL_DIM)
	box.add_child(_label(("● " if owned else "○ ") + String(node["name"]), TYPE_BODY, head_col))
	box.add_child(_label(_tree_node_desc(node), TYPE_SMALL, COL_DIM))
	if owned:
		box.add_child(_label("解放済", TYPE_SMALL, UIKit.ACCENT if UIKit.available() else DS.ACCENT))
	else:
		var buy := _button("欠片 %d" % int(node["cost"]), _on_tree_buy.bind(id, String(node["id"])), TYPE_SMALL)
		buy.disabled = not avail or int(s["shards"]) < int(node["cost"])
		if not avail and int(node.get("req_aff", 0)) > sim.aff(id):
			buy.text = "♥%d必要" % int(node["req_aff"])
		box.add_child(buy)
	card.add_child(box)
	return card


func _tree_node_desc(node: Dictionary) -> String:
	var e: Dictionary = node["effect"]
	if e.has("skill"):
		return "技習得"
	var parts: Array[String] = []
	if e.has("atk"):
		parts.append("攻+%d%%" % int(float(e["atk"]) * 100))
	if e.has("hp"):
		parts.append("HP+%d%%" % int(float(e["hp"]) * 100))
	if e.has("crit"):
		parts.append("会心+%d%%" % int(float(e["crit"]) * 100))
	return "／".join(parts)


func _on_tree_buy(id: String, node_id: String) -> void:
	if sim.tree_unlock(id, node_id):
		_sfx("ui_equip")
		_pump_events()
		_save(Time.get_unix_time_from_system())
		_refresh_header()
		_open_status(id)  # 再描画


func _on_status_skill(id: String, sid: String) -> void:
	sim.equip_skill(id, sid)
	_open_status(id)


func _close_status() -> void:
	status_overlay.visible = false


# ──────────────────────────────────────────
# 経営サブ画面（panel_col 内で tabs と差し替え）
# ──────────────────────────────────────────

func _build_management_overlay() -> void:
	management_overlay = VBoxContainer.new()
	management_overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	management_overlay.add_theme_constant_override("separation", 0)
	management_overlay.visible = false
	# ── ヘッダ
	var header := PanelContainer.new()
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(0.08, 0.08, 0.08)
	hsb.border_color = Color(0.3, 0.3, 0.3)
	hsb.border_width_bottom = 2
	hsb.set_content_margin_all(14)
	header.add_theme_stylebox_override("panel", hsb)
	var hcol := VBoxContainer.new()
	hcol.add_theme_constant_override("separation", 2)
	hcol.add_child(_label("経　営", TYPE_DISPLAY, COL_TEXT))
	hcol.add_child(_label("編成・献立・闇市・交易船", TYPE_SMALL, COL_DIM))
	header.add_child(hcol)
	management_overlay.add_child(header)
	# ── スクロール（ops_box がここに入る）
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	management_overlay.add_child(scroll)
	var inner := MarginContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		inner.add_theme_constant_override(m, 12)
	scroll.add_child(inner)
	inner.add_child(ops_box)
	# ── 戻るボタン
	var close_btn := _button("← ホームへ戻る", _close_management, TYPE_SUB)
	close_btn.custom_minimum_size = Vector2(0, 48)
	management_overlay.add_child(close_btn)
	panel_col.add_child(management_overlay)


func _open_management() -> void:
	_sfx("ui_confirm")
	# 経営内容を最新化してから開く
	_clear(ops_box)
	_fill_ops(ops_box)
	tabs.visible = false
	management_overlay.visible = true


func _close_management() -> void:
	management_overlay.visible = false
	tabs.visible = true


# ──────────────────────────────────────────
# 箱開封ページ（ホームから直接アクセス）
# ──────────────────────────────────────────

func _build_box_overlay() -> void:
	box_overlay = VBoxContainer.new()
	box_overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box_overlay.add_theme_constant_override("separation", 0)
	box_overlay.visible = false
	# ── ヘッダ
	var header := PanelContainer.new()
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(0.06, 0.05, 0.02)
	hsb.border_color = Color(0.55, 0.38, 0.08)
	hsb.border_width_bottom = 2
	hsb.set_content_margin_all(14)
	header.add_theme_stylebox_override("panel", hsb)
	var hcol := VBoxContainer.new()
	hcol.add_theme_constant_override("separation", 2)
	hcol.add_child(_label("ギフトボックス", TYPE_DISPLAY, Color(1.0, 0.82, 0.35)))
	hcol.add_child(_label("冒険で集めた箱を開封する", TYPE_SMALL, COL_DIM))
	header.add_child(hcol)
	box_overlay.add_child(header)
	# ── スクロール（box_overlay_content が入る）
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box_overlay.add_child(scroll)
	var margin_wrap := MarginContainer.new()
	margin_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin_wrap.add_theme_constant_override(m, 12)
	scroll.add_child(margin_wrap)
	box_overlay_content = VBoxContainer.new()
	box_overlay_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box_overlay_content.add_theme_constant_override("separation", 8)
	margin_wrap.add_child(box_overlay_content)
	# ── 戻るボタン
	var close_btn := _button("← ホームへ戻る", _close_box_page, TYPE_SUB)
	close_btn.custom_minimum_size = Vector2(0, 48)
	box_overlay.add_child(close_btn)
	panel_col.add_child(box_overlay)


func _open_box_page() -> void:
	_sfx("ui_confirm")
	_clear(box_overlay_content)
	_fill_box_page(box_overlay_content)
	tabs.visible = false
	box_overlay.visible = true


func _close_box_page() -> void:
	box_overlay.visible = false
	tabs.visible = true


## 箱リストUIを box コンテナに充填。
func _fill_box_page(box: VBoxContainer) -> void:
	var boxes: Array = sim.state["boxes"]
	var box_count: int = boxes.size()
	# ヘッダー行：合計数＋一括開封
	var hdr_row := HBoxContainer.new()
	hdr_row.add_theme_constant_override("separation", 8)
	var count_lbl := _label("%d 個" % box_count, TYPE_SMALL, COL_WARM if box_count > 0 else COL_DIM)
	count_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_row.add_child(count_lbl)
	var bulk_b := _button("一括開封", _on_open_all_boxes, TYPE_SMALL)
	bulk_b.disabled = box_count == 0
	if UIKit.available() and box_count > 0:
		UIKit.as_primary(bulk_b)
	hdr_row.add_child(bulk_b)
	box.add_child(hdr_row)
	# 個別箱行
	if box_count == 0:
		box.add_child(_label("箱はありません", TYPE_SMALL, COL_DIM))
	else:
		for bi in boxes.size():
			var grade := int(boxes[bi])
			var gc := _box_grade_color(grade)
			var item_row := HBoxContainer.new()
			item_row.add_theme_constant_override("separation", 10)
			var bic := _box_icon(grade)
			if bic != null:
				item_row.add_child(_icon_rect(bic, 36))
			var gl := _label(KuroData.BOX_NAMES[grade], TYPE_SMALL, gc)
			gl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			item_row.add_child(gl)
			var ob := _button("開封", _on_open_box, TYPE_SMALL)
			if UIKit.available():
				UIKit.as_primary(ob)
			item_row.add_child(ob)
			box.add_child(item_row)


# ──────────────────────────────────────────
# 編成・献立サブ画面（panel_col 内で tabs と差し替え）
# ──────────────────────────────────────────

func _build_formation_overlay() -> void:
	formation_overlay = VBoxContainer.new()
	formation_overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	formation_overlay.add_theme_constant_override("separation", 0)
	formation_overlay.visible = false
	# ── ヘッダ
	var header := PanelContainer.new()
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(0.08, 0.06, 0.04)
	hsb.border_color = Color(0.35, 0.25, 0.1)
	hsb.set_border_width_all(0); hsb.set_border_width_all(0)
	hsb.border_width_bottom = 2
	hsb.set_content_margin_all(14)
	header.add_theme_stylebox_override("panel", hsb)
	var hcol := VBoxContainer.new()
	hcol.add_theme_constant_override("separation", 2)
	hcol.add_child(_label("編成・献立", TYPE_DISPLAY, Color(1.0, 0.85, 0.5)))
	hcol.add_child(_label("扉方針・仲間の配置・今夜のメニューを決める", TYPE_SMALL, COL_DIM))
	header.add_child(hcol)
	formation_overlay.add_child(header)
	# ── スクロール内容（_refresh_morning が直接更新する既存 nodes を追加）
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	formation_overlay.add_child(scroll)
	var margin_wrap := MarginContainer.new()
	margin_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin_wrap.add_theme_constant_override(m, 12)
	scroll.add_child(margin_wrap)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 8)
	margin_wrap.add_child(inner)
	# forecast / stock / door / girls / menu_title / menu_box を inner に収める
	inner.add_child(forecast_label)
	inner.add_child(stock_row)
	inner.add_child(door_btn)
	inner.add_child(girls_box)
	inner.add_child(menu_title)
	inner.add_child(menu_box)
	# ── 戻るボタン
	var close_btn := _button("← ホームへ戻る", _close_formation, TYPE_SUB)
	close_btn.custom_minimum_size = Vector2(0, 48)
	formation_overlay.add_child(close_btn)
	panel_col.add_child(formation_overlay)


func _open_formation() -> void:
	_sfx("ui_confirm")
	# 経営サブ画面から開かれた場合は経営を閉じてから遷移
	if management_overlay != null:
		management_overlay.visible = false
	tabs.visible = false
	formation_overlay.visible = true


func _close_formation() -> void:
	formation_overlay.visible = false
	tabs.visible = true


# ──────────────────────────────────────────
# 闇市サブ画面（panel_col 内で tabs と差し替え）
# ──────────────────────────────────────────

func _build_market_overlay() -> void:
	market_overlay = VBoxContainer.new()
	market_overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	market_overlay.add_theme_constant_override("separation", 0)
	market_overlay.visible = false
	# ── ヘッダ（グラフィカル）
	market_overlay.add_child(_build_market_header())
	# ── カウントダウン兼サブテキスト行
	var sub_bar := PanelContainer.new()
	var sub_sb := StyleBoxFlat.new()
	sub_sb.bg_color = Color(0.10, 0.05, 0.01)
	sub_sb.set_content_margin_all(8)
	sub_bar.add_theme_stylebox_override("panel", sub_sb)
	sub_bar.add_child(_label("夜の裏取引。在庫は毎晩更新される。", TYPE_SMALL, Color(0.75, 0.55, 0.3)))
	market_overlay.add_child(sub_bar)
	# ── スクロール商品リスト
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	market_overlay.add_child(scroll)
	market_content = VBoxContainer.new()
	market_content.add_theme_constant_override("separation", 8)
	market_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		market_content.add_theme_constant_override(m, 12)
	scroll.add_child(market_content)
	# ── 戻るボタン
	var close_btn := _button("← ホームへ戻る", _close_market, TYPE_SUB)
	close_btn.custom_minimum_size = Vector2(0, 48)
	market_overlay.add_child(close_btn)
	panel_col.add_child(market_overlay)


func _build_market_header() -> Control:
	var hero := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.08, 0.02)
	sb.set_content_margin_all(16)
	hero.add_theme_stylebox_override("panel", sb)
	var bg_path := "res://assets/generated/ui/screen_shop.png"
	if ResourceLoader.exists(bg_path):
		var tr := TextureRect.new()
		tr.texture = load(bg_path)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.modulate = Color(1, 1, 1, 0.25)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hero.add_child(tr)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.add_child(_label("闇　市", TYPE_DISPLAY, Color(1.0, 0.65, 0.2)))
	col.add_child(_label("夜の裏取引。怪しい品が流れ着く。", TYPE_BODY, Color(0.9, 0.7, 0.5)))
	hero.add_child(col)
	return hero


func _fill_market_content() -> void:
	_clear(market_content)
	var s := sim.state
	# 所持ゴールドバッジ
	var gold_card := PanelContainer.new()
	var gcsb := StyleBoxFlat.new()
	gcsb.bg_color = Color(0.12, 0.10, 0.03)
	gcsb.border_color = Color(0.8, 0.65, 0.15, 0.9)
	gcsb.set_border_width_all(1)
	gcsb.set_content_margin_all(12)
	gcsb.corner_radius_top_left = 6; gcsb.corner_radius_top_right = 6
	gcsb.corner_radius_bottom_left = 6; gcsb.corner_radius_bottom_right = 6
	gold_card.add_theme_stylebox_override("panel", gcsb)
	var gold_row := HBoxContainer.new()
	gold_row.add_theme_constant_override("separation", 8)
	gold_row.add_child(_label("所持ゴールド", TYPE_SMALL, COL_DIM))
	var gl := _label("%d G" % int(s["gold"]), TYPE_SUB, COL_ACCENT)
	gl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gold_row.add_child(gl)
	gold_card.add_child(gold_row)
	market_content.add_child(gold_card)
	# 商品リスト（品目ごとに説明を出し分け）
	var item_descs: Dictionary = {
		"recipe": "ランダムなレシピを1つ習得する",
		"mats":   "乾・肉・海 素材それぞれ +2",
		"invite": "翌日の来客数 +3",
	}
	for i in KuroData.MARKET.size():
		var item: Dictionary = KuroData.MARKET[i]
		var item_id := String(item["id"])
		var icon: Texture2D = null
		if item_id == "mats":
			icon = _ing_icon("meat")
		elif item_id == "recipe":
			icon = _food_icon("chashu")
		var desc: String = item_descs.get(item_id, "")
		market_content.add_child(_market_item_card(String(item["name"]), "%dG" % int(item["price"]),
				_on_buy.bind(i), int(s["gold"]) >= int(item["price"]), icon, desc))


func _market_item_card(title: String, price_text: String, cb: Callable, enabled: bool,
		icon: Texture2D, subtitle: String) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.08, 0.04) if enabled else Color(0.09, 0.07, 0.05)
	sb.border_color = Color(0.6, 0.35, 0.1) if enabled else Color(0.25, 0.2, 0.15)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(12)
	sb.corner_radius_top_left = 4; sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4; sb.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	if icon != null:
		var ir := _icon_rect(icon, 48)
		ir.custom_minimum_size = Vector2(48, 48)
		row.add_child(ir)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 3)
	info.add_child(_label(title, TYPE_BODY, Color(1.0, 0.85, 0.6) if enabled else COL_DIM))
	info.add_child(_label(subtitle, TYPE_SMALL, COL_DIM))
	row.add_child(info)
	var buy_btn := _button(price_text, cb, TYPE_SUB)
	buy_btn.custom_minimum_size = Vector2(72, 0)
	buy_btn.disabled = not enabled
	if enabled:
		buy_btn.modulate = Color(1.0, 0.75, 0.2)
	row.add_child(buy_btn)
	panel.add_child(row)
	return panel


func _open_market() -> void:
	_sfx("ui_confirm")
	_fill_market_content()
	if management_overlay != null:
		management_overlay.visible = false
	tabs.visible = false
	market_overlay.visible = true


func _close_market() -> void:
	market_overlay.visible = false
	tabs.visible = true


# ──────────────────────────────────────────
# 交易船サブ画面（panel_col 内で tabs と差し替え）
# ──────────────────────────────────────────

func _build_ship_overlay() -> void:
	ship_overlay = VBoxContainer.new()
	ship_overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ship_overlay.add_theme_constant_override("separation", 0)
	ship_overlay.visible = false
	# ── ヘッダ（グラフィカル）
	ship_overlay.add_child(_build_ship_header())
	# ── カウントダウン帯
	var timer_bar := PanelContainer.new()
	var timer_sb := StyleBoxFlat.new()
	timer_sb.bg_color = Color(0.02, 0.07, 0.13)
	timer_sb.set_content_margin_all(8)
	timer_bar.add_theme_stylebox_override("panel", timer_sb)
	ship_overlay_label = _label("", TYPE_SMALL, COL_ACCENT)
	timer_bar.add_child(ship_overlay_label)
	ship_overlay.add_child(timer_bar)
	# ── スクロール在庫リスト
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ship_overlay.add_child(scroll)
	ship_content = VBoxContainer.new()
	ship_content.add_theme_constant_override("separation", 8)
	ship_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		ship_content.add_theme_constant_override(m, 12)
	scroll.add_child(ship_content)
	# ── 戻るボタン
	var close_btn := _button("← ホームへ戻る", _close_ship, TYPE_SUB)
	close_btn.custom_minimum_size = Vector2(0, 48)
	ship_overlay.add_child(close_btn)
	panel_col.add_child(ship_overlay)


func _build_ship_header() -> Control:
	var hero := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.10, 0.18)
	sb.set_content_margin_all(16)
	hero.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.add_child(_label("交 易 船", TYPE_DISPLAY, Color(0.3, 0.85, 1.0)))
	col.add_child(_label("はるか遠くから流れ着いた品々。時間で在庫は入れ替わる。", TYPE_BODY, Color(0.6, 0.85, 0.95)))
	hero.add_child(col)
	return hero


func _fill_ship_content() -> void:
	_clear(ship_content)
	var s := sim.state
	var now := Time.get_unix_time_from_system()
	if ship_overlay_label != null and is_instance_valid(ship_overlay_label):
		ship_overlay_label.text = _ship_head(now)
	ship_content.add_child(_label("所持ゴールド: %dG" % int(s["gold"]), TYPE_SUB, Color(0.3, 0.85, 1.0)))
	var stock: Array = s["ship"]["stock"]
	if stock.is_empty():
		ship_content.add_child(_label("（船は出払っている。次の入荷を待とう）", TYPE_BODY, COL_DIM))
		return
	for i in stock.size():
		var entry: Dictionary = stock[i]
		var text := ""
		var subtitle := ""
		var tcol := COL_TEXT
		if entry["type"] == "pet":
			var pet: Dictionary = KuroData.PETS[entry["pet"]]
			text = "ペット：%s" % pet["name"]
			subtitle = String(pet["desc"])
			tcol = COL_WARM
		else:
			var it: Dictionary = entry["item"]
			text = "%s %s" % [SimItems.display_name(it), SimItems.affix_text(it)]
			subtitle = "希少品"
			tcol = SimItems.GRADES[int(entry["item"]["grade"])]["color"]
		ship_content.add_child(_ship_item_card(text, subtitle, "%dG" % int(entry["price"]),
				_on_ship_buy.bind(i), int(s["gold"]) >= int(entry["price"]), tcol))
	if not s["pets"].is_empty():
		var pet_names: Array[String] = []
		for pid in s["pets"]:
			pet_names.append(KuroData.PETS[pid]["name"])
		ship_content.add_child(_label("店の住人: " + "、".join(pet_names), TYPE_SMALL, COL_DIM))


func _ship_item_card(title: String, subtitle: String, price_text: String,
		cb: Callable, enabled: bool, title_color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.09, 0.14) if enabled else Color(0.04, 0.06, 0.08)
	sb.border_color = Color(0.2, 0.55, 0.8) if enabled else Color(0.12, 0.22, 0.32)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(12)
	sb.corner_radius_top_left = 4; sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4; sb.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 3)
	info.add_child(_label(title, TYPE_BODY, title_color if enabled else COL_DIM))
	info.add_child(_label(subtitle, TYPE_SMALL, COL_DIM))
	row.add_child(info)
	var buy_btn := _button(price_text, cb, TYPE_SUB)
	buy_btn.custom_minimum_size = Vector2(72, 0)
	buy_btn.disabled = not enabled
	if enabled:
		buy_btn.modulate = Color(0.5, 0.9, 1.0)
	row.add_child(buy_btn)
	panel.add_child(row)
	return panel


func _open_ship() -> void:
	_sfx("ui_confirm")
	_fill_ship_content()
	if management_overlay != null:
		management_overlay.visible = false
	tabs.visible = false
	ship_overlay.visible = true


func _close_ship() -> void:
	ship_overlay.visible = false
	tabs.visible = true


## 潜行中の育成導線：配信を観ながら、各メンバーをタップで装備セット／スキル育成。
func _fill_dive_party() -> void:
	if dive_party_row == null:
		return
	_clear(dive_party_row)
	dive_party_row.add_child(_label("育成▶", TYPE_SMALL, COL_DIM))
	for id in sim.divers():
		var g: Dictionary = KuroData.GIRLS[id]
		var b := _button(String(g["name"]), _open_status.bind(id), TYPE_SMALL)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dive_party_row.add_child(b)


## 店先バナーの枠（角丸＋ネオン縁、内側余白なし）。
func _banner_style() -> StyleBoxFlat:
	var b := DS._sb(DS.SURFACE, Color(DS.ACCENT.r, DS.ACCENT.g, DS.ACCENT.b, 0.45), DS.R_MD, 0)
	return b


## CTA（主要動線）ボタン：アクセント塗り。
func _cta(text: String, cb: Callable, font_size := DS.T_SUB) -> Button:
	return DS.as_primary(_button(text, cb, font_size))


## 資源バッジ：アイコン＋数値（ヘッダーの資源バー用）。
func _badge(tex: Texture2D, value: String, color := COL_TEXT) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", DS.SP_1)
	if tex != null:
		hb.add_child(_icon_rect(tex, 22))
	var l := _label(value, DS.T_BODY, color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	hb.add_child(l)
	return hb


func _build_morning(parent: Control) -> void:
	# ── 全画面キャラクター＋フローティングUI ──────────────────────────
	morning_panel = Control.new()
	morning_panel.name = "店"
	morning_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	morning_panel.clip_contents = true
	morning_panel.visible = true

	# ① 互換用プレースホルダー（overlay 等から参照される）
	home_scene = VBoxContainer.new()
	home_scene.visible = false
	morning_panel.add_child(home_scene)

	# 下半分暗幕：背景画像の上でテキストを読みやすくする
	var grad := ColorRect.new()
	grad.set_anchor(SIDE_LEFT, 0); grad.set_anchor(SIDE_TOP, 0.5)
	grad.set_anchor(SIDE_RIGHT, 1); grad.set_anchor(SIDE_BOTTOM, 1)
	grad.color = Color(0.0, 0.0, 0.0, 0.75)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	morning_panel.add_child(grad)

	# ② 左上：日数・ゴールド バッジ
	var info_wrap := PanelContainer.new()
	info_wrap.set_anchor(SIDE_LEFT, 0); info_wrap.set_anchor(SIDE_TOP, 0)
	info_wrap.set_anchor(SIDE_RIGHT, 0); info_wrap.set_anchor(SIDE_BOTTOM, 0)
	info_wrap.set_offset(SIDE_LEFT, 10); info_wrap.set_offset(SIDE_TOP, 10)
	info_wrap.set_offset(SIDE_RIGHT, 190); info_wrap.set_offset(SIDE_BOTTOM, 66)
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color(0.0, 0.0, 0.0, 0.62)
	isb.corner_radius_top_left = 8; isb.corner_radius_top_right = 8
	isb.corner_radius_bottom_left = 8; isb.corner_radius_bottom_right = 8
	isb.set_content_margin_all(8)
	info_wrap.add_theme_stylebox_override("panel", isb)
	var info_col := VBoxContainer.new()
	info_col.add_theme_constant_override("separation", 1)
	home_day_lbl = _label("Day 1", TYPE_SMALL, COL_WARM)
	home_gold_lbl = _label("金 0G", TYPE_SMALL, Color(1.0, 0.85, 0.5))
	info_col.add_child(home_day_lbl)
	info_col.add_child(home_gold_lbl)
	info_wrap.add_child(info_col)
	morning_panel.add_child(info_wrap)

	# ③ 右側：丸アイコンナビ（編成・箱管理）
	var right_nav := VBoxContainer.new()
	right_nav.set_anchor(SIDE_LEFT, 1); right_nav.set_anchor(SIDE_TOP, 0)
	right_nav.set_anchor(SIDE_RIGHT, 1); right_nav.set_anchor(SIDE_BOTTOM, 0)
	right_nav.set_offset(SIDE_LEFT, -80); right_nav.set_offset(SIDE_TOP, 80)
	right_nav.set_offset(SIDE_RIGHT, -8); right_nav.set_offset(SIDE_BOTTOM, 380)
	right_nav.add_theme_constant_override("separation", 14)
	right_nav.add_child(_home_icon_btn("編成", "⚙", _open_formation))
	# 箱バッジ付き経営アイコン
	# 箱アイコン（バッジ付き） → 箱開封ページ直行
	var box_nav_wrap := VBoxContainer.new()
	box_nav_wrap.add_theme_constant_override("separation", 2)
	var box_icon_btn := _home_icon_btn("箱", "📦", _open_box_page)
	home_box_badge = _label("", 10, Color(1.0, 0.7, 0.2))
	home_box_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box_nav_wrap.add_child(box_icon_btn)
	box_nav_wrap.add_child(home_box_badge)
	right_nav.add_child(box_nav_wrap)
	right_nav.add_child(_home_icon_btn("経営", "🏪", _open_management))
	right_nav.add_child(_home_icon_btn("改装", "🔮", _switch_tab.bind(4)))
	morning_panel.add_child(right_nav)

	# ④ キャラ顔アイコン行（FaceCam＋シナリオ動線＋吹き出し）
	home_char_badges.clear()
	home_face_cams.clear()
	var char_row := HBoxContainer.new()
	char_row.set_anchor(SIDE_LEFT, 0); char_row.set_anchor(SIDE_TOP, 1)
	char_row.set_anchor(SIDE_RIGHT, 1); char_row.set_anchor(SIDE_BOTTOM, 1)
	char_row.set_offset(SIDE_LEFT, 12); char_row.set_offset(SIDE_TOP, -325)
	char_row.set_offset(SIDE_RIGHT, -90); char_row.set_offset(SIDE_BOTTOM, -215)
	char_row.add_theme_constant_override("separation", 4)
	for cid in KuroData.GIRL_ORDER:
		# Controlラッパー：FaceCamをFULL_RECTで埋め、バッジをオーバーレイ
		var fc_wrap := Control.new()
		fc_wrap.custom_minimum_size = Vector2(58, 105)
		fc_wrap.mouse_filter = Control.MOUSE_FILTER_STOP
		fc_wrap.gui_input.connect(_on_char_face_input.bind(cid))
		var fc := FaceCam.new()
		fc.girl_id = cid
		fc.show_label = true
		fc.set_anchors_preset(Control.PRESET_FULL_RECT)
		fc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		home_face_cams[cid] = fc
		fc_wrap.add_child(fc)
		# ！バッジ（右上角オーバーレイ）
		var cbadge := Label.new()
		cbadge.text = ""
		cbadge.add_theme_font_size_override("font_size", 12)
		cbadge.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
		cbadge.z_index = 1
		cbadge.set_anchor(SIDE_LEFT, 1); cbadge.set_anchor(SIDE_TOP, 0)
		cbadge.set_anchor(SIDE_RIGHT, 1); cbadge.set_anchor(SIDE_BOTTOM, 0)
		cbadge.set_offset(SIDE_LEFT, -22); cbadge.set_offset(SIDE_TOP, 2)
		cbadge.set_offset(SIDE_RIGHT, -2); cbadge.set_offset(SIDE_BOTTOM, 18)
		home_char_badges[cid] = cbadge
		fc_wrap.add_child(cbadge)
		char_row.add_child(fc_wrap)
	# 右側：会話タイトル吹き出し
	var speech_wrap := VBoxContainer.new()
	speech_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speech_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	home_speech_lbl = _label("", TYPE_SMALL, Color(1.0, 1.0, 1.0, 0.85))
	home_speech_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	home_speech_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home_speech_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	home_speech_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	speech_wrap.add_child(home_speech_lbl)
	char_row.add_child(speech_wrap)
	morning_panel.add_child(char_row)

	# ⑤ 下部：ステータス＋タスク入力＋集中ボタン
	var bottom_area := VBoxContainer.new()
	bottom_area.set_anchor(SIDE_LEFT, 0); bottom_area.set_anchor(SIDE_TOP, 1)
	bottom_area.set_anchor(SIDE_RIGHT, 1); bottom_area.set_anchor(SIDE_BOTTOM, 1)
	bottom_area.clip_contents = true
	bottom_area.set_offset(SIDE_LEFT, 12); bottom_area.set_offset(SIDE_TOP, -200)
	bottom_area.set_offset(SIDE_RIGHT, -90); bottom_area.set_offset(SIDE_BOTTOM, -8)
	bottom_area.add_theme_constant_override("separation", 8)

	# 営業ステータス 1行（キリコノートはホームから除外→経営overlayへ）
	store_top = VBoxContainer.new()
	store_top.add_theme_constant_override("separation", SP_1)
	var live := _shop_line() if (shop != null and shop.open) else "暖簾は仕舞われている。"
	shop_status = _label(live, TYPE_SMALL, COL_WARM)
	shop_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shop_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	store_top.add_child(shop_status)
	bottom_area.add_child(store_top)

	task_edit = LineEdit.new()
	task_edit.placeholder_text = "集中するタスクを書く…"
	task_edit.add_theme_font_size_override("font_size", 18)
	bottom_area.add_child(task_edit)

	var ctrl := HBoxContainer.new()
	ctrl.add_theme_constant_override("separation", 4)
	for opt in [["速", "quick", 0.0], ["15m", "pomo", 15.0], ["25m", "pomo", 25.0], ["50m", "pomo", 50.0]]:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = mode_group
		b.text = String(opt[0])
		b.add_theme_font_size_override("font_size", 15)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_mode.bind(String(opt[1]), float(opt[2])))
		if float(opt[2]) == 25.0:
			b.button_pressed = true
		ctrl.add_child(_juice(b))
	bottom_area.add_child(ctrl)

	var start := _cta("▶  集中を始める", _on_depart, TYPE_SUB)
	start.custom_minimum_size = Vector2(0, 52)
	if UIKit.available():
		UIKit.as_pomodoro(start)
	bottom_area.add_child(start)
	morning_panel.add_child(bottom_area)

	# ⑤ 互換ノード（_refresh_morning / overlay から参照される）
	morning_box = VBoxContainer.new()
	morning_box.visible = false
	ops_box = VBoxContainer.new()
	ops_box.add_theme_constant_override("separation", 6)
	mgmt_banner_sub = _label("", TYPE_SMALL, COL_DIM)
	forecast_label = _label("", 19, Color(1.0, 0.85, 0.5))
	stock_row = HBoxContainer.new()
	stock_row.add_theme_constant_override("separation", 2)
	door_btn = _button("", _on_door_policy, 17)
	girls_box = VBoxContainer.new()
	girls_box.add_theme_constant_override("separation", 5)
	menu_title = _label("献立", 15, COL_DIM)
	menu_box = VBoxContainer.new()
	morning_panel.add_child(morning_box)

	parent.add_child(morning_panel)
	_tab_pages.append(morning_panel)


## 丸型アイコンボタン（右ナビ用）。emoji + ラベル縦並び。
func _home_icon_btn(label_text: String, icon_char: String, cb: Callable) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 3)
	var btn := Button.new()
	btn.text = icon_char
	btn.custom_minimum_size = Vector2(60, 60)
	btn.flat = false
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 26)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	sb.border_color = Color(0.45, 0.45, 0.45, 0.8)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	sb.corner_radius_top_left = 30; sb.corner_radius_top_right = 30
	sb.corner_radius_bottom_left = 30; sb.corner_radius_bottom_right = 30
	btn.add_theme_stylebox_override("normal", sb)
	var sb_hover := sb.duplicate() as StyleBoxFlat
	sb_hover.bg_color = Color(0.1, 0.1, 0.1, 0.85)
	sb_hover.border_color = COL_ACCENT
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.pressed.connect(cb)
	wrap.add_child(btn)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(lbl)
	return wrap


func _build_dive_panel(parent: Control) -> void:
	dive_panel = VBoxContainer.new()
	dive_panel.add_theme_constant_override("separation", 8)
	dive_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	door_row = HBoxContainer.new()
	door_row.add_theme_constant_override("separation", 8)
	door_row.visible = false
	var open_b := _button("扉を開ける", _on_door_choice.bind(true), 22)
	open_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	door_row.add_child(open_b)
	var skip_b := _button("無視して進む", _on_door_choice.bind(false), 22)
	skip_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	door_row.add_child(skip_b)
	dive_panel.add_child(door_row)
	# 潜行中の育成導線：配信を観ながら、拾った装備のセット／スキル成長・装備（タップで各キャラ）
	dive_party_row = HBoxContainer.new()
	dive_party_row.add_theme_constant_override("separation", SP_1)
	dive_panel.add_child(dive_party_row)
	# 最小情報HUD（戦闘ログのスパムではなく、探索率・現在地・遭遇だけ）
	dive_info = _label("", TYPE_BODY, UIKit.SECONDARY)
	dive_info.autowrap_mode = TextServer.AUTOWRAP_OFF
	dive_panel.add_child(dive_info)
	# ボス遭遇バナー
	boss_banner = PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.22, 0.04, 0.04, 0.92)
	bsb.border_color = Color(0.85, 0.15, 0.15, 0.9)
	bsb.set_border_width_all(2)
	bsb.set_content_margin_all(6)
	bsb.corner_radius_top_left = 6; bsb.corner_radius_top_right = 6
	bsb.corner_radius_bottom_left = 6; bsb.corner_radius_bottom_right = 6
	boss_banner.add_theme_stylebox_override("panel", bsb)
	boss_banner.visible = false
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	boss_banner_tex = TextureRect.new()
	boss_banner_tex.custom_minimum_size = Vector2(48, 48)
	boss_banner_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	boss_banner_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	brow.add_child(boss_banner_tex)
	var bcol := VBoxContainer.new()
	bcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bcol.add_theme_constant_override("separation", 2)
	bcol.add_child(_label("⚠ BOSS", 13, Color(1.0, 0.35, 0.35)))
	var boss_name_lbl := _label("", 18, Color(1.0, 0.7, 0.7))
	boss_name_lbl.name = "BossName"
	bcol.add_child(boss_name_lbl)
	brow.add_child(bcol)
	boss_banner.add_child(brow)
	dive_panel.add_child(boss_banner)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.custom_minimum_size = Vector2(0, 120)
	log_label.add_theme_font_size_override("normal_font_size", 19)
	log_label.add_theme_color_override("default_color", COL_TEXT)
	dive_panel.add_child(log_label)
	abandon_btn = DS.as_danger(_button("撤退（切断）…", _on_abandon_pressed, TYPE_BODY))
	dive_panel.add_child(abandon_btn)
	# デバッグ早送り：アンカーを過去にずらすと次フレームのキャッチアップが
	# その分を固定ステップで一気に消化する（決定論は崩れない）
	var dbg := HBoxContainer.new()
	dbg.add_theme_constant_override("separation", 6)
	var dbg_label := _label("DEBUG", 14, Color(1, 1, 1, 0.3))
	dbg.add_child(dbg_label)
	for opt in [["≫ +1分", 60.0], ["≫ +10分", 600.0], ["≫ 完走まで", -1.0]]:
		var b := _button(String(opt[0]), _on_debug_ff.bind(float(opt[1])), 16)
		b.modulate = Color(1, 1, 1, 0.55)
		dbg.add_child(b)
	dive_panel.add_child(dbg)
	parent.add_child(dive_panel)


func _scroll_tab(title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	sc.add_child(box)
	_tab_content.add_child(sc)
	sc.visible = _tab_pages.is_empty()  # 最初のページだけ表示
	_tab_pages.append(sc)
	return box


func _build_member_tab() -> void:
	member_box = _scroll_tab("メンバー")


## メンバー一覧：各キャラのカード→詳細・スキルツリーへの明確な導線。
func _refresh_member() -> void:
	if member_box == null:
		return
	_clear(member_box)
	for id in KuroData.GIRL_ORDER:
		var g: Dictionary = KuroData.GIRLS[id]
		var gc: Color = g["color"]
		# キャラカラーをカード背景に薄く乗せる
		var card := PanelContainer.new()
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color(gc.r * 0.15, gc.g * 0.15, gc.b * 0.15)
		csb.border_color = Color(gc.r * 0.5, gc.g * 0.5, gc.b * 0.5, 0.7)
		csb.set_border_width_all(1)
		csb.set_content_margin_all(12)
		csb.corner_radius_top_left = 6; csb.corner_radius_top_right = 6
		csb.corner_radius_bottom_left = 6; csb.corner_radius_bottom_right = 6
		card.add_theme_stylebox_override("panel", csb)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		# ポートレート（大きめ）
		var pr := PortraitRect.new()
		pr.girl_id = id
		pr.custom_minimum_size = Vector2(72, 100)
		row.add_child(pr)
		# 情報列
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 3)
		info.add_child(_label(String(g["name"]), TYPE_SUB, gc))
		info.add_child(_label(String(g["role"]), TYPE_SMALL, COL_DIM))
		var hearts: int = clampi(int(round(sim.aff(id) / 20.0)), 0, 5)
		info.add_child(_label("♥".repeat(hearts) + "♡".repeat(5 - hearts), TYPE_SMALL, Color("e88fb0")))
		info.add_child(_label("攻 %d  HP %d" % [int(sim.girl_atk(id)), int(sim.girl_maxhp(id))],
				TYPE_SMALL, COL_DIM))
		row.add_child(info)
		var btn := _button("育成", _open_status.bind(id), TYPE_SMALL)
		if UIKit.available():
			UIKit.as_primary(btn)
		row.add_child(btn)
		card.add_child(row)
		member_box.add_child(card)


func _build_memory_tab() -> void:
	memo_box = _scroll_tab("記憶")


## 記憶アーカイブ：道中で拾ったメモリ（短文小説）を読む。未収集は ？？？。
## 表層はカジュアル、裏に不穏さ——掘る人だけが読む。
func _refresh_memory_archive() -> void:
	if memo_box == null:
		return
	_clear(memo_box)
	var got: Array = sim.state.get("memories", [])
	memo_box.add_child(_label("記憶のかけら %d / %d　― 潜るほど見つかる ―"
			% [got.size(), KuroMemories.MEMORIES.size()], TYPE_SMALL, COL_DIM))
	var purple := UIKit.ACCENT if UIKit.available() else DS.ACCENT
	for m in KuroMemories.MEMORIES:
		var owned: bool = m["id"] in got
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _card_sb())
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", SP_1)
		if owned:
			box.add_child(_label(String(m["title"]), TYPE_SUB, purple))
			var body := _label(String(m["text"]), TYPE_BODY, COL_TEXT)
			body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(body)
		else:
			box.add_child(_label("？？？", TYPE_SUB, COL_DIM))
			box.add_child(_label("（B%dF 付近で見つかる）" % int(m["floor"]), TYPE_SMALL, COL_DIM))
		card.add_child(box)
		memo_box.add_child(card)


func _build_inventory_tab() -> void:
	inv_box = _scroll_tab("倉庫")


func _build_renov_tab() -> void:
	var box := _scroll_tab("改装")
	renov_info = _label("ノードをタップして解放（隣のノードから順に）", 17, COL_DIM)
	box.add_child(renov_info)
	renov_view = RenovView.new()
	renov_view.sim = sim
	renov_view.node_tapped.connect(_on_renov_tapped)
	box.add_child(renov_view)


func _build_stats_tab() -> void:
	stats_box = _scroll_tab("統計")


func _build_tab_footer() -> void:
	var footer_panel := PanelContainer.new()
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.04, 0.03, 0.06, 0.92)
	fsb.border_color = Color(DS.LINE.r, DS.LINE.g, DS.LINE.b, 0.5)
	fsb.border_width_top = 1
	fsb.set_content_margin_all(0)
	footer_panel.add_theme_stylebox_override("panel", fsb)
	_tab_footer = HBoxContainer.new()
	_tab_footer.add_theme_constant_override("separation", 0)
	footer_panel.add_child(_tab_footer)
	tabs.add_child(footer_panel)

	# 4タブ: 0=店(page), 1=メンバー(page), 2=市場(overlay), 3=経営(overlay)
	var tab_data: Array = [
		["店",      "ui/tab_shop",      _switch_tab.bind(0)],
		["メンバー", "ui/tab_member",    _switch_tab.bind(1)],
		["市場",    "ui/tab_market",    func(): _close_all_overlays(); _open_market()],
		["経営",    "ui/tab_mgmt",      func(): _close_all_overlays(); _open_management()],
	]
	for i in tab_data.size():
		var entry: Array = tab_data[i]
		var btn := Button.new()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 62)
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 2)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.set_anchors_preset(Control.PRESET_FULL_RECT)
		var icon_tex := _gen_tex(String(entry[1]))
		var ir := _icon_rect(icon_tex, 28)
		ir.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ir.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(ir)
		var lbl := Label.new()
		lbl.text = String(entry[0])
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(lbl)
		btn.add_child(col)
		btn.pressed.connect(entry[2] as Callable)
		_tab_footer.add_child(btn)
		_tab_buttons.append(btn)
	_update_tab_buttons()


## 全オーバーレイを閉じてタブビューに戻る（フッターからオーバーレイ切替時に使う）。
func _close_all_overlays() -> void:
	for ov in [management_overlay, box_overlay, formation_overlay, market_overlay, ship_overlay]:
		if ov != null and ov.visible:
			ov.visible = false
	if tabs != null:
		tabs.visible = true


func _switch_tab(idx: int) -> void:
	if idx == _tab_active:
		return
	_tab_active = idx
	for i in _tab_pages.size():
		_tab_pages[i].visible = (i == idx)
	_update_tab_buttons()
	_sfx("ui_tab")


func _update_tab_buttons() -> void:
	for i in _tab_buttons.size():
		var btn: Button = _tab_buttons[i]
		var active := (i == _tab_active)
		# アクティブ：シアン、非アクティブ：薄いグレー
		btn.modulate = COL_ACCENT if active else Color(COL_DIM.r, COL_DIM.g, COL_DIM.b, 0.7)
		# アクティブタブの下線
		var sb := StyleBoxFlat.new()
		if active:
			sb.bg_color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.08)
			sb.border_color = COL_ACCENT
			sb.border_width_top = 2
		else:
			sb.bg_color = Color(0, 0, 0, 0)
			sb.border_color = Color(0, 0, 0, 0)
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover",  sb)
		btn.add_theme_stylebox_override("pressed", sb)


func _build_close() -> void:
	# 全画面オーバーレイ＋中央カード（はみ出し防止のため幅をマージンで束縛）
	close_panel = Control.new()
	close_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	close_panel.visible = false
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.04, 0.03, 0.82)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	close_panel.add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(m, 28)
	close_panel.add_child(margin)
	# 縦スペーサーで上下中央寄せしつつ、カードは束縛幅いっぱいに広げる
	var col := VBoxContainer.new()
	margin.add_child(col)
	var sp_top := Control.new()
	sp_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sp_top)
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", SP_3)
	box.add_child(_section("休憩 — 焚き火"))
	close_text = _label("", TYPE_BODY)
	close_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(close_text)
	# 焚き火で一息 → 店に戻る（店は常時営業。次の集中は店の「集中を始める」から）
	var to_shop := _cta("🏮 店に戻る", _on_return_to_store, TYPE_SUB)
	to_shop.custom_minimum_size = Vector2(0, 54)
	box.add_child(to_shop)
	card.add_child(box)
	col.add_child(card)
	var sp_bot := Control.new()
	sp_bot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sp_bot)
	add_child(close_panel)


func _build_audio() -> void:
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		sfx_pool.append(p)
	# ElevenLabs(mp3) > 手続き生成(wav) > 現行（CC0/手続き）の順で優先
	bgm = _make_loop(_audio_pick("bgm_el/store", "res://assets/third_party/music/sketchbook_loop.ogg"), -16.0)
	bgm_dive = _make_loop(_audio_pick("bgm_el/dive", "res://assets/generated/bgm/dive_drone.wav"), -60.0)
	bgm_battle = _make_loop(_audio_pick("bgm_el/battle", "res://assets/generated/bgm/battle_layer.wav"), -60.0)


## 生成BGMがあればそのパス（mp3優先・無ければwav）、無ければフォールバックを返す。
func _audio_pick(gen_base: String, fallback: String) -> String:
	var base := "res://assets/generated/" + gen_base
	if ResourceLoader.exists(base + ".mp3"):
		return base + ".mp3"
	if ResourceLoader.exists(base + ".wav"):
		return base + ".wav"
	return fallback


## ループ再生する AudioStreamPlayer を作る（OGG/WAV 両対応）。
func _make_loop(path: String, vol_db: float) -> AudioStreamPlayer:
	if not ResourceLoader.exists(path):
		return null
	var p := AudioStreamPlayer.new()
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamMP3:
		stream.loop = true  # ElevenLabs生成のBGM
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	p.stream = stream
	p.volume_db = vol_db
	add_child(p)
	return p


## フェーズ・戦況でBGMをクロスフェード（店⇄潜行＋戦闘レイヤー）。
func _update_bgm(delta: float) -> void:
	var diving := phase == Phase.DIVE
	var in_combat: bool = diving and sim.state["in_combat"]
	_fade(bgm, -16.0 if not diving else -42.0, delta)
	_fade(bgm_dive, -10.0 if diving else -60.0, delta)
	_fade(bgm_battle, -10.0 if in_combat else -60.0, delta)


func _fade(p: AudioStreamPlayer, target_db: float, delta: float) -> void:
	if p == null:
		return
	# 鳴っていなければ開始（ユーザー操作後＝Webの自動再生制限を回避）
	if not p.playing and bgm != null and bgm.playing and target_db > -55.0:
		p.play()
	p.volume_db = move_toward(p.volume_db, target_db, 30.0 * delta)


func _label(text: String, font_size: int, color := COL_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	# AUTOWRAP_OFF がデフォルト：HBoxContainer内で文字が1列縦積みになるのを防ぐ。
	# 折り返しが必要な場所では呼び出し元で設定する。
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


## Vignelli の「ルーラー」：フラッシュレフトの小見出し＋直下に 2px の罫。
## 中央寄せの「― 〜 ―」を置き換え、型を吊るす規律にする。
func _section(text: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", SP_1)
	var lbl := _label(text, TYPE_SMALL, COL_ACCENT)
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(lbl)
	var rule := ColorRect.new()
	rule.color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.5)
	rule.custom_minimum_size = Vector2(0, 2)
	box.add_child(rule)
	return box


func _button(text: String, cb: Callable, font_size := TYPE_SUB) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.pressed.connect(cb)
	return _juice(b)


## 押し心地：押下で少し縮み、離すとポンと戻る。全ボタンに自動適用。
## トグル等 Button.new() を直接作る箇所も _juice(b) を通せば同じ手触りになる。
func _juice(b: Button) -> Button:
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.button_down.connect(func() -> void:
		b.pivot_offset = b.size * 0.5
		create_tween().tween_property(b, "scale", Vector2(0.93, 0.93), 0.06))
	b.button_up.connect(func() -> void:
		var tw := create_tween()
		tw.tween_property(b, "scale", Vector2(1.05, 1.05), 0.07)
		tw.tween_property(b, "scale", Vector2.ONE, 0.08))
	return b


var _gen_cache := {}


func _gen_tex(path: String) -> Texture2D:
	if not _gen_cache.has(path):
		var full := "res://assets/generated/%s.png" % path
		_gen_cache[path] = load(full) if ResourceLoader.exists(full) else null
	return _gen_cache[path]


func _food_icon(id: String) -> Texture2D:
	return _gen_tex("food/" + id)


func _box_icon(grade: int) -> Texture2D:
	return _gen_tex("box/%d" % grade)


func _ing_icon(kind: String) -> Texture2D:
	return _gen_tex("ing/" + kind)


func _icon_rect(tex: Texture2D, sz: int) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = Vector2(sz, sz)
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return tr


## サブ画面のカード/行パネル。UIキットがあれば9-patch、無ければDSフラット。
func _card_sb() -> StyleBox:
	return UIKit.row_box(DS.SP_2) if UIKit.available() else DS._sb(DS.SURFACE, DS.LINE, DS.R_SM, DS.SP_2)


func _girl_icon(id: String) -> TextureRect:
	var tr := TextureRect.new()
	var sprite: String = KuroData.GIRLS[id]["sprite"]
	var path := "res://assets/third_party/dungeon/frames/%s_idle_anim_f0.png" % sprite
	if not ResourceLoader.exists(path):
		path = "res://assets/third_party/dungeon/frames/%s_anim_f0.png" % sprite
	if ResourceLoader.exists(path):
		tr.texture = load(path)
	tr.custom_minimum_size = Vector2(52, 78)
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.modulate = Color(1.08, 1.0, 0.9)  # わずかに暖色へ寄せる
	return tr


# --- 表示更新 ----------------------------------------------------------------


func _refresh_all() -> void:
	_refresh_header()
	if phase == Phase.MORNING:
		_refresh_morning()
	# サブタブ（メンバー/記憶/倉庫/統計）はタブが表示中かつタブ1以降が選択されているとき更新
	if tabs != null and tabs.visible and _tab_active >= 1:
		_refresh_member()
		_refresh_memory_archive()
		_refresh_inventory()
		_refresh_stats()
		if renov_view != null:
			renov_view.queue_redraw()


## ヘッダーの資源バー（アイコン付きバッジ）。
func _refresh_header() -> void:
	var s := sim.state
	_clear(header_bar)
	header_bar.add_child(_badge(null, "Day %d" % int(s["day"]), COL_WARM))
	header_bar.add_child(_badge(null, "金%d" % int(s["gold"]), Color(1.0, 0.86, 0.5)))
	header_bar.add_child(_badge(_box_icon(2), "%d" % s["boxes"].size()))
	if int(s["streak"]) > 0:
		header_bar.add_child(_badge(null, "連%d" % int(s["streak"]), COL_ACCENT))
	# 右寄せのスペーサー＋廃材
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_bar.add_child(sp)
	header_bar.add_child(_badge(null, "欠片%d" % int(s["shards"]), Color(1.0, 0.7, 0.85)))
	header_bar.add_child(_badge(null, "屑%d" % int(s["scrap"]), DS.SUCCESS))


func _refresh_morning() -> void:
	var s := sim.state
	# ホーム画面のキャラ全画面レイアウト：左上バッジを更新
	if home_day_lbl != null and is_instance_valid(home_day_lbl):
		home_day_lbl.text = "Day %d" % int(s["day"])
	if home_gold_lbl != null and is_instance_valid(home_gold_lbl):
		var streak := int(s["streak"])
		home_gold_lbl.text = "金 %dG%s" % [int(s["gold"]), "  ⚡%d" % streak if streak > 0 else ""]
	if home_box_badge != null and is_instance_valid(home_box_badge):
		var bn: int = (s["boxes"] as Array).size()
		home_box_badge.text = "×%d" % bn if bn > 0 else ""
	# キャラ会話バッジ＋吹き出し更新
	var av_talk := sim.available_talk()
	var av_girl := String(av_talk.get("girl", "")) if not av_talk.is_empty() else ""
	for gid in home_char_badges:
		var cbdg: Label = home_char_badges[gid]
		if is_instance_valid(cbdg):
			cbdg.text = "！" if gid == av_girl else ""
	if home_speech_lbl != null and is_instance_valid(home_speech_lbl):
		if not av_girl.is_empty():
			var sc: Dictionary = TalkData.TALKS[av_girl][int(av_talk.get("tier", 0))]
			var title := String(sc.get("title", ""))
			home_speech_lbl.text = "「%s」" % title
			# 会話あり → そのキャラの FaceCam に口パク（タイトルで口の動きをプレビュー）
			if home_face_cams.has(av_girl):
				var fc: FaceCam = home_face_cams[av_girl]
				if is_instance_valid(fc) and not fc.speaking:
					fc.start_speech(title)
		else:
			home_speech_lbl.text = ""
	# 営業ライブ（毎秒更新）- store_top はホーム画面下部に配置済み。shop_status を更新。
	if shop_status != null and is_instance_valid(shop_status):
		var live := _shop_line() if (shop != null and shop.open) else "暖簾は仕舞われている。"
		shop_status.text = live
	# キリコ依頼は _build_morning で初期追加済み。動的更新が必要なら store_top を再構築:
	# (省略: 依頼内容は変わらないため静的でよい)
	forecast_label.text = "%s予報『%s』の客が多い夜" % [offline_note, s["forecast"]]
	# 素材在庫をアイコン付きで
	_clear(stock_row)
	for kind in KuroData.INGS:
		var ic := _ing_icon(kind)
		if ic != null:
			stock_row.add_child(_icon_rect(ic, 26))
		var sl := _label("%s%d　" % [KuroData.ING_NAMES[kind], int(s["stock"][kind])], 18, COL_DIM)
		sl.autowrap_mode = TextServer.AUTOWRAP_OFF
		stock_row.add_child(sl)
	_clear(girls_box)
	var _avail := KuroData.GIRL_ORDER.filter(func(x): return s["girls"].has(x))
	if _avail.is_empty():
		return
	if not _avail.has(_formation_sel):
		_formation_sel = _avail[0]
	girls_box.add_child(_girl_hero_panel(_formation_sel))
	menu_title.text = "献立 %d/%d枠 ｜ ◎=予報一致 ⚠=素材切れ" % [s["morning"]["menu"].size(), sim.menu_limit()]
	_clear(menu_box)
	var menu: Array = s["morning"]["menu"]
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 5)
	for id in s["recipes"]:
		if int(s["recipes"][id]) <= 0:
			continue
		var r: Dictionary = KuroData.RECIPES[id]
		var star := int(s["recipes"][id])
		var in_menu: bool = id in menu
		var hit: bool = r["taste"] == s["forecast"]
		var ing_stock := int(s["stock"].get(r["ing"], 0))
		var b2 := Button.new()
		b2.toggle_mode = true
		b2.button_pressed = in_menu
		b2.text = "%s%s☆%d %s%d%s%s" % ["● " if in_menu else "", r["name"], star,
				KuroData.ING_NAMES[r["ing"]], ing_stock,
				" ◎" if hit else "", " ！" if ing_stock <= 0 else ""]
		b2.add_theme_font_size_override("font_size", 17)
		var fi := _food_icon(id)
		if fi != null:
			b2.icon = fi
			b2.add_theme_constant_override("icon_max_width", 26)
		if in_menu:
			b2.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
		b2.pressed.connect(_on_menu_toggle.bind(String(id)))
		flow.add_child(_juice(b2))
	menu_box.add_child(flow)
	door_btn.text = "扉方針：%s" % ("開ける" if s["morning"]["door"] == "open" else "無視する")
	# 経営バナーのサマリを更新
	if mgmt_banner_sub != null and is_instance_valid(mgmt_banner_sub):
		mgmt_banner_sub.text = "編成・闇市・交易船"
	# 経営サブ画面が開いていれば中身も更新
	if management_overlay != null and management_overlay.visible:
		_clear(ops_box)
		_fill_ops(ops_box)


## 経営UI（編成・闇市・交易船の3導線のみ）を box に充填。
func _fill_ops(box: VBoxContainer) -> void:
	var s := sim.state
	box.add_child(_formation_banner_btn(s))
	box.add_child(_market_banner_btn(s))
	box.add_child(_ship_banner_btn(s))


## コンパクトな編成カード（小型立ち絵＋2行＋店番トグル）。
func _girl_card(id: String) -> PanelContainer:
	var s := sim.state
	var g: Dictionary = KuroData.GIRLS[id]
	var keeper: bool = s["morning"]["keeper"] == id
	var panel := PanelContainer.new()
	if keeper:
		panel.add_theme_stylebox_override("panel", DS.card_accent(COL_WARM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	# 立ち絵タップで詳細（ステータス）画面
	var icon_btn := Button.new()
	icon_btn.flat = true
	icon_btn.custom_minimum_size = Vector2(44, 58)
	icon_btn.pressed.connect(_open_status.bind(id))
	var icon := _girl_icon(id)
	icon.custom_minimum_size = Vector2(38, 54)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_btn.add_child(icon)
	row.add_child(icon_btn)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	var role := "店番" if keeper else "潜行"
	col.add_child(_label("%s ♥%d  攻%d HP%d  好%s" % [g["name"], sim.aff(id),
			int(sim.girl_atk(id)), int(sim.girl_maxhp(id)), g["fav"]], 18, g["color"]))
	# スキルチップ（コンパクト）
	var skill_row := HBoxContainer.new()
	skill_row.add_theme_constant_override("separation", 3)
	for sid in sim.known_skills(id):
		var def: Dictionary = KuroData.SKILL_DB[sid]
		var equipped: bool = sid in s["girls"][id]["skills_eq"]
		var sk := _button(("★" if equipped else "") + String(def["name"]), _on_skill_toggle.bind(id, String(sid)), 14)
		if not equipped and s["girls"][id]["skills_eq"].size() >= sim.skill_slots():
			sk.disabled = true
		skill_row.add_child(sk)
	if keeper:
		var syn := _label("→ %s" % g["synergy"], 14, Color(1.0, 0.85, 0.5))
		syn.autowrap_mode = TextServer.AUTOWRAP_OFF
		skill_row.add_child(syn)
	col.add_child(skill_row)
	row.add_child(col)
	var b := _button(role, _on_keeper.bind(id), 18)
	b.custom_minimum_size = Vector2(58, 0)
	b.disabled = keeper
	if keeper:
		b.modulate = Color(1.0, 0.85, 0.5)
	row.add_child(b)
	panel.add_child(row)
	return panel


## モバイルRPGスタイル編成ビュー（全員潜航）。
## タブ→キャラ切替、大型立ち絵＋詳細ボタン、ステータス、スキルグリッド。
func _girl_hero_panel(id: String) -> VBoxContainer:
	var s := sim.state
	assert(KuroData.GIRLS.has(id) and s["girls"].has(id),
			"_girl_hero_panel: '%s' はセーブデータに存在しません" % id)
	var g: Dictionary = KuroData.GIRLS[id]
	var gc: Color = g["color"]

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)

	# ── キャラ選択タブ ──────────────────────────────────────
	var sel_row := HBoxContainer.new()
	sel_row.add_theme_constant_override("separation", 3)
	for gid in KuroData.GIRL_ORDER:
		if not s["girls"].has(gid):
			continue
		var gg: Dictionary = KuroData.GIRLS[gid]
		var is_sel: bool = gid == id
		var tab := Button.new()
		tab.flat = true
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size = Vector2(0, 68)
		var tab_col := VBoxContainer.new()
		tab_col.alignment = BoxContainer.ALIGNMENT_CENTER
		tab_col.add_theme_constant_override("separation", 3)
		tab_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var face_wrap := Control.new()
		face_wrap.custom_minimum_size = Vector2(48, 48)
		face_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		face_wrap.clip_contents = true
		face_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var face_tex := _gen_tex("face/%s/neutral_closed" % gid)
		if face_tex != null:
			var face_tr := TextureRect.new()
			face_tr.texture = face_tex
			face_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			face_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			face_tr.set_anchors_preset(Control.PRESET_FULL_RECT)
			face_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			face_wrap.add_child(face_tr)
		else:
			var icon := _girl_icon(gid)
			icon.set_anchors_preset(Control.PRESET_FULL_RECT)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			face_wrap.add_child(icon)
		tab_col.add_child(face_wrap)
		var name_lbl := _label(String(gg["name"]), TYPE_SMALL,
				gg["color"] if is_sel else COL_DIM)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tab_col.add_child(name_lbl)
		tab.add_child(tab_col)
		var tsb := StyleBoxFlat.new()
		tsb.bg_color = Color(gg["color"].r * 0.22, gg["color"].g * 0.22,
				gg["color"].b * 0.28, 0.95) if is_sel \
				else Color(DS.BG.r, DS.BG.g, DS.BG.b, 0.88)
		tsb.border_width_bottom = 3
		tsb.border_color = gg["color"] if is_sel \
				else Color(gg["color"].r, gg["color"].g, gg["color"].b, 0.25)
		tsb.set_corner_radius_all(DS.R_SM)
		tsb.set_content_margin_all(4)
		tab.add_theme_stylebox_override("normal", tsb)
		tab.add_theme_stylebox_override("hover", tsb)
		tab.add_theme_stylebox_override("pressed", tsb)
		tab.pressed.connect(func():
			_formation_sel = gid
			_refresh_morning())
		sel_row.add_child(_juice(tab))
	outer.add_child(sel_row)

	# ── ヒーローパネル（大型立ち絵＋詳細ボタン）────────────────
	var hero_panel := PanelContainer.new()
	var hero_sb := StyleBoxFlat.new()
	hero_sb.bg_color = Color(gc.r * 0.10, gc.g * 0.10, gc.b * 0.15)
	hero_sb.border_color = Color(gc.r, gc.g, gc.b, 0.5)
	hero_sb.set_border_width_all(1)
	hero_sb.set_corner_radius_all(DS.R_LG)
	hero_sb.set_content_margin_all(10)
	hero_panel.add_theme_stylebox_override("panel", hero_sb)
	var hero_col := VBoxContainer.new()
	hero_col.add_theme_constant_override("separation", 6)
	var pr := PortraitRect.new()
	pr.girl_id = id
	pr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pr.custom_minimum_size = Vector2(0, 160)
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_col.add_child(pr)
	# 詳細ボタン（affordance を明示）
	var detail_btn := _button("詳細 ▶", _open_status.bind(id), TYPE_SMALL)
	detail_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	detail_btn.custom_minimum_size = Vector2(92, 30)
	hero_col.add_child(detail_btn)
	hero_panel.add_child(hero_col)
	outer.add_child(hero_panel)

	# ── ステータス行 ────────────────────────────────────────
	var stats_panel := PanelContainer.new()
	stats_panel.add_theme_stylebox_override("panel", DS.card_style())
	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 16)
	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.add_theme_constant_override("separation", 2)
	name_col.add_child(_label(String(g["name"]), TYPE_SUB, gc))
	name_col.add_child(_label(String(g["role"]), TYPE_SMALL, COL_DIM))
	var hearts: int = clampi(int(round(sim.aff(id) / 20.0)), 0, 5)
	name_col.add_child(_label(
			"♥".repeat(hearts) + "♡".repeat(5 - hearts), TYPE_SMALL, Color("e88fb0")))
	stats_row.add_child(name_col)
	var nums_col := VBoxContainer.new()
	nums_col.add_theme_constant_override("separation", 3)
	nums_col.add_child(_label("攻  %d" % int(sim.girl_atk(id)), TYPE_SMALL, Color(1.0, 0.75, 0.5)))
	nums_col.add_child(_label("HP  %d" % int(sim.girl_maxhp(id)), TYPE_SMALL, Color(0.5, 1.0, 0.7)))
	nums_col.add_child(_label("好み  %s" % String(g["fav"]), TYPE_SMALL, COL_DIM))
	stats_row.add_child(nums_col)
	stats_panel.add_child(stats_row)
	outer.add_child(stats_panel)

	# ── スキルグリッド（2列、装備済み=★オレンジ→未装備=dim）──
	var known := sim.known_skills(id)
	var eq_set: Array = s["girls"][id]["skills_eq"]
	var max_slots: int = sim.skill_slots()
	if not known.is_empty():
		var skill_section := VBoxContainer.new()
		skill_section.add_theme_constant_override("separation", 6)
		skill_section.add_child(_section("スキル  %d/%d 装備中" % [eq_set.size(), max_slots]))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		# 装備済みを先に、未装備を後に
		var sorted: Array = []
		for sid in known:
			if String(sid) in eq_set:
				sorted.insert(0, sid)
			else:
				sorted.append(sid)
		for sid in sorted:
			var sid_str: String = String(sid)
			var def: Dictionary = KuroData.SKILL_DB[sid_str]
			var equipped: bool = sid_str in eq_set
			var full: bool = not equipped and eq_set.size() >= max_slots
			var sk := Button.new()
			sk.text = ("★ " if equipped else "") + String(def["name"])
			sk.add_theme_font_size_override("font_size", 14)
			sk.custom_minimum_size = Vector2(0, 46)
			sk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sk.disabled = full
			if equipped:
				DS.as_primary(sk)
			elif full:
				sk.modulate = Color(1, 1, 1, 0.45)
			sk.pressed.connect(_on_skill_toggle.bind(id, sid_str))
			_juice(sk)
			grid.add_child(sk)
		# 奇数スキル数のとき2列目を空パディング
		if sorted.size() % 2 == 1:
			var pad := Control.new()
			pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(pad)
		skill_section.add_child(grid)
		outer.add_child(skill_section)

	return outer


## ホームの主役：店内イラスト（提供アート）。無ければ立ち絵シーンにフォールバック。
func _build_home_hero() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", SP_2)
	var bg := "res://assets/art/home_bg.png"
	if ResourceLoader.exists(bg):
		var tr := TextureRect.new()
		tr.texture = load(bg)
		# COVERED＋明示高さ＋clip で確実に大きく表示（FIT_WIDTH_PROPORTIONAL は
		# VBox内で高さ0に潰れて表示されないことがあるため使わない）。
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.custom_minimum_size = Vector2(0, 160)
		tr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tr.clip_contents = true
		box.add_child(tr)
	else:
		box.add_child(_build_shop_scene())
	var rep: int = clampi(sim.sign_total(), 0, 5)
	box.add_child(_label("評判 " + "★".repeat(rep) + "☆".repeat(5 - rep), TYPE_SMALL, COL_WARM))
	return box


## 店モードの"額縁"：皆が戻った店内の立ち絵＋営業ライブ＋評判。
func _build_shop_scene() -> PanelContainer:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", SP_2)
	# 店内：パーティの立ち絵が並ぶ（営業中は皆が戻っている）
	var cast := HBoxContainer.new()
	cast.add_theme_constant_override("separation", SP_1)
	cast.alignment = BoxContainer.ALIGNMENT_CENTER
	for id in KuroData.GIRL_ORDER:
		var pr := PortraitRect.new()
		pr.girl_id = id
		pr.custom_minimum_size = Vector2(64, 96)
		pr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pr.mouse_filter = Control.MOUSE_FILTER_STOP  # タップで詳細/スキルツリーへ
		pr.tooltip_text = "%s の詳細・スキルツリー" % String(KuroData.GIRLS[id]["name"])
		pr.gui_input.connect(_on_portrait_input.bind(id))
		cast.add_child(pr)
	# 依頼人キリコ（NPC・紫）も在席。タップで彼女のひとこと。
	var kp := PortraitRect.new()
	kp.girl_id = "kiriko_npc"
	kp.custom_minimum_size = Vector2(64, 96)
	kp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kp.mouse_filter = Control.MOUSE_FILTER_STOP
	kp.tooltip_text = "キリコ（依頼人）"
	kp.gui_input.connect(_on_kiriko_tap)
	cast.add_child(kp)
	box.add_child(cast)
	# 営業状況＋評判を1行に
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", SP_2)
	var live := _shop_line() if (shop != null and shop.open) else "暖簾は仕舞われている。"
	shop_status = _label(live, TYPE_SMALL, COL_WARM)
	shop_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	status_row.add_child(shop_status)
	var rep: int = clampi(sim.sign_total(), 0, 5)
	status_row.add_child(_label("★".repeat(rep) + "☆".repeat(5 - rep), TYPE_SMALL, COL_WARM))
	box.add_child(status_row)
	panel.add_child(box)
	return panel


## 依頼人キリコの立ち絵タップ → ひとこと（軽く）。
func _on_kiriko_tap(event: InputEvent) -> void:
	var tapped: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed)
	if not tapped:
		return
	var lines := ["…今日も、暖簾を出してくれたんだ", "まだ、考えてくれてる?",
			"あったかいの、おいしかった", "急がなくていいよ。ここにいるから"]
	_sfx("ui_confirm")
	_notify("キリコ「%s」" % lines[randi() % lines.size()])


## 本日の献立カード（食アイコン＋名前）。
func _build_menu_cards() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", SP_1)
	box.add_child(_section("本日の献立"))
	var menu: Array = sim.state["morning"]["menu"]
	if menu.is_empty():
		box.add_child(_label("献立が空。準備で一品入れて。", TYPE_SMALL, COL_DIM))
		return box
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	for id in menu:
		var r: Dictionary = KuroData.RECIPES[id]
		var card := PanelContainer.new()
		var cb := VBoxContainer.new()
		cb.alignment = BoxContainer.ALIGNMENT_CENTER
		var fi := _food_icon(String(id))
		if fi != null:
			cb.add_child(_icon_rect(fi, 40))
		cb.add_child(_label(String(r["name"]), TYPE_SMALL, COL_TEXT))
		card.add_child(cb)
		flow.add_child(card)
	box.add_child(flow)
	return box


## 依頼人キリコの常設依頼チップ（コンパクト1行）。
## 紫＝精神世界/キリコの識別色。
func _build_kiriko_request() -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var kr := UIKit.KIRIKO if UIKit.available() else Color("cdb4db")
	var kr_d := UIKit.KIRIKO_DANGER if UIKit.available() else Color("9d4edd")
	sb.bg_color = Color(kr_d.r * 0.15, kr_d.g * 0.1, kr_d.b * 0.2)
	sb.border_color = kr_d
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	sb.corner_radius_top_left = 4; sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4; sb.corner_radius_bottom_right = 4
	card.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_label("依頼", TYPE_SMALL, kr))
	row.add_child(_label("キリコ「私を殺してほしい」", TYPE_SMALL, kr_d))
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	row.add_child(_label("― 未応答 ―", TYPE_SMALL, kr))
	card.add_child(row)
	return card


## 編成・献立エントリーバナーボタン（ホーム画面からページへの導線）。
func _formation_banner_btn(s: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.08, 0.05)
	sb.border_color = Color(0.4, 0.32, 0.1)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(12)
	sb.corner_radius_top_left = 6; sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6; sb.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
				or (e is InputEventScreenTouch and e.pressed):
			_open_formation())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	col.add_child(_label("編成・献立", TYPE_SUB, Color(1.0, 0.85, 0.5)))
	var menu_count: int = s["morning"]["menu"].size()
	col.add_child(_label("献立 %d品 ／ 全員潜航" % menu_count, TYPE_SMALL, COL_DIM))
	row.add_child(col)
	row.add_child(_label("▶", TYPE_HEAD, Color(0.6, 0.5, 0.2)))
	panel.add_child(row)
	return panel


## 闇市エントリーバナーボタン（ホーム画面からページへの導線）。
func _market_banner_btn(s: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.07, 0.02)
	sb.border_color = Color(0.55, 0.28, 0.06)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(12)
	sb.corner_radius_top_left = 6; sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6; sb.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
				or (e is InputEventScreenTouch and e.pressed):
			_open_market())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	col.add_child(_label("闇　市", TYPE_SUB, Color(1.0, 0.65, 0.2)))
	col.add_child(_label("%d種の品が入荷中" % KuroData.MARKET.size(), TYPE_SMALL, Color(0.85, 0.65, 0.45)))
	row.add_child(col)
	var arrow := _label("▶", TYPE_HEAD, Color(0.7, 0.4, 0.1))
	row.add_child(arrow)
	panel.add_child(row)
	return panel


## 交易船エントリーバナーボタン（ホーム画面からページへの導線）。
func _ship_banner_btn(s: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.09, 0.17)
	sb.border_color = Color(0.15, 0.45, 0.75)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(12)
	sb.corner_radius_top_left = 6; sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6; sb.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
				or (e is InputEventScreenTouch and e.pressed):
			_open_ship())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	col.add_child(_label("交 易 船", TYPE_SUB, Color(0.3, 0.85, 1.0)))
	var now := Time.get_unix_time_from_system()
	var stock_count: int = s["ship"]["stock"].size()
	var sub_text := "%d点の希少品" % stock_count if stock_count > 0 else "（出払い中）"
	col.add_child(_label(sub_text, TYPE_SMALL, Color(0.5, 0.75, 0.9)))
	row.add_child(col)
	var arrow := _label("▶", TYPE_HEAD, Color(0.2, 0.55, 0.85))
	row.add_child(arrow)
	panel.add_child(row)
	return panel


## リスト行コンポーネント：[アイコン] 見出し（伸長）[末尾アクション]。
## 闇市・交易船など「1行1アクション」のリストに使う。面はSURFACEの薄カード。
func _list_row(title: String, action_text: String, cb: Callable, enabled: bool,
		icon: Texture2D = null, title_color := COL_TEXT) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _card_sb())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SP_2)
	if icon != null:
		row.add_child(_icon_rect(icon, 30))
	var lbl := _label(title, TYPE_BODY, title_color)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var act := _button(action_text, cb, TYPE_BODY)
	act.disabled = not enabled
	act.custom_minimum_size = Vector2(78, 0)
	row.add_child(act)
	panel.add_child(row)
	return panel


func _ship_head(now: float) -> String:
	var rem := maxf(0.0, KuroData.SHIP_ROTATE_SEC - (now - float(sim.state["ship"]["rotated"])))
	return "交易船　入替まで %s" % _mmss(rem)


func _refresh_inventory() -> void:
	_clear(inv_box)
	var s := sim.state
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", SP_2)
	row.add_child(_badge(null, "屑 %d" % int(s["scrap"]), DS.SUCCESS))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	row.add_child(_button("一括分解", _on_bulk_salvage, TYPE_BODY))
	row.add_child(_button("合成 3→1", _on_synthesize, TYPE_BODY))
	inv_box.add_child(row)
	# 装備中サマリ
	inv_box.add_child(_section("装備中"))
	for id in KuroData.GIRL_ORDER:
		var parts: Array[String] = []
		for slot in ["weapon", "armor", "trinket"]:
			var it: Dictionary = s["girls"][id]["equip"][slot]
			parts.append("—" if it.is_empty() else SimItems.display_name(it))
		var sl := _label("%s  %s" % [KuroData.GIRLS[id]["name"], "  ".join(parts)], TYPE_SMALL, COL_DIM)
		sl.autowrap_mode = TextServer.AUTOWRAP_OFF
		inv_box.add_child(sl)
	var inv: Array = s["inventory"]
	inv_box.add_child(_section("倉庫"))
	if inv.is_empty():
		inv_box.add_child(_label("倉庫は空。潜って拾おう（装備は自動装着される）", TYPE_SMALL, COL_DIM))
		return
	var sorted_items := inv.duplicate()
	sorted_items.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	var shown: int = mini(sorted_items.size(), 40)
	for k in shown:
		var it: Dictionary = sorted_items[k]
		var target := _equip_target(it)
		var diff := float(it["score"]) - float(target["cur_score"])
		var badge := ("▲+%d" % int(diff)) if diff > 0.0 else ("▼%d" % int(diff))
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _card_sb())
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", SP_1)
		var slot_ic := _gen_tex("equip/" + String(it["slot"]))
		if slot_ic != null:
			line.add_child(_icon_rect(slot_ic, 18))
		var name_label := _label("%s %s %s" % [SimItems.display_name(it), SimItems.affix_text(it), badge],
				TYPE_SMALL, SimItems.GRADES[int(it["grade"])]["color"])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		var eq := _button("装備", _on_equip.bind(int(it["id"])), TYPE_SMALL)
		eq.disabled = diff <= 0.0
		line.add_child(eq)
		line.add_child(_button("分解", _on_salvage.bind(int(it["id"])), TYPE_SMALL))
		var rr := _button("刻印", _on_reroll.bind(int(it["id"])), TYPE_SMALL)
		rr.disabled = int(s["scrap"]) < SimItems.REROLL_COST
		line.add_child(rr)
		panel.add_child(line)
		inv_box.add_child(panel)
	if sorted_items.size() > shown:
		inv_box.add_child(_label("…ほか %d 品（スコア上位のみ表示）" % (sorted_items.size() - shown), TYPE_SMALL, COL_DIM))


## このアイテムを最も活かせる子（現装備スコアが最低）。
func _equip_target(item: Dictionary) -> Dictionary:
	var best_id := KuroData.GIRL_ORDER[0]
	var best_cur := INF
	for id in KuroData.GIRL_ORDER:
		var cur: Dictionary = sim.state["girls"][id]["equip"][item["slot"]]
		var cur_score := 0.0 if cur.is_empty() else float(cur["score"])
		if cur_score < best_cur:
			best_cur = cur_score
			best_id = id
	return {"girl": best_id, "cur_score": best_cur}


func _refresh_stats() -> void:
	_clear(stats_box)
	var s := sim.state
	var total_min := float(s["stats"]["focus_min"])
	stats_box.add_child(_label("累計集中: %d時間%d分   潜行: %d回" % [
		int(total_min / 60.0), int(total_min) % 60, int(s["stats"]["dives"])], 20))
	stats_box.add_child(_label("ストリーク: %d連続完走   最深: B%dF   営業: %d日目" % [
		int(s["streak"]), int(s["best_floor"]) + 1, int(s["day"])], 18))
	var today := Time.get_date_string_from_system()
	var runs_today := int(s["daily"]["runs"]) if String(s["daily"]["date"]) == today else 0
	stats_box.add_child(_label("デイリー: 今日 %d/3 完走（ポモドーロのみ）" % runs_today, 18))
	if runs_today >= 3 and not s["daily"]["claimed"]:
		stats_box.add_child(_button("デイリー報酬（+500G）", _on_claim_daily, TYPE_SUB))
	# デバッグ：獲得x10トグル
	var dbg := _button("DEBUG 獲得x10：%s" % ("ON" if s.get("debug_x10", false) else "OFF"),
			_on_toggle_debug_gain, TYPE_SMALL)
	dbg.modulate = Color(1, 0.85, 0.5) if s.get("debug_x10", false) else Color(1, 1, 1, 0.6)
	stats_box.add_child(dbg)
	stats_box.add_child(_section("週間集中グラフ"))
	var now := Time.get_unix_time_from_system()
	for i in range(6, -1, -1):
		var date := Time.get_datetime_string_from_unix_time(int(now) - i * 86400).substr(0, 10)
		var minutes := float(s["weekly"].get(date, 0.0))
		var bar := "■".repeat(mini(int(minutes / 15.0) + (1 if minutes > 0.0 else 0), 20))
		stats_box.add_child(_label("%s  %s %d分" % [date.substr(5), bar, int(minutes)], 16))
	stats_box.add_child(_label(
		"Sprites:0x72(CC0) FX:pimen SFX:Leohpaz Music:Abstraction(CC0) Font:DotGothic16(OFL)",
		12, Color(1, 1, 1, 0.25)))


func _aff_summary() -> Array[String]:
	var out: Array[String] = []
	for id in KuroData.GIRL_ORDER:
		out.append("%s♥%d" % [KuroData.GIRLS[id]["name"], sim.aff(id)])
	return out


func _log(msg: String) -> void:
	if msg.is_empty():
		return
	log_count += 1
	if log_count > 300:
		log_label.clear()
		log_count = 0
	log_label.append_text(msg + "\n")


# --- 操作 --------------------------------------------------------------------


func _on_keeper(id: String) -> void:
	sim.set_keeper(id)
	_refresh_morning()


func _on_menu_toggle(id: String) -> void:
	sim.toggle_menu(id)
	_refresh_morning()


func _on_door_policy() -> void:
	var m: Dictionary = sim.state["morning"]
	m["door"] = "skip" if m["door"] == "open" else "open"
	_refresh_morning()


func _on_mode(mode: String, minutes: float) -> void:
	dive_mode = mode
	dive_minutes = minutes
	task_edit.visible = mode == "pomo"


func _on_door_choice(open: bool) -> void:
	door_row.visible = false
	sim.resolve_door(open)
	_pump_events()


## デバッグ早送り。seconds=-1 は残り時間ぜんぶ（完走まで）。
func _on_debug_ff(seconds: float) -> void:
	var run: Dictionary = sim.state["run"]
	if not run["active"]:
		return
	if seconds < 0.0:
		seconds = float(run["duration"]) - float(run["elapsed"]) + 1.0
	run["anchor"] = float(run["anchor"]) - seconds
	_log("（DEBUG）%d秒 早送り" % int(seconds))


func _on_open_box() -> void:
	var r := sim.open_box()
	if r.is_empty():
		return
	_save(Time.get_unix_time_from_system())
	_refresh_morning()
	if box_overlay != null and box_overlay.visible:
		_clear(box_overlay_content)
		_fill_box_page(box_overlay_content)
	_show_box_reveal(r)


## 全ての箱をまとめて開封（演出なし）。経営オーバーレイをリフレッシュして返る。
func _on_open_all_boxes() -> void:
	if sim.state["boxes"].is_empty():
		return
	while not sim.state["boxes"].is_empty():
		sim.open_box()
	_save(Time.get_unix_time_from_system())
	_refresh_morning()
	_open_box_page()


## ホーム画面のキャラアイコンをタップ：会話があれば開始、なければステータス表示。
func _on_char_icon_tap(girl_id: String) -> void:
	var av := sim.available_talk()
	if not av.is_empty() and String(av.get("girl", "")) == girl_id:
		_on_talk_start(girl_id, int(av["tier"]))
	else:
		_open_status(girl_id)


## gui_input 経由のタップ判定 → _on_char_icon_tap に委譲。
func _on_char_face_input(event: InputEvent, girl_id: String) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed):
		_on_char_icon_tap(girl_id)


## グレード別カラー（木=茶 鉄=銀 銀=白銀 金=金）
func _box_grade_color(grade: int) -> Color:
	match grade:
		0: return Color(0.75, 0.55, 0.30)
		1: return Color(0.70, 0.78, 0.85)
		2: return Color(0.85, 0.92, 1.00)
		3: return Color(1.00, 0.85, 0.20)
		_: return COL_TEXT


## 箱開封演出オーバーレイ。アニメーション完了後に「受け取る」で消える。
func _show_box_reveal(result: Dictionary) -> void:
	var grade := int(result["grade"])
	var grade_color := _box_grade_color(grade)
	var grade_name: String = KuroData.BOX_NAMES[grade]

	# ── オーバーレイ本体
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 200
	add_child(overlay)

	# 暗幕（最初は透明）
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.0)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(backdrop)

	# カード（画面中央）
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(280, 0)
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.07, 0.06, 0.04)
	csb.border_color = grade_color
	csb.set_border_width_all(2)
	csb.set_content_margin_all(24)
	csb.corner_radius_top_left = 8; csb.corner_radius_top_right = 8
	csb.corner_radius_bottom_left = 8; csb.corner_radius_bottom_right = 8
	card.add_theme_stylebox_override("panel", csb)
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	# グレード名
	var grade_lbl := _label(grade_name, TYPE_DISPLAY, grade_color)
	grade_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(grade_lbl)

	# 箱画像（scale 0 スタート）
	var box_tex := _box_icon(grade)
	var box_rect := TextureRect.new()
	if box_tex != null:
		box_rect.texture = box_tex
	box_rect.custom_minimum_size = Vector2(120, 120)
	box_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box_rect.pivot_offset = Vector2(60, 60)
	box_rect.scale = Vector2.ZERO
	box_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(box_rect)

	# "開封中…" ラベル
	var status_lbl := _label("開封中…", TYPE_SUB, COL_DIM)
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_lbl)

	# 報酬テキスト（最初は透明）
	var reward_lbl := _label(result["text"], TYPE_BODY, grade_color)
	reward_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reward_lbl.custom_minimum_size = Vector2(220, 0)
	reward_lbl.modulate = Color(1, 1, 1, 0)
	vbox.add_child(reward_lbl)

	# 「受け取る」ボタン（最初は透明）
	var dismiss_btn := _button("受け取る", func(): overlay.queue_free(), TYPE_SUB)
	dismiss_btn.custom_minimum_size = Vector2(200, 48)
	dismiss_btn.modulate = Color(1, 1, 1, 0)
	if UIKit.available():
		UIKit.as_primary(dismiss_btn)
	vbox.add_child(dismiss_btn)

	# ── アニメーション シーケンス
	_sfx("chest_open")

	# Phase 1: 暗幕フェードイン ＋ 箱ポップイン（0.35s）
	var tw1 := create_tween().set_parallel(true)
	tw1.tween_property(backdrop, "color", Color(0.0, 0.0, 0.0, 0.82), 0.25)
	tw1.tween_property(box_rect, "scale", Vector2(1.0, 1.0), 0.35)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw1.finished

	# Phase 2: シェイク（0.24s）
	var tw2 := create_tween()
	tw2.tween_property(box_rect, "rotation", deg_to_rad(9), 0.07)
	tw2.tween_property(box_rect, "rotation", deg_to_rad(-9), 0.07)
	tw2.tween_property(box_rect, "rotation", deg_to_rad(4), 0.05)
	tw2.tween_property(box_rect, "rotation", 0.0, 0.05)
	await tw2.finished

	# Phase 3: グレードカラーでフラッシュ → 消える（0.34s）
	status_lbl.text = "…"
	var tw3 := create_tween()
	tw3.tween_property(box_rect, "modulate",
			Color(grade_color.r * 2.8, grade_color.g * 2.2, grade_color.b * 1.2, 1.0), 0.12)
	tw3.tween_property(box_rect, "modulate", Color(1, 1, 1, 0), 0.22)
	await tw3.finished

	# Phase 4: 報酬テキスト＋ボタンフェードイン（0.30s）
	status_lbl.modulate = Color(1, 1, 1, 0)
	var tw4 := create_tween().set_parallel(true)
	tw4.tween_property(reward_lbl, "modulate", Color(1, 1, 1, 1), 0.30)
	tw4.tween_property(dismiss_btn, "modulate", Color(1, 1, 1, 1), 0.30)
	await tw4.finished


func _on_buy(idx: int) -> void:
	var r := sim.market_buy(idx)
	if r.is_empty():
		return
	_sfx("ui_buy")
	_save(Time.get_unix_time_from_system())
	_refresh_morning()
	if market_overlay != null and market_overlay.visible:
		_fill_market_content()
	elif management_overlay != null and management_overlay.visible:
		_clear(ops_box); _fill_ops(ops_box)


func _on_skill_toggle(girl_id: String, skill_id: String) -> void:
	sim.equip_skill(girl_id, skill_id)
	_refresh_morning()


func _on_equip(item_id: int) -> void:
	for it in sim.state["inventory"]:
		if int(it["id"]) == item_id:
			sim.equip_from_inventory(item_id, String(_equip_target(it)["girl"]))
			_sfx("ui_equip")
			break
	_refresh_all()


func _on_salvage(item_id: int) -> void:
	sim.salvage_item(item_id)
	_refresh_inventory()
	_refresh_header()


func _on_reroll(item_id: int) -> void:
	if sim.reroll_item(item_id):
		_sfx("ui_equip")
	_refresh_inventory()
	_refresh_header()


func _on_bulk_salvage() -> void:
	var r := sim.bulk_salvage()
	_sfx("ui_buy")
	_refresh_inventory()
	_refresh_header()
	inv_box.add_child(_label("一括分解: %d品 → 廃材+%d" % [int(r["count"]), int(r["dust"])], 16, DS.SUCCESS))


func _on_synthesize() -> void:
	var made := sim.synthesize_all()
	if made > 0:
		_sfx("ui_equip")
	_pump_events()
	_refresh_all()


func _on_renov_tapped(id: String) -> void:
	var node: Dictionary = KuroData.RENOV_NODES[id]
	if id in sim.state["renov"]:
		renov_info.text = "%s: %s（改装済み）" % [node["name"], node["desc"]]
		return
	if not sim.renov_available(id):
		renov_info.text = "%s: 隣の区画から先に改装しよう" % node["name"]
		return
	renov_info.text = "%s: %s" % [node["name"], node["desc"]]
	_ask("「%s」を %dG で改装する？\n%s" % [node["name"], int(node["cost"]), node["desc"]],
			_on_renov_confirmed.bind(id))


func _on_renov_confirmed(id: String) -> void:
	if sim.unlock_renov(id):
		_sfx("ui_confirm")
		_pump_events()
		_save(Time.get_unix_time_from_system())
		_refresh_all()
	else:
		renov_info.text = "ゴールドが足りない…"


func _on_ship_buy(idx: int) -> void:
	if sim.buy_ship(idx):
		_sfx("ui_buy")
		_pump_events()
		_save(Time.get_unix_time_from_system())
		_refresh_all()
		if ship_overlay != null and ship_overlay.visible:
			_fill_ship_content()


func _on_claim_daily() -> void:
	if sim.claim_daily():
		_sfx("chest_open")
		_pump_events()
		_save(Time.get_unix_time_from_system())
		_refresh_all()


func _on_toggle_debug_gain() -> void:
	sim.state["debug_x10"] = not sim.state.get("debug_x10", false)
	_sfx("ui_confirm")
	_save(Time.get_unix_time_from_system())
	_refresh_all()


func _on_talk_start(girl: String, tier: int) -> void:
	_sfx("ui_confirm")
	talk_view.start(girl, tier)  # 完了は _on_scene_finished が処理


func _ask(text: String, cb: Callable) -> void:
	pending_confirm = cb
	confirm.dialog_text = text
	confirm.popup_centered()


func _on_confirmed() -> void:
	if pending_confirm.is_valid():
		pending_confirm.call()
	pending_confirm = Callable()


func _clear(box: Control) -> void:
	for c in box.get_children():
		c.queue_free()


func _save(now: float) -> void:
	sim.sync_rng()
	sim.state["last_seen"] = now
	SaveGame.save_state(sim.state)


func _sfx(sfx_name: String) -> void:
	if not sfx_cache.has(sfx_name):
		# ElevenLabs(mp3) > 手続き生成(wav) > 現行(wav) の順で優先
		var gen := "res://assets/generated/sfx/" + sfx_name
		var path := "res://assets/third_party/sfx/%s.wav" % sfx_name
		if ResourceLoader.exists(gen + ".mp3"):
			path = gen + ".mp3"
		elif ResourceLoader.exists(gen + ".wav"):
			path = gen + ".wav"
		sfx_cache[sfx_name] = load(path) if ResourceLoader.exists(path) else null
	var stream: AudioStream = sfx_cache[sfx_name]
	if stream == null:
		return
	var p := sfx_pool[sfx_next]
	sfx_next = (sfx_next + 1) % sfx_pool.size()
	p.stream = stream
	p.play()


func _show_boss_banner() -> void:
	if boss_banner == null:
		return
	var mobs: Array = sim.state["mobs"]
	var boss_mob := {}
	for m in mobs:
		if m["boss"]:
			boss_mob = m
			break
	if boss_mob.is_empty():
		return
	var sprite := String(boss_mob.get("sprite", ""))
	var path := "res://assets/third_party/dungeon/frames/%s_idle_anim_f0.png" % sprite
	if not ResourceLoader.exists(path):
		path = "res://assets/third_party/dungeon/frames/%s_anim_f0.png" % sprite
	boss_banner_tex.texture = load(path) if ResourceLoader.exists(path) else null
	var lbl := boss_banner.get_node_or_null("HBoxContainer/VBoxContainer/BossName") as Label
	if lbl != null:
		lbl.text = String(boss_mob.get("name", ""))
	boss_banner.visible = true


func _notify(text: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"if(window.Notification&&Notification.permission==='granted'){new Notification(%s);}" % JSON.stringify(text),
			true)


func _request_notify_permission() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"if(window.Notification&&Notification.permission==='default'){Notification.requestPermission();}",
			true)
