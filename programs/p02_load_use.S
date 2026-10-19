# p02_load_use.S - a load feeding every kind of consumer
# x10 = data base 0x200. x30/x31 reserved (check macro / failure code).
        addi x10, x0, 512
        addi x11, x0, 100
        sw   x11, 0(x10)          # mem[0x200] = 100
        addi x12, x0, 100

# 1: load -> ALU rs1
        lw   x1, 0(x10)
        addi x2, x1, 1
        check x2, 101

# 2: load -> ALU rs2
        addi x3, x0, 5
        lw   x1, 0(x10)
        add  x4, x3, x1
        check x4, 105

# 3: load -> store data
        lw   x1, 0(x10)
        sw   x1, 8(x10)
        lw   x5, 8(x10)
        check x5, 100

# 4: load -> store address (pointer fetched from memory)
        addi x6, x0, 0x240
        sw   x6, 4(x10)           # mem[0x204] = 0x240
        addi x7, x0, 77
        lw   x8, 4(x10)           # x8 = 0x240
        sw   x7, 0(x8)            # store address comes straight from the load
        lw   x9, 0x40(x10)        # address 0x240
        check x9, 77

# 5: load -> branch operands (as rs1, then as rs2)
        lw   x1, 0(x10)
        beq  x1, x12, t5a         # taken (100 == 100)
        addi x13, x13, 1
t5a:    lw   x1, 0(x10)
        bne  x12, x1, t5b_bad     # not taken
        j    t5b
t5b_bad: addi x13, x13, 1
t5b:    check x13, 0

# 6: load -> JALR base (target address stored in memory)
        auipc x14, 0              # P
        addi  x14, x14, 24        # target = P + 24
        sw    x14, 12(x10)
        lw    x15, 12(x10)
        jalr  x0, x15, 0          # at P+16
        addi  x16, x16, 1         # P+20, must be skipped
        check x16, 0              # P+24 = jump target

# 7: pointer chasing (load -> load address)
        addi x6, x0, 0x214
        sw   x6, 16(x10)          # mem[0x210] = 0x214
        li   x6, 0xABC
        sw   x6, 20(x10)          # mem[0x214] = 0xABC
        lw   x1, 16(x10)
        lw   x2, 0(x1)
        check x2, 0xABC

# 8: load into x0 must neither stall nor forward
        lw   x0, 0(x10)
        add  x1, x0, x0
        check x1, 0

# 9: back-to-back loads feeding one consumer
        lw   x1, 0(x10)
        lw   x2, 0(x10)
        add  x3, x1, x2
        check x3, 200

# 10: load, one unrelated instruction, then the consumer (no stall needed)
        lw   x1, 0(x10)
        addi x9, x0, 1
        add  x2, x1, x9
        check x2, 101

# 11: load feeding a dependent chain
        lw   x1, 0(x10)
        addi x2, x1, 1
        addi x3, x2, 1
        addi x4, x3, 1
        check x4, 103

        halt

fail:   li   x31, 1
        sw   x31, 2032(x0)
spin:   j    spin
