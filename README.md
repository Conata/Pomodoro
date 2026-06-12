# 黒猫飯店

ネオン街の中華料理屋 × 裏のクーロンマンション。
**探索が本編、経営は閉店三行、集中（ポモドーロ）が深度になる。**

- `DESIGN.md` … 実装仕様 v4（`WORLD.md` と併読。WORLD.md は届き次第ここに置く）
- **Play（現行ビルド）:** https://conata.github.io/Pomodoro/
  — いまは同エンジンの姉妹作 **POMODORO HERO v1** が動いている。黒猫飯店の Godot 実装はこのコードベースを土台に進める
- `docs/pomodoro-hero/DESIGN.md` … 姉妹作 POMODORO HERO の設計（同エンジン・同ユニバース）
- `main.gd` / `src/` … Godot 4.3 実装
  - `src/sim/` … エンジン非依存のコアロジック（シード付きRNG・0.2秒固定ステップ・キャッチアップ）。
    黒猫飯店の dive sim / closeDay もこの形式で移植する
- `tests/test_sim.gd` … ヘッドレステスト: `godot --headless -s tests/test_sim.gd`
- `assets/third_party/` … オープンソースアセット（ライセンス台帳: `CREDITS.md`）
- `.github/workflows/deploy.yml` … main へ push で自動ビルド → GitHub Pages 公開
