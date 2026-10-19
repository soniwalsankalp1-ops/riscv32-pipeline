#!/usr/bin/env bash
# Compare TRACE=0 vs TRACE=1: area, flops, setup slack, critical path endpoints.
# Usage: scripts/run_experiment.sh [target_ps=9000]
cd "$(dirname "$0")/.." || exit 1
mkdir -p synthesis/experiments
PS=${1:-9000}
NS=$(echo "scale=3; $PS/1000" | bc)
for t in 0 1; do
  echo "================ TRACE=$t  (target $NS ns) ================"
  TRACE=$t ./scripts/run_synth_lib.sh $PS > /dev/null || { echo "synthesis failed"; exit 1; }
  cp synthesis/reports/stat_lib.txt synthesis/experiments/stat_trace$t.txt
  echo "cells : $(grep -m1 'Number of cells' synthesis/reports/stat_lib.txt | awk '{print $NF}')"
  grep -m2 -E "Chip area|sequential" synthesis/reports/stat_lib.txt
  echo "flops : $(grep -Ec 'sky130_fd_sc_hd__e?dfxtp' synthesis/riscv_core_netlist.v)"
  PERIOD_NS=$NS sta -no_splash -exit scripts/sta.tcl 2>&1 \
     | tee synthesis/experiments/sta_trace$t.txt \
     | grep -E "Startpoint|Endpoint|slack \(" | head -4
done
