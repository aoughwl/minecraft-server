#!/usr/bin/env python3
"""Driver of r2a.py: items and files.  r2ad.py <upstream block dir> <out dir> [path prefixes]"""
import os, re, sys, json
from r2a import P, tokenize, name, camel, FIELD_KW, uses

BEHAV = {'BlockBehaviour': 'newBlockBehaviour', 'FluidBehaviour': 'newFluidBehaviour'}
SKIP_TRAITS = {'BlockMetadata', 'FluidMetadata', 'BlockBehaviour', 'FluidBehaviour', 'BlockEntity', 'Default', 'Clone', 'From', 'Display', 'Debug', 'PartialEq', 'Eq', 'Send', 'Sync', 'Hash', 'Copy'}

class Items:
    def __init__(self, path, src, known):
        self.path = path; self.p = P(tokenize(src), known); self.p.hoist = []; self.known = known
        self.types = []; self.consts = []; self.forwards = []; self.bodies = []; self.register = []; self.tests = False
    def sig(self, nm, params, ret, pub):
        ps = ', '.join('%s: %s' % (a, ('var ' + t) if (t.startswith('NbtCompound') and a == 'nbt') else t) for a, t, _ in params)
        return 'proc %s%s(%s)%s' % (nm, '*' if pub else '', ps, ': ' + ret if ret else '')
    def run(self):
        while self.p.pk()[0] != 'eof':
            self.item()
    def item(self):
        p = self.p
        attrs = p.skip_attrs()
        flat = [' '.join(a) for a in attrs]
        pub = False
        if p.at('pub'):
            p.nx(); pub = True
            if p.at('('): p.skip_balanced()
        p.eat('async'); p.eat('unsafe')
        v = p.v()
        if any(a.startswith('cfg') and 'test' in a for a in flat):
            self.tests = True
            p.skip_item(); return
        if v == 'use':
            while not p.eat(';'): p.nx()
            return
        if v == 'mod':
            p.skip_item(); return
        if v == 'struct': return self.struct(attrs, pub)
        if v == 'enum': return self.enum(pub)
        if v == 'type':
            p.nx(); nm = p.nx()[1]; p.skip_generics(); p.need('='); t = p.ty(); p.need(';')
            if t != nm:
                self.types.append('type %s%s = %s' % (nm, '*' if pub else '', t))
            return
        if v == 'const' or v == 'static':
            p.nx(); p.eat('mut')
            if p.at('fn'):
                return self.freefn(pub)
            nm = p.nx()[1]; p.need(':'); t = p.ty(); p.need('=')
            pre, e = p.with_hoist(0, p.expr); p.need(';')
            kw = 'const' if not re.search(r'block[A-Z]|\(\)|[A-Z]\w*\.\w+\(', e) else 'let'
            self.consts.append('%s %s%s: %s = %s' % (kw, nm, '*' if pub else '', t, e)); return
        if v == 'fn': return self.freefn(pub)
        if v == 'impl': return self.impl()
        if v == 'macro_rules':
            p.nx(); p.nx(); p.nx(); p.skip_balanced(); p.eat(';'); self.partial_macro = True; return
        if p.v(1) == '!':
            nm = p.nx()[1]; p.nx(); st = p.i; p.skip_balanced(); p.eat(';')
            self.bodies.append('%s(%s)' % (camel(nm), ' '.join(str(x[1]) for x in p.t[st + 1:p.i - 2]))); return
        if v == 'trait': return self.trait()
        raise SyntaxError('item %r near %s' % (v, p.near()))
    def freefn(self, pub):
        p = self.p
        fname, hs, params, muts, ret = p.fn(None, pub)
        if p.at(';'):
            p.nx(); return
        s = self.sig(name(fname), params, ret, True)
        self.forwards.append(s)
        self.bodies.append(s + ' =')
        p.next_decl = [x[0] for x in params]; self.bodies += p.fn_body(ret, muts); self.bodies.append('')
    def struct(self, attrs, pub):
        p = self.p
        p.nx(); nm = p.nx()[1]; p.skip_generics()
        for a in attrs:
            if a and a[0] in ('pumpkin_block', 'pumpkin_block_from_tag', 'pumpkin_fluid'):
                self.register.append((nm, a[0], a[2:-1] if a[1] == '(' else a[1:]))
        if p.eat(';'):
            self.types.append('type %s* = object' % nm); return
        if p.at('('):
            p.skip_balanced(); p.eat(';')
            self.types.append('type %s* = R2A_MANUAL_tuple_struct' % nm); return
        p.need('{')
        fs = []
        while not p.eat('}'):
            p.skip_attrs()
            if p.at('pub'):
                p.nx()
                if p.at('('): p.skip_balanced()
            f = p.nx()[1]; p.need(':'); p.ctx.selfname = nm; t = p.ty(); p.eat(',')
            fs.append('  %s*: %s' % (FIELD_KW.get(f, camel(f)), t))
        base = ' of BlockEntity' if nm in self.known['be'] else ''
        # A Copy struct has value semantics: a ref would alias what Rust copies.
        isCopy = any(x and x[0] == 'derive' and 'Copy' in x for x in attrs)
        self.types.append('type %s* = %sobject%s\n%s' % (nm, '' if isCopy and not base else 'ref ', base, '\n'.join(fs) or '  discard'))
    def enum(self, pub):
        p = self.p
        p.nx(); nm = p.nx()[1]; p.skip_generics(); p.need('{')
        vs = []; payload = False
        while not p.eat('}'):
            p.skip_attrs(); v = p.nx()[1]
            if p.at('(') or p.at('{'):
                payload = True; p.skip_balanced()
            if p.eat('='):
                v += ' = ' + p.expr()
            vs.append(v); p.eat(',')
        t = 'type %s* {.pure.} = enum\n%s' % (nm + 'Kind' if payload else nm, '\n'.join('  ' + ('k' + x if payload else x) for x in vs))
        if payload:
            fs = self.known['payload'][nm]
            t += '\ntype %s* = object\n  kind*: %sKind' % (nm, nm)
            for v, types in fs.items():
                for i, ty in enumerate(types):
                    t += '\n  f%d%s*: %s' % (i, v, ty)
        self.types.append(t)
    def impl(self):
        p = self.p
        p.nx(); p.skip_generics()
        p.eat('!')
        first = p.ty(); target = first; tr = None
        if p.eat('for'):
            tr = first; target = p.ty()
        if p.at('where'):
            while not p.at('{'): p.nx()
        tr0 = tr.split('[')[0] if tr else None
        p.ctx.selfname = target
        p.need('{')
        fields = []
        while not p.eat('}'):
            p.skip_attrs()
            pub = False
            if p.at('pub'):
                p.nx(); pub = True
                if p.at('('): p.skip_balanced()
            if p.v() == 'const' and p.v(1) == 'fn': p.nx()
            p.eat('async')
            if p.at('const'):
                p.nx(); nm = p.nx()[1]; p.need(':'); t = p.ty(); p.need('=')
                pre, e = p.with_hoist(0, p.expr); p.need(';')
                self.consts.append('const %s*: %s = %s' % (nm, t, e)); continue
            if p.at('type'):
                p.skip_item(); continue
            fname, hs, params, muts, ret = p.fn(target, pub)
            if fname == 'as_any':
                p.skip_balanced(); continue
            self.one_impl_fn(tr0, target, fname, hs, params, muts, ret, pub, fields)
        if tr0 in BEHAV:
            sig = 'proc new%s*(): %s' % (target, tr0)
            self.forwards.append(sig)
            self.bodies.append(sig + ' =')
            self.bodies.append('  result = %s()' % BEHAV[tr0])
            for f, proc0 in fields:
                self.bodies.append('  result.%sImpl = %s' % (f, proc0))
            self.bodies.append('')
        elif tr0 == 'BlockEntity':
            self.be_vt(target, fields)
        elif tr0 in self.known['traits']:
            self.trait_impl(tr0, target, fields)
        p.ctx.selfname = None
    def one_impl_fn(self, tr0, target, fname, hs, params, muts, ret, pub, fields):
        p = self.p; prefix = target[0].lower() + target[1:]; nm = name(fname)
        p.in_trait_impl = tr0 in self.known['traits']
        if tr0 in BEHAV or tr0 == 'BlockEntity' or tr0 in self.known['traits']:
            pname = prefix + nm[0].upper() + nm[1:] + '_' + tr0
            if tr0 == 'BlockEntity':
                ps = [('self0', 'BlockEntity', None)] + params if hs else params
            elif tr0 in BEHAV:
                ps = params
            else:
                ps = [('self', tr0, None)] + params
            s = self.sig(pname, ps, ret, False)
            self.forwards.append(s)
            self.bodies.append(s + ' =')
            if tr0 == 'BlockEntity' and hs: self.bodies.append('  let self = %s(self0)' % target)
            p.next_decl = [x[0] for x in params]
            body0 = p.fn_body(ret, muts)
            if tr0 in BEHAV and any(re.search(r'\bself\b', x) and not x.strip().startswith('#') for x in body0):
                # A unit struct's own methods take it as a value.
                self.bodies.append('  let self = %s()' % target)
            self.bodies += body0; self.bodies.append('')
            fields.append((nm, pname))
            return
        if tr0 in ('BlockMetadata', 'FluidMetadata'):
            s = 'proc %sIds*(): seq[%s]' % (prefix, 'BlockId' if tr0 == 'BlockMetadata' else 'uint16')
            self.forwards.append(s); self.bodies.append(s + ' =')
            p.next_decl = []; body = p.fn_body('seq[BlockId]', muts)
            body = [('  @' + x.strip()) if x.strip().startswith('[') else x for x in body]
            self.bodies += body; self.bodies.append('')
            self.register.append((target, 'ids', [prefix + 'Ids']))
            return
        # A plain impl or an extension trait: procs with `self` first.
        selfT = target
        if hs == 'mut' and (target.endswith('Properties') or target in self.known['payload'] or target.endswith('Shape') or target.endswith('Connection')):
            selfT = 'var ' + target
        ps = ([('self', selfT, None)] if hs else []) + params
        if fname == 'new' and not hs: nm = 'new' + target
        if fname == 'default' and not hs: nm = 'default' + target
        s = self.sig(nm, ps, ret, True)
        self.forwards.append(s); self.bodies.append(s + ' =')
        p.next_decl = [x[0] for x in params]; self.bodies += p.fn_body(ret, muts); self.bodies.append('')
    def be_vt(self, target, fields):
        prefix = target[0].lower() + target[1:]
        self.types.append('var g%sVt: nil BlockEntityVt' % target)
        s = 'proc %sVt*(): BlockEntityVt' % prefix
        self.forwards.append(s)
        self.bodies.append(s + ' =')
        self.bodies.append('  if g%sVt == nil:' % target)
        self.bodies.append('    let v = newBlockEntityVt()')
        for f, proc0 in fields:
            if f != 'fromNbt':
                self.bodies.append('    v.%sImpl = %s' % (f, proc0))
        self.bodies.append('    g%sVt = v' % target)
        self.bodies.append('  g%sVt' % target)
        self.bodies.append('')
    def trait_impl(self, tr, target, fields):
        prefix = target[0].lower() + target[1:]
        s = 'proc %sAs%s*(): %s' % (prefix, tr, tr)
        self.types.append('var g%sAs%s: nil %s' % (target, tr, tr))
        self.forwards.append(s)
        self.bodies.append(s + ' =')
        self.bodies.append('  if g%sAs%s == nil:' % (target, tr))
        self.bodies.append('    let v = new%s()' % tr)
        for f, proc0 in fields:
            self.bodies.append('    v.%sImpl = %s' % (f, proc0))
        for sup in self.known['supers'].get(tr, []):
            self.bodies.append('    v.%s = %sAs%s()' % (sup[0].lower() + sup[1:], prefix, sup))
        self.bodies.append('    g%sAs%s = v' % (target, tr))
        self.bodies.append('  g%sAs%s' % (target, tr))
        self.bodies.append('')
    def trait(self):
        p = self.p
        p.nx(); tr = p.nx()[1]; p.skip_generics()
        sup = []
        if p.eat(':'):
            while not p.at('{', 'where'):
                t = p.nx()
                if t[0] == 'id' and t[1] not in ('Send', 'Sync', 'Sized', 'Any'): sup.append(t[1])
        if p.at('where'):
            while not p.at('{'): p.nx()
        if tr not in self.known['traits']:
            p.skip_balanced(); return
        p.ctx.selfname = None
        p.need('{')
        vt = []; wrappers = []; ctor = []
        while not p.eat('}'):
            p.skip_attrs()
            p.eat('async')
            if p.at('const') or p.at('type'):
                p.skip_item(); continue
            fname, hs, params, muts, ret = p.fn(tr, True)
            nm = name(fname)
            if not hs:
                # An associated function has no self: a plain proc.
                if p.at(';'):
                    p.nx(); continue
                sg = self.sig(nm, params, ret, True)
                self.forwards.append(sg); self.bodies.append(sg + ' =')
                p.next_decl = [x[0] for x in params]; self.bodies += p.fn_body(ret, muts); self.bodies.append('')
                continue
            ps = [('self', tr, None)] + params
            ty = ', '.join('%s: %s' % (a, t) for a, t, _ in ps)
            vt.append('  %sImpl*: proc(%s)%s {.closure.}' % (nm, ty, ': ' + ret if ret else ''))
            ws = self.sig(nm, ps, ret, True)
            self.forwards.append(ws)
            args = ', '.join(a for a, _, _ in ps)
            wrappers.append(ws + ' =\n  let f = self.%sImpl\n  f(%s)\n' % (nm, args))
            if p.at(';'):
                p.nx(); continue
            cap = nm[0].upper() + nm[1:]
            d = self.sig('default%s_%s' % (cap, tr), ps, ret, False)
            self.forwards.append(d); self.bodies.append(d + ' =')
            p.next_decl = [x[0] for x in params]; self.bodies += p.fn_body(ret, muts); self.bodies.append('')
            ctor.append('  result.%sImpl = default%s_%s' % (nm, cap, tr))
        sups = ['  %s*: %s' % (s[0].lower() + s[1:], s) for s in sup]
        self.types.append('type %s* = ref object\n%s' % (tr, '\n'.join(vt + sups) or '  discard'))
        self.bodies += wrappers
        s = 'proc new%s*(): %s' % (tr, tr)
        self.forwards.append(s)
        self.bodies.append(s + ' =\n  result = %s()' % tr)
        self.bodies += ctor; self.bodies.append('')

def scan(root):
    known = {'traits': set(), 'supers': {}, 'structs': set(), 'be': set(), 'tm': {}, 'impls': set(), 'payload': {}}
    for dp, _, ns in os.walk(root):
        for n in ns:
            if not n.endswith('.rs'): continue
            s = open(os.path.join(dp, n), encoding='utf8').read()
            for m in re.finditer(r'^\s*(?:pub(?:\(crate\))? )?trait (\w+)[^{]*\{', s, re.M):
                tr = m[1]
                if tr in SKIP_TRAITS or tr.endswith('Ext') or tr in ('SegmentProperties', 'RedstoneGateBlockProperties', 'ViewerCountListener'): continue
                known['traits'].add(tr)
                sup = re.search(r':\s*([\w\s+]+)\{', m[0])
                if sup:
                    known['supers'][tr] = [x.strip() for x in sup[1].split('+') if x.strip() and x.strip() not in ('Send', 'Sync', 'Sized', 'Any')]
                body = s[m.end():]; d = 1; e = 0
                while d and e < len(body):
                    d += {'{': 1, '}': -1}.get(body[e], 0); e += 1
                for f in re.finditer(r'\bfn (\w+)', body[:e]): known['tm'][f[1]] = tr
            for m in re.finditer(r'impl\s+(\w+)(?:<[^>]*>)?\s+for\s+(\w+)', s): known['impls'].add((m[2], m[1]))
            for m in re.finditer(r'\benum (\w+)\s*\{([^}]*)\}', s):
                vs = re.findall(r'^\s*(\w+)(?:\(([^)]*)\))?,?\s*(?://.*)?$', m[2], re.M)
                if any(x[1] for x in vs):
                    PR = {'u8': 'uint8', 'BlockStateId': 'BlockStateId'}
                    known['payload'][m[1]] = {v: [PR.get(y.strip(), y.strip().replace('&', '').replace("'static ", '')) for y in t.split(',') if y.strip()] for v, t in vs}
            for m in re.finditer(r'\bstruct (\w+)', s): known['structs'].add(m[1])
            for m in re.finditer(r'impl BlockEntity for (\w+)', s): known['be'].add(m[1])
    return known

def modpath(rel):
    d, b = os.path.split(rel[:-3])
    if b == 'mod':
        leaf = os.path.basename(d) if d else 'block'
        return os.path.join(d, leaf + 'mod').replace(os.sep, '/')
    return os.path.join(d, b).replace(os.sep, '/')

def imports_for(src, rel, allrel):
    here = os.path.dirname(modpath(rel))
    out = []
    for u in uses(src, rel):
        seg = u.split('::')
        if seg[0] == 'crate' and seg[1:2] == ['block']:
            segs = seg[2:]
        elif seg[0] == 'super':
            cur = (os.path.dirname(rel).split('/') if os.path.dirname(rel) else [])
            if os.path.basename(rel) != 'mod.rs':
                pass
            elif cur:
                cur = cur[:-1]
            i = 0
            while i < len(seg) and seg[i] == 'super':
                if i > 0: cur = cur[:-1]
                i += 1
            segs = cur + seg[i:]
        else:
            continue
        for k in range(len(segs), 0, -1):
            cand = '/'.join(segs[:k])
            hit = cand + '.rs' if cand + '.rs' in allrel else (cand + '/mod.rs' if cand + '/mod.rs' in allrel else None)
            if hit:
                if hit != rel and hit not in ('mod.rs', 'registry.rs', 'entities/mod.rs', 'blocks/mod.rs', 'fluid/mod.rs'):
                    r = os.path.relpath(modpath(hit), here or '.').replace(os.sep, '/')
                    if r not in out: out.append(r)
                break
    return out

def translate(root, outroot, only=None):
    known = scan(root)
    allrel = set()
    for dp, _, ns in os.walk(root):
        for n in ns:
            if n.endswith('.rs'): allrel.add(os.path.relpath(os.path.join(dp, n), root).replace(os.sep, '/'))
    res = {}
    for rel in sorted(allrel):
        if only and not any(rel.startswith(o) for o in only): continue
        if rel.endswith('/tests.rs'): continue
        src = open(os.path.join(root, rel), encoding='utf8').read()
        it = Items(rel, src, known)
        try:
            it.run()
        except Exception as e:
            res[rel] = 'FAIL %s' % e
            print('FAIL', rel, str(e)[:200])
            continue
        target = modpath(rel)
        pre = '../' * target.count('/')
        lines = ['## Port of pumpkin/src/block/%s' % rel]
        for x in sorted(set(it.p.partial)):
            lines.append('## PARTIAL: pumpkin/src/block/%s - %s' % (rel, x))
        lines += ['', '{.feature: "untyped".}', '{.feature: "lenientnils".}', '', 'import %sblockprelude' % pre]
        for i in imports_for(src, rel, allrel):
            lines.append('import %s' % i)
        lines.append('')
        lines += [c for c in it.consts if c.startswith('const')]; lines.append('')
        # `use a::B as C`
        for m in re.finditer(r'\b([A-Z]\w+) as ([A-Z]\w+)\b', ' '.join(x for x in re.findall(r'(^\s*(?:pub\s+)?use\s+[^;]+;)', src, re.M))):
            it.types.insert(0, 'type %s = %s' % (m[2], m[1]))
        # One type section: Rust's types may refer to each other in any order.
        tys = [t for t in it.types if t.startswith('type ')]
        if tys:
            lines.append('type')
            for t in tys:
                for i, l in enumerate(t.split(chr(10))):
                    if l.startswith('type '):
                        lines.append('  ' + l[5:])
                    else:
                        lines.append('  ' + l)
            lines.append('')
        lines += [t for t in it.types if not t.startswith('type ')]; lines.append('')
        lines += [c for c in it.consts if not c.startswith('const')]; lines.append('')
        lines += it.forwards; lines.append('')
        lines += it.bodies
        reg = []
        for nm, how, a in it.register:
            if how == 'pumpkin_block': reg.append('  r.register(%s, new%s())' % (json.dumps(a[0]), nm))
            elif how == 'pumpkin_block_from_tag': reg.append('  r.registerTag(%s, new%s())' % (json.dumps(a[0]), nm))
            elif how == 'pumpkin_fluid': reg.append('  r.registerFluid(%s, new%s())' % (json.dumps(a[0]), nm))
            elif how == 'ids': reg.append('  r.registerIds(%s(), new%s())' % (a[0], nm))
        if reg:
            lines += ['proc register%s*(r: BlockRegistry) =' % ''.join(p.capitalize() for p in re.split('[/_]', target)), *reg, '']
        text = chr(10).join(lines)
        text = text.replace('let ' + chr(1), 'var ')
        def left(m):
            pn, body, pre = it.p.closures[int(m[1])]
            return 'R2A_MANUAL("closure |%s| %s")' % (pn, body.replace(chr(34), chr(39)).replace(chr(92), '')[:70])
        text = re.sub(r'__CL(\d+)__', left, text)
        lines = text.split(chr(10))
        os.makedirs(os.path.dirname(os.path.join(outroot, target)) or outroot, exist_ok=True)
        open(os.path.join(outroot, target + '.aowl'), 'w', encoding='utf8', newline='\n').write('\n'.join(lines) + '\n')
        res[rel] = 'ok'
    return res

if __name__ == '__main__':
    r = translate(sys.argv[1], sys.argv[2], sys.argv[3:] or None)
    print(sum(1 for v in r.values() if v == 'ok'), 'ok', sum(1 for v in r.values() if v != 'ok'), 'failed')
