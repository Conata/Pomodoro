extends Control
## 黒猫飯店 — 新メイン（HD-2D シェル）＋ KuroSim ロジック接続。
## 旧メイン（経営シム/タイマー一式）は legacy/main_legacy.gd に退避。
## 本シェルは HD-2D の「ホーム」「潜航（戦闘）」を画面遷移で繋ぎ、
## 潜航は KuroSim を実際に駆動して結果をオーバーレイへ反映する（表示層＝HD-2D）。

const HOME := "res://home_screen.tscn"
const DIVE := "res://dive_screen.tscn"
const MENU := "res://menu_screen.tscn"
const RESULT := "res://result_screen.tscn"

var sim: KuroSim = null
var _current: Node = null
var _dive_overlay: Node = null   # 潜航中のみ。毎フレーム set_data で更新
var _dive_stage: Node = null     # 潜航中のみ。敵の出し入れを同期
var _menu_overlay: Node = null   # メニュー（メンバー/市場/経営/工房）表示中のみ
var _in_dive := false
var _speed := 1                  # 潜航の早送り倍率（fast コマンドで 1→2→3 巡回）
var _home_data: Dictionary = {}  # ホーム表示データ（日数/金/セリフ）
var _last_summary: Dictionary = {}  # 直近の run_complete サマリ（精算リザルト表示用）
var _save_accum := 0.0           # 潜航中オートセーブの蓄積秒
const AUTOSAVE_SEC := 20.0       # 潜航中はこの間隔で自動保存（旧メイン同方式）
var _title_accum := 0.0          # タブタイトル残時間の更新間隔（1秒毎）
const TITLE_DEFAULT := "黒猫飯店"

var _talk_view: TalkView = null  # 会話（VN）オーバーレイ（常駐・必要時に最前面で再生）
var _pending_talk: Dictionary = {}  # 再生中の会話 {girl, tier}（完了時に complete_talk）
var _fade_rect: ColorRect = null # 画面遷移フェード（最前面・入力は透過）
var _fade_tween: Tween = null

# ── オーディオ（旧メインの簡約版）：店⇄潜航＋戦闘レイヤーのクロスフェード＋SFX ──
var _bgm: AudioStreamPlayer = null         # 店テーマ
var _bgm_dive: AudioStreamPlayer = null    # 潜航ドローン
var _bgm_battle: AudioStreamPlayer = null  # 戦闘レイヤー
var _sfx_pool: Array = []
var _sfx_i := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 会話オーバーレイを常駐。CanvasLayer(高layer)に載せ、画面遷移に関係なく最前面で再生。
	var talk_layer := CanvasLayer.new()
	talk_layer.layer = 10
	add_child(talk_layer)
	_talk_view = TalkView.new()
	_talk_view.visible = false
	_talk_view.finished.connect(_on_talk_finished)
	talk_layer.add_child(_talk_view)
	# 画面遷移フェード（会話より上・入力は素通し）
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 15
	add_child(fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.01, 0.01, 0.03, 1.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.modulate.a = 0.0
	fade_layer.add_child(_fade_rect)
	_build_audio()
	var loaded := SaveGame.load_state()
	if loaded.is_empty():
		sim = KuroSim.new()           # 新規（gold 120 / day 1）
	else:
		sim = KuroSim.new(loaded)     # セーブから再開
	sim.apply_offline(Time.get_unix_time_from_system())  # 安息収入＋last_seen 更新
	if bool(sim.state["run"]["active"]):
		# 中断したダイブを再開（_process が anchor で時間をキャッチアップする）
		if String(sim.state["run"]["mode"]) == "pomo":
			var remain := float(sim.state["run"]["duration"]) \
					- (Time.get_unix_time_from_system() - float(sim.state["run"]["anchor"]))
			_schedule_notify(remain, "浮上。%d分の集中、おつかれさま" % int(float(sim.state["run"]["duration"]) / 60.0))
		_goto(DIVE)
	else:
		_refresh_home_data("「いらっしゃい。今日はどこで仕入れる？」")
		_goto(HOME)
	_save()                           # last_seen / 安息分を確定保存


## 現在の状態を保存（rng を state に同期してから書き出す）。
func _save() -> void:
	if sim == null:
		return
	sim.sync_rng()
	SaveGame.save_state(sim.state)


## Web通知。iOS(ホーム画面に追加したPWA)は new Notification() 非対応のため
## ServiceWorker の showNotification を優先し、無ければ従来のコンストラクタへ。
## tag で同文通知を置換（予約タイマーとの二重発火を無害化）。
func _notify(text: String) -> void:
	if OS.has_feature("web"):
		var t := JSON.stringify(text)
		JavaScriptBridge.eval("""
(function(){
  if (!('Notification' in window) || Notification.permission !== 'granted') return;
  if (navigator.serviceWorker && navigator.serviceWorker.controller) {
    navigator.serviceWorker.ready.then(function(r){ r.showNotification(%s, {tag:'kuro-pomo'}); });
  } else {
    try { new Notification(%s, {tag:'kuro-pomo'}); } catch (e) {}
  }
})();""" % [t, t], true)


## 完走時刻にJS側タイマーで通知を予約する。Godot のフレームループは
## 裏タブで停止するため、これが無いと通知が「タブに戻った瞬間」になる。
## 再予約時は前の予約を破棄（abandon/早期浮上は _cancel_scheduled_notify）。
func _schedule_notify(seconds: float, text: String) -> void:
	if not OS.has_feature("web") or seconds <= 0.0:
		return
	var t := JSON.stringify(text)
	JavaScriptBridge.eval("""
(function(){
  if (window._kuroNotifyTimer) { clearTimeout(window._kuroNotifyTimer); window._kuroNotifyTimer = null; }
  if (!('Notification' in window)) return;
  window._kuroNotifyTimer = setTimeout(function(){
    window._kuroNotifyTimer = null;
    if (Notification.permission !== 'granted') return;
    if (navigator.serviceWorker && navigator.serviceWorker.controller) {
      navigator.serviceWorker.ready.then(function(r){ r.showNotification(%s, {tag:'kuro-pomo'}); });
    } else { try { new Notification(%s, {tag:'kuro-pomo'}); } catch (e) {} }
  }, %d);
})();""" % [t, t, int(seconds * 1000.0)], true)


func _cancel_scheduled_notify() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"if(window._kuroNotifyTimer){clearTimeout(window._kuroNotifyTimer);window._kuroNotifyTimer=null;}", true)


## 通知許可のリクエスト（未決定の時だけ・ダイブ開始のユーザー操作に乗せる）。
func _request_notify_permission() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"if(window.Notification&&Notification.permission==='default'){Notification.requestPermission();}",
			true)


func _mmss(sec: float) -> String:
	var s := maxi(int(ceil(sec)), 0)
	return "%d:%02d" % [int(s / 60.0), s % 60]


# ── オーディオ（旧メイン同方式・簡約）────────────────────────────────────────

func _build_audio() -> void:
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		_sfx_pool.append(p)
	# ElevenLabs(mp3) > 手続き生成(wav) > CC0 の順で優先（旧メインと同じ選好）
	_bgm = _make_loop(_audio_pick("bgm_el/store", "res://assets/third_party/music/sketchbook_loop.ogg"), -16.0)
	_bgm_dive = _make_loop(_audio_pick("bgm_el/dive", "res://assets/generated/bgm/dive_drone.wav"), -60.0)
	_bgm_battle = _make_loop(_audio_pick("bgm_el/battle", "res://assets/generated/bgm/battle_layer.wav"), -60.0)


## 生成BGM/SFXがあればそのパス（mp3優先）、無ければフォールバックを返す。
func _audio_pick(gen_base: String, fallback: String) -> String:
	var base := "res://assets/generated/" + gen_base
	if ResourceLoader.exists(base + ".mp3"):
		return base + ".mp3"
	if ResourceLoader.exists(base + ".wav"):
		return base + ".wav"
	return fallback


## ループ再生する AudioStreamPlayer を作る（OGG/MP3/WAV 対応）。
func _make_loop(path: String, vol_db: float) -> AudioStreamPlayer:
	if not ResourceLoader.exists(path):
		return null
	var p := AudioStreamPlayer.new()
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamMP3:
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	p.stream = stream
	p.volume_db = vol_db
	add_child(p)
	return p


## 効果音を1発（mp3優先→生成wav→サードパーティwav）。プールを巡回。
func _sfx(name: String) -> void:
	if _sfx_pool.is_empty():
		return
	var path := _audio_pick("sfx/" + name, "res://assets/third_party/sfx/%s.wav" % name)
	if not ResourceLoader.exists(path):
		return
	var p: AudioStreamPlayer = _sfx_pool[_sfx_i]
	_sfx_i = (_sfx_i + 1) % _sfx_pool.size()
	p.stream = load(path)
	p.play()


## Webの自動再生制限対策：最初のユーザー操作で店テーマを開始する。
func _ensure_audio_started() -> void:
	if _bgm != null and not _bgm.playing:
		_bgm.play()


## フェーズ・戦況でBGMをクロスフェード（店⇄潜航＋戦闘レイヤー）。
func _update_bgm(delta: float) -> void:
	var in_combat: bool = _in_dive and sim != null and bool(sim.state["in_combat"])
	_fade(_bgm, -42.0 if _in_dive else -16.0, delta)
	_fade(_bgm_dive, -10.0 if _in_dive else -60.0, delta)
	_fade(_bgm_battle, -10.0 if in_combat else -60.0, delta)


func _fade(p: AudioStreamPlayer, target_db: float, delta: float) -> void:
	if p == null:
		return
	# 鳴っていなければ開始（店テーマが動いている＝ユーザー操作済みの時だけ）
	if not p.playing and _bgm != null and _bgm.playing and target_db > -55.0:
		p.play()
	p.volume_db = move_toward(p.volume_db, target_db, 30.0 * delta)


## アプリ終了・バックグラウンド化で取りこぼさず保存する。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_save()


func _process(delta: float) -> void:
	_update_bgm(delta)   # フェーズに応じた店⇄潜航クロスフェード（潜航外でも動かす）
	if not _in_dive or sim == null:
		return
	# 早送り：アンカーを余分に巻き戻して「より多くの時間が経った」ことにする
	if _speed > 1 and bool(sim.state["run"]["active"]):
		sim.state["run"]["anchor"] = float(sim.state["run"]["anchor"]) - float(_speed - 1) * delta
	# KuroSim を実時間アンカーで駆動（タブ非アクティブでも正確：旧メインと同方式）
	_catch_up(Time.get_unix_time_from_system())
	_update_dive_ui()
	# 探索イベント（撃破・箱・記憶・扉・再同期…）を潜航オーバーレイのフィードへ。
	# run_complete サマリ（撃破数/到達階など）は精算リザルト用に確保する。
	var evs := sim.drain_events()
	if _dive_overlay != null and _dive_overlay.has_method("add_events"):
		_dive_overlay.add_events(evs)
	for e in evs:
		match String(e.get("kind", "")):
			"run_complete":
				_last_summary = e.get("summary", {})
			"dmg_pop":
				# 被弾（味方側）はカメラを揺らす（打撃感）
				if String(e.get("at", "")) == "party" and _dive_stage != null and _dive_stage.has_method("punch"):
					_dive_stage.punch(0.28)
			"fx":
				# 大技（爆発/雷）は強めに揺らす
				if String(e.get("fx", "")) in ["explosion", "lightning"] \
						and _dive_stage != null and _dive_stage.has_method("punch"):
					_dive_stage.punch(0.45)
	if not bool(sim.state["run"]["active"]):
		_surface()                # 浮上＝精算→リザルト→翌朝→店へ
		return
	# 潜航中オートセーブ（中断・クラッシュでも進行を失わない）
	_save_accum += delta
	if _save_accum >= AUTOSAVE_SEC:
		_save_accum = 0.0
		_save()
	# タブタイトルに残時間（別タブで作業中でも進捗が見える＝ポモドーロの芯）
	_title_accum += delta
	if _title_accum >= 1.0:
		_title_accum = 0.0
		var run: Dictionary = sim.state["run"]
		var remain := maxf(float(run["duration"]) - float(run["elapsed"]), 0.0)
		var label := String(run["task"]) if run["mode"] == "pomo" else "クイック"
		DisplayServer.window_set_title("%s ▼ %s" % [_mmss(remain), label])


## ホーム表示データを KuroSim から更新（日数・所持金・ストリーク・セリフ）。
func _refresh_home_data(vn_line: String) -> void:
	var dg := "Day %d   金 %d" % [int(sim.state["day"]), int(sim.state["gold"])]
	if int(sim.state["streak"]) > 0:
		dg += "   連%d" % int(sim.state["streak"])
	_home_data = {"day_gold": dg, "line": vn_line}


## 浮上：その日の営業を精算し、箱を開け、結果をリザルト画面で提示する。
## 「店に戻る」で翌朝のホームへ（翌朝への進行は continue 時に行う）。
func _surface() -> void:
	# 店番が客人/未設定でも keeper_apt を持つ既定に補正（クラッシュ防止）
	var keeper: String = sim.state["morning"]["keeper"]
	if not (KuroData.GIRLS.get(keeper, {}) as Dictionary).has("keeper_apt"):
		sim.state["morning"]["keeper"] = "kiriko"
	var night: Dictionary = sim.close_day()
	# 箱を開封し、1個ずつ結果を集める（リザルトでリビール）
	var box_results: Array = []
	while not (sim.state["boxes"] as Array).is_empty():
		var r: Dictionary = sim.open_box()
		if r.is_empty():
			break
		box_results.append(r)
	# ポモドーロ完走を日課に記録（デイリー/ストリーク/週間）＋完走通知。
	# 切断（クイック全滅など）はカウントしない＝旧メインと同じ規律。
	_cancel_scheduled_notify()   # 早期浮上なら未来の予約を破棄（tagで二重発火も無害）
	if String(_last_summary.get("mode", "")) == "pomo" and not bool(_last_summary.get("disconnected", false)):
		sim.register_completion(Time.get_date_string_from_system(), float(_last_summary.get("minutes", 0.0)))
		_notify("浮上。%d分の集中、おつかれさま" % int(round(float(_last_summary.get("minutes", 0.0)))))
	# その夜話せる相手（aff閾値の未読シーン・1夜1人）。next_morning 前に確保。
	var talk: Dictionary = sim.available_talk()
	var result_data := {
		"day": int(sim.state["day"]),   # いま閉じた夜の日付（next_morning 前に確保）
		"lines": night.get("lines", []),
		"gold": int(night.get("gold", 0)),
		"boxes": box_results,
		"story": String(night.get("story", "")),
		"summary": _last_summary,
		"talk": talk,
		"daily": (sim.state["daily"] as Dictionary).duplicate(),
		"streak": int(sim.state["streak"]),
	}
	_last_summary = {}
	# 翌朝へ進めてから保存（リザルト中にアプリが落ちても状態は常に整合）
	sim.next_morning()
	_refresh_home_data("「お疲れさま。今夜は %dG の売上だったよ」" % int(night.get("gold", 0)))
	_save()             # 精算・開封・翌朝の確定を保存
	_sfx("chest_open" if not box_results.is_empty() else "teleport")   # 浮上の音
	_show_result(result_data)


## 精算リザルト画面を開いて結果を流し込む。
func _show_result(data: Dictionary) -> void:
	_goto(RESULT)
	if _current != null:
		var overlay := _current.get_node_or_null("Overlay")
		if overlay != null and overlay.has_method("set_data"):
			overlay.set_data(data)


## リザルトの会話ボタンから、その夜の相手と会話（VN）を最前面で再生する。
func _start_result_talk() -> void:
	if _current == null or _talk_view == null:
		return
	var overlay := _current.get_node_or_null("Overlay")
	if overlay == null or not ("talk" in overlay):
		return
	var t: Dictionary = overlay.talk
	if t.is_empty():
		return
	_pending_talk = t
	_talk_view.position = Vector2.ZERO
	_talk_view.size = size           # CanvasLayer内なので画面サイズを明示
	_talk_view.start(String(t["girl"]), int(t["tier"]))


## 会話終了：好感度・既読を確定し、リザルトの会話ボタンを消す。
func _on_talk_finished(meta: Dictionary) -> void:
	var gid := String(meta.get("girl", ""))
	if gid != "" and sim != null:
		sim.complete_talk(gid, int(meta.get("tier", 0)))
		sim.drain_events()
		_save()
	_pending_talk = {}
	if _talk_view != null:
		_talk_view.visible = false
	if _current != null:
		var overlay := _current.get_node_or_null("Overlay")
		if overlay != null and overlay.has_method("clear_talk"):
			overlay.clear_talk()


## 固定ステップのキャッチアップ（now － anchor 分だけ step を回す）。
func _catch_up(now: float) -> void:
	var run: Dictionary = sim.state["run"]
	if not bool(run["active"]):
		return
	var target := now - float(run["anchor"])
	var steps := mini(int((target - float(run["elapsed"])) / KuroData.SIM_DT), 200000)
	for _i in steps:
		sim.step(KuroData.SIM_DT)
		if not bool(run["active"]):
			break


func _goto(path: String) -> void:
	if _current != null:
		_current.queue_free()
		_current = null
	_dive_overlay = null
	_dive_stage = null
	_menu_overlay = null
	_speed = 1
	_in_dive = (path == DIVE)
	if not _in_dive:
		DisplayServer.window_set_title(TITLE_DEFAULT)   # 潜航以外はタイトルを戻す
	_current = load(path).instantiate()
	add_child(_current)
	# 遷移フェード（切替直後を暗幕から明ける）
	if _fade_rect != null:
		if _fade_tween != null and _fade_tween.is_valid():
			_fade_tween.kill()
		_fade_rect.modulate.a = 1.0
		_fade_tween = create_tween()
		_fade_tween.tween_property(_fade_rect, "modulate:a", 0.0, 0.32) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if _in_dive:
		_dive_stage = _current.get_node_or_null("Stage")
	var overlay := _current.get_node_or_null("Overlay")
	if overlay != null:
		if overlay.has_signal("action_pressed"):
			overlay.action_pressed.connect(_on_home_action)
			if overlay.has_method("bind"):
				overlay.bind(sim)              # メニュー：KuroSim を参照させて実データ描画
				_menu_overlay = overlay
			if overlay.has_method("set_data") and not _home_data.is_empty():
				overlay.set_data(_home_data)   # ホーム：実データ反映（日数/金/セリフ）
		if overlay.has_signal("command_pressed"):
			overlay.command_pressed.connect(_on_dive_command)
			_dive_overlay = overlay


## ホーム／メニューのUI操作。
## フッターナビ（home/member/market/management/workshop）＝画面遷移、
## それ以外の "動詞:パラメータ" はメニュー各パネルの操作（KuroSim を実際に駆動）。
func _on_home_action(id: String) -> void:
	_ensure_audio_started()   # 最初のタップで店テーマ開始（Web自動再生制限対策）
	match id:
		"pomodoro":
			# 25分ポモドーロ集中＝仕入れ（早送り/早期終了は仕入れ画面のボタンで）
			_request_notify_permission()   # 完走通知の許可（ユーザー操作起点なのでここ）
			_sfx("ui_confirm")
			sim.drain_events()    # ホーム/メニューの残存イベントを捨ててから開始
			sim.start_run("pomo", 25.0, Time.get_unix_time_from_system(), "集中仕入れ")
			_schedule_notify(25.0 * 60.0, "浮上。25分の集中、おつかれさま")
			_save_accum = 0.0
			_save()       # 開始時点を保存（中断しても再開できる）
			_goto(DIVE)
		"depart", "field":
			# クイック仕入れ（80秒）
			_sfx("ui_confirm")
			sim.drain_events()
			sim.start_run("quick", 1.0, Time.get_unix_time_from_system(), "仕入れ")
			_save_accum = 0.0
			_save()
			_goto(DIVE)
		"talk":
			# 精算リザルトの会話ボタン → その夜の相手と会話（VN）を再生
			_sfx("ui_confirm")
			_start_result_talk()
		"claim":
			# デイリー報酬（3完走で+500G・1日1回）
			if sim.claim_daily():
				_sfx("chest_open")
				sim.drain_events()
				_save()
				if _current != null:
					var ov := _current.get_node_or_null("Overlay")
					if ov != null and ov.has_method("claim_done"):
						ov.claim_done()
		"continue":
			# 精算リザルトから翌朝のホームへ（next_morning は浮上時に済み）
			_refresh_home_data("「おはよう。今日はどこで仕入れる？」")
			_goto(HOME)
		"home":
			# フッター「ホーム」＝店（HD-2D ホーム）へ。既にホームならセリフだけ戻す。
			_say_home("「おかえり。今日も飯店、開けるよ。」")
		"member", "market", "management", "workshop":
			_open_menu(id)
		"menu", "cat":
			# ホーム上部の ≡／猫 はメニュー（メンバー）への近道。
			_open_menu("member")
		"settings", "bell":
			# 設定・通知は未実装（旧版から未移植）。
			print("[home] action(未実装): ", id)
		_:
			_on_menu_action(id)


## メニュー画面を開く（既に開いていればパネル切替のみ＝タブ感覚で軽量）。
func _open_menu(panel: String) -> void:
	if panel == "market" and sim != null:
		sim.maybe_rotate_ship(Time.get_unix_time_from_system())  # 入店時に交易船を更新
	if _menu_overlay != null and is_instance_valid(_menu_overlay):
		_menu_overlay.set_panel(panel)
	else:
		_goto(MENU)
		if _menu_overlay != null:
			_menu_overlay.set_panel(panel)


## メニュー各パネルの操作（"動詞:パラメータ"）。KuroSim を駆動して再描画する。
func _on_menu_action(id: String) -> void:
	if sim == null:
		return
	var parts := id.split(":")
	var verb := parts[0]
	# パラメータ付きの動詞は引数欠落なら無視（不正IDでの添字アクセス防止）。
	var need := {
		"buy": 2, "ship": 2, "keeper": 2, "menu": 2, "renov": 2,
		"skill": 3, "tree": 3, "bag_store": 2, "salvage_bag": 2,
		"reroll_storage": 2, "salvage_storage": 2, "equip_storage": 3,
		"socket_storage": 3, "remove_gem": 3,
	}
	if need.has(verb) and parts.size() < int(need[verb]):
		return
	var toast := ""
	match verb:
		"buy":
			var r: Dictionary = sim.market_buy(int(parts[1]))
			if not r.is_empty():
				_sfx("ui_buy")
			toast = String(r.get("text", "ゴールドが足りない")) if not r.is_empty() else "ゴールドが足りない"
		"ship":
			var bought := sim.buy_ship(int(parts[1]))
			if bought:
				_sfx("ui_buy")
			toast = "交易船から購入した" if bought else "買えなかった"
		"keeper":
			sim.set_keeper(parts[1])
			toast = "店番を %s に" % KuroData.GIRLS[parts[1]]["name"]
		"menu":
			toast = "献立を更新" if sim.toggle_menu(parts[1]) else "枠がいっぱい／未所持"
		"door":
			var m: Dictionary = sim.state["morning"]
			m["door"] = "closed" if m["door"] == "open" else "open"
			toast = "扉の方針：%s" % ("開ける" if m["door"] == "open" else "見送る")
		"renov":
			toast = "改装「%s」を解放" % KuroData.RENOV_NODES[parts[1]]["name"] if sim.unlock_renov(parts[1]) else "ゴールドが足りない"
		"skill":
			toast = "スキルを更新" if sim.equip_skill(parts[1], parts[2]) else "スキル枠がいっぱい"
		"tree":
			toast = "育成ノードを解放" if sim.tree_unlock(parts[1], parts[2]) else "欠片が足りない／条件未達"
		"bag_all":
			var moved := sim.bag_all_to_storage()
			toast = "バッグから倉庫へ %d件移動" % moved
		"bag_store":
			toast = "倉庫へ移動" if sim.bag_to_storage(int(parts[1])) else "倉庫がいっぱい（廃材化）"
		"synth_bag":
			var made_bag := sim.synthesize_all()
			toast = "バッグ合成 %d件" % made_bag if made_bag > 0 else "合成できる装備がない"
		"bulk_salvage_bag":
			var rb: Dictionary = sim.bulk_salvage()
			toast = "バッグ不要品 %d件 → 廃材%d" % [int(rb.get("count", 0)), int(rb.get("dust", 0))]
		"salvage_bag":
			var dust_bag := sim.salvage_item(int(parts[1]))
			toast = "分解 → 廃材%d" % dust_bag if dust_bag > 0 else "分解できない"
		"synth_storage":
			var made_storage := sim.synthesize_storage()
			toast = "倉庫合成 %d件" % made_storage if made_storage > 0 else "合成できる装備がない"
		"bulk_salvage_storage":
			var rs: Dictionary = sim.bulk_salvage_storage()
			toast = "倉庫不要品 %d件 → 廃材%d" % [int(rs.get("count", 0)), int(rs.get("dust", 0))]
		"reroll_storage":
			toast = "刻印を更新" if sim.reroll_storage(int(parts[1])) else "廃材不足／対象なし"
		"salvage_storage":
			var dust_storage := sim.salvage_from_storage(int(parts[1]))
			toast = "分解 → 廃材%d" % dust_storage if dust_storage > 0 else "分解できない"
		"equip_storage":
			var gid := parts[2]
			toast = "%s に装備" % KuroData.GIRLS[gid]["name"] if sim.equip_from_storage(int(parts[1]), gid) else "装備できない"
		"socket_storage":
			toast = "装飾を嵌めた" if sim.socket_gem(int(parts[1]), parts[2]) else "装飾できない"
		"remove_gem":
			toast = "装飾を外した" if sim.remove_gem(int(parts[1]), int(parts[2])) else "外せない"
		_:
			print("[menu] action: ", id)
			return
	sim.drain_events()  # ログイベントは破棄（トーストで代替）
	_save()             # 購入・編成・改装などの変更を保存
	if _menu_overlay != null and is_instance_valid(_menu_overlay):
		if toast != "" and _menu_overlay.has_method("set_toast"):
			_menu_overlay.set_toast(toast)
		_menu_overlay.queue_redraw()


## ホームのVNセリフを差し替えて、現在のホームオーバーレイへ即時反映する。
func _say_home(vn_line: String) -> void:
	if _menu_overlay != null or _in_dive:
		_goto(HOME)
	_refresh_home_data(vn_line)
	if _current != null:
		var overlay := _current.get_node_or_null("Overlay")
		if overlay != null and overlay.has_method("set_data"):
			overlay.set_data(_home_data)


## 潜航のコマンド。home=撤退 / finish=早期浮上 / fast=早送り /
## cast=手動スキル1発 / toggle_manual=スキル手動⇄自動（未決分岐の実験）。
func _on_dive_command(id: String) -> void:
	_ensure_audio_started()
	match id:
		"home", "pause":
			# 中断して店へ戻る（撤退）
			_cancel_scheduled_notify()       # 撤退＝完走ではないので通知予約を破棄
			if sim != null and bool(sim.state["run"]["active"]):
				sim.abandon_run()
			_refresh_home_data("「無理はしないで。仕切り直そう。」")
			_goto(HOME)
			_save()                          # 撤退（切断ペナルティ）を保存
		"finish":
			# 早期終了＝今すぐ浮上（残り時間を飛ばして正常終了→精算）
			var run: Dictionary = sim.state["run"]
			if bool(run["active"]):
				run["elapsed"] = float(run["duration"])
				sim.step(KuroData.SIM_DT)   # 終端処理を発火（次フレームの _process が _surface）
		"fast":
			_speed = (_speed % 3) + 1        # 1→2→3→1
		"cast":
			# 手動スキル発動（撃てるものが無ければ拒否音のみ）
			var r: Dictionary = sim.manual_cast()
			if r.is_empty():
				_sfx("ui_denied")
			else:
				_sfx("thunder")
				if _dive_overlay != null and _dive_overlay.has_method("add_events"):
					_dive_overlay.add_events([{"kind": "log", "msg": "%s、%s！" % [
							KuroData.GIRLS[r["girl"]]["name"], String(r["name"])]}])
		"toggle_manual":
			# スキル手動⇄自動の切替（未決分岐を遊んで決めるための実験フラグ）
			sim.state["manual_skill"] = not bool(sim.state.get("manual_skill", false))
			_save()
		_:
			print("[dive] command(未接続): ", id)


## 潜航オーバーレイへ KuroSim の実データを流し込む。
func _update_dive_ui() -> void:
	if _dive_overlay == null:
		return
	var ds: Array = sim.divers()
	var party: Array = []
	var tot := 0.0
	var mx := 0.0
	for gid in ds:
		var g: Dictionary = KuroData.GIRLS.get(gid, {})
		var hp := int(sim.state["hp"].get(gid, 0))
		var mhp := maxi(int(sim.girl_maxhp(gid)), 1)
		tot += hp
		mx += mhp
		party.append({"name": String(g.get("name", gid)), "hp": hp, "mhp": mhp, "sp": 100, "msp": 100})
	# 交戦中のボス名（バナー用）
	var boss_name := ""
	for m in sim.state["mobs"]:
		if bool(m.get("boss", false)):
			boss_name = String(m.get("name", ""))
			break
	# 横スクロールステージ（タスクバーヒーロー型）へ実データを毎フレーム反映
	if _dive_stage != null and _dive_stage.has_method("set_view"):
		var girls_view: Array = []
		for gid in ds:
			var ready := 0
			var eq: Array = sim.state["girls"][gid]["skills_eq"]
			for sid in eq:
				if float((sim.state["cds"].get(gid, {}) as Dictionary).get(sid, 0.0)) <= 0.0:
					ready += 1
			girls_view.append({
				"id": gid, "hp": float(sim.state["hp"].get(gid, 0)), "mhp": sim.girl_maxhp(gid),
				"ready": ready, "slots": eq.size(),
			})
		var mobs_view: Array = []
		for m in sim.state["mobs"]:
			mobs_view.append({"sprite": String(m.get("sprite", "goblin")),
					"hp": float(m["hp"]), "boss": bool(m.get("boss", false))})
		_dive_stage.set_view({
			"dist": float(sim.state["dist"]),
			"in_combat": bool(sim.state["in_combat"]),
			"party": girls_view, "mobs": mobs_view,
			"gold_gain": int(sim.state["gold"]) - int(sim.state["run"]["gold0"]),
		})
	elif _dive_stage != null and _dive_stage.has_method("set_dive_state"):
		# 旧3Dステージ互換
		var mob_sprites: Array = []
		for m in sim.state["mobs"]:
			mob_sprites.append(String(m.get("sprite", "")))
		_dive_stage.set_dive_state(mob_sprites.size(), bool(sim.state["in_combat"]),
				boss_name != "", mob_sprites)
	var run: Dictionary = sim.state["run"]
	var remain := maxf(float(run["duration"]) - float(run["elapsed"]), 0.0)
	var prog := fmod(float(sim.state["dist"]), KuroData.FLOOR_LEN) / KuroData.FLOOR_LEN
	_dive_overlay.set_data({
		"party": party,
		"player_lv": "B%d" % sim.current_floor(),
		"player_hp": (tot / mx) if mx > 0.0 else 0.0,
		"player_exp": prog,
		"quest_text": "仕入れ中  B%d  残り %d秒" % [sim.current_floor(), int(remain)],
		"speed_mult": _speed,
		"manual_skill": bool(sim.state.get("manual_skill", false)),
		"skill_label": String(sim.next_ready_skill().get("name", "")),
		"boss_name": boss_name if bool(sim.state["in_combat"]) else "",
	})
