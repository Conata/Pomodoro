# 黒猫飯店

ネオン街の中華料理屋 × 裏のクーロンマンション。
**探索が本編、経営は閉店三行、集中（ポモドーロ）が深度になる。**

- **Play:** https://conata.github.io/Pomodoro/ （main へ push で自動ビルド→公開）
- `DESIGN.md` … 実装仕様 v4 ／ `WORLD.md` … 世界観の憲法（併読）
- `docs/pomodoro-hero/DESIGN.md` … 姉妹作 POMODORO HERO の設計（同エンジン・同ユニバース）
- `main.gd` / `src/` … Godot 4.3 実装
  - `src/sim/` … エンジン非依存のコアロジック（dive sim / closeDay / 箱 / 会話。
    シード付きRNG・0.2秒固定ステップ・キャッチアップ）
  - `src/ui/` … 潜行ビュー・会話シーン（Rain98系：青のモノクローム×雨×斜めバンド）
- `tests/test_sim.gd` … ヘッドレステスト: `godot --headless -s tests/test_sim.gd`
- `assets/third_party/` … オープンソースアセット（ライセンス台帳: `CREDITS.md`）
- `.github/workflows/deploy.yml` … main へ push で自動ビルド → GitHub Pages 公開
