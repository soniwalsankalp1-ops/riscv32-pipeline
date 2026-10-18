// branch_unit.v - branch condition and redirect decision (used in EX)
//  redirect        = JAL | JALR | (branch & condition true)
//  redirect_target = ALU result with bit 0 cleared
//                    (branch/JAL: PC+imm, JALR: rs1+imm; the JALR rule clears bit 0)
// funct3 010/011 are not valid branches and are never taken.
module branch_unit #(
    parameter XLEN = 32
) (
    input  wire [XLEN-1:0] rs1_val,       // forwarded operand A
    input  wire [XLEN-1:0] rs2_val,       // forwarded operand B
    input  wire [XLEN-1:0] alu_result,
    input  wire [2:0]      funct3,
    input  wire            branch,
    input  wire            jal,
    input  wire            jalr,
    output wire            redirect,
    output wire [XLEN-1:0] redirect_target
);

    wire eq   = (rs1_val == rs2_val);
    wire lt_s = ($signed(rs1_val) < $signed(rs2_val));
    wire lt_u = (rs1_val < rs2_val);

    reg cond;
    always @* begin
        case (funct3)
            3'b000:  cond = eq;     // BEQ
            3'b001:  cond = ~eq;    // BNE
            3'b100:  cond = lt_s;   // BLT
            3'b101:  cond = ~lt_s;  // BGE
            3'b110:  cond = lt_u;   // BLTU
            3'b111:  cond = ~lt_u;  // BGEU
            default: cond = 1'b0;
        endcase
    end

    assign redirect        = jal | jalr | (branch & cond);
    assign redirect_target = {alu_result[XLEN-1:1], 1'b0};

endmodule
