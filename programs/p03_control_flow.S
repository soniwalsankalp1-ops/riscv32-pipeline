# p03_control_flow.S - branches and jumps next to each other
# 'wrong' is a trap: reaching it means a flushed instruction executed.

# 1: backward loop, branch operand forwarded from the addi just before it
        addi x1, x0, 10
        addi x2, x0, 0
loop:   add  x2, x2, x1
        addi x1, x1, -1
        bne  x1, x0, loop
        check x2, 55

# 2: a taken branch sitting in the shadow of a taken branch must not execute
        beq  x0, x0, a1
        beq  x0, x0, wrong
        addi x3, x3, 1
a1:     check x3, 0

# 3: a jump in the shadow of a jump must not execute (so x5 is never written)
        jal  x6, j1
        jal  x5, wrong
        addi x4, x4, 1
j1:     check x5, 0
        check x4, 0

# 4: JAL straight to another JAL
        jal  x0, k1
        addi x7, x7, 1
k1:     jal  x0, k2
        addi x7, x7, 1
k2:     check x7, 0

# 5: call and return. f2 returns immediately, so the link value is used
#    right after the JAL wrote it.
        addi x8, x0, 0
        jal  x1, f1
        addi x8, x8, 100
        jal  x1, f2
        addi x8, x8, 1000
        j    done5
f1:     addi x8, x8, 7
        ret
f2:     ret
done5:  check x8, 1107

# 6: branch operands arriving from different pipeline stages
        addi x9,  x0, 5
        addi x10, x0, 5
        beq  x9, x10, m1          # x9 from MEM/WB, x10 from EX/MEM
        addi x11, x11, 1
m1:     addi x9,  x0, 6
        addi x10, x0, 7
        bne  x9, x10, m2          # taken (6 != 7)
        addi x11, x11, 1
m2:     bge  x9, x10, m3_bad      # not taken (6 >= 7 is false)
        j    m3
m3_bad: addi x11, x11, 1
m3:     check x11, 0

        halt

wrong:  j    fail
fail:   li   x31, 1
        sw   x31, 2032(x0)
spin:   j    spin
