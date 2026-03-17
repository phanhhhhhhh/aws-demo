#!/bin/bash
# =================================================================
# test-api.sh - Test toàn bộ API sau khi deploy
# Usage: ./test-api.sh http://your-alb-dns.amazonaws.com
# =================================================================

BASE_URL="${1:-http://localhost:8080}"
PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

check() {
  local name=$1
  local expected=$2
  local actual=$3
  if echo "$actual" | grep -q "$expected"; then
    echo -e "  ${GREEN}✓ PASS${NC} $name"
    ((PASS++))
  else
    echo -e "  ${RED}✗ FAIL${NC} $name"
    echo -e "    Expected to contain: ${YELLOW}$expected${NC}"
    echo -e "    Got: $actual"
    ((FAIL++))
  fi
}

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🧪 API Test Suite"
echo "  Base URL: ${BASE_URL}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 1. Health Check ───────────────────────────────────────────────
echo ""
echo "📋 Health Checks"
HEALTH=$(curl -s "${BASE_URL}/actuator/health")
check "Actuator health" '"status":"UP"' "$HEALTH"

INFO=$(curl -s "${BASE_URL}/api/public/health-info")
check "App health-info" '"status":"UP"' "$INFO"

# ── 2. Register ───────────────────────────────────────────────────
echo ""
echo "📝 Register"
TIMESTAMP=$(date +%s)
TEST_USER="testuser_${TIMESTAMP}"
TEST_EMAIL="test_${TIMESTAMP}@example.com"

REGISTER=$(curl -s -X POST "${BASE_URL}/api/auth/register" \
  -H "Content-Type: application/json" \
  -d "{
    \"username\": \"${TEST_USER}\",
    \"email\": \"${TEST_EMAIL}\",
    \"password\": \"password123\",
    \"fullName\": \"Test User ${TIMESTAMP}\"
  }")
check "Register new user" '"token"' "$REGISTER"
check "Register returns username" "\"username\":\"${TEST_USER}\"" "$REGISTER"
check "Register success message" "Registration successful" "$REGISTER"

TOKEN=$(echo $REGISTER | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

# Duplicate register
DUP=$(curl -s -X POST "${BASE_URL}/api/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${TEST_USER}\",\"email\":\"${TEST_EMAIL}\",\"password\":\"123456\"}")
check "Reject duplicate username" "already exists" "$DUP"

# Validation errors
INVALID=$(curl -s -X POST "${BASE_URL}/api/auth/register" \
  -H "Content-Type: application/json" \
  -d '{"username":"ab","email":"not-an-email","password":"123"}')
check "Validation: short username" "username" "$INVALID"
check "Validation: invalid email" "email" "$INVALID"

# ── 3. Login ──────────────────────────────────────────────────────
echo ""
echo "🔐 Login"
LOGIN=$(curl -s -X POST "${BASE_URL}/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${TEST_USER}\",\"password\":\"password123\"}")
check "Login success" '"token"' "$LOGIN"
check "Login returns message" "Login successful" "$LOGIN"

WRONG_LOGIN=$(curl -s -X POST "${BASE_URL}/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${TEST_USER}\",\"password\":\"wrongpassword\"}")
check "Reject wrong password" "Invalid username or password" "$WRONG_LOGIN"

WRONG_USER=$(curl -s -X POST "${BASE_URL}/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"nonexistent","password":"password"}')
check "Reject unknown user" "Invalid username or password" "$WRONG_USER"

# ── 4. Protected endpoints ────────────────────────────────────────
echo ""
echo "🔒 Protected Endpoints"
if [ -n "$TOKEN" ]; then
  PROFILE=$(curl -s "${BASE_URL}/api/users/me" \
    -H "Authorization: Bearer ${TOKEN}")
  check "Get my profile" "\"username\":\"${TEST_USER}\"" "$PROFILE"
  check "Profile has email" "\"email\":\"${TEST_EMAIL}\"" "$PROFILE"
else
  echo -e "  ${YELLOW}⚠ Skipped (no token)${NC}"
fi

NO_AUTH=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/users/me")
check "Reject no auth token (401)" "401" "$NO_AUTH"

FAKE_TOKEN=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/users/me" \
  -H "Authorization: Bearer fake.token.here")
check "Reject fake token (401)" "401" "$FAKE_TOKEN"

# ── Summary ───────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$((PASS + FAIL))
if [ $FAIL -eq 0 ]; then
  echo -e "  ${GREEN}✅ All ${TOTAL} tests passed!${NC}"
else
  echo -e "  ${RED}❌ ${FAIL}/${TOTAL} tests failed${NC}"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
