class_name SimRNG
extends RefCounted
## シード付き決定論RNG（mulberry32移植）。
## DESIGN.md「乱数はシード付きRNGに置換し、将来のサーバー権威抽選に備える」に対応。
## state を保存・復元すれば乱数列が完全に再現できる。
## 注意: randf/randi はグローバル関数と同名のため、クラス内部では相互に
## 呼ばず必ず next_u32() から直接導出する（グローバル側に解決されて
## 決定論が壊れる事故を防ぐ）。

var state: int = 1


func _init(seed_value: int = 1) -> void:
	state = seed_value & 0xFFFFFFFF


func next_u32() -> int:
	state = (state + 0x6D2B79F5) & 0xFFFFFFFF
	var t: int = state
	t = ((t ^ (t >> 15)) * ((t | 1) & 0xFFFFFFFF)) & 0xFFFFFFFF
	t = t ^ ((t + (((t ^ (t >> 7)) * ((t | 61) & 0xFFFFFFFF)) & 0xFFFFFFFF)) & 0xFFFFFFFF)
	return (t ^ (t >> 14)) & 0xFFFFFFFF


## [0.0, 1.0) の一様乱数。
func randf() -> float:
	return float(next_u32()) / 4294967296.0


## [0, n) の整数。
func randi(n: int) -> int:
	if n <= 0:
		return 0
	return next_u32() % n


## [a, b] の整数（両端含む）。
func randi_range(a: int, b: int) -> int:
	if b <= a:
		return a
	return a + next_u32() % (b - a + 1)


## [a, b) の実数。
func randf_range(a: float, b: float) -> float:
	return a + (float(next_u32()) / 4294967296.0) * (b - a)


## 確率 p で true。
func chance(p: float) -> bool:
	return float(next_u32()) / 4294967296.0 < p


## 配列からランダムに1要素。
func pick(arr: Array) -> Variant:
	return arr[next_u32() % arr.size()]
