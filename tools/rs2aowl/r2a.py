#!/usr/bin/env python3
"""One-time translator: upstream's pumpkin/src/block Rust subset -> aowlmony.  r2a.py <rs> <out> <upstream path>
Anything it cannot translate becomes R2A_MANUAL(...) so that the compile fails there: never a silent stub."""
import re, sys, os, json

KW3 = ['..=', '<<=', '>>=', '...']
KW2 = ['::', '->', '=>', '==', '!=', '<=', '>=', '&&', '||', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '<<', '>>', '..']

def tokenize(s):
    i = 0; out = []; n = len(s); pending = []
    while i < n:
        c = s[i]
        if c.isspace(): i += 1; continue
        if s.startswith('//', i):
            j = s.find('\n', i); j = n if j < 0 else j
            t = s[i:j]
            if not t.startswith('///') and not t.startswith('//!') or True:
                pending.append(t.lstrip('/!').strip())
            i = j; continue
        if s.startswith('/*', i):
            i = s.find('*/', i) + 2; continue
        m = re.match(r"r#([A-Za-z_]\w*)", s[i:])
        if m: out.append(('id', m[1], pending)); pending = []; i += m.end(); continue
        m = re.match(r'(?:b|r#*)?"', s[i:])
        if m and (c == '"' or c in 'br'):
            if c == 'r':
                h = re.match(r'r(#*)"', s[i:]); end = '"' + h[1]; j = s.find(end, i + h.end())
                out.append(('str', s[i + h.end():j], pending)); pending = []; i = j + len(end); continue
            st = i + m.end(); j = st
            while s[j] != '"':
                j += 2 if s[j] == '\\' else 1
            out.append(('str', s[st:j], pending)); pending = []; i = j + 1; continue
        m = re.match(r"'(\\.|[^\\'])'", s[i:])
        if m: out.append(('chr', m[1], pending)); pending = []; i += m.end(); continue
        m = re.match(r"'[A-Za-z_]\w*", s[i:])
        if m: out.append(('life', m[0], pending)); pending = []; i += m.end(); continue
        m = re.match(r"(0x[0-9a-fA-F_]+|0b[01_]+|\d[\d_]*(?:\.\d[\d_]*|\.(?![\w.]))?(?:[eE][-+]?\d+)?)((?:_?[iuf](?:8|16|32|64|128|size))?)", s[i:])
        if m:
            # 1..2 must not read 1. as a float: the regex needs a digit after the dot, so it does not.
            out.append(('num', (m[1].replace('_', '') + ('0' if m[1].endswith('.') else ''), m[2].lstrip('_')), pending)); pending = []; i += m.end(); continue
        m = re.match(r"[A-Za-z_]\w*", s[i:])
        if m: out.append(('id', m[0], pending)); pending = []; i += m.end(); continue
        for L in (KW3, KW2):
            hit = next((k for k in L if s.startswith(k, i)), None)
            if hit: break
        if hit: out.append(('p', hit, pending)); pending = []; i += len(hit); continue
        out.append(('p', c, pending)); pending = []; i += 1
    out.append(('eof', '', pending))
    return out

def camel(s):
    if s.isupper() and len(s) > 1: return s
    parts = s.split('_')
    lead = ''
    while parts and parts[0] == '': parts.pop(0)
    if not parts: return 'x'
    r = parts[0] + ''.join(p[:1].upper() + p[1:] for p in parts[1:])
    return r

def pascal(s):
    return ''.join(p[:1].upper() + p[1:].lower() for p in s.split('_'))

NIM_KW = {'type': 'kind0', 'in': 'in0', 'is': 'is0', 'of': 'of0', 'end': 'end0', 'from': 'from0', 'to': 'to0', 'block': 'blockRef', 'method': 'method0',
          'proc': 'proc0', 'func': 'func0', 'var': 'var0', 'let': 'let0', 'const': 'const0', 'not': 'not0', 'and': 'and0', 'or': 'or0', 'div': 'div0',
          'mod': 'mod0', 'shl': 'shl0', 'shr': 'shr0', 'iterator': 'iterator0', 'template': 'template0', 'object': 'object0', 'addr': 'addr0', 'done': 'done0',
          'result': 'result0', 'len': 'len0', 'nil': 'nil0', 'bind': 'bind0', 'mixin': 'mixin0', 'using': 'using0', 'with': 'with0', 'without': 'without0', 'interface': 'interface0', 'out': 'out0'}
def name(s):
    c = camel(s)
    return NIM_KW.get(c, c)
FIELD_KW = {'type': 'kind0', 'block': 'block0'}

PRIM = {'u8': 'uint8', 'u16': 'uint16', 'u32': 'uint32', 'u64': 'uint64', 'usize': 'int', 'i8': 'int8', 'i16': 'int16', 'i32': 'int32', 'i64': 'int64',
        'isize': 'int', 'f32': 'float32', 'f64': 'float64', 'bool': 'bool', 'str': 'string', 'String': 'string', 'char': 'char', 'u128': 'uint64', 'i128': 'int64'}
WRAP = {'Arc', 'Box', 'Mutex', 'RwLock', 'Rc', 'AtomicCell', 'Weak', 'ArcSwap', 'Pin', 'Cell', 'RefCell', 'Cow'}
ATOMIC = {'AtomicBool': 'bool', 'AtomicU8': 'uint8', 'AtomicU16': 'uint16', 'AtomicU32': 'uint32', 'AtomicU64': 'uint64', 'AtomicI8': 'int8', 'AtomicI16': 'int16',
          'AtomicI32': 'int32', 'AtomicI64': 'int64', 'AtomicUsize': 'int', 'AtomicF32': 'float32'}
TYPEMAP = {'World': 'BlockWorld', 'Player': 'BlockPlayer', 'EntityBase': 'BlockActor', 'Server': 'BlockServer', 'BlockAccessor': 'BlockWorld', 'Self': None}
TYPE_LIKE = re.compile(r'^[A-Z][a-z]')

class Ctx:
    def __init__(self):
        self.selfname = None; self.tmp = 0; self.alias = {}; self.locals = set()

class P:
    def __init__(self, toks, known):
        self.t = toks; self.i = 0; self.known = known; self.ctx = Ctx(); self.manual = []; self.locals_struct = set(); self.partial = []
        self.ret = None; self.closures = []
    # --- token helpers
    def pk(self, k=0): return self.t[min(self.i + k, len(self.t) - 1)]
    def v(self, k=0):
        t = self.pk(k); return t[1] if t[0] in ('p', 'id') else None
    def nx(self):
        t = self.t[self.i]; self.i += 1; return t
    def at(self, *vals): return self.v() in vals
    def eat(self, val):
        if self.v() == val: self.i += 1; return True
        return False
    def need(self, val):
        if not self.eat(val):
            raise SyntaxError('expected %r at %r near %s' % (val, self.pk()[1], self.near()))
    def near(self):
        return ' '.join(str(t[1]) for t in self.t[max(0, self.i - 8):self.i + 6])
    def split_gt(self):
        t = self.pk()
        if t[0] == 'p' and t[1] in ('>>', '>=', '>>='):
            self.t[self.i] = ('p', '>', t[2]); self.t.insert(self.i + 1, ('p', t[1][1:], []))
    def skip_generics(self):
        if not self.at('<'): return []
        d = 0; out = []
        while True:
            self.split_gt()
            t = self.nx()
            if t[1] == '<' and t[0] == 'p': d += 1
            elif t[1] == '>' and t[0] == 'p':
                d -= 1
                if d == 0: return out
            out.append(t[1])
    def skip_attrs(self):
        attrs = []
        while self.at('#'):
            self.nx(); self.eat('!'); self.need('[')
            d = 1; s = []
            while d:
                t = self.nx()
                if t[1] == '[' and t[0] == 'p': d += 1
                elif t[1] == ']' and t[0] == 'p':
                    d -= 1
                    if not d: break
                s.append(t[1])
            attrs.append(s)
        return attrs
    # --- types
    def ty(self):
        self.split_gt()
        while self.at('&', '&&', '*'):
            self.nx()
            if self.pk()[0] == 'life': self.nx()
            self.eat('mut'); self.eat('const')
        if self.pk()[0] == 'life': self.nx(); self.eat('+')
        if self.eat('dyn') or self.eat('impl'):
            r = self.ty()
            while self.eat('+'):
                if self.pk()[0] == 'life': self.nx()
                else: self.ty()
            return r
        if self.eat('('):
            xs = []
            while not self.eat(')'):
                xs.append(self.ty()); self.eat(',')
            return '(' + ', '.join(xs) + ')' if xs else 'void'
        if self.eat('['):
            e = self.ty()
            if self.eat(';'):
                n = self.expr(); self.need(']')
                return 'array[%s, %s]' % (n, e)
            self.need(']')
            return 'seq[%s]' % e
        if self.at('fn', 'Fn', 'FnOnce', 'FnMut'):
            self.nx()
            self.need('(')
            while not self.eat(')'):
                self.ty(); self.eat(',')
            if self.eat('->'): self.ty()
            return 'R2A_MANUAL_fnType'
        segs = []
        while True:
            t = self.nx(); segs.append(t[1])
            if not self.eat('::'): break
        last = segs[-1]; args = []
        self.split_gt()
        if self.at('<'):
            self.nx()
            while True:
                self.split_gt()
                if self.eat('>'): break
                if self.pk()[0] == 'life': self.nx()
                elif self.pk()[0] == 'id' and self.v(1) == '=':
                    self.nx(); self.nx(); args.append(self.ty())
                else: args.append(self.ty())
                self.eat(','); self.split_gt()
        if last in WRAP: return args[-1] if args else 'R2A_MANUAL_wrap'
        if last in ATOMIC: return ATOMIC[last]
        if last == 'Option': return 'Option[%s]' % args[0]
        if last in ('Vec', 'VecDeque'): return 'seq[%s]' % args[0]
        if last == 'HashMap' or last == 'FxHashMap': return 'Table[%s, %s]' % (args[0], args[1])
        if last == 'HashSet' or last == 'FxHashSet': return 'HashSet[%s]' % args[0]
        if last == 'Result': return 'BlockResult[%s]' % args[0]
        if last.endswith('Future'): return args[-1] if args else 'void'
        if last == 'MutexGuard': return args[-1] if args else 'R2A_MANUAL_guard'
        if last == 'Future': return args[-1] if args else 'void'
        if last == 'Self': return self.ctx.selfname or 'Self'
        if last in PRIM: return PRIM[last]
        if last in TYPEMAP and TYPEMAP[last]: return TYPEMAP[last]
        if args: return '%s[%s]' % (last, ', '.join(args))
        return last
    # --- patterns: returns a pattern tree
    def pat(self):
        self.eat('|')
        alts = [self.pat1()]
        while self.eat('|'): alts.append(self.pat1())
        return alts[0] if len(alts) == 1 else ('or', alts)
    def pat1(self):
        while self.at('&', '&&'): self.nx()
        self.eat('ref'); m = self.eat('mut')
        t = self.pk()
        if t[0] in ('num', 'str', 'chr'):
            lit = self.lit(self.nx())
            if self.at('..=', '..'):
                op = self.nx()[1]
                hi = self.lit(self.nx()) if self.pk()[0] == 'num' else None
                return ('range', lit, hi, op)
            return ('lit', lit)
        if self.at('-'):
            self.nx(); lit = '-' + self.lit(self.nx())
            if self.at('..='):
                self.nx(); self.eat('-'); return ('range', lit, self.lit(self.nx()), '..=')
            return ('lit', lit)
        if self.at('('):
            self.nx(); xs = []
            while not self.eat(')'):
                xs.append(self.pat()); self.eat(',')
            return ('tuple', xs)
        if self.at('['):
            self.nx(); xs = []
            while not self.eat(']'):
                xs.append(self.pat()); self.eat(',')
            return ('slice', xs)
        if self.at('..'):
            self.nx(); return ('rest',)
        if self.at('_'):
            self.nx(); return ('wild',)
        segs = [self.nx()[1]]
        while self.eat('::'): segs.append(self.nx()[1])
        if self.at('('):
            self.nx(); xs = []
            while not self.eat(')'):
                xs.append(self.pat()); self.eat(',')
            return ('call', segs, xs)
        if self.at('{'):
            self.nx(); fs = []
            while not self.eat('}'):
                if self.eat('..'): continue
                self.eat('ref'); self.eat('mut')
                f = self.nx()[1]
                sub = self.pat() if self.eat(':') else ('bind', f, False)
                fs.append((f, sub)); self.eat(',')
            return ('struct', segs, fs)
        if self.at('@'):
            self.nx(); return ('at', segs[0], self.pat())
        if len(segs) == 1 and (segs[0][0].islower() or segs[0][0] == '_'):
            return ('bind', segs[0], m)
        return ('path', segs)
    def pat_value(self, p):
        if p[0] == 'lit': return p[1]
        if p[0] == 'path': return self.path_value(p[1])
        return None
    def pat_cond(self, p, subj):
        """returns (cond or None, [(name, expr)])"""
        k = p[0]
        if k in ('wild', 'rest'): return None, []
        if k == 'bind': return None, [(name(p[1]), subj)]
        if k == 'lit': return '%s == %s' % (subj, p[1]), []
        if k == 'path':
            if p[1][-1] == 'None' and len(p[1]) == 1: return '%s.isNone' % subj, []
            en = p[1][-2] if len(p[1]) >= 2 else ''
            if en == 'Self': en = self.ctx.selfname
            if en in self.known['payload']: return '%s.kind == %sKind.k%s' % (subj, en, p[1][-1]), []
            return '%s == %s' % (subj, self.path_value(p[1])), []
        if k == 'range': return '%s >= %s and %s %s %s' % (subj, p[1], subj, '<=' if p[3] == '..=' else '<', p[2]), []
        if k == 'or':
            cs = []
            for a in p[1]:
                c, b = self.pat_cond(a, subj)
                if b: return 'R2A_MANUAL("or-binding")', []
                cs.append(c or 'true')
            return '(' + ' or '.join(cs) + ')', []
        if k == 'tuple':
            cs = []; bs = []
            for i, a in enumerate(p[1]):
                c, b = self.pat_cond(a, '%s[%d]' % (subj, i))
                if c: cs.append(c)
                bs += b
            return ' and '.join(cs) if cs else None, bs
        if k == 'call':
            h = p[1][-1]
            if h == 'Some':
                c, b = self.pat_cond(p[2][0], subj + '.unsafeGet')
                return subj + '.isSome' + (' and ' + c if c else ''), b
            if h == 'Ok' or h == 'Err':
                c, b = self.pat_cond(p[2][0], subj + ('.value' if h == 'Ok' else '.error'))
                return (subj + '.isOk' if h == 'Ok' else 'not ' + subj + '.isOk') + (' and ' + c if c else ''), b
            # A payload enum variant: `kind` plus a field per variant.
            en = p[1][-2] if len(p[1]) >= 2 else ''
            if en == 'Self': en = self.ctx.selfname
            cs = ['%s.kind == %sKind.k%s' % (subj, en, h)]; bs = []
            for i, a in enumerate(p[2]):
                c, b = self.pat_cond(a, '%s.f%d%s' % (subj, i, h))
                if c: cs.append(c)
                bs += b
            return ' and '.join(cs), bs
        if k == 'struct':
            bs = []; cs = []
            for f, sub in p[2]:
                c, b = self.pat_cond(sub, '%s.%s' % (subj, FIELD_KW.get(f, camel(f))))
                if c: cs.append(c)
                bs += b
            return (' and '.join(cs) if cs else None), bs
        if k == 'at':
            c, b = self.pat_cond(p[2], subj)
            return c, b + [(name(p[1]), subj)]
        return 'R2A_MANUAL("pattern")', []
    def pat_lets(self, p, vars_mut=False):
        """irrefutable pattern to the text left of `=`"""
        if p[0] == 'bind': return name(p[1])
        if p[0] == 'wild': return '_'
        if p[0] == 'tuple': return '(' + ', '.join(self.pat_lets(x) for x in p[1]) + ')'
        return 'R2A_MANUAL_pat'
    def tmpn(self):
        self.ctx.tmp += 1
        return 't%d' % self.ctx.tmp
    # --- literals and paths
    def lit(self, t):
        if t[0] == 'num':
            v, suf = t[1]
            if suf in PRIM:
                q = {'uint8': 'u8', 'uint16': 'u16', 'uint32': 'u32', 'uint64': 'u64', 'int8': 'i8', 'int16': 'i16', 'int32': 'i32', 'int64': 'i64', 'float32': 'f32', 'float64': 'f64'}.get(PRIM[suf])
                if q: return "%s'%s" % (v, q)
                return v
            return v
        if t[0] == 'str': return json.dumps(t[1])
        if t[0] == 'chr': return "'%s'" % t[1]
        raise SyntaxError('lit')
    def path_value(self, segs):
        segs = [s for s in segs if s not in ('crate', 'self', 'pumpkin_data', 'super', 'pumpkin_util', 'pumpkin_world', 'pumpkin_protocol', 'block_properties', 'std')]
        if segs and segs[0] == 'Self' and self.ctx.selfname: segs[0] = self.ctx.selfname
        last = segs[-1]
        if len(segs) >= 2:
            head = segs[-2]
            if head in self.known['payload'] and last in self.known['payload'][head]:
                return '%s(kind: %sKind.k%s)' % (head, head, last)
            if head == 'Block' and len(segs) >= 3 and segs[-3] == 'tag': return 'Block_' + last
            if head == 'Item' and len(segs) >= 3 and segs[-3] == 'tag': return 'Item_' + last
            if head == 'Fluid' and len(segs) >= 3 and segs[-3] == 'tag': return 'Fluid_' + last
            if head == 'Block' and last.isupper() or (head == 'Block' and '_' in last and last.upper() == last): return 'block' + pascal(last) + '()'
            if head == 'Item' and last.upper() == last: return 'item' + pascal(last) + '()'
            if head == 'Fluid' and last.upper() == last: return 'Fluid.' + last
            if head == 'BlockId' and last.upper() == last: return 'blockId' + pascal(last)
            if head == 'ItemStack' and last == 'EMPTY': return 'emptyItemStack()'
            if head == 'Ordering': return '0'
            if head == 'Axis': return 'BlockAxis.' + last
            if head == 'StatisticCategory': return 'sc' + last
            if head == 'CustomStatistic': return 'cs' + last
            if head == 'Sound': return 'sd' + last
            if head == 'SoundCategory': return 'sc' + last
            if head == 'WorldEvent': return 'we' + last
            if head == 'Particle': return 'pt' + last
            if head == 'BlockFlags': return {'NOTIFY_NEIGHBORS': 'BfNotifyNeighbors', 'NOTIFY_LISTENERS': 'BfNotifyListeners', 'NOTIFY_ALL': 'BfNotifyAll', 'FORCE_STATE': 'BfForceState', 'SKIP_DROPS': 'BfSkipDrops', 'MOVED': 'BfMoved', 'SKIP_REDSTONE_WIRE_STATE_REPLACEMENT': 'BfSkipRedstoneWireStateReplacement', 'SKIP_BLOCK_ENTITY_REPLACED_CALLBACK': 'BfSkipBlockEntityReplacedCallback', 'SKIP_BLOCK_ADDED_CALLBACK': 'BfSkipBlockAddedCallback', 'SKIP_NEIGHBOR_UPDATE': 'BfSkipNeighborUpdate'}.get(last, 'Bf' + pascal(last))
            if head == 'TickPriority': return 'tp' + last
            if head == 'BlockActionResult': return 'bar' + last
            if head == 'BlockStateId' and last == 'AIR': return 'blockStateIdAir'
            if head in PRIM and last in ('MAX', 'MIN'): return ('high' if last == 'MAX' else 'low') + '(%s)' % PRIM[head]
            if head in self.known['structs'] or head in self.known['payload']:
                if last.upper() == last: return last
                if last[0].isupper(): return head + '.' + last
                return name(last)
            if last[0].isupper() and head[0].isupper(): return head + '.' + last  # an enum value
            if last.upper() == last: return last
        if last[0].isupper(): return last
        return name(last)
    # --- expressions. Each returns text; statements needing hoisting go to self.hoist
    PREC = [('||',), ('&&',), ('==', '!=', '<', '>', '<=', '>='), ('|',), ('^',), ('&',), ('<<', '>>'), ('+', '-'), ('*', '/', '%')]
    OPS = {'||': 'or', '&&': 'and', '|': 'or', '^': 'xor', '&': 'and', '<<': 'shl', '>>': 'shr', '%': 'mod'}
    def expr(self, nostruct=False):
        return self.assign(nostruct)
    def assign(self, ns):
        l = self.range_(ns)
        if self.at('=', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '<<=', '>>='):
            op = self.nx()[1]; r = self.assign(ns)
            if op == '=': return '%s = %s' % (l, r)
            if op in ('+=', '-=', '*=', '/='): return '%s %s %s' % (l, op, r)
            return '%s = %s %s %s' % (l, l, self.OPS[op[:-1]], r)
        return l
    def range_(self, ns):
        if self.at('..', '..='):
            op = self.nx()[1]; return 'R2A_MANUAL("open range")'
        l = self.bin(0, ns)
        if self.at('..', '..='):
            op = self.nx()[1]
            if self.at(')', ']', '{', ','): return 'R2A_MANUAL("open range")'
            r = self.bin(0, ns)
            return '%s %s %s' % (l, '..' if op == '..=' else '..<', r)
        return l
    def bin(self, lv, ns):
        if lv >= len(self.PREC): return self.cast(ns)
        l = self.bin(lv + 1, ns)
        while self.pk()[0] == 'p' and self.v() in self.PREC[lv]:
            op = self.nx()[1]; r = self.bin(lv + 1, ns)
            if op == '/':
                pass
            l = '(not (%s == %s))' % (l, r) if op == '!=' else '(%s %s %s)' % (l, self.OPS.get(op, op), r)
        return l
    def cast(self, ns):
        e = self.unary(ns)
        while self.eat('as'):
            t = self.ty()
            e = '%s(%s)' % (t, e)
        return e
    def unary(self, ns):
        if self.eat('!'): return '(not %s)' % self.unary(ns)
        if self.eat('-'): return '(-%s)' % self.unary(ns)
        if self.eat('*'): return self.unary(ns)
        if self.at('&', '&&'):
            self.nx(); self.eat('mut'); return self.unary(ns)
        return self.postfix(ns)
    DROP = {'iter', 'into_iter', 'clone', 'as_ref', 'as_deref', 'as_mut', 'copied', 'cloned', 'to_owned', 'borrow', 'into', 'as_str', 'to_string_lossy', 'as_slice', 'lock', 'upgrade', 'load_full', 'iter_mut', 'read', 'write', 'as_any'}
    def args(self):
        self.need('(')
        xs = []
        while not self.eat(')'):
            xs.append(self.expr()); self.eat(',')
        return xs
    def postfix(self, ns):
        e = self.primary(ns)
        while True:
            if self.eat('?'):
                if self.ret and self.ret.startswith('Option['):
                    tq = self.tmpn()
                    self.hoist.append('let %s = %s' % (tq, e))
                    self.hoist.append('if %s.isNone: return none[%s]()' % (tq, self.ret[7:-1]))
                    e = tq + '.unsafeGet'
                else:
                    e = 'R2A_MANUAL_try(%s)' % e
                continue
            if self.at('('):
                e = '%s(%s)' % (e, ', '.join(self.args())); continue
            if self.at('['):
                self.nx(); ix = self.expr(); self.need(']'); e = '%s[%s]' % (e, ix); continue
            if self.at('.'):
                self.nx(); t = self.nx()
                if t[1] == 'await': continue
                if t[0] == 'num':
                    if t[1][0] == '0' and re.search(r'(pos|Pos|position|Position|location|Location|Offset)$', e):
                        e = e + '.vec'
                        continue
                    e = '%s[%s]' % (e, t[1][0]) if '.' not in t[1][0] else '%s[%s][%s]' % ((e,) + tuple(t[1][0].split('.')))
                    continue
                m = t[1]
                gen = []
                if self.at('::'):
                    self.nx(); gen = self.skip_generics()
                if m == 'random' and gen:
                    self.args()
                    e = 'randomOf(%s)' % PRIM.get(str(gen[1]) if len(gen) > 1 else '', 'float32')
                    continue
                if m in ('downcast_ref', 'cast_any', 'downcast') and gen:
                    self.args()
                    e = 'asType(%s, %s)' % (e, ''.join(str(x) for x in gen if x != '<'))
                    continue
                if self.at('('):
                    if m in self.DROP:
                        self.args(); continue
                    a = self.args()
                    e = self.method(e, m, a); continue
                e = '%s.%s' % (e, FIELD_KW.get(m, camel(m))); continue
            return e
    def method(self, e, m, a):
        A = ', '.join(a)
        if m == 'map_or' and len(a) == 2 and a[1].startswith('__CL'):
            pn, body, pre = self.closures[int(a[1][4:-2])]
            tmp = self.tmpn(); r = self.tmpn()
            H = self.hoist
            H.append('let %s = %s' % (tmp, e))
            H.append('var %s = %s' % (r, a[0]))
            H.append('if %s.isSome:' % tmp)
            H.append('  let %s = %s.unsafeGet' % (pn, tmp))
            H.extend('  ' + x for x in pre)
            H.append('  %s = %s' % (r, body))
            return r
        cl = self.closure_arg(a)
        if cl is not None:
            r = self.combinator(e, m, cl)
            if r is not None: return r
        if m == 'load': return e
        if m == 'get_block_entity_as': pass
        if m == 'store': return '%s = %s' % (e, a[0])
        if m == 'fetch_add': return '%s += %s' % (e, a[0])
        if m == 'fetch_sub': return '%s -= %s' % (e, a[0])
        if m == 'unwrap' or m == 'expect': return '%s.get()' % e
        if m == 'unwrap_or_else' or m == 'map_or' or m == 'is_some_and': pass
        if m == 'unwrap_or': return '%s.get(%s)' % (e, a[0])
        if m == 'is_empty': return 'isEmpty(%s)' % e
        if m == 'len': return 'len(%s)' % e
        if m == 'to_string': return '$(%s)' % e
        if m == 'push': return '%s.add(%s)' % (e, A)
        if m == 'contains' : return 'contains(%s, %s)' % (e, A)
        if m == 'powi' or m == 'powf': return 'pow(float64(%s), float64(%s))' % (e, A)
        if m == 'floor' or m == 'ceil' or m == 'sqrt' or m == 'round': return '%s(%s)' % (m, e)
        if m == 'abs': return 'abs(%s)' % e
        if m == 'clamp': return 'clamp(%s, %s)' % (e, A)
        if m == 'saturating_sub': return 'saturatingSub(%s, %s)' % (e, A)
        if m == 'saturating_add': return 'saturatingAdd(%s, %s)' % (e, A)
        if m == 'rem_euclid': return 'floorMod(%s, %s)' % (e, A)
        if e == 'self' and getattr(self, 'in_trait_impl', False) and m not in self.known['tm'] and self.ctx.selfname:
            e = self.ctx.selfname + '()'
        if e == 'self' and m in self.known['tm'] and self.ctx.selfname and not getattr(self, 'cur_trait', None):
            tr = self.known['tm'][m]
            sn = self.ctx.selfname
            if (sn, tr) not in self.known['impls']:
                # A method of its own BlockBehaviour impl.
                nm = name(m)
                return '%s%s%s_BlockBehaviour(%s)' % (sn[0].lower(), sn[1:], nm[0].upper() + nm[1:], A)
            return '%s(%s%s)' % (name(m), sn[0].lower() + sn[1:] + 'As' + tr + '()', ', ' + A if A else '')
        return '%s.%s(%s)' % (e, name(m), A)
    def closure_arg(self, a):
        if len(a) == 1 and a[0].startswith('__CL'):
            return self.closures[int(a[0][4:-2])]
        return None
    def combinator(self, e, m, cl):
        pn, body, pre = cl
        tmp = self.tmpn(); r = self.tmpn()
        H = self.hoist
        inner = ['  ' + x for x in pre]
        if m == 'is_some_and' or m == 'is_none_or':
            H.append('let %s = %s' % (tmp, e))
            H.append('var %s = %s' % (r, 'false' if m == 'is_some_and' else 'true'))
            H.append('if %s.isSome:' % tmp)
            H.append('  let %s = %s.unsafeGet' % (pn, tmp))
            H.extend(inner); H.append('  %s = %s' % (r, body))
            return r
        if m == 'any' or m == 'all':
            H.append('var %s = %s' % (r, 'false' if m == 'any' else 'true'))
            H.append('for %s in %s:' % (pn, e))
            H.extend(inner)
            H.append('  if %s:' % (body if m == 'any' else 'not (%s)' % body))
            H.append('    %s = %s' % (r, 'true' if m == 'any' else 'false'))
            H.append('    break')
            return r
        if m == 'map' and e.startswith('['):
            # `[a, b].map(|x| ..)`: upstream's one use yields bools.
            H.append('var %s = newSeq[bool]()' % r)
            H.append('for %s in %s:' % (pn, e))
            H.extend(inner); H.append('  %s.add(%s)' % (r, body))
            return r
        if m == 'then' and self.ret and self.ret.startswith('Option['):
            H.append('var %s = none[%s]()' % (r, self.ret[7:-1]))
            H.append('if %s:' % e)
            H.extend(inner); H.append('  %s = some(%s)' % (r, body))
            return r
        if m == 'map' and self.ret and self.ret.startswith('Option['):
            H.append('let %s = %s' % (tmp, e))
            H.append('var %s = none[%s]()' % (r, self.ret[7:-1]))
            H.append('if %s.isSome:' % tmp)
            H.append('  let %s = %s.unsafeGet' % (pn, tmp))
            H.extend(inner); H.append('  %s = some(%s)' % (r, body))
            return r
        if m == 'unwrap_or_else':
            H.append('let %s = %s' % (tmp, e))
            H.append('let %s =' % r)
            H.append('  if %s.isSome: %s.unsafeGet' % (tmp, tmp))
            H.append('  else:')
            H.extend(['  ' + x for x in inner]); H.append('    %s' % body)
            return r
        return None
    def closure(self):
        return 'R2A_MANUAL("closure")'
    def parse_closure(self):
        st = self.i
        params = []
        if not self.eat('||'):
            self.need('|')
            while not self.eat('|'):
                params.append(self.pat1())
                if self.eat(':'): self.ty()
                self.eat(',')
        if self.eat('->'): self.ty()
        pn = '_' if not params else self.pat_lets(params[0])
        if len(params) > 1: pn = 'R2A_MANUAL_closure_params'
        saved = self.hoist; self.hoist = []
        # A closure body in braces with statements is left to the hand pass.
        if self.at('{'):
            lines = self.braced(1, True)
            # The last value of the block is the closure's value, however many lines it takes.
            cb = self.tmpn()
            pre = ['let %s = block:' % cb] + lines
            body = cb
        else:
            body = self.expr(); pre = list(self.hoist)
        self.hoist = saved
        self.closures.append((pn, body, pre))
        return '__CL%d__' % (len(self.closures) - 1)
    def skip_closure(self):
        if self.eat('||'): pass
        else:
            self.need('|')
            while not self.eat('|'): self.nx()
        if self.eat('->'): self.ty()
        self.expr()
    def block_lines(self, ind, value=False):
        """the statements of a { } at this indentation."""
        return self.stmts(ind, value)
    def hoisted_control(self, ns):
        """if/match/block in expression position: hoist it into a temporary."""
        tmp = self.tmpn()
        lines = self.braced(1, True) if self.at('{') else self.control(1, True)
        self.hoist.append('let %s = block:' % tmp)
        self.hoist.extend(lines)
        return tmp
    def primary(self, ns):
        t = self.pk()
        if t[0] in ('num', 'str', 'chr'): return self.lit(self.nx())
        v = self.v()
        if v == '(':
            self.nx()
            if self.eat(')'): return 'void0'
            xs = [self.expr()]; tup = False
            while self.eat(','):
                tup = True
                if self.at(')'): break
                xs.append(self.expr())
            self.need(')')
            return '(' + ', '.join(xs) + ')'
        if v == '[':
            self.nx(); xs = []
            if self.eat(']'): return '[]'
            xs.append(self.expr())
            if self.eat(';'):
                n = self.expr(); self.need(']'); return 'R2A_MANUAL("array repeat")'
            while self.eat(','):
                if self.at(']'): break
                xs.append(self.expr())
            self.need(']')
            return '[' + ', '.join(xs) + ']'
        if v in ('if', 'match', '{', 'unsafe', 'loop', 'while', 'for'):
            return self.hoisted_control(ns)
        if v == 'async':
            self.nx(); self.eat('move')
            if self.at('|', '||'):
                return self.parse_closure()
            return self.hoisted_control(ns)
        if v == 'return':
            self.nx()
            if self.at(';', '}', ',', ')'): return 'return'
            return 'return ' + self.expr()
        if v == 'break': self.nx(); return 'break'
        if v == 'continue': self.nx(); return 'continue'
        if v == 'true' or v == 'false': self.nx(); return v
        if v == '|' or v == '||' or v == 'move':
            self.eat('move'); return self.parse_closure()
        if v == '<':  # <Self as T>::f or <T>::f
            self.nx(); a = self.ty(); tr = None
            if self.eat('as'): tr = self.ty()
            self.split_gt(); self.need('>'); self.need('::')
            f = self.nx()[1]
            if self.at('('):
                args = self.args()
                return self.trait_call(tr or a, f, args)
            return 'R2A_MANUAL_qpath'
        if v == 'self':
            self.nx()
            if self.at('::'):
                pass
            else:
                return 'self'
            self.i -= 1
        if t[0] != 'id': raise SyntaxError('primary %r near %s' % (t[1], self.near()))
        return self.pathexpr(ns)
    def trait_call(self, tr, f, args):
        """T::m(self, ...): self as the trait T."""
        tr = tr.split('[')[0]
        if tr in self.known['traits'] and args and args[0] == 'self':
            sn = self.ctx.selfname
            if sn:
                args = [sn[0].lower() + sn[1:] + 'As' + tr + '()'] + args[1:]
        if tr == 'BlockBehaviour' and args and args[0] == 'self': return 'R2A_MANUAL("self as BlockBehaviour")'
        return '%s(%s)' % (name(f), ', '.join(args))
    def pathexpr(self, ns):
        segs = [self.nx()[1]]
        gen = []
        while self.at('::'):
            self.nx()
            if self.at('<'):
                gen = self.skip_generics(); continue
            segs.append(self.nx()[1])
        if self.at('!') and self.v(1) in ('(', '[', '{'):
            self.nx(); return self.macro(segs[-1])
        if self.at('{') and not ns and segs[-1][0].isupper():
            return self.structlit(segs)
        head = segs[-2] if len(segs) >= 2 else None
        last = segs[-1]
        if self.at('('):
            a = self.args()
            return self.pathcall(segs, head, last, a, gen)
        if last == 'None' and len(segs) == 1: return self.none_expr()
        if len(segs) == 1 and last in self.ctx.alias: return self.ctx.alias[last]
        if len(segs) == 1 and name(last) in self.ctx.alias: return self.ctx.alias[name(last)]
        if len(segs) == 1 and last == 'Self': return self.ctx.selfname
        return self.path_value(segs) if not (len(segs) == 1 and last[0].islower()) else name(last)
    def none_expr(self):
        if self.ret and self.ret.startswith('Option['): return 'none[%s]()' % self.ret[7:-1]
        return 'R2A_NONE'
    def pathcall(self, segs, head, last, a, gen):
        A = ', '.join(a)
        if len(segs) == 1:
            if last == 'Some': return 'some(%s)' % A
            if last == 'Ok': return 'okResult(%s)' % A
            if last == 'Err': return 'errResult(%s)' % A
            if last == 'Box' : return A
            return '%s(%s)' % (name(last), A)
        if head == 'Box' and last == 'pin': return a[0]
        if head in ('Box', 'Arc', 'Mutex', 'RwLock', 'Rc', 'AtomicCell', 'ArcSwap') or head in ATOMIC:
            if last in ('new', 'clone', 'from', 'from_ref'): return a[0]
        if head == 'BlockFlags' and last == 'empty': return "0'u32"
        if head in ('Vec', 'VecDeque') and last in ('new', 'with_capacity'): return '@[]'
        if head in ('HashMap', 'FxHashMap') and last in ('new', 'default'): return 'initTable()'
        if head in PRIM and last in ('from', 'try_from'): return '%s(%s)' % (PRIM[head], A)
        if head in PRIM and last in ('max', 'min'): return '%s(%s)' % (last, A)
        if head == 'cmp' and last in ('max', 'min'): return '%s(%s)' % (last, A)
        if head == 'BlockDirection' and last in ('all', 'horizontal', 'vertical', 'update_order', 'abstract_block_update_order', 'flow_directions'):
            return 'blockDirection' + pascal(last).replace('_', '') + '()'
        if head == 'Self' and self.ctx.selfname: head = self.ctx.selfname
        if head in self.known['payload'] and last in self.known['payload'][head]:
            return '%s(kind: %sKind.k%s, %s)' % (head, head, last, ', '.join('f%d%s: %s' % (i, last, x) for i, x in enumerate(a)))
        if head in self.known['traits']:
            return self.trait_call(head, last, a)
        if head == 'NbtCompound' and last == 'new': return 'newCompound()'
        if head == 'rand' and last == 'random':
            return 'randomOf(%s)' % PRIM.get(str(gen[1]) if len(gen) > 1 else '', 'float32')
        if head == 'tag' or head is None: return '%s(%s)' % (name(last), A)
        if head[0].isupper():
            if head in self.known['structs'] or head in self.known['payload']:
                if last == 'new': return 'new%s(%s)' % (head, A)
                if last == 'default': return 'default%s(%s)' % (head, A)
                return '%s(%s)' % (name(last), A)
            if last == 'new': return 'new%s(%s)' % (head, A)
            if last == 'default':
                return '%s.defaultFor(%s)' % (head, A)
            return '%s.%s(%s)' % (head, name(last), A) if A else '%s.%s()' % (head, name(last))
        return '%s(%s)' % (name(last), A)
    def structlit(self, segs):
        self.need('{'); xs = []
        n = segs[-1]
        if n == 'Self': n = self.ctx.selfname
        if len(segs) >= 2 and segs[-2][0].isupper(): n = 'R2A_MANUAL_variant_' + n
        while not self.eat('}'):
            if self.eat('..'):
                self.expr(); xs.append('R2A_MANUAL_update: 0'); continue
            f = self.nx()[1]
            fv = FIELD_KW.get(f, camel(f))
            if self.eat(':'): xs.append('%s: %s' % (fv, self.expr()))
            else: xs.append('%s: %s' % (fv, self.ctx.alias.get(f, name(f))))
            self.eat(',')
        return '%s(%s)' % (n, ', '.join(xs))
    def macro(self, m):
        op = self.nx()[1]; cl = {'(': ')', '[': ']', '{': '}'}[op]
        if m == 'matches':
            e = self.expr(); self.need(','); p = self.pat()
            g = None
            if self.eat('if'): g = self.expr()
            self.eat(','); self.need(cl)
            c, b = self.pat_cond(p, e)
            if b or g: return 'R2A_MANUAL("matches! binding")'
            return '(%s)' % (c or 'true')
        xs = []
        while not self.eat(cl):
            xs.append(self.expr()); self.eat(',')
            if self.at(';'):
                self.nx(); n = self.expr(); self.need(cl)
                return 'R2A_MANUAL("repeat %s")' % n
        if m == 'vec': return '@[' + ', '.join(xs) + ']'
        if m == 'format': return 'rustFormat(' + ', '.join(xs) + ')'
        if m in ('warn', 'info', 'debug', 'trace', 'error', 'println', 'eprintln', 'log'): return 'discard'
        if m in ('unreachable', 'panic', 'todo', 'unimplemented'): return 'rustPanic("' + m + '")'
        if m == 'assert': return 'doAssert ' + xs[0]
        if m == 'assert_eq': return 'doAssert %s == %s' % (xs[0], xs[1])
        return 'R2A_MANUAL("macro %s")' % m
    # --- control flow: returns lines relative to indentation ind (spaces = 2*ind)
    def control(self, ind, value):
        v = self.v()
        if v == 'if': return self.if_(ind, value)
        if v == 'match': return self.match(ind, value)
        if v == 'unsafe': self.nx()
        if v == '{' or v == 'unsafe':
            return self.braced_block(ind, value)
        if v == 'loop':
            self.nx(); b = self.braced(ind + 1, False)
            return [pad(ind) + 'while true:'] + b
        if v == 'while':
            self.nx()
            if self.eat('let'):
                p = self.pat(); self.need('='); e = self.with_hoist(ind, lambda: self.expr(True))
                c, bs = self.pat_cond(p, 't')
                tmp = self.tmpn()
                c, bs = self.pat_cond(p, tmp)
                b = self.braced(ind + 1, False)
                return e[0] + [pad(ind) + 'while true:', pad(ind + 1) + 'let %s = %s' % (tmp, e[1]), pad(ind + 1) + 'if not (%s): break' % c] + [pad(ind + 1) + 'let %s = %s' % x for x in bs] + b
            pre, c = self.with_hoist(ind, lambda: self.expr(True))
            b = self.braced(ind + 1, False)
            return pre + [pad(ind) + 'while %s:' % c] + b
        if v == 'for':
            self.nx(); p = self.pat(); self.need('in')
            pre, e = self.with_hoist(ind, lambda: self.expr(True))
            head = self.pat_lets(p)
            for nm in re.findall(r'\w+', head): self.decl.add(nm)
            # `for x in f()` over an array result fails to borrow: through a local.
            if e.endswith(')') and ' ..' not in e:
                t0 = self.tmpn()
                pre = pre + [pad(ind) + 'let %s = %s' % (t0, e)]
                e = t0
            b = self.braced(ind + 1, False)
            if head == 'R2A_MANUAL_pat': head = 'R2A_MANUAL_forpat'
            # A `for` body that is a single discardable call fails, so such a body gets a closing `continue`.
            real = [x for x in b if not x.strip().startswith('#')]
            if len(real) == 1 and ('setBlockState(' in real[0] or 'breakBlock(' in real[0]): b.append(pad(ind + 1) + 'continue')
            return pre + [pad(ind) + 'for %s in %s:' % (head.strip('()') if p[0] == 'tuple' else head, e)] + b
        raise SyntaxError('control ' + str(v))
    def braced_block(self, ind, value):
        return [pad(ind) + 'block:'] + self.braced(ind + 1, value)
    def braced(self, ind, value):
        self.need('{')
        saved = dict(self.ctx.alias)
        lines = self.stmts(ind, value)
        self.ctx.alias = saved
        self.need('}')
        if not [l for l in lines if not l.strip().startswith('#')]: lines = lines + [pad(ind) + 'discard']
        return lines
    def with_hoist(self, ind, f):
        saved = getattr(self, 'hoist', [])
        self.hoist = []
        e = f()
        h = self.hoist; self.hoist = saved
        return [pad(ind) + x if not x.startswith('  ') or True else x for x in rebase(h, ind)], e
    def if_(self, ind, value):
        self.need('if')
        parts = self.if_parts()
        # Everything after the first part must not run unless the parts before it passed.
        # A later `let` over a plain place reads nothing that can fail, so it may run first.
        nested = any(p[0] == 'let' and not re.fullmatch(r'let t\d+ = [\w.]+', p[1][-1]) for p in parts[1:])
        if nested:
            return self.if_nested(parts, ind, value)
        out = []
        conds = []; binds = []
        for k, p in enumerate(parts):
            if k > 0 and p[1] and p[0] != 'let':
                # A condition with statements of its own runs only if those before it passed.
                c0 = self.tmpn()
                out.append(pad(ind) + 'var %s = false' % c0)
                out.append(pad(ind) + 'if %s:' % ' and '.join(conds))
                out += [pad(ind + 1) + x for x in p[1]]
                out.append(pad(ind + 1) + '%s = %s' % (c0, p[2]))
                conds = [c0]
                continue
            out += [pad(ind) + x for x in p[1]]
            conds.append(p[2])
            binds += p[3]
        body = self.braced(ind + 1, value)
        out.append(pad(ind) + 'if %s:' % ' and '.join(conds))
        out += [pad(ind + 1) + 'let %s = %s' % b for b in binds]
        out += body
        return out + self.if_rest(ind, value)
    def if_rest(self, ind, value):
        out = []
        while self.at('else'):
            self.nx()
            if self.at('if'):
                save = self.i
                self.nx()
                parts = self.if_parts()
                if len(parts) == 1 and not parts[0][1]:
                    body = self.braced(ind + 1, value)
                    out.append(pad(ind) + 'elif %s:' % parts[0][2])
                    out += [pad(ind + 1) + 'let %s = %s' % b for b in parts[0][3]]
                    out += body
                    continue
                # Needs a statement first: nest under the else.
                self.i = save
                out.append(pad(ind) + 'else:')
                out += self.if_(ind + 1, value)
                return out
            out.append(pad(ind) + 'else:')
            out += self.braced(ind + 1, value)
            break
        return out
    def if_nested(self, parts, ind, value):
        out = []
        lbl = None
        # The else, when there is one, runs when any part fails: a labelled block carries the body's way out.
        self.ctx.tmp += 1
        probe_else = None
        level = ind + 1
        lbl = 'chain%d' % self.ctx.tmp
        out.append(pad(ind) + 'block %s:' % lbl)
        for p in parts:
            out += [pad(level) + x for x in p[1]]
            out.append(pad(level) + 'if %s:' % p[2])
            out += [pad(level + 1) + 'let %s = %s' % b for b in p[3]]
            level += 1
        body = self.braced(level, value)
        out += body
        if self.at('else'):
            out.append(pad(level) + 'break ' + lbl)
            self.nx()
            if self.at('if'):
                out += self.if_(ind + 1, value)
            else:
                out += self.braced(ind + 1, value)
        return out
    def if_parts(self):
        """`a && let P = e && b`: each part as (kind, lines to run first, condition, bindings)."""
        parts = []
        while True:
            if self.eat('let'):
                p = self.pat(); self.need('=')
                pr, e = self.with_hoist(0, lambda: self.bin(2, True))
                tmp = self.tmpn()
                pre = pr + ['let %s = %s' % (tmp, e)]
                if p[0] == 'call' and p[1][-1] == 'Some' and p[2][0][0] == 'bind':
                    binds = []
                    if p[2][0][2]:
                        binds.append(('\x01' + name(p[2][0][1]), tmp + '.unsafeGet'))
                    else:
                        binds.append((name(p[2][0][1]), tmp + '.unsafeGet'))
                        self.ctx.alias[p[2][0][1]] = tmp + '.unsafeGet'
                    parts.append(('let', pre, tmp + '.isSome', binds))
                else:
                    c, b = self.pat_cond(p, tmp)
                    for nm, val in b: self.ctx.alias[nm] = val
                    parts.append(('let', pre, c or 'true', b))
            else:
                pr, e = self.with_hoist(0, lambda: self.bin(2, True))
                parts.append(('cond', pr, e, []))
            if self.at('||') and len(parts) == 1 and parts[0][0] == 'cond':
                self.nx(); pr, e2 = self.with_hoist(0, lambda: self.bin(0, True))
                parts[0] = ('cond', parts[0][1] + pr, '(%s or %s)' % (parts[0][2], e2), [])
            if not self.eat('&&'):
                break
        for x in parts:
            for nm, _ in x[3]: self.decl.add(nm.lstrip(chr(1)))
        return parts
    def match(self, ind, value):
        self.need('match')
        pre, subj = self.with_hoist(ind, lambda: self.expr(True))
        self.need('{')
        arms = []
        while not self.eat('}'):
            self.skip_attrs()
            comments = self.pk()[2]
            p = self.pat(); g = None
            start = self.i
            if self.eat('if'):
                g = 'guard'
                gstart = self.i
                # guard text must see this arm's bindings
                c0, b0 = self.pat_cond(p, 'm')
                saved = dict(self.ctx.alias)
                g = (self.expr(True), saved)
            self.need('=>')
            arms.append((p, g, self.i, comments))
            # Skip the arm body for now to find the next: parse below on a second pass.
            self.skip_arm()
        end = self.i
        simple = all(a[1] is None and self.simple_pat(a[0]) for a in arms)
        out = list(pre)
        if simple:
            out.append(pad(ind) + 'case %s' % subj)
            for p, g, pos, com in arms:
                head = 'else:' if p[0] == 'wild' else 'of %s:' % ', '.join(self.case_vals(p))
                out.append(pad(ind) + head)
                out += self.arm_body(pos, ind + 1, value)
        else:
            # A place is matched in place: an arm may write through its binding.
            if re.fullmatch(r'[\w.]+', subj):
                tmp = subj
            else:
                tmp = self.tmpn()
                out.append(pad(ind) + 'let %s = %s' % (tmp, subj))
            first = True
            self.ctx.tmp += 0
            for p, g, pos, com in arms:
                c, b = self.pat_cond(p, tmp)
                savedal = dict(self.ctx.alias)
                for nm, val in b:
                    self.ctx.alias[nm] = val
                    self.decl.add(nm)
                if g is not None:
                    # Reparse the guard now the bindings are known.
                    c = (c + ' and ' if c else '') + self.reparse_guard(pos)
                if c is None:
                    out.append(pad(ind) + ('else:' if not first else 'if true:'))
                else:
                    out.append(pad(ind) + ('if %s:' if first else 'elif %s:') % c)
                out += [pad(ind + 1) + 'let %s = %s' % x for x in b]
                out += self.arm_body(pos, ind + 1, value)
                self.ctx.alias = savedal
                first = False
            if arms and self.pat_cond(arms[-1][0], tmp)[0] is not None:
                out.append(pad(ind) + 'else:'); out.append(pad(ind + 1) + 'rustPanic("non-exhaustive")')
        self.i = end
        return out
    def reparse_guard(self, pos):
        i = pos - 1  # at =>; walk back to the `if`
        d = 0
        while True:
            i -= 1
            t = self.t[i]
            if t[0] == 'p' and t[1] in ')]}': d += 1
            elif t[0] == 'p' and t[1] in '([{': d -= 1
            elif t[0] == 'id' and t[1] == 'if' and d == 0: break
        save = self.i; self.i = i + 1
        g = self.expr(True); self.i = save
        return g
    def simple_pat(self, p):
        if p[0] in ('lit', 'wild', 'range'): return p[0] != 'range' or p[3] == '..='
        if p[0] == 'path': return p[1][-1] != 'None'
        if p[0] == 'or': return all(self.simple_pat(x) and x[0] != 'wild' for x in p[1])
        return False
    def case_vals(self, p):
        if p[0] == 'or':
            return sum((self.case_vals(x) for x in p[1]), [])
        if p[0] == 'lit': return [p[1]]
        if p[0] == 'range': return ['%s .. %s' % (p[1], p[2])]
        return [self.path_value(p[1])]
    def skip_arm(self):
        d = 0
        first = True
        if self.at('{'):
            self.skip_balanced()
            self.eat(',')
            return
        while True:
            t = self.pk()
            if t[0] == 'p' and t[1] in '([{': d += 1
            elif t[0] == 'p' and t[1] in ')]}':
                if d == 0: return
                d -= 1
            elif t[0] == 'p' and t[1] == ',' and d == 0:
                self.nx(); return
            self.nx()
    def skip_balanced(self):
        d = 0
        while True:
            t = self.nx()
            if t[0] == 'p' and t[1] in '([{': d += 1
            elif t[0] == 'p' and t[1] in ')]}':
                d -= 1
                if d == 0: return
    def arm_body(self, pos, ind, value):
        save = self.i; self.i = pos
        if self.at('{'):
            lines = self.braced(ind, value)
        else:
            lines = self.stmt_expr(ind, value, True)
        self.i = save
        return lines
    def stmt_expr(self, ind, value, is_tail):
        v = self.v()
        if v in ('if', 'match', 'loop', 'while', 'for', 'unsafe') or v == '{':
            return self.control(ind, value)
        pre, e = self.with_hoist(ind, self.expr)
        if e == 'void0': return pre + [pad(ind) + 'discard']
        return pre + [pad(ind) + e]
    def stmts(self, ind, value):
        out = []
        while not self.at('}') and self.pk()[0] != 'eof':
            com = self.pk()[2]
            for c in com:
                if c: out.append(pad(ind) + '# ' + c)
            self.skip_attrs()
            if self.eat('let'):
                out += self.let(ind)
                continue
            if self.at('fn', 'const', 'use', 'static', 'struct', 'impl', 'enum', 'type'):
                if self.at('use'):
                    while not self.eat(';'): self.nx()
                    continue
                if self.at('const'):
                    self.nx(); nm = self.nx()[1]; self.need(':'); t = self.ty(); self.need('=')
                    pre, e = self.with_hoist(ind, self.expr); self.need(';')
                    out += pre + [pad(ind) + 'const %s: %s = %s' % (nm, t, e)]
                    continue
                if self.at('fn'):
                    out += ['\x00'] if False else []
                    out += rebase(self.fn(None, False), ind)
                    continue
                out.append(pad(ind) + 'R2A_MANUAL_inner_item')
                self.skip_item(); continue
            # server.plugin_manager.fire: no plugin can change the outcome here.
            if self.at('if') and self.v(1) == 'let' and self.is_plugin_if():
                self.partial.append('plugin events are not fired: nothing listens to them from here yet')
                continue
            v = self.v()
            lines = None
            if v in ('if', 'match', 'loop', 'while', 'for', 'unsafe', '{'):
                lines = self.control(ind, False)
                if self.at('.') and self.v(1) == 'into':
                    self.i += 4
                # `if` used as the tail value: re-emit in value mode.
                if self.at('}') and value:
                    pass
                out_tail = self.at('}')
                self.eat(';')
                out += lines
                continue
            pre, e = self.with_hoist(ind, self.expr)
            had_semi = self.eat(';')
            out += pre
            if e == 'void0': continue
            if e.startswith('R2A_NONE'): pass
            if had_semi and re.search(r'\.(setBlockState|breakBlock)\([^=]*\)$', e) and not e.startswith('return'): e = 'discard ' + e
            out.append(pad(ind) + e)
        return out
    def is_plugin_if(self):
        j = self.i; d = 0; seen = False
        # Look at the condition and the block for plugin_manager/fire.
        k = j
        while not (self.t[k][0] == 'p' and self.t[k][1] == '{'): k += 1
        cond = ' '.join(str(self.t[x][1]) for x in range(j, k))
        if 'server' not in cond or 'upgrade' not in cond: return False
        save = self.i; self.i = k; self.skip_balanced(); e = self.i
        body = ' '.join(str(self.t[x][1]) for x in range(k, e))
        self.i = save
        if 'plugin_manager' in body:
            self.i = e
            return True
        return False
    def skip_item(self):
        while not self.at('{', ';'): self.nx()
        if self.at('{'): self.skip_balanced()
        else: self.nx()
    def let(self, ind):
        p = self.pat()
        t = None
        if self.eat(':'): t = self.ty()
        kw = 'var' if self.let_mut(p) else 'let'
        if self.eat(';'):
            return [pad(ind) + 'var %s: %s' % (self.pat_lets(p), t or 'R2A_MANUAL_type')]
        self.need('=')
        # `let g = x.lock().await`: a guard is the place itself, not a copy of it.
        start = self.i
        pre, e = self.with_hoist(ind, self.expr)
        guard = False
        for k in range(start, self.i - 1):
            pass
        src = [str(x[1]) for x in self.t[start:self.i]]
        if p[0] == 'bind' and len(src) >= 2 and src[-2:] == ['.', 'await'] and 'lock' in src[-5:]:
            self.ctx.alias[p[1]] = e
            self.eat(';')
            return pre
        if self.at('else'):
            self.nx()
            tmp = self.tmpn()
            c, bs = self.pat_cond(p, tmp)
            b = self.braced(ind + 1, False)
            self.eat(';')
            return pre + [pad(ind) + 'let %s = %s' % (tmp, e), pad(ind) + 'if not (%s):' % (c or 'true')] + b + [pad(ind) + 'let %s = %s' % x for x in bs]
        self.eat(';')
        p = self.unshadow(p)
        if p[0] == 'slice':
            tmp = self.tmpn()
            return pre + [pad(ind) + 'let %s = %s' % (tmp, e)] + [pad(ind) + 'let %s = %s[%d]' % (self.pat_lets(x), tmp, i) for i, x in enumerate(p[1])]
        left = self.pat_lets(p)
        if p[0] == 'call' and p[1][-1] == 'BlockPos':
            p = p[2][0]; e = e + '.vec'
        if p[0] in ('struct', 'call'):
            tmp = self.tmpn()
            c, bs = self.pat_cond(p, tmp)
            for nm, val in bs: self.decl.add(nm)
            return pre + [pad(ind) + 'let %s = %s' % (tmp, e)] + [pad(ind) + 'let %s = %s' % x for x in bs]
        if p[0] not in ('bind', 'tuple', 'wild'):
            return pre + [pad(ind) + 'R2A_MANUAL_letpat = %s' % e]
        return pre + [pad(ind) + '%s %s%s = %s' % (kw, left, ': ' + t if t else '', e)]
    def unshadow(self, p):
        """Rust may `let` a name twice in one scope and aowlmony may not: the later one gets a new name."""
        if p[0] == 'bind':
            n = name(p[1])
            if n in self.decl:
                self.declN += 1
                new = '%s%d' % (n, self.declN)
                self.ctx.alias[p[1]] = new
                return ('bind', new, p[2])
            self.decl.add(n)
            self.ctx.alias.pop(p[1], None)
            return p
        if p[0] == 'tuple' or p[0] == 'slice':
            return (p[0], [self.unshadow(x) for x in p[1]])
        return p
    def let_mut(self, p):
        if p[0] == 'bind': return p[2]
        return False
    # --- items
    def fn(self, selftype, is_pub, prefix='', export=None):
        """at `fn`; returns lines"""
        self.need('fn')
        fname = self.nx()[1]
        self.skip_generics()
        self.need('(')
        params = []; muts = []; hasself = False
        while not self.eat(')'):
            self.skip_attrs()
            while self.at('&'):
                self.nx()
                if self.pk()[0] == 'life': self.nx()
            m = self.eat('mut')
            if self.at('self'):
                self.nx(); hasself = 'mut' if m else True
                if self.eat(':'): self.ty()
                self.eat(','); continue
            p = self.pat()
            self.need(':')
            t = self.ty()
            params.append((self.pat_lets(p) if p[0] != 'wild' else 'unused%d' % len(params), t, p))
            if m or (p[0] == 'bind' and p[2]): muts.append(self.pat_lets(p))
            self.eat(',')
        ret = None
        if self.eat('->'): ret = self.ty()
        if self.at('where'):
            while not self.at('{', ';'): self.nx()
        if ret == 'void': ret = None
        return (fname, hasself, params, muts, ret)
    def fn_body(self, ret, muts, ind=1):
        savedret = self.ret; self.ret = ret
        saved_ctx_alias = self.ctx.alias; self.ctx.alias = {}
        self.decl = set(getattr(self, 'next_decl', [])); self.declN = 0
        self.need('{')
        # Box::pin(async move { ... }) is the body itself.
        if self.v() == 'Box' and self.v(2) == 'pin':
            self.i += 4
            if self.at('async'):
                self.eat('async'); self.eat('move')
                self.need('{')
                lines = self.stmts(ind, ret is not None)
                self.need('}'); self.eat(','); self.need(')')
            else:
                pre, e = self.with_hoist(ind, self.expr)
                self.eat(','); self.need(')')
                lines = pre + [pad(ind) + e]
        else:
            lines = self.stmts(ind, ret is not None)
        self.need('}')
        self.ret = savedret; self.ctx.alias = saved_ctx_alias
        if not [l for l in lines if not l.strip().startswith('#')]: lines.append(pad(ind) + 'discard')
        suf = {'uint8': "'u8", 'uint16': "'u16", 'uint32': "'u32", 'int8': "'i8", 'int16': "'i16", 'int64': "'i64", 'uint64': "'u64", 'float32': "'f32"}.get(ret)
        if suf:
            lines = [re.sub(r'^(\s*)(\d+(?:\.\d+)?)$', lambda m: m[1] + m[2] + suf, l) for l in lines]
        return [pad(ind) + 'var %s = %s' % (m, m) for m in muts] + lines

def pad(n): return '  ' * n
def rebase(lines, ind):
    return [l for l in lines]

def uses(s, here):
    """module paths this file imports, from its use items."""
    out = set()
    for m in re.finditer(r'^\s*(?:pub\s+)?use\s+([^;]+);', s, re.M):
        flat = []
        def walk(pre, t):
            t = t.strip()
            d = 0; cur = ''; parts = []
            i = t.find('{')
            if i < 0:
                flat.append(pre + t); return
            head = t[:i]; body = t[i + 1:t.rfind('}')]
            for ch in body:
                if ch == '{': d += 1
                if ch == '}': d -= 1
                if ch == ',' and d == 0: parts.append(cur); cur = ''
                else: cur += ch
            if cur.strip(): parts.append(cur)
            for x in parts: walk(pre + head, x)
        walk('', re.sub(r'\s+', '', m[1]))
        out.update(flat)
    return out
