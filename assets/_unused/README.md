# _unused（退避置き場）

使えないが消すには惜しい素材の隔離先。ビルド/コードからは参照しない。

## walk_sheets/
旧 `walk_front.png` / `walk_back.png`（各キャラ）。
64〜96px の歩行シート（横連結4〜5フレーム）で、本セット（144x192 の `<anim>_f<n>.png`）とは
解像度・フォーマット・絵柄が不整合。HD-2D ビルボードに流用すると「コンタクトシート状」に崩れたため退避。

方向別歩行は `gen_anim_frames_gemini.py` の `walk_front`/`walk_back`（144x192 正規スペック）で
生成し直す方針（横向きは既存 `run`＝side view で代用）。
