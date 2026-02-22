#!/usr/bin/env bash
# サンプルデータを Vespa に投入するスクリプト
# 使用例: ./scripts/feed-data.sh [ENDPOINT]

set -euo pipefail

ENDPOINT="${1:-http://localhost:8080}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_FILE="${SCRIPT_DIR}/../data/sample-music.jsonl"
FEED_URL="${ENDPOINT}/document/v1"

echo "=== Vespa にサンプルデータを投入します ==="
echo "  エンドポイント: ${ENDPOINT}"
echo "  データファイル: ${DATA_FILE}"

if [ ! -f "${DATA_FILE}" ]; then
  echo "エラー: データファイルが見つかりません: ${DATA_FILE}"
  exit 1
fi

# Vespa の起動を確認
echo "--- Vespa API の起動を確認中... ---"
"${SCRIPT_DIR}/wait-for-vespa.sh" "${ENDPOINT}" 300

SUCCESS=0
FAIL=0
TOTAL=0

echo "--- データ投入開始 ---"
while IFS= read -r LINE; do
  [ -z "${LINE}" ] && continue
  TOTAL=$((TOTAL + 1))

  # document ID を抽出（id:music:music::<number>）
  DOC_ID=$(echo "${LINE}" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['put'])" 2>/dev/null || \
           echo "${LINE}" | grep -o '"put": *"[^"]*"' | cut -d'"' -f4)

  # Vespa Document API にフィードするには /document/v1/{namespace}/{doctype}/docid/{id} にアクセス
  # jsonl の "put" フォーマットはそのまま vespa-feed-client で利用できるが、
  # ここでは標準 curl で Document API v1 を使用する
  FIELDS=$(echo "${LINE}" | python3 -c "import sys, json; d=json.load(sys.stdin); print(json.dumps({'fields': d['fields']}))" 2>/dev/null)

  # id:music:music::<id> => namespace=music, doctype=music, id=<id>
  NS=$(echo "${DOC_ID}" | cut -d: -f2)
  DOCTYPE=$(echo "${DOC_ID}" | cut -d: -f3)
  DOCID=$(echo "${DOC_ID}" | cut -d: -f5)
  URL="${ENDPOINT}/document/v1/${NS}/${DOCTYPE}/docid/${DOCID}"

  HTTP_CODE=$(curl -s -o /tmp/feed-response.txt -w "%{http_code}" \
    -X PUT \
    -H "Content-Type: application/json" \
    -d "${FIELDS}" \
    "${URL}")

  if [ "${HTTP_CODE}" -ge 200 ] && [ "${HTTP_CODE}" -lt 300 ]; then
    echo "  [OK] ${DOC_ID} => HTTP ${HTTP_CODE}"
    SUCCESS=$((SUCCESS + 1))
  else
    echo "  [NG] ${DOC_ID} => HTTP ${HTTP_CODE}"
    cat /tmp/feed-response.txt
    FAIL=$((FAIL + 1))
  fi
done < "${DATA_FILE}"

echo ""
echo "=== 投入完了 ==="
echo "  成功: ${SUCCESS}件"
echo "  失敗: ${FAIL}件"
echo "  合計: ${TOTAL}件"

if [ "${FAIL}" -gt 0 ]; then
  exit 1
fi
