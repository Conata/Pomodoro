# Godot → GitHub Pages スマホ開発パイプライン

push するたびに Web ビルドが自動生成され、GitHub Pages に公開される。
スマホのブラウザで URL を開けば常に最新ビルドが実機テストできる。

## 初回セットアップ（5分・スマホのGitHubアプリ/ブラウザでも可）

1. GitHub で新規リポジトリ作成（public 推奨。private は Pages が有料プラン要）
2. このフォルダの中身を丸ごと push（main ブランチ）
3. リポジトリの **Settings → Pages → Source を「GitHub Actions」に変更**
4. Actions タブでビルド完了（緑✓）を待つ（初回 約2〜3分）
5. `https://<ユーザー名>.github.io/<リポジトリ名>/` を開く
   → 「黒猫飯店 — pipeline OK」とタップカウンタが出れば開通

## 日常の開発ループ（携帯のみ）

- Claude にコード/シーンを書かせる → Claude Code またはGitHub Web編集で main に push
- 2〜3分後、同じURLをリロード → 実機で最新版をプレイ
- フィードバックを Claude へ → 繰り返し

## 技術メモ

- Web書き出しは **thread_support=false（シングルスレッド）**。
  GitHub Pages は COOP/COEP ヘッダを設定できないため、4.3 の
  非スレッドエクスポートで SharedArrayBuffer 要件を回避している。
  （音の遅延が気になったら itch.io 配信 or coi-serviceworker 導入で
  スレッド有効化に切り替え可能）
- レンダラは GL Compatibility（Web/モバイルの推奨）
- ビルドイメージ: barichello/godot-ci:4.3（エクスポートテンプレート同梱）
- Godot のバージョンを上げる時は deploy.yml のイメージタグと
  project.godot の features を揃えて変更すること
