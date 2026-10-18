`timescale 1ns/1ps

module tb_forwarding_unit;
    reg  [4:0] rs1, rs2, mrd, wrd;
    reg        mwe, wwe;
    wire [1:0] fa, fb;
    integer errors, checks, i, j, k, l, m, n;
    reg [31:0] r;

    forwarding_unit dut (
        .ex_rs1(rs1), .ex_rs2(rs2),
        .exmem_rd(mrd), .exmem_reg_write(mwe),
        .memwb_rd(wrd), .memwb_reg_write(wwe),
        .fwd_a(fa), .fwd_b(fb));

    // Independent reference: later assignment overrides earlier one, so the
    // youngest instruction (EX/MEM) is applied last and wins.
    function [1:0] ref_fwd;
        input [4:0] rs;
        input [4:0] frd_m;
        input       fwe_m;
        input [4:0] frd_w;
        input       fwe_w;
        begin
            ref_fwd = 2'd0;
            if (rs != 5'd0) begin
                if (fwe_w && (frd_w == rs)) ref_fwd = 2'd2;
                if (fwe_m && (frd_m == rs)) ref_fwd = 2'd1;
            end
        end
    endfunction

    function [4:0] regval;     // 0,1,2 and 31
        input [1:0] s;
        begin
            regval = (s == 2'd3) ? 5'd31 : {3'd0, s};
        end
    endfunction

    task chk;
        input [4:0] t_rs1;
        input [4:0] t_rs2;
        input [4:0] t_mrd;
        input       t_mwe;
        input [4:0] t_wrd;
        input       t_wwe;
        input [1:0] exp_a;
        input [1:0] exp_b;
        input [8*16-1:0] name;
        begin
            rs1 = t_rs1; rs2 = t_rs2; mrd = t_mrd; mwe = t_mwe; wrd = t_wrd; wwe = t_wwe;
            #1;
            checks = checks + 2;
            if (fa !== exp_a) begin
                errors = errors + 1;
                $display("FAIL %0s fwd_a: rs1=%0d rs2=%0d mrd=%0d/%b wrd=%0d/%b got=%b exp=%b",
                         name, t_rs1, t_rs2, t_mrd, t_mwe, t_wrd, t_wwe, fa, exp_a);
            end
            if (fb !== exp_b) begin
                errors = errors + 1;
                $display("FAIL %0s fwd_b: rs1=%0d rs2=%0d mrd=%0d/%b wrd=%0d/%b got=%b exp=%b",
                         name, t_rs1, t_rs2, t_mrd, t_mwe, t_wrd, t_wwe, fb, exp_b);
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

        // ---- Directed, hand-written expectations ----
        //  chk(rs1, rs2, exmem_rd, exmem_we, memwb_rd, memwb_we, exp_a, exp_b)
        chk(5'd1, 5'd2, 5'd9, 1, 5'd8, 1, 2'd0, 2'd0, "no match");
        chk(5'd1, 5'd2, 5'd1, 1, 5'd8, 1, 2'd1, 2'd0, "exmem rs1");
        chk(5'd1, 5'd2, 5'd2, 1, 5'd8, 1, 2'd0, 2'd1, "exmem rs2");
        chk(5'd1, 5'd2, 5'd9, 1, 5'd1, 1, 2'd2, 2'd0, "memwb rs1");
        chk(5'd1, 5'd2, 5'd9, 1, 5'd2, 1, 2'd0, 2'd2, "memwb rs2");
        chk(5'd1, 5'd2, 5'd1, 1, 5'd1, 1, 2'd1, 2'd0, "both: exmem wins");
        chk(5'd3, 5'd3, 5'd3, 1, 5'd3, 1, 2'd1, 2'd1, "both ops, both hit");
        chk(5'd1, 5'd2, 5'd1, 0, 5'd1, 0, 2'd0, 2'd0, "write disabled");
        chk(5'd1, 5'd2, 5'd1, 0, 5'd1, 1, 2'd2, 2'd0, "exmem we=0 -> memwb");
        chk(5'd0, 5'd0, 5'd0, 1, 5'd0, 1, 2'd0, 2'd0, "x0 never forwarded");
        chk(5'd1, 5'd2, 5'd1, 1, 5'd2, 1, 2'd1, 2'd2, "split A/B");
        chk(5'd1, 5'd2, 5'd2, 1, 5'd1, 1, 2'd2, 2'd1, "split B/A");
        chk(5'd31,5'd31,5'd31,1, 5'd0, 1, 2'd1, 2'd1, "x31");

        // ---- Exhaustive over {x0,x1,x2,x31} for all 4 addresses and both enables ----
        for (i = 0; i < 4; i = i + 1)
          for (j = 0; j < 4; j = j + 1)
            for (k = 0; k < 4; k = k + 1)
              for (l = 0; l < 4; l = l + 1)
                for (m = 0; m < 4; m = m + 1)
                    chk(regval(i[1:0]), regval(j[1:0]),
                        regval(k[1:0]), m[1],
                        regval(l[1:0]), m[0],
                        ref_fwd(regval(i[1:0]), regval(k[1:0]), m[1], regval(l[1:0]), m[0]),
                        ref_fwd(regval(j[1:0]), regval(k[1:0]), m[1], regval(l[1:0]), m[0]),
                        "exhaustive");

        // ---- Random with lots of collisions (register numbers 0..7) ----
        for (n = 0; n < 5000; n = n + 1) begin
            r = $random;
            chk({2'd0, r[2:0]}, {2'd0, r[5:3]},
                {2'd0, r[8:6]}, r[9], {2'd0, r[12:10]}, r[13],
                ref_fwd({2'd0, r[2:0]}, {2'd0, r[8:6]}, r[9], {2'd0, r[12:10]}, r[13]),
                ref_fwd({2'd0, r[5:3]}, {2'd0, r[8:6]}, r[9], {2'd0, r[12:10]}, r[13]),
                "random");
        end

        if (errors == 0) $display("RESULT: PASS (%0d checks)", checks);
        else             $display("RESULT: FAIL (%0d errors / %0d checks)", errors, checks);
        $finish;
    end
endmodule
