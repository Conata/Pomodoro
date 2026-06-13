class_name FxData
extends RefCounted
## エフェクトの一元レジストリ。エフェクトを足すのはここに1行＋PNGだけ。
##   "名前": {"file": 画像パス, "size": 1フレーム正方px, "frames": 枚数, "fps": 速さ, "side": "enemy"/"party"}
## DiveView はこの表だけを見て描画する。スキルは SKILL_DB の "fx" で名前を指すだけ。
##
## 追加手順:
##   1) スプライトシート（横並び）を assets/ に置く（または gen_*.py で生成）
##   2) ここに1行足す
##   3) スキルや sim から emit_fx 名で呼ぶ／SKILL_DB に "fx":"名前" を書く

const FX := {
	"explosion": {"file": "res://assets/third_party/effects/explosion2.png", "size": 50, "frames": 18, "fps": 24.0, "side": "enemy"},
	"lightning": {"file": "res://assets/third_party/effects/lightning_strike.png", "size": 66, "frames": 13, "fps": 22.0, "side": "enemy"},
	"smoke": {"file": "res://assets/third_party/effects/smoke.png", "size": 64, "frames": 13, "fps": 14.0, "side": "party"},
	"heal": {"file": "res://assets/generated/fx/heal.png", "size": 48, "frames": 10, "fps": 18.0, "side": "party"},
}


static func has(name: String) -> bool:
	return FX.has(name)


static func side_of(name: String) -> String:
	return String(FX.get(name, {}).get("side", "enemy"))
