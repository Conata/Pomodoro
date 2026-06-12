# サードパーティアセット クレジット

本番想定のオープンソース/フリーアセット。**Leohpaz の2パックは帰属表示が必須**
（ゲーム内の統計タブ下部とこのファイルに記載して充足）。それ以外は CC0/OFL。

| アセット | 作者 | ライセンス | 用途 | 配布元 |
|---|---|---|---|---|
| `dungeon/` Dungeon Tileset II v1.7 | 0x72 | CC0 1.0 | ヒーロー/モンスター/宝箱/小物スプライト | https://0x72.itch.io/dungeontileset-ii |
| `sfx/` Minifantasy Dungeon SFX（chest_open, sword, damage） | Leohpaz | 無料・**要クレジット** | 宝箱・攻撃・被弾SE | https://leohpaz.itch.io/minifantasy-dungeon-sfx-pack |
| `sfx/` RPG Essentials SFX Free（ui_*, slash, enemy_death, fire, thunder, teleport） | Leohpaz | 無料・**要クレジット** | UI/戦闘/魔法SE | https://leohpaz.itch.io/rpg-essentials-sfx-free |
| `music/sketchbook_loop.ogg`（Music Loop Bundle より） | Abstraction (Tallbeard Studios) | CC0 1.0（同梱 LICENSE.txt） | BGMループ | https://tallbeard.itch.io/music-loop-bundle |
| `effects/explosion2.png` Fire Spell Effect 02 | pimen | 無料（商用可・クレジット任意） | 範囲スキル/ゲート突破エフェクト | https://pimen.itch.io/fire-spell-effect-02 |
| `effects/lightning_strike.png` Thunder Spell Effect | pimen | 無料（商用可・クレジット任意） | 連鎖雷/レベルアップエフェクト | https://pimen.itch.io/thunder-spell-effect-02 |
| `effects/smoke.png` Smoke VFX 1 | pimen | 無料（商用可・クレジット任意） | 全滅/撤退エフェクト | https://pimen.itch.io/smoke-vfx-1 |
| `../fonts/DotGothic16-Regular.ttf` | Fontworks | SIL OFL 1.1（同梱 OFL.txt） | UIフォント（日本語） | https://fonts.google.com/specimen/DotGothic16 |

## 加工メモ

- SFX は容量削減のため 24bit/44.1kHz ステレオ → 16bit/22.05kHz モノラルに変換済み
- スプライトは原版のまま（16px グリッド、`frames/` は1枚ずつの連番アニメ）

## 新しいアセットを足すときのルール

1. ライセンスを必ず確認（CC0 / OFL / CC-BY を推奨。CC-BY なら帰属表示を追加）
2. この表に1行追加し、帰属が必要ならゲーム内クレジット（main.gd の統計タブ）にも追加
3. ライセンス文書が同梱されている場合はファイルごとコピーする
