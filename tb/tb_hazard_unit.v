`timescale 1ns/1ps

module tb_hazard_unit;
    reg        mr, red;
    reg  [4:0] rd, rs1, rs2;
    wire       pcs, ids, iff, xf;
    integer errors, checks, a, b, c, d, e, n;
    reg [31:0] r;

    hazard_unit dut (
        .idex_mem_read(mr), .idex_rd(rd), .id_rs1(rs1), .id_rs2(rs2),
        .ex_redirect(red),
        .pc_stall(pcs), .ifid_stall(ids), .ifid_flush(iff), .idex_flush(xf));

    // Reference: returns {pc_stall, ifid_stall, ifid_flush, idex_flush}
    function [3:0] ref_out;
        input       fmr;
        input [4:0] frd;
        input [4:0] f1;
        input [4:0] f2;
        input       fred;
        reg lu;
        begin
            lu = 1'b0;
            if (fmr)
                if (frd != 5'd0)
                    if ((frd == f1) || (frd == f2))
                        lu = 1'b1;
            ref_out = {lu & ~fred, lu & ~fred, fred, fred | lu};
        end
    endfunction

    task chk;
        input       t_mr;
        input [4:0] t_rd;
        input [4:0] t_rs1;
        input [4:0] t_rs2;
        input       t_red;
        input [3:0] expv;
        input [8*16-1:0] name;
        begin
            mr = t_mr; rd = t_rd; rs1 = t_rs1; rs2 = t_rs2; red = t_red;
            #1;
            checks = checks + 1;
            if ({pcs, ids, iff, xf} !== expv) begin
                errors = errors + 1;
                $display("FAIL %0s: mr=%b rd=%0d rs1=%0d rs2=%0d red=%b got=%b exp=%b",
                         name, t_mr, t_rd, t_rs1, t_rs2, t_red, {pcs, ids, iff, xf}, expv);
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

        // ---- Directed, hand-written. Expected = {pc_stall, ifid_stall, ifid_flush, idex_flush}
        //      chk(mem_read, rd, rs1, rs2, redirect, expected)
        chk(1, 5'd5, 5'd5, 5'd1, 0, 4'b1101, "load-use rs1");
        chk(1, 5'd5, 5'd1, 5'd5, 0, 4'b1101, "load-use rs2");
        chk(1, 5'd5, 5'd3, 5'd4, 0, 4'b0000, "load, no dep");
        chk(1, 5'd0, 5'd0, 5'd0, 0, 4'b0000, "load to x0");
        chk(0, 5'd5, 5'd5, 5'd5, 0, 4'b0000, "not a load");
        chk(0, 5'd0, 5'd0, 5'd0, 1, 4'b0011, "redirect only");
        chk(1, 5'd5, 5'd5, 5'd5, 1, 4'b0011, "redirect beats stall");
        chk(0, 5'd0, 5'd0, 5'd0, 0, 4'b0000, "idle");

        // ---- Exhaustive: mem_read x rd{0,1,2} x rs1{0,1,2} x rs2{0,1,2} x redirect ----
        for (a = 0; a < 2; a = a + 1)
          for (b = 0; b < 3; b = b + 1)
            for (c = 0; c < 3; c = c + 1)
              for (d = 0; d < 3; d = d + 1)
                for (e = 0; e < 2; e = e + 1)
                    chk(a[0], b[4:0], c[4:0], d[4:0], e[0],
                        ref_out(a[0], b[4:0], c[4:0], d[4:0], e[0]), "exhaustive");

        // ---- Random with many collisions ----
        for (n = 0; n < 5000; n = n + 1) begin
            r = $random;
            chk(r[0], {2'd0, r[3:1]}, {2'd0, r[6:4]}, {2'd0, r[9:7]}, r[10],
                ref_out(r[0], {2'd0, r[3:1]}, {2'd0, r[6:4]}, {2'd0, r[9:7]}, r[10]),
                "random");
        end

        if (errors == 0) $display("RESULT: PASS (%0d checks)", checks);
        else             $display("RESULT: FAIL (%0d errors / %0d checks)", errors, checks);
        $finish;
    end
endmodule
