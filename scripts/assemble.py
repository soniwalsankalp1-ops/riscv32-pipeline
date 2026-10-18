#!/usr/bin/env python3
"""assemble.py - tiny RV32I assembler (standard library only).

Usage:  python3 scripts/assemble.py prog.S -o build/prog.hex
        python3 scripts/assemble.py --selftest

Output: one 32-bit word per line, 8 hex digits ($readmemh format), plus a
        .lst listing next to it.

Syntax:
  - '#' or '//' start a comment; labels are 'name:'
  - registers: x0..x31 and ABI names (zero, ra, sp, t0.., a0.., s0..)
  - numbers: decimal, 0x hex, negative allowed
  - lui/auipc take the upper 20-bit value (lui x5, 0x12345 -> 0x12345000)
  - branch/jal targets: a label, or a raw numeric byte offset (jal x0, 0 = spin)
Pseudo-instructions:
  nop, mv, not, neg, seqz, snez, li, j, jr, ret,
  beqz, bnez, bltz, bgez, bgt, ble, bgtu, bleu,
  halt   -> sw x0, 0x7F0(x0) ; jal x0, 0   (store to 'tohost', then spin)
  check rs, imm -> li x30, imm ; bne rs, x30, fail   (needs a 'fail' label)
Directive: .word value   (.text/.globl/.section are ignored)
"""
import argparse
import os
import re
import sys

MAX_WORDS = 1024        # matches the 4 KB instruction memory of the testbench
TOHOST = 0x7F0          # store here to end a test


class AsmError(Exception):
    pass


# ---------------------------------------------------------------- registers
REGS = {}
for _i in range(32):
    REGS['x%d' % _i] = _i
REGS.update({'zero': 0, 'ra': 1, 'sp': 2, 'gp': 3, 'tp': 4, 'fp': 8, 's0': 8, 's1': 9})
for _i in range(3):
    REGS['t%d' % _i] = 5 + _i
for _i in range(8):
    REGS['a%d' % _i] = 10 + _i
for _i in range(2, 12):
    REGS['s%d' % _i] = 16 + _i
for _i in range(3, 7):
    REGS['t%d' % _i] = 25 + _i

IDENT = re.compile(r'^[A-Za-z_.][\w.]*$')


def reg(tok):
    key = tok.strip().lower()
    if key not in REGS:
        raise AsmError("bad register '%s'" % tok)
    return REGS[key]


def num(tok):
    try:
        return int(tok.strip(), 0)
    except ValueError:
        raise AsmError("bad number '%s'" % tok)


def rng(v, lo, hi, what):
    if not lo <= v <= hi:
        raise AsmError("%s %d out of range [%d, %d]" % (what, v, lo, hi))


def parse_mem(tok):
    """'imm(reg)' -> (imm, reg)"""
    m = re.fullmatch(r'\s*(.*?)\s*\(\s*(\w+)\s*\)\s*', tok)
    if not m:
        raise AsmError("bad memory operand '%s' (expected imm(reg))" % tok)
    imm = num(m.group(1)) if m.group(1) else 0
    return imm, reg(m.group(2))


# ---------------------------------------------------------------- encoders
def enc_r(f7, rs2, rs1, f3, rd, opc):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | opc


def enc_i(imm, rs1, f3, rd, opc):
    rng(imm, -2048, 2047, 'immediate')
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | opc


def enc_s(imm, rs2, rs1, f3):
    rng(imm, -2048, 2047, 'offset')
    return (((imm >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | \
           ((imm & 0x1F) << 7) | 0x23


def enc_b(off, rs2, rs1, f3):
    rng(off, -4096, 4094, 'branch offset')
    if off & 1:
        raise AsmError("branch offset %d is odd" % off)
    o = off & 0x1FFF
    return (((o >> 12) & 1) << 31) | (((o >> 5) & 0x3F) << 25) | (rs2 << 20) | \
           (rs1 << 15) | (f3 << 12) | (((o >> 1) & 0xF) << 8) | (((o >> 11) & 1) << 7) | 0x63


def enc_u(imm20, rd, opc):
    rng(imm20, -0x80000, 0xFFFFF, 'upper immediate')
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opc


def enc_j(off, rd):
    rng(off, -1048576, 1048574, 'jump offset')
    if off & 1:
        raise AsmError("jump offset %d is odd" % off)
    o = off & 0x1FFFFF
    return (((o >> 20) & 1) << 31) | (((o >> 1) & 0x3FF) << 21) | (((o >> 11) & 1) << 20) | \
           (((o >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F


R_OPS = {'add': (0x00, 0), 'sub': (0x20, 0), 'sll': (0x00, 1), 'slt': (0x00, 2),
         'sltu': (0x00, 3), 'xor': (0x00, 4), 'srl': (0x00, 5), 'sra': (0x20, 5),
         'or': (0x00, 6), 'and': (0x00, 7)}
I_OPS = {'addi': 0, 'slti': 2, 'sltiu': 3, 'xori': 4, 'ori': 6, 'andi': 7}
SH_OPS = {'slli': (0x00, 1), 'srli': (0x00, 5), 'srai': (0x20, 5)}
LOAD_OPS = {'lb': 0, 'lh': 1, 'lw': 2, 'lbu': 4, 'lhu': 5}
STORE_OPS = {'sb': 0, 'sh': 1, 'sw': 2}
BR_OPS = {'beq': 0, 'bne': 1, 'blt': 4, 'bge': 5, 'bltu': 6, 'bgeu': 7}


def target_offset(tok, pc, labels):
    tok = tok.strip()
    if IDENT.match(tok):
        if tok not in labels:
            raise AsmError("undefined label '%s'" % tok)
        return labels[tok] - pc
    return num(tok)


def encode(mnem, ops, pc, labels):
    def need(n):
        if len(ops) != n:
            raise AsmError("'%s' needs %d operands, got %d" % (mnem, n, len(ops)))

    if mnem == '.word':
        need(1)
        return num(ops[0]) & 0xFFFFFFFF
    if mnem in R_OPS:
        need(3)
        f7, f3 = R_OPS[mnem]
        return enc_r(f7, reg(ops[2]), reg(ops[1]), f3, reg(ops[0]), 0x33)
    if mnem in I_OPS:
        need(3)
        return enc_i(num(ops[2]), reg(ops[1]), I_OPS[mnem], reg(ops[0]), 0x13)
    if mnem in SH_OPS:
        need(3)
        sh = num(ops[2])
        rng(sh, 0, 31, 'shift amount')
        f7, f3 = SH_OPS[mnem]
        return (f7 << 25) | (sh << 20) | (reg(ops[1]) << 15) | (f3 << 12) | \
               (reg(ops[0]) << 7) | 0x13
    if mnem in LOAD_OPS:
        need(2)
        imm, rs1 = parse_mem(ops[1])
        return enc_i(imm, rs1, LOAD_OPS[mnem], reg(ops[0]), 0x03)
    if mnem in STORE_OPS:
        need(2)
        imm, rs1 = parse_mem(ops[1])
        return enc_s(imm, reg(ops[0]), rs1, STORE_OPS[mnem])
    if mnem in BR_OPS:
        need(3)
        off = target_offset(ops[2], pc, labels)
        return enc_b(off, reg(ops[1]), reg(ops[0]), BR_OPS[mnem])
    if mnem == 'lui':
        need(2)
        return enc_u(num(ops[1]), reg(ops[0]), 0x37)
    if mnem == 'auipc':
        need(2)
        return enc_u(num(ops[1]), reg(ops[0]), 0x17)
    if mnem == 'jal':
        if len(ops) == 1:
            return enc_j(target_offset(ops[0], pc, labels), 1)
        need(2)
        return enc_j(target_offset(ops[1], pc, labels), reg(ops[0]))
    if mnem == 'jalr':
        if len(ops) == 1:                       # jalr rs
            return enc_i(0, reg(ops[0]), 0, 1, 0x67)
        if len(ops) == 2:                       # jalr rd, imm(rs1)
            imm, rs1 = parse_mem(ops[1])
            return enc_i(imm, rs1, 0, reg(ops[0]), 0x67)
        need(3)                                 # jalr rd, rs1, imm
        return enc_i(num(ops[2]), reg(ops[1]), 0, reg(ops[0]), 0x67)
    raise AsmError("unknown instruction '%s'" % mnem)


# ---------------------------------------------------------------- pseudo-instructions
def expand(m, ops):
    """Return a list of (mnemonic, operands) base instructions."""
    if m in ('.text', '.globl', '.global', '.section'):
        return []
    if m == 'nop':
        return [('addi', ['x0', 'x0', '0'])]
    if m == 'mv':
        return [('addi', [ops[0], ops[1], '0'])]
    if m == 'not':
        return [('xori', [ops[0], ops[1], '-1'])]
    if m == 'neg':
        return [('sub', [ops[0], 'x0', ops[1]])]
    if m == 'seqz':
        return [('sltiu', [ops[0], ops[1], '1'])]
    if m == 'snez':
        return [('sltu', [ops[0], 'x0', ops[1]])]
    if m == 'li':
        v = num(ops[1])
        if not -(2 ** 31) <= v < 2 ** 32:
            raise AsmError("li value %d does not fit in 32 bits" % v)
        v &= 0xFFFFFFFF
        if v >= 2 ** 31:
            v -= 2 ** 32
        if -2048 <= v <= 2047:
            return [('addi', [ops[0], 'x0', str(v)])]
        lo = ((v & 0xFFF) ^ 0x800) - 0x800          # sign-extended low 12 bits
        hi = ((v - lo) >> 12) & 0xFFFFF
        out = [('lui', [ops[0], str(hi)])]
        if lo != 0:
            out.append(('addi', [ops[0], ops[0], str(lo)]))
        return out
    if m == 'j':
        return [('jal', ['x0', ops[0]])]
    if m == 'jr':
        return [('jalr', ['x0', ops[0], '0'])]
    if m == 'ret':
        return [('jalr', ['x0', 'x1', '0'])]
    if m == 'beqz':
        return [('beq', [ops[0], 'x0', ops[1]])]
    if m == 'bnez':
        return [('bne', [ops[0], 'x0', ops[1]])]
    if m == 'bltz':
        return [('blt', [ops[0], 'x0', ops[1]])]
    if m == 'bgez':
        return [('bge', [ops[0], 'x0', ops[1]])]
    if m == 'bgt':
        return [('blt', [ops[1], ops[0], ops[2]])]
    if m == 'ble':
        return [('bge', [ops[1], ops[0], ops[2]])]
    if m == 'bgtu':
        return [('bltu', [ops[1], ops[0], ops[2]])]
    if m == 'bleu':
        return [('bgeu', [ops[1], ops[0], ops[2]])]
    if m == 'halt':
        return [('sw', ['x0', '%d(x0)' % TOHOST]), ('jal', ['x0', '0'])]
    if m == 'check':
        return expand('li', ['x30', ops[1]]) + [('bne', [ops[0], 'x30', 'fail'])]
    return [(m, ops)]


# ---------------------------------------------------------------- two-pass assembly
def assemble(text):
    labels = {}
    items = []          # (addr, mnemonic, operands, lineno, source text)
    pc = 0
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.split('#')[0].split('//')[0].strip()
        while True:
            m = re.match(r'^([A-Za-z_.][\w.]*)\s*:\s*(.*)$', line)
            if not m:
                break
            if m.group(1) in labels:
                raise AsmError("line %d: duplicate label '%s'" % (lineno, m.group(1)))
            labels[m.group(1)] = pc
            line = m.group(2).strip()
        if not line:
            continue
        parts = line.split(None, 1)
        mnem = parts[0].lower()
        ops = [o.strip() for o in parts[1].split(',')] if len(parts) > 1 else []
        try:
            base = expand(mnem, ops)
        except AsmError as e:
            raise AsmError("line %d: %s" % (lineno, e))
        except IndexError:
            raise AsmError("line %d: wrong number of operands for '%s'" % (lineno, mnem))
        for k, (bm, bo) in enumerate(base):
            items.append((pc, bm, bo, lineno, raw.strip() if k == 0 else '    (expanded)'))
            pc += 4

    if len(items) > MAX_WORDS:
        raise AsmError("program has %d words; instruction memory holds %d" % (len(items), MAX_WORDS))

    words, listing = [], []
    for addr, bm, bo, lineno, src in items:
        try:
            w = encode(bm, bo, addr, labels)
        except AsmError as e:
            raise AsmError("line %d: %s" % (lineno, e))
        words.append(w)
        listing.append("%04x: %08x  %s" % (addr, w, src))
    return words, listing


# ---------------------------------------------------------------- self-test
SELFTEST = [
    ("addi x1, x0, 5",        [0x00500093]),
    ("addi x2, x1, 3",        [0x00308113]),
    ("add x3, x2, x1",        [0x001101B3]),
    ("sub x1, x2, x3",        [0x403100B3]),
    ("sw x3, 0(x0)",          [0x00302023]),
    ("lw x4, 0(x0)",          [0x00002203]),
    ("beq x0, x0, 12",        [0x00000663]),
    ("beq x0, x0, -4",        [0xFE000EE3]),
    ("jal x9, 8",             [0x008004EF]),
    ("jal x0, 0",             [0x0000006F]),
    ("lui x5, 0x12345",       [0x123452B7]),
    ("addi x1, x0, -1",       [0xFFF00093]),
    ("srai x1, x2, 3",        [0x40315093]),
    ("add x12, x9, x11",      [0x00B48633]),
    ("nop",                   [0x00000013]),
    ("ret",                   [0x00008067]),
    ("li x5, 0x12345678",     [0x123452B7, 0x67828293]),
]


def selftest():
    bad = 0
    for src, exp in SELFTEST:
        try:
            got, _ = assemble(src)
        except AsmError as e:
            got = str(e)
        if got != exp:
            bad += 1
            print("SELFTEST FAIL: %-22s got=%s exp=%s" % (src, got, ['%08x' % x for x in exp]))
    print("assembler self-test: %d/%d passed" % (len(SELFTEST) - bad, len(SELFTEST)))
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser(description="Tiny RV32I assembler")
    ap.add_argument('source', nargs='?')
    ap.add_argument('-o', '--output')
    ap.add_argument('--selftest', action='store_true')
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if not args.source:
        ap.error("source file required")
    with open(args.source) as f:
        text = f.read()
    try:
        words, listing = assemble(text)
    except AsmError as e:
        print("%s: error: %s" % (args.source, e), file=sys.stderr)
        return 1
    out = args.output or os.path.splitext(args.source)[0] + '.hex'
    d = os.path.dirname(out)
    if d:
        os.makedirs(d, exist_ok=True)
    with open(out, 'w') as f:
        f.write(''.join('%08x\n' % w for w in words))
    with open(os.path.splitext(out)[0] + '.lst', 'w') as f:
        f.write('\n'.join(listing) + '\n')
    print("%s: %d words -> %s" % (args.source, len(words), out))
    return 0


if __name__ == '__main__':
    sys.exit(main())
