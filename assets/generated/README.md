# 手続き生成アセット（ピクセルアート）

`tools/gen_assets.py`（Pillow）で生成。再生成は:

    python3 tools/gen_assets.py

- `food/<id>.png` … 料理12種（献立チップ・精算で使用）
- `box/<0-3>.png` … 箱4グレード（木/鉄/銀/金）
- `ing/<dry|meat|sea>.png` … 素材3種（乾物/肉/海鮮）

すべて 32px ネイティブ。Godot 側は nearest 拡大でドット感を保つ。
キャラ立ち絵（フユキ等）は AI 生成で assets/portraits/ へ（別系統）。
