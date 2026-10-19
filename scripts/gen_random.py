#!/usr/bin/env python3
"""gen_random.py - constrained-random RV32I program generator.

Usage: python3 scripts/gen_random.py --seed 7 --length 150 -o build/r7.S

Rules that keep every generated program valid and terminating:
  * control flow only jumps FORWARD, to the start of a later 'unit'
    (auipc+jalr and the 3-instruction memory sequence are atomic units)
  * data accesses stay inside 0x400..0x4FF and are always aligned
    (never near the tohost address 0x7F0)
  * only legal RV32I instructions are produced
Registers: x1..x10 are the random pool, x31 = data base 0x400,
           x29 = temp for computed addresses.
The same seed always produces the same program.
"""
import argparse
import random
import sys

BASE = 31
TMP = 29
POOL = list(range(1, 11))
R_OPS = ['add', 'sub', 'sll', 'slt', 'sltu', 'xor', 'srl', 'sra', 'or', 'and']
I_OPS = ['addi', 'slti', 'sltiu', 'xori', 'ori', 'andi']
SH_OPS = ['slli', 'srli', 'srai']
LOADS = [('lb', 1), ('lbu', 1), ('lh', 2), ('lhu', 2), ('lw', 4)]
STORES = [('sb', 1), ('sh', 2), ('sw', 4)]
BRANCHES = ['beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu']
EDGE_IMM = [0, 1, -1, 2047, -2048, 255, -256, 1024]
EDGE_VAL = [0, 1, 0xFFFFFFFF, 0x80000000, 0x7FFFFFFF, 0x0000FFFF,
            0xFFFF0000, 0x12345678, 0xDEADBEEF]
MAX_LENGTH = 250


class Gen:
    def __init__(self, seed, n):
        self.r = random.Random(seed)
        self.n = n
        self.recent = [1, 2, 3]       # last destination registers

    # ---- operand choosers
    def note(self, reg):
        if reg != 0:
            self.recent = (self.recent + [reg])[-3:]

    def pool(self):
        return self.r.choice(POOL)

    def dst(self):
        return 0 if self.r.random() < 0.06 else self.pool()

    def src(self):
        x = self.r.random()
        if x < 0.45:
            return self.r.choice(self.recent)     # dependency on a recent result
        if x < 0.50:
            return 0
        return self.pool()

    def imm12(self):
        if self.r.random() < 0.2:
            return self.r.choice(EDGE_IMM)
        return self.r.randint(-2048, 2047)

    def value32(self):
        if self.r.random() < 0.4:
            return self.r.choice(EDGE_VAL)
        return self.r.getrandbits(32)

    def fwd_target(self, idx):
        """index of the unit a forward jump lands on (idx+1 .. n, n = final halt)"""
        return idx + 1 + self.r.randint(0, min(3, self.n - 1 - idx))

    # ---- units: each returns (size_in_instructions, fn(starts) -> list of lines)
    def u_alu_r(self, idx):
        op = self.r.choice(R_OPS)
        a, b = self.src(), self.src()
        d = self.dst()
        self.note(d)
        line = "%s x%d, x%d, x%d" % (op, d, a, b)
        return 1, (lambda starts: [line])

    def u_alu_i(self, idx):
        op = self.r.choice(I_OPS)
        a = self.src()
        d = self.dst()
        self.note(d)
        line = "%s x%d, x%d, %d" % (op, d, a, self.imm12())
        return 1, (lambda starts: [line])

    def u_shift(self, idx):
        op = self.r.choice(SH_OPS)
        a = self.src()
        d = self.dst()
        self.note(d)
        line = "%s x%d, x%d, %d" % (op, d, a, self.r.randint(0, 31))
        return 1, (lambda starts: [line])

    def u_upper(self, idx):
        op = self.r.choice(['lui', 'auipc'])
        d = self.dst()
        self.note(d)
        line = "%s x%d, 0x%05x" % (op, d, self.r.getrandbits(20))
        return 1, (lambda starts: [line])

    def u_mem(self, idx):
        if self.r.random() < 0.5:
            op, al = self.r.choice(LOADS)
            off = self.r.randrange(0, 256, al)
            d = self.dst()
            self.note(d)
            line = "%s x%d, %d(x%d)" % (op, d, off, BASE)
        else:
            op, al = self.r.choice(STORES)
            off = self.r.randrange(0, 256, al)
            line = "%s x%d, %d(x%d)" % (op, self.src(), off, BASE)
        return 1, (lambda starts: [line])

    def u_memc(self, idx):
        # computed address: tmp = (rs & 0xFC) + base, then access off(tmp)
        a = self.src()
        pre = ["andi x%d, x%d, 252" % (TMP, a),
               "add x%d, x%d, x%d" % (TMP, TMP, BASE)]
        if self.r.random() < 0.5:
            op, al = self.r.choice(LOADS)
            off = self.r.randrange(0, 4, al)
            d = self.dst()
            self.note(d)
            last = "%s x%d, %d(x%d)" % (op, d, off, TMP)
        else:
            op, al = self.r.choice(STORES)
            off = self.r.randrange(0, 4, al)
            last = "%s x%d, %d(x%d)" % (op, self.src(), off, TMP)
        lines = pre + [last]
        return 3, (lambda starts: lines)

    def u_branch(self, idx):
        op = self.r.choice(BRANCHES)
        a = self.src()
        b = a if self.r.random() < 0.2 else self.src()    # equal operands sometimes
        tgt = self.fwd_target(idx)
        return 1, (lambda starts: ["%s x%d, x%d, %d" % (op, a, b, starts[tgt] - starts[idx])])

    def u_jal(self, idx):
        d = self.dst()
        self.note(d)
        tgt = self.fwd_target(idx)
        return 1, (lambda starts: ["jal x%d, %d" % (d, starts[tgt] - starts[idx])])

    def u_jalr(self, idx):
        t = self.pool()
        self.note(t)
        d = self.dst()
        self.note(d)
        tgt = self.fwd_target(idx)
        odd = self.r.choice([0, 1])       # odd offset: JALR must clear bit 0 of the target

        def fn(starts):
            off = starts[tgt] - starts[idx] + odd
            return ["auipc x%d, 0" % t, "jalr x%d, %d(x%d)" % (d, off, t)]
        return 2, fn

    def unit(self, idx):
        kinds = ['alu_r', 'alu_i', 'shift', 'upper', 'mem', 'memc', 'branch', 'jal', 'jalr']
        weights = [22, 16, 6, 5, 18, 8, 14, 4, 4]
        kind = self.r.choices(kinds, weights)[0]
        return getattr(self, 'u_' + kind)(idx)

    # ---- whole program
    def prologue(self):
        lines = ["li x%d, 1024" % BASE]                    # data window base 0x400
        for reg in POOL:
            lines.append("li x%d, 0x%08x" % (reg, self.value32()))
        for j in range(8):                                 # preload some memory words
            lines.append("sw x%d, %d(x%d)" % (POOL[j], 4 * j, BASE))
        return lines

    def program(self):
        lines = self.prologue()
        units = [self.unit(i) for i in range(self.n)]
        starts = [0]
        for size, _ in units:
            starts.append(starts[-1] + 4 * size)
        for _, fn in units:
            lines.extend(fn(starts))
        lines.append("halt")
        return lines


def main():
    ap = argparse.ArgumentParser(description="Constrained-random RV32I program generator")
    ap.add_argument('--seed', type=int, required=True)
    ap.add_argument('--length', type=int, default=150, help="number of units (max %d)" % MAX_LENGTH)
    ap.add_argument('-o', '--output', required=True)
    args = ap.parse_args()
    if not 1 <= args.length <= MAX_LENGTH:
        print("length must be 1..%d" % MAX_LENGTH, file=sys.stderr)
        return 1
    lines = Gen(args.seed, args.length).program()
    with open(args.output, 'w') as f:
        f.write("# random program, seed=%d length=%d (regenerate with gen_random.py)\n"
                % (args.seed, args.length))
        f.write("\n".join(lines) + "\n")
    return 0


if __name__ == '__main__':
    sys.exit(main())
