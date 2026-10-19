# p04_forward_corners.S - forwarding priority, distances and store paths
        addi x10, x0, 512

# 1: same register written 3 times; consumers at distance 1, 2, 3
        addi x1, x0, 1
        addi x1, x0, 2
        add  x2, x1, x0           # distance 1: EX/MEM must beat the older MEM/WB write -> 2
        addi x1, x0, 3
        nop
        add  x3, x1, x0           # distance 2: MEM/WB -> 3
        addi x1, x0, 4
        nop
        nop
        add  x4, x1, x0           # distance 3: regfile write-through -> 4
        check x2, 2
        check x3, 3
        check x4, 4

# 2: operands from different stages, and one register used for both operands
        addi x5, x0, 6
        addi x6, x0, 7
        add  x7, x5, x6           # x5 from MEM/WB, x6 from EX/MEM -> 13
        add  x8, x6, x5           # both from the register file -> 13
        add  x9, x6, x6           # same register on both ports -> 14
        check x7, 13
        check x8, 13
        check x9, 14

# 3: store data and store address forwarding
        addi x11, x0, 0x11
        sw   x11, 0(x10)          # data from EX/MEM
        addi x12, x0, 0x22
        nop
        sw   x12, 4(x10)          # data from MEM/WB
        addi x13, x10, 8          # x13 = 0x208
        addi x14, x0, 0x33
        sw   x14, 0(x13)          # address from MEM/WB, data from EX/MEM
        sw   x13, 12(x13)         # same register as address and data -> mem[0x214] = 0x208
        lw   x15, 0(x10)
        lw   x16, 4(x10)
        lw   x17, 8(x10)
        lw   x18, 20(x10)
        check x15, 0x11
        check x16, 0x22
        check x17, 0x33
        check x18, 0x208

# 4: byte store immediately followed by word load of the same word
        li   x1, 0x11223344
        sw   x1, 16(x10)          # 0x210
        addi x2, x0, 170          # 0xAA
        sb   x2, 17(x10)
        lw   x3, 16(x10)
        lbu  x4, 17(x10)
        check x3, 0x1122AA44
        check x4, 170

# 5: LUI whose immediate bits look like a source register that was just written
        addi x5, x0, 5
        lui  x6, 0x28             # imm bits [19:15] = 5, but LUI has no rs1
        check x6, 0x28000

# 6: x0 as destination in different positions
        addi x1, x0, 9
        add  x0, x1, x1           # ignored
        add  x2, x0, x1           # x0 must read 0 -> 9
        lw   x0, 0(x10)
        add  x3, x0, x1           # -> 9
        check x2, 9
        check x3, 9

        halt

fail:   li   x31, 1
        sw   x31, 2032(x0)
spin:   j    spin
