#!/usr/bin/env bash
# Generic (library-free) Yosys synthesis of riscv_core.
# Produces gate/flop counts and a topological logic-depth report.
# NOT real area or timing: that needs a liberty file + STA (see docs).
cd "$(dirname "$0")/.." || exit 1
mkdir -p synthesis/reports
R=synthesis/reports
TOP=riscv_core
SRCS=$(ls rtl/*.v | tr "\n" " ")
RD="read_verilog -I rtl $SRCS; hierarchy -check -top $TOP"

echo "--- Run 1: hierarchical (per-module breakdown) ---"
yosys -l $R/hier.log -p "$RD; proc; opt; synth -top $TOP; check; tee -o $R/stat_hier.txt stat" > /dev/null 2>&1 \
    || { echo "YOSYS ERROR (see $R/hier.log)"; exit 1; }

echo "--- Run 2: flattened (whole-core totals, logic depth) ---"
yosys -l $R/flat.log -p "$RD; synth -top $TOP -flatten; check; tee -o $R/stat_flat.txt stat; tee -o $R/ltp.txt ltp -noff" > /dev/null 2>&1 \
    || { echo "YOSYS ERROR (see $R/flat.log)"; exit 1; }

{
  echo "tool   : $(yosys -V)"
  echo "commit : $(git rev-parse --short HEAD 2>/dev/null) (uncommitted changes may exist)"
  echo "flow   : generic synth, no liberty file, no timing constraints"
} > $R/info.txt

echo
echo "=== Cleanliness checks ==="
echo "latches inferred : $(grep -c 'DLATCH' $R/stat_flat.txt)   (expect 0)"
echo "yosys warnings   : $(grep -ci 'warning' $R/flat.log)   (expect 0; read them if not)"
echo "memory messages  : $(grep -ci 'memory' $R/flat.log)   (regfile handling, read build log if surprising)"
echo
echo "=== Flattened totals ==="
cat $R/stat_flat.txt
echo
echo "=== Longest topological path (cell levels, NOT nanoseconds) ==="
tail -n 25 $R/ltp.txt
echo
echo "=== Per-module summary (hierarchical run) ==="
grep -E "^=== |Number of cells|DFF|cells$" $R/stat_hier.txt | head -n 80
echo
cat $R/info.txt
