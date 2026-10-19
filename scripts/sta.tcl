# OpenSTA script. Pre-layout, ideal clock, no wire parasitics.
# Usage: PERIOD_NS=10 sta -no_splash -exit scripts/sta.tcl
set period 10.0
if {[info exists ::env(PERIOD_NS)]} { set period $::env(PERIOD_NS) }

read_liberty synthesis/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_verilog synthesis/riscv_core_netlist.v
link_design riscv_core

create_clock -name clk -period $period [get_ports clk]
# Memories are outside the core: assume 30% of the period for external delay.
set_input_delay  [expr $period * 0.3] -clock clk [lsearch -inline -all -not -exact [all_inputs] [get_ports clk]]
set_output_delay [expr $period * 0.3] -clock clk [all_outputs]

puts "=== Clock period: $period ns ==="
report_checks -path_delay max -format full -digits 3
puts "=== Worst slack ==="
report_wns
report_tns
puts "=== Hold check ==="
report_checks -path_delay min -digits 3
