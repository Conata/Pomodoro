class_name EventData
extends RefCounted
## イベント／チュートリアルのシーン集。会話(TalkData)と同じ再生器(TalkView)で動く。
## 足すのはここに1エントリ：
##   "id": {"speaker": 立ち絵キャラid, "title": 見出し, "lines": [[who,text]...],
##          任意 "a"/"b" で2択, 任意 "once": true で一度だけ}
## 発火は main の _maybe_event() が state["events_seen"] を見て出す。
## WORLD.md の文体（説明しすぎない・キャラの声）を守ること。

const EVENTS := {
	"tutorial": {
		"speaker": "mil", "title": "はじめに", "once": true,
		"lines": [
			["g", "店長。同期の準備ができました"],
			["g", "朝、潜る三人と、店番の一人を決めます"],
			["g", "店番に残した子が、その夜の店を決めます。事実です"],
			["g", "集中したい時間を選んで、潜る。現実の集中が、深度になります"],
			["g", "浮上したら、夜の三行。獲ってきた素材が、出せる料理を決めます"],
			["*", "換気扇の音。雨。"],
			["g", "…難しく考えなくて大丈夫。まず、一度潜ってみましょう"],
		],
	},
	# 例：初浮上後のひとこと（足すならここに1行）
	"first_surface": {
		"speaker": "yuzuki", "title": "おかえり", "once": true,
		"lines": [
			["g", "おう、おかえり。無事でなにより"],
			["g", "獲ってきたやつで、今夜の品書きが決まる。…腹減ったろ？"],
		],
	},
}
