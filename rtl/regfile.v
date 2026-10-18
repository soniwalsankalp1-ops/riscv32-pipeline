// regfile.v - 32 x XLEN register file
//  * x0 reads as zero and ignores writes
//  * two combinational read ports, one synchronous write port
//  * write-through bypass: a read of the register being written this
//    cycle returns wdata (solves the WB-to-ID hazard without negedge tricks)
//  * synchronous active-high reset clears all registers
module regfile #(
    parameter XLEN = 32
) (
    input  wire            clk,
    input  wire            rst,
    input  wire            we,
    input  wire [4:0]      waddr,
    input  wire [XLEN-1:0] wdata,
    input  wire [4:0]      raddr1,
    input  wire [4:0]      raddr2,
    output wire [XLEN-1:0] rdata1,
    output wire [XLEN-1:0] rdata2
);

    reg [XLEN-1:0] regs [0:31];
    integer i;

    // A write really happens only if enabled, not in reset, and not to x0
    wire wr_en = we && !rst && (waddr != 5'd0);

    // Sequential logic
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= {XLEN{1'b0}};
        end else if (wr_en) begin
            regs[waddr] <= wdata;
        end
    end

    // Combinational reads with bypass
    assign rdata1 = (raddr1 == 5'd0)              ? {XLEN{1'b0}} :
                    (wr_en && (waddr == raddr1))  ? wdata        :
                                                    regs[raddr1];

    assign rdata2 = (raddr2 == 5'd0)              ? {XLEN{1'b0}} :
                    (wr_en && (waddr == raddr2))  ? wdata        :
                                                    regs[raddr2];

endmodule
