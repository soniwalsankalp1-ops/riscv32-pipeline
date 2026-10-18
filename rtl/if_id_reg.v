// if_id_reg.v - IF/ID pipeline register
// Priority: reset > flush > stall (hold) > load
// A bubble is valid=0 with a NOP (addi x0,x0,0) so waveforms stay readable.
module if_id_reg #(
    parameter XLEN = 32
) (
    input  wire            clk,
    input  wire            rst,
    input  wire            stall,
    input  wire            flush,
    input  wire [XLEN-1:0] pc_d,
    input  wire [31:0]     instr_d,
    output reg             valid_q,
    output reg  [XLEN-1:0] pc_q,
    output reg  [31:0]     instr_q
);

    localparam [31:0] NOP = 32'h00000013;

    always @(posedge clk) begin
        if (rst || flush) begin
            valid_q <= 1'b0;
            pc_q    <= {XLEN{1'b0}};
            instr_q <= NOP;
        end else if (!stall) begin
            valid_q <= 1'b1;
            pc_q    <= pc_d;
            instr_q <= instr_d;
        end
        // else: stall -> hold current values
    end

endmodule
