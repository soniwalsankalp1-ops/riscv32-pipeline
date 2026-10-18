// hazard_unit.v - stall and flush control (combinational)
//
// Branch/jump redirect is resolved in EX. Priority: redirect > stall.
//
//  load-use : instruction in EX is a load and its rd is a source of the
//             instruction in ID.  -> hold PC and IF/ID, bubble into ID/EX.
//  redirect : taken branch / jump in EX.  -> flush IF/ID and ID/EX (the PC
//             itself is loaded with the target by pc_reg).
//
// A load and a branch/jump cannot both be in EX, so the two cases never
// really overlap; the priority is still explicit so the design stays safe
// if it is extended later.
module hazard_unit (
    input  wire       idex_mem_read,   // instruction in EX is a load
    input  wire [4:0] idex_rd,
    input  wire [4:0] id_rs1,          // already forced to x0 if unused
    input  wire [4:0] id_rs2,
    input  wire       ex_redirect,
    output wire       pc_stall,
    output wire       ifid_stall,
    output wire       ifid_flush,
    output wire       idex_flush
);

    wire load_use = idex_mem_read && (idex_rd != 5'd0) &&
                    ((idex_rd == id_rs1) || (idex_rd == id_rs2));

    wire stall = load_use && !ex_redirect;

    assign pc_stall   = stall;
    assign ifid_stall = stall;
    assign ifid_flush = ex_redirect;
    assign idex_flush = ex_redirect || stall;   // stall inserts a bubble into EX

endmodule
