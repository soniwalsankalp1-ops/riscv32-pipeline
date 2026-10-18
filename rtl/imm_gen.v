// imm_gen.v - immediate extraction and sign extension (RV32I)
// Sign bit is always instr[31]. Unknown opcodes produce 0.
`include "riscv_defs.vh"

module imm_gen (
    input  wire [31:0] instr,
    output reg  [31:0] imm
);

    always @* begin
        case (instr[6:0])
            `OP_OPIMM, `OP_LOAD, `OP_JALR:   // I-type
                imm = {{20{instr[31]}}, instr[31:20]};
            `OP_STORE:                       // S-type
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            `OP_BRANCH:                      // B-type (bit 0 is always 0)
                imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            `OP_LUI, `OP_AUIPC:              // U-type
                imm = {instr[31:12], 12'b0};
            `OP_JAL:                         // J-type (bit 0 is always 0)
                imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            default:
                imm = 32'd0;
        endcase
    end

endmodule
