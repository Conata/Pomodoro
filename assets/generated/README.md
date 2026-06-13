# 手続き生成アセット（ピクセルアート）

`tools/gen_assets.py` / `tools/gen_bg.py`（Pillow）で生成。再生成は:

    python3 tools/gen_assets.py    # 料理・箱・素材
    python3 tools/gen_bg.py        # 視差背景

- `food/<id>.png` … 料理12種（献立チップ・精算で使用）
- `box/<0-3>.png` … 箱4グレード（木/鉄/銀/金）
- `ing/<dry|meat|sea>.png` … 素材3種（乾物/肉/海鮮）
- `bg/city_far.png` `bg/city_mid.png` … 電脳深層の視差スカイライン
- `bg/interior.png` … 黒猫飯店の店内（暖色・窓の外は冷ネオン）。店先バナー背景
- `fx/heal.png` … 回復エフェクト（緑の輪＋上昇スパーク）
- `bgm/dive_drone.wav` `bgm/battle_layer.wav` … 手続き生成BGM
  （潜行ドローン＋戦闘レイヤー、Pythonのwaveで合成）。店テーマ⇄潜行を
  フェーズでクロスフェード、戦闘中は戦闘レイヤーを重ねる

料理/箱/素材は 32px ネイティブ。Godot 側は nearest 拡大でドット感を保つ。
キャラ立ち絵（フユキ等）は AI 生成で assets/portraits/ へ（別系統）。
