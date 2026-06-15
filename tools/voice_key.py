#!/usr/bin/env python3
"""会話/実況ボイスのファイル名キーを出す（ゲーム側 _voice_key と一致）。

ゲームは assets/generated/voice/<id>/<key>.{ogg,mp3,wav} を自動再生する。
key = sha256("<id>|<セリフ>") の先頭16桁。TTS(Gemini/Irodori等)で作った音声を
この名前で置けば、発話時に再生され FaceCam の口が実音に同期する。

使い方:
    python3 tools/voice_key.py mil "完璧です。でも、おいしいかどうかは…"
    # → 16桁hex。 出力先: assets/generated/voice/mil/<その16桁>.ogg
"""
import sys
import hashlib

if len(sys.argv) < 3:
    sys.exit('usage: voice_key.py <char_id> "<セリフ>"')
gid, text = sys.argv[1], sys.argv[2]
print(hashlib.sha256(("%s|%s" % (gid, text)).encode("utf-8")).hexdigest()[:16])
