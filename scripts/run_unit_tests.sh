#!/usr/bin/env bash
# Compile and run every unit testbench with Icarus Verilog.
# Also runs a (non-fatal) Verilator lint pass over the RTL.
# Format of each entry:  testname:rtl_file1 rtl_file2 ...
cd "$(dirname "$0")/.." || exit 1
mkdir -p build
overall=0

TESTS=(
  "alu:alu"
  "regfile:regfile"
  "imm_gen:imm_gen"
  "control_unit:control_unit"
  "branch_unit:branch_unit"
  "pc_reg:pc_reg"
  "load_store_unit:load_store_unit"
  "pipe_regs:if_id_reg id_ex_reg ex_mem_reg mem_wb_reg"
)

echo "--- Verilator lint (warnings are informational) ---"
for t in "${TESTS[@]}"; do
    files="${t#*:}"
    for f in $files; do
        verilator --lint-only -Wall -Wno-fatal -Irtl --top-module "$f" "rtl/$f.v" 2>&1 \
            | grep -E '^%(Warning|Error)' | head -n 10
    done
done

echo
echo "--- Unit tests (Icarus Verilog) ---"
for t in "${TESTS[@]}"; do
    name="${t%%:*}"
    files="${t#*:}"
    srcs=""
    for f in $files; do srcs="$srcs rtl/$f.v"; done
    printf '%-16s ' "$name"
    if ! iverilog -g2005 -Irtl -o "build/tb_$name.vvp" $srcs "tb/tb_$name.v" 2> "build/tb_$name.compile.log"; then
        echo "COMPILE ERROR (see build/tb_$name.compile.log)"
        overall=1
        continue
    fi
    timeout 120 vvp -n "build/tb_$name.vvp" > "build/tb_$name.log" 2>&1
    if grep -q "RESULT: PASS" "build/tb_$name.log"; then
        grep "RESULT:" "build/tb_$name.log"
    else
        echo "FAIL (see build/tb_$name.log)"
        overall=1
    fi
done

echo
if [ $overall -eq 0 ]; then echo "ALL UNIT TESTS PASSED"; else echo "SOME TESTS FAILED"; fi
exit $overall
