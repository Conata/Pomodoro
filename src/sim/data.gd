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
const CHEST_INTERVAL := 480.0  # 箱はプレイ時間8分毎に蓄積（TBH準拠）
const SHIP_ROTATE_SEC := 600.0  # 交易船は10分毎に在庫入替
const OFFLINE_CAP_SEC := 28800.0  # 安息の上限8時間

# 深度スケーリング sc=1+flAbs*0.35
static func depth_scale(fl_abs: int) -> float:
	return 1.0 + fl_abs * 0.35


# 素材3種（Dave the Diver サイクル：何を獲ったかが献立を決める）
const INGS := ["dry", "meat", "sea"]
const ING_NAMES := {"dry": "乾物", "meat": "肉", "sea": "海鮮"}

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

# スキル（TBH準拠：装備するCD制アクティブ。好感度で習得、枠1＋覚醒で2）
# unlock: 0=最初から / 1=aff45 / 2=aff80
const SKILL_DB := {
	"first_aid": {"girl": "mil", "name": "応急手当", "unlock": 0, "cd": 10.0, "kind": "heal_one", "power": 0.32},
	"cover": {"girl": "mil", "name": "庇い手", "unlock": 1, "cd": 24.0, "kind": "shield_all", "power": 0.25},
	"sanctum": {"girl": "mil", "name": "静域", "unlock": 2, "cd": 30.0, "kind": "shield_all", "power": 0.42},
	"wok_fist": {"girl": "yuzuki", "name": "まかない拳", "unlock": 0, "cd": 6.0, "kind": "hit", "power": 2.5},
	"wok_storm": {"girl": "yuzuki", "name": "中華鍋旋風", "unlock": 1, "cd": 12.0, "kind": "aoe", "power": 1.6},
	"honki": {"girl": "yuzuki", "name": "本気の一撃", "unlock": 2, "cd": 20.0, "kind": "hit", "power": 4.5},
	"buzz": {"girl": "muu", "name": "バズワード", "unlock": 0, "cd": 9.0, "kind": "aoe", "power": 1.4},
	"encore": {"girl": "muu", "name": "アンコール", "unlock": 1, "cd": 18.0, "kind": "heal_all", "power": 0.4},
	"viral": {"girl": "muu", "name": "拡散", "unlock": 2, "cd": 14.0, "kind": "aoe", "power": 2.6},
	"observe": {"girl": "kiriko", "name": "観測射撃", "unlock": 0, "cd": 7.0, "kind": "hit", "power": 2.8},
	"hypothesis": {"girl": "kiriko", "name": "雷の仮説", "unlock": 1, "cd": 14.0, "kind": "aoe", "power": 2.4},
	"reconnect": {"girl": "kiriko", "name": "再接続理論", "unlock": 2, "cd": 22.0, "kind": "hit", "power": 5.2},
}
const SKILL_UNLOCK_AFF := [0, 45, 80]

# 改装ツリー（TBHのルーンツリー準拠：ゴールド消費・マップ型・隣接解放）
# 方向別傾向: 上=宝箱系／左上=金策／左下=素材／右=戦闘／下=システム
const RENOV_NODES := {
	"start": {"name": "店の鍵", "cost": 0, "pos": [0, 0], "prev": [], "effect": {}, "desc": "すべての始まり"},
	"chest1": {"name": "箱の勘Ⅰ", "cost": 200, "pos": [0, -1], "prev": ["start"], "effect": {"chest_interval": 0.10}, "desc": "箱の蓄積間隔 -10%"},
	"chest2": {"name": "箱の勘Ⅱ", "cost": 800, "pos": [0, -2], "prev": ["chest1"], "effect": {"chest_interval": 0.15}, "desc": "箱の蓄積間隔 -15%"},
	"chest3": {"name": "目利き", "cost": 2500, "pos": [0, -3], "prev": ["chest2"], "effect": {"chest_quality": 1.0}, "desc": "箱の中身が豪華になる"},
	"gold1": {"name": "商いⅠ", "cost": 300, "pos": [-1, -1], "prev": ["start"], "effect": {"gold": 0.10}, "desc": "獲得ゴールド +10%"},
	"gold2": {"name": "商いⅡ", "cost": 900, "pos": [-2, -1], "prev": ["gold1"], "effect": {"gold": 0.15}, "desc": "獲得ゴールド +15%"},
	"gold3": {"name": "老舗の貫禄", "cost": 3000, "pos": [-3, -2], "prev": ["gold2"], "effect": {"gold": 0.25}, "desc": "獲得ゴールド +25%"},
	"mat1": {"name": "仕入れ筋Ⅰ", "cost": 300, "pos": [-1, 1], "prev": ["start"], "effect": {"mat": 0.04}, "desc": "素材ドロップ +4pt"},
	"mat2": {"name": "仕入れ筋Ⅱ", "cost": 900, "pos": [-2, 1], "prev": ["mat1"], "effect": {"mat": 0.06}, "desc": "素材ドロップ +6pt"},
	"mat3": {"name": "地下の市場", "cost": 3000, "pos": [-3, 2], "prev": ["mat2"], "effect": {"mat": 0.10}, "desc": "素材ドロップ +10pt"},
	"atk1": {"name": "包丁研ぎ", "cost": 250, "pos": [1, 0], "prev": ["start"], "effect": {"atk": 0.08}, "desc": "攻撃 +8%"},
	"hp1": {"name": "賄いの底力", "cost": 700, "pos": [2, 0], "prev": ["atk1"], "effect": {"hp": 0.10}, "desc": "最大HP +10%"},
	"atk2": {"name": "火力の極み", "cost": 1800, "pos": [3, 0], "prev": ["hp1"], "effect": {"atk": 0.12}, "desc": "攻撃 +12%"},
	"crit1": {"name": "急所の図面", "cost": 1200, "pos": [2, -1], "prev": ["hp1"], "effect": {"crit": 0.10}, "desc": "会心 +10%"},
	"kitchen": {"name": "厨房拡張", "cost": 3500, "pos": [1, -1], "prev": ["chest1", "atk1"], "effect": {"menu_slot": 1}, "desc": "献立枠 +1（披露の幅が広がる）"},
	"spd1": {"name": "出前の健脚", "cost": 1200, "pos": [2, 1], "prev": ["hp1"], "effect": {"spd": 0.10}, "desc": "潜行速度 +10%"},
	"sign1": {"name": "ネオン看板", "cost": 1500, "pos": [0, 1], "prev": ["start"], "effect": {"sign": 1}, "desc": "看板 +1（客が増える）"},
	"clockwork": {"name": "ぜんまい仕掛け", "cost": 1200, "pos": [1, 2], "prev": ["sign1"], "effect": {"auto_chest": 1}, "desc": "箱を自動で開封する"},
	"rest": {"name": "安息", "cost": 2000, "pos": [-1, 2], "prev": ["sign1"], "effect": {"offline": 1}, "desc": "閉店中も収入（上限8時間）"},
	"awaken": {"name": "覚醒", "cost": 2500, "pos": [0, 2], "prev": ["sign1"], "effect": {"skill_slot": 1}, "desc": "全員のスキル枠 +1"},
	"sign2": {"name": "増築", "cost": 6000, "pos": [0, 3], "prev": ["awaken"], "effect": {"sign": 2}, "desc": "看板 +2"},
}

# ペット3種（交易船で稀に売られる）
const PETS := {
	"owl": {"name": "雨宿りの梟", "cost": 5000, "effect": {"gold": 0.15}, "desc": "売上 +15%"},
	"lizard": {"name": "配管の蜥蜴", "cost": 5000, "effect": {"mat": 0.05}, "desc": "素材ドロップ +5pt"},
	"fox": {"name": "路地の狐", "cost": 5000, "effect": {"discover": 0.06}, "desc": "装備の発見 +6pt"},
}

# レシピカード：通常9種＋特注3種（住民ストーリー紐付き）。
# 重複＝星上げ☆3まで（価格+25%/星）
const RECIPES := {
	"tantan": {"name": "担々麺", "taste": "辛", "base": 42, "ing": "dry"},
	"mabo": {"name": "麻婆豆腐", "taste": "辛", "base": 38, "ing": "meat"},
	"suanla": {"name": "酸辣湯", "taste": "辛", "base": 34, "ing": "sea"},
	"chashu": {"name": "叉焼麺", "taste": "旨", "base": 40, "ing": "meat"},
	"chahan": {"name": "炒飯", "taste": "旨", "base": 32, "ing": "dry"},
	"wantan": {"name": "雲呑湯", "taste": "淡", "base": 30, "ing": "sea"},
	"okayu": {"name": "翡翠粥", "taste": "淡", "base": 28, "ing": "dry"},
	"annin": {"name": "杏仁豆腐", "taste": "甘", "base": 26, "ing": "dry"},
	"goma": {"name": "胡麻団子", "taste": "甘", "base": 24, "ing": "dry"},
	# 特注（売れた夜に住民ストーリー発火→永続バフ）
	"yakuzen": {"name": "タオ爺の薬膳火鍋", "taste": "辛", "base": 88, "ing": "meat", "resident": "tao"},
	"parfait": {"name": "ノノの電脳パフェ", "taste": "甘", "base": 80, "ing": "dry", "resident": "nono"},
	"wasure": {"name": "404さんの忘れ麺", "taste": "淡", "base": 84, "ing": "sea", "resident": "err404"},
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
	{"name": "管理区画", "color": Color(0.10, 0.16, 0.34), "ing": "dry",
		"mobs": ["tiny_zombie", "skelet"], "boss": "big_zombie"},
	{"name": "商店遺構", "color": Color(0.08, 0.20, 0.30), "ing": "meat",
		"mobs": ["goblin", "imp"], "boss": "ogre"},
	{"name": "記憶の海", "color": Color(0.07, 0.12, 0.38), "ing": "sea",
		"mobs": ["wogol", "ice_zombie"], "boss": "big_demon"},
]

# 闇市（夜に3品）
const MARKET := [
	{"id": "recipe", "name": "レシピの写本（ランダム）", "price": 250},
	{"id": "mats", "name": "素材箱（乾・肉・海 +2ずつ）", "price": 100},
	{"id": "invite", "name": "招待状（翌夜 客+3）", "price": 150},
]


static func recipe_price(id: String, star: int) -> int:
	return int(float(RECIPES[id]["base"]) * (1.0 + 0.25 * (star - 1)))


static func girl_mult(aff: int) -> float:
	return 1.0 + aff / 200.0
