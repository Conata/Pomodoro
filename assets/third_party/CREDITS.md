# サードパーティアセット クレジット

本番想定のオープンソース/フリーアセット。**Leohpaz の2パックは帰属表示が必須**
（ゲーム内の統計タブ下部とこのファイルに記載して充足）。それ以外は CC0/OFL。

| アセット | 作者 | ライセンス | 用途 | 配布元 |
|---|---|---|---|---|
| `dungeon/` Dungeon Tileset II v1.7 | 0x72 | CC0 1.0 | ヒーロー/モンスター/宝箱/小物スプライト | https://0x72.itch.io/dungeontileset-ii |
| `sfx/` Minifantasy Dungeon SFX（chest_open, sword, damage） | Leohpaz | 無料・**要クレジット** | 宝箱・攻撃・被弾SE | https://leohpaz.itch.io/minifantasy-dungeon-sfx-pack |
| `sfx/` RPG Essentials SFX Free（ui_*, slash, enemy_death, fire, thunder, teleport） | Leohpaz | 無料・**要クレジット** | UI/戦闘/魔法SE | https://leohpaz.itch.io/rpg-essentials-sfx-free |
| `sfx/` UI Audio ＋ Interface Sounds（下表の19本の素材） | Kenney | CC0 1.0 | 箱開封・拾得・経営・夜営業・遷移のSE | https://kenney.nl/assets/ui-audio ／ https://kenney.nl/assets/interface-sounds |
| `music/sketchbook_loop.ogg`（Music Loop Bundle より） | Abstraction (Tallbeard Studios) | CC0 1.0（同梱 LICENSE.txt） | BGMループ | https://tallbeard.itch.io/music-loop-bundle |
| `effects/explosion2.png` Fire Spell Effect 02 | pimen | 無料（商用可・クレジット任意） | 範囲スキル/ゲート突破エフェクト | https://pimen.itch.io/fire-spell-effect-02 |
| `effects/lightning_strike.png` Thunder Spell Effect | pimen | 無料（商用可・クレジット任意） | 連鎖雷/レベルアップエフェクト | https://pimen.itch.io/thunder-spell-effect-02 |
| `effects/smoke.png` Smoke VFX 1 | pimen | 無料（商用可・クレジット任意） | 全滅/撤退エフェクト | https://pimen.itch.io/smoke-vfx-1 |
| `overlays/raylight.png` `overlays/fog.png` | Pixel-Boy / AAA（Ninja Adventure Asset Pack） | CC0 1.0 | 光芒・霧のアトモスフィア | https://github.com/pixel-boy/NinjaAdventure |
| `kenney_naturekit/` Nature Kit 2.1（GLTF 329モデル） | Kenney | CC0 1.0（同梱 License.txt） | HD-2D 探索画面の木/柵/岩/茂み/花/石畳 | https://kenney.nl/assets/nature-kit |
| `cyberpunk_kit/` Cyberpunk Game Kit（GLTF・Platforms 52モデル） | Quaternius | CC0 1.0（同梱 License.txt） | HD-2D サイバーパンク（黒猫飯店）のビル/看板/街灯/AC/アンテナ/TV/パイプ | https://quaternius.com/packs/cyberpunkgamekit.html |
| `../fonts/DotGothic16-Regular.ttf` | Fontworks | SIL OFL 1.1（同梱 OFL.txt） | UIフォント（日本語） | https://fonts.google.com/specimen/DotGothic16 |

## 加工メモ

- SFX は容量削減のため 24bit/44.1kHz ステレオ → 16bit/22.05kHz モノラルに変換済み
- スプライトは原版のまま（16px グリッド、`frames/` は1枚ずつの連番アニメ）

## 新しいアセットを足すときのルール

1. ライセンスを必ず確認（CC0 / OFL / CC-BY を推奨。CC-BY なら帰属表示を追加）
2. この表に1行追加し、帰属が必要ならゲーム内クレジット（main.gd の統計タブ）にも追加
3. ライセンス文書が同梱されている場合はファイルごとコピーする


## Kenney SFX の取り込み内訳（2026-07-28）

`tools/import_kenney_sfx.py` で取り込んだ19本。**どの音がどの素材から来たか**を残す
（手で置くと半年後に出どころが分からなくなるため、スクリプトで再現できるようにしてある）。

取得元は Kenney の CC0 パックを Godot 向けに wav 化したミラー：
- https://github.com/Calinou/kenney-ui-audio
- https://github.com/Calinou/kenney-interface-sounds

選定は波形の実測（長さ・ピーク・ゼロ交差率＝明るさ）に基づく。たとえば `bong_001` は
ZCR 0.2 で最も暗く重いので格の高い箱の芯に、`glass_004` は 0.71秒 ZCR 14.6 で最も
明るく長いので、その上に散らす飾りに使っている。複数指定は重ねて1本にしている（CC0なので加工可）。

| 出力 | 元素材 | 用途 |
| --- | --- | --- |
| `box_wood` | drop_001 | 箱開封・木 |
| `box_iron` | confirmation_001 | 箱開封・鉄 |
| `box_silver` | glass_002 ＋ confirmation_001 | 箱開封・銀 |
| `box_gold` | bong_001 ＋ glass_004 | 箱開封・金 |
| `boss_appear` | bong_001 ＋ glitch_001 | ボス出現 |
| `wipe_out` | error_002 | 全滅・緊急再同期 |
| `pickup` | pluck_001 | 装備の発見 |
| `memory_get` | glass_004 | 記憶のかけら |
| `renov_unlock` | confirmation_002 | 改装の解放 |
| `craft_great` | confirmation_002 ＋ glass_004 | 工房の大成功 |
| `daily_done` | confirmation_003 | デイリー達成 |
| `streak_up` | pluck_002 ＋ pluck_001 | 連続完走の更新 |
| `serve_dish` | drop_002 | 配膳（皿を置く） |
| `guest_leave` | back_002 | 客が帰る |
| `ticket` | tick_001 | 伝票が埋まる |
| `night_close` | close_002 | 夜営業の締め |
| `focus_start` | switch_001 | 「集中する」を押す |
| `sheet_open` | open_002 | シートを開く |
| `talk_next` | select_002 | 会話を送る |

変換は既存ルールどおり 16bit / 22.05kHz / モノラル、ピーク 0.92 に正規化。
実測でクリップ 0.00%、規格外 0件。
