#!/usr/bin/env bash
# Vespa コンテナ API の起動を待機するスクリプト
# 使用例: ./scripts/wait-for-vespa.sh [ENDPOINT] [TIMEOUT]

set -euo pipefail

ENDPOINT="${1:-http://localhost:8080}"
TIMEOUT="${2:-300}"
HEALTH_URL="${ENDPOINT}/state/v1/health"

echo "=== Vespa API の起動を待機中 ==="
echo "  エンドポイント: ${ENDPOINT}"
echo "  タイムアウト: ${TIMEOUT}秒"

START_TIME=$(date +%s)
while true; do
  CURRENT_TIME=$(date +%s)
  ELAPSED=$((CURRENT_TIME - START_TIME))

  if [ "${ELAPSED}" -ge "${TIMEOUT}" ]; then
    echo "エラー: ${TIMEOUT}秒待機しましたが Vespa が起動しませんでした"
    exit 1
  fi

  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${HEALTH_URL}" 2>/dev/null || echo "000")
  if [ "${HTTP_CODE}" = "200" ]; then
    echo "=== Vespa API が起動しました（${ELAPSED}秒経過）==="
    break
  fi

  echo "  待機中... HTTP=${HTTP_CODE} （${ELAPSED}/${TIMEOUT}秒経過）"
  sleep 5
done
