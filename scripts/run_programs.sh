#!/usr/bin/env bash
# Assemble every programs/*.S and run it on the core with the scoreboard.
cd "$(dirname "$0")/.." || exit 1
mkdir -p build
overall=0

echo "--- Assembler self-test ---"
python3 scripts/assemble.py --selftest || exit 1

echo
echo "--- Compile core + scoreboard testbench ---"
if ! iverilog -g2005 $IVFLAGS -Irtl -Itb -o build/tb_core.vvp rtl/*.v tb/tb_core.v 2> build/tb_core.compile.log; then
    echo "COMPILE ERROR (see build/tb_core.compile.log)"
    exit 1
fi
echo "OK"

echo
echo "--- Programs ---"
for src in programs/*.S; do
    name=$(basename "$src" .S)
    printf '%-22s ' "$name"
    if ! python3 scripts/assemble.py "$src" -o "build/$name.hex" > "build/$name.asm.log" 2>&1; then
        echo "ASSEMBLE ERROR (see build/$name.asm.log)"
        overall=1
        continue
    fi
    timeout 120 vvp -n build/tb_core.vvp +hex="build/$name.hex" > "build/$name.log" 2>&1
    if grep -q "RESULT: PASS" "build/$name.log"; then
        grep "RESULT:" "build/$name.log"
    else
        echo "FAIL (see build/$name.log)"
        overall=1
    fi
done

echo
if [ $overall -eq 0 ]; then echo "ALL PROGRAMS PASSED"; else echo "SOME PROGRAMS FAILED"; fi
exit $overall
