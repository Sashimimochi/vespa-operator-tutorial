#!/usr/bin/env bash
# Vespa 検索テストスクリプト
# 使用例: ./scripts/search.sh [ENDPOINT]

set -euo pipefail

ENDPOINT="${1:-http://localhost:8080}"
SEARCH_URL="${ENDPOINT}/search/"

echo "=== Vespa 検索テスト ==="
echo "  エンドポイント: ${ENDPOINT}"
echo ""

# ヘルパー関数: 検索を実行して結果を表示
run_search() {
  local DESC="$1"
  local QUERY="$2"
  local EXTRA="${3:-}"

  echo "--- ${DESC} ---"
  echo "  クエリ: ${QUERY}"

  PARAMS="query=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${QUERY}'))")"
  if [ -n "${EXTRA}" ]; then
    PARAMS="${PARAMS}&${EXTRA}"
  fi

  RESPONSE=$(curl -s "${SEARCH_URL}?${PARAMS}")

  # 結果件数を表示
  TOTAL=$(echo "${RESPONSE}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    total = d.get('root', {}).get('fields', {}).get('totalCount', 0)
    hits = d.get('root', {}).get('children', [])
    print(f'  ヒット数: {total}件')
    for i, hit in enumerate(hits[:3], 1):
        fields = hit.get('fields', {})
        title = fields.get('title', '')
        artist = fields.get('artist', '')
        year = fields.get('year', '')
        score = hit.get('relevance', 0)
        print(f'  [{i}] {title} / {artist} ({year}) スコア: {score:.3f}')
except Exception as e:
    print(f'  エラー: {e}')
    print(sys.stdin.read()[:200])
" 2>/dev/null || echo "  レスポンス取得エラー")
  echo "${TOTAL}"
  echo ""
}

# Vespa の起動確認
echo "--- Vespa API の起動を確認中... ---"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/wait-for-vespa.sh" "${ENDPOINT}" 60

echo ""
echo "=== 検索テスト開始 ==="
echo ""

# テスト 1: 日本語キーワード検索
run_search "日本語キーワード検索: YOASOBI" "YOASOBI"

# テスト 2: 日本語タイトル検索
run_search "日本語タイトル検索: 夜に駆ける" "夜に駆ける"

# テスト 3: 英語アーティスト検索
run_search "英語アーティスト検索: Queen" "Queen"

# テスト 4: ジャンルフィルター
run_search "ジャンルフィルター: アニメ" "anime" "yql=select%20*%20from%20music%20where%20genre%20contains%20%22%E3%82%A2%E3%83%8B%E3%83%A1%22"

# テスト 5: 全件取得
echo "--- 全件取得（最大5件） ---"
RESPONSE=$(curl -s "${SEARCH_URL}?yql=select%20*%20from%20music%20where%20true&hits=5")
echo "${RESPONSE}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    total = d.get('root', {}).get('fields', {}).get('totalCount', 0)
    hits = d.get('root', {}).get('children', [])
    print(f'  総ドキュメント数: {total}件')
    for i, hit in enumerate(hits, 1):
        fields = hit.get('fields', {})
        title = fields.get('title', '')
        artist = fields.get('artist', '')
        print(f'  [{i}] {title} / {artist}')
except Exception as e:
    print(f'  エラー: {e}')
" 2>/dev/null || echo "  エラー"
echo ""

echo "=== 検索テスト完了 ==="
