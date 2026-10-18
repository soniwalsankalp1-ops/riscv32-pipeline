`timescale 1ns/1ps
`include "riscv_defs.vh"

module tb_control_unit;
    reg  [31:0] instr;
    wire        rw, sa, sb, mr, mw, br, jl, jr, ill;
    wire [3:0]  aop;
    wire [1:0]  wbs;
    integer errors, checks;

    control_unit dut (
        .instr(instr), .reg_write(rw), .alu_src_a(sa), .alu_src_b(sb),
        .alu_op(aop), .mem_read(mr), .mem_write(mw), .wb_sel(wbs),
        .branch(br), .jal(jl), .jalr(jr), .illegal(ill)
    );

    // Build an instruction: hi7 = instr[31:25], rs2=2, rs1=1, rd=3
    function [31:0] mk;
        input [6:0] hi7; input [2:0] f3; input [6:0] opc;
        mk = {hi7, 5'd2, 5'd1, f3, 5'd3, opc};
    endfunction

    // Compared vector: {reg_write, src_a, src_b, alu_op, mem_read, mem_write,
    //                   wb_sel, branch, jal, jalr, illegal}
    task chk;
        input [31:0] ins;
        input erw; input esa; input esb; input [3:0] eop;
        input emr; input emw; input [1:0] ewb;
        input ebr; input ejl; input ejr; input eill;
        input [8*12-1:0] name;
        begin
            instr = ins; #1;
            checks = checks + 1;
            if ({rw,sa,sb,aop,mr,mw,wbs,br,jl,jr,ill} !==
                {erw,esa,esb,eop,emr,emw,ewb,ebr,ejl,ejr,eill}) begin
                errors = errors + 1;
                $display("FAIL %0s: instr=%h", name, ins);
                $display("   got = %b", {rw,sa,sb,aop,mr,mw,wbs,br,jl,jr,ill});
                $display("   exp = %b", {erw,esa,esb,eop,emr,emw,ewb,ebr,ejl,ejr,eill});
                $display("   fields: rw sa sb aop mr mw wb br jal jalr ill");
            end
        end
    endtask

    // Shorthand for an illegal instruction: everything zero, illegal = 1
    task chk_ill;
        input [31:0] ins;
        input [8*12-1:0] name;
        begin
            chk(ins, 0,0,0,`ALU_ADD, 0,0,`WB_ALU, 0,0,0, 1, name);
        end
    endtask

    initial begin
        #1000000;
        $display("RESULT: FAIL (timeout)");
        $finish;
    end

    initial begin
        errors = 0; checks = 0;

        // ---------------- R-type ----------------
        chk(mk(7'b0000000,3'b000,`OP_OP), 1,0,0,`ALU_ADD,  0,0,`WB_ALU, 0,0,0,0, "add");
        chk(mk(7'b0100000,3'b000,`OP_OP), 1,0,0,`ALU_SUB,  0,0,`WB_ALU, 0,0,0,0, "sub");
        chk(mk(7'b0000000,3'b001,`OP_OP), 1,0,0,`ALU_SLL,  0,0,`WB_ALU, 0,0,0,0, "sll");
        chk(mk(7'b0000000,3'b010,`OP_OP), 1,0,0,`ALU_SLT,  0,0,`WB_ALU, 0,0,0,0, "slt");
        chk(mk(7'b0000000,3'b011,`OP_OP), 1,0,0,`ALU_SLTU, 0,0,`WB_ALU, 0,0,0,0, "sltu");
        chk(mk(7'b0000000,3'b100,`OP_OP), 1,0,0,`ALU_XOR,  0,0,`WB_ALU, 0,0,0,0, "xor");
        chk(mk(7'b0000000,3'b101,`OP_OP), 1,0,0,`ALU_SRL,  0,0,`WB_ALU, 0,0,0,0, "srl");
        chk(mk(7'b0100000,3'b101,`OP_OP), 1,0,0,`ALU_SRA,  0,0,`WB_ALU, 0,0,0,0, "sra");
        chk(mk(7'b0000000,3'b110,`OP_OP), 1,0,0,`ALU_OR,   0,0,`WB_ALU, 0,0,0,0, "or");
        chk(mk(7'b0000000,3'b111,`OP_OP), 1,0,0,`ALU_AND,  0,0,`WB_ALU, 0,0,0,0, "and");

        // ---------------- I-type ALU ----------------
        chk(mk(7'b1111111,3'b000,`OP_OPIMM), 1,0,1,`ALU_ADD,  0,0,`WB_ALU, 0,0,0,0, "addi neg");
        chk(mk(7'b0100000,3'b000,`OP_OPIMM), 1,0,1,`ALU_ADD,  0,0,`WB_ALU, 0,0,0,0, "addi bit30");
        chk(mk(7'b0000000,3'b010,`OP_OPIMM), 1,0,1,`ALU_SLT,  0,0,`WB_ALU, 0,0,0,0, "slti");
        chk(mk(7'b0000000,3'b011,`OP_OPIMM), 1,0,1,`ALU_SLTU, 0,0,`WB_ALU, 0,0,0,0, "sltiu");
        chk(mk(7'b0000000,3'b100,`OP_OPIMM), 1,0,1,`ALU_XOR,  0,0,`WB_ALU, 0,0,0,0, "xori");
        chk(mk(7'b0000000,3'b110,`OP_OPIMM), 1,0,1,`ALU_OR,   0,0,`WB_ALU, 0,0,0,0, "ori");
        chk(mk(7'b0000000,3'b111,`OP_OPIMM), 1,0,1,`ALU_AND,  0,0,`WB_ALU, 0,0,0,0, "andi");
        chk(mk(7'b0000000,3'b001,`OP_OPIMM), 1,0,1,`ALU_SLL,  0,0,`WB_ALU, 0,0,0,0, "slli");
        chk(mk(7'b0000000,3'b101,`OP_OPIMM), 1,0,1,`ALU_SRL,  0,0,`WB_ALU, 0,0,0,0, "srli");
        chk(mk(7'b0100000,3'b101,`OP_OPIMM), 1,0,1,`ALU_SRA,  0,0,`WB_ALU, 0,0,0,0, "srai");

        // ---------------- U / J ----------------
        chk(mk(7'b0000000,3'b000,`OP_LUI),   1,0,1,`ALU_PASSB, 0,0,`WB_ALU, 0,0,0,0, "lui");
        chk(mk(7'b0000000,3'b000,`OP_AUIPC), 1,1,1,`ALU_ADD,   0,0,`WB_ALU, 0,0,0,0, "auipc");
        chk(mk(7'b0000000,3'b000,`OP_JAL),   1,1,1,`ALU_ADD,   0,0,`WB_PC4, 0,1,0,0, "jal");
        chk(mk(7'b0000000,3'b000,`OP_JALR),  1,0,1,`ALU_ADD,   0,0,`WB_PC4, 0,0,1,0, "jalr");

        // ---------------- Branches ----------------
        chk(mk(7'b0000000,3'b000,`OP_BRANCH), 0,1,1,`ALU_ADD, 0,0,`WB_ALU, 1,0,0,0, "beq");
        chk(mk(7'b0000000,3'b001,`OP_BRANCH), 0,1,1,`ALU_ADD, 0,0,`WB_ALU, 1,0,0,0, "bne");
        chk(mk(7'b0000000,3'b100,`OP_BRANCH), 0,1,1,`ALU_ADD, 0,0,`WB_ALU, 1,0,0,0, "blt");
        chk(mk(7'b0000000,3'b101,`OP_BRANCH), 0,1,1,`ALU_ADD, 0,0,`WB_ALU, 1,0,0,0, "bge");
        chk(mk(7'b0000000,3'b110,`OP_BRANCH), 0,1,1,`ALU_ADD, 0,0,`WB_ALU, 1,0,0,0, "bltu");
        chk(mk(7'b0000000,3'b111,`OP_BRANCH), 0,1,1,`ALU_ADD, 0,0,`WB_ALU, 1,0,0,0, "bgeu");

        // ---------------- Loads / stores ----------------
        chk(mk(7'b0000000,3'b000,`OP_LOAD), 1,0,1,`ALU_ADD, 1,0,`WB_MEM, 0,0,0,0, "lb");
        chk(mk(7'b0000000,3'b001,`OP_LOAD), 1,0,1,`ALU_ADD, 1,0,`WB_MEM, 0,0,0,0, "lh");
        chk(mk(7'b0000000,3'b010,`OP_LOAD), 1,0,1,`ALU_ADD, 1,0,`WB_MEM, 0,0,0,0, "lw");
        chk(mk(7'b0000000,3'b100,`OP_LOAD), 1,0,1,`ALU_ADD, 1,0,`WB_MEM, 0,0,0,0, "lbu");
        chk(mk(7'b0000000,3'b101,`OP_LOAD), 1,0,1,`ALU_ADD, 1,0,`WB_MEM, 0,0,0,0, "lhu");
        chk(mk(7'b0000000,3'b000,`OP_STORE), 0,0,1,`ALU_ADD, 0,1,`WB_ALU, 0,0,0,0, "sb");
        chk(mk(7'b0000000,3'b001,`OP_STORE), 0,0,1,`ALU_ADD, 0,1,`WB_ALU, 0,0,0,0, "sh");
        chk(mk(7'b0000000,3'b010,`OP_STORE), 0,0,1,`ALU_ADD, 0,1,`WB_ALU, 0,0,0,0, "sw");

        // ---------------- FENCE = legal NOP ----------------
        chk(mk(7'b0000000,3'b000,`OP_FENCE), 0,0,0,`ALU_ADD, 0,0,`WB_ALU, 0,0,0,0, "fence");

        // ---------------- Illegal / unsupported ----------------
        chk_ill(32'h00000073,                          "ecall");
        chk_ill(32'h00000000,                          "all zeros");
        chk_ill(32'hFFFFFFFF,                          "all ones");
        chk_ill(mk(7'b0000001,3'b000,`OP_OP),          "mul (M ext)");
        chk_ill(mk(7'b0100000,3'b001,`OP_OP),          "sll alt f7");
        chk_ill(mk(7'b0100000,3'b001,`OP_OPIMM),       "slli bad f7");
        chk_ill(mk(7'b0000001,3'b101,`OP_OPIMM),       "srli bad f7");
        chk_ill(mk(7'b0000000,3'b010,`OP_BRANCH),      "branch f3=2");
        chk_ill(mk(7'b0000000,3'b011,`OP_LOAD),        "load f3=3");
        chk_ill(mk(7'b0000000,3'b110,`OP_LOAD),        "load f3=6");
        chk_ill(mk(7'b0000000,3'b100,`OP_STORE),       "store f3=4");
        chk_ill(mk(7'b0000000,3'b001,`OP_JALR),        "jalr f3=1");

        if (errors == 0) $display("RESULT: PASS (%0d checks)", checks);
        else             $display("RESULT: FAIL (%0d errors / %0d checks)", errors, checks);
        $finish;
    end
endmodule
