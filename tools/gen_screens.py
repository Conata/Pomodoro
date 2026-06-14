#!/usr/bin/env python3
"""3モードの画面モックを依存ゼロで合成する（Godot 無し環境での見た目確認用）。

gen_ui_kit.py の 9-patch テクスチャ＋パレットを使い、店/キャンプ/探索の
レイアウト意図を 1 枚絵にする。実装(main.gd)前の合意形成と、Step2 の指針。

    python3 tools/gen_screens.py
出力： assets/generated/ui/screen_shop.png / screen_camp.png / screen_dive.png
"""
import os
import math
import gen_ui_kit as K

ROOT = K.ROOT
C = K.COL
W, H = 380, 760

# COL に無い差し色（指定値）をローカルに補う。
CAMPFIRE = (0xff, 0xb3, 0x47)
SPARK = (0xff, 0xd5, 0x6b)
WINDOW_NIGHT = (0x2a, 0x35, 0x50)


def _bg(tint=(0x15, 0x15, 0x15), warm=0.0):
	buf = K.new_buf(W, H)
	for y in range(H):
		t = y / (H - 1)
		base = K.lerp(tint, (max(tint[0] - 8, 0), max(tint[1] - 8, 0), max(tint[2] - 8, 0)), t)
		for x in range(W):
			K.blend(buf, W, x, y, int(base[0]), int(base[1]), int(base[2]), 1.0)
	return buf


def _tex(name, store={}):
	if name not in store:
		K.import_png(os.path.join(ROOT, name + ".png"), store, name)
	return store[name]


def panel(buf, name, x, y, w, h, m):
	s = _tex(name)
	d = K.stretch9(s["buf"], s["w"], s["h"], m, w, h)
	K.paste(buf, W, d, w, h, x, y)


def disc(buf, cx, cy, r, col, a=1.0):
	for y in range(int(cy - r) - 1, int(cy + r) + 2):
		if y < 0 or y >= H:
			continue
		for x in range(int(cx - r) - 1, int(cx + r) + 2):
			if x < 0 or x >= W:
				continue
			d = math.hypot(x + 0.5 - cx, y + 0.5 - cy) - r
			cov = min(max(0.5 - d, 0.0), 1.0)
			if cov > 0:
				K.blend(buf, W, x, y, col[0], col[1], col[2], cov * a)


def soft_glow(buf, cx, cy, r, col, a=0.5):
	for y in range(int(cy - r), int(cy + r)):
		if y < 0 or y >= H:
			continue
		for x in range(int(cx - r), int(cx + r)):
			if x < 0 or x >= W:
				continue
			d = math.hypot(x - cx, y - cy) / r
			if d < 1.0:
				K.blend(buf, W, x, y, col[0], col[1], col[2], a * (1.0 - d) ** 2)


def char(buf, x, y, s, hair, name_col=None):
	"""ちびキャラのシルエット（頭＋体＋髪色）。スプライト確定までの placeholder。"""
	body = (0x2c, 0x2a, 0x27)
	# 体
	bw, bh = int(16 * s), int(22 * s)
	bx = x - bw // 2
	for yy in range(bh):
		t = yy / bh
		rr = int(bw * (0.5 + 0.5 * t) / 2)
		for xx in range(-rr, rr):
			K.blend(buf, W, x + xx, y + yy, body[0], body[1], body[2], 0.95)
	# 頭
	disc(buf, x, y - int(2 * s), int(8 * s), (0xe8, 0xd9, 0xc4))
	# 髪
	disc(buf, x, y - int(5 * s), int(8 * s), hair, 0.92)
	disc(buf, x, y - int(2 * s), int(8.5 * s), hair, 0.30)


def _txt(buf, x, y, n, col, cell=4, gap=2, a=0.62):
	for k in range(n):
		for yy in range(cell):
			for xx in range(cell - 1):
				K.blend(buf, W, x + k * (cell + gap) + xx, y + yy, col[0], col[1], col[2], a)


def topbar(buf, title_n, accent):
	panel(buf, "topbar", 10, 10, W - 20, 44, K.MARGINS["topbar"])
	_txt(buf, 26, 28, title_n, C["ink"])
	_txt(buf, W - 96, 28, 6, accent)  # 時刻/所持金


RED_NEON = (0xd2, 0x3b, 0x2e)


def navrail(buf, active=0):
	"""左の縦ナビ（店/探索/記憶の欠片/設定）。active を橙で点灯。"""
	panel(buf, "panel_inset", 8, 64, 46, 470, K.MARGINS["panel_inset"])
	cols = [C["amber"], C["mint"], C["purple"], C["ink"]]
	for i in range(4):
		cy = 96 + i * 70
		if i == active:
			panel(buf, "row", 12, cy - 20, 38, 40, K.MARGINS["row"])
		disc(buf, 31, cy, 11, cols[i] if i == active else (0x55, 0x52, 0x4c), 0.9)


# ── 店モード（ホーム画面：賑わう飯店＋集中を始めるCTA。接客シミュは裏で稼働） ──
def screen_shop():
	buf = _bg((0x16, 0x12, 0x10))
	# 上部バー：ロゴ＋時刻/日付＋ポモドーロ＋ベル/メニュー
	panel(buf, "topbar", 8, 10, W - 16, 46, K.MARGINS["topbar"])
	disc(buf, 28, 33, 10, (0x12, 0x12, 0x12)); disc(buf, 24, 30, 3, C["amber"]); disc(buf, 32, 30, 3, C["amber"])
	_txt(buf, 46, 28, 6, C["ink"])           # 黒猫飯店
	_txt(buf, 150, 28, 5, C["ink"])          # 23:41 5/24
	disc(buf, 280, 33, 9, (0, 0, 0, 0));
	for r in (9, 6):
		disc(buf, 280, 33, r, C["mint"], 0.25)
	_txt(buf, 296, 30, 4, C["mint"])         # 25:00
	disc(buf, W - 40, 33, 6, C["amber"], 0.8)  # ベル
	_txt(buf, W - 24, 28, 2, C["ink"])         # メニュー
	# 左ナビ
	navrail(buf, active=0)
	# 飯店内観（主役・赤ネオン）
	panel(buf, "panel", 60, 64, W - 70, 470, K.MARGINS["panel"])
	soft_glow(buf, 210, 230, 230, RED_NEON, 0.10)
	soft_glow(buf, 210, 200, 150, C["amber"], 0.08)
	# 赤ネオン看板「黒猫飯店」
	panel(buf, "panel_inset", 150, 92, 150, 40, K.MARGINS["panel_inset"])
	for gx in range(5):
		_txt(buf, 168 + gx * 26, 104, 2, RED_NEON, cell=6, gap=2, a=0.95)
	soft_glow(buf, 225, 112, 90, RED_NEON, 0.18)
	# 窓（夜の青）
	panel(buf, "panel_inset", 78, 150, 80, 64, K.MARGINS["panel_inset"])
	soft_glow(buf, 118, 182, 44, WINDOW_NIGHT, 0.5)
	# カウンター
	for yy in range(300, 322):
		for xx in range(80, W - 24):
			K.blend(buf, W, xx, yy, 0x3a, 0x16, 0x12, 0.7)
	# キャラ：店主ミル(奥)・常連・主役の赤髪・紫キリコ・黒猫たち
	char(buf, 150, 290, 3.0, (0x33, 0x2e, 0x3a))   # ミル（カウンター内）
	char(buf, 250, 370, 3.6, RED_NEON)             # 赤髪の主役（手前）
	char(buf, 320, 360, 3.2, C["purple"])          # キリコ（紫）
	disc(buf, 110, 400, 14, (0x12, 0x12, 0x12)); disc(buf, 104, 392, 3, C["amber"]); disc(buf, 116, 392, 3, C["amber"])  # 黒猫
	disc(buf, 350, 300, 11, (0x12, 0x12, 0x12))    # 黒猫2
	# 大CTA：集中を始める（ミント＝ポモドーロ）
	panel(buf, "button_mint", 60, 548, W - 200, 56, K.MARGINS["button"])
	_txt(buf, 110, 566, 8, (0x0c, 0x2a, 0x23))     # 集中を始める
	_txt(buf, 110, 584, 6, (0x0c, 0x2a, 0x23), cell=3, gap=1, a=0.7)  # ポモドーロ 25:00
	_txt(buf, 70, 614, 7, C["ink"], cell=3, gap=1, a=0.5)            # 長押しでクイック
	# 右下スタッツ：評判/資金/記憶の欠片
	panel(buf, "row", W - 132, 548, 122, 150, K.MARGINS["row"])
	for k in range(5):
		disc(buf, W - 116 + k * 18, 572, 6, C["amber"] if k < 3 else (0x40, 0x3a, 0x33))
	_txt(buf, W - 120, 596, 4, C["ink"])     # 資金
	_txt(buf, W - 120, 620, 5, C["amber"])   # 12,840G
	_txt(buf, W - 120, 648, 4, C["purple"])  # 記憶の欠片 128
	K.save_png(os.path.join(ROOT, "screen_shop.png"), W, H, buf)
	print("  screen_shop.png")


# ── キャンプモード（休憩＝情報量↑・焚き火＋仲間＋会話ログ） ────────────────
def screen_camp():
	buf = _bg((0x11, 0x11, 0x11))
	topbar(buf, 7, C["amber"])  # キャンプ 休憩 04:32
	# 焚き火
	soft_glow(buf, W // 2, 250, 150, CAMPFIRE, 0.5)
	soft_glow(buf, W // 2, 250, 70, SPARK, 0.6)
	disc(buf, W // 2, 270, 26, CAMPFIRE, 0.9)
	disc(buf, W // 2, 262, 14, SPARK, 0.9)
	# 仲間4人（焚き火を囲む）
	char(buf, 90, 250, 3.4, (0x33, 0x2e, 0x3a))   # ミル
	char(buf, 290, 250, 3.4, (0x6a, 0x4a, 0x2a))  # ムュウ
	char(buf, 120, 360, 3.4, (0x46, 0x9d, 0x84))  # レイカ（ミント寄り）
	char(buf, 260, 360, 3.4, (0x8e, 0x6b, 0xc7))  # フズキ
	# 会話ログ（情報量を増やすモード）
	panel(buf, "bubble", 24, 430, W - 48, 110, K.MARGINS["bubble"])
	for i in range(4):
		_txt(buf, 40, 450 + i * 22, 12 - i, C["ink"], a=0.7)
	# 支度ボタン（装備/献立）＋潜るCTA
	panel(buf, "button", 10, 560, (W - 30) // 2, 52, K.MARGINS["button"]); _txt(buf, 60, 580, 4, C["ink"])
	panel(buf, "button", 20 + (W - 30) // 2, 560, (W - 30) // 2, 52, K.MARGINS["button"]); _txt(buf, 230, 580, 4, C["ink"])
	panel(buf, "button_primary", 10, 624, W - 20, 56, K.MARGINS["button"]); _txt(buf, 150, 646, 6, (0x23, 0x17, 0x08))
	K.save_png(os.path.join(ROOT, "screen_camp.png"), W, H, buf)
	print("  screen_camp.png")


# ── 探索モード（ポモドーロ中＝放置・最小情報・戦闘ログ無し） ──────────────
def screen_dive():
	buf = _bg((0x1a, 0x1c, 0x2a))  # ダンジョン通常 #2B2D42 寄り
	soft_glow(buf, W // 2, 300, 260, C["purple"], 0.10)  # オカルトの気配
	topbar(buf, 6, C["mint"])  # 場所＋時刻
	# 大きな探索ビュー（暗い・抽象）
	panel(buf, "panel_inset", 10, 64, W - 20, 360, K.MARGINS["panel_inset"])
	# パーティの点（小さく）
	for k in range(4):
		disc(buf, 150 + k * 28, 250, 6, C["mint"] if k == 0 else (0x6a, 0x66, 0x60))
	# 最小情報のみ（戦闘ログは出さない）
	panel(buf, "row", 10, 440, W - 20, 150, K.MARGINS["row"])
	_txt(buf, 28, 462, 7, C["mint"])    # 探索率 72%
	_txt(buf, 28, 500, 9, C["ink"])     # 現在地：忘却区画
	_txt(buf, 28, 538, 9, C["purple"])  # 遭遇：人格『後悔』
	# ポモドーロ残り（ミントの大バー）
	panel(buf, "bar_bg", 10, 612, W - 20, 16, 7)
	panel(buf, "bar_mint", 10, 612, int((W - 20) * 0.72), 16, 7)
	_txt(buf, 150, 648, 6, C["mint"], cell=6, gap=3)  # 18:22 / 25:00
	K.save_png(os.path.join(ROOT, "screen_dive.png"), W, H, buf)
	print("  screen_dive.png")


def main():
	print("3モード画面モック生成")
	screen_shop()
	screen_camp()
	screen_dive()
	print("完了。")


if __name__ == "__main__":
	main()
