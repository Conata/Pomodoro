class_name GameData
extends RefCounted
## 静的ゲームデータ。DESIGN.md の「システム仕様（TBH実仕様準拠）」に対応する。
## バランス数値はすべてここに集約し、ロジック（GameSim）からは参照のみ。

const SIM_DT := 0.2  # 固定ステップ秒。DESIGN.md タイマー実装の要
const LAYER_LENGTH := 600.0  # 1層=600m
const CHEST_INTERVAL := 480.0  # 箱は8分毎
const SHIP_ROTATE_SEC := 600.0  # 交易船は10分毎
const OFFLINE_CAP_SEC := 28800.0  # 安息の上限8時間
const BLESSING_TIMEOUT := 15.0  # 加護の自動選択
const REROLL_COST := 50  # 刻印=星屑50

# グレード7段階（粗末〜星界）
const GRADES := [
	{"name": "粗末", "mult": 1.0, "color": Color(0.55, 0.55, 0.55)},
	{"name": "普通", "mult": 1.4, "color": Color(0.85, 0.85, 0.85)},
	{"name": "上質", "mult": 2.0, "color": Color(0.45, 0.85, 0.45)},
	{"name": "精錬", "mult": 3.0, "color": Color(0.4, 0.65, 1.0)},
	{"name": "英雄", "mult": 4.5, "color": Color(0.75, 0.45, 1.0)},
	{"name": "伝説", "mult": 7.0, "color": Color(1.0, 0.65, 0.2)},
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
	"xp": {"name": "知", "min": 3, "max": 10},
	"crit": {"name": "会", "min": 2, "max": 8},
}

const CLASSES := {
	"warrior": {"name": "戦士", "atk": 12.0, "hp": 130.0},
	"mage": {"name": "魔法使い", "atk": 16.0, "hp": 80.0},
	"priest": {"name": "僧侶", "atk": 8.0, "hp": 95.0},
	"rogue": {"name": "盗賊", "atk": 14.0, "hp": 90.0},
}

const HERO_NAMES := ["アルト", "ベル", "セロ", "ディア", "エマ", "フィン", "ギド", "ハナ", "イオ", "ユノ"]

# ヒーロー毎に装備するCD制アクティブ。レベルで習得（lv）
const SKILL_DB := {
	"strike": {"cls": "warrior", "name": "強撃", "lv": 1, "cd": 6.0, "kind": "hit", "power": 2.5},
	"whirl": {"cls": "warrior", "name": "旋風", "lv": 8, "cd": 12.0, "kind": "aoe", "power": 1.6},
	"bulwark": {"cls": "warrior", "name": "鉄壁", "lv": 16, "cd": 25.0, "kind": "shield_all", "power": 0.25},
	"fireball": {"cls": "mage", "name": "火球", "lv": 1, "cd": 8.0, "kind": "aoe", "power": 2.0},
	"chain": {"cls": "mage", "name": "連鎖雷", "lv": 10, "cd": 14.0, "kind": "aoe", "power": 2.8},
	"pray": {"cls": "priest", "name": "祈り", "lv": 1, "cd": 10.0, "kind": "heal_one", "power": 0.3},
	"circle": {"cls": "priest", "name": "癒しの輪", "lv": 8, "cd": 18.0, "kind": "heal_all", "power": 0.4},
	"sanctuary": {"cls": "priest", "name": "聖域", "lv": 16, "cd": 30.0, "kind": "shield_all", "power": 0.4},
	"ambush": {"cls": "rogue", "name": "急襲", "lv": 1, "cd": 7.0, "kind": "gold_hit", "power": 2.2},
	"shadow": {"cls": "rogue", "name": "影討ち", "lv": 12, "cd": 13.0, "kind": "hit", "power": 3.2},
}

# ルーンツリー: ゴールド消費・マップ型・隣接（prev のいずれか所持）から解放。
# 方向別傾向: 上=宝箱系/左上=金策/左下=経験値/右=戦闘/下=システム
const RT_NODES := {
	"start": {"name": "起点", "cost": 0, "pos": [0, 0], "prev": [], "effect": {}, "desc": "すべての始まり"},
	# 上: 宝箱系
	"chest1": {"name": "箱の鍵Ⅰ", "cost": 200, "pos": [0, -1], "prev": ["start"], "effect": {"chest_interval": 0.10}, "desc": "箱の獲得間隔 -10%"},
	"chest2": {"name": "箱の鍵Ⅱ", "cost": 800, "pos": [0, -2], "prev": ["chest1"], "effect": {"chest_interval": 0.15}, "desc": "箱の獲得間隔 -15%"},
	"chest3": {"name": "宝物庫", "cost": 2500, "pos": [0, -3], "prev": ["chest2"], "effect": {"chest_quality": 1.0}, "desc": "箱の中身が豪華になる"},
	# 左上: 金策
	"gold1": {"name": "商才Ⅰ", "cost": 300, "pos": [-1, -1], "prev": ["start"], "effect": {"gold": 0.10}, "desc": "獲得ゴールド +10%"},
	"gold2": {"name": "商才Ⅱ", "cost": 900, "pos": [-2, -1], "prev": ["gold1"], "effect": {"gold": 0.15}, "desc": "獲得ゴールド +15%"},
	"gold3": {"name": "黄金律", "cost": 3000, "pos": [-3, -2], "prev": ["gold2"], "effect": {"gold": 0.25}, "desc": "獲得ゴールド +25%"},
	# 左下: 経験値
	"xp1": {"name": "見聞Ⅰ", "cost": 300, "pos": [-1, 1], "prev": ["start"], "effect": {"xp": 0.10}, "desc": "獲得XP +10%"},
	"xp2": {"name": "見聞Ⅱ", "cost": 900, "pos": [-2, 1], "prev": ["xp1"], "effect": {"xp": 0.15}, "desc": "獲得XP +15%"},
	"xp3": {"name": "叡智", "cost": 3000, "pos": [-3, 2], "prev": ["xp2"], "effect": {"xp": 0.25}, "desc": "獲得XP +25%"},
	# 右: 戦闘
	"atk1": {"name": "刃研ぎ", "cost": 250, "pos": [1, 0], "prev": ["start"], "effect": {"atk": 0.08}, "desc": "攻撃 +8%"},
	"hp1": {"name": "鍛錬", "cost": 700, "pos": [2, 0], "prev": ["atk1"], "effect": {"hp": 0.10}, "desc": "最大HP +10%"},
	"atk2": {"name": "闘気", "cost": 1800, "pos": [3, 0], "prev": ["hp1"], "effect": {"atk": 0.12}, "desc": "攻撃 +12%"},
	"crit1": {"name": "急所読み", "cost": 1200, "pos": [2, -1], "prev": ["hp1"], "effect": {"crit": 0.10}, "desc": "会心 +10%"},
	"spd1": {"name": "健脚", "cost": 1200, "pos": [2, 1], "prev": ["hp1"], "effect": {"spd": 0.10}, "desc": "移動速度 +10%"},
	# 下: システム（ゲーム構造を変える）
	"cmd1": {"name": "指揮Ⅰ", "cost": 1500, "pos": [0, 1], "prev": ["start"], "effect": {"party": 1}, "desc": "ヒーロー枠 +1"},
	"clockwork": {"name": "ぜんまい", "cost": 1200, "pos": [1, 2], "prev": ["cmd1"], "effect": {"auto_chest": 1}, "desc": "箱を自動で開封する"},
	"rest": {"name": "安息", "cost": 2000, "pos": [-1, 2], "prev": ["cmd1"], "effect": {"offline": 1}, "desc": "オフライン報酬（上限8時間）"},
	"awaken": {"name": "覚醒", "cost": 2500, "pos": [0, 2], "prev": ["cmd1"], "effect": {"skill_slot": 1}, "desc": "全員のスキル枠 +1"},
	"cmd2": {"name": "指揮Ⅱ", "cost": 6000, "pos": [0, 3], "prev": ["awaken"], "effect": {"party": 1}, "desc": "ヒーロー枠 +1"},
}

# バイオーム5種ループ
const BIOMES := [
	{"name": "苔の森", "color": Color(0.14, 0.30, 0.20)},
	{"name": "廃坑", "color": Color(0.28, 0.22, 0.15)},
	{"name": "水晶洞", "color": Color(0.16, 0.24, 0.40)},
	{"name": "溶岩窟", "color": Color(0.38, 0.14, 0.10)},
	{"name": "星霜の塔", "color": Color(0.22, 0.15, 0.36)},
]

# レベルアップ時の加護（パーティ全体に累積）
const BLESSINGS := [
	{"id": "atk", "name": "猛攻の加護", "val": 0.10, "desc": "攻撃 +10%"},
	{"id": "hp", "name": "堅守の加護", "val": 0.12, "desc": "最大HP +12%"},
	{"id": "spd", "name": "疾駆の加護", "val": 0.08, "desc": "移動 +8%"},
	{"id": "gold", "name": "黄金の加護", "val": 0.10, "desc": "獲得G +10%"},
	{"id": "xp", "name": "叡智の加護", "val": 0.10, "desc": "獲得XP +10%"},
]

const PETS := {
	"cat": {"name": "金策猫", "cost": 5000, "effect": {"gold": 0.15}, "desc": "獲得G +15%"},
	"owl": {"name": "学者梟", "cost": 5000, "effect": {"xp": 0.15}, "desc": "獲得XP +15%"},
	"fox": {"name": "探索狐", "cost": 5000, "effect": {"discover": 0.15}, "desc": "ドロップ発見率アップ"},
}


## 周回スケーリング。DESIGN.md: areaScale(idx)=1+idx*0.8
static func area_scale(idx: int) -> float:
	return 1.0 + idx * 0.8


static func xp_needed(lv: int) -> float:
	return 20.0 * pow(lv, 1.6)
