#!/usr/bin/env python3
"""How much of the upstream Rust tree this port has, file by file.

    python tools/port_status.py [upstream-checkout] [--missing crate]

A port names what it translates in its header comment, so an upstream file counts as
touched when a source here names its path or its crate-relative tail. Touched is not
finished: a header can say "core only". Lines marked `## PARTIAL: <path>` count as
touched-partial, and the table keeps them apart. Generated code under pumpkin-data is
left out: that is regenerated from assets/, not hand-ported.
"""
import os
import re
import subprocess
import sys

here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
argv = sys.argv[1:]
only = ''
if '--missing' in argv:
    i = argv.index('--missing')
    only = argv[i + 1]
    del argv[i:i + 2]
upstream = argv[0] if argv else os.path.join(os.path.dirname(here), 'ref', 'pumpkin-1.21.11')

rs = subprocess.run(['git', '-C', upstream, 'ls-files', '*.rs'], capture_output=True, text=True).stdout.splitlines()
rs = [p for p in rs if '/generated/' not in p and '/src/' in p]

# Only comments name upstream files. Generated tables hold huge single tokens, and a regex over
# those takes minutes, so generated output is skipped and only lines mentioning `.rs` are read.
named = set()
ref = re.compile(r'[\w\-./]+\.rs\b')
for root, dirs, names in os.walk(os.path.join(here, 'src')):
    dirs[:] = [d for d in dirs if d != 'generated']
    for n in names:
        if n.endswith('.aowl'):
            for line in open(os.path.join(root, n), encoding='utf-8', errors='replace'):
                if '.rs' in line and len(line) < 2000:
                    named.update(m.replace(chr(92), '/') for m in ref.findall(line))
tails = set()
for n in named:
    parts = n.split('/')
    for i in range(len(parts)):
        tails.add('/'.join(parts[i:]))

rows = {}
missing = []
for p in rs:
    crate = p[len('crates/'):].split('/')[0] if p.startswith('crates/') else p.split('/')[0]
    tail = p.split('/src/', 1)[-1]
    lines = sum(1 for _ in open(os.path.join(upstream, p), 'rb'))
    r = rows.setdefault(crate, [0, 0, 0, 0])
    r[0] += 1
    r[1] += lines
    # The full path always counts. A shorter tail counts unless it could be any crate's file.
    hit = p in tails or (crate + '/src/' + tail) in tails or (
        tail in tails and tail.split('/')[-1] not in ('mod.rs', 'lib.rs', 'main.rs') if '/' in tail
        else tail in named and tail not in ('mod.rs', 'lib.rs', 'main.rs'))
    if hit:
        r[2] += 1
        r[3] += lines
    elif crate == only:
        missing.append((lines, tail))

if only:
    for lines, tail in sorted(missing, reverse=True):
        print('%7d %s' % (lines, tail))
    sys.exit(0)
print('%-28s %6s %8s %6s %8s %5s' % ('crate', 'files', 'lines', 'named', 'lines', '%'))
tot = [0, 0, 0, 0]
for c, r in sorted(rows.items(), key=lambda kv: -kv[1][1]):
    print('%-28s %6d %8d %6d %8d %4d%%' % (c, r[0], r[1], r[2], r[3], 100 * r[3] / max(1, r[1])))
    tot = [a + b for a, b in zip(tot, r)]
print('%-28s %6d %8d %6d %8d %4d%%' % ('TOTAL', tot[0], tot[1], tot[2], tot[3], 100 * tot[3] / max(1, tot[1])))
