#!/usr/bin/env python3
"""How much of the upstream Rust tree this port has, file by file.

    python tools/port_status.py [upstream-checkout] [--missing crate]

Each upstream file is in one of four states:

  whole    a source here names it, and no PARTIAL line does. Not proof it is right: that takes
           its tests, and for the server tools/mcbot.py.
  partial  a `## PARTIAL: <path>` line names it, saying what is missing.
  draft    machine-translated and never compiled, so it is not counted as ported at all.
  missing  no source names it.

Generated code under pumpkin-data is left out: that is regenerated from assets/, not hand-ported.
`--missing crate` lists what is not whole for that crate, largest first, with its state.
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
ref = re.compile(r'[\w\-./]+\.rs\b')
draftWords = ('machine translation', 'not yet compiled')
named = set()
partial = set()
drafts = set()
for root, dirs, names in os.walk(os.path.join(here, 'src')):
    dirs[:] = [d for d in dirs if d != 'generated']
    for n in names:
        if not n.endswith('.aowl'):
            continue
        for line in open(os.path.join(root, n), encoding='utf-8', errors='replace'):
            if '.rs' not in line or len(line) >= 2000:
                continue
            found = [m.replace(chr(92), '/') for m in ref.findall(line)]
            named.update(found)
            if 'PARTIAL' in line:
                # The upstream file is the first path; later ones are only mentioned.
                head = found[:1]
                partial.update(head)
                if any(w in line for w in draftWords):
                    drafts.update(head)


def names(group, path, crate, tail):
    """Whether a group of named paths names this upstream file."""
    if path in group or (crate + '/src/' + tail) in group:
        return True
    if tail.split('/')[-1] in ('mod.rs', 'lib.rs', 'main.rs'):
        return False
    # A bare file name ("biome.rs", "loot.rs") exists in several crates, and a comment about
    # one must not mark the others: it counts only with the crate's own directory in front
    # of it, or from the crate root. Longer tails ("world/mod.rs") are specific enough.
    if '/' not in tail:
        return any(n == tail or n.endswith('/' + crate + '/src/' + tail) or n.endswith(crate + '/src/' + tail)
                   for n in group)
    return any(n == tail or n.endswith('/' + tail) for n in group)


rows = {}
listed = []
for p in rs:
    crate = p[len('crates/'):].split('/')[0] if p.startswith('crates/') else p.split('/')[0]
    tail = p.split('/src/', 1)[-1]
    lines = sum(1 for _ in open(os.path.join(upstream, p), 'rb'))
    row = rows.setdefault(crate, {'files': 0, 'lines': 0, 'whole': 0, 'partial': 0, 'draft': 0, 'missing': 0})
    row['files'] += 1
    row['lines'] += lines
    if not names(named, p, crate, tail):
        state = 'missing'
    elif names(drafts, p, crate, tail):
        state = 'draft'
    elif names(partial, p, crate, tail):
        state = 'partial'
    else:
        state = 'whole'
    row[state] += lines
    if crate == only and state != 'whole':
        listed.append((lines, state, tail))

if only:
    for lines, state, tail in sorted(listed, reverse=True):
        print('%7d %-8s %s' % (lines, state, tail))
    sys.exit(0)

print('Upstream lines by state. Whole means named with no PARTIAL line, not proven correct.')
print('%-26s %6s %8s %8s %8s %8s %8s %6s' % ('crate', 'files', 'lines', 'whole', 'partial', 'draft', 'missing', 'whole%'))
total = dict.fromkeys(('files', 'lines', 'whole', 'partial', 'draft', 'missing'), 0)
for crate, row in sorted(rows.items(), key=lambda kv: -kv[1]['lines']):
    print('%-26s %6d %8d %8d %8d %8d %8d %5d%%' % (crate, row['files'], row['lines'], row['whole'], row['partial'],
                                                 row['draft'], row['missing'], 100 * row['whole'] / max(1, row['lines'])))
    for k in total:
        total[k] += row[k]
print('%-26s %6d %8d %8d %8d %8d %8d %5d%%' % ('TOTAL', total['files'], total['lines'], total['whole'], total['partial'],
                                             total['draft'], total['missing'], 100 * total['whole'] / max(1, total['lines'])))
