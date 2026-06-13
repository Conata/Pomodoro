# 追加・調整ガイド（メンテ用）

「あとから足す／いじる」を最小手数にするための地図。データ駆動を徹底しているので、
多くは **1ファイルに1エントリ** で済む。変更後は必ず:

    godot --headless -s tests/test_sim.gd      # 70チェック
    godot --headless -s tools/balance_report.gd # 経済カーブ

## エフェクトを足す
1. 横並びスプライトシート（PNG）を `assets/` に置く（または `tools/gen_*.py` で生成）
2. `src/sim/fx_data.gd` の `FX` に1行：
   `"名前": {"file": パス, "size": 1コマpx, "frames": 枚数, "fps": 速さ, "side": "enemy"/"party"}`
3. 以降 `名前` で呼べる。DiveView も main も自動で対応（描画も出す側も FxData 準拠）

## 技（スキル）を足す
`src/sim/data.gd` の `SKILL_DB` に1行だけ：
```
"id": {"girl": キャラ, "name": 表示名, "unlock": 0|1|2, "cd": 秒,
       "kind": "hit"/"aoe"/"heal_one"/"heal_all"/"shield_all", "power": 係数,
       "fx": "FxData名"（任意）}
```
効果は `kind`、見た目は `fx` で完結（`sim._cast_skill` がデータから自動処理）。
`unlock` は好感度 0/45/80 で習得。

## キャラを足す
1. `KuroData.GIRLS` に1人（color/role/fav/hp/atk/keeper_apt/synergy/sprite）
2. `KuroData.GIRL_ORDER` に id 追加（隊列順）
3. `SKILL_DB` にそのキャラの技を数本
4. 立ち絵：`assets/portraits/<id>.png`（無ければ Portrait が色シルエットで代替）
5. 掛け合い：`Banter.LINES[<id>]`、会話：`TalkData.TALKS[<id>]`（3シーン）

## 探索中のセリフ（掛け合い）を足す
- 独り言・反応 → `src/sim/banter.gd` の `LINES[キャラ][状況]` に "セリフ" を1行。
  状況は start/idle/combat/boss/loot/levelup/gate/wipe/door。
  idle が「放置で愛着が湧く」核心なので多めに。
- 二人の応酬 → 同ファイル `EXCHANGES` に
  `{"lines": [["キャラ","…"],["相手","…"], ...]}` を1要素。話者が全員潜行中の時だけ、
  平時に約4割の確率で発生し、bubble が順に流れる。

## イベント／チュートリアルを足す
1. `src/sim/event_data.gd` の `EVENTS` に1エントリ（speaker/title/lines、任意で a/b 2択）
2. 出すタイミングは `main._maybe_event("id")` を呼ぶ場所を足すだけ。
   既読は `state["events_seen"]` で自動管理（`once` 相当）。
   再生器は会話と共通（TalkView）。文体は WORLD.md に従う。

## ボタンの手触り
`_button()` 生成のボタンは自動で押下アニメ（`_juice`）が付く。
`Button.new()` を直接作る箇所は `_juice(b)` を通せば同じ手触りになる。

## バランス調整
- 主要ノブの所在:
  - 出現/速度/深度: `KuroData`（`DIVE_SPEED` `ENC_MIN/MAX` `depth_scale`）
  - 戦利品の量: `sim._on_mob_killed`（ゴールド/素材/箱）
  - 夜の売上: `sim.close_day`（客数=8+看板、味マッチ単価1.2、店番シナジー）
  - 価格/星上げ: `KuroData.recipe_price`、闇市 `KuroData.MARKET`
- 手順：ノブを1つ変える → `tools/balance_report.gd` を回す → 25分/7日の傾きを見る。
- 現状メモ（2026-06 計測）：25分=+約4900G、7日=約20万G。DESIGN.md の旧目標
  （25分+1339G/7日5000G）から大きく上振れ。エンカウント高頻度化の影響。
  **最終は実機の体感で決める**（DESIGN.md）。
