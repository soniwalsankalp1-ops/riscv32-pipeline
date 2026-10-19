# Verification

## Layers

| Layer | What it checks | Result (measured) |
|---|---|---|
| Unit tests (11) | alu, regfile, imm_gen, control_unit, branch_unit, pc_reg, load_store_unit, pipeline registers, forwarding_unit, hazard_unit, core smoke test | All pass |
| Directed programs (4) | Forwarding, load-use, control flow, sub-word memory, x0 handling, JAL/JALR, LUI/AUIPC | All pass (127, 71, 68, 75 instructions) |
| Random programs | Constrained-random streams, same scoreboard | 1,200 seeds passed, about 308,000 instructions |

## How the scoreboard works

tb/tb_core.v runs one assembled program on the core. Each time the core retires an
instruction, tb/rv32i_model.vh (a non-pipelined RV32I model) executes the same one and
the testbench compares PC, instruction word, destination register and value. At the end
it compares all registers and all of data memory. A store to address 0x7F0 ends the test.
Programs also carry hand-computed checks, so a shared misreading of the spec by model and
RTL would still be caught there. A 50,000-cycle timeout stops runaway simulations.

## Random generator rules

Branches and jumps only go forward, data accesses stay in 0x400-0x4FF and are aligned,
only legal instructions are produced, and every seed is reproducible.

## Bugs found

The only defect found by this environment so far was a wrong hand-written expected value
in tb_hazard_unit (the RTL was right). No RTL bugs were found by the regression.

## Gaps (honest list)

- No functional coverage measurement: passing means no mismatch was found.
- RTL and model were written by the same author.
- The scoreboard checks results and order, not cycle-exact stall counts.
- Random programs never loop backward; loops are covered only by p03.
- With TRACE=0, PC and instruction word are not compared per retire.
- Misaligned accesses, illegal-instruction traps and CSRs are not tested.
