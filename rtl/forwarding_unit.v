// forwarding_unit.v - operand forwarding select for the EX stage (combinational)
//
// For each source register of the instruction in EX:
//   1. EX/MEM holds a writer of that register  -> FWD_EXMEM  (youngest, wins)
//   2. else MEM/WB holds a writer              -> FWD_MEMWB
//   3. else                                    -> FWD_NONE (use register-file value)
// Never forward for x0 (it always reads zero).
// Bubbles have reg_write = 0, so they never forward.
`include "riscv_defs.vh"

module forwarding_unit (
    input  wire [4:0] ex_rs1,
    input  wire [4:0] ex_rs2,
    input  wire [4:0] exmem_rd,
    input  wire       exmem_reg_write,
    input  wire [4:0] memwb_rd,
    input  wire       memwb_reg_write,
    output reg  [1:0] fwd_a,
    output reg  [1:0] fwd_b
);

    wire exmem_ok = exmem_reg_write && (exmem_rd != 5'd0);
    wire memwb_ok = memwb_reg_write && (memwb_rd != 5'd0);

    always @* begin
        // Operand A (rs1). EX/MEM is checked first: it is the younger instruction.
        if (exmem_ok && (exmem_rd == ex_rs1))
            fwd_a = `FWD_EXMEM;
        else if (memwb_ok && (memwb_rd == ex_rs1))
            fwd_a = `FWD_MEMWB;
        else
            fwd_a = `FWD_NONE;

        // Operand B (rs2). Same priority.
        if (exmem_ok && (exmem_rd == ex_rs2))
            fwd_b = `FWD_EXMEM;
        else if (memwb_ok && (memwb_rd == ex_rs2))
            fwd_b = `FWD_MEMWB;
        else
            fwd_b = `FWD_NONE;
    end

endmodule
