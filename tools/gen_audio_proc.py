#!/usr/bin/env python3
"""依存ゼロ（Python 標準ライブラリのみ）で BGM/SE を合成する。

ElevenLabs が使えない環境（APIキー無し・egress 不可）でも、ゲームに実際に鳴る
音を入れるためのフォールバック生成器。ネオン中華＋電脳トーンを狙った加算合成。

    python3 tools/gen_audio_proc.py          # SE12種 + BGM3種
    python3 tools/gen_audio_proc.py --sfx     # SEのみ
    python3 tools/gen_audio_proc.py --music   # BGMのみ

出力（ゲームは mp3 > wav > 既存フォールバック の順で自動ロード）：
    assets/generated/sfx/<name>.wav
    assets/generated/bgm_el/<name>.wav

後で ElevenLabs の mp3 を同じディレクトリに置けば、そちらが優先される。
"""
import os
import sys
import math
import wave
import struct
import random

ROOT = os.path.join(os.path.dirname(__file__), "..", "assets", "generated")
SR = 44100      # SE
SR_BGM = 32000  # BGM（尺が長いので軽く）
TAU = 2.0 * math.pi


# ---- 低レベル合成ヘルパ -------------------------------------------------

def buf(seconds, sr):
    return [0.0] * int(seconds * sr)


def add_tone(b, sr, freq, start, dur, amp, wave_fn, env=None, detune=0.0,
             vibrato=0.0, vib_rate=5.0):
    """b に 1 ボイス分を加算。env(t01)->gain。"""
    i0 = int(start * sr)
    n = int(dur * sr)
    end = min(i0 + n, len(b))
    phase = 0.0
    phase2 = 0.0
    for i in range(i0, end):
        t = (i - i0) / sr
        t01 = (i - i0) / n
        g = amp * (env(t01) if env else 1.0)
        f = freq * (1.0 + vibrato * math.sin(TAU * vib_rate * t))
        phase += TAU * f / sr
        s = wave_fn(phase)
        if detune:
            phase2 += TAU * (f * (1.0 + detune)) / sr
            s = 0.5 * (s + wave_fn(phase2))
        b[i] += g * s


def add_noise(b, sr, start, dur, amp, env=None, lp=None):
    """フィルタ付きホワイトノイズを加算。lp=0..1 で一次ローパス係数。"""
    i0 = int(start * sr)
    n = int(dur * sr)
    end = min(i0 + n, len(b))
    prev = 0.0
    for i in range(i0, end):
        t01 = (i - i0) / n
        g = amp * (env(t01) if env else 1.0)
        w = random.uniform(-1.0, 1.0)
        if lp is not None:
            prev += lp * (w - prev)
            w = prev
        b[i] += g * w


def s_sin(p):
    return math.sin(p)


def s_saw(p):
    x = (p / TAU) % 1.0
    return 2.0 * x - 1.0


def s_sq(p):
    return 1.0 if math.sin(p) >= 0 else -1.0


def s_tri(p):
    x = (p / TAU) % 1.0
    return 4.0 * abs(x - 0.5) - 1.0


# エンベロープ
def env_perc(decay=0.5):
    return lambda t: math.exp(-t / max(decay, 1e-4))


def env_ad(a=0.05, d=0.5):
    def f(t):
        if t < a:
            return t / a
        return math.exp(-(t - a) / max(d, 1e-4))
    return f


def env_swell():
    return lambda t: math.sin(math.pi * t)


def env_sus(a=0.02, r=0.1):
    def f(t):
        if t < a:
            return t / a
        if t > 1.0 - r:
            return max(0.0, (1.0 - t) / r)
        return 1.0
    return f


def lowpass(b, k):
    prev = 0.0
    for i in range(len(b)):
        prev += k * (b[i] - prev)
        b[i] = prev


def delay(b, sr, time, fb=0.3, mix=0.3):
    d = int(time * sr)
    if d <= 0:
        return
    for i in range(d, len(b)):
        b[i] += mix * b[i - d] * fb


def bitcrush(b, bits=6, rate=1):
    levels = 2 ** bits
    hold = 0.0
    for i in range(len(b)):
        if i % rate == 0:
            hold = round(b[i] * levels) / levels
        b[i] = hold


def normalize(b, peak=0.89):
    m = max((abs(x) for x in b), default=0.0)
    if m < 1e-6:
        return
    g = peak / m
    for i in range(len(b)):
        x = b[i] * g
        # ソフトクリップ
        b[i] = math.tanh(x * 1.2) / math.tanh(1.2)


def write_wav(path, b, sr):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        frames = bytearray()
        for x in b:
            v = int(max(-1.0, min(1.0, x)) * 32767)
            frames += struct.pack("<h", v)
        w.writeframes(bytes(frames))
    return len(b) / sr


# ---- SE -----------------------------------------------------------------

def sfx_ui_confirm():
    b = buf(0.22, SR)
    add_tone(b, SR, 880, 0.0, 0.22, 0.6, s_sin, env_perc(0.09))
    add_tone(b, SR, 1320, 0.03, 0.19, 0.4, s_sin, env_perc(0.07))
    return b, SR


def sfx_ui_denied():
    b = buf(0.24, SR)
    add_tone(b, SR, 175, 0.0, 0.24, 0.5, s_sq, env_perc(0.12))
    add_tone(b, SR, 130, 0.06, 0.18, 0.4, s_sq, env_perc(0.1))
    lowpass(b, 0.25)
    return b, SR


def sfx_ui_equip():
    b = buf(0.2, SR)
    add_noise(b, SR, 0.0, 0.02, 0.5, env_perc(0.01), lp=0.5)
    add_tone(b, SR, 1240, 0.01, 0.18, 0.4, s_sin, env_perc(0.06))
    add_tone(b, SR, 1870, 0.01, 0.14, 0.25, s_sin, env_perc(0.05))
    return b, SR


def sfx_ui_buy():
    b = buf(0.34, SR)
    for hit in (0.0, 0.085):
        for f, a in ((2480, 0.4), (3310, 0.3), (4120, 0.2)):
            add_tone(b, SR, f, hit, 0.22, a, s_sin, env_perc(0.07))
    return b, SR


def sfx_chest_open():
    b = buf(0.95, SR)
    # きしむ蓋
    add_noise(b, SR, 0.0, 0.45, 0.4, lambda t: 0.5 * (1 - math.cos(8 * t)), lp=0.12)
    add_tone(b, SR, 90, 0.0, 0.45, 0.2, s_saw, env_sus(0.1, 0.2), vibrato=0.3, vib_rate=6)
    # きらめき
    for k, f in enumerate((1320, 1760, 2640, 3520)):
        add_tone(b, SR, f, 0.5 + k * 0.07, 0.3, 0.3, s_sin, env_perc(0.12))
    return b, SR


def sfx_sword():
    b = buf(0.26, SR)
    add_noise(b, SR, 0.0, 0.26, 0.7, env_swell(), lp=0.2)
    return b, SR


def sfx_damage():
    b = buf(0.24, SR)
    # ピッチが落ちる鈍い当たり
    i0 = 0
    n = len(b)
    phase = 0.0
    for i in range(n):
        t01 = i / n
        f = 130 * (1 - 0.45 * t01)
        phase += TAU * f / SR
        b[i] += 0.7 * math.exp(-t01 / 0.18) * math.sin(phase)
    add_noise(b, SR, 0.0, 0.04, 0.3, env_perc(0.02), lp=0.3)
    return b, SR


def sfx_slash():
    b = buf(0.2, SR)
    add_noise(b, SR, 0.0, 0.2, 0.8, env_perc(0.05), lp=0.6)
    lp = buf(0.2, SR)
    add_noise(lp, SR, 0.0, 0.2, 0.8, env_perc(0.05), lp=0.08)
    for i in range(len(b)):  # ハイパス＝原音 − ローパス
        b[i] -= 0.7 * lp[i]
    return b, SR


def sfx_enemy_death():
    b = buf(0.6, SR)
    for k in range(6):
        f = 1200 * (0.8 ** k)
        add_tone(b, SR, f, k * 0.07, 0.2, 0.4, s_sq, env_perc(0.08))
    add_noise(b, SR, 0.0, 0.6, 0.25, env_perc(0.25), lp=0.4)
    bitcrush(b, bits=5, rate=2)
    return b, SR


def sfx_fire():
    b = buf(0.55, SR)
    add_noise(b, SR, 0.0, 0.55, 0.8, lambda t: math.sin(math.pi * min(t * 1.4, 1.0)) * math.exp(-t / 0.4), lp=0.18)
    add_noise(b, SR, 0.0, 0.1, 0.3, env_perc(0.04), lp=0.5)  # 着火クラックル
    return b, SR


def sfx_thunder():
    b = buf(0.5, SR)
    add_noise(b, SR, 0.0, 0.5, 0.7, env_perc(0.18), lp=0.7)
    for f in (2200, 3300, 4700):
        add_tone(b, SR, f, 0.0, 0.12, 0.2, s_sin, env_perc(0.04))
    for _ in range(14):  # クラックル
        t = random.uniform(0.0, 0.35)
        add_noise(b, SR, t, 0.02, random.uniform(0.2, 0.5), env_perc(0.008), lp=0.8)
    return b, SR


def sfx_teleport():
    b = buf(0.9, SR)
    # 上昇シマー
    for det in (0.0, 0.006, -0.006):
        n = len(b)
        phase = 0.0
        for i in range(n):
            t01 = i / n
            f = 300 * (1 + 3.0 * t01) * (1 + det)
            phase += TAU * f / SR
            b[i] += 0.18 * math.sin(math.pi * t01) * math.sin(phase)
    for k, f in enumerate((880, 1320, 1760, 2640)):
        add_tone(b, SR, f, 0.4 + k * 0.08, 0.4, 0.22, s_sin, env_perc(0.18))
    delay(b, SR, 0.13, fb=0.4, mix=0.3)
    return b, SR


SFX = {
    "ui_confirm": sfx_ui_confirm, "ui_denied": sfx_ui_denied,
    "ui_equip": sfx_ui_equip, "ui_buy": sfx_ui_buy,
    "chest_open": sfx_chest_open, "sword": sfx_sword,
    "damage": sfx_damage, "slash": sfx_slash,
    "enemy_death": sfx_enemy_death, "fire": sfx_fire,
    "thunder": sfx_thunder, "teleport": sfx_teleport,
}


# ---- BGM ----------------------------------------------------------------

def _note(name):
    """音名 -> 周波数（A4=440）。例 'C4','Ds4'(=C#)。"""
    semis = {"C": -9, "Cs": -8, "D": -7, "Ds": -6, "E": -5, "F": -4,
             "Fs": -3, "G": -2, "Gs": -1, "A": 0, "As": 1, "B": 2}
    pc = name[:-1]
    octv = int(name[-1])
    n = semis[pc] + (octv - 4) * 12
    return 440.0 * (2 ** (n / 12.0))


def bgm_store():
    """夜のロウファイ：温かいローズ系パッド＋柔らかいブラシ。"""
    sr = SR_BGM
    beat = 60.0 / 74.0
    bars = 4
    length = bars * 4 * beat
    b = buf(length, sr)
    # ii-V-I-vi（Dm7 - G7 - Cmaj7 - Am7）
    chords = [
        ["D3", "F3", "A3", "C4"],
        ["G2", "B2", "D3", "F3"],
        ["C3", "E3", "G3", "B3"],
        ["A2", "C3", "E3", "G3"],
    ]
    for bar, ch in enumerate(chords):
        t = bar * 4 * beat
        for nm in ch:
            f = _note(nm)
            add_tone(b, sr, f, t, 4 * beat, 0.14, s_sin,
                     env_sus(0.08, 0.3), vibrato=0.004, vib_rate=5.2)
            add_tone(b, sr, f * 2, t, 4 * beat, 0.05, s_sin,
                     env_sus(0.08, 0.3))  # 倍音で艶
        # ベースはルート
        add_tone(b, sr, _note(ch[0]) / 2, t, beat * 1.5, 0.22, s_tri, env_ad(0.01, 0.6))
        add_tone(b, sr, _note(ch[0]) / 2, t + 2 * beat, beat * 1.5, 0.18, s_tri, env_ad(0.01, 0.6))
    # ブラシ系ハット（裏拍）
    for k in range(int(bars * 4 * 2)):
        if k % 2 == 1:
            add_noise(b, sr, k * beat / 2, 0.09, 0.06, env_perc(0.03), lp=0.85)
    lowpass(b, 0.35)
    delay(b, sr, beat / 2, fb=0.25, mix=0.18)
    return b, sr


def bgm_dive():
    """暗いアンビエント潜行：サブベース＋ゆっくり蠢くパッド＋疎なブリップ。"""
    sr = SR_BGM
    length = 16.0
    b = buf(length, sr)
    # サブ
    add_tone(b, sr, _note("A1"), 0.0, length, 0.3, s_sin, env_sus(1.0, 1.0))
    # デチューンパッド（ゆっくりうねる）
    for f, det in ((_note("A2"), 0.004), (_note("E3"), -0.004), (_note("C3"), 0.006)):
        add_tone(b, sr, f, 0.0, length, 0.12, s_saw, env_sus(2.0, 2.0),
                 detune=det, vibrato=0.003, vib_rate=0.15)
    # カットオフのゆらぎ
    cut = [0.06 + 0.05 * (0.5 + 0.5 * math.sin(TAU * 0.05 * (i / sr))) for i in range(len(b))]
    prev = 0.0
    for i in range(len(b)):
        prev += cut[i] * (b[i] - prev)
        b[i] = prev
    # 疎なブリップ
    random.seed(7)
    for _ in range(7):
        t = random.uniform(0.5, length - 1.0)
        f = random.choice([_note("A4"), _note("C5"), _note("E5")])
        add_tone(b, sr, f, t, 0.5, 0.16, s_sin, env_perc(0.18))
    delay(b, sr, 0.375, fb=0.45, mix=0.35)
    return b, sr


def bgm_battle():
    """緊迫の電脳戦闘：駆動ベースアルペジオ＋キック＋ハット＋リードスタブ。"""
    sr = SR_BGM
    bpm = 140.0
    step = 60.0 / bpm / 4.0  # 16分
    steps = 64               # 4小節
    length = steps * step
    b = buf(length, sr)
    root = "A1"
    arp = [_note("A2"), _note("E3"), _note("A3"), _note("E3")]
    for s in range(steps):
        t = s * step
        # ベースアルペジオ（16分）
        add_tone(b, sr, arp[s % len(arp)], t, step * 0.9, 0.22, s_sq, env_perc(0.05))
        # キック（4つ打ち）
        if s % 4 == 0:
            kb = buf(0.18, sr)
            n = len(kb)
            ph = 0.0
            for i in range(n):
                t01 = i / n
                f = 120 * (1 - 0.7 * t01) + 45
                ph += TAU * f / sr
                kb[i] = 0.9 * math.exp(-t01 / 0.12) * math.sin(ph)
            i0 = int(t * sr)
            for i in range(len(kb)):
                if i0 + i < len(b):
                    b[i0 + i] += kb[i]
        # ハット（8分裏）
        if s % 2 == 1:
            add_noise(b, sr, t, 0.05, 0.12, env_perc(0.02), lp=0.9)
        # リードスタブ（小節頭・半ばにコード）
        if s % 16 in (0, 10):
            for nm in ("A3", "C4", "E4"):
                add_tone(b, sr, _note(nm), t, step * 3, 0.1, s_saw, env_perc(0.12), detune=0.004)
    lowpass(b, 0.6)
    return b, sr


BGM = {"store": bgm_store, "dive": bgm_dive, "battle": bgm_battle}


# ---- main ---------------------------------------------------------------

def gen_sfx():
    for name, fn in SFX.items():
        b, sr = fn()
        normalize(b, 0.9)
        out = os.path.join(ROOT, "sfx", name + ".wav")
        dur = write_wav(out, b, sr)
        print("  SE  %-12s %.2fs" % (name, dur))


def gen_music():
    for name, fn in BGM.items():
        b, sr = fn()
        normalize(b, 0.82)
        out = os.path.join(ROOT, "bgm_el", name + ".wav")
        dur = write_wav(out, b, sr)
        print("  BGM %-8s %.1fs" % (name, dur))


def main():
    args = sys.argv[1:]
    do_sfx = ("--sfx" in args) or not args or not ("--music" in args and "--sfx" not in args)
    only_music = ("--music" in args and "--sfx" not in args)
    only_sfx = ("--sfx" in args and "--music" not in args)
    print("手続き生成（依存ゼロ）")
    if only_music:
        gen_music()
    elif only_sfx:
        gen_sfx()
    else:
        gen_sfx()
        gen_music()
    print("完了。godot --import → push でWebに反映。")


if __name__ == "__main__":
    main()
