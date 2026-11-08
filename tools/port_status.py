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
args = [a for a in sys.argv[1:] if not a.startswith('--')]
upstream = args[0] if args else os.path.join(os.path.dirname(here), 'ref', 'pumpkin')
only = sys.argv[sys.argv.index('--missing') + 1] if '--missing' in sys.argv else ''
if only in args: args.remove(only)

rs = subprocess.run(['git', '-C', upstream, 'ls-files', 'crates/*.rs'], capture_output=True, text=True).stdout.splitlines()
rs = [p for p in rs if '/generated/' not in p]

text = []
for root, _, names in os.walk(os.path.join(here, 'src')):
    for n in names:
        if n.endswith('.aowl'):
            text.append(open(os.path.join(root, n), encoding='utf-8', errors='replace').read())
blob = '\n'.join(text)
named = set(m.replace(chr(92), '/') for m in re.findall(r'[\w\-./]+\.rs\b', blob))
tails = set()
for n in named:
    parts = n.split('/')
    for i in range(len(parts)):
        tails.add('/'.join(parts[i:]))
partial = set(re.findall(r'## PARTIAL: ([\w\-./]+\.rs)', blob))

rows = {}
missing = []
for p in rs:
    crate = p.split('/')[1]
    tail = p.split('/src/', 1)[-1]
    lines = sum(1 for _ in open(os.path.join(upstream, p), 'rb'))
    r = rows.setdefault(crate, [0, 0, 0, 0])
    r[0] += 1
    r[1] += lines
    hit = tail in tails if '/' in tail else (tail in named and tail not in ('mod.rs', 'lib.rs', 'main.rs'))
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
