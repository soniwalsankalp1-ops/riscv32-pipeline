# Architecture

## Block diagram (text)

    PC -> IF -> [IF/ID] -> ID -> [ID/EX] -> EX -> [EX/MEM] -> MEM -> [MEM/WB] -> WB
     ^           decode+regfile             ALU+branch          data memory        |
     |                ^                          |                                  |
     |                +---- WB write / bypass ---+----------------------------------+
     +------------- redirect target (taken branch/jump, from EX) -------------------+

Memories are outside the core: instruction port (imem_addr/imem_rdata) and
data port (dmem_addr/dmem_wdata/dmem_wstrb/dmem_re/dmem_rdata).

## What each stage does

| Stage | Modules | Work |
|---|---|---|
| IF | pc_reg, if_id_reg | Fetch instruction at PC, PC+4 or redirect |
| ID | control_unit, imm_gen, regfile, hazard_unit, id_ex_reg | Decode, read registers (write-through bypass), detect load-use |
| EX | forwarding_unit, alu, branch_unit, ex_mem_reg | Forward operands, ALU, resolve branch/jump |
| MEM | load_store_unit, mem_wb_reg | Byte-strobed stores, aligned/sign-extended loads |
| WB | write-back mux, regfile | Select ALU / load data / PC+4 and write the register |

## Hazard handling

| Mechanism | Trigger | Action |
|---|---|---|
| Forwarding | EX source register equals rd of EX/MEM or MEM/WB writer (rd != x0) | Mux in EX; EX/MEM has priority over MEM/WB |
| Load-use stall | Load in EX, its rd equals rs1/rs2 of instruction in ID | Hold PC and IF/ID, bubble into ID/EX (1 cycle) |
| Redirect/flush | Taken branch or any jump in EX | Load PC with target, flush IF/ID and ID/EX (2 slots) |
| Register-file bypass | WB writes the register that ID reads in the same cycle | Read returns the write data |

Priority: reset > redirect/flush > stall > normal advance.
A load and a branch/jump cannot both be in EX, so stall and redirect never
truly overlap; the priority is still coded explicitly.

Unused source fields (LUI, AUIPC, JAL) are forced to x0 in ID so they never
cause false forwarding or false stalls.

## Timing diagrams

Forwarding, no stall:

    cycle:            1    2    3    4    5    6
    add x1,x2,x3      IF   ID   EX   MEM  WB
    sub x4,x1,x5           IF   ID   EX*  MEM  WB     * x1 from EX/MEM
    and x6,x1,x7                IF   ID   EX*  MEM    * x1 from MEM/WB
    or  x8,x1,x9                     IF   ID*  EX     * x1 via regfile bypass

Load-use (one bubble):

    cycle:            1    2    3    4    5    6    7
    lw  x1,0(x2)      IF   ID   EX   MEM  WB
    add x3,x1,x4           IF   ID   ID   EX*  MEM  WB   * x1 from MEM/WB
    bubble                           --   EX   MEM  WB

Taken branch (resolved in EX, two slots flushed):

    cycle:            1    2    3    4    5    6
    beq (taken)       IF   ID   EX*  MEM  WB          * redirect decided here
    i+1                    IF   ID   xx                (flushed)
    i+2                         IF   xx                (flushed)
    target                           IF   ID   EX

## Measured behavior

On `p01_basic` the testbench measured 127 retired instructions in 150 cycles
(CPI 1.181), with 3 load-use stall cycles and 11 taken redirects. This is one
program, not a benchmark.

## Known limits

- The EX/MEM link-value forwarding path for JAL/JALR cannot be exercised, because the
  instruction after a jump is always flushed. It is not claimed as verified.
- Misaligned accesses are undefined.
