// rv32i_model.vh - independent behavioral RV32I reference model (NOT synthesizable)
//
// Included INSIDE the testbench module. It is a plain instruction-set simulator:
// no pipeline, one instruction per call of model_step, its own registers and
// byte-addressed 4 KB data memory. It must be written without looking at the
// RTL structure: it only follows the RISC-V spec.
//
// Unsupported/illegal encodings behave as NOPs, exactly like the core
// (FENCE, ECALL, EBREAK, CSR, bad funct3/funct7 -> no effect).
// A store to M_TOHOST ends the test (m_done = 1, m_tohost_val = stored value).

reg [31:0] m_regs [0:31];
reg [7:0]  m_mem  [0:4095];
reg [31:0] m_imem [0:1023];
reg [31:0] m_pc;
reg        m_done;
reg [31:0] m_tohost_val;

// description of the instruction executed by the latest model_step
reg [31:0] m_x_pc, m_x_instr, m_x_data;
reg        m_x_we;
reg [4:0]  m_x_rd;

localparam [31:0] M_TOHOST = 32'h000007F0;

task model_reset;
    integer k;
    begin
        for (k = 0; k < 32;   k = k + 1) m_regs[k] = 32'd0;
        for (k = 0; k < 4096; k = k + 1) m_mem[k]  = 8'd0;
        m_pc = RESET_VECTOR;
        m_done = 1'b0;
        m_tohost_val = 32'd0;
    end
endtask

task model_step;
    reg [31:0] ins, a, b, imm, res, npc, addr;
    reg [6:0]  opc, f7;
    reg [2:0]  f3;
    reg [4:0]  rd, rs1, rs2, sh;
    reg [11:0] ai;
    reg [7:0]  b0, b1, b2, b3;
    reg        we, take, legal;
    begin
        ins = m_imem[m_pc[11:2]];
        opc = ins[6:0];   rd  = ins[11:7];  f3 = ins[14:12];
        rs1 = ins[19:15]; rs2 = ins[24:20]; f7 = ins[31:25];
        a = m_regs[rs1];  b = m_regs[rs2];
        npc = m_pc + 32'd4;
        we = 1'b0; res = 32'd0; take = 1'b0; legal = 1'b1;
        imm = 32'd0; addr = 32'd0; sh = 5'd0;

        case (opc)
            7'b0110111: begin                                   // LUI
                res = {ins[31:12], 12'b0}; we = 1'b1;
            end
            7'b0010111: begin                                   // AUIPC
                res = m_pc + {ins[31:12], 12'b0}; we = 1'b1;
            end
            7'b1101111: begin                                   // JAL
                imm = {{11{ins[31]}}, ins[31], ins[19:12], ins[20], ins[30:21], 1'b0};
                res = m_pc + 32'd4; npc = m_pc + imm; we = 1'b1;
            end
            7'b1100111: begin                                   // JALR
                imm = {{20{ins[31]}}, ins[31:20]};
                res = m_pc + 32'd4; npc = (a + imm) & 32'hFFFFFFFE; we = 1'b1;
                legal = (f3 == 3'b000);
            end
            7'b1100011: begin                                   // BRANCH
                imm = {{19{ins[31]}}, ins[31], ins[7], ins[30:25], ins[11:8], 1'b0};
                case (f3)
                    3'b000:  take = (a == b);
                    3'b001:  take = (a != b);
                    3'b100:  take = ($signed(a) <  $signed(b));
                    3'b101:  take = ($signed(a) >= $signed(b));
                    3'b110:  take = (a <  b);
                    3'b111:  take = (a >= b);
                    default: take = 1'b0;
                endcase
                if (take) npc = m_pc + imm;
            end
            7'b0000011: begin                                   // LOAD
                imm = {{20{ins[31]}}, ins[31:20]};
                addr = a + imm; ai = addr[11:0];
                b0 = m_mem[ai];
                b1 = m_mem[ai + 12'd1];
                b2 = m_mem[ai + 12'd2];
                b3 = m_mem[ai + 12'd3];
                we = 1'b1;
                case (f3)
                    3'b000:  res = {{24{b0[7]}}, b0};
                    3'b001:  res = {{16{b1[7]}}, b1, b0};
                    3'b010:  res = {b3, b2, b1, b0};
                    3'b100:  res = {24'd0, b0};
                    3'b101:  res = {16'd0, b1, b0};
                    default: legal = 1'b0;
                endcase
            end
            7'b0100011: begin                                   // STORE
                imm = {{20{ins[31]}}, ins[31:25], ins[11:7]};
                addr = a + imm; ai = addr[11:0];
                case (f3)
                    3'b000: begin
                        m_mem[ai] = b[7:0];
                    end
                    3'b001: begin
                        m_mem[ai] = b[7:0];
                        m_mem[ai + 12'd1] = b[15:8];
                    end
                    3'b010: begin
                        m_mem[ai] = b[7:0];
                        m_mem[ai + 12'd1] = b[15:8];
                        m_mem[ai + 12'd2] = b[23:16];
                        m_mem[ai + 12'd3] = b[31:24];
                    end
                    default: legal = 1'b0;
                endcase
                if (legal && addr == M_TOHOST) begin
                    m_done = 1'b1;
                    m_tohost_val = b;
                end
            end
            7'b0010011: begin                                   // OP-IMM
                imm = {{20{ins[31]}}, ins[31:20]};
                sh = ins[24:20]; we = 1'b1;
                case (f3)
                    3'b000: res = a + imm;
                    3'b010: res = ($signed(a) < $signed(imm)) ? 32'd1 : 32'd0;
                    3'b011: res = (a < imm) ? 32'd1 : 32'd0;
                    3'b100: res = a ^ imm;
                    3'b110: res = a | imm;
                    3'b111: res = a & imm;
                    3'b001: begin
                        res = a << sh;
                        legal = (f7 == 7'b0000000);
                    end
                    default: begin                              // 3'b101
                        if (f7[5]) res = $signed(a) >>> sh;
                        else       res = a >> sh;
                        legal = (f7 == 7'b0000000) || (f7 == 7'b0100000);
                    end
                endcase
            end
            7'b0110011: begin                                   // OP
                we = 1'b1; sh = b[4:0];
                legal = (f7 == 7'b0000000) ||
                        (f7 == 7'b0100000 && (f3 == 3'b000 || f3 == 3'b101));
                case (f3)
                    3'b000: begin
                        if (f7[5]) res = a - b;
                        else       res = a + b;
                    end
                    3'b001: res = a << sh;
                    3'b010: res = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
                    3'b011: res = (a < b) ? 32'd1 : 32'd0;
                    3'b100: res = a ^ b;
                    3'b101: begin
                        if (f7[5]) res = $signed(a) >>> sh;
                        else       res = a >> sh;
                    end
                    3'b110: res = a | b;
                    default: res = a & b;
                endcase
            end
            default: begin
                // FENCE, SYSTEM, anything else: NOP
            end
        endcase

        if (!legal) begin
            we = 1'b0;
            npc = m_pc + 32'd4;
        end

        if (we && rd != 5'd0) m_regs[rd] = res;

        m_x_pc    = m_pc;
        m_x_instr = ins;
        m_x_we    = we && (rd != 5'd0);
        m_x_rd    = rd;
        m_x_data  = res;
        m_pc      = npc;
    end
endtask
