`timescale 1ns/1ps

module tb_core_smoke;
    reg         clk, rst;
    wire [31:0] imem_addr, imem_rdata, dmem_addr, dmem_wdata, dmem_rdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_re;
    wire        retire_valid, retire_we;
    wire [31:0] retire_pc, retire_instr, retire_data;
    wire [4:0]  retire_rd;

    reg [31:0] imem [0:255];
    reg [31:0] dmem [0:255];
    reg [31:0] wtmp;
    integer errors, checks, i;

    riscv_core #(.RESET_VECTOR(32'h00000000)) dut (
        .clk(clk), .rst(rst),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_wstrb(dmem_wstrb),
        .dmem_re(dmem_re), .dmem_rdata(dmem_rdata),
        .retire_valid(retire_valid), .retire_pc(retire_pc), .retire_instr(retire_instr),
        .retire_we(retire_we), .retire_rd(retire_rd), .retire_data(retire_data));

    // Behavioral memories: combinational read, byte-strobed synchronous write
    assign imem_rdata = imem[imem_addr[9:2]];
    assign dmem_rdata = dmem[dmem_addr[9:2]];

    always @(posedge clk) begin
        if (dmem_wstrb != 4'b0000) begin
            wtmp = dmem[dmem_addr[9:2]];
            if (dmem_wstrb[0]) wtmp[7:0]   = dmem_wdata[7:0];
            if (dmem_wstrb[1]) wtmp[15:8]  = dmem_wdata[15:8];
            if (dmem_wstrb[2]) wtmp[23:16] = dmem_wdata[23:16];
            if (dmem_wstrb[3]) wtmp[31:24] = dmem_wdata[31:24];
            dmem[dmem_addr[9:2]] <= wtmp;
        end
    end

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task check_reg;
        input integer idx;
        input [31:0]  expv;
        begin
            checks = checks + 1;
            if (dut.u_regfile.regs[idx] !== expv) begin
                errors = errors + 1;
                $display("FAIL x%0d: got=%h exp=%h", idx, dut.u_regfile.regs[idx], expv);
            end
        end
    endtask

    initial begin
        #100000;
        $display("RESULT: FAIL (timeout)");
        $finish;
    end

    initial begin
        $dumpfile("build/core_smoke.vcd");
        $dumpvars(0, tb_core_smoke);

        errors = 0; checks = 0;
        for (i = 0; i < 256; i = i + 1) begin
            imem[i] = 32'h00000013;   // NOP
            dmem[i] = 32'h00000000;
        end

        imem[0]  = 32'h00500093;  // addi x1,x0,5
        imem[1]  = 32'h00308113;  // addi x2,x1,3
        imem[2]  = 32'h001101B3;  // add  x3,x2,x1
        imem[3]  = 32'h00302023;  // sw   x3,0(x0)
        imem[4]  = 32'h00002203;  // lw   x4,0(x0)
        imem[5]  = 32'h004202B3;  // add  x5,x4,x4      (load-use)
        imem[6]  = 32'h00000663;  // beq  x0,x0,+12     (taken -> 36)
        imem[7]  = 32'h06300313;  // addi x6,x0,99      (flushed)
        imem[8]  = 32'h06400393;  // addi x7,x0,100     (flushed)
        imem[9]  = 32'h00700413;  // addi x8,x0,7
        imem[10] = 32'h008004EF;  // jal  x9,+8         (-> 48, x9 = 44)
        imem[11] = 32'h00100513;  // addi x10,x0,1      (flushed)
        imem[12] = 32'h00B00593;  // addi x11,x0,11
        imem[13] = 32'h00B48633;  // add  x12,x9,x11
        imem[14] = 32'h0000006F;  // jal  x0,0          (loop forever)

        rst = 1'b1;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        repeat (100) @(posedge clk);
        #1;

        // x0 has no storage (regs[0] is never written); it is checked through the read ports elsewhere
        check_reg(1,  32'd5);
        check_reg(2,  32'd8);
        check_reg(3,  32'd13);
        check_reg(4,  32'd13);
        check_reg(5,  32'd26);
        check_reg(6,  32'd0);    // flushed
        check_reg(7,  32'd0);    // flushed
        check_reg(8,  32'd7);
        check_reg(9,  32'd44);   // JAL link
        check_reg(10, 32'd0);    // flushed
        check_reg(11, 32'd11);
        check_reg(12, 32'd55);

        checks = checks + 1;
        if (dmem[0] !== 32'd13) begin
            errors = errors + 1;
            $display("FAIL dmem[0]: got=%h exp=0000000d", dmem[0]);
        end

        if (errors == 0) $display("RESULT: PASS (%0d checks)", checks);
        else             $display("RESULT: FAIL (%0d errors / %0d checks)", errors, checks);
        $finish;
    end
endmodule
