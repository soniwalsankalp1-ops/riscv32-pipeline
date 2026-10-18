// riscv_core.v - 5-stage pipelined RV32I core
//
//  IF  : pc_reg, instruction memory (combinational read), IF/ID
//  ID  : control_unit, imm_gen, regfile (write-through bypass), ID/EX
//  EX  : forwarding, ALU, branch_unit (branch/jump resolved here), EX/MEM
//  MEM : load_store_unit, data memory, MEM/WB
//  WB  : write-back mux -> regfile
//
// Hazards: EX/MEM->EX and MEM/WB->EX forwarding, 1-cycle load-use stall,
//          2-slot flush on a taken branch/jump (predict not-taken).
// Memories live outside the core. Reads are combinational; writes are
// byte-strobed and should be applied by the memory on the rising clock edge.
// Reset is synchronous and active-high everywhere.
`include "riscv_defs.vh"

module riscv_core #(
    parameter [31:0] RESET_VECTOR = 32'h00000000
) (
    input  wire        clk,
    input  wire        rst,
    // instruction memory
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata,
    // data memory
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire [3:0]  dmem_wstrb,
    output wire        dmem_re,
    input  wire [31:0] dmem_rdata,
    // retire trace (one entry per instruction leaving WB)
    output wire        retire_valid,
    output wire [31:0] retire_pc,
    output wire [31:0] retire_instr,
    output wire        retire_we,       // writes a register (rd != x0)
    output wire [4:0]  retire_rd,
    output wire [31:0] retire_data
);

    localparam XLEN = 32;

    // ------------------------------------------------------------------
    // Signal declarations
    // ------------------------------------------------------------------
    // hazard control
    wire        pc_stall, ifid_stall, ifid_flush, idex_flush;

    // IF
    wire [31:0] pc;

    // IF/ID outputs
    wire        ifid_valid;
    wire [31:0] ifid_pc, ifid_instr;

    // ID
    wire        id_reg_write, id_alu_src_a, id_alu_src_b;
    wire [3:0]  id_alu_op;
    wire        id_mem_read, id_mem_write;
    wire [1:0]  id_wb_sel;
    wire        id_branch, id_jal, id_jalr, id_illegal;
    wire [31:0] id_imm, id_rs1_data, id_rs2_data;
    wire [6:0]  id_opcode = ifid_instr[6:0];

    // A source register counts as "used" only if the instruction really reads it.
    // Unused fields are forced to x0 so they never trigger forwarding or stalls
    // (for LUI/AUIPC/JAL those bits are actually immediate bits).
    wire id_uses_rs1 = !id_illegal &&
                       (id_opcode == `OP_OPIMM || id_opcode == `OP_OP     ||
                        id_opcode == `OP_LOAD  || id_opcode == `OP_STORE  ||
                        id_opcode == `OP_BRANCH|| id_opcode == `OP_JALR);
    wire id_uses_rs2 = !id_illegal &&
                       (id_opcode == `OP_OP || id_opcode == `OP_STORE ||
                        id_opcode == `OP_BRANCH);
    wire [4:0] id_rs1 = id_uses_rs1 ? ifid_instr[19:15] : 5'd0;
    wire [4:0] id_rs2 = id_uses_rs2 ? ifid_instr[24:20] : 5'd0;
    wire [4:0] id_rd  = ifid_instr[11:7];

    // ID/EX outputs
    wire        idex_valid;
    wire [31:0] idex_pc, idex_instr, idex_rs1_data, idex_rs2_data, idex_imm;
    wire [4:0]  idex_rs1, idex_rs2, idex_rd;
    wire [2:0]  idex_funct3;
    wire        idex_reg_write, idex_alu_src_a, idex_alu_src_b;
    wire [3:0]  idex_alu_op;
    wire        idex_mem_read, idex_mem_write;
    wire [1:0]  idex_wb_sel;
    wire        idex_branch, idex_jal, idex_jalr;

    // EX
    wire [1:0]  fwd_a, fwd_b;
    reg  [31:0] ex_rs1_val, ex_rs2_val;
    wire [31:0] alu_a, alu_b, ex_alu_result;
    wire        ex_redirect;
    wire [31:0] ex_redirect_target;
    wire [31:0] ex_pc_plus4 = idex_pc + 32'd4;

    // EX/MEM outputs
    wire        exmem_valid;
    wire [31:0] exmem_pc, exmem_instr, exmem_pc_plus4, exmem_alu_result, exmem_store_data;
    wire [4:0]  exmem_rd;
    wire [2:0]  exmem_funct3;
    wire        exmem_reg_write, exmem_mem_read, exmem_mem_write;
    wire [1:0]  exmem_wb_sel;

    // Value forwarded from EX/MEM. JAL/JALR results are PC+4 (link), not the ALU
    // output. Loads are never forwarded from here: the load-use stall guarantees
    // the consumer reaches EX only when the load is already in MEM/WB.
    wire [31:0] exmem_fwd_data = (exmem_wb_sel == `WB_PC4) ? exmem_pc_plus4
                                                           : exmem_alu_result;

    // MEM
    wire [31:0] mem_load_data;

    // MEM/WB outputs
    wire        memwb_valid;
    wire [31:0] memwb_pc, memwb_instr, memwb_pc_plus4, memwb_alu_result, memwb_load_data;
    wire [4:0]  memwb_rd;
    wire        memwb_reg_write;
    wire [1:0]  memwb_wb_sel;

    // WB
    reg  [31:0] wb_data;

    // ------------------------------------------------------------------
    // IF stage
    // ------------------------------------------------------------------
    pc_reg #(.XLEN(XLEN), .RESET_VECTOR(RESET_VECTOR)) u_pc (
        .clk(clk), .rst(rst),
        .stall(pc_stall),
        .redirect(ex_redirect), .redirect_target(ex_redirect_target),
        .pc(pc), .pc_plus4());

    assign imem_addr = pc;

    if_id_reg #(.XLEN(XLEN)) u_if_id (
        .clk(clk), .rst(rst), .stall(ifid_stall), .flush(ifid_flush),
        .pc_d(pc), .instr_d(imem_rdata),
        .valid_q(ifid_valid), .pc_q(ifid_pc), .instr_q(ifid_instr));

    // ------------------------------------------------------------------
    // ID stage
    // ------------------------------------------------------------------
    control_unit u_ctrl (
        .instr(ifid_instr),
        .reg_write(id_reg_write), .alu_src_a(id_alu_src_a), .alu_src_b(id_alu_src_b),
        .alu_op(id_alu_op), .mem_read(id_mem_read), .mem_write(id_mem_write),
        .wb_sel(id_wb_sel), .branch(id_branch), .jal(id_jal), .jalr(id_jalr),
        .illegal(id_illegal));

    imm_gen u_imm (.instr(ifid_instr), .imm(id_imm));

    regfile #(.XLEN(XLEN)) u_regfile (
        .clk(clk), .rst(rst),
        .we(memwb_reg_write), .waddr(memwb_rd), .wdata(wb_data),
        .raddr1(id_rs1), .raddr2(id_rs2),
        .rdata1(id_rs1_data), .rdata2(id_rs2_data));

    hazard_unit u_hazard (
        .idex_mem_read(idex_mem_read), .idex_rd(idex_rd),
        .id_rs1(id_rs1), .id_rs2(id_rs2),
        .ex_redirect(ex_redirect),
        .pc_stall(pc_stall), .ifid_stall(ifid_stall),
        .ifid_flush(ifid_flush), .idex_flush(idex_flush));

    id_ex_reg #(.XLEN(XLEN)) u_id_ex (
        .clk(clk), .rst(rst), .flush(idex_flush),
        .valid_d(ifid_valid), .pc_d(ifid_pc), .instr_d(ifid_instr),
        .rs1_data_d(id_rs1_data), .rs2_data_d(id_rs2_data), .imm_d(id_imm),
        .rs1_addr_d(id_rs1), .rs2_addr_d(id_rs2), .rd_addr_d(id_rd),
        .funct3_d(ifid_instr[14:12]),
        .reg_write_d(id_reg_write), .alu_src_a_d(id_alu_src_a), .alu_src_b_d(id_alu_src_b),
        .alu_op_d(id_alu_op), .mem_read_d(id_mem_read), .mem_write_d(id_mem_write),
        .wb_sel_d(id_wb_sel), .branch_d(id_branch), .jal_d(id_jal), .jalr_d(id_jalr),
        .valid_q(idex_valid), .pc_q(idex_pc), .instr_q(idex_instr),
        .rs1_data_q(idex_rs1_data), .rs2_data_q(idex_rs2_data), .imm_q(idex_imm),
        .rs1_addr_q(idex_rs1), .rs2_addr_q(idex_rs2), .rd_addr_q(idex_rd),
        .funct3_q(idex_funct3),
        .reg_write_q(idex_reg_write), .alu_src_a_q(idex_alu_src_a), .alu_src_b_q(idex_alu_src_b),
        .alu_op_q(idex_alu_op), .mem_read_q(idex_mem_read), .mem_write_q(idex_mem_write),
        .wb_sel_q(idex_wb_sel), .branch_q(idex_branch), .jal_q(idex_jal), .jalr_q(idex_jalr));

    // ------------------------------------------------------------------
    // EX stage
    // ------------------------------------------------------------------
    forwarding_unit u_fwd (
        .ex_rs1(idex_rs1), .ex_rs2(idex_rs2),
        .exmem_rd(exmem_rd), .exmem_reg_write(exmem_reg_write),
        .memwb_rd(memwb_rd), .memwb_reg_write(memwb_reg_write),
        .fwd_a(fwd_a), .fwd_b(fwd_b));

    // Forwarding muxes (the forwarded value also feeds the branch compare and store data)
    always @* begin
        case (fwd_a)
            `FWD_EXMEM: ex_rs1_val = exmem_fwd_data;
            `FWD_MEMWB: ex_rs1_val = wb_data;
            default:    ex_rs1_val = idex_rs1_data;
        endcase
        case (fwd_b)
            `FWD_EXMEM: ex_rs2_val = exmem_fwd_data;
            `FWD_MEMWB: ex_rs2_val = wb_data;
            default:    ex_rs2_val = idex_rs2_data;
        endcase
    end

    assign alu_a = idex_alu_src_a ? idex_pc  : ex_rs1_val;
    assign alu_b = idex_alu_src_b ? idex_imm : ex_rs2_val;

    alu #(.XLEN(XLEN)) u_alu (
        .a(alu_a), .b(alu_b), .alu_op(idex_alu_op), .result(ex_alu_result));

    branch_unit #(.XLEN(XLEN)) u_branch (
        .rs1_val(ex_rs1_val), .rs2_val(ex_rs2_val), .alu_result(ex_alu_result),
        .funct3(idex_funct3),
        .branch(idex_branch), .jal(idex_jal), .jalr(idex_jalr),
        .redirect(ex_redirect), .redirect_target(ex_redirect_target));

    ex_mem_reg #(.XLEN(XLEN)) u_ex_mem (
        .clk(clk), .rst(rst),
        .valid_d(idex_valid), .pc_d(idex_pc), .instr_d(idex_instr),
        .pc_plus4_d(ex_pc_plus4), .alu_result_d(ex_alu_result),
        .store_data_d(ex_rs2_val), .rd_addr_d(idex_rd), .funct3_d(idex_funct3),
        .reg_write_d(idex_reg_write), .mem_read_d(idex_mem_read),
        .mem_write_d(idex_mem_write), .wb_sel_d(idex_wb_sel),
        .valid_q(exmem_valid), .pc_q(exmem_pc), .instr_q(exmem_instr),
        .pc_plus4_q(exmem_pc_plus4), .alu_result_q(exmem_alu_result),
        .store_data_q(exmem_store_data), .rd_addr_q(exmem_rd), .funct3_q(exmem_funct3),
        .reg_write_q(exmem_reg_write), .mem_read_q(exmem_mem_read),
        .mem_write_q(exmem_mem_write), .wb_sel_q(exmem_wb_sel));

    // ------------------------------------------------------------------
    // MEM stage
    // ------------------------------------------------------------------
    load_store_unit u_lsu (
        .addr(exmem_alu_result), .funct3(exmem_funct3),
        .mem_write(exmem_mem_write), .store_data(exmem_store_data),
        .raw_rdata(dmem_rdata),
        .dmem_wdata(dmem_wdata), .dmem_wstrb(dmem_wstrb),
        .load_data(mem_load_data));

    assign dmem_addr = exmem_alu_result;
    assign dmem_re   = exmem_mem_read;

    mem_wb_reg #(.XLEN(XLEN)) u_mem_wb (
        .clk(clk), .rst(rst),
        .valid_d(exmem_valid), .pc_d(exmem_pc), .instr_d(exmem_instr),
        .pc_plus4_d(exmem_pc_plus4), .alu_result_d(exmem_alu_result),
        .load_data_d(mem_load_data), .rd_addr_d(exmem_rd),
        .reg_write_d(exmem_reg_write), .wb_sel_d(exmem_wb_sel),
        .valid_q(memwb_valid), .pc_q(memwb_pc), .instr_q(memwb_instr),
        .pc_plus4_q(memwb_pc_plus4), .alu_result_q(memwb_alu_result),
        .load_data_q(memwb_load_data), .rd_addr_q(memwb_rd),
        .reg_write_q(memwb_reg_write), .wb_sel_q(memwb_wb_sel));

    // ------------------------------------------------------------------
    // WB stage
    // ------------------------------------------------------------------
    always @* begin
        case (memwb_wb_sel)
            `WB_MEM: wb_data = memwb_load_data;
            `WB_PC4: wb_data = memwb_pc_plus4;
            default: wb_data = memwb_alu_result;
        endcase
    end

    // ------------------------------------------------------------------
    // Retire trace
    // ------------------------------------------------------------------
    assign retire_valid = memwb_valid;
    assign retire_pc    = memwb_pc;
    assign retire_instr = memwb_instr;
    assign retire_we    = memwb_valid && memwb_reg_write && (memwb_rd != 5'd0);
    assign retire_rd    = memwb_rd;
    assign retire_data  = wb_data;

endmodule
