# riscv32-pipeline: 5-stage pipelined RV32I core in Verilog

A synthesizable 32-bit RISC-V (RV32I) processor with a classic five-stage pipeline
(IF, ID, EX, MEM, WB), a self-checking verification environment, and a
generic ASIC synthesis and timing flow (Yosys + OpenSTA, sky130 library).

Educational project. Not a product, not silicon-proven.

## Features

- RV32I base integer ISA, Verilog-2001 RTL, one module per file in `rtl/`
- Forwarding: EX/MEM to EX and MEM/WB to EX (EX/MEM has priority), register-file write-through bypass
- 1-cycle load-use stall; taken branches/jumps resolved in EX (2-cycle flush, predict not-taken)
- Priority: reset > redirect/flush > stall > normal advance
- Synchronous active-high reset everywhere
- Memories live outside the core (simple instruction/data ports, byte strobes on writes)
- Optional `TRACE=0` parameter removes trace-only pc/instr pipeline fields

## Instruction support

| Group | Instructions | Status |
|---|---|---|
| Upper immediate | LUI, AUIPC | Supported |
| Jumps | JAL, JALR | Supported |
| Branches | BEQ, BNE, BLT, BGE, BLTU, BGEU | Supported |
| Loads | LB, LH, LW, LBU, LHU | Supported |
| Stores | SB, SH, SW | Supported |
| ALU immediate | ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI | Supported |
| ALU register | ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND | Supported |
| FENCE | | Executes as NOP |
| ECALL, EBREAK, CSR instructions | | Unsupported (treated as NOP) |
| Traps, interrupts, exceptions | | Unsupported |
| Misaligned loads/stores | | Undefined behavior; tests never generate them |

## Repository layout

    rtl/        synthesizable Verilog (core and submodules)
    tb/         testbenches and the behavioral reference model
    programs/   directed assembly tests (p01..p04)
    scripts/    assembler, random generator, test and synthesis scripts
    docs/       architecture, verification, synthesis notes
    synthesis/  reports and constraints (netlist and liberty file are not tracked)

## Requirements

Icarus Verilog, Verilator (lint only), Yosys, OpenSTA, Python 3, GTKWave (optional).
Developed on Ubuntu under WSL with Icarus 12.0, Verilator 5.032, Yosys 0.52, OpenSTA 2.0.17.

## Run the tests

    ./scripts/run_unit_tests.sh        # 11 unit/module tests
    ./scripts/run_programs.sh          # 4 directed programs with scoreboard
    ./scripts/run_random.sh 200        # 200 constrained-random programs
    ./scripts/run_all.sh 200           # all of the above
    IVFLAGS="-Ptb_core.TRACE=0" ./scripts/run_random.sh 200 1   # trace-free configuration

## Verification results (measured)

| Suite | Result |
|---|---|
| Unit tests | 11/11 pass |
| Directed programs | 4/4 pass (127, 71, 68, 75 instructions) |
| Random programs | 1,200 seeds passed (200 at length 150, 1000 at length 250), about 308,000 instructions checked against the reference model |
| Example CPI | 1.181 on `p01_basic` (one program, not a benchmark) |

Every retired instruction is compared with an independent non-pipelined reference model
(PC, instruction, destination register, value); final registers and all of data memory
are compared at the end. See `docs/verification.md` for the gaps.

## Synthesis results (measured, pre-layout)

Flow: Yosys 0.52 + ABC mapped to sky130_fd_sc_hd (tt, 25 C, 1.8 V), OpenSTA 2.0.17,
ideal clock, no wire parasitics, 30% input/output delay assumption for external memories.

| Configuration | Flops | Area (um^2) | Meets timing at |
|---|---|---|---|
| Default (TRACE=1) | 1,632 | about 80,800 to 80,900 | about 11 ns in the Experiment 1 sweep |
| TRACE=0 | 1,497 | about 77,400 to 77,600 | about 10 ns in the same sweep |

Caveats: the timing results varied by about 1 ns between runs with tiny netlist changes
(ABC is not stable at that level), so treat the frequency as "roughly 90 to 100 MHz, pre-layout".
This is not post-layout data and says nothing about power. See `docs/synthesis.md`.
# riscv32-pipeline: 5-stage pipelined RV32I core in Verilog

A synthesizable 32-bit RISC-V (RV32I) processor with a classic five-stage pipeline
(IF, ID, EX, MEM, WB), a self-checking verification environment, and a
generic ASIC synthesis and timing flow (Yosys + OpenSTA, sky130 library).

Educational project. Not a product, not silicon-proven.

## Features

- RV32I base integer ISA, Verilog-2001 RTL, one module per file in `rtl/`
- Forwarding: EX/MEM to EX and MEM/WB to EX (EX/MEM has priority), register-file write-through bypass
- 1-cycle load-use stall; taken branches/jumps resolved in EX (2-cycle flush, predict not-taken)
- Priority: reset > redirect/flush > stall > normal advance
- Synchronous active-high reset everywhere
- Memories live outside the core (simple instruction/data ports, byte strobes on writes)
- Optional `TRACE=0` parameter removes trace-only pc/instr pipeline fields

## Instruction support

| Group | Instructions | Status |
|---|---|---|
| Upper immediate | LUI, AUIPC | Supported |
| Jumps | JAL, JALR | Supported |
| Branches | BEQ, BNE, BLT, BGE, BLTU, BGEU | Supported |
| Loads | LB, LH, LW, LBU, LHU | Supported |
| Stores | SB, SH, SW | Supported |
| ALU immediate | ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI | Supported |
| ALU register | ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND | Supported |
| FENCE | | Executes as NOP |
| ECALL, EBREAK, CSR instructions | | Unsupported (treated as NOP) |
| Traps, interrupts, exceptions | | Unsupported |
| Misaligned loads/stores | | Undefined behavior; tests never generate them |

## Repository layout

    rtl/        synthesizable Verilog (core and submodules)
    tb/         testbenches and the behavioral reference model
    programs/   directed assembly tests (p01..p04)
    scripts/    assembler, random generator, test and synthesis scripts
    docs/       architecture, verification, synthesis notes
    synthesis/  reports and constraints (netlist and liberty file are not tracked)

## Requirements

Icarus Verilog, Verilator (lint only), Yosys, OpenSTA, Python 3, GTKWave (optional).
Developed on Ubuntu under WSL with Icarus 12.0, Verilator 5.032, Yosys 0.52, OpenSTA 2.0.17.

## Run the tests

    ./scripts/run_unit_tests.sh        # 11 unit/module tests
    ./scripts/run_programs.sh          # 4 directed programs with scoreboard
    ./scripts/run_random.sh 200        # 200 constrained-random programs
    ./scripts/run_all.sh 200           # all of the above
    IVFLAGS="-Ptb_core.TRACE=0" ./scripts/run_random.sh 200 1   # trace-free configuration

## Verification results (measured)

| Suite | Result |
|---|---|
| Unit tests | 11/11 pass |
| Directed programs | 4/4 pass (127, 71, 68, 75 instructions) |
| Random programs | 1,200 seeds passed (200 at length 150, 1000 at length 250), about 308,000 instructions checked against the reference model |
| Example CPI | 1.181 on `p01_basic` (one program, not a benchmark) |

Every retired instruction is compared with an independent non-pipelined reference model
(PC, instruction, destination register, value); final registers and all of data memory
are compared at the end. See `docs/verification.md` for the gaps.

## Synthesis results (measured, pre-layout)

Flow: Yosys 0.52 + ABC mapped to sky130_fd_sc_hd (tt, 25 C, 1.8 V), OpenSTA 2.0.17,
ideal clock, no wire parasitics, 30% input/output delay assumption for external memories.

| Configuration | Flops | Area (um^2) | Meets timing at |
|---|---|---|---|
| Default (TRACE=1) | 1,632 | about 80,800 to 80,900 | about 11 ns in the Experiment 1 sweep |
| TRACE=0 | 1,497 | about 77,400 to 77,600 | about 10 ns in the same sweep |

Caveats: the timing results varied by about 1 ns between runs with tiny netlist changes
(ABC is not stable at that level), so treat the frequency as "roughly 90 to 100 MHz, pre-layout".
This is not post-layout data and says nothing about power. See `docs/synthesis.md`.

## Limitations

- RV32I only; no CSRs, traps, interrupts, M/A/C extensions
- Static predict-not-taken branching; no branch predictor, no caches, no bus protocol
- Combinational memory read model; real SRAM access time is not in the timing numbers
- Reference model and RTL were written by the same author; hand-computed checks in the
  directed programs partly guard against a shared misreading of the spec
- No functional-coverage measurement; passing tests mean no mismatch was found
- No place-and-route and no power numbers
## Limitations

- RV32I only; no CSRs, traps, interrupts, M/A/C extensions
- Static predict-not-taken branching; no branch predictor, no caches, no bus protocol
- Combinational memory read model; real SRAM access time is not in the timing numbers
- Reference model and RTL were written by the same author; hand-computed checks in the
  directed programs partly guard against a shared misreading of the spec
- No functional-coverage measurement; passing tests mean no mismatch was found
- No place-and-route and no power numbers
