`timescale 1ns/1ps

module tb_branch_unit;
    reg  [31:0] a, b, alu_res;
    reg  [2:0]  f3;
    reg         br, jl, jr;
    wire        redirect;
    wire [31:0] target;
    integer errors, checks, i, j, k, m, n;
    reg [31:0] ra, rb;

    branch_unit #(.XLEN(32)) dut (
        .rs1_val(a), .rs2_val(b), .alu_result(alu_res), .funct3(f3),
        .branch(br), .jal(jl), .jalr(jr),
        .redirect(redirect), .redirect_target(target));

    // Independent reference: signed compare via sign bits, equality via XOR
    function ref_cond;
        input [31:0] fa;
        input [31:0] fb;
        input [2:0]  ff;
        reg eq, ltu, lts;
        begin
            eq  = ((fa ^ fb) == 32'd0);
            ltu = (fa < fb);
            lts = (fa[31] != fb[31]) ? fa[31] : ltu;
            case (ff)
                3'b000:  ref_cond = eq;
                3'b001:  ref_cond = ~eq;
                3'b100:  ref_cond = lts;
                3'b101:  ref_cond = ~lts;
                3'b110:  ref_cond = ltu;
                3'b111:  ref_cond = ~ltu;
                default: ref_cond = 1'b0;
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
                3'd6: edge_val = 32'h12345678;
                default: edge_val = 32'hAAAAAAAA;
            endcase
        end
    endfunction

    task chk;
        input [31:0] ta;
        input [31:0] tb2;
        input [2:0]  tf;
        input        tbr;
        input        tjl;
        input        tjr;
        input        exp_red;
        input [8*14-1:0] name;
        begin
            a = ta; b = tb2; f3 = tf; br = tbr; jl = tjl; jr = tjr;
            alu_res = 32'h00001235;       // odd on purpose: bit 0 must be cleared
            #1;
            checks = checks + 2;
            if (redirect !== exp_red) begin
                errors = errors + 1;
                $display("FAIL %0s redirect: a=%h b=%h f3=%b br=%b jal=%b jalr=%b got=%b exp=%b",
                         name, ta, tb2, tf, tbr, tjl, tjr, redirect, exp_red);
            end
            if (target !== 32'h00001234) begin
                errors = errors + 1;
                $display("FAIL %0s target: got=%h exp=00001234", name, target);
            end
        end
    endtask

    initial begin
        #5000000;
        $display("RESULT: FAIL (timeout)");
        $finish;
    end

    initial begin
        errors = 0; checks = 0;

        // ---- Directed (hand-written expectations): chk(a,b,f3, br,jal,jalr, expect) ----
        chk(32'd5, 32'd5, 3'b000, 1,0,0, 1, "beq equal");
        chk(32'd5, 32'd6, 3'b000, 1,0,0, 0, "beq differ");
        chk(32'd5, 32'd6, 3'b001, 1,0,0, 1, "bne differ");
        chk(32'd5, 32'd5, 3'b001, 1,0,0, 0, "bne equal");
        chk(32'hFFFFFFFF, 32'd1, 3'b100, 1,0,0, 1, "blt -1<1");
        chk(32'd1, 32'hFFFFFFFF, 3'b100, 1,0,0, 0, "blt 1<-1");
        chk(32'd5, 32'd5,        3'b100, 1,0,0, 0, "blt equal");
        chk(32'hFFFFFFFF, 32'd1, 3'b101, 1,0,0, 0, "bge -1>=1");
        chk(32'd5, 32'd5,        3'b101, 1,0,0, 1, "bge equal");
        chk(32'hFFFFFFFF, 32'd1, 3'b110, 1,0,0, 0, "bltu max<1");
        chk(32'd1, 32'hFFFFFFFF, 3'b110, 1,0,0, 1, "bltu 1<max");
        chk(32'hFFFFFFFF, 32'd1, 3'b111, 1,0,0, 1, "bgeu max>=1");
        chk(32'd5, 32'd5,        3'b111, 1,0,0, 1, "bgeu equal");
        chk(32'h80000000, 32'h7FFFFFFF, 3'b100, 1,0,0, 1, "blt min<max");
        chk(32'h80000000, 32'h7FFFFFFF, 3'b110, 1,0,0, 0, "bltu min<max");
        chk(32'd5, 32'd5, 3'b010, 1,0,0, 0, "invalid f3=2");
        chk(32'd5, 32'd5, 3'b011, 1,0,0, 0, "invalid f3=3");
        chk(32'd5, 32'd5, 3'b000, 0,0,0, 0, "not a branch");
        chk(32'd1, 32'd2, 3'b000, 0,1,0, 1, "jal");
        chk(32'd1, 32'd2, 3'b000, 0,0,1, 1, "jalr");

        // ---- Edge values x all funct3 x all {branch,jal,jalr} combos vs reference ----
        for (i = 0; i < 8; i = i + 1)
            for (j = 0; j < 8; j = j + 1)
                for (k = 0; k < 8; k = k + 1)
                    for (m = 0; m < 8; m = m + 1)
                        chk(edge_val(i), edge_val(j), k, m[2], m[1], m[0],
                            m[1] | m[0] | (m[2] & ref_cond(edge_val(i), edge_val(j), k)),
                            "edge sweep");

        // ---- Random operands, random alu_result (target low bit must be cleared) ----
        for (n = 0; n < 3000; n = n + 1) begin
            ra = $random; rb = $random;
            // bias half of the cases toward equal operands
            if (n % 2) rb = ra;
            for (k = 0; k < 8; k = k + 1)
                chk(ra, rb, k, 1, 0, 0, ref_cond(ra, rb, k), "random");
        end

        if (errors == 0) $display("RESULT: PASS (%0d checks)", checks);
        else             $display("RESULT: FAIL (%0d errors / %0d checks)", errors, checks);
        $finish;
    end
endmodule
