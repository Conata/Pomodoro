class_name KuroData
extends RefCounted
## 黒猫飯店 — 静的ゲームデータ。DESIGN.md（実装仕様 v4）準拠。
## バランス数値はここに集約し、ロジック（KuroSim）からは参照のみ。

const SIM_DT := 0.2  # 固定ステップ秒（ポモドーロ機構の要）
const FLOOR_LEN := 420.0  # 階長
const DOOR_AT := 0.55  # 階中間55%地点に「増築された扉」
const QUICK_SEC := 80.0  # クイックダイブ
const DOOR_BANNER_SEC := 12.0  # クイック時の決断バナー（同期時間+12秒補償）
const DIVE_SPEED := 2.4  # m/s。エンカウント間隔11-17m ≒ 撃破後4.5-7秒
const ENC_MIN := 11.0
const ENC_MAX := 17.0
const RESYNC_BACK := 40.0  # 緊急再同期で戻る距離
const BREAK_SEC := 300.0  # 夜（休憩）の目安5分

# 深度スケーリング sc=1+flAbs*0.35
static func depth_scale(fl_abs: int) -> float:
	return 1.0 + fl_abs * 0.35


# 味4系統
const TASTES := ["辛", "甘", "旨", "淡"]
const TASTE_COLORS := {
	"辛": Color(1.0, 0.45, 0.45),
	"甘": Color(1.0, 0.75, 0.85),
	"旨": Color(1.0, 0.85, 0.5),
	"淡": Color(0.65, 0.9, 1.0),
}

# ヒロイン4人。order固定（ミルが必ず盾）。aff倍率 1+aff/200
# keeper_apt: 店番の仕込み適性 / synergy: 店番シナジー
const GIRLS := {
	"mil": {
		"name": "ミル", "order": 0, "role": "前衛・守護", "sprite": "knight_f",
		"hp": 150.0, "atk": 7.0, "fav": "淡",
		"keeper_apt": 1.0, "synergy": "静かな給仕", "synergy_desc": "単価+10%",
		"color": Color(0.8, 0.9, 1.0),
	},
	"yuzuki": {
		"name": "ユズキ", "order": 1, "role": "近接火力", "sprite": "elf_f",
		"hp": 110.0, "atk": 13.0, "fav": "旨",
		"keeper_apt": 1.35, "synergy": "解析いらずの仕込み", "synergy_desc": "仕込み数+35%",
		"color": Color(1.0, 0.75, 0.55),
	},
	"muu": {
		"name": "ムゥ", "order": 2, "role": "手数・歌", "sprite": "wizzard_f",
		"hp": 95.0, "atk": 9.0, "fav": "甘",
		"keeper_apt": 0.9, "synergy": "店内ライブ", "synergy_desc": "客数+4",
		"color": Color(1.0, 0.7, 0.9),
	},
	"kiriko": {
		"name": "キリコ", "order": 3, "role": "後衛重撃・高クリ", "sprite": "necromancer",
		"hp": 85.0, "atk": 16.0, "fav": "辛",
		"keeper_apt": 1.0, "synergy": "解析仕込み", "synergy_desc": "予報外れの皿も売れる",
		"color": Color(0.75, 0.65, 1.0),
	},
}

const GIRL_ORDER := ["mil", "yuzuki", "muu", "kiriko"]

# 会話解放閾値（好感度）
const TALK_THRESHOLDS := [15, 45, 80]

# レシピカード：通常9種＋特注3種（住民ストーリー紐付き）。
# 重複＝星上げ☆3まで（価格+25%/星）
const RECIPES := {
	"tantan": {"name": "担々麺", "taste": "辛", "base": 42},
	"mabo": {"name": "麻婆豆腐", "taste": "辛", "base": 38},
	"suanla": {"name": "酸辣湯", "taste": "辛", "base": 34},
	"chashu": {"name": "叉焼麺", "taste": "旨", "base": 40},
	"chahan": {"name": "炒飯", "taste": "旨", "base": 32},
	"wantan": {"name": "雲呑湯", "taste": "淡", "base": 30},
	"okayu": {"name": "翡翠粥", "taste": "淡", "base": 28},
	"annin": {"name": "杏仁豆腐", "taste": "甘", "base": 26},
	"goma": {"name": "胡麻団子", "taste": "甘", "base": 24},
	# 特注（売れた夜に住民ストーリー発火→永続バフ）
	"yakuzen": {"name": "タオ爺の薬膳火鍋", "taste": "辛", "base": 88, "resident": "tao"},
	"parfait": {"name": "ノノの電脳パフェ", "taste": "甘", "base": 80, "resident": "nono"},
	"wasure": {"name": "404さんの忘れ麺", "taste": "淡", "base": 84, "resident": "err404"},
}

const RESIDENTS := {
	"tao": {"name": "タオ爺", "buff": "薬膳の評判で客数+2",
		"story": "「効くかどうかは、わしが決める」タオ爺は完食し、杖の代わりに箸を立てて帰った。翌日から、爺の弟子たちが通ってくる。"},
	"nono": {"name": "ノノ", "buff": "解析共有で素材ドロップ+8%",
		"story": "「甘味は演算を加速する……」ノノはパフェの層構造を3分撮影してから食べた。お礼に、深層の素材マップが届いた。"},
	"err404": {"name": "404さん", "buff": "投げ銭で売上+10%",
		"story": "「思い出せないままで、うまかった」404さんは名前のない通貨で払った。レジは受理した。なぜかは聞かないことにする。"},
}

# 箱グレード4段階
const BOX_NAMES := ["木箱", "鉄箱", "銀箱", "金箱"]
# drop table: レシピ50%／設備15%／記憶の欠片25%（♥+10）／招待状10%
const DROP_RECIPE := 0.50
const DROP_EQUIP := 0.15
const DROP_SHARD := 0.25

# バイオーム3種ループ（電脳深層＝最初の店主の脳内）
const BIOMES := [
	{"name": "管理区画", "color": Color(0.10, 0.16, 0.34),
		"mobs": ["tiny_zombie", "skelet"], "boss": "big_zombie"},
	{"name": "商店遺構", "color": Color(0.08, 0.20, 0.30),
		"mobs": ["goblin", "imp"], "boss": "ogre"},
	{"name": "記憶の海", "color": Color(0.07, 0.12, 0.38),
		"mobs": ["wogol", "ice_zombie"], "boss": "big_demon"},
]

# 闇市（夜に3品）
const MARKET := [
	{"id": "recipe", "name": "レシピの写本（ランダム）", "price": 250},
	{"id": "mats", "name": "素材箱（+5）", "price": 100},
	{"id": "invite", "name": "招待状（翌夜 客+3）", "price": 150},
]


static func recipe_price(id: String, star: int) -> int:
	return int(float(RECIPES[id]["base"]) * (1.0 + 0.25 * (star - 1)))


static func girl_mult(aff: int) -> float:
	return 1.0 + aff / 200.0
