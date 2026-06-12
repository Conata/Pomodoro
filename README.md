# Pomodoro

POMODORO HERO — ポモドーロ×放置ハクスラ。

- **Play (Godot Web版):** https://conata.github.io/Pomodoro/
- `DESIGN.md` … 設計仕様書（移植時に壊してはいけない構造はここ）
- `main.gd` / `src/` … Godot 4.3 実装（開発中）
  - `src/sim/` … エンジン非依存のコアロジック（決定論シミュレーション）
  - `src/ui/` … 潜行ビュー・ルーンツリー描画
- `tests/test_sim.gd` … ヘッドレステスト: `godot --headless -s tests/test_sim.gd`
- `.github/workflows/deploy.yml` … main へ push で自動ビルド → GitHub Pages 公開
  （Settings → Pages → Source が「GitHub Actions」になっていること）
