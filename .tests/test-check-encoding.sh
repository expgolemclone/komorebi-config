#!/bin/bash
# Tests for check-encoding.sh
# Run from the project root.

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/check-encoding.sh"
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

pass=0
fail=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $label"
    ((pass++))
  else
    echo "  FAIL: $label (expected=$expected, actual=$actual)"
    ((fail++))
  fi
}

# --- Setup a temporary git repo ---
cd "$TMPDIR_TEST"
git init -q
git config user.email "test@test.com"
git config user.name "test"

# Initial commit so HEAD exists
echo "init" > init.txt
git add init.txt
git commit -q -m "init"

# --- Test 1: UTF-8 + LF file passes ---
echo "Test 1: UTF-8 LF file"
printf 'hello\nworld\n' > good.txt
git add good.txt
bash "$SCRIPT" > /dev/null 2>&1
assert_eq "UTF-8 LF passes" "0" "$?"

git reset -q HEAD good.txt
rm -f good.txt

# --- Test 2: CRLF file fails ---
echo "Test 2: CRLF file"
printf 'hello\r\nworld\r\n' > crlf.txt
git add crlf.txt
bash "$SCRIPT" > /dev/null 2>&1
assert_eq "CRLF detected" "1" "$?"

git reset -q HEAD crlf.txt
rm -f crlf.txt

# --- Test 3: No modified files passes ---
echo "Test 3: No modified files"
bash "$SCRIPT" > /dev/null 2>&1
assert_eq "No files passes" "0" "$?"

# --- Test 4: Japanese UTF-8 text passes ---
echo "Test 4: Japanese UTF-8"
printf '%s\n' '日本語テスト' > jp.txt
git add jp.txt
bash "$SCRIPT" > /dev/null 2>&1
assert_eq "Japanese UTF-8 passes" "0" "$?"

git reset -q HEAD jp.txt
rm -f jp.txt

# --- Test 5: Mixed (some good, one CRLF) fails ---
echo "Test 5: Mixed files"
printf 'good\n' > a.txt
printf 'bad\r\n' > b.txt
git add a.txt b.txt
bash "$SCRIPT" > /dev/null 2>&1
assert_eq "Mixed files fail" "1" "$?"

git reset -q HEAD a.txt b.txt
rm -f a.txt b.txt

# --- Summary ---
echo ""
echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
