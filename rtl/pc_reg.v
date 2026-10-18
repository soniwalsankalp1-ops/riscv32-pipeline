// pc_reg.v - program counter
// Priority: reset > redirect (taken branch/jump) > stall (hold) > PC+4
module pc_reg #(
    parameter XLEN = 32,
    parameter [XLEN-1:0] RESET_VECTOR = {XLEN{1'b0}}
) (
    input  wire            clk,
    input  wire            rst,
    input  wire            stall,
    input  wire            redirect,
    input  wire [XLEN-1:0] redirect_target,
    output reg  [XLEN-1:0] pc,
    output wire [XLEN-1:0] pc_plus4
);

    assign pc_plus4 = pc + 4;

    always @(posedge clk) begin
        if (rst)           pc <= RESET_VECTOR;
        else if (redirect) pc <= redirect_target;
        else if (!stall)   pc <= pc_plus4;
    end

endmodule
