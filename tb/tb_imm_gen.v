`timescale 1ns/1ps
`include "riscv_defs.vh"

module tb_imm_gen;
    reg  [31:0] instr;
    wire [31:0] imm;
    integer errors, checks, n;
    reg [31:0] r;

    imm_gen dut (.instr(instr), .imm(imm));

    // Encoders: build an instruction FROM a known immediate (inverse of the RTL)
    function [31:0] enc_i;
        input [31:0] v; input [4:0] rs1; input [4:0] rd; input [2:0] f3; input [6:0] opc;
        enc_i = {v[11:0], rs1, f3, rd, opc};
    endfunction

    function [31:0] enc_s;
        input [31:0] v; input [4:0] rs1; input [4:0] rs2; input [2:0] f3;
        enc_s = {v[11:5], rs2, rs1, f3, v[4:0], `OP_STORE};
    endfunction

    function [31:0] enc_b;
        input [31:0] v; input [4:0] rs1; input [4:0] rs2; input [2:0] f3;
        enc_b = {v[12], v[10:5], rs2, rs1, f3, v[4:1], v[11], `OP_BRANCH};
    endfunction

    function [31:0] enc_u;
        input [31:0] v; input [4:0] rd; input [6:0] opc;
        enc_u = {v[31:12], rd, opc};
    endfunction

    function [31:0] enc_j;
        input [31:0] v; input [4:0] rd;
        enc_j = {v[20], v[10:1], v[11], v[19:12], rd, `OP_JAL};
    endfunction

    task chk;
        input [31:0] ins;
        input [31:0] expv;
        input [8*12-1:0] name;
        begin
            instr = ins; #1;
            checks = checks + 1;
            if (imm !== expv) begin
                errors = errors + 1;
                $display("FAIL %0s: instr=%h got=%h exp=%h", name, ins, imm, expv);
            end
        end
    endtask

    // Each test_x uses random register/funct3 fields: they must not affect imm
    task test_i;
        input [31:0] v;
        reg [31:0] q;
        begin
            q = $random;
            chk(enc_i(v, q[4:0], q[9:5], q[12:10], `OP_OPIMM), v, "I opimm");
            chk(enc_i(v, q[4:0], q[9:5], q[12:10], `OP_LOAD),  v, "I load");
            chk(enc_i(v, q[4:0], q[9:5], q[12:10], `OP_JALR),  v, "I jalr");
        end
    endtask

    task test_s;
        input [31:0] v;
        reg [31:0] q;
        begin
            q = $random;
            chk(enc_s(v, q[4:0], q[9:5], q[12:10]), v, "S store");
        end
    endtask

    task test_b;
        input [31:0] v;
        reg [31:0] q;
        begin
            q = $random;
            chk(enc_b(v, q[4:0], q[9:5], q[12:10]), v, "B branch");
        end
    endtask

    task test_u;
        input [31:0] v;
        reg [31:0] q;
        begin
            q = $random;
            chk(enc_u(v, q[4:0], `OP_LUI),   v, "U lui");
            chk(enc_u(v, q[4:0], `OP_AUIPC), v, "U auipc");
        end
    endtask

    task test_j;
        input [31:0] v;
        reg [31:0] q;
        begin
            q = $random;
            chk(enc_j(v, q[4:0]), v, "J jal");
        end
    endtask

    initial begin
        #1000000;
        $display("RESULT: FAIL (timeout)");
        $finish;
    end

    initial begin
        errors = 0; checks = 0;

        // Directed edge values (range limits, zero, -1)
        test_i(0);  test_i(1);  test_i(-1);  test_i(2047);  test_i(-2048);
        test_s(0);  test_s(1);  test_s(-1);  test_s(2047);  test_s(-2048);
        test_b(0);  test_b(2);  test_b(-2);  test_b(4094);  test_b(-4096);
        test_j(0);  test_j(2);  test_j(-2);  test_j(1048574); test_j(-1048576);
        test_u(32'h00000000); test_u(32'h00001000); test_u(32'h12345000);
        test_u(32'hFFFFF000); test_u(32'h80000000);

        // Known real encodings (hand-checked)
        chk(32'hFFF00093, 32'hFFFFFFFF, "addi -1");     // addi x1,x0,-1
        chk(32'h123452B7, 32'h12345000, "lui");         // lui  x5,0x12345
        chk(32'hFE000EE3, 32'hFFFFFFFC, "beq -4");      // beq  x0,x0,-4

        // R-type has no immediate -> 0
        chk({7'b0100000, 5'd2, 5'd1, 3'b000, 5'd3, `OP_OP}, 32'd0, "R-type");

        // Random in-range immediates
        for (n = 0; n < 500; n = n + 1) begin
            r = $random;
            test_i({{20{r[11]}}, r[11:0]});
            test_s({{20{r[23]}}, r[23:12]});
            test_b({{19{r[12]}}, r[12:1], 1'b0});
            test_j({{11{r[20]}}, r[20:1], 1'b0});
            test_u({r[31:12], 12'b0});
        end

        if (errors == 0) $display("RESULT: PASS (%0d checks)", checks);
        else             $display("RESULT: FAIL (%0d errors / %0d checks)", errors, checks);
        $finish;
    end
endmodule
