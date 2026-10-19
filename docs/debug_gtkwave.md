# Debugging with GTKWave

## Make a waveform

    iverilog -g2005 -Irtl -Itb -o build/tb_core.vvp rtl/*.v tb/tb_core.v
    python3 scripts/assemble.py programs/p01_basic.S -o build/p01_basic.hex
    vvp -n build/tb_core.vvp +hex=build/p01_basic.hex +vcd
    gtkwave build/core_tb.vcd

On WSL the GUI needs Windows 11 or WSLg. A text trace works everywhere:

    vvp -n build/tb_core.vvp +hex=build/p01_basic.hex +trace | head -40

Each trace line is one retired instruction: cycle, PC, instruction, destination, data.
A cycle gap of 1 extra between retires is a load-use stall; a gap of 2 is a taken
branch or jump.

## Signals to add (hierarchy tb_core.dut.*)

| What | Signals |
|---|---|
| PC and instruction | pc, ifid_pc, ifid_instr |
| Pipeline registers | idex_*, exmem_*, memwb_* |
| Register write | memwb_reg_write, memwb_rd, wb_data |
| ALU | alu_a, alu_b, idex_alu_op, ex_alu_result |
| Forwarding | fwd_a, fwd_b (0 regfile, 1 EX/MEM, 2 MEM/WB) |
| Stall and flush | pc_stall, ifid_stall, ifid_flush, idex_flush |
| Branch decision | ex_redirect, ex_redirect_target |
| Memory | dmem_addr, dmem_wdata, dmem_wstrb, dmem_re, dmem_rdata |

## Common failures

| Symptom | Where to look |
|---|---|
| Wrong branch target | ex_redirect_target vs idex_pc + idex_imm; JALR bit 0 cleared |
| Stale register value | fwd_a/fwd_b at the consumer cycle; regfile bypass |
| Wrong value with two writers of one register | forwarding priority: EX/MEM must beat MEM/WB |
| Instruction executes twice | stall not holding PC and IF/ID together |
| Flushed instruction still writes | idex_flush and the valid bit in ID/EX |
| Load result wrong | wb_sel, load_store_unit offset and sign extension |

## Using the scoreboard

A failing run prints the first mismatch with DUT and MODEL values side by side.
Find that PC in build/<name>.lst, then look at the cycles just before its retire.
For random failures, replay with the seed: build/random/r<seed>.hex.
