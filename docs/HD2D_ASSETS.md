# HD-2D フリー素材カタログ（環境・地形・エフェクト）

HD-2D 探索画面の背景/地形を**自作せず**、ライセンスが明確な無料素材で組むための調達リスト。
方針の背景は `docs/HD2D_DESIGN.md`、実装は `docs/HD2D.md`。

> **Godot の強み**：glTF / GLB を**ネイティブ取り込み**できる（Unity のようにプラグイン不要）。
> note 記事が Unity で苦労した「glTF のテクスチャ紐付け／インポート」は、Godot ではほぼ素直に通る。
> 取り込んだメッシュのマテリアルで `Texture Filter = Nearest` にすると、HD-2D の“荒いテクスチャ”感が出る。

---

## 1. 環境・フィールド（voxel / ローポリ）

### 最優先：CC0（クレジット不要・商用可）

| 提供元 | パック例 | 形式 | ライセンス | 用途 |
|---|---|---|---|---|
| **Kenney** | [Nature Kit](https://kenney.nl/assets/nature-kit)（**導入済**）/ [Voxel Pack](https://kenney.nl/assets/voxel-pack) / [City Kit (Suburban)](https://kenney.nl/assets/city-kit-suburban) / [Castle Kit](https://kenney.nl/assets/castle-kit) | glTF/FBX/OBJ | **CC0** | 木・建物・塀・道など中庭〜街の構成 |

> **✅ Nature Kit 導入済み**：`assets/third_party/kenney_naturekit/`（GLTF 形式 329 モデル＋License.txt、CC0）。
> HD-2D プロトタイプ（`hd2d_view.gd` の `_build_props()`）で木・柵・岩・茂み・花・石畳を配置済み。
> 1 タイル = 1 ユニット設計・足元 y=0。木は約 1.7 ユニット高なので `scale 2.5` 前後でキャラを見下ろす高さになる。
| **Quaternius** | [Ultimate Nature Pack](https://quaternius.com/packs/ultimatenature.html) / [Ultimate Stylized Nature Pack](https://quaternius.com/packs/ultimatestylizednature.html) | glTF/FBX/OBJ/Blend | **CC0** | スタイライズな木・岩・草。HD-2D 背景向き |
| **Kenney（全部入り）** | [Game Assets All-in-1](https://kenney.nl/data/itch/preview/) | 各種 | **CC0** | まとめて入手したい場合 |

- Kenney は 30,000+ 点がすべて CC0。`Nature Kit` は HD-2D の中庭/森に直結。
- Quaternius の `Ultimate Stylized Nature` は法線マップ付きでオクトラ系の柔らかい質感。

### 集約サイト（モデル毎にライセンス確認）

| サイト | 内容 | ライセンス | 注意 |
|---|---|---|---|
| **[Poly Pizza](https://poly.pizza/)** | ローポリ集約・ログイン不要 DL | CC0 と CC-BY が**混在** | 各モデル表示の CC0/CC-BY を確認。CC-BY はクレジット必須 |
| **[Sketchfab（CC0 フィルタ）](https://sketchfab.com/tags/magicavoxel)** | voxel 製ジオラマ・街 | **モデル毎**（CC0/CC-BY/不可あり） | DL 可否とライセンスを必ず個別確認。note 記事が参照した供給源 |
| **[OpenGameArt](https://opengameart.org/)** | 2D/3D 全般 | CC0/CC-BY/GPL 等 | ライセンス欄を必ず確認 |

> **Sketchfab の注意**：millions のモデルがあるがライセンスはモデル単位。
> 「Downloadable」かつ「CC0 もしくは商用可な CC-BY」だけを使い、CC-BY はクレジットを残す。

---

## 2. voxel を自作したくなった場合のツール

| ツール | 役割 | 備考 |
|---|---|---|
| **[MagicaVoxel](https://ephtracy.github.io/)** | voxel モデリング＋荒テクスチャ | 無料。.vox 出力。**glTF 直接出力は不可**（OBJ/PLY 経由） |
| **[Blockbench](https://www.blockbench.net/)** | ブラウザ動作・**glTF/GLB 直接出力** | MagicaVoxel→OBJ→Blockbench→glTF で Godot に渡せる |

記事の知見：voxel フィールド × 荒テクスチャ × 明るい照明・強コントラスト × 奥行きで、
オクトラ風は十分に再現できる（高精細自作モデルは不要）。

---

## 3. エフェクト・空気感（パーティクル等は素材で）

自前のパーティクル実装はせず、テクスチャ/スプライト素材で足す方針。

| 種類 | 探し先 | 例 | ライセンス |
|---|---|---|---|
| 舞う花びら・埃・ホタル | Kenney [Particle Pack](https://kenney.nl/assets/particle-pack) | 煙/光/粒テクスチャ | **CC0** |
| 光芒・グロー・フレア | OpenGameArt「light ray / god ray」 | 加算用オーバーレイ | CC0/CC-BY 要確認 |
| 既存流用 | 本リポジトリ `assets/third_party/overlays/raylight.png` | 既に dive_view で使用中 | （取得元のライセンス踏襲） |

> 本作の GL Compatibility では DOF が出ない代わりに、**光芒/粒の素材を加算ビルボードで重ねる**と空気感を補える。

---

## 4. ライセンス運用（重要）

- **CC0**：クレジット不要・商用可。最優先で選ぶ。
- **CC-BY**：商用可だが**クレジット必須**。使うなら作者名・出典・ライセンスを `CREDITS` に記載。
- **CC-BY-SA / GPL / NC**：それぞれ継承・非商用などの制約。**配布形態と合うか要確認**（NC は商用不可）。
- 本リポジトリは既に CC0 素材（0x72 DungeonTileset 等）を使用。新規もこの基準（CC0 優先）に揃える。
- 取り込んだ素材は提供元・ライセンス・URL を `docs/` か `CREDITS` 系ファイルに必ず控える。

---

## 5. 取り込み手順（Godot 4.6）

1. glTF/GLB を `assets/third_party/<pack名>/` に配置（ライセンス文も同梱）。
2. インポート後、メッシュのマテリアルで **Texture Filter = Nearest**（荒テクスチャ感）。
3. HD-2D シーン（`hd2d_view.gd`）のプレースホルダ地面/ボックスを、取り込んだメッシュに置換。
4. ライト強度・コントラスト・glow を調整して質感を詰める（`docs/HD2D_DESIGN.md` §2.3–2.5）。

---

## 6. まず試すおすすめ（最短ルート）

1. **Kenney [Nature Kit](https://kenney.nl/assets/nature-kit)（CC0）** をDLし、木・塀・地面ブロックを配置 → 中庭を構成。
2. 物足りなければ **Quaternius [Ultimate Stylized Nature](https://quaternius.com/packs/ultimatestylizednature.html)（CC0）** を追加。
3. 雰囲気を詰める素材として **Kenney [Particle Pack](https://kenney.nl/assets/particle-pack)（CC0）** の光/粒。

いずれも CC0 なのでクレジット不要・商用可で、Godot に glTF でそのまま入る。
