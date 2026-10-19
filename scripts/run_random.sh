#!/usr/bin/env bash
# Run constrained-random programs through the core + scoreboard.
# Usage: scripts/run_random.sh [count=100] [first_seed=1] [length=150]
# Failing seeds keep their files in build/random/ so they can be replayed.
cd "$(dirname "$0")/.." || exit 1
count=${1:-100}
first=${2:-1}
len=${3:-150}
mkdir -p build/random

if ! iverilog -g2005 -Irtl -Itb -o build/tb_core.vvp rtl/*.v tb/tb_core.v 2> build/tb_core.compile.log; then
    echo "COMPILE ERROR (see build/tb_core.compile.log)"
    exit 1
fi

pass=0; fail=0; total=0; failed=""
for ((s = first; s < first + count; s++)); do
    f=build/random/r$s
    if ! python3 scripts/gen_random.py --seed "$s" --length "$len" -o "$f.S" ||
       ! python3 scripts/assemble.py "$f.S" -o "$f.hex" > "$f.asm.log" 2>&1; then
        fail=$((fail + 1)); failed="$failed $s(gen/asm)"
        continue
    fi
    timeout 120 vvp -n build/tb_core.vvp +hex="$f.hex" > "$f.log" 2>&1
    if grep -q "RESULT: PASS" "$f.log"; then
        n=$(grep -o 'PASS ([0-9]*' "$f.log" | grep -o '[0-9]*')
        total=$((total + n))
        pass=$((pass + 1))
        rm -f "$f.S" "$f.hex" "$f.lst" "$f.log" "$f.asm.log"
    else
        fail=$((fail + 1)); failed="$failed $s"
    fi
done

echo "random seeds run: $count (first seed $first, length $len)"
echo "passed: $pass   failed: $fail   instructions checked: $total"
if [ $fail -ne 0 ]; then
    echo "failing seeds:$failed"
    echo "replay one:  vvp -n build/tb_core.vvp +hex=build/random/r<seed>.hex +trace | tail -30"
    echo "log:         cat build/random/r<seed>.log"
    exit 1
fi
echo "ALL RANDOM TESTS PASSED"
