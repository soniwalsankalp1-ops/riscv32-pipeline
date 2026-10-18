// control_unit.v - instruction decoder (purely combinational)
//
// Conventions:
//  alu_src_a : 0 = rs1,  1 = PC
//  alu_src_b : 0 = rs2,  1 = immediate
//  ALU target trick: branches and JAL compute PC+imm in the ALU,
//                    JALR computes rs1+imm in the ALU.
//  wb_sel    : WB_ALU / WB_MEM / WB_PC4 (link value for JAL/JALR)
//  illegal   : unsupported or invalid encoding. All other outputs are forced
//              to zero so the instruction acts as a NOP. (FENCE is a legal
//              NOP; ECALL/EBREAK/CSR are flagged illegal = unsupported.)
`include "riscv_defs.vh"

module control_unit (
    input  wire [31:0] instr,
    output reg         reg_write,
    output reg         alu_src_a,
    output reg         alu_src_b,
    output reg  [3:0]  alu_op,
    output reg         mem_read,
    output reg         mem_write,
    output reg  [1:0]  wb_sel,
    output reg         branch,
    output reg         jal,
    output reg         jalr,
    output reg         illegal
);

    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];

    wire f7_zero = (funct7 == 7'b0000000);
    wire f7_alt  = (funct7 == 7'b0100000);   // SUB / SRA / SRAI

    always @* begin
        // Safe defaults = NOP
        reg_write = 1'b0;
        alu_src_a = 1'b0;
        alu_src_b = 1'b0;
        alu_op    = `ALU_ADD;
        mem_read  = 1'b0;
        mem_write = 1'b0;
        wb_sel    = `WB_ALU;
        branch    = 1'b0;
        jal       = 1'b0;
        jalr      = 1'b0;
        illegal   = 1'b0;

        case (opcode)
            `OP_LUI: begin
                reg_write = 1'b1; alu_src_b = 1'b1; alu_op = `ALU_PASSB;
            end

            `OP_AUIPC: begin
                reg_write = 1'b1; alu_src_a = 1'b1; alu_src_b = 1'b1; alu_op = `ALU_ADD;
            end

            `OP_JAL: begin
                reg_write = 1'b1; alu_src_a = 1'b1; alu_src_b = 1'b1; alu_op = `ALU_ADD;
                wb_sel = `WB_PC4; jal = 1'b1;
            end

            `OP_JALR: begin
                reg_write = 1'b1; alu_src_b = 1'b1; alu_op = `ALU_ADD;
                wb_sel = `WB_PC4; jalr = 1'b1;
                if (funct3 != 3'b000) illegal = 1'b1;
            end

            `OP_BRANCH: begin
                branch = 1'b1; alu_src_a = 1'b1; alu_src_b = 1'b1; alu_op = `ALU_ADD;
                if (funct3[2:1] == 2'b01) illegal = 1'b1;   // funct3 = 010, 011
            end

            `OP_LOAD: begin
                reg_write = 1'b1; alu_src_b = 1'b1; alu_op = `ALU_ADD;
                mem_read = 1'b1; wb_sel = `WB_MEM;
                if (funct3 == 3'b011 || funct3[2:1] == 2'b11) illegal = 1'b1;
            end

            `OP_STORE: begin
                alu_src_b = 1'b1; alu_op = `ALU_ADD; mem_write = 1'b1;
                if (funct3[2] || funct3 == 3'b011) illegal = 1'b1;
            end

            `OP_OPIMM: begin
                reg_write = 1'b1; alu_src_b = 1'b1;
                case (funct3)
                    3'b000: alu_op = `ALU_ADD;   // never SUB: instr[30] is part of the immediate
                    3'b010: alu_op = `ALU_SLT;
                    3'b011: alu_op = `ALU_SLTU;
                    3'b100: alu_op = `ALU_XOR;
                    3'b110: alu_op = `ALU_OR;
                    3'b111: alu_op = `ALU_AND;
                    3'b001: begin
                        alu_op = `ALU_SLL;
                        if (!f7_zero) illegal = 1'b1;
                    end
                    default: begin   // 3'b101
                        if (f7_zero)     alu_op = `ALU_SRL;
                        else if (f7_alt) alu_op = `ALU_SRA;
                        else             illegal = 1'b1;
                    end
                endcase
            end

            `OP_OP: begin
                reg_write = 1'b1;
                case (funct3)
                    3'b000:  alu_op = f7_alt ? `ALU_SUB : `ALU_ADD;
                    3'b001:  alu_op = `ALU_SLL;
                    3'b010:  alu_op = `ALU_SLT;
                    3'b011:  alu_op = `ALU_SLTU;
                    3'b100:  alu_op = `ALU_XOR;
                    3'b101:  alu_op = f7_alt ? `ALU_SRA : `ALU_SRL;
                    3'b110:  alu_op = `ALU_OR;
                    default: alu_op = `ALU_AND;   // 3'b111
                endcase
                // funct7 must be 0, except 0100000 for SUB (000) and SRA (101)
                if (!f7_zero && !(f7_alt && (funct3 == 3'b000 || funct3 == 3'b101)))
                    illegal = 1'b1;
            end

            `OP_FENCE: begin
                // Legal NOP (single hart, in-order, no cache)
            end

            default: illegal = 1'b1;   // includes SYSTEM (ECALL/EBREAK/CSR)
        endcase

        // Illegal instructions must have no side effects
        if (illegal) begin
            reg_write = 1'b0; alu_src_a = 1'b0; alu_src_b = 1'b0; alu_op = `ALU_ADD;
            mem_read  = 1'b0; mem_write = 1'b0; wb_sel = `WB_ALU;
            branch    = 1'b0; jal = 1'b0; jalr = 1'b0;
        end
    end

endmodule
