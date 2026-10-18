`timescale 1ns/1ps
`include "riscv_defs.vh"

module tb_alu;
    reg  [31:0] a, b;
    reg  [3:0]  op;
    wire [31:0] y;
    integer errors, checks;
    integer i, j, k, n;
    reg [31:0] ra, rb;
    reg [3:0]  kop;

    alu #(.XLEN(32)) dut (.a(a), .b(b), .alu_op(op), .result(y));

    // Independent reference model: written with different identities than the RTL
    function [31:0] ref_alu;
        input [31:0] fa;
        input [31:0] fb;
        input [3:0]  fop;
        reg   [4:0]  sh;
        begin
            sh = fb[4:0];
            case (fop)
                `ALU_ADD:   ref_alu = fa + (~(~fb));
                `ALU_SUB:   ref_alu = fa + (~fb) + 32'd1;
                `ALU_SLL:   ref_alu = fa << sh;
                `ALU_SLT:   ref_alu = (fa[31] != fb[31]) ? {31'd0, fa[31]} : {31'd0, (fa < fb)};
                `ALU_SLTU:  ref_alu = {31'd0, (fa < fb)};
                `ALU_XOR:   ref_alu = (fa | fb) & ~(fa & fb);
                `ALU_SRL:   ref_alu = fa >> sh;
                `ALU_SRA:   ref_alu = fa[31] ? ~((~fa) >> sh) : (fa >> sh);
                `ALU_OR:    ref_alu = fa | fb;
                `ALU_AND:   ref_alu = fa & fb;
                `ALU_PASSB: ref_alu = fb;
                default:    ref_alu = 32'd0;
            endcase
        end
    endfunction

    function [31:0] edge_val;
        input [2:0] s;
        begin
            case (s)
                3'd0: edge_val = 32'h00000000;
                3'd1: edge_val = 32'h00000001;
                3'd2: edge_val = 32'hFFFFFFFF;
                3'd3: edge_val = 32'h80000000;
                3'd4: edge_val = 32'h7FFFFFFF;
                3'd5: edge_val = 32'h0000001F;
                3'd6: edge_val = 32'h00000020;
                default: edge_val = 32'hAAAAAAAA;
            endcase
        end
    endfunction

    task chk;
        input [31:0] ta;
        input [31:0] tb2;
        input [3:0]  top;
        input [31:0] expv;
        input [8*12-1:0] name;
        begin
            a = ta; b = tb2; op = top;
            #1;
            checks = checks + 1;
            if (y !== expv) begin
                errors = errors + 1;
                $display("FAIL %0s: op=%0d a=%h b=%h got=%h exp=%h", name, top, ta, tb2, y, expv);
            end
        end
    endtask

    // Timeout watchdog
    initial begin
        #5000000;
        $display("RESULT: FAIL (timeout)");
        $finish;
    end

    initial begin
        errors = 0; checks = 0;

        // ---- Directed edge cases (expected values written by hand) ----
        chk(32'h7FFFFFFF, 32'h00000001, `ALU_ADD,  32'h80000000, "add ovf");
        chk(32'hFFFFFFFF, 32'h00000001, `ALU_ADD,  32'h00000000, "add wrap");
        chk(32'h00000000, 32'h00000001, `ALU_SUB,  32'hFFFFFFFF, "sub neg");
        chk(32'h80000000, 32'h00000001, `ALU_SUB,  32'h7FFFFFFF, "sub ovf");
        chk(32'h00000001, 32'h0000001F, `ALU_SLL,  32'h80000000, "sll 31");
        chk(32'h00000001, 32'h00000020, `ALU_SLL,  32'h00000001, "sll mod32");
        chk(32'hFFFFFFFF, 32'h00000001, `ALU_SLT,  32'h00000001, "slt -1<1");
        chk(32'h00000001, 32'hFFFFFFFF, `ALU_SLT,  32'h00000000, "slt 1<-1");
        chk(32'h80000000, 32'h7FFFFFFF, `ALU_SLT,  32'h00000001, "slt min<max");
        chk(32'hFFFFFFFF, 32'h00000001, `ALU_SLTU, 32'h00000000, "sltu max<1");
        chk(32'h00000001, 32'hFFFFFFFF, `ALU_SLTU, 32'h00000001, "sltu 1<max");
        chk(32'h00000005, 32'h00000005, `ALU_SLT,  32'h00000000, "slt equal");
        chk(32'h80000000, 32'h0000001F, `ALU_SRL,  32'h00000001, "srl 31");
        chk(32'h80000000, 32'h0000001F, `ALU_SRA,  32'hFFFFFFFF, "sra 31");
        chk(32'h7FFFFFFF, 32'h00000004, `ALU_SRA,  32'h07FFFFFF, "sra pos");
        chk(32'hF0000000, 32'h00000004, `ALU_SRA,  32'hFF000000, "sra neg");
        chk(32'hFF00FF00, 32'h0FF00FF0, `ALU_XOR,  32'hF0F0F0F0, "xor");
        chk(32'hFF00FF00, 32'h0FF00FF0, `ALU_OR,   32'hFFF0FFF0, "or");
        chk(32'hFF00FF00, 32'h0FF00FF0, `ALU_AND,  32'h0F000F00, "and");
        chk(32'h12345678, 32'hDEADBEEF, `ALU_PASSB,32'hDEADBEEF, "passb");

        // ---- Exhaustive over edge values x all ops vs reference model ----
        for (i = 0; i < 8; i = i + 1)
            for (j = 0; j < 8; j = j + 1)
                for (k = 0; k <= 10; k = k + 1) begin
                    kop = k;
                    chk(edge_val(i), edge_val(j), kop,
                        ref_alu(edge_val(i), edge_val(j), kop), "edge x edge");
                end

        // ---- Random vs reference model ----
        for (n = 0; n < 2000; n = n + 1) begin
            ra = $random; rb = $random;
            for (k = 0; k <= 10; k = k + 1) begin
                kop = k;
                chk(ra, rb, kop, ref_alu(ra, rb, kop), "random");
            end
        end

        if (errors == 0) $display("RESULT: PASS (%0d checks)", checks);
        else             $display("RESULT: FAIL (%0d errors / %0d checks)", errors, checks);
        $finish;
    end
endmodule
