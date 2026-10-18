`timescale 1ns/1ps

module tb_pc_reg;
    reg         clk, rst, stall, redirect;
    reg  [31:0] target;
    wire [31:0] pc, pc_plus4, pc2, pc2_plus4;
    integer errors, checks, n;
    reg [31:0] exp_pc, exp_pc2;
    reg        r_rst, r_stall, r_red;
    reg [31:0] r;

    // dut uses reset vector 0, dut2 uses a non-zero reset vector
    pc_reg #(.XLEN(32), .RESET_VECTOR(32'h00000000)) dut (
        .clk(clk), .rst(rst), .stall(stall), .redirect(redirect),
        .redirect_target(target), .pc(pc), .pc_plus4(pc_plus4));
    pc_reg #(.XLEN(32), .RESET_VECTOR(32'h80000000)) dut2 (
        .clk(clk), .rst(rst), .stall(stall), .redirect(redirect),
        .redirect_target(target), .pc(pc2), .pc_plus4(pc2_plus4));

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task expect32;
        input [31:0] got;
        input [31:0] expv;
        input [8*20-1:0] name;
        begin
            checks = checks + 1;
            if (got !== expv) begin
                errors = errors + 1;
                $display("FAIL %0s: got=%h exp=%h t=%0t", name, got, expv, $time);
            end
        end
    endtask

    // One clock cycle with given inputs; updates the reference model and compares
    task step;
        input        s_rst;
        input        s_stall;
        input        s_red;
        input [31:0] s_target;
        begin
            rst = s_rst; stall = s_stall; redirect = s_red; target = s_target;
            @(posedge clk); #1;
            if (s_rst)        begin exp_pc = 32'h00000000; exp_pc2 = 32'h80000000; end
            else if (s_red)   begin exp_pc = s_target;     exp_pc2 = s_target;     end
            else if (!s_stall) begin exp_pc = exp_pc + 4;  exp_pc2 = exp_pc2 + 4;  end
            expect32(pc,  exp_pc,  "pc model");
            expect32(pc2, exp_pc2, "pc2 model");
            expect32(pc_plus4,  pc  + 32'd4, "pc_plus4");
            expect32(pc2_plus4, pc2 + 32'd4, "pc2_plus4");
        end
    endtask

    initial begin
        #5000000;
        $display("RESULT: FAIL (timeout)");
        $finish;
    end

    initial begin
        errors = 0; checks = 0;
        rst = 1'b1; stall = 1'b0; redirect = 1'b0; target = 32'd0;

        // ---- Directed tests with hand-written expectations ----
        step(1,0,0,32'd0);
        expect32(pc,  32'h00000000, "reset vector 0");
        expect32(pc2, 32'h80000000, "reset vector param");

        step(0,0,0,32'd0);  expect32(pc, 32'h00000004, "pc+4 #1");
        step(0,0,0,32'd0);  expect32(pc, 32'h00000008, "pc+4 #2");

        step(0,1,0,32'd0);
        step(0,1,0,32'd0);  expect32(pc, 32'h00000008, "stall holds");

        step(0,0,1,32'h00000100); expect32(pc, 32'h00000100, "redirect");
        step(0,0,0,32'd0);        expect32(pc, 32'h00000104, "after redirect");

        step(0,1,1,32'h00000200); expect32(pc, 32'h00000200, "redirect beats stall");
        step(1,0,1,32'h00000300); expect32(pc, 32'h00000000, "reset beats redirect");

        // ---- Random run vs reference model ----
        for (n = 0; n < 3000; n = n + 1) begin
            r = $random;
            r_rst   = (r[5:0]   == 6'd0);      // ~1.5%
            r_stall = (r[7:6]   == 2'd0);      // 25%
            r_red   = (r[10:8]  == 3'd0);      // 12.5%
            step(r_rst, r_stall, r_red, ($random & 32'hFFFFFFFC));
        end

        if (errors == 0) $display("RESULT: PASS (%0d checks)", checks);
        else             $display("RESULT: FAIL (%0d errors / %0d checks)", errors, checks);
        $finish;
    end
endmodule
