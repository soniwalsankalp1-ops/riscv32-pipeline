`timescale 1ns/1ps

module tb_pipe_regs;
    // Expected bubble/reset images: {valid, pc, instr(NOP), everything else 0}
    localparam [64:0]  IFID_RST  = {1'b0, 32'd0, 32'h00000013};
    localparam [192:0] IDEX_RST  = {1'b0, 32'd0, 32'h00000013, 128'd0};
    localparam [173:0] EXMEM_RST = {1'b0, 32'd0, 32'h00000013, 109'd0};
    localparam [168:0] MEMWB_RST = {1'b0, 32'd0, 32'h00000013, 104'd0};

    reg clk, rst;
    integer errors, checks, n;
    reg force_valid;
    reg [31:0] saved;
    reg [31:0] rr;

    // ---------------- IF/ID ----------------
    reg         ifid_stall, ifid_flush;
    reg  [31:0] ifid_pc_d, ifid_instr_d;
    wire        ifid_valid_q;
    wire [31:0] ifid_pc_q, ifid_instr_q;

    if_id_reg #(.XLEN(32)) u_ifid (
        .clk(clk), .rst(rst), .stall(ifid_stall), .flush(ifid_flush),
        .pc_d(ifid_pc_d), .instr_d(ifid_instr_d),
        .valid_q(ifid_valid_q), .pc_q(ifid_pc_q), .instr_q(ifid_instr_q));

    // ---------------- ID/EX ----------------
    reg         idex_flush;
    reg         idex_valid_d;
    reg  [31:0] idex_pc_d, idex_instr_d, idex_rs1_data_d, idex_rs2_data_d, idex_imm_d;
    reg  [4:0]  idex_rs1_addr_d, idex_rs2_addr_d, idex_rd_addr_d;
    reg  [2:0]  idex_funct3_d;
    reg         idex_reg_write_d, idex_alu_src_a_d, idex_alu_src_b_d;
    reg  [3:0]  idex_alu_op_d;
    reg         idex_mem_read_d, idex_mem_write_d;
    reg  [1:0]  idex_wb_sel_d;
    reg         idex_branch_d, idex_jal_d, idex_jalr_d;

    wire        idex_valid_q;
    wire [31:0] idex_pc_q, idex_instr_q, idex_rs1_data_q, idex_rs2_data_q, idex_imm_q;
    wire [4:0]  idex_rs1_addr_q, idex_rs2_addr_q, idex_rd_addr_q;
    wire [2:0]  idex_funct3_q;
    wire        idex_reg_write_q, idex_alu_src_a_q, idex_alu_src_b_q;
    wire [3:0]  idex_alu_op_q;
    wire        idex_mem_read_q, idex_mem_write_q;
    wire [1:0]  idex_wb_sel_q;
    wire        idex_branch_q, idex_jal_q, idex_jalr_q;

    id_ex_reg #(.XLEN(32)) u_idex (
        .clk(clk), .rst(rst), .flush(idex_flush),
        .valid_d(idex_valid_d), .pc_d(idex_pc_d), .instr_d(idex_instr_d),
        .rs1_data_d(idex_rs1_data_d), .rs2_data_d(idex_rs2_data_d), .imm_d(idex_imm_d),
        .rs1_addr_d(idex_rs1_addr_d), .rs2_addr_d(idex_rs2_addr_d), .rd_addr_d(idex_rd_addr_d),
        .funct3_d(idex_funct3_d), .reg_write_d(idex_reg_write_d),
        .alu_src_a_d(idex_alu_src_a_d), .alu_src_b_d(idex_alu_src_b_d),
        .alu_op_d(idex_alu_op_d), .mem_read_d(idex_mem_read_d), .mem_write_d(idex_mem_write_d),
        .wb_sel_d(idex_wb_sel_d), .branch_d(idex_branch_d), .jal_d(idex_jal_d), .jalr_d(idex_jalr_d),
        .valid_q(idex_valid_q), .pc_q(idex_pc_q), .instr_q(idex_instr_q),
        .rs1_data_q(idex_rs1_data_q), .rs2_data_q(idex_rs2_data_q), .imm_q(idex_imm_q),
        .rs1_addr_q(idex_rs1_addr_q), .rs2_addr_q(idex_rs2_addr_q), .rd_addr_q(idex_rd_addr_q),
        .funct3_q(idex_funct3_q), .reg_write_q(idex_reg_write_q),
        .alu_src_a_q(idex_alu_src_a_q), .alu_src_b_q(idex_alu_src_b_q),
        .alu_op_q(idex_alu_op_q), .mem_read_q(idex_mem_read_q), .mem_write_q(idex_mem_write_q),
        .wb_sel_q(idex_wb_sel_q), .branch_q(idex_branch_q), .jal_q(idex_jal_q), .jalr_q(idex_jalr_q));

    // ---------------- EX/MEM ----------------
    reg         exmem_valid_d;
    reg  [31:0] exmem_pc_d, exmem_instr_d, exmem_pc_plus4_d, exmem_alu_result_d, exmem_store_data_d;
    reg  [4:0]  exmem_rd_addr_d;
    reg  [2:0]  exmem_funct3_d;
    reg         exmem_reg_write_d, exmem_mem_read_d, exmem_mem_write_d;
    reg  [1:0]  exmem_wb_sel_d;

    wire        exmem_valid_q;
    wire [31:0] exmem_pc_q, exmem_instr_q, exmem_pc_plus4_q, exmem_alu_result_q, exmem_store_data_q;
    wire [4:0]  exmem_rd_addr_q;
    wire [2:0]  exmem_funct3_q;
    wire        exmem_reg_write_q, exmem_mem_read_q, exmem_mem_write_q;
    wire [1:0]  exmem_wb_sel_q;

    ex_mem_reg #(.XLEN(32)) u_exmem (
        .clk(clk), .rst(rst),
        .valid_d(exmem_valid_d), .pc_d(exmem_pc_d), .instr_d(exmem_instr_d),
        .pc_plus4_d(exmem_pc_plus4_d), .alu_result_d(exmem_alu_result_d),
        .store_data_d(exmem_store_data_d), .rd_addr_d(exmem_rd_addr_d), .funct3_d(exmem_funct3_d),
        .reg_write_d(exmem_reg_write_d), .mem_read_d(exmem_mem_read_d),
        .mem_write_d(exmem_mem_write_d), .wb_sel_d(exmem_wb_sel_d),
        .valid_q(exmem_valid_q), .pc_q(exmem_pc_q), .instr_q(exmem_instr_q),
        .pc_plus4_q(exmem_pc_plus4_q), .alu_result_q(exmem_alu_result_q),
        .store_data_q(exmem_store_data_q), .rd_addr_q(exmem_rd_addr_q), .funct3_q(exmem_funct3_q),
        .reg_write_q(exmem_reg_write_q), .mem_read_q(exmem_mem_read_q),
        .mem_write_q(exmem_mem_write_q), .wb_sel_q(exmem_wb_sel_q));

    // ---------------- MEM/WB ----------------
    reg         memwb_valid_d;
    reg  [31:0] memwb_pc_d, memwb_instr_d, memwb_pc_plus4_d, memwb_alu_result_d, memwb_load_data_d;
    reg  [4:0]  memwb_rd_addr_d;
    reg         memwb_reg_write_d;
    reg  [1:0]  memwb_wb_sel_d;

    wire        memwb_valid_q;
    wire [31:0] memwb_pc_q, memwb_instr_q, memwb_pc_plus4_q, memwb_alu_result_q, memwb_load_data_q;
    wire [4:0]  memwb_rd_addr_q;
    wire        memwb_reg_write_q;
    wire [1:0]  memwb_wb_sel_q;

    mem_wb_reg #(.XLEN(32)) u_memwb (
        .clk(clk), .rst(rst),
        .valid_d(memwb_valid_d), .pc_d(memwb_pc_d), .instr_d(memwb_instr_d),
        .pc_plus4_d(memwb_pc_plus4_d), .alu_result_d(memwb_alu_result_d),
        .load_data_d(memwb_load_data_d), .rd_addr_d(memwb_rd_addr_d),
        .reg_write_d(memwb_reg_write_d), .wb_sel_d(memwb_wb_sel_d),
        .valid_q(memwb_valid_q), .pc_q(memwb_pc_q), .instr_q(memwb_instr_q),
        .pc_plus4_q(memwb_pc_plus4_q), .alu_result_q(memwb_alu_result_q),
        .load_data_q(memwb_load_data_q), .rd_addr_q(memwb_rd_addr_q),
        .reg_write_q(memwb_reg_write_q), .wb_sel_q(memwb_wb_sel_q));

    // ---------------- bundled views for whole-register comparison ----------------
    wire [64:0]  ifid_in_cat  = {1'b1, ifid_pc_d, ifid_instr_d};
    wire [64:0]  ifid_out_cat = {ifid_valid_q, ifid_pc_q, ifid_instr_q};

    wire [192:0] idex_in_cat = {idex_valid_d, idex_pc_d, idex_instr_d, idex_rs1_data_d,
        idex_rs2_data_d, idex_imm_d, idex_rs1_addr_d, idex_rs2_addr_d, idex_rd_addr_d,
        idex_funct3_d, idex_reg_write_d, idex_alu_src_a_d, idex_alu_src_b_d, idex_alu_op_d,
        idex_mem_read_d, idex_mem_write_d, idex_wb_sel_d, idex_branch_d, idex_jal_d, idex_jalr_d};
    wire [192:0] idex_out_cat = {idex_valid_q, idex_pc_q, idex_instr_q, idex_rs1_data_q,
        idex_rs2_data_q, idex_imm_q, idex_rs1_addr_q, idex_rs2_addr_q, idex_rd_addr_q,
        idex_funct3_q, idex_reg_write_q, idex_alu_src_a_q, idex_alu_src_b_q, idex_alu_op_q,
        idex_mem_read_q, idex_mem_write_q, idex_wb_sel_q, idex_branch_q, idex_jal_q, idex_jalr_q};

    wire [173:0] exmem_in_cat = {exmem_valid_d, exmem_pc_d, exmem_instr_d, exmem_pc_plus4_d,
        exmem_alu_result_d, exmem_store_data_d, exmem_rd_addr_d, exmem_funct3_d,
        exmem_reg_write_d, exmem_mem_read_d, exmem_mem_write_d, exmem_wb_sel_d};
    wire [173:0] exmem_out_cat = {exmem_valid_q, exmem_pc_q, exmem_instr_q, exmem_pc_plus4_q,
        exmem_alu_result_q, exmem_store_data_q, exmem_rd_addr_q, exmem_funct3_q,
        exmem_reg_write_q, exmem_mem_read_q, exmem_mem_write_q, exmem_wb_sel_q};

    wire [168:0] memwb_in_cat = {memwb_valid_d, memwb_pc_d, memwb_instr_d, memwb_pc_plus4_d,
        memwb_alu_result_d, memwb_load_data_d, memwb_rd_addr_d, memwb_reg_write_d, memwb_wb_sel_d};
    wire [168:0] memwb_out_cat = {memwb_valid_q, memwb_pc_q, memwb_instr_q, memwb_pc_plus4_q,
        memwb_alu_result_q, memwb_load_data_q, memwb_rd_addr_q, memwb_reg_write_q, memwb_wb_sel_q};

    // Scoreboard (expected register contents)
    reg [64:0]  exp_ifid;
    reg [192:0] exp_idex;
    reg [173:0] exp_exmem;
    reg [168:0] exp_memwb;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task expect_eq;
        input [255:0] got;
        input [255:0] expv;
        input [8*16-1:0] name;
        begin
            checks = checks + 1;
            if (got !== expv) begin
                errors = errors + 1;
                $display("FAIL %0s at t=%0t", name, $time);
                $display("   got = %h", got);
                $display("   exp = %h", expv);
            end
        end
    endtask

    task randomize;
        begin
            ifid_pc_d = $random;  ifid_instr_d = $random;

            idex_valid_d = force_valid ? 1'b1 : (($random & 3) != 0);   // 75% valid in random mode
            idex_pc_d = $random;  idex_instr_d = $random;
            idex_rs1_data_d = $random; idex_rs2_data_d = $random; idex_imm_d = $random;
            idex_rs1_addr_d = $random; idex_rs2_addr_d = $random; idex_rd_addr_d = $random;
            idex_funct3_d = $random;
            idex_reg_write_d = $random; idex_alu_src_a_d = $random; idex_alu_src_b_d = $random;
            idex_alu_op_d = $random; idex_mem_read_d = $random; idex_mem_write_d = $random;
            idex_wb_sel_d = $random; idex_branch_d = $random; idex_jal_d = $random; idex_jalr_d = $random;

            exmem_valid_d = $random; exmem_pc_d = $random; exmem_instr_d = $random;
            exmem_pc_plus4_d = $random; exmem_alu_result_d = $random; exmem_store_data_d = $random;
            exmem_rd_addr_d = $random; exmem_funct3_d = $random; exmem_reg_write_d = $random;
            exmem_mem_read_d = $random; exmem_mem_write_d = $random; exmem_wb_sel_d = $random;

            memwb_valid_d = $random; memwb_pc_d = $random; memwb_instr_d = $random;
            memwb_pc_plus4_d = $random; memwb_alu_result_d = $random; memwb_load_data_d = $random;
            memwb_rd_addr_d = $random; memwb_reg_write_d = $random; memwb_wb_sel_d = $random;
        end
    endtask

    // One clock: apply controls (+ optionally new data), predict, tick, compare
    task cycle;
        input c_rst;
        input c_stall;
        input c_flush_ifid;
        input c_flush_idex;
        input c_newdata;
        begin
            if (c_newdata) randomize;
            rst = c_rst; ifid_stall = c_stall; ifid_flush = c_flush_ifid; idex_flush = c_flush_idex;
            #1;   // let the bundled wires settle before sampling them
            if (c_rst) begin
                exp_ifid = IFID_RST; exp_idex = IDEX_RST; exp_exmem = EXMEM_RST; exp_memwb = MEMWB_RST;
            end else begin
                if (c_flush_ifid)    exp_ifid = IFID_RST;
                else if (!c_stall)   exp_ifid = ifid_in_cat;
                if (c_flush_idex || !idex_valid_d) exp_idex = IDEX_RST;
                else                               exp_idex = idex_in_cat;
                exp_exmem = exmem_in_cat;
                exp_memwb = memwb_in_cat;
            end
            @(posedge clk); #1;
            expect_eq(ifid_out_cat,  exp_ifid,  "IF/ID");
            expect_eq(idex_out_cat,  exp_idex,  "ID/EX");
            expect_eq(exmem_out_cat, exp_exmem, "EX/MEM");
            expect_eq(memwb_out_cat, exp_memwb, "MEM/WB");
        end
    endtask

    initial begin
        #10000000;
        $display("RESULT: FAIL (timeout)");
        $finish;
    end

    initial begin
        errors = 0; checks = 0; force_valid = 1'b1;
        rst = 1'b1; ifid_stall = 1'b0; ifid_flush = 1'b0; idex_flush = 1'b0;

        // ---- Directed section ----
        cycle(1,0,0,0,1);                                    // reset
        expect_eq(ifid_instr_q, 32'h00000013, "reset ifid nop");
        expect_eq(idex_reg_write_q, 1'b0, "reset idex ctrl");

        cycle(0,0,0,0,1);                                    // normal load
        expect_eq(ifid_instr_q, ifid_instr_d, "ifid load");
        expect_eq(idex_rd_addr_q, idex_rd_addr_d, "idex load");
        expect_eq(exmem_alu_result_q, exmem_alu_result_d, "exmem load");
        expect_eq(memwb_load_data_q, memwb_load_data_d, "memwb load");

        saved = ifid_instr_q;
        cycle(0,1,0,0,1);                                    // stall IF/ID, new data offered
        expect_eq(ifid_instr_q, saved, "ifid stall holds");
        expect_eq(idex_pc_q, idex_pc_d, "idex not stalled");

        cycle(0,0,1,1,1);                                    // flush both
        expect_eq(ifid_instr_q, 32'h00000013, "ifid flush nop");
        expect_eq(ifid_valid_q, 1'b0, "ifid flush valid");
        expect_eq(idex_valid_q, 1'b0, "idex flush valid");
        expect_eq(idex_reg_write_q, 1'b0, "idex flush rw");
        expect_eq(idex_mem_write_q, 1'b0, "idex flush mw");
        expect_eq(idex_mem_read_q, 1'b0, "idex flush mr");
        expect_eq(idex_branch_q | idex_jal_q | idex_jalr_q, 1'b0, "idex flush br");

        cycle(0,1,1,0,1);                                    // flush AND stall: flush wins
        expect_eq(ifid_valid_q, 1'b0, "flush beats stall");

        // ---- Random section ----
        force_valid = 1'b0;
        for (n = 0; n < 3000; n = n + 1) begin
            rr = $random;
            cycle((rr[4:0] == 5'd0),        // ~3% reset
                  (rr[6:5] == 2'd0),        // 25% stall
                  (rr[9:7] == 3'd0),        // 12.5% IF/ID flush
                  (rr[12:10] == 3'd0),      // 12.5% ID/EX flush
                  1'b1);
        end

        if (errors == 0) $display("RESULT: PASS (%0d checks)", checks);
        else             $display("RESULT: FAIL (%0d errors / %0d checks)", errors, checks);
        $finish;
    end
endmodule
