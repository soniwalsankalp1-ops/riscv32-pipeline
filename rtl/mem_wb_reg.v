// mem_wb_reg.v - MEM/WB pipeline register (reset only)
// load_data_d is the already aligned/sign-extended load result from the
// load_store_unit, so the write-back mux in WB is a simple 3-way select.
module mem_wb_reg #(
    parameter XLEN = 32
) (
    input  wire            clk,
    input  wire            rst,
    input  wire            valid_d,
    input  wire [XLEN-1:0] pc_d,
    input  wire [31:0]     instr_d,
    input  wire [XLEN-1:0] pc_plus4_d,
    input  wire [XLEN-1:0] alu_result_d,
    input  wire [XLEN-1:0] load_data_d,
    input  wire [4:0]      rd_addr_d,
    input  wire            reg_write_d,
    input  wire [1:0]      wb_sel_d,
    output reg             valid_q,
    output reg  [XLEN-1:0] pc_q,
    output reg  [31:0]     instr_q,
    output reg  [XLEN-1:0] pc_plus4_q,
    output reg  [XLEN-1:0] alu_result_q,
    output reg  [XLEN-1:0] load_data_q,
    output reg  [4:0]      rd_addr_q,
    output reg             reg_write_q,
    output reg  [1:0]      wb_sel_q
);

    always @(posedge clk) begin
        if (rst) begin
            valid_q      <= 1'b0;
            pc_q         <= {XLEN{1'b0}};
            instr_q      <= 32'h00000013;
            pc_plus4_q   <= {XLEN{1'b0}};
            alu_result_q <= {XLEN{1'b0}};
            load_data_q  <= {XLEN{1'b0}};
            rd_addr_q    <= 5'd0;
            reg_write_q  <= 1'b0;
            wb_sel_q     <= 2'd0;
        end else begin
            valid_q      <= valid_d;
            pc_q         <= pc_d;
            instr_q      <= instr_d;
            pc_plus4_q   <= pc_plus4_d;
            alu_result_q <= alu_result_d;
            load_data_q  <= load_data_d;
            rd_addr_q    <= rd_addr_d;
            reg_write_q  <= reg_write_d;
            wb_sel_q     <= wb_sel_d;
        end
    end

endmodule
