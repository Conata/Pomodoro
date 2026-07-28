extends Control
## 黒猫飯店 — 新メイン（HD-2D シェル）＋ KuroSim ロジック接続。
## 旧メイン（経営シム/タイマー一式）は legacy/main_legacy.gd に退避。
## 本シェルは HD-2D の「ホーム」「潜航（戦闘）」を画面遷移で繋ぎ、
## 潜航は KuroSim を実際に駆動して結果をオーバーレイへ反映する（表示層＝HD-2D）。

## 画面（シーン切替）は「店」と「潜航」の2つだけ。メニュー6パネル・精算リザルト・
## 会話はすべて常駐シート（CanvasLayer上のオーバーレイ）で、生きている世界の上に重ねる
## ＝タスクバーヒーロー方式（戦闘バーは止まらず、窓が上に開くだけ）。
const HOME := "res://home_screen.tscn"
const DIVE := "res://dive_screen.tscn"

var sim: KuroSim = null
var _current: Node = null
var _screen := ""                # いま表示中の世界（HOME / DIVE）
var _dive_overlay: Node = null   # 潜航中のみ。毎フレーム set_data で更新
var _dive_stage: Node = null     # 潜航中のみ。敵の出し入れを同期
var _menu_overlay: MenuOverlay = null     # 常駐シート（visible で開閉）
var _night_overlay: NightOverlay = null   # 夜営業シアター（浮上→精算の間に上演）
var _result_overlay: ResultOverlay = null # 常駐シート（visible で開閉）
var _pending_result: Dictionary = {}      # 夜営業の幕が降りたら見せる精算データ
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
var _sfx_router: SfxRouter = SfxRouter.new()  # 潜航イベント→効果音の割り当て＋間引き
var _dive_clock := 0.0                        # 潜航の経過秒（クールダウンの時計。早送りも織り込む）
var _ui_clock := 0.0                          # 画面まわりの経過秒（潜航外でも進む。UI音のクールダウン用）
## 実測用：鳴らした音の種類別カウント。音を足すたび「鳴らしすぎていないか」は
## 机上ではなく必ずこの数字で確かめる（検証スクリプトはこれを読んで集計する）。
## 本番でも回るが辞書1本の加算だけ＝実質ゼロコスト。
var sfx_counts: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 会話オーバーレイを常駐。CanvasLayer(高layer)に載せ、画面遷移に関係なく最前面で再生。
	var talk_layer := CanvasLayer.new()
	talk_layer.layer = 10
	add_child(talk_layer)
	_talk_view = TalkView.new()
	_talk_view.visible = false
	_talk_view.finished.connect(_on_talk_finished)
	# 会話を送る＝行が1つ進んだ瞬間（地の文は line_shown を出さないので黙る）
	_talk_view.line_shown.connect(func(_gid: String, _text: String): _sfx_cue("talk_next"))
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
	# 常駐シート：メニュー（6パネル）とリザルト。世界の上の CanvasLayer に載せ、
	# visible の開閉だけで使い回す（シーン切替しない＝下の世界は生きたまま）。
	var sheet_layer := CanvasLayer.new()
	sheet_layer.layer = 5
	add_child(sheet_layer)
	_menu_overlay = MenuOverlay.new()
	_menu_overlay.visible = false
	_menu_overlay.bind(sim)
	_menu_overlay.action_pressed.connect(_on_home_action)
	sheet_layer.add_child(_menu_overlay)
	_night_overlay = NightOverlay.new()
	_night_overlay.visible = false
	_night_overlay.finished.connect(_on_night_finished)
	_night_overlay.tip_tapped.connect(func(): _sfx("ui_buy"))
	_night_overlay.sfx_cue.connect(_sfx_cue)   # 配膳・伝票・追い返し・締めの一幕
	sheet_layer.add_child(_night_overlay)
	_result_overlay = ResultOverlay.new()
	_result_overlay.visible = false
	_result_overlay.action_pressed.connect(_on_home_action)
	_result_overlay.sfx_cue.connect(_sfx_cue)  # 箱開封の瞬間・三行精算のパネル
	sheet_layer.add_child(_result_overlay)
	# CanvasLayer 直下の Control はアンカーが効かない（TalkView と同じ罠）ので
	# 画面サイズを明示し、リサイズにも追従させる
	resized.connect(_fit_sheets)
	_fit_sheets()
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


## 全画面シート（メニュー／夜営業／精算）が世界を覆っている間は 3D の描画を止める。
## シミュレーションは止めない＝世界は生きたまま、見えていない絵を描くのをやめるだけ。
## visible を切り替える箇所が散っているので、毎フレーム可視状態から従属的に決める
## （どこかで戻し忘れても次のフレームで必ず復帰する）。
var _world_paused := false

func _sync_world_render() -> void:
	var covered := (_menu_overlay != null and _menu_overlay.visible) \
			or (_night_overlay != null and _night_overlay.visible) \
			or (_result_overlay != null and _result_overlay.visible)
	if covered == _world_paused:
		return
	_world_paused = covered
	if _current == null:
		return
	for child in _current.get_children():
		if child.has_method("set_render_paused"):
			child.set_render_paused(covered)


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


## 効果音の基準音量。プールの各プレイヤーはここを起点に vol_db を足し引きする。
## 将来ミュート／音量設定を付けるなら、触るのはこの1箇所だけで済む
## （効果音の再生経路は _sfx() 一本に絞ってある）。
const SFX_BASE_DB := -8.0

## 効果音を1発（mp3優先→生成wav→サードパーティwav）。プールを巡回。
## vol_db は基準からの増減、pitch は再生ピッチ（0 以下は 1.0 扱い）。
## 25分鳴り続ける画面なので、呼び出し側はピッチを ±5% ほど散らして単調さを避ける。
## 既存の呼び出し（名前だけ）は今までどおり基準音量・等倍ピッチで鳴る。
func _sfx(name: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if _sfx_pool.is_empty():
		return
	var path := _audio_pick("sfx/" + name, "res://assets/third_party/sfx/%s.wav" % name)
	if not ResourceLoader.exists(path):
		return   # 音が無くても落ちない（生成前・差し替え中でも安全）
	sfx_counts[name] = int(sfx_counts.get(name, 0)) + 1   # 実測用（種類別の発音回数）
	var p: AudioStreamPlayer = _sfx_pool[_sfx_i]
	_sfx_i = (_sfx_i + 1) % _sfx_pool.size()
	p.stream = load(path)
	p.volume_db = SFX_BASE_DB + vol_db
	p.pitch_scale = clampf(pitch, 0.05, 4.0) if pitch > 0.0 else 1.0
	p.play()


## 潜航イベントを効果音へ（割り当てと間引きは SfxRouter が決める）。
func _sfx_event(e: Dictionary) -> void:
	if _sfx_router == null:
		return
	for play in _sfx_router.route(e, _dive_clock):
		_sfx(String(play["name"]), float(play["vol"]), float(play["pitch"]))


## 画面まわりの合図（箱開封・夜営業・経営・横断）を効果音へ。
## オーバーレイ（Control）は _sfx を直接持たないので、シグナルでここへ集める＝
## **音の出口は _sfx ひとつのまま**。割り当て・音量・間引きは SfxRouter に閉じている。
func _sfx_cue(cue: String) -> void:
	if _sfx_router == null:
		return
	for play in _sfx_router.route_ui(cue, _ui_clock):
		_sfx(String(play["name"]), float(play["vol"]), float(play["pitch"]))


## Webの自動再生制限対策：最初のユーザー操作で店テーマを開始する。
func _ensure_audio_started() -> void:
	if _bgm != null and not _bgm.playing:
		_bgm.play()


## フェーズ・戦況でBGMをクロスフェード（店⇄潜航＋戦闘レイヤー）。
## 潜航中の編成寄り道（メニュー）でも潜航ドローンを維持＝ランが続いている実感を切らさない。
func _update_bgm(delta: float) -> void:
	var diving: bool = _in_dive or (sim != null and bool(sim.state["run"]["active"]))
	var in_combat: bool = _in_dive and sim != null and bool(sim.state["in_combat"])
	_fade(_bgm, -42.0 if diving else -16.0, delta)
	_fade(_bgm_dive, -10.0 if diving else -60.0, delta)
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
	_sync_world_render()  # 全画面シートで隠れている間は3Dの描画を止める
	# 画面まわりの音のクールダウンはこの時計で測る。潜航の内外を問わず進む
	# （夜営業も精算も潜航の外で起きるので、_dive_clock では測れない）。
	_ui_clock += delta
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
	if _dive_stage != null and _dive_stage.has_method("add_events"):
		_dive_stage.add_events(evs)   # 実体アンカーの戦闘FX（数字・斬撃・バースト）
	# 効果音のクールダウンはこの時計で測る。早送り中は世界も早く進むので
	# 同じだけ進めておく（×3 で潜っている間だけ音が詰まる、という事故を防ぐ）。
	# 逆に裏タブから戻った直後は、数分ぶんのイベントが1フレームに固まって届く。
	# その時この時計はほとんど進まない＝クールダウンが全部生きて、
	# 「戻った瞬間に数十発鳴る」という最悪の事故が構造的に起きない。
	_dive_clock += delta * float(_speed)
	for e in evs:
		_sfx_event(e)   # 命中／会心／撃破／被弾／スキル／レベルアップ／階層突破の音
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
	var streak_before := int(sim.state["streak"])
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
	var script: Array = night.get("script", [])
	# 劇場を上演する夜は「翌朝へ進める」を幕が降りるまで遅らせる。
	# settle_service は pending_night（皿数・売上）を書き換えるので、
	# 先に next_morning すると上積みの行き先が消えてしまう。
	if script.is_empty():
		sim.next_morning()
	_refresh_home_data("「お疲れさま。今夜は %dG の売上だったよ」" % int(night.get("gold", 0)))
	_save()             # 精算・開封・翌朝の確定を保存
	_sfx("chest_open" if not box_results.is_empty() else "teleport")   # 浮上の音
	# 連続完走が伸びた夜だけ、浮上の音の上に一段重ねる（伸びない夜は黙る）
	if int(sim.state["streak"]) > streak_before:
		_sfx_cue("streak_up")
	# 皿が出た夜は、精算の前に夜営業シアターを上演（スキップ可・放置でも完走）
	if script.is_empty():
		_show_result(result_data)
	else:
		_pending_result = result_data
		_goto(HOME)
		_night_overlay.set_data({"day": int(result_data["day"]), "script": script,
				"customers": int(night.get("customers", script.size())),
				"keeper": String(night.get("keeper", "kiriko")),
				"streak": int(sim.state["streak"]),
				"regulars": int(night.get("regulars", 0))})
		_night_overlay.visible = true


## 夜営業の幕が降りた：給仕の実績（チップ・追い客・取り逃し）を精算へ反映する。
## close_day の売上は「その夜に出せる上限」で、確定値はここで決まる。
## 何もしなければ 0/0/0 が渡り、delta も 0＝席を外した人は一切損をしない。
func _on_night_finished(tips: int, extra: int, walked_out: int) -> void:
	_night_overlay.visible = false
	if sim != null:
		var r := sim.settle_service(tips, extra, walked_out)
		var parts: Array[String] = []
		if int(r["tips"]) > 0:
			parts.append("タップ給仕 +%dG" % int(r["tips"]))
		if int(r["extra"]) > 0:
			parts.append("追い客 %d人 +%dG" % [int(r["extra"]), int(r["extra_gold"])])
		if int(r["walked_out"]) > 0:
			parts.append("待ちきれず %d人 −%dG" % [int(r["walked_out"]), int(r["lost_gold"])])
		if not parts.is_empty() and _pending_result.has("lines"):
			(_pending_result["lines"] as Array).append("／".join(parts))
		# 上積み後の売上を精算画面へ（劇場の伝票の数字と食い違わせない）
		var night: Dictionary = sim.state["pending_night"]
		if not night.is_empty():
			_pending_result["gold"] = int(night.get("gold", _pending_result.get("gold", 0)))
		sim.next_morning()          # 上積みを織り込んでから翌朝へ
		_refresh_home_data("「お疲れさま。今夜は %dG の売上だったよ」" % int(_pending_result.get("gold", 0)))
		_save()
	if not _pending_result.is_empty():
		_show_result(_pending_result)
		_pending_result = {}


## 精算リザルトシートを開いて結果を流し込む（世界は店へ戻しておく）。
func _show_result(data: Dictionary) -> void:
	if _screen != HOME:
		_goto(HOME)                   # シートは _goto が畳む
	_menu_overlay.visible = false
	_night_overlay.visible = false
	_result_overlay.set_data(data)
	_result_overlay.visible = true


## リザルトの会話ボタンから、その夜の相手と会話（VN）を最前面で再生する。
func _start_result_talk() -> void:
	if _talk_view == null or not _result_overlay.visible:
		return
	var t: Dictionary = _result_overlay.talk
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
	if _result_overlay != null and _result_overlay.visible:
		_result_overlay.clear_talk()


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
	# 世界の切替時はシートを畳む（開き直しは呼び出し側の責務）
	for sheet in [_menu_overlay, _night_overlay, _result_overlay]:
		if sheet != null:
			sheet.visible = false
	_screen = path
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
		# 潜航に入る／戻るたびに効果音のクールダウンを畳み直す（時計も0から）
		_dive_clock = 0.0
		_sfx_router.reset()
		_dive_stage = _current.get_node_or_null("Stage")
	var overlay := _current.get_node_or_null("Overlay")
	if overlay != null:
		if overlay.has_signal("action_pressed"):
			overlay.action_pressed.connect(_on_home_action)
			if overlay.has_method("bind"):
				overlay.bind(sim)              # ホーム：仕込みカード等の実データ描画
			if overlay.has_method("set_data") and not _home_data.is_empty():
				overlay.set_data(_home_data)   # ホーム：実データ反映（日数/金/セリフ）
		if overlay.has_signal("command_pressed"):
			overlay.command_pressed.connect(_on_dive_command)
			_dive_overlay = overlay
	if path == HOME:
		_sync_home_stage()   # 店番の立ち位置・改装プロップ・会話マーカーを反映


## ホーム／メニューのUI操作。
## フッターナビ（home/member/market/management/workshop）＝画面遷移、
## それ以外の "動詞:パラメータ" はメニュー各パネルの操作（KuroSim を実際に駆動）。
func _on_home_action(id: String) -> void:
	_ensure_audio_started()   # 最初のタップで店テーマ開始（Web自動再生制限対策）
	match id:
		"pomodoro", "sortie_pomo":
			# 25分ポモドーロ集中＝仕入れ（選択中のステージ×難易度で出撃）
			_launch_dive("pomo")
		"depart", "field":
			# 「仕入れへ」ポータル＝深層マップ（ステージ・難易度選択）へ
			_open_menu("map")
		"sortie_quick":
			# クイック仕入れ（80秒・マップから）
			_launch_dive("quick")
		"talk":
			# 精算リザルトの会話ボタン → その夜の相手と会話（VN）を再生
			_sfx("ui_confirm")
			_start_result_talk()
		"claim":
			# デイリー報酬（3完走で+500G・1日1回）
			if sim.claim_daily():
				_sfx_cue("daily_done")
				sim.drain_events()
				_save()
				if _result_overlay.visible:
					_result_overlay.claim_done()
		"continue":
			# 精算リザルトを閉じて翌朝のホームへ（next_morning は浮上時に済み）
			_say_home("「おはよう。今日はどこで仕入れる？」")
		"home", "resume_dive":
			# フッター「ホーム」＝店へ。潜航中（編成の寄り道）ならシートを閉じるだけで
			# 下で走り続けている潜航にそのまま戻る。
			if sim != null and bool(sim.state["run"]["active"]):
				_menu_overlay.visible = false
				if _screen != DIVE:
					_goto(DIVE)
			else:
				_say_home("「おかえり。今日も飯店、開けるよ。」")
		"member", "market", "management", "workshop":
			_open_menu(id)
		"prep_card":
			# 仕込みカードの余白タップ＝経営パネル（献立・店番・扉の詳細編集）へ
			_open_menu("management")
		"menu", "cat":
			# ホーム上部の ≡／猫 はメニュー（メンバー）への近道。
			_open_menu("member")
		"settings", "bell":
			# 設定・通知は未実装（旧版から未移植）。
			print("[home] action(未実装): ", id)
		_:
			_on_menu_action(id)


## 常駐シートを画面いっぱいに合わせる（開く時とリサイズ時に呼ぶ）。
func _fit_sheets() -> void:
	for sheet in [_menu_overlay, _night_overlay, _result_overlay]:
		if sheet != null:
			sheet.position = Vector2.ZERO
			sheet.size = size


## メニューシートを開く（既に開いていればパネル切替のみ＝タブ感覚で軽量）。
## シーン切替しないので、下の世界（店ディオラマ／潜航ステージ）は動き続ける。
func _open_menu(panel: String) -> void:
	if panel == "market" and sim != null:
		sim.maybe_rotate_ship(Time.get_unix_time_from_system())  # 入店時に交易船を更新
	if not _menu_overlay.visible:
		_menu_overlay.visible = true
		_menu_overlay._panel_t = 0.0   # 開いた時も登場トランジションを出す
		_sfx_cue("sheet_open")         # 窓が開く音。パネル切替（タブ感覚）では鳴らさない
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
		"socket_storage": 3, "remove_gem": 3, "stage": 2, "diff": 2,
		"unequip": 3,
		"restock": 2,
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
		"keeper_next":
			# 仕込みカードの店番チップ：タップで次の子へ巡回
			var order: Array = KuroData.GIRL_ORDER
			var ki := order.find(String(sim.state["morning"]["keeper"]))
			sim.set_keeper(order[(ki + 1) % order.size()])
			_sfx("ui_confirm")
		"menu":
			toast = "献立を更新" if sim.toggle_menu(parts[1]) else "枠がいっぱい／未所持"
		"door":
			var m: Dictionary = sim.state["morning"]
			m["door"] = "closed" if m["door"] == "open" else "open"
			toast = "扉の方針：%s" % ("開ける" if m["door"] == "open" else "見送る")
		"renov":
			# 改装の解放＝ノードが爆ぜて前提から光の線が走る瞬間。金を払っただけの
			# 「買った音」ではなく、店が一段変わった合図を当てる。
			if sim.unlock_renov(parts[1]):
				_sfx_cue("renov_unlock")
				toast = "改装「%s」を解放" % KuroData.RENOV_NODES[parts[1]]["name"]
			else:
				toast = "ゴールドが足りない"
		"skill":
			toast = "スキルを更新" if sim.equip_skill(parts[1], parts[2]) else "スキル枠がいっぱい"
		"tree":
			toast = "育成ノードを解放" if sim.tree_unlock(parts[1], parts[2]) else "欠片が足りない／条件未達"
		"stage":
			toast = "ステージ %s を選択" % KuroData.stage_label(int(parts[1])) \
					if sim.select_stage(int(parts[1])) else "まだ開放されていない"
		"restock":
			# 仕込みカードの売り逃し警告：足りない素材が獲れる階を選んでマップへ
			if sim.select_stage(int(parts[1])):
				_open_menu("map")
				toast = "ステージ %s — 足りない素材はここで獲れる" % KuroData.stage_label(int(parts[1]))
		"diff":
			var di := int(parts[1])
			toast = "難易度 %s（×%.1f）" % [KuroData.DIFFICULTIES[di]["name"], float(KuroData.DIFFICULTIES[di]["mult"])] \
					if sim.select_difficulty(di) else "前の難易度で第1幕を突破すると開く"
		"bag_all":
			var moved := sim.bag_all_to_storage()
			toast = "バッグから倉庫へ %d件移動" % moved
		"bag_store":
			toast = "倉庫へ移動" if sim.bag_to_storage(int(parts[1])) else "倉庫がいっぱい（廃材化）"
		"synth_bag":
			var made_bag := sim.synthesize_all()
			if made_bag > 0:
				_sfx_cue("craft_ok")   # バッグ合成に大成功は無い＝既存の確定音のまま
			toast = "バッグ合成 %d件" % made_bag if made_bag > 0 else "合成できる装備がない"
		"bulk_salvage_bag":
			var rb: Dictionary = sim.bulk_salvage()
			toast = "バッグ不要品 %d件 → 廃材%d" % [int(rb.get("count", 0)), int(rb.get("dust", 0))]
		"salvage_bag":
			var dust_bag := sim.salvage_item(int(parts[1]))
			toast = "分解 → 廃材%d" % dust_bag if dust_bag > 0 else "分解できない"
		"synth_storage":
			# 10%で「★大成功★」（2ランク上）が出る。確率で当たる要素なので、
			# ここだけは通常成功と音を変える＝引きの良し悪しが耳で分かる。
			# 大成功かどうかはログにしか残らないので、末尾で捨てる前にここで拾う。
			var made_storage := sim.synthesize_storage()
			if made_storage > 0:
				var great := false
				for ev in sim.drain_events():
					if String(ev.get("kind", "")) == "loot" \
							and String(ev.get("msg", "")).begins_with("★大成功★"):
						great = true
				_sfx_cue("craft_great" if great else "craft_ok")
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
			if not KuroData.GIRLS.has(gid):
				return
			var equipped := sim.equip_from_storage(int(parts[1]), gid)
			_sfx("ui_equip" if equipped else "ui_denied")
			toast = "%s に装備" % String(KuroData.GIRLS[gid]["name"]) if equipped else "装備できない"
		"unequip":
			# メンバー画面の装備枠から外して倉庫へ（倉庫満杯なら廃材化はシム側の判断）。
			# 未知の id で GIRLS/SLOTS を引くと落ちるので、引く前に必ず存在を確かめる。
			var ug := parts[1]
			var uslot := parts[2]
			if not KuroData.GIRLS.has(ug) or not SimItems.SLOTS.has(uslot):
				return
			var removed := sim.unequip_to_storage(ug, uslot)
			# 外す音は着ける音を少し低く＝同じ所作の裏返しとして聞こえる
			_sfx("ui_equip" if removed else "ui_denied", 0.0, 0.86 if removed else 1.0)
			toast = "%s の%sを外した" % [String(KuroData.GIRLS[ug]["name"]),
					String((SimItems.SLOTS[uslot] as Dictionary)["name"])] \
					if removed else "外せる装備が無い"
		"socket_storage":
			var socketed := sim.socket_gem(int(parts[1]), parts[2])
			_sfx("ui_equip" if socketed else "ui_denied", 0.0, 1.12 if socketed else 1.0)
			toast = "装飾を嵌めた" if socketed else "装飾できない"
		"remove_gem":
			var pulled := sim.remove_gem(int(parts[1]), int(parts[2]))
			_sfx("ui_equip" if pulled else "ui_denied", 0.0, 0.9 if pulled else 1.0)
			toast = "装飾を外した" if pulled else "外せない"
		_:
			print("[menu] action: ", id)
			return
	sim.drain_events()  # ログイベントは破棄（トーストで代替）
	_save()             # 購入・編成・改装などの変更を保存
	if _menu_overlay != null and _menu_overlay.visible:
		if toast != "":
			_menu_overlay.set_toast(toast)
		_menu_overlay.queue_redraw()
	_sync_home_stage()  # 店番替え・改装解放をディオラマへ即反映（HOME表示時のみ実働）


## 出撃：選択中のステージ×難易度でダイブを開始する（pomo/quick 共通）。
func _launch_dive(mode: String) -> void:
	if bool(sim.state["run"]["active"]):
		# すでに潜航中（編成の寄り道から出撃ボタン）→ シートを閉じて復帰のみ。
		# 復帰は「儀式」ではないので、始まりの音は鳴らさない。
		_sfx("ui_confirm")
		_menu_overlay.visible = false
		if _screen != DIVE:
			_goto(DIVE)
		return
	# 25分の始まりの儀式。スイッチを入れる音を1発だけ置いて、画面フェードに重ねる。
	_sfx_cue("focus_start")
	sim.drain_events()    # ホーム/メニューの残存イベントを捨ててから開始
	if mode == "pomo":
		_request_notify_permission()   # 完走通知の許可（ユーザー操作起点）
		sim.start_run("pomo", 25.0, Time.get_unix_time_from_system(), "集中仕入れ")
		_schedule_notify(25.0 * 60.0, "浮上。25分の集中、おつかれさま")
	else:
		sim.start_run("quick", 1.0, Time.get_unix_time_from_system(), "仕入れ")
	_save_accum = 0.0
	_save()               # 開始時点を保存（中断しても再開できる）
	_goto(DIVE)


## ホームのディオラマへ経営状態を反映（店番の立ち位置・改装プロップ・会話マーカー）。
func _sync_home_stage() -> void:
	if _screen != HOME or _current == null or sim == null:
		return
	var stage := _current.get_node_or_null("DinerStage")
	if stage != null and stage.has_method("set_home_state"):
		stage.set_home_state({
			"keeper": String(sim.state["morning"]["keeper"]),
			"divers": sim.divers(),
			"renov": sim.state["renov"],
			"talk": String(sim.available_talk().get("girl", "")),
		})


## 店へ戻ってVNセリフを差し替える（シートは畳み、世界がホームでなければ切替）。
func _say_home(vn_line: String) -> void:
	_menu_overlay.visible = false
	_result_overlay.visible = false
	if _screen != HOME:
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
		"loadout":
			# 潜航中の編成：メニューシートを潜航の上に開くだけ。シーンは切り替わらず
			# 下でランが走り続ける（＝タスクバーヒーローの窓）。装備・スキル・
			# キューブ合成の変更は次ステップから即このランに反映。
			_sfx("ui_confirm")
			_open_menu("member")
			_menu_overlay.set_toast("潜航は継続中。装備・スキル・合成は即反映される")
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
			"diff": int(sim.state.get("difficulty", 0)),
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


## 潜航イベント → 効果音の割り当て（純ロジック・再生はしない）。
##
## 分けてある理由は2つ。
##  1) 25分のあいだ、命中は0.8秒に1回・撃破は2.5秒に1回起きる。素直に鳴らすと
##     1500回の連打になって耳が潰れるので、種類ごとの最小間隔（クールダウン）で
##     必ず間引く。ここが効いているかは数字で確かめたい。
##  2) 実際の AudioStreamPlayer を持たないので、tests から素で回して
##     「何がいつ何回鳴るか」を実測できる（tests/_sfx_count.gd）。
##
## route() は {"why": 瞬間の名前, "name": 音名, "vol": 基準からのdB, "pitch": 再生ピッチ}
## の配列を返す（"why" は集計・ログ用。再生には使わない）。
## 鳴らさない時は空配列。音そのものが存在しない場合の守りは _sfx() 側（ResourceLoader.exists）。
class SfxRouter extends RefCounted:
	# 戦闘の地の音（頻発するもの）の最小間隔。長いほど静かになる。
	# 実測（tests/_sfx_count.gd）で決めた値。25分の交戦は約200秒だが、それが
	# 1秒未満の小競り合い約280回に散っているので、素直に鳴らすと撃破だけで
	# 700発になる。ここを絞って全体を「10秒に1つ何か鳴る」程度に落としている。
	const CD_HIT := 14.0        # 通常命中（slash / sword を交互）
	const CD_CRIT := 12.0       # 会心。通常命中とは別枠＝会心だけは通りやすい
	const CD_KILL := 18.0      # 雑魚撃破。一番数が多いので一番きつく絞る
	const CD_ELITE := 9.0      # エリート撃破（25分で40回前後しか出ない）
	const CD_HURT := 18.0       # 被弾
	const CD_SKILL := 8.0      # 攻撃スキル（爆発／雷）
	const CD_SONG := 30.0      # ムュウの歌。交戦中ずっと抽選されるので特に長く
	const CD_HEAL := 15.0      # 回復スキル。数が多いうえ地味なので特に間引く
	const CD_LOOT := 20.0      # 装備の発見。自動装着のたびに来る（実測 12秒だと25分で47発）
	const CD_BOSS := 6.0       # ボス出現。階ごとに1回だが、同じ階で再抽選される
	const CD_MEM := 4.0        # 記憶のかけら。1ランに数個の節目
	# どの戦闘音どうしも最低これだけは空ける。_sfx_pool は4本しかないので、
	# 同じ瞬間に重なると古い音が途中で切られて汚くなる。
	const FLOOR_GAP := 0.22

	# スキルの見た目名（SKILL_DB の "fx"）→ 効果音。表に無い fx は鳴らさない。
	const FX_SFX := {
		"explosion": "fire",
		"lightning": "thunder",
		"song": "teleport",     # ムュウの歌＝上昇シマー。回復の合図として通りがいい
		"heal": "heal",
	}

	# ── 画面まわり（潜航の外）の割り当て表 ────────────────────────────
	# cue -> [音名, 基準からの dB, 最小間隔（秒）]
	# 頻度が高いものほど絞る。夜営業は1回の上演で配膳11・伝票11が来るので、
	# ここを甘くすると劇場が「効果音の連打」になる。伝票は最も数が多く、
	# 絵としても脇役（下端のスロットが埋まるだけ）なので一番小さい。
	const UI_SFX := {
		# 箱開封（等級ごと）。音の長さ 0.13/0.29/0.35/0.76 秒が、
		# 開封後の尺 0.24/0.34/0.54/0.82 秒（開封＋着地）にそれぞれ収まる。
		"box_0":        ["box_wood",    -13.0, 0.08],
		"box_1":        ["box_iron",     -9.0, 0.08],
		"box_2":        ["box_silver",   -5.0, 0.08],
		"box_3":        ["box_gold",     -1.0, 0.08],
		# 経営
		"renov_unlock": ["renov_unlock", -4.0, 0.30],
		"craft_great":  ["craft_great",   0.0, 0.30],
		"craft_ok":     ["ui_confirm",    0.0, 0.30],
		# 夜営業（頻発。音量はここで絞りきる）
		# 最小間隔は「同じ瞬間に重ならない」ぶんだけ。店番の手は KEEPER_CD=0.28 秒
		# 間隔なので、それより長くすると配膳が理由なく黙る（実測 0.45 で 8回中3回が消えた）。
		"serve":        ["serve_dish",  -15.0, 0.25],
		"guest_leave":  ["guest_leave", -11.0, 0.60],
		"ticket":       ["ticket",      -22.0, 0.55],
		"night_close":  ["night_close",  -5.0, 2.00],
		# 横断
		"focus_start":  ["focus_start",  -5.0, 0.50],
		"sheet_open":   ["sheet_open",  -12.0, 0.30],
		"talk_next":    ["talk_next",   -17.0, 0.10],
		"daily_done":   ["daily_done",   -3.0, 1.00],
		"streak_up":    ["streak_up",    -5.0, 1.00],
	}
	# 夜営業の3種は互いにこれだけ空ける。配膳と伝票は 1.7 秒ずれて交互に来るが、
	# 席が5つあるので同じフレームに複数そろうことがある（＝4本のプールを食い潰す）。
	const NIGHT_KEYS := ["serve", "ticket", "guest_leave"]
	const NIGHT_GAP := 0.14
	# 節目（box_3 / craft_great）の前後で黙らせる相手。
	const HUSH_UI := ["box_0", "box_1", "box_2", "serve", "ticket", "guest_leave",
			"craft_ok", "talk_next", "sheet_open"]
	# 戦闘の地の音（_hush が黙らせる相手）。拾得とボスもここに含める＝
	# 節目の音の直後に「拾った」が刺さらない。
	const HUSH_BATTLE := ["hit", "crit", "kill", "elite", "hurt", "skill", "song",
			"heal", "loot", "boss"]

	var _next := {}          # 分類 -> 次に鳴らしてよい時刻
	var _last_battle := -999.0
	var _last_night := -999.0
	var _blade := 0          # slash / sword の交互カウンタ

	func reset() -> void:
		_next.clear()
		_last_battle = -999.0
		_last_night = -999.0

	## key の音を now に鳴らしてよいか。よければクールダウンを張って true。
	## battle=true の音は FLOOR_GAP による全体の間引きも受ける。
	func _ok(key: String, now: float, cd: float, battle: bool) -> bool:
		if battle and now - _last_battle < FLOOR_GAP:
			return false
		if now < float(_next.get(key, -999.0)):
			return false
		_next[key] = now + cd
		if battle:
			_last_battle = now
		return true

	func _jit(lo: float = 0.95, hi: float = 1.05) -> float:
		return randf_range(lo, hi)   # ピッチを散らして「同じ音の連打」に聞こえないように

	## 節目の音のために、戦闘の地の音を sec 秒だけ黙らせる。
	## resonance は2.8秒の長い音で、_sfx_pool は4本しかない＝
	## 直後に戦闘音が4発入ると鳴りきる前に横取りされる。間も演出のうち。
	func _hush(now: float, sec: float) -> void:
		_hush_keys(HUSH_BATTLE, now, sec)
		_last_battle = now + sec - FLOOR_GAP

	## 指定した分類だけを sec 秒黙らせる（画面まわりの節目でも使う）。
	func _hush_keys(keys: Array, now: float, sec: float) -> void:
		for key in keys:
			_next[key] = maxf(float(_next.get(key, -999.0)), now + sec)

	func route(e: Dictionary, now: float) -> Array:
		match String(e.get("kind", "")):
			"dmg_pop":
				if String(e.get("at", "")) == "enemy":
					if bool(e.get("crit", false)):
						# 会心：同じ剣の音を高く・強く＝通常命中と一段違って聞こえる
						if _ok("crit", now, CD_CRIT, true):
							return [{"why": "会心", "name": "sword", "vol": -3.0, "pitch": _jit(1.16, 1.26)}]
						return []
					if _ok("hit", now, CD_HIT, true):
						_blade = 1 - _blade
						return [{"why": "命中", "name": ("slash" if _blade == 0 else "sword"),
								"vol": -12.0, "pitch": _jit()}]
					return []
				# 被弾（味方）
				if _ok("hurt", now, CD_HURT, true):
					return [{"why": "被弾", "name": "damage", "vol": -7.0, "pitch": _jit(0.94, 1.04)}]
				return []
			"kill":
				if bool(e.get("boss", false)):
					# ボス撃破は必ず鳴らす（1ランに数回）。低いピッチで格を出す。
					# 直後に explosion の fx が来るので、そちらは少し黙らせて団子を防ぐ。
					_next["skill"] = now + 1.4
					_next["kill"] = now + CD_KILL      # 雑魚の音を後ろに重ねない
					_next["elite"] = now + CD_ELITE
					_last_battle = now
					return [{"why": "撃破:ボス", "name": "enemy_death", "vol": 0.0, "pitch": 0.68}]
				if bool(e.get("elite", false)):
					if _ok("elite", now, CD_ELITE, true):
						_next["kill"] = now + CD_KILL  # 格上を鳴らしたら雑魚は黙る
						return [{"why": "撃破:エリート", "name": "enemy_death", "vol": -3.0, "pitch": _jit(0.82, 0.90)}]
					return []
				if _ok("kill", now, CD_KILL, true):
					return [{"why": "撃破:雑魚", "name": "enemy_death", "vol": -10.0, "pitch": _jit(0.97, 1.09)}]
				return []
			"fx":
				var fx := String(e.get("fx", ""))
				if not FX_SFX.has(fx):
					return []
				if fx == "heal":
					if _ok("heal", now, CD_HEAL, true):
						return [{"why": "スキル:回復", "name": "heal", "vol": -13.0, "pitch": _jit()}]
					return []
				if fx == "song":
					if _ok("song", now, CD_SONG, true):
						return [{"why": "スキル:歌", "name": "teleport", "vol": -12.0, "pitch": _jit()}]
					return []
				if _ok("skill", now, CD_SKILL, true):
					return [{"why": "スキル:" + fx, "name": String(FX_SFX[fx]), "vol": -8.0, "pitch": _jit()}]
				return []
			"levelup":
				# 節目は間引かない（25分で10回前後・共鳴は4回まで）。
				# 共鳴の獲得はレベルアップより格上の音にする。
				if String(e.get("res_name", "")) != "":
					_hush(now, 1.6)   # 2.8秒の鐘。せめて前半は横取りさせない
					return [{"why": "共鳴の獲得", "name": "resonance", "vol": -1.0, "pitch": 1.0}]
				_hush(now, 0.6)
				return [{"why": "同期率Lv上昇", "name": "sync_up", "vol": -5.0, "pitch": 1.0}]
			"gate":
				# 階層突破。1ランで数回しか無い到達の合図。
				_hush(now, 0.8)
				return [{"why": "階層突破", "name": "floor_clear", "vol": -3.0, "pitch": 1.0}]
			"boss":
				# ボス出現。バナーだけでは雑魚の接近と区別が薄いので、
				# 低く濁った一撃を当てて「格が違う」を耳で先に伝える。
				if not _ok("boss", now, CD_BOSS, false):
					return []
				_hush(now, 0.7)
				return [{"why": "ボス出現", "name": "boss_appear", "vol": -2.0, "pitch": 1.0}]
			"resync":
				# 全滅→緊急再同期。25分が途切れない設計なので画は静かだが、
				# 何が起きたかは音で必ず言う（ログ行は流れて消える）。
				_hush(now, 0.8)
				return [{"why": "緊急再同期", "name": "wipe_out", "vol": -4.0, "pitch": 1.0}]
			"loot", "door_loot":
				# 装備の発見。自動装着のたびに来るので序盤は数が多い＝強く間引く。
				if _ok("loot", now, CD_LOOT, false):
					return [{"why": "装備の発見", "name": "pickup", "vol": -14.0, "pitch": _jit()}]
				return []
			"memory":
				# 記憶のかけら＝物語の断片。1ランに数個の節目なので、
				# 共鳴と同じ扱いで前後を黙らせて山を立てる。
				if not _ok("memory", now, CD_MEM, false):
					return []
				_hush(now, 1.0)
				return [{"why": "記憶のかけら", "name": "memory_get", "vol": -3.0, "pitch": 1.0}]
		return []


	## 画面まわりの合図 → 効果音。潜航と同じ考え方（表・音量・最小間隔）で間引く。
	## now は main._ui_clock（潜航の内外を問わず進む時計）。
	func route_ui(cue: String, now: float) -> Array:
		if not UI_SFX.has(cue):
			return []
		var row: Array = UI_SFX[cue]
		var night: bool = cue in NIGHT_KEYS
		if night and now - _last_night < NIGHT_GAP:
			return []
		if now < float(_next.get(cue, -999.0)):
			return []
		_next[cue] = now + float(row[2])
		if night:
			_last_night = now
		var pitch := 1.0
		match cue:
			"box_3", "craft_great":
				# 節目。_sfx_pool は4本しかないので、前後を黙らせないと
				# 1.2秒の演出のあいだに後ろの箱の音が食い込んで山が潰れる。
				_hush_keys(HUSH_UI, now, 0.55)
			"box_0", "box_1":
				pitch = _jit(0.97, 1.03)   # 木箱が12個続く日がある。同じ音の連打にしない
			"serve", "ticket":
				pitch = _jit(0.94, 1.06)
		return [{"why": cue, "name": String(row[0]), "vol": float(row[1]), "pitch": pitch}]
