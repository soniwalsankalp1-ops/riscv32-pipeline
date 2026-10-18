`timescale 1ns/1ps

module tb_regfile;
    reg         clk, rst, we;
    reg  [4:0]  waddr, raddr1, raddr2;
    reg  [31:0] wdata;
    wire [31:0] rdata1, rdata2;
    integer errors, checks, i;

    regfile #(.XLEN(32)) dut (
        .clk(clk), .rst(rst), .we(we), .waddr(waddr), .wdata(wdata),
        .raddr1(raddr1), .raddr2(raddr2), .rdata1(rdata1), .rdata2(rdata2)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Unique per-register test pattern
    function [31:0] pat;
        input [7:0] n;
        begin
            pat = {n, 8'h5A, ~n, 8'hA5};
        end
    endfunction

    task expect32;
        input [31:0] got;
        input [31:0] expv;
        input [8*24-1:0] name;
        begin
            checks = checks + 1;
            if (got !== expv) begin
                errors = errors + 1;
                $display("FAIL %0s: got=%h exp=%h t=%0t", name, got, expv, $time);
            end
        end
    endtask

    // Write one register (drive on negedge, captured at following posedge)
    task write_reg;
        input [4:0]  a;
        input [31:0] d;
        begin
            @(negedge clk);
            we = 1'b1; waddr = a; wdata = d;
            @(negedge clk);
            we = 1'b0;
        end
    endtask

    task check_all_zero;
        input [8*24-1:0] name;
        integer r;
        begin
            for (r = 0; r < 32; r = r + 1) begin
                raddr1 = r; raddr2 = r; #1;
                expect32(rdata1, 32'd0, name);
                expect32(rdata2, 32'd0, name);
            end
        end
    endtask

    initial begin
        #1000000;
        $display("RESULT: FAIL (timeout)");
        $finish;
    end

    initial begin
        errors = 0; checks = 0;
        rst = 1'b1; we = 1'b0; waddr = 0; wdata = 0; raddr1 = 0; raddr2 = 0;
        repeat (2) @(negedge clk);
        rst = 1'b0;

        // 1. After reset everything reads zero
        check_all_zero("after reset");

        // 2. Basic write / read on both ports
        write_reg(5'd5, 32'hA5A5A5A5);
        raddr1 = 5'd5; raddr2 = 5'd0; #1;
        expect32(rdata1, 32'hA5A5A5A5, "write x5 port1");
        expect32(rdata2, 32'd0,        "x0 port2");
        raddr1 = 5'd0; raddr2 = 5'd5; #1;
        expect32(rdata1, 32'd0,        "x0 port1");
        expect32(rdata2, 32'hA5A5A5A5, "write x5 port2");

        // 3. x0 is write-protected
        write_reg(5'd0, 32'hFFFFFFFF);
        raddr1 = 5'd0; raddr2 = 5'd0; #1;
        expect32(rdata1, 32'd0, "x0 write ignored 1");
        expect32(rdata2, 32'd0, "x0 write ignored 2");

        // 4. Write every register x1..x31, read back through both ports
        for (i = 1; i < 32; i = i + 1)
            write_reg(i[4:0], pat(i[7:0]));
        for (i = 0; i < 32; i = i + 1) begin
            raddr1 = i[4:0];
            raddr2 = 5'd31 - i[4:0];
            #1;
            expect32(rdata1, (i == 0)  ? 32'd0 : pat(i[7:0]),        "readback port1");
            expect32(rdata2, (i == 31) ? 32'd0 : pat(8'd31 - i[7:0]), "readback port2");
        end

        // 5. Write-through bypass: read sees wdata in the same cycle
        write_reg(5'd7, 32'h11111111);
        @(negedge clk);
        we = 1'b1; waddr = 5'd7; wdata = 32'h22222222;
        raddr1 = 5'd7; raddr2 = 5'd7; #1;
        expect32(rdata1, 32'h22222222, "bypass port1");
        expect32(rdata2, 32'h22222222, "bypass port2");
        @(negedge clk);                 // posedge happened: value now stored
        we = 1'b0; #1;
        expect32(rdata1, 32'h22222222, "stored after bypass");

        // 6. we = 0 must not write
        @(negedge clk);
        we = 1'b0; waddr = 5'd9; wdata = 32'hDEADBEEF;
        @(negedge clk);
        raddr1 = 5'd9; #1;
        expect32(rdata1, pat(8'd9), "we=0 no write");

        // 7. Bypass must not leak into x0
        @(negedge clk);
        we = 1'b1; waddr = 5'd0; wdata = 32'hFFFFFFFF;
        raddr1 = 5'd0; #1;
        expect32(rdata1, 32'd0, "x0 no bypass");
        @(negedge clk);
        we = 1'b0;

        // 8. Reset in the middle of operation clears everything
        @(negedge clk);
        rst = 1'b1;
        @(negedge clk);
        rst = 1'b0;
        check_all_zero("mid-run reset");

        // 9. Write attempted during reset is ignored
        @(negedge clk);
        rst = 1'b1; we = 1'b1; waddr = 5'd3; wdata = 32'h12345678;
        raddr1 = 5'd3; #1;
        expect32(rdata1, 32'd0, "no bypass in reset");
        @(negedge clk);
        rst = 1'b0; we = 1'b0; #1;
        expect32(rdata1, 32'd0, "write during reset ignored");

        if (errors == 0) $display("RESULT: PASS (%0d checks)", checks);
        else             $display("RESULT: FAIL (%0d errors / %0d checks)", errors, checks);
        $finish;
    end
endmodule
