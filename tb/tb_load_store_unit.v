`timescale 1ns/1ps

module tb_load_store_unit;
    reg  [31:0] addr, store_data, raw_rdata;
    reg  [2:0]  f3;
    reg         mem_write;
    wire [31:0] wdata, load_data;
    wire [3:0]  wstrb;
    integer errors, checks, n, a, a2, lt, st;
    reg [31:0] wmem [0:3];     // word memory, updated through the DUT's strobes
    reg [7:0]  bmem [0:15];    // reference byte memory, updated by simple arithmetic
    reg [31:0] r;

    load_store_unit dut (
        .addr(addr), .funct3(f3), .mem_write(mem_write), .store_data(store_data),
        .raw_rdata(raw_rdata), .dmem_wdata(wdata), .dmem_wstrb(wstrb),
        .load_data(load_data));

    task expect32;
        input [31:0] got;
        input [31:0] expv;
        input [8*16-1:0] name;
        begin
            checks = checks + 1;
            if (got !== expv) begin
                errors = errors + 1;
                $display("FAIL %0s: addr=%h f3=%b got=%h exp=%h", name, addr, f3, got, expv);
            end
        end
    endtask

    function [2:0] load_type;
        input [2:0] i;
        begin
            case (i)
                3'd0:    load_type = 3'b000;  // LB
                3'd1:    load_type = 3'b001;  // LH
                3'd2:    load_type = 3'b010;  // LW
                3'd3:    load_type = 3'b100;  // LBU
                default: load_type = 3'b101;  // LHU
            endcase
        end
    endfunction

    function ok_align;
        input [31:0] ad;
        input [2:0]  ff;
        begin
            case (ff[1:0])
                2'b01:   ok_align = (ad[0]   == 1'b0);
                2'b10:   ok_align = (ad[1:0] == 2'b00);
                default: ok_align = 1'b1;
            endcase
        end
    endfunction

    task init_mem;
        integer w, k;
        reg [31:0] v;
        begin
            for (w = 0; w < 4; w = w + 1) begin
                v = $random;
                wmem[w] = v;
                for (k = 0; k < 4; k = k + 1)
                    bmem[w*4 + k] = v[8*k +: 8];
            end
        end
    endtask

    // Directed check of strobes and write data
    task strobe_chk;
        input [31:0] ad;
        input [2:0]  ff;
        input [31:0] d;
        input        we;
        input [3:0]  exp_strb;
        input [31:0] exp_wdata;
        input [8*16-1:0] name;
        begin
            addr = ad; f3 = ff; store_data = d; mem_write = we; #1;
            expect32({28'd0, wstrb}, {28'd0, exp_strb}, name);
            if (we) expect32(wdata, exp_wdata, name);
            mem_write = 1'b0;
        end
    endtask

    // Store through the DUT (word memory) and through the reference (byte memory)
    task do_store;
        input [31:0] ad;
        input [31:0] d;
        input [2:0]  ff;
        integer k, nb;
        reg [31:0] tmp;
        reg [31:0] exp_strb;
        begin
            addr = ad; store_data = d; f3 = ff; mem_write = 1'b1; #1;
            nb = (ff[1:0] == 2'b00) ? 1 : (ff[1:0] == 2'b01) ? 2 : 4;
            // strobes must cover exactly nb bytes starting at (ad % 4)
            exp_strb = ((1 << nb) - 1) << (ad % 4);
            expect32({28'd0, wstrb}, exp_strb, "strobe pattern");
            // apply to word memory via DUT outputs
            tmp = wmem[ad >> 2];
            for (k = 0; k < 4; k = k + 1)
                if (wstrb[k]) tmp[8*k +: 8] = wdata[8*k +: 8];
            wmem[ad >> 2] = tmp;
            // apply to reference byte memory
            for (k = 0; k < nb; k = k + 1)
                bmem[ad + k] = d[8*k +: 8];
            mem_write = 1'b0;
        end
    endtask

    task do_load;
        input [31:0] ad;
        input [2:0]  ff;
        reg [31:0] refv;
        reg [7:0]  bv;
        reg [15:0] hv;
        begin
            if (ok_align(ad, ff)) begin
                addr = ad; f3 = ff; mem_write = 1'b0;
                raw_rdata = wmem[ad >> 2];
                #1;
                bv = bmem[ad];
                hv = {bmem[ad+1], bmem[ad]};
                case (ff)
                    3'b000:  refv = {{24{bv[7]}}, bv};
                    3'b001:  refv = {{16{hv[15]}}, hv};
                    3'b010:  refv = {bmem[ad+3], bmem[ad+2], bmem[ad+1], bmem[ad]};
                    3'b100:  refv = {24'd0, bv};
                    default: refv = {16'd0, hv};
                endcase
                expect32(load_data, refv, "load vs ref");
            end
        end
    endtask

    initial begin
        #50000000;
        $display("RESULT: FAIL (timeout)");
        $finish;
    end

    initial begin
        errors = 0; checks = 0;
        mem_write = 1'b0; addr = 0; store_data = 0; raw_rdata = 0; f3 = 0;

        // ---- Directed strobe / write-data checks (hand-written) ----
        //          addr  f3     data        we  strb    wdata
        strobe_chk(32'd0, 3'b000, 32'h000000AB, 1, 4'b0001, 32'hABABABAB, "sb off0");
        strobe_chk(32'd1, 3'b000, 32'h000000AB, 1, 4'b0010, 32'hABABABAB, "sb off1");
        strobe_chk(32'd2, 3'b000, 32'h000000AB, 1, 4'b0100, 32'hABABABAB, "sb off2");
        strobe_chk(32'd3, 3'b000, 32'h000000AB, 1, 4'b1000, 32'hABABABAB, "sb off3");
        strobe_chk(32'd0, 3'b001, 32'h0000BEEF, 1, 4'b0011, 32'hBEEFBEEF, "sh off0");
        strobe_chk(32'd2, 3'b001, 32'h0000BEEF, 1, 4'b1100, 32'hBEEFBEEF, "sh off2");
        strobe_chk(32'd4, 3'b010, 32'hCAFEF00D, 1, 4'b1111, 32'hCAFEF00D, "sw");
        strobe_chk(32'd4, 3'b010, 32'hCAFEF00D, 0, 4'b0000, 32'h0,        "no write");

        // ---- Directed load checks on raw word 0x8081FF7F ----
        raw_rdata = 32'h8081FF7F;
        f3 = 3'b000; addr = 32'd0; #1; expect32(load_data, 32'h0000007F, "lb off0");
        f3 = 3'b000; addr = 32'd1; #1; expect32(load_data, 32'hFFFFFFFF, "lb off1");
        f3 = 3'b000; addr = 32'd2; #1; expect32(load_data, 32'hFFFFFF81, "lb off2");
        f3 = 3'b000; addr = 32'd3; #1; expect32(load_data, 32'hFFFFFF80, "lb off3");
        f3 = 3'b100; addr = 32'd3; #1; expect32(load_data, 32'h00000080, "lbu off3");
        f3 = 3'b001; addr = 32'd0; #1; expect32(load_data, 32'hFFFFFF7F, "lh off0");
        f3 = 3'b001; addr = 32'd2; #1; expect32(load_data, 32'hFFFF8081, "lh off2");
        f3 = 3'b101; addr = 32'd0; #1; expect32(load_data, 32'h0000FF7F, "lhu off0");
        f3 = 3'b101; addr = 32'd2; #1; expect32(load_data, 32'h00008081, "lhu off2");
        f3 = 3'b010; addr = 32'd0; #1; expect32(load_data, 32'h8081FF7F, "lw");

        // ---- Random stores, then read everything back with every load type ----
        init_mem;
        for (n = 0; n < 2000; n = n + 1) begin
            r  = $random;
            st = r[7:4] % 3;            // 0=SB, 1=SH, 2=SW  (same as funct3 encoding)
            a  = r[11:8];               // 0..15
            if (st == 1) a = a & 14;    // halfword aligned
            if (st == 2) a = a & 12;    // word aligned
            do_store(a, $random, st);
            for (lt = 0; lt < 5; lt = lt + 1)
                for (a2 = 0; a2 < 16; a2 = a2 + 1)
                    do_load(a2, load_type(lt));
        end

        if (errors == 0) $display("RESULT: PASS (%0d checks)", checks);
        else             $display("RESULT: FAIL (%0d errors / %0d checks)", errors, checks);
        $finish;
    end
endmodule
