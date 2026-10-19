#!/usr/bin/env bash
# One-command regression: unit tests + directed programs + random seeds.
# Usage: scripts/run_all.sh [random_count=100]
cd "$(dirname "$0")/.." || exit 1
rc=0

echo "=== 1/3 unit tests ==="
./scripts/run_unit_tests.sh | grep -E "RESULT|FAIL|ALL|SOME|COMPILE"
[ "${PIPESTATUS[0]}" -eq 0 ] || rc=1

echo
echo "=== 2/3 directed programs ==="
./scripts/run_programs.sh | grep -E "RESULT|FAIL|ALL|SOME|ERROR|self-test"
[ "${PIPESTATUS[0]}" -eq 0 ] || rc=1

echo
echo "=== 3/3 random programs ==="
./scripts/run_random.sh "${1:-100}"
[ $? -eq 0 ] || rc=1

echo
if [ $rc -eq 0 ]; then echo "REGRESSION PASSED"; else echo "REGRESSION FAILED"; fi
exit $rc
