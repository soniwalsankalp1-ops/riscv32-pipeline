// alu.v - purely combinational 32-bit ALU
// Shift amount is always b[4:0] (RV32I rule), regardless of XLEN.
`include "riscv_defs.vh"

module alu #(
    parameter XLEN = 32
) (
    input  wire [XLEN-1:0] a,
    input  wire [XLEN-1:0] b,
    input  wire [3:0]      alu_op,
    output reg  [XLEN-1:0] result
);

    wire [4:0] shamt = b[4:0];

    always @* begin
        case (alu_op)
            `ALU_ADD:   result = a + b;
            `ALU_SUB:   result = a - b;
            `ALU_SLL:   result = a << shamt;
            `ALU_SLT:   result = {{(XLEN-1){1'b0}}, ($signed(a) < $signed(b))};
            `ALU_SLTU:  result = {{(XLEN-1){1'b0}}, (a < b)};
            `ALU_XOR:   result = a ^ b;
            `ALU_SRL:   result = a >> shamt;
            `ALU_SRA:   result = $signed(a) >>> shamt;  // arithmetic shift
            `ALU_OR:    result = a | b;
            `ALU_AND:   result = a & b;
            `ALU_PASSB: result = b;
            default:    result = {XLEN{1'b0}};
        endcase
    end

endmodule
