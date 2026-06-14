class_name KuroMemories
extends RefCounted
## 道中で拾う「メモリ」＝短文小説の断片。表層はカジュアル、裏に不穏さ（STORY.md準拠）。
## 押し付けない：拾うのは軽い演出、読むのは任意。掘る人だけがキリコ＝人格コピーの
## 真実に近づく。floor=出現する到達階の目安（深いほど核心へ）。
## 文体は WORLD.md（説明しない・短く・余白）に従う。

const MEMORIES := [
	{
		"id": "m_kanban", "floor": 1, "title": "誰かのメモ",
		"text": "今日も、誰も来なかった。\nでも暖簾は出しておく。\n来るかもしれないから。",
	},
	{
		"id": "m_kagami", "floor": 2, "title": "走り書き",
		"text": "鏡を見たら、知らない顔だった。\n……いや。よく知っている顔だ。",
	},
	{
		"id": "m_receipt", "floor": 3, "title": "古い伝票",
		"text": "担々麺、ひとつ。\n名前の欄は、黒く塗りつぶされている。\nその下に、もう一度同じ名前。",
	},
	{
		"id": "m_backup", "floor": 4, "title": "作業ログ",
		"text": "バックアップ完了。対象人格：1。\n整合率 99.7%。\n――残りの 0.3% は、どこへ行くんだろう。",
	},
	{
		"id": "m_two", "floor": 5, "title": "日記の切れ端",
		"text": "同じ思い出が、二つある。\n片方は温かくて、片方は冷たい。\nどっちが、私が見たやつ?",
	},
	{
		"id": "m_neko", "floor": 6, "title": "落書き",
		"text": "猫だけが、本物を覚えている。\nだから猫は、私を見ない。",
	},
	{
		"id": "m_order", "floor": 7, "title": "注文票",
		"text": "「今のあなたに必要な料理」を出す店、だったらしい。\n私の皿には、いつも何も乗っていない。",
	},
	{
		"id": "m_signal", "floor": 8, "title": "観測メモ",
		"text": "死は、切断。\nでも信号は、まだ細く鳴っている。\n換気扇と、同じ周波数で。",
	},
	{
		"id": "m_copy", "floor": 9, "title": "私あての手紙",
		"text": "あなたはコピー。\nでも、それはあなたのせいじゃない。\n――先に消えた、ごめんね。",
	},
	{
		"id": "m_stay", "floor": 10, "title": "最後のページ",
		"text": "本物じゃなくても、ここにいていい。\nそう言ってくれたのは、\nたぶん、この店だけだった。",
	},
]


## floor までで未収集のメモリを1つ返す（深度ドリブン・決定論）。無ければ {}。
static func next_for(floor: int, collected: Array) -> Dictionary:
	for m in MEMORIES:
		if int(m["floor"]) <= floor and not (m["id"] in collected):
			return m
	return {}


static func get_by_id(id: String) -> Dictionary:
	for m in MEMORIES:
		if String(m["id"]) == id:
			return m
	return {}
