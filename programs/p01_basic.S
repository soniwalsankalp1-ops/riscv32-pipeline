# p01_basic.S - first directed program
# Two independent checks:
#   1. 'check reg, value' compares against a hand-computed value (jumps to 'fail' if wrong)
#   2. the testbench compares every retired instruction with the reference model
# x30 is reserved for 'check'. x31 holds the failure code.

# ---- 1. EX/MEM and MEM/WB forwarding, back-to-back dependent chain ----
        addi x1, x0, 5
        addi x2, x1, 3          # x1 from EX/MEM
        add  x3, x2, x1         # x2 from EX/MEM, x1 from MEM/WB
        sub  x4, x3, x2
        add  x5, x4, x4         # x5 = 10
        add  x5, x5, x5         # x5 = 20 (depends on the previous instruction)
        add  x5, x5, x5         # x5 = 40
        check x2, 8
        check x3, 13
        check x4, 5
        check x5, 40

# ---- 2. Forwarding priority: EX/MEM (younger) must beat MEM/WB (older) ----
        addi x6, x0, 1
        addi x6, x6, 2          # x6 = 3
        addi x6, x6, 4          # x6 = 7
        add  x7, x6, x6         # both older instructions write x6; must use 7 -> 14
        check x6, 7
        check x7, 14

# ---- 3. x0 is never written and never forwarded ----
        addi x0, x0, 5          # write to x0 must be ignored
        add  x8, x0, x0         # a wrong forward of the x0 write would give 10
        check x8, 0

# ---- 4. Shifts and signed/unsigned compares ----
        li   x1, 0x80000000
        srai x2, x1, 31         # 0xFFFFFFFF
        srli x3, x1, 31         # 1
        slli x4, x3, 31         # 0x80000000
        slt  x5, x1, x3         # signed: -2^31 < 1  -> 1
        sltu x6, x1, x3         # unsigned: 0x80000000 < 1 -> 0
        check x2, -1
        check x3, 1
        check x4, 0x80000000
        check x5, 1
        check x6, 0

# ---- 5. Memory: store/load, load-use stall, load->store, load->branch ----
        addi x10, x0, 256       # base address 0x100
        li   x11, 0x12345678
        sw   x11, 0(x10)
        lw   x12, 0(x10)
        add  x13, x12, x0       # load-use: 1-cycle stall, then forward
        check x13, 0x12345678
        lw   x14, 0(x10)
        sw   x14, 4(x10)        # store data comes from the load just before
        lw   x15, 4(x10)
        check x15, 0x12345678
        lw   x16, 0(x10)
        beq  x16, x12, ok1      # load-use feeding a branch compare (taken)
        addi x18, x0, 99        # must be skipped
ok1:    check x18, 0

# ---- 6. Sub-word loads and stores (memory word 0x8081FF7F at 0x108) ----
        li   x19, 0x8081FF7F
        sw   x19, 8(x10)
        lb   x20, 8(x10)        # 0x7F
        lb   x21, 9(x10)        # 0xFF -> sign extended
        lb   x22, 10(x10)       # 0x81 -> sign extended
        lb   x23, 11(x10)       # 0x80 -> sign extended
        lbu  x24, 11(x10)       # 0x80 zero extended
        lh   x25, 8(x10)        # 0xFF7F -> sign extended
        lh   x26, 10(x10)       # 0x8081 -> sign extended
        lhu  x27, 10(x10)       # 0x8081 zero extended
        check x20, 127
        check x21, -1
        check x22, 0xFFFFFF81
        check x23, 0xFFFFFF80
        check x24, 128
        check x25, 0xFFFFFF7F
        check x26, 0xFFFF8081
        check x27, 0x8081
        addi x28, x0, 0x55
        sb   x28, 9(x10)        # byte 1 of the word -> 0x8081557F
        sh   x28, 10(x10)       # upper halfword -> 0x0055557F
        lw   x29, 8(x10)
        check x29, 0x0055557F

# ---- 7. All six branches, taken and not taken (x3 counts wrong paths) ----
        addi x1, x0, -1
        addi x2, x0, 1
        addi x3, x0, 0
        blt  x1, x2, b1         # -1 < 1 signed: taken
        addi x3, x3, 1
b1:     bltu x1, x2, b2_bad     # 0xFFFFFFFF < 1 unsigned: NOT taken
        j    b2
b2_bad: addi x3, x3, 1
b2:     bge  x2, x1, b3         # 1 >= -1 signed: taken
        addi x3, x3, 1
b3:     bgeu x2, x1, b4_bad     # 1 >= 0xFFFFFFFF unsigned: NOT taken
        j    b4
b4_bad: addi x3, x3, 1
b4:     bne  x1, x2, b5         # taken
        addi x3, x3, 1
b5:     beq  x1, x1, b6         # taken
        addi x3, x3, 1
b6:     check x3, 0

# ---- 8. JAL / JALR (return needs the link value right after JAL writes it) ----
        addi x8, x0, 0
        jal  x1, func1
        addi x8, x8, 100        # runs after the return
        j    after_call
func1:  jalr x0, x1, 1          # target = x1 + 1, bit 0 cleared -> x1
after_call:
        check x8, 100

# ---- 9. LUI and AUIPC ----
        auipc x9, 0
        auipc x10, 0
        sub  x11, x10, x9       # two AUIPCs, 4 bytes apart
        check x11, 4
        lui  x12, 0xABCDE
        check x12, 0xABCDE000

        halt                    # store to tohost (value 0 = pass), then spin

fail:   li   x31, 1
        sw   x31, 2032(x0)      # tohost = 1 -> testbench reports failure
spin:   j    spin
