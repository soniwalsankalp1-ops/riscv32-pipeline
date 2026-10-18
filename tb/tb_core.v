`timescale 1ns/1ps
// tb_core.v - runs one assembled program on the core and checks it against
// the reference model (scoreboard).
//   vvp build/tb_core.vvp +hex=build/prog.hex [+trace] [+vcd]
//
// Every instruction the core retires is compared with the model: PC,
// instruction word, destination register and value. When the model sees the
// store to 'tohost' the final registers and ALL of data memory are compared.

module tb_core;
    localparam [31:0] RESET_VECTOR = 32'h00000000;
    localparam integer MAX_CYCLES  = 50000;

    reg         clk, rst;
    wire [31:0] imem_addr, imem_rdata, dmem_addr, dmem_wdata, dmem_rdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_re;
    wire        retire_valid, retire_we;
    wire [31:0] retire_pc, retire_instr, retire_data;
    wire [4:0]  retire_rd;

    reg [31:0] imem [0:1023];
    reg [31:0] dmem [0:1023];
    reg [31:0] wtmp;
    reg [8*256-1:0] hexfile;

    integer i, retired, total_cycles, first_cycle, stall_cycles, redirect_cycles, span;
    reg     seen_first, finished, trace, mism;
    real    cpi;

    `include "rv32i_model.vh"

    riscv_core #(.RESET_VECTOR(RESET_VECTOR)) dut (
        .clk(clk), .rst(rst),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_wstrb(dmem_wstrb),
        .dmem_re(dmem_re), .dmem_rdata(dmem_rdata),
        .retire_valid(retire_valid), .retire_pc(retire_pc), .retire_instr(retire_instr),
        .retire_we(retire_we), .retire_rd(retire_rd), .retire_data(retire_data));

    // Behavioral memories: combinational read, byte-strobed synchronous write
    assign imem_rdata = imem[imem_addr[11:2]];
    assign dmem_rdata = dmem[dmem_addr[11:2]];

    always @(posedge clk) begin
        if (dmem_wstrb != 4'b0000) begin
            wtmp = dmem[dmem_addr[11:2]];
            if (dmem_wstrb[0]) wtmp[7:0]   = dmem_wdata[7:0];
            if (dmem_wstrb[1]) wtmp[15:8]  = dmem_wdata[15:8];
            if (dmem_wstrb[2]) wtmp[23:16] = dmem_wdata[23:16];
            if (dmem_wstrb[3]) wtmp[31:24] = dmem_wdata[31:24];
            dmem[dmem_addr[11:2]] <= wtmp;
        end
    end

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task finish_fail;
        input [8*48-1:0] msg;
        begin
            finished = 1'b1;
            $display("RESULT: FAIL (%0s)", msg);
            $finish;
        end
    endtask

    // Called when the model has executed the tohost store (all older
    // instructions have retired and been compared one by one).
    task end_of_test;
        integer w, bad;
        reg [31:0] mw;
        begin
            bad = 0;
            if (m_tohost_val !== 32'd0) begin
                bad = bad + 1;
                $display("FAIL: program self-check failed, tohost value = %0d (see 'fail' label in the .S file)",
                         m_tohost_val);
            end
            for (w = 1; w < 32; w = w + 1)
                if (dut.u_regfile.regs[w] !== m_regs[w]) begin
                    bad = bad + 1;
                    if (bad < 10)
                        $display("FAIL: final x%0d DUT=%h MODEL=%h", w, dut.u_regfile.regs[w], m_regs[w]);
                end
            for (w = 0; w < 1024; w = w + 1) begin
                mw = {m_mem[4*w+3], m_mem[4*w+2], m_mem[4*w+1], m_mem[4*w]};
                if (dmem[w] !== mw) begin
                    bad = bad + 1;
                    if (bad < 10)
                        $display("FAIL: final dmem[0x%03h] DUT=%h MODEL=%h", w*4, dmem[w], mw);
                end
            end
            finished = 1'b1;
            if (bad == 0) begin
                span = total_cycles - first_cycle + 1;
                cpi = span;
                cpi = cpi / retired;
                $display("  retired instructions         : %0d", retired);
                $display("  cycles (first..last retire)  : %0d", span);
                $display("  CPI measured in this run     : %0.3f", cpi);
                $display("  cycles with PC stalled       : %0d (load-use)", stall_cycles);
                $display("  taken branch/jump redirects  : %0d", redirect_cycles);
                $display("RESULT: PASS (%0d instructions checked against the reference model)", retired);
            end else begin
                $display("RESULT: FAIL (%0d final-state problems)", bad);
            end
            $finish;
        end
    endtask

    // ---------------- scoreboard: runs on the falling edge, when DUT outputs are stable
    always @(negedge clk) begin
        total_cycles = total_cycles + 1;
        if (!finished) begin
            if (total_cycles > MAX_CYCLES) begin
                finish_fail("timeout: program never reached tohost");
            end else begin
                if (seen_first) begin
                    if (dut.pc_stall    === 1'b1) stall_cycles    = stall_cycles + 1;
                    if (dut.ex_redirect === 1'b1) redirect_cycles = redirect_cycles + 1;
                end
                if (retire_valid === 1'b1) begin
                    if (!seen_first) begin
                        seen_first = 1'b1;
                        first_cycle = total_cycles;
                    end
                    model_step;
                    retired = retired + 1;

                    if (trace)
                        $display("%5d  pc=%h  instr=%h  we=%b rd=x%0d data=%h",
                                 total_cycles, retire_pc, retire_instr,
                                 retire_we, retire_rd, retire_data);

                    mism = 1'b0;
                    if (retire_pc    !== m_x_pc)    mism = 1'b1;
                    else if (retire_instr !== m_x_instr) mism = 1'b1;
                    else if (retire_we    !== m_x_we)    mism = 1'b1;
                    else if (m_x_we && (retire_rd !== m_x_rd || retire_data !== m_x_data))
                        mism = 1'b1;

                    if (mism) begin
                        $display("FAIL: scoreboard mismatch at retire #%0d (cycle %0d)", retired, total_cycles);
                        $display("   DUT  : pc=%h instr=%h we=%b rd=x%0d data=%h",
                                 retire_pc, retire_instr, retire_we, retire_rd, retire_data);
                        $display("   MODEL: pc=%h instr=%h we=%b rd=x%0d data=%h",
                                 m_x_pc, m_x_instr, m_x_we, m_x_rd, m_x_data);
                        finish_fail("scoreboard mismatch");
                    end else if (m_done) begin
                        end_of_test;
                    end
                end
            end
        end
    end

    initial begin
        errors_init;
        if (!$value$plusargs("hex=%s", hexfile)) begin
            $display("ERROR: run with +hex=<program.hex>");
            $display("RESULT: FAIL (no program given)");
            $finish;
        end
        trace = $test$plusargs("trace");
        if ($test$plusargs("vcd")) begin
            $dumpfile("build/core_tb.vcd");
            $dumpvars(0, tb_core);
        end
        for (i = 0; i < 1024; i = i + 1) begin
            imem[i] = 32'h00000013;     // NOP
            dmem[i] = 32'h00000000;
        end
        $readmemh(hexfile, imem);
        for (i = 0; i < 1024; i = i + 1) m_imem[i] = imem[i];
        model_reset;

        rst = 1'b1;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
    end

    task errors_init;
        begin
            retired = 0; total_cycles = 0; first_cycle = 0;
            stall_cycles = 0; redirect_cycles = 0; span = 0;
            seen_first = 1'b0; finished = 1'b0; trace = 1'b0; mism = 1'b0;
        end
    endtask
endmodule
