class_name FaceCam
extends Control
## 配信者の「ワイプ（顔カメラ）」。表情シート（assets/generated/face/<id>/）があれば
## まばたき＋リップシンクで動く。無ければ立ち絵(assets/portraits/<id>.png)の頭部を
## 静止表示、それも無ければキャラ色のバストで代替する＝素材ゼロでも成立する。
##
## 表情フレーム命名（tools/slice_expressions.py の出力）:
##   <expr>_closed.png / <expr>_half.png / <expr>_open.png / <expr>_blink.png
##   expr 既定: neutral（他に smile/surprise/calm 等を set_expression で）
## TTS音声が入ったら _mouth_target を AudioServer のピークで駆動すれば本物の口パクになる。

## かな→口の開き値（0=閉口 / 0.85=全開）。ー=-1 は直前値を継続（長音）。
const _KANA_MOUTH := {
	"あ":0.85,"い":0.40,"う":0.25,"え":0.60,"お":0.70,  # あ行
	"か":0.85,"き":0.40,"く":0.25,"け":0.60,"こ":0.70,
	"さ":0.85,"し":0.40,"す":0.25,"せ":0.60,"そ":0.70,
	"た":0.85,"ち":0.40,"つ":0.25,"て":0.60,"と":0.70,
	"な":0.85,"に":0.40,"ぬ":0.25,"ね":0.60,"の":0.70,
	"は":0.85,"ひ":0.40,"ふ":0.25,"へ":0.60,"ほ":0.70,
	"ま":0.85,"み":0.40,"む":0.25,"め":0.60,"も":0.70,
	"や":0.85,"ゆ":0.25,"よ":0.70,
	"ら":0.85,"り":0.40,"る":0.25,"れ":0.60,"ろ":0.70,
	"わ":0.85,"を":0.70,"ん":0.12,
	"が":0.85,"ぎ":0.40,"ぐ":0.25,"げ":0.60,"ご":0.70,
	"ざ":0.85,"じ":0.40,"ず":0.25,"ぜ":0.60,"ぞ":0.70,
	"だ":0.85,"ぢ":0.40,"づ":0.25,"で":0.60,"ど":0.70,
	"ば":0.85,"び":0.40,"ぶ":0.25,"べ":0.60,"ぼ":0.70,
	"ぱ":0.85,"ぴ":0.40,"ぷ":0.25,"ぺ":0.60,"ぽ":0.70,
	"ゃ":0.85,"ゅ":0.25,"ょ":0.70,
	"ぁ":0.85,"ぃ":0.40,"ぅ":0.25,"ぇ":0.60,"ぉ":0.70,
	"っ":0.0,"ー":-1.0,  # 促音・長音
	"ア":0.85,"イ":0.40,"ウ":0.25,"エ":0.60,"オ":0.70,  # カタカナ
	"カ":0.85,"キ":0.40,"ク":0.25,"ケ":0.60,"コ":0.70,
	"サ":0.85,"シ":0.40,"ス":0.25,"セ":0.60,"ソ":0.70,
	"タ":0.85,"チ":0.40,"ツ":0.25,"テ":0.60,"ト":0.70,
	"ナ":0.85,"ニ":0.40,"ヌ":0.25,"ネ":0.60,"ノ":0.70,
	"ハ":0.85,"ヒ":0.40,"フ":0.25,"ヘ":0.60,"ホ":0.70,
	"マ":0.85,"ミ":0.40,"ム":0.25,"メ":0.60,"モ":0.70,
	"ヤ":0.85,"ユ":0.25,"ヨ":0.70,
	"ラ":0.85,"リ":0.40,"ル":0.25,"レ":0.60,"ロ":0.70,
	"ワ":0.85,"ヲ":0.70,"ン":0.12,
	"ガ":0.85,"ギ":0.40,"グ":0.25,"ゲ":0.60,"ゴ":0.70,
	"ザ":0.85,"ジ":0.40,"ズ":0.25,"ゼ":0.60,"ゾ":0.70,
	"ダ":0.85,"ヂ":0.40,"ヅ":0.25,"デ":0.60,"ド":0.70,
	"バ":0.85,"ビ":0.40,"ブ":0.25,"ベ":0.60,"ボ":0.70,
	"パ":0.85,"ピ":0.40,"プ":0.25,"ペ":0.60,"ポ":0.70,
	"ャ":0.85,"ュ":0.25,"ョ":0.70,
	"ァ":0.85,"ィ":0.40,"ゥ":0.25,"ェ":0.60,"ォ":0.70,
	"ッ":0.0,
}

var girl_id := ""
var speaking := false              # この配信者が今しゃべっているか（main/chrome が設定）
var eating := false                # 食事中（咀嚼リズムで口が動く）
var expression := "neutral"
var show_label := true
var flip_h := false                # true で左右反転（画面内側に向かせる用）

# TTS音声駆動（全FaceCam共有）。main が Voice バスを作って設定する。
# voice_active 中は「発話中の」ワイプの口を音量ピークで動かす（実音同期）。
static var voice_bus := -1
static var voice_active := false

var _tex_cache := {}
var _mouth := 0.0
var _mouth_target := 0.0
var _talk_t := 0.0
var _phoneme_seq: Array = []       # [{v:float, d:float}] start_speech が生成
var _phoneme_idx := 0
var _phoneme_t := 0.0              # 現フォネムの残り秒（負になったら次へ）
var _chew_t := 0.0                 # 咀嚼タイマー（eating 用）
var _chew_phase := 0               # 0=とじ 1=半開 2=全開 1=半開 のサイクル
var _blink_t := 2.0
var _blinking := 0.0
var _pulse := 0.0
var _expr_timer := 0.0            # >0 のあいだ expression を維持し、0 になったら neutral に戻す
var _mouth_frame := "closed"      # 実際に描画するフレーム名（ホールドで切り替えを制限）
var _mouth_hold  := 0.0           # >0 のあいだフレーム切り替えを禁止（秒）


func _ready() -> void:
	clip_contents = true
	_blink_t = randf_range(2.0, 5.0)


## 表情を duration 秒だけ切り替え、その後 neutral に自動で戻す。
## duration=0 で即時 neutral 戻し。
func set_expression(expr: String, duration: float = 1.8) -> void:
	expression = expr
	_expr_timer = duration


## テキストからかな→母音→口の開き値のシーケンスを生成する。
## dive_chrome が新しいセリフ吹き出しを検出したときに呼ぶ。
## speaking フラグが true の間、_process がシーケンスを再生する。
func start_speech(text: String) -> void:
	_phoneme_seq = []
	_phoneme_idx = 0
	_phoneme_t = 0.0
	var prev_v := 0.0
	for i in text.length():
		var c := text[i]
		var v := 0.65   # 未知文字（漢字等）= 中程度開口
		var d := 0.11   # 通常モーラ duration（秒）
		if _KANA_MOUTH.has(c):
			v = float(_KANA_MOUTH[c])
			if c == "っ" or c == "ッ":
				d = 0.06
			elif c == "ー":
				v = prev_v   # 長音：直前の母音値を延長
				d = 0.13
			else:
				d = 0.10
		elif c == "。" or c == "　" or c == " ":
			v = 0.0; d = 0.18
		elif c == "、":
			v = 0.0; d = 0.12
		elif c in ["！", "？", "…", "「", "」", "・"]:
			v = 0.0; d = 0.06
		if v >= 0.0:
			prev_v = v
		_phoneme_seq.append({"v": v, "d": d})


func _process(delta: float) -> void:
	_pulse += delta
	# 表情タイマー：期限が来たら neutral に戻す
	if _expr_timer > 0.0:
		_expr_timer -= delta
		if _expr_timer <= 0.0:
			expression = "neutral"
	# 口の動き：発話 > 咀嚼 > 閉口 の優先順
	if speaking:
		if FaceCam.voice_active and FaceCam.voice_bus >= 0:
			# TTS音声が再生中なら、その音量ピークで口を駆動（テキスト推定より実音優先）
			var vdb := AudioServer.get_bus_peak_volume_left_db(FaceCam.voice_bus, 0)
			_mouth_target = clampf((vdb + 42.0) / 42.0, 0.0, 1.0)
		# フォネムシーケンス再生（start_speech がセット済みのとき）
		elif not _phoneme_seq.is_empty():
			_phoneme_t -= delta
			while _phoneme_t <= 0.0:
				if _phoneme_idx >= _phoneme_seq.size():
					_phoneme_idx = 0  # テキストより発話時間が長ければループ
				var ph: Dictionary = _phoneme_seq[_phoneme_idx]
				var v: float = ph["v"]
				if v >= 0.0:
					_mouth_target = v
				_phoneme_t += float(ph["d"])
				_phoneme_idx += 1
		else:
			# フォールバック：シーケンスが無い場合のランダム口パク
			_talk_t += delta
			if _talk_t >= 0.0:
				var rnd := randf()
				var next_dur: float
				if rnd < 0.22:
					_mouth_target = 0.0
					next_dur = randf_range(0.06, 0.13)
				elif rnd < 0.55:
					_mouth_target = randf_range(0.55, 1.0)
					next_dur = randf_range(0.12, 0.22)
				else:
					_mouth_target = randf_range(0.2, 0.55)
					next_dur = randf_range(0.09, 0.16)
				_talk_t = -next_dur
	elif eating:
		# 咀嚼（0→1→2→1→0 をゆっくり繰り返す。1周 ~1.4s）
		_chew_t += delta
		var chew_step := 0.35  # 1ステップの秒数
		if _chew_t >= chew_step:
			_chew_t -= chew_step
			_chew_phase = (_chew_phase + 1) % 4  # 0,1,2,1,0,1,2… (4でラップ→0,1,2,3→map下)
		# phase: 0=閉 1=半開 2=全開 3=半開（0と同じ扱い）
		match _chew_phase:
			0, 3: _mouth_target = 0.0
			1:    _mouth_target = 0.4
			2:    _mouth_target = 0.85
	else:
		_mouth_target = 0.0
	# 発話中は追いつき速度を上げ、閉じるときは緩める（自然な口の動き）
	var mouth_speed := 14.0 if _mouth_target > _mouth else 8.0
	_mouth = move_toward(_mouth, _mouth_target, delta * mouth_speed)
	# フレームホールド：素材ごとに頭角度が微妙に違うためチラつく。
	# 1フレームに複数回切り替わらないよう最低 0.09s 同じフレームを維持する。
	var wanted_frame := "closed"
	if _mouth >= 0.65:
		wanted_frame = "open"
	elif _mouth >= 0.25:
		wanted_frame = "half"
	_mouth_hold = maxf(0.0, _mouth_hold - delta)
	if wanted_frame != _mouth_frame and _mouth_hold <= 0.0:
		_mouth_frame = wanted_frame
		_mouth_hold = 0.09  # 90ms ホールド
	# eating 中は expression を eat に固定（戦闘表情タイマーがなければ）
	if eating and _expr_timer <= 0.0:
		expression = "eat"
	elif not eating and expression == "eat":
		expression = "neutral"
	# まばたき
	_blink_t -= delta
	if _blink_t <= 0.0:
		_blinking = 0.12
		_blink_t = randf_range(2.5, 5.5)
	if _blinking > 0.0:
		_blinking -= delta
	if visible:
		queue_redraw()


func _tex(name: String) -> Texture2D:
	if girl_id.is_empty():
		return null
	var path := "res://assets/generated/face/%s/%s.png" % [girl_id, name]
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[path]


func _portrait() -> Texture2D:
	if girl_id.is_empty():
		return null
	var path := "res://assets/portraits/%s.png" % girl_id
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[path]


## src（ピクセル矩形）を dst にアスペクト維持で隙間なく敷く（COVER）。
func _draw_cover(tex: Texture2D, dst: Rect2, src: Rect2) -> void:
	var sa := src.size.x / maxf(src.size.y, 1.0)
	var da := dst.size.x / maxf(dst.size.y, 1.0)
	if sa > da:
		var nw := src.size.y * da
		src.position.x += (src.size.x - nw) * 0.5
		src.size.x = nw
	else:
		var nh := src.size.x / da
		src.position.y += (src.size.y - nh) * 0.5
		src.size.y = nh
	draw_texture_rect_region(tex, dst, src)


## 閉口ベース + 口開けオーバーレイの合成描画（MotionPNGTuber 方式）。
## 上部 56%（目・鼻・髪）は常に base_tex（closed）を使い頭アングルの揺れを隠す。
## 下部 44% のみ overlay_tex（half/open）で差し替え、境界はグラジェントブレンドで隠す。
## オーバーレイは自身のサイズで COVER クロップするため size 不一致でも崩れない。
func _draw_mouth_composite(base_tex: Texture2D, overlay_tex: Texture2D, dst: Rect2) -> void:
	# ── ベース COVER クロップ ────────────────────────────
	var bsz := base_tex.get_size()
	var src := Rect2(Vector2.ZERO, bsz)
	var da  := dst.size.x / maxf(dst.size.y, 1.0)
	var sa  := bsz.x / maxf(bsz.y, 1.0)
	if sa > da:
		var nw := bsz.y * da
		src.position.x += (bsz.x - nw) * 0.5
		src.size.x = nw
	else:
		var nh := bsz.x / da
		src.position.y += (bsz.y - nh) * 0.5
		src.size.y = nh
	draw_texture_rect_region(base_tex, dst, src)

	if overlay_tex == null:
		return

	# ── オーバーレイ COVER クロップ（overlay 自身のサイズで計算）───
	var osz := overlay_tex.get_size()
	var osrc := Rect2(Vector2.ZERO, osz)
	var osa  := osz.x / maxf(osz.y, 1.0)
	if osa > da:
		var nw := osz.y * da
		osrc.position.x += (osz.x - nw) * 0.5
		osrc.size.x = nw
	else:
		var nh := osz.x / da
		osrc.position.y += (osz.y - nh) * 0.5
		osrc.size.y = nh

	# ── 下部を SPLIT から全開で描画 ────────────────────────
	const SPLIT  := 0.60   # 上 60% は base 固定（目・鼻・髪）
	const BLEND  := 0.10   # SPLIT 上 10% をグラジェントブレンド
	const STEPS  := 6      # グラジェントのステップ数

	# フル不透明ゾーン（SPLIT 〜 1.0）
	var oy  := dst.position.y + dst.size.y  * SPLIT
	var oh  := dst.size.y  * (1.0 - SPLIT)
	var osy := osrc.position.y + osrc.size.y * SPLIT
	var osh := osrc.size.y * (1.0 - SPLIT)
	draw_texture_rect_region(overlay_tex,
		Rect2(dst.position.x, oy, dst.size.x, oh),
		Rect2(osrc.position.x, osy, osrc.size.x, osh))

	# グラジェントゾーン（SPLIT-BLEND 〜 SPLIT）
	for i in STEPS:
		var t     := float(i) / float(STEPS - 1)     # 0.0 〜 1.0
		var frac0 := (SPLIT - BLEND) + BLEND * (float(i) / STEPS)
		var frac1 := frac0 + BLEND / STEPS
		var sy  := dst.position.y + dst.size.y  * frac0
		var sh  := dst.size.y  * (frac1 - frac0)
		var ssy := osrc.position.y + osrc.size.y * frac0
		var ssh := osrc.size.y * (frac1 - frac0)
		draw_texture_rect_region(overlay_tex,
			Rect2(dst.position.x, sy, dst.size.x, sh),
			Rect2(osrc.position.x, ssy, osrc.size.x, ssh),
			Color(1.0, 1.0, 1.0, t))


func _draw() -> void:
	var sz := size
	if sz.x < 4.0 or sz.y < 4.0:
		return
	# カメラ枠（暗背景＋ネオン縁）
	var accent: Color = KuroData.GIRLS[girl_id]["color"] if KuroData.GIRLS.has(girl_id) else Color(0.5, 0.8, 1.0)
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.04, 0.05, 0.09, 0.92))
	var inner := Rect2(2, 2, sz.x - 4, sz.y - 4)
	# flip_h=true のときキャンバス座標を水平反転してテクスチャを鏡像描画
	if flip_h:
		draw_set_transform(Vector2(sz.x, 0.0), 0.0, Vector2(-1.0, 1.0))
	# 顔：表情フレーム > 立ち絵頭部 > キャラ色バスト
	var drew := false
	if _blinking > 0.0:
		# まばたき中：blink フレームをそのまま描画（一瞬なので合成不要）
		var btex := _tex("%s_blink" % expression)
		if btex == null:
			btex = _tex("%s_closed" % expression)
		if btex != null:
			_draw_cover(btex, inner, Rect2(Vector2.ZERO, btex.get_size()))
			drew = true
	else:
		# 通常：closed を常にベースに使い、half/open は下部のみ合成
		var base := _tex("%s_closed" % expression)
		if base == null:
			base = _tex("neutral_closed")
		if base != null:
			var overlay: Texture2D = null
			if _mouth_frame != "closed":
				overlay = _tex("%s_%s" % [expression, _mouth_frame])
				# サイズ不一致（古い 256px 等）はニュートラルにフォールバック
				if overlay != null and overlay.get_size() != base.get_size():
					overlay = _tex("neutral_%s" % _mouth_frame)
				# expression 専用 half/open がない場合も neutral を使う
				if overlay == null and expression != "neutral":
					overlay = _tex("neutral_%s" % _mouth_frame)
			_draw_mouth_composite(base, overlay, inner)
			drew = true
	if not drew:
		var pf := _portrait()
		if pf != null:
			var ps := pf.get_size()
			_draw_cover(pf, inner, Rect2(0, 0, ps.x, ps.y * 0.42))  # 頭〜胸元
			drew = true
	if not drew:
		# 最終フォールバック：キャラ色のバスト＋頭文字
		draw_circle(Vector2(sz.x * 0.5, sz.y * 0.92), sz.x * 0.42, accent.darkened(0.2))
		draw_circle(Vector2(sz.x * 0.5, sz.y * 0.42), sz.x * 0.26, accent)
	# トランスフォームリセット（枠線・ラベルは反転しない）
	if flip_h:
		draw_set_transform(Vector2.ZERO)
	# 枠線（発話中は明るく脈動）
	var glow := 0.5 + (0.4 * (0.5 + 0.5 * sin(_pulse * 6.0)) if speaking else 0.0)
	draw_rect(Rect2(Vector2.ZERO, sz), Color(accent.r, accent.g, accent.b, glow), false, 2.0)
	# 名前＋赤LIVEドット
	if show_label and KuroData.GIRLS.has(girl_id):
		var font := get_theme_default_font()
		var nm := String(KuroData.GIRLS[girl_id]["name"])
		draw_rect(Rect2(0, sz.y - 20, sz.x, 20), Color(0.03, 0.03, 0.06, 0.7))
		draw_circle(Vector2(10, sz.y - 10), 3.5, Color(1.0, 0.25, 0.3))
		draw_string(font, Vector2(20, sz.y - 6), nm, HORIZONTAL_ALIGNMENT_LEFT, sz.x - 24, 12,
				Color(0.92, 0.95, 1.0))
