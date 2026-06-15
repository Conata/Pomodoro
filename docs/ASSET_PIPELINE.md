# アセット生成 × ローカル同期 手順書

あなた（ローカルで PixAI / ComfyUI 生成）と、私（リポジトリ側の実装・配線）を
すり合わせるためのドキュメント。**「ここに、この名前で、このサイズで置けば、ゲームが自動で拾う」**を一覧化してある。

---

## 0. 役割分担と同期フロー

```
あなた(ローカル) ── 生成(PixAI/ComfyUI) → スライス(tools/*.py) → 規定パスに配置
                                                    │ git add/commit/push
                                                    ▼
リポジトリ(branch: claude/elevenlabs-game-audio-5ec655)
                                                    │ 私が pull → 必要なら配線・調整
                                                    ▼
                                         main へ merge → GitHub Pages 自動デプロイ
```

- **置くだけで動く**：下表のパス・命名に従えば、Godot 側は **自動でフォールバック付きで拾う**（無ければ手続き生成／立ち絵／シルエットに自動で落ちる）。コード変更不要。
- 渡し方は2通り：①自分でブランチに commit/push する ②ファイルを私に渡す（私が配置・commit）。
- **キャラID対応（重要）**：`ミル=mil` / `ユズキ=yuzuki` / `ムュウ=muu` / `レイカ(プレイアブル)=kiriko` / `NPCキリコ=kiriko_npc`


こちらにキャラのリファレンスがある
/Users/mekezzo/Work/Pomodoro/docs/Refs/Chara


---

## 1. ローカルでゲームを動かす

Godot **4.3** が必要（CIと同じ）。

```bash
# エディタで開く（推奨）：project.godot を開いて F5
godot --path .

# ヘッドレスで単体テスト（simの決定論テスト）
godot --headless -s tests/test_sim.gd

# 新しいアセットを置いたら一度インポート（.import を生成）
godot --headless --import

# Web書き出し（Pagesと同じ単一スレッド設定。export templatesが要る）
mkdir -p build/web
godot --headless --export-release "Web" build/web/index.html
python3 -m http.server -d build/web 8000   # http://localhost:8000 で確認
```

> 画像/音声を追加したら **`--import` を一度走らせる**と、エディタ無しでも反映される。

---

## 2. 置き場所と命名（これが「契約」）

| 種類 | パス | 形式・サイズ | 拾われ方 |
|---|---|---|---|
| **立ち絵（ポートレート）** | `assets/portraits/<id>.png` | 透過PNG・全身・縦長(目安 ~800×1700) | ステータス/会話で使用。無ければ手続きシルエット |
| **顔カメラ表情シート** | `assets/generated/face/<id>/<expr>_<state>.png` | 透過PNG・全コマ同寸 | 配信ワイプが口パク/まばたき。無ければ立ち絵頭部→キャラ色 |
| **戦闘スプライト** | `assets/generated/sprites/<id>/<anim>.png` | 横並び4コマシート・透過 | 潜行の歩行/攻撃。無ければ yuzuki→0x72 で代替 |
| **探索背景（クリーン）** | `assets/art/explore_bg.png` | 853×1844 目安・**キャラ/UIなしの街だけ** | 潜行の背景。無ければ手続き都市 |
| **店内背景** | `assets/art/home_bg.png` | 853×1844 目安 | 店ホームの主役絵 |
| **BGM** | `assets/generated/bgm_el/{store,dive,battle}.mp3` | ループmp3（wavも可） | mp3>wav>CC0 の順で自動採用 |
| **効果音** | `assets/generated/sfx/<name>.{mp3,wav}` | 短いワンショット | 同上。名前は下記12種 |

**SFX名（12種）**：`ui_confirm` `ui_denied` `ui_equip` `ui_buy` `chest_open` `sword` `damage` `slash` `enemy_death` `fire` `thunder` `teleport`

**BGMプロンプト指針**（Ace-Step 1.5）：
- `store`：深夜のlo-fiジャズ、雨、ローズピアノ、ブラシドラム、温かい中華食堂。ループ。
- `dive`：ダークアンビエント、サイバーパンクの潜降、低いサブベース、まばらなブリップ、静かな緊張。ループ。
- `battle`：緊張感のある電子パルス、ドライブ感のあるパーカッション、ネオン戦闘。ループ。

---

## 3. 顔カメラ用「表情シート」の作り方（PixAI/Qwen → スライス）

配信ワイプ（右下の顔カメラ）と会話のリップシンクに使う。**頭の位置を全コマで固定**し、口（と目）だけ変える＝位置がズレないのが命。

### 既定テンプレ（4行×4列＝16コマ）
- **行＝表情**：`neutral`（通常） / `smile`（笑顔） / `surprise`（驚き） / `calm`（伏し目・穏やか）
- **列＝口/目**：`closed`（閉口） / `half`（半開） / `open`（開口） / `blink`（目を閉じる）

> リップシンクは closed→half→open を音量で切替、まばたきは blink を一瞬差す。

### 生成のコツ（重要：一貫性が全て）
- **同一キャラ・同一構図・同一スケール**で、顔（バストアップ）を**毎セル同じ位置**に。差分は口と目だけ。
- 背景は**単色のフラット**（キャラに無い色。例 `#1a1030` の濃紫や `#00ff00`）にして、後でキーイングで抜く。
- 16コマを1発生成が難しければ、**行ごと（1×4）に分割生成**してOK（下のスライサで `--rows 1` を行ごとに回す）。
- 最低限これだけでも口パクは成立：**`neutral` の 1×4（closed/half/open/blink）**。

### スライス
```bash
pip install Pillow            # 任意: numpy scipy（背景キーイングが綺麗になる）

# フル(4×4)。背景#1a1030を抜く
python3 tools/slice_expressions.py kiriko sheet_reika.png --bg 1a1030

# 最小(neutralの1行だけ)：rows=1, exprs=neutral
python3 tools/slice_expressions.py muu muu_neutral_row.png --rows 1 --exprs neutral --bg 00ff00
```
→ `assets/generated/face/<id>/neutral_closed.png` …等が出力され、配信ワイプが自動で口パクし始める。

---

## 4. 立ち絵（ポートレート）

mil / muu / kiriko(レイカ) が未実装（今は手続きシルエット）。yuzuki / kiriko_npc は実画像あり。

- **生成**：全身・**透過背景**が理想。無理なら単色背景で出す。
- **キーイング（単色背景→透過）**：
```bash
python3 tools/key_bg.py in.png assets/portraits/muu.png --bg ffffff --tol 18
# 透過PNGならそのまま assets/portraits/<id>.png に置くだけ
```
- **色の方向性**（per-char accent）：mil=シアン / muu=ピンク〜マゼンタ / kiriko(レイカ)=紫 / yuzuki=暖色。
- 全体パレット：BG `#151515` / オレンジ `#E6A15A`(店) / ミント `#69D2B0`(集中) / 紫 `#8E6BC7`(精神世界)。

---

## 5. 戦闘スプライト（任意・GIF推奨）

潜行の歩行/攻撃。アニメGIFがあるなら既存ツールで横並びシート化：
```bash
python3 tools/gen_sprites.py kiriko walk_front.gif attack.gif
# → assets/generated/sprites/kiriko/walk_front.png / attack.png（4コマ横並び）
```
静止画しか無い場合は当面 `walk_front`（1〜数コマ）だけでも可。`attack` が無ければ歩行で代替表示される。

---

## 6. クリーンな探索背景（おすすめ最優先の1枚）

今の `explore_bg.png` は**キャラ/UI/赤✕が描き込まれた完成モック**なので、ライブ描画と二重写りになりがち。
**「キャラもUIも無い、ネオン廃墟の街だけ」**の縦長(853×1844目安)を1枚もらえれば差し替えるだけで一段綺麗になる。
- プロンプト指針：雨のサイバーパンク廃墟、紫×シアンのネオン、奥行きのある路地、人物なし、UIなし、縦構図。

---

## 7. 私が用意済みの受け口（コード側）

- **FaceCam（配信ワイプ）**：`src/ui/face_cam.gd`。表情シート→立ち絵頭部→キャラ色の順で自動フォールバック。発話中に口パク、ランダムでまばたき。TTS音声が来たら音量ピーク駆動に差し替え予定。
- **スライサ/キーイング**：`tools/slice_expressions.py` `tools/key_bg.py` `tools/gen_sprites.py`。
- **音声の自動採用**：`assets/generated/...` に mp3/wav を置けば手続き版より優先して読む（`_audio_pick` / `_sfx`）。

> TODO（私側・素材が来たら）：会話画面(talk_view)にも FaceCam を載せてリップシンク。
> TTS音声プールの再生バス追加（口パクを実音量に連動）。PixAI APIラッパ（`tools/pixai_gen.py`）は API仕様をもらえれば作る。
