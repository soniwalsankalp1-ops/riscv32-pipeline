// id_ex_reg.v - ID/EX pipeline register
// This register never stalls. A load-use stall is done by inserting a
// bubble here (flush=1) while IF/ID and the PC hold.
// An instruction with valid_d=0 is ALWAYS turned into a bubble, so an
// invalid instruction can never reach EX with live control signals.
// Bubble = every control signal zero.
`include "riscv_defs.vh"

module id_ex_reg #(
    parameter XLEN = 32
) (
    input  wire            clk,
    input  wire            rst,
    input  wire            flush,
    // from ID
    input  wire            valid_d,
    input  wire [XLEN-1:0] pc_d,
    input  wire [31:0]     instr_d,
    input  wire [XLEN-1:0] rs1_data_d,
    input  wire [XLEN-1:0] rs2_data_d,
    input  wire [XLEN-1:0] imm_d,
    input  wire [4:0]      rs1_addr_d,
    input  wire [4:0]      rs2_addr_d,
    input  wire [4:0]      rd_addr_d,
    input  wire [2:0]      funct3_d,
    input  wire            reg_write_d,
    input  wire            alu_src_a_d,
    input  wire            alu_src_b_d,
    input  wire [3:0]      alu_op_d,
    input  wire            mem_read_d,
    input  wire            mem_write_d,
    input  wire [1:0]      wb_sel_d,
    input  wire            branch_d,
    input  wire            jal_d,
    input  wire            jalr_d,
    // to EX
    output reg             valid_q,
    output reg  [XLEN-1:0] pc_q,
    output reg  [31:0]     instr_q,
    output reg  [XLEN-1:0] rs1_data_q,
    output reg  [XLEN-1:0] rs2_data_q,
    output reg  [XLEN-1:0] imm_q,
    output reg  [4:0]      rs1_addr_q,
    output reg  [4:0]      rs2_addr_q,
    output reg  [4:0]      rd_addr_q,
    output reg  [2:0]      funct3_q,
    output reg             reg_write_q,
    output reg             alu_src_a_q,
    output reg             alu_src_b_q,
    output reg  [3:0]      alu_op_q,
    output reg             mem_read_q,
    output reg             mem_write_q,
    output reg  [1:0]      wb_sel_q,
    output reg             branch_q,
    output reg             jal_q,
    output reg             jalr_q
);

    wire bubble = rst | flush | ~valid_d;

    always @(posedge clk) begin
        if (bubble) begin
            valid_q     <= 1'b0;
            pc_q        <= {XLEN{1'b0}};
            instr_q     <= 32'h00000013;
            rs1_data_q  <= {XLEN{1'b0}};
            rs2_data_q  <= {XLEN{1'b0}};
            imm_q       <= {XLEN{1'b0}};
            rs1_addr_q  <= 5'd0;
            rs2_addr_q  <= 5'd0;
            rd_addr_q   <= 5'd0;
            funct3_q    <= 3'd0;
            reg_write_q <= 1'b0;
            alu_src_a_q <= 1'b0;
            alu_src_b_q <= 1'b0;
            alu_op_q    <= `ALU_ADD;
            mem_read_q  <= 1'b0;
            mem_write_q <= 1'b0;
            wb_sel_q    <= `WB_ALU;
            branch_q    <= 1'b0;
            jal_q       <= 1'b0;
            jalr_q      <= 1'b0;
        end else begin
            valid_q     <= valid_d;
            pc_q        <= pc_d;
            instr_q     <= instr_d;
            rs1_data_q  <= rs1_data_d;
            rs2_data_q  <= rs2_data_d;
            imm_q       <= imm_d;
            rs1_addr_q  <= rs1_addr_d;
            rs2_addr_q  <= rs2_addr_d;
            rd_addr_q   <= rd_addr_d;
            funct3_q    <= funct3_d;
            reg_write_q <= reg_write_d;
            alu_src_a_q <= alu_src_a_d;
            alu_src_b_q <= alu_src_b_d;
            alu_op_q    <= alu_op_d;
            mem_read_q  <= mem_read_d;
            mem_write_q <= mem_write_d;
            wb_sel_q    <= wb_sel_d;
            branch_q    <= branch_d;
            jal_q       <= jal_d;
            jalr_q      <= jalr_d;
        end
    end

endmodule
