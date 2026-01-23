#!/bin/bash
# test-authorization.sh - Run all authorization scenario tests
#
# Usage:
#   ./scripts/test-authorization.sh
#
# Prerequisites:
#   - kubectl port-forward -n spiffe-demo svc/web-dashboard 8080:8080 &

set -e

BASE_URL="${BASE_URL:-http://localhost:8080}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

pass() { echo -e "${GREEN}PASS${NC}"; }
fail() { echo -e "${RED}FAIL${NC}"; }

check_result() {
    local expected=$1
    local actual=$2
    if [ "$expected" == "$actual" ]; then
        pass
    else
        fail
        echo "  Expected: $expected, Got: $actual"
    fi
}

echo "=============================================="
echo "  SPIFFE/SPIRE Authorization Test Suite"
echo "=============================================="
echo ""
echo "Base URL: $BASE_URL"
echo ""

# Health check
echo -n "Health check... "
health=$(curl -s "$BASE_URL/health" | jq -r '.status' 2>/dev/null)
if [ "$health" == "healthy" ]; then
    pass
else
    fail
    echo "Dashboard not responding. Is port-forward running?"
    exit 1
fi

echo ""
echo "=== Direct Access Tests ==="
echo ""

echo -n "1. Alice -> DOC-001 (engineering, should GRANT): "
result=$(curl -s -X POST "$BASE_URL/api/access-direct" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "alice", "document_id": "DOC-001"}' | jq -r '.granted')
check_result "true" "$result"

echo -n "2. Bob -> DOC-002 (finance, should GRANT): "
result=$(curl -s -X POST "$BASE_URL/api/access-direct" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "bob", "document_id": "DOC-002"}' | jq -r '.granted')
check_result "true" "$result"

echo -n "3. Bob -> DOC-003 (admin, should GRANT): "
result=$(curl -s -X POST "$BASE_URL/api/access-direct" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "bob", "document_id": "DOC-003"}' | jq -r '.granted')
check_result "true" "$result"

echo -n "4. Carol -> DOC-004 (hr, should GRANT): "
result=$(curl -s -X POST "$BASE_URL/api/access-direct" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "carol", "document_id": "DOC-004"}' | jq -r '.granted')
check_result "true" "$result"

echo -n "5. Bob -> DOC-001 (Bob lacks engineering, should DENY): "
result=$(curl -s -X POST "$BASE_URL/api/access-direct" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "bob", "document_id": "DOC-001"}' | jq -r '.granted')
check_result "false" "$result"

echo -n "6. Carol -> DOC-002 (Carol lacks finance, should DENY): "
result=$(curl -s -X POST "$BASE_URL/api/access-direct" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "carol", "document_id": "DOC-002"}' | jq -r '.granted')
check_result "false" "$result"

echo -n "7. Alice -> DOC-003 (Alice lacks admin, should DENY): "
result=$(curl -s -X POST "$BASE_URL/api/access-direct" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "alice", "document_id": "DOC-003"}' | jq -r '.granted')
check_result "false" "$result"

echo -n "8. Alice -> DOC-004 (Alice lacks hr, should DENY): "
result=$(curl -s -X POST "$BASE_URL/api/access-direct" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "alice", "document_id": "DOC-004"}' | jq -r '.granted')
check_result "false" "$result"

echo ""
echo "=== Delegated Access Tests ==="
echo ""

echo -n "9.  Alice -> GPT-4 -> DOC-001 (both have engineering, should GRANT): "
result=$(curl -s -X POST "$BASE_URL/api/access-delegated" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "alice", "agent_id": "gpt4", "document_id": "DOC-001"}' | jq -r '.granted')
check_result "true" "$result"

echo -n "10. Alice -> GPT-4 -> DOC-002 (both have finance, should GRANT): "
result=$(curl -s -X POST "$BASE_URL/api/access-delegated" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "alice", "agent_id": "gpt4", "document_id": "DOC-002"}' | jq -r '.granted')
check_result "true" "$result"

echo -n "11. Bob -> Claude -> DOC-003 (both have admin, should GRANT): "
result=$(curl -s -X POST "$BASE_URL/api/access-delegated" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "bob", "agent_id": "claude", "document_id": "DOC-003"}' | jq -r '.granted')
check_result "true" "$result"

echo -n "12. Carol -> Claude -> DOC-004 (both have hr, should GRANT): "
result=$(curl -s -X POST "$BASE_URL/api/access-delegated" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "carol", "agent_id": "claude", "document_id": "DOC-004"}' | jq -r '.granted')
check_result "true" "$result"

echo -n "13. GPT-4 -> DOC-001 (no user delegation, should DENY): "
result=$(curl -s -X POST "$BASE_URL/api/access-delegated" \
  -H "Content-Type: application/json" \
  -d '{"agent_id": "gpt4", "document_id": "DOC-001"}' | jq -r '.granted')
check_result "false" "$result"

echo -n "14. Alice -> Summarizer -> DOC-001 (Summarizer lacks engineering, should DENY): "
result=$(curl -s -X POST "$BASE_URL/api/access-delegated" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "alice", "agent_id": "summarizer", "document_id": "DOC-001"}' | jq -r '.granted')
check_result "false" "$result"

echo -n "15. Bob -> GPT-4 -> DOC-003 (GPT-4 lacks admin, should DENY): "
result=$(curl -s -X POST "$BASE_URL/api/access-delegated" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "bob", "agent_id": "gpt4", "document_id": "DOC-003"}' | jq -r '.granted')
check_result "false" "$result"

echo -n "16. Alice -> GPT-4 -> DOC-004 (neither has hr, should DENY): "
result=$(curl -s -X POST "$BASE_URL/api/access-delegated" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "alice", "agent_id": "gpt4", "document_id": "DOC-004"}' | jq -r '.granted')
check_result "false" "$result"

echo -n "17. Carol -> GPT-4 -> DOC-004 (GPT-4 lacks hr, should DENY): "
result=$(curl -s -X POST "$BASE_URL/api/access-delegated" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "carol", "agent_id": "gpt4", "document_id": "DOC-004"}' | jq -r '.granted')
check_result "false" "$result"

echo ""
echo "=============================================="
echo "  Tests Complete"
echo "=============================================="
