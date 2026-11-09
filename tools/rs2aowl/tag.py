#!/usr/bin/env python3
"""Marks every translated file outside what registry.aowl and the tests pull in as PARTIAL, and counts both."""
import os, re, subprocess
repo = r'C:\Users\timbuktu\dev\minecraft-server\src\server\block'
up = r'C:\Users\timbuktu\dev\ref\pumpkin-1.21.11\pumpkin\src\block'
def imports(path):
    out = []
    d = os.path.dirname(path)
    for line in open(path, encoding='utf8'):
        m = re.match(r'^import\s+(.*)$', line)
        if not m: continue
        spec = m[1].strip()
        m2 = re.match(r'^([\w./-]*?/?)\[(.*)\]$', spec)
        names = [m2[1] + x.strip() for x in m2[2].split(',')] if m2 else [x.strip() for x in spec.split(',')]
        for n in names:
            n = n.split(' as ')[0].strip().strip('"')
            f = os.path.normpath(os.path.join(d, n + '.aowl'))
            if os.path.exists(f) and os.path.normpath(f).replace(chr(92), '/').startswith(os.path.normpath(repo).replace(chr(92), '/')): out.append(os.path.normpath(f))
    return out
# Continuation lines of the bracketed imports in registry.aowl: read it whole.
seen = set()
roots = [os.path.join(repo, 'registry.aowl'), os.path.join(repo, 'testworld.aowl'), os.path.join(repo, 'spreadingsnowy.aowl')]
txt = open(roots[0], encoding='utf8').read()
for m in re.finditer(r'^import (blocks[\w/]*)/\[([^\]]*)\]', txt, re.M):
    for n in m[2].split(','):
        roots.append(os.path.join(repo, m[1].replace('/', os.sep), n.strip() + '.aowl'))
roots = [os.path.normpath(x) for x in roots]
st = list(roots)
while st:
    f = st.pop()
    if f in seen: continue
    seen.add(f)
    st += imports(f)
tot = chk = 0; tagged = 0; lines_ok = 0; lines_no = 0; markers = 0; mfiles = 0
names_no = []
for dp, _, ns in os.walk(repo):
    for n in ns:
        if not n.endswith('.aowl') or n.endswith('test.aowl'): continue
        f = os.path.normpath(os.path.join(dp, n))
        s = open(f, encoding='utf8').read()
        m = re.match(r'## Port of pumpkin/src/block/(\S+\.rs)\n', s)
        if not m: continue
        tot += 1
        rs = os.path.join(up, m[1].replace('/', os.sep))
        L = sum(1 for _ in open(rs, 'rb')) if os.path.exists(rs) else 0
        if f in seen:
            cleaned = re.sub(r'## PARTIAL: [^\n]*not yet compiled[^\n]*\n', '', s)
            if cleaned != s:
                open(f, 'w', encoding='utf8', newline='\n').write(cleaned)
            chk += 1; lines_ok += L; continue
        lines_no += L
        names_no.append(m[1])
        k = len(re.findall(r'R2A_', s))
        markers += k; mfiles += 1 if k else 0
        tagline = '## PARTIAL: pumpkin/src/block/%s - machine translation of the whole file, not yet compiled%s; expect errors, and read it against upstream before trusting it.\n' % (m[1], ' (%d R2A_ markers show what the translator could not do)' % k if k else '')
        if 'not yet compiled' not in s:
            s = s[:m.end()] + tagline + s[m.end():]
            open(f, 'w', encoding='utf8', newline='\n').write(s); tagged += 1
print('translated files', tot, 'compiled', chk, 'lines', lines_ok, '| not compiled', tot - chk, 'lines', lines_no, '| tagged now', tagged, '| R2A markers', markers, 'in', mfiles)
print('compiled:', sorted(os.path.relpath(x, repo).replace(os.sep, '/') for x in seen if x.endswith('.aowl')))
