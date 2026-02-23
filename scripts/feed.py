#!/usr/bin/env python3
"""Vespa サンプルデータ投入スクリプト / Feed sample data to Vespa"""

import json
import sys
import time
import urllib.error
import urllib.request

FEED_PORT = sys.argv[1] if len(sys.argv) > 1 else "8080"
DATA_FILE = sys.argv[2] if len(sys.argv) > 2 else "data/feed.json"

docs = json.load(open(DATA_FILE))
errors = []

for d in docs:
    doc_id = d["put"].split("::")[-1]
    url = f"http://localhost:{FEED_PORT}/document/v1/music/music/docid/{doc_id}"
    body = json.dumps({"fields": d["fields"]}).encode()
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    ok = False
    for attempt in range(5):
        try:
            urllib.request.urlopen(req, timeout=30)
            title_ja = d["fields"].get("title_ja", "")
            print(f"投入: {d['fields']['title']} / {title_ja}")
            ok = True
            break
        except urllib.error.HTTPError as e:
            print(
                f"  試行 {attempt+1}/5 失敗 HTTP {e.code}: {d['fields']['title']}",
                file=sys.stderr,
            )
            if attempt < 4:
                time.sleep(10)
        except Exception as e:
            print(
                f"  試行 {attempt+1}/5 失敗 {e}: {d['fields']['title']}",
                file=sys.stderr,
            )
            if attempt < 4:
                time.sleep(10)
    if not ok:
        errors.append(d["fields"]["title"])

if errors:
    print(f"投入失敗: {errors}", file=sys.stderr)
    sys.exit(1)
