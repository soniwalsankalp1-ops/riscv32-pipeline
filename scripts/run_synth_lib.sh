#!/usr/bin/env bash
# Yosys synthesis mapped to sky130_fd_sc_hd (typical corner).
# Usage: scripts/run_synth_lib.sh [target_period_ps=10000]
# Area is from the liberty file. Timing is NOT reported here: use STA (run_sta.sh).
cd "$(dirname "$0")/.." || exit 1
LIB=synthesis/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
R=synthesis/reports
PERIOD=${1:-10000}
[ -f "$LIB" ] || { echo "missing $LIB"; exit 1; }
mkdir -p $R
SRCS=$(ls rtl/*.v | tr "\n" " ")

yosys -l $R/lib_synth.log -p "
read_liberty -overwrite -setattr liberty_cell -lib $LIB
read_verilog -I rtl $SRCS
chparam -set TRACE ${TRACE:-1} riscv_core
hierarchy -check -top riscv_core
synth -top riscv_core -flatten
dfflibmap -liberty $LIB
abc -liberty $LIB -constr synthesis/abc.constr -D $PERIOD
opt_clean -purge
check
tee -o $R/stat_lib.txt stat -liberty $LIB
write_verilog -noattr synthesis/riscv_core_netlist.v
" > /dev/null 2>&1 || { echo "YOSYS ERROR (see $R/lib_synth.log)"; exit 1; }

{
  echo "tool    : $(yosys -V)"
  echo "library : $(basename $LIB)  (typical corner)"
  echo "abc -D  : $PERIOD ps (synthesis target only, not a timing result)"
  echo "commit  : $(git rev-parse --short HEAD 2>/dev/null)"
} > $R/info_lib.txt

grep -E "Number of cells|Chip area|sequential" $R/stat_lib.txt | tail -5
echo
cat $R/info_lib.txt
