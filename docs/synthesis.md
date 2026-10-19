# Synthesis and timing

## Flow

Yosys 0.52 (synth, dfflibmap, abc) mapped to sky130_fd_sc_hd, typical corner
(tt, 25 C, 1.8 V), timing by OpenSTA 2.0.17 with an ideal clock, no wire parasitics,
and a 30% input/output delay assumption (my assumption, memories are outside the core).
ABC runs with synthesis/abc.constr (driving cell and load) so high-fanout nets get buffered.

Reproduce:

    wget -O synthesis/lib/sky130_fd_sc_hd__tt_025C_1v80.lib https://raw.githubusercontent.com/efabless/skywater-pdk-libs-sky130_fd_sc_hd/master/timing/sky130_fd_sc_hd__tt_025C_1v80.lib
    ./scripts/run_synth_lib.sh 10000
    PERIOD_NS=10 sta -no_splash -exit scripts/sta.tcl

## Measured results

| Item | Value |
|---|---|
| Generic synthesis | 0 latches, 0 warnings, 0 inferred memories |
| Flops (TRACE=1 / TRACE=0) | 1,632 / 1,497 |
| Area TRACE=1 | about 80,800 to 80,900 um^2 |
| Area TRACE=0 | about 77,400 to 77,600 um^2 |
| Flop share of area | about 52 to 53% |

## Experiments

1. TRACE=0 removes trace-only pc/instr pipeline fields: -135 flops, about -4% area.
   Stable across clock targets.
2. x0 without storage in the register file: no change in flop count, area change within
   noise. Hypothesis (32 fewer flops) was wrong; Yosys had already removed them.

## Timing: what can and cannot be claimed

- An early unbuffered netlist showed absurd slews (4 to 10 ns) from high-fanout nets;
  adding ABC constraints fixed it.
- Setup slack varied by about 1 ns between runs with tiny netlist changes. An early
  "met at 9 ns" result was not reproducible and is retired.
- Honest claim: roughly 10 to 11 ns (90 to 100 MHz), pre-layout, one corner.
- The critical path moved between runs, so no specific critical-path story is claimed.

## Not done

Place-and-route, clock tree, wire parasitics, multi-corner timing, power estimate.
OpenSTA 2.0.17 is old and warned about the library operating condition.
