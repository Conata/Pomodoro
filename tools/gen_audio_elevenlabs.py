#!/usr/bin/env python3
"""ElevenLabs で BGM/SE を生成して assets/ に配置する。

この実行環境は api.elevenlabs.io への egress が塞がれているため、Claude は
ここから叩けない。ネットワークが通る場所（手元 or egress許可後）で実行する：

    export ELEVENLABS_API_KEY=sk_xxx        # キーは環境変数で（コミット禁止）
    python3 tools/gen_audio_elevenlabs.py    # SEのみ
    python3 tools/gen_audio_elevenlabs.py --music   # BGMも（Music APIが要る）

出力：
    assets/generated/sfx/<name>.mp3   … ゲームが自動で優先ロード（無ければ現wav）
    assets/generated/bgm_el/<name>.mp3 … 同上（無ければ現在の手続きBGM）

生成後は Godot でインポート（エディタを開く or CI ビルド）すれば反映。
"""
import os, sys, json, urllib.request, urllib.error

KEY = os.environ.get("ELEVENLABS_API_KEY", "").strip()
ROOT = os.path.join(os.path.dirname(__file__), "..", "assets", "generated")
BASE = "https://api.elevenlabs.io/v1"

# ゲームの _sfx 名に対応（assets/generated/sfx/<name>.mp3）。プロンプトは
# ネオン中華＋電脳のトーン。duration は短く、prompt_influence 高めで素材寄りに。
SFX = {
    "ui_confirm":   ("soft warm UI confirm chime, single short blip, cozy", 0.5),
    "ui_denied":    ("muted UI error tick, soft negative, short", 0.5),
    "ui_equip":     ("light gear equip click, cloth and metal, short", 0.5),
    "ui_buy":       ("small cash register coin clink, pleasant, short", 0.6),
    "chest_open":   ("wooden chest creak open with a soft sparkle, short", 1.0),
    "sword":        ("quick kitchen cleaver swoosh, light metallic, short", 0.5),
    "damage":       ("soft body hit thud, muffled, short", 0.5),
    "slash":        ("sharp blade slash whoosh, short", 0.5),
    "enemy_death":  ("digital glitch dissolve, enemy disappears, short", 0.7),
    "fire":         ("compact fire whoosh burst, short", 0.6),
    "thunder":      ("crisp electric zap crackle, short", 0.6),
    "teleport":     ("warm resurface shimmer, rising digital chime", 1.0),
}

# BGM（--music 時）。Music API が必要。ループ前提のため尾を切って使う。
MUSIC = {
    "store":  ("late-night lo-fi jazz, warm rain, gentle rhodes and brush drums, "
               "cozy Chinese diner at midnight, calm loopable", 35000),
    "dive":   ("dark ambient synth drone, cyberpunk descent, deep sub bass, "
               "sparse blips, tense but calm, loopable", 30000),
    "battle": ("tense electronic pulse, driving percussion, neon combat, loopable", 24000),
}


def _post(path, payload, out):
    req = urllib.request.Request(BASE + path, data=json.dumps(payload).encode(),
        headers={"xi-api-key": KEY, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        data = r.read()
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "wb").write(data)
    return len(data)


def gen_sfx():
    for name, (prompt, dur) in SFX.items():
        out = os.path.join(ROOT, "sfx", name + ".mp3")
        try:
            n = _post("/sound-generation",
                {"text": prompt, "duration_seconds": dur, "prompt_influence": 0.6}, out)
            print("  SE  %-12s %d bytes" % (name, n))
        except urllib.error.HTTPError as e:
            print("  SE  %-12s FAILED %s %s" % (name, e.code, e.read()[:120]))


def gen_music():
    for name, (prompt, ms) in MUSIC.items():
        out = os.path.join(ROOT, "bgm_el", name + ".mp3")
        try:
            n = _post("/music", {"prompt": prompt, "music_length_ms": ms}, out)
            print("  BGM %-8s %d bytes" % (name, n))
        except urllib.error.HTTPError as e:
            # Music API が無いプランは長尺SEで代用（最大22s）
            print("  BGM %-8s music API NG (%s); sound-generationで代用" % (name, e.code))
            try:
                n = _post("/sound-generation",
                    {"text": prompt, "duration_seconds": 22, "prompt_influence": 0.3}, out)
                print("       fallback %d bytes" % n)
            except urllib.error.HTTPError as e2:
                print("       fallback FAILED %s" % e2.code)


def main():
    if not KEY:
        sys.exit("ELEVENLABS_API_KEY が未設定です。export してから実行してください。")
    print("ElevenLabs 生成開始（キーは表示しません）")
    gen_sfx()
    if "--music" in sys.argv:
        gen_music()
    print("完了。Godotでインポート→push でWebに反映。")


if __name__ == "__main__":
    main()
