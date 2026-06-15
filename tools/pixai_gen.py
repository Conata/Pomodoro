#!/usr/bin/env python3
"""PixAI API で画像を生成して規定パスに保存する（依存なし・標準ライブラリのみ）。

PixAI は GraphQL API（公式 Go/JS クライアント準拠）:
  - エンドポイント : https://api.pixai.art/graphql
  - 認証          : Authorization: Bearer <PIXAI_API_KEY>
  - 生成          : mutation createGenerationTask(parameters: JSONObject!) -> { id status }
  - 取得          : query getGenerationTask(id) -> { id status outputs }   （outputs は JSONObject）
  - メディアURL    : query media(id) -> { urls { variant url } }（variant=PUBLIC を使う）
  - 状態          : waiting / running / completed / failed / cancelled

使い方:
    export PIXAI_API_KEY=sk_...                       # 自分のキー（コミット厳禁）
    python3 tools/pixai_gen.py \
        --prompt "1girl, occult scientist, purple hair, bust, flat #1a1030 bg" \
        --model 1648918127446573124 \
        --width 768 --height 1024 \
        --out assets/portraits/_raw/kiriko.png
    # → 透過化は tools/key_bg.py、表情シート分割は tools/slice_expressions.py へ

注意:
  - modelId は pixai.art のモデルページで選ぶ（必須）。--model 省略時は例のモデルID。
  - PixAI はクレジット消費。失敗時に無駄打ちしないよう少数で試すこと。
  - GraphQLのフィールド名が将来変わったら QUERY_* 定数を直すだけで追従できる。
  - 立ち絵/シートに使うなら「単色フラット背景」を prompt に明記すると後処理が楽。
"""
import os
import sys
import json
import time
import argparse
import urllib.request
import urllib.error

ENDPOINT = os.environ.get("PIXAI_API_URL", "https://api.pixai.art/graphql")

MUT_CREATE = """
mutation createGenerationTask($parameters: JSONObject!) {
  createGenerationTask(parameters: $parameters) { id status }
}
"""
QUERY_TASK = """
query getGenerationTask($id: ID!) {
  getGenerationTask(id: $id) { id status outputs }
}
"""
QUERY_MEDIA = """
query media($id: ID!) {
  media(id: $id) { id urls { variant url } }
}
"""


def _gql(query, variables):
    key = os.environ.get("PIXAI_API_KEY")
    if not key:
        sys.exit("環境変数 PIXAI_API_KEY が未設定です")
    body = json.dumps({"query": query, "variables": variables}).encode("utf-8")
    req = urllib.request.Request(ENDPOINT, data=body, method="POST", headers={
        "Content-Type": "application/json",
        "Authorization": "Bearer " + key,
    })
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            payload = json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        sys.exit("HTTP %d: %s" % (e.code, e.read().decode("utf-8", "ignore")))
    if payload.get("errors"):
        sys.exit("GraphQL error: " + json.dumps(payload["errors"], ensure_ascii=False))
    return payload.get("data", {})


def _find_urls(obj):
    """ネストした dict/list から画像URLっぽいものを全部拾う（outputsの形に依存しないため）。"""
    out = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            if isinstance(v, str) and v.startswith("http") and k.lower() in ("url", "src", "image", "public"):
                out.append(v)
            else:
                out += _find_urls(v)
    elif isinstance(obj, list):
        for v in obj:
            out += _find_urls(v)
    return out


def _find_media_ids(obj):
    out = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k.lower() in ("mediaid", "id") and isinstance(v, str) and v.isdigit():
                out.append(v)
            else:
                out += _find_media_ids(v)
    elif isinstance(obj, list):
        for v in obj:
            out += _find_media_ids(v)
    return out


def _download(url, path):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with urllib.request.urlopen(url, timeout=120) as r:
        data = r.read()
    open(path, "wb").write(data)
    print("saved %s (%d KB)" % (path, len(data) // 1024))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prompt", required=True)
    ap.add_argument("--negative", default="lowres, bad anatomy, watermark, text, ui")
    ap.add_argument("--model", default="1648918127446573124", help="pixai.art のモデルID")
    ap.add_argument("--width", type=int, default=768)
    ap.add_argument("--height", type=int, default=1024)
    ap.add_argument("--steps", type=int, default=25)
    ap.add_argument("--cfg", type=float, default=7.0)
    ap.add_argument("--seed", type=int, default=0, help="0=ランダム。シート用に固定すると一貫性UP")
    ap.add_argument("--batch", type=int, default=1)
    ap.add_argument("--out", required=True, help="保存先（batch>1 は _0,_1… が付く）")
    ap.add_argument("--timeout", type=int, default=300)
    args = ap.parse_args()

    params = {
        "prompts": args.prompt,
        "negativePrompts": args.negative,
        "modelId": args.model,
        "width": args.width,
        "height": args.height,
        "samplingSteps": args.steps,
        "cfgScale": args.cfg,
        "batchSize": args.batch,
        "priority": 1000,
    }
    if args.seed:
        params["seed"] = args.seed

    data = _gql(MUT_CREATE, {"parameters": params})
    task = data.get("createGenerationTask") or {}
    tid = task.get("id")
    if not tid:
        sys.exit("タスク作成に失敗: " + json.dumps(data, ensure_ascii=False))
    print("task %s : %s" % (tid, task.get("status")))

    deadline = time.time() + args.timeout
    outputs = None
    while time.time() < deadline:
        time.sleep(3)
        d = _gql(QUERY_TASK, {"id": tid})
        t = d.get("getGenerationTask") or {}
        st = t.get("status")
        print("  status:", st)
        if st == "completed":
            outputs = t.get("outputs")
            break
        if st in ("failed", "cancelled"):
            sys.exit("生成失敗: " + str(st))
    if outputs is None:
        sys.exit("タイムアウト")

    urls = _find_urls(outputs)
    if not urls:  # outputs に mediaId しか無い場合はメディアを引く
        for mid in dict.fromkeys(_find_media_ids(outputs)):
            md = _gql(QUERY_MEDIA, {"id": mid}).get("media") or {}
            for u in md.get("urls", []):
                if u.get("variant") in (None, "PUBLIC"):
                    urls.append(u["url"])
    if not urls:
        sys.exit("画像URLが取れません。outputs=" + json.dumps(outputs, ensure_ascii=False))

    if len(urls) == 1:
        _download(urls[0], args.out)
    else:
        base, ext = os.path.splitext(args.out)
        for i, u in enumerate(urls):
            _download(u, "%s_%d%s" % (base, i, ext))


if __name__ == "__main__":
    main()
