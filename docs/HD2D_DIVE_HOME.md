# HD-2D 適用設計：潜航シーン & ホーム画面

HD-2D プロトタイプ（`src/ui/hd2d_view.gd`）の手法を、本編の **潜航（ダイブ）** と **ホーム（店）** に
適用する場合の設計と仕様。前提・素材は `docs/HD2D.md` / `docs/HD2D_ASSETS.md` を参照。

## 0. 大原則

- **KuroSim が唯一の真実（決定論）**。3D 化はすべて**表示層だけ**。sim の状態を読むのみで、
  presentation から sim へは書き込まない（既存テスト `tests/test_sim.gd` を壊さない）。
- 現状の `dive_view.gd`（2D `_draw`）/ ホーム（`main.gd` 内）は **public API を保ったまま差し替える**。
  → `main.gd` への影響を最小化し、A/B（2D版へフォールバック）を残せる。
- レンダラは **Mobile**（DOF/glow が出る）に切替済み。Web 配信は WebGPU 前提になる点は別途判断。

## 1. 共通基盤：`Hd2dStage`（リファクタで抽出）

`hd2d_view.gd` に詰まっている再利用部品を 1 つのクラス／シーンに切り出し、ダイブ・ホーム・探索が共有する。

| 部品 | 現状の関数 | 役割 |
|---|---|---|
| SubViewport 3D ワールド | `_build_viewport` | 3D を Control 内に内包（既存 UI と共存） |
| ビルボード生成 | `_make_billboard` | Y固定ビルボード＋shaded＋アルファスシザー |
| アニメ駆動 | `ChibiAnim` | run/attack/hurt/die 等のステート |
| 環境/ライティング | `_build_env_cyberpunk/_nature` | テーマ別プリセット |
| ブロブ影 | `_add_blob_shadow` | 接地影（追従） |
| 粒子 | `_build_particles` | 空気の粒子感 |
| モデルローダ | `_add_gltf` / `_make_glow` / `_make_wet` | キット配置・発光・濡れ質感 |
| カメラ | `_update_camera` | 周回／追従／ズーム／シェイク |
| ヴィネット / DOF | `_build_vignette` / CameraAttributes | 仕上げ |

`Hd2dStage` の最低 API（案）:
```
add_actor(id) -> Billboard         # キャラ追加（ChibiAnim 付き）
set_actor(id, pos, anim_params, flip)
add_prop(path, xform, glow, wet)   # キット配置
set_env(preset)                    # 朝/夜/biome 等のライティング
camera_follow(target, mode)        # track/orbit/zoom
project_to_screen(world_pos)       # 吹き出し・ダメージ数字の 2D 配置用
raycast_actor(screen_pos)          # タップ判定
```

---

## 2. 潜航シーン（`DiveView3D`）

### 2.1 設計方針
- 世界観「電脳深層」＝サイバーパンク。**Cyberpunk Game Kit がそのまま地形に使える**（テーマ一致）。
- 既存 `DiveView` の public API（`sim`, `say()`, `spawn_damage(at)`, `spawn_fx(kind, at)`, `remaining`）を**そのまま実装**。
  `main.gd` は生成するクラスを差し替えるだけ。

### 2.2 ワールド構成
- **3D コリドー（廊下）**を `sim.state["dist"]` に応じてスクロール／前進。
  床・壁はキット（Platform / Sign / Pipe / Light）を **MultiMesh でタイル化**し、無限スクロール風に再配置。
- **biome 差し替え**：`KuroData.BIOMES`（フロアごとの色）→ 3D 環境プリセット
  `{ネオン色, フォグ, 小物セット, 床マテリアル}` のテーブルにマップ。深層が進むほど色・密度を変える。
- パーティ＝左クラスタのビルボード（`run/attack/hurt/die`）。敵＝前方から接近するビルボード。

### 2.3 戦闘演出（既存ロジックは不変）
- `sim.state["in_combat"]` で**カメラ寄り＋突進ランジ**（既存 `_cam_zoom` / lunge を 3D の Z/X に移植）。
- `spawn_damage()` → ダメージ数字は `project_to_screen()` で頭上に 2D 描画（or `Label3D`）。
- `spawn_fx("explosion"/"lightning")` → ビルボード quad アニメ or `CPUParticles3D`。
- ボス（`m["boss"]`）→ 大型ビルボード＋**スクリーン HP バー**＋赤縁（既存 `_draw_boss_stage` 相当を 2D チロー側に）。

### 2.4 UI チロー（`DiveChrome`）は 2D のまま
- 配信 UI（集中タイマー、HP バー、掛け合いログ、扉カード、ダメージ数字、雨）は
  **2D Control オーバーレイ**として SubViewport の上に重ねる。**3D＝世界 / 2D＝UI** の分離。
- 吹き出し（`say`）＝頭上に `project_to_screen` で 2D 配置（既存 `_draw_bubble` 流用）。

### 2.5 既存要素の対応
| 既存（2D dive_view） | HD-2D 版 |
|---|---|
| 視差スクロール背景 | 3D コリドー（実深度）＋フォグ |
| 地面プラットフォーム | キット床タイル（MultiMesh） |
| 扉／イベントカード | 3D ゲート or 2D カード継続 |
| ゴールオーブ | 3D 発光オーブ（終端） |
| 雨 | 2D オーバーレイ or 3D 粒子 |
| 赤い✕の渦 | 3D 発光デカール or 2D 継続 |

---

## 3. ホーム画面（`HomeView3D`）

### 3.1 設計方針
- 「黒猫飯店」の**店内/店先を 3D ジオラマ化**。固定〜ゆる周回カメラで店を映す（オクトラの町画面風）。
- 管理 UI（5 タブ、編成/箱/経営/改装ボタン、日数/ゴールド、会話吹き出し）は
  **2D Control オーバーレイのまま**。3D＝店の絵 / 2D＝操作 UI。

### 3.2 ワールド構成
- 店ジオラマ：サイバーパンクキット＋**中華要素**（提灯／暖簾／ネオン「黒猫飯店」）。
  カウンター・席・厨房をキット＋小物で構成。
- キャラ＝店番ビルボード（`idle/eat/talk`）。**営業ライブ**＝客ビルボードが来店し配膳する演出を
  `sim` の営業状態（売上/客入り）に連動。

### 3.3 インタラクション（既存導線を維持）
- キャラタップ → `raycast_actor(screen_pos)` でヒット → **会話（TalkView）/ 詳細（portrait）** を開く。
  既存の顔タップ起点（`home_face_cams` / `home_char_badges`）をレイキャストに置換。

### 3.4 時間帯ライティング
- `sim` の朝/昼/夜/精算フェーズで環境ライティングを切替（朝＝暖色、夜＝ネオン）。
  `_build_env_*` のプリセットを時間帯テーブル化して流用。

### 3.5 顔システムとの両立
- 現状ホームは `FaceCam`（口パク顔）。HD-2D 化後は **シーン内＝チビビルボード／タップ時＝顔ポートレート・会話**。
  顔システムは会話・キャラ詳細モーダルで**継続使用**（捨てない）。

---

## 4. 段階導入計画

1. **`Hd2dStage` 抽出**：`hd2d_view.gd` から共通部品を切り出す（破壊が無く、まず安全）。
2. **`HomeView3D`**：影響が局所でコアループを温存。まず店ジオラマ＋キャラ配置＋タップ導線。
3. **`DiveView3D`**：戦闘演出を移植。public API 維持で `main.gd` 差し替えのみ。2D 版をフォールバックに残す。
4. **最適化**：床/壁 MultiMesh、ライト数の集約（Mobile はライト上限あり）、SubViewport 解像度、粒子上限。
5. **Web 方針の決着**：Mobile＝WebGPU か、Web 用に別 Compatibility ビルドか。

## 5. リスク・留意点

- **パフォーマンス**：Mobile レンダラはライト数に上限。ネオンは「**emission＋少数の集約 OmniLight**」か
  ベイクで賄う。床/壁は MultiMesh、敵/味方はビルボードで軽い。
- **決定論**：sim は不変。3D は読むだけ（テスト維持）。
- **スコープ**：ダイブは演出要素（fx/boss/door/log/雨）が多い。**表示層だけ差し替え、ロジックは触らない**。
- **Web**：Mobile 化で WebGPU 前提（既出の判断待ち）。Web を残すなら HD-2D 画面のみ別ビルド等。
