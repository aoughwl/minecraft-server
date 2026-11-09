#!/usr/bin/env python3
"""Regenerate translated files into the repo, except those under hand care (HAND below, or listed in hand.txt).
Then write the umbrella checks in this directory."""
import os, re, shutil, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
up = r'C:\Users\timbuktu\dev\ref\pumpkin-1.21.11\pumpkin\src\block'
repo = r'C:\Users\timbuktu\dev\minecraft-server\src\server\block'
out = os.path.join(here, 'out')
shutil.rmtree(out, ignore_errors=True)
print(subprocess.run([sys.executable, os.path.join(here, 'r2ad.py'), up, out], capture_output=True, text=True).stdout[-900:])
hand = set(l.strip() for l in open(os.path.join(here, 'hand.txt'))) if os.path.exists(os.path.join(here, 'hand.txt')) else set()
hand |= {'blockmod.aowl', 'registry.aowl', 'fluid/fluidmod.aowl', 'entities/entitiesmod.aowl'}
sys.path.insert(0, here)
import importlib, patches as pm, patches2 as pm2
patches = pm.PATCHES
n = 0
for dp, _, ns in os.walk(out):
    for f in ns:
        rel = os.path.relpath(os.path.join(dp, f), out).replace(os.sep, '/')
        if rel in hand: continue
        s = open(os.path.join(dp, f), encoding='utf8').read()
        s = re.sub(r'(breakBlock\([^\n]*?)R2A_NONE', r'\1nil', s)
        s = re.sub(r'(updateNeighbors\([^\n]*?)R2A_NONE', r'\1none[BlockDirection]()', s)
        s = re.sub(r'\b\w+: R2A_NONE(, )?', '', s)
        for old, new in list(patches.get(rel, [])) + list(pm2.PATCHES2.get(rel, [])):
            if old.startswith('re:'):
                s, cnt = re.subn(old[3:], lambda m: new, s)
                if not cnt: print('PATCH MISS', rel, old[:60])
                continue
            if old not in s: print('PATCH MISS', rel, old[:60])
            s = s.replace(old, new)
        t = os.path.join(repo, rel)
        os.makedirs(os.path.dirname(t), exist_ok=True)
        open(t, 'w', encoding='utf8', newline='\n').write(s); n += 1
print('wrote', n)
for name, root in [('chk_redstone', 'blocks/redstone'), ('chk_blocks', 'blocks'), ('chk_fluid', 'fluid'), ('chk_entities', 'entities')]:
    mods = []
    for dp, _, ns in os.walk(os.path.join(repo, root)):
        for f in ns:
            if f.endswith('.aowl') and not f.endswith('test.aowl'):
                rel = os.path.relpath(os.path.join(dp, f), os.path.join(repo)).replace(os.sep, '/')[:-5]
                mods.append(rel)
                if name == 'chk_redstone' and any(x in rel for x in ('crafter', 'dispenser', 'dropper')): mods.pop()
    with open(os.path.join(here, name + '.aowl'), 'w', newline='\n') as o:
        for i, m in enumerate(sorted(mods)):
            o.write('import "server/block/%s" as m%d\n' % (m, i))
