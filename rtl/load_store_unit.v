// load_store_unit.v - byte/halfword/word access helper (purely combinational)
//
// Store path: replicate data across lanes and generate byte strobes.
// Load path : pick the right byte/halfword out of the 32-bit word read from
//             memory, then sign- or zero-extend.
// Memory is little-endian and word-organised (addr[1:0] picks the byte lane).
// Misaligned accesses are NOT supported (undefined; tests never do them).
module load_store_unit (
    input  wire [31:0] addr,         // byte address from ALU
    input  wire [2:0]  funct3,       // 000 B, 001 H, 010 W, 100 BU, 101 HU
    input  wire        mem_write,
    input  wire [31:0] store_data,   // rs2 value
    input  wire [31:0] raw_rdata,    // full word returned by data memory
    output reg  [31:0] dmem_wdata,
    output reg  [3:0]  dmem_wstrb,
    output reg  [31:0] load_data
);

    wire [1:0] off = addr[1:0];

    // ---------------- store path ----------------
    always @* begin
        dmem_wdata = store_data;
        dmem_wstrb = 4'b0000;
        if (mem_write) begin
            case (funct3[1:0])
                2'b00: begin                              // SB
                    dmem_wdata = {4{store_data[7:0]}};
                    dmem_wstrb = 4'b0001 << off;
                end
                2'b01: begin                              // SH
                    dmem_wdata = {2{store_data[15:0]}};
                    dmem_wstrb = off[1] ? 4'b1100 : 4'b0011;
                end
                default: begin                            // SW (11 is illegal and blocked by the decoder)
                    dmem_wdata = store_data;
                    dmem_wstrb = 4'b1111;
                end
            endcase
        end
    end

    // ---------------- load path ----------------
    reg [7:0]  sel_byte;
    reg [15:0] sel_half;

    always @* begin
        case (off)
            2'd0:    sel_byte = raw_rdata[7:0];
            2'd1:    sel_byte = raw_rdata[15:8];
            2'd2:    sel_byte = raw_rdata[23:16];
            default: sel_byte = raw_rdata[31:24];
        endcase
        sel_half = off[1] ? raw_rdata[31:16] : raw_rdata[15:0];
    end

    always @* begin
        case (funct3)
            3'b000:  load_data = {{24{sel_byte[7]}}, sel_byte};   // LB
            3'b001:  load_data = {{16{sel_half[15]}}, sel_half};  // LH
            3'b010:  load_data = raw_rdata;                       // LW
            3'b100:  load_data = {24'd0, sel_byte};               // LBU
            3'b101:  load_data = {16'd0, sel_half};               // LHU
            default: load_data = raw_rdata;
        endcase
    end

endmodule
