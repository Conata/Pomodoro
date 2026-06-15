#!/usr/bin/env python3
"""PixAI API で画像を生成して保存する（依存なし・標準ライブラリのみ）。

PixAI は GraphQL API（公式 Go/JS クライアント準拠）:
  - エンドポイント : https://api.pixai.art/graphql
  - 認証          : Authorization: Bearer <PIXAI_API_KEY>
  - 生成          : mutation createGenerationTask(parameters: JSONObject!) -> { id status }
  - 取得          : query getGenerationTask(id) -> { id status outputs }   （outputs は JSONObject）
  - メディアURL    : query media(id) -> { urls { variant url } }（variant=PUBLIC）
  - 状態          : waiting / running / completed / failed / cancelled

APIキーの置き場所（どれか）:
  1) 環境変数:    export PIXAI_API_KEY=sk_...
  2) .env ファイル（リポジトリ直下。.gitignore 済み）: PIXAI_API_KEY=sk_...
  ※ コミット厳禁・チャット貼り付け厳禁。露出したら pixai.art で再発行。

単発生成:
    python3 tools/pixai_gen.py --prompt "1girl, purple hair, full body, flat #1a1030 bg" \
        --model 1648918127446573124 --width 768 --height 1280 --out assets/portraits/_raw/kiriko.png

10モデル一括比較（同じプロンプト/シードで全モデルを1枚ずつ→見比べる）:
    # tools/pixai_models.txt に「ID  名前」を1行ずつ書く（pixai.art のモデルページURLの数字がID）
    python3 tools/pixai_gen.py --models-file tools/pixai_models.txt --seed 12345 \
        --prompt "1girl, occult scientist, long purple hair, bust, flat #1a1030 bg, anime" \
        --out tools/_out/model_test
    # → tools/_out/model_test/<id>_<名前>.png が並ぶので一番好みのモデルIDを採用
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


def load_env() -> None:
    """リポジトリ直下の .env を読み、未設定の環境変数だけ補う（依存なしの簡易パーサ）。"""
    root = os.path.join(os.path.dirname(__file__), "..")
    for path in (os.path.join(os.getcwd(), ".env"), os.path.join(root, ".env")):
        if not os.path.isfile(path):
            continue
        for line in open(path, encoding="utf-8"):
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def _gql(query, variables):
    key = os.environ.get("PIXAI_API_KEY")
    if not key:
        sys.exit("PIXAI_API_KEY が未設定です（環境変数 or .env に入れてください）")
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
    except urllib.error.URLError as e:
        sys.exit("通信失敗（このサンドボックスは外部通信が制限されています。ローカルで実行してください）: %s" % e)
    if payload.get("errors"):
        raise RuntimeError(json.dumps(payload["errors"], ensure_ascii=False))
    return payload.get("data", {})


def _find_urls(obj):
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
    print("  saved %s (%d KB)" % (path, len(data) // 1024))


def generate(params, timeout) -> list:
    """1タスク実行して画像URL一覧を返す。"""
    data = _gql(MUT_CREATE, {"parameters": params})
    task = data.get("createGenerationTask") or {}
    tid = task.get("id")
    if not tid:
        raise RuntimeError("タスク作成失敗: " + json.dumps(data, ensure_ascii=False))
    deadline = time.time() + timeout
    while time.time() < deadline:
        time.sleep(3)
        t = (_gql(QUERY_TASK, {"id": tid}).get("getGenerationTask") or {})
        st = t.get("status")
        if st == "completed":
            outputs = t.get("outputs")
            urls = _find_urls(outputs)
            if not urls:
                for mid in dict.fromkeys(_find_media_ids(outputs)):
                    md = _gql(QUERY_MEDIA, {"id": mid}).get("media") or {}
                    for u in md.get("urls", []):
                        if u.get("variant") in (None, "PUBLIC"):
                            urls.append(u["url"])
            return urls
        if st in ("failed", "cancelled"):
            raise RuntimeError("生成失敗: " + str(st))
    raise RuntimeError("タイムアウト")


def _base_params(a):
    p = {
        "prompts": a.prompt,
        "negativePrompts": a.negative,
        "width": a.width,
        "height": a.height,
        "samplingSteps": a.steps,
        "cfgScale": a.cfg,
        "batchSize": a.batch,
        "priority": 1000,
    }
    if a.seed:
        p["seed"] = a.seed
    return p


def _read_models_file(path):
    """各行「ID  名前」（# はコメント）。名前は省略可。"""
    out = []
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(None, 1)
        mid = parts[0]
        name = parts[1].strip() if len(parts) > 1 else mid
        if mid.isdigit():
            out.append((mid, name))
    return out


def main():
    load_env()
    ap = argparse.ArgumentParser()
    ap.add_argument("--prompt", required=True)
    ap.add_argument("--negative", default="lowres, bad anatomy, watermark, text, ui, multiple views")
    ap.add_argument("--model", default=os.environ.get("PIXAI_MODEL_ID", "1648918127446573124"))
    ap.add_argument("--models", default="", help="比較するモデルIDのカンマ区切り")
    ap.add_argument("--models-file", default="", help="「ID 名前」を並べたファイル")
    ap.add_argument("--width", type=int, default=768)
    ap.add_argument("--height", type=int, default=1024)
    ap.add_argument("--steps", type=int, default=25)
    ap.add_argument("--cfg", type=float, default=7.0)
    ap.add_argument("--seed", type=int, default=0, help="比較時は固定推奨（同じ構図で見比べ）")
    ap.add_argument("--batch", type=int, default=1)
    ap.add_argument("--out", required=True, help="単発=ファイル / 比較=出力ディレクトリ")
    ap.add_argument("--timeout", type=int, default=300)
    a = ap.parse_args()

    # --- 比較モード（10モデル一括）---
    models = []
    if a.models_file:
        models = _read_models_file(a.models_file)
    elif a.models:
        models = [(m.strip(), m.strip()) for m in a.models.split(",") if m.strip()]
    if models:
        os.makedirs(a.out, exist_ok=True)
        print("== %d モデルを比較生成（seed=%s）==" % (len(models), a.seed or "random"))
        for mid, name in models:
            safe = "".join(c if c.isalnum() or c in "-_" else "_" for c in name)[:40]
            params = _base_params(a)
            params["modelId"] = mid
            print("model %s (%s)" % (mid, name))
            try:
                urls = generate(params, a.timeout)
            except Exception as e:
                print("  skip:", e)
                continue
            if urls:
                _download(urls[0], os.path.join(a.out, "%s_%s.png" % (mid, safe)))
        print("→ %s を見比べて好みのIDを採用してください" % a.out)
        return

    # --- 単発モード ---
    params = _base_params(a)
    params["modelId"] = a.model
    urls = generate(params, a.timeout)
    if not urls:
        sys.exit("画像URLが取得できませんでした")
    if len(urls) == 1:
        _download(urls[0], a.out)
    else:
        base, ext = os.path.splitext(a.out)
        for i, u in enumerate(urls):
            _download(u, "%s_%d%s" % (base, i, ext))


if __name__ == "__main__":
    main()
