// riscv_defs.vh - shared constants for the RV32I core
`ifndef RISCV_DEFS_VH
`define RISCV_DEFS_VH

// Opcodes (instr[6:0])
`define OP_LUI    7'b0110111
`define OP_AUIPC  7'b0010111
`define OP_JAL    7'b1101111
`define OP_JALR   7'b1100111
`define OP_BRANCH 7'b1100011
`define OP_LOAD   7'b0000011
`define OP_STORE  7'b0100011
`define OP_OPIMM  7'b0010011
`define OP_OP     7'b0110011
`define OP_FENCE  7'b0001111
`define OP_SYSTEM 7'b1110011

// ALU operation codes
`define ALU_ADD   4'd0
`define ALU_SUB   4'd1
`define ALU_SLL   4'd2
`define ALU_SLT   4'd3
`define ALU_SLTU  4'd4
`define ALU_XOR   4'd5
`define ALU_SRL   4'd6
`define ALU_SRA   4'd7
`define ALU_OR    4'd8
`define ALU_AND   4'd9
`define ALU_PASSB 4'd10   // result = b (used by LUI)

// Write-back source select
`define WB_ALU    2'd0
`define WB_MEM    2'd1
`define WB_PC4    2'd2

// Forwarding select (operand source in EX)
`define FWD_NONE  2'd0    // value read from the register file in ID
`define FWD_EXMEM 2'd1    // from the EX/MEM register (younger instruction)
`define FWD_MEMWB 2'd2    // from the write-back value (older instruction)

`endif
