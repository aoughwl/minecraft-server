"""Chunk / section border scenario against a private server (never the user's): rows and columns of planks that cross the chunk borders
x = 16k, z = 16k and the section borders y = 16k are placed (by the bot's use-item-on, or by /fill and /setblock) and read back through
RCON `execute if block` after a few seconds, and again after a save-all + restart (--phase check).

    python tests/border_scenario.py --port 25860 --rcon-port 25861 --name BorderBot --phase place --mode bot --y 100
    python tests/border_scenario.py --port 25860 --rcon-port 25861 --name BorderBot --phase check --y 100

Modes: `bot` (the bot's use-item-on), `cmd` (/fill and /setblock) over a settled area; `edge` (a /fill over x = 15 | 16 straight after the
login, before the neighbouring chunk is loaded; must refuse or store every block). Options: --away <s>, --pregen <blocks>, --y <floor y>.

The bot must be a level 4 operator of a scratch server with RCON enabled (tests/run_border_scenario.sh). Runs tools/mcbot.py UNEDITED
through its --c1 session slot (like tests/body_scenario.py). Exit status 0 only when no placed block is missing.
"""
import os
import socket
import struct
import sys
import time
import types

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import mcbot  # noqa: E402

OPT = {'rcon_port': 25861, 'password': 'borderpw', 'name': 'BorderBot', 'phase': 'place', 'mode': 'bot', 'y': 100, 'away': 0,
       'material': 'oak_planks', 'pregen': 0, 'wait': 5.0}


def cells(y0):
    """name -> list of (x, y, z). Row A along x at z = 100, row B along z at x = 20, three columns (interior x=3, border x=15 and x=16)."""
    out = {}
    out['rowx'] = [(x, y0, 100) for x in range(-20, 41)]
    out['rowz'] = [(20, y0, z) for z in range(84, 131)]
    for cx in (3, 15, 16):
        out['col%d' % cx] = [(cx, y, 104) for y in range(y0, y0 + 41)]
    out['deck'] = [(x, y0 + 4, 108) for x in range(-12, 29)]
    return out


def is_border(x, y, z):
    return (x & 15) in (0, 15) or (z & 15) in (0, 15) or (y & 15) in (0, 15)


def session(m, c, st, w, biomes, ctx, args):
    Y = OPT['y']
    MAT = 'minecraft:' + OPT['material']

    def wait(cond, what, seconds=15.0):
        m.pump(c, st, w, biomes, ctx, cond, what, seconds)

    def settle(seconds):
        end = time.time() + seconds
        try:
            m.pump(c, st, w, biomes, ctx, lambda: time.time() > end, 'time', seconds + 5.0)
        except Exception:
            pass

    def cmd(line):
        c.send(m.SB_CHAT_COMMAND, m.string(line))

    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    wait(lambda: w.health is not None, 'health')
    c.send(m.SB_CHANGE_GAME_MODE, m.varint(1))
    wait(lambda: w.mode == 1, 'creative')
    rc = socket.create_connection(('127.0.0.1', OPT['rcon_port']), timeout=10)
    rc.sendall(mcbot.rcon_packet(1, 3, OPT['password']))
    pid, _, _ = mcbot.rcon_read(rc)
    assert pid == 1, 'RCON login'
    ident = [10]

    def rcon(line):
        ident[0] += 1
        rc.sendall(mcbot.rcon_packet(ident[0], 2, line))
        rc.settimeout(8.0)
        while True:
            pid, ptype, text = mcbot.rcon_read(rc)
            if pid == ident[0]:
                break
        settle(0.02)
        return text

    def must(line):
        out = rcon(line)
        if 'filled' not in out and 'placed' not in out.lower():
            print('  COMMAND FAILED: %s -> %s' % (line, out), flush=True)
        return out

    def tp(x, y, z, secs=1.0):
        cmd('tp %s %f %f %f' % (OPT['name'], x + 0.5, y, z + 0.5))
        settle(secs)

    def to_area():
        tp(10, Y + 3, 100, 1.0)
        try:
            wait(lambda: w.block(10, Y - 1, 100) is not None, 'chunks of the area', 150.0)
        except Exception:
            print('  no chunk for the area: pos %s, %d chunks known: %s' % (w.pos, len(w.chunks), sorted(w.chunks)[:30]), flush=True)
            raise
        settle(2.0)

    C = cells(Y)

    def need_chunks():
        """Every chunk the lines touch must be on the client (so it is loaded on the server) before a block is set."""
        for name, lst in C.items():
            for (x, y, z) in (lst[0], lst[-1], lst[len(lst) // 2]):
                if w.block(x, Y - 1, z) is None:
                    wait(lambda: w.block(x, Y - 1, z) is not None, 'chunk of %d %d' % (x, z), 150.0)

    def lines():
        for name, lst in C.items():
            yield name, lst

    def probe(x, y, z):
        """True when the SERVER holds MAT at the cell: a same-block `fill ... replace` answers '1 blocks filled' only for a match (it changes
        nothing); `execute if block` has no result over RCON on this server."""
        ident[0] += 1
        rc.sendall(mcbot.rcon_packet(ident[0], 2, 'fill %d %d %d %d %d %d %s replace %s' % (x, y, z, x, y, z, MAT, MAT)))
        rc.settimeout(5.0)
        while True:
            pid, ptype, text = mcbot.rcon_read(rc)
            if pid == ident[0]:
                return text.startswith('1 blocks filled')

    def read_all():
        """RCON read-back of every cell (server side) -> missing set. The bot keeps answering keep-alives in between."""
        missing = set()
        n = 0
        for name, lst in lines():
            for (x, y, z) in lst:
                n += 1
                if n % 8 == 0:
                    settle(0.02)
                if not probe(x, y, z):
                    missing.add((x, y, z))
        return missing

    def client_missing():
        miss = set()
        for name, lst in lines():
            for (x, y, z) in lst:
                if w.block(x, y, z) in (None, 0):
                    miss.add((x, y, z))
        return miss

    def report(tag, missing, cl):
        tot_b = tot_i = mis_b = mis_i = 0
        for name, lst in lines():
            nb = ni = mb = mi = 0
            for (x, y, z) in lst:
                if is_border(x, y, z):
                    nb += 1
                    mb += (x, y, z) in missing
                else:
                    ni += 1
                    mi += (x, y, z) in missing
            tot_b += nb
            tot_i += ni
            mis_b += mb
            mis_i += mi
            print('  %s %-7s border %d/%d missing, interior %d/%d missing' % (tag, name, mb, nb, mi, ni), flush=True)
        shown = sorted(missing)[:40]
        if shown:
            print('  %s missing cells: %s' % (tag, shown), flush=True)
        print('SUMMARY %s server border_missing=%d/%d interior_missing=%d/%d client_missing=%d' % (
            tag, mis_b, tot_b, mis_i, tot_i, len(cl)), flush=True)
        return len(missing)

    if OPT['mode'] == 'edge':
        if OPT['phase'] == 'check':
            return
        # Right after the login, with no wait for the chunks around the spawn: a /fill over the border x = 15 | 16 whose far half is in a chunk the
        # server has not loaded yet. Either the command refuses the whole box ("That position is not loaded") and nothing is written, or it
        # fills and every block is really there on the server. What it must never do is say "12 blocks filled" and store only the loaded half
        # (the other half then showed on the client as phantom blocks and vanished when the real chunk arrived).
        edge = []
        for xx in range(9, 21):
            edge.append((xx, 67, 4))
        must('fill 5 63 1 25 83 7 minecraft:air')
        must('fill 5 62 1 25 62 7 minecraft:stone')
        out = rcon('fill 9 67 4 20 67 4 %s' % MAT)
        print('  edge fill -> %s' % out, flush=True)
        settle(2.0)
        have = [p for p in edge if probe(*p)]
        client = [p for p in edge if w.block(*p) not in (None, 0)]
        print('SUMMARY edge fill=%r server_planks=%d/12 client_planks=%d/12' % (out, len(have), len(client)), flush=True)
        if 'filled' in out:
            ok = len(have) == 12
        else:
            ok = 'not loaded' in out and len(have) == 0 and len(client) == 0
        print('RESULT %s' % ('PASS' if ok else 'FAIL'), flush=True)
        if not ok:
            raise m.Fail('the border fill stored %d of 12 blocks but answered %r (client shows %d)' % (len(have), out, len(client)))
        return

    if OPT['phase'] == 'check':
        to_area()
        settle(3.0)
        miss = read_all()
        n = report('after-restart', miss, client_missing())
        print('RESULT %s' % ('PASS' if n == 0 else 'FAIL'), flush=True)
        if n:
            raise m.Fail('blocks missing after restart')
        return

    to_area()
    need_chunks()
    if OPT['pregen']:
        print(rcon('pregen start %d' % OPT['pregen']), flush=True)
    # clear + floor under every line (small boxes: the /fill limit is 32768)
    boxes = [(-24, 44, 99, 101, 'x'), (19, 21, 82, 132, 'z'), (2, 4, 103, 105, 'c'), (14, 17, 103, 105, 'c'), (-14, 30, 107, 109, 'd')]
    for (x0, x1, z0, z1, kind) in boxes:
        h = 3 if kind not in ('c', 'd') else (43 if kind == 'c' else 6)
        for zz in range(z0, z1 + 1, 16) if kind == 'z' else [z0]:
            zz1 = min(zz + 15, z1) if kind == 'z' else z1
            must('fill %d %d %d %d %d %d minecraft:air' % (x0, Y, zz, x1, Y + h, zz1))
            must('fill %d %d %d %d %d %d minecraft:stone' % (x0, Y - 1, zz, x1, Y - 1, zz1))
    settle(1.0)

    # the floating deck between two stone pillars is always built by command (as tests/trigger_scenario.py does)
    must('fill -13 %d 108 -13 %d 108 minecraft:stone' % (Y, Y + 4))
    must('fill 29 %d 108 29 %d 108 minecraft:stone' % (Y, Y + 4))
    must('fill -12 %d 108 28 %d 108 %s' % (Y + 4, Y + 4, MAT))
    if OPT['mode'] == 'cmd':
        # a /fill across the borders for the rows, a /setblock each for the columns
        must('fill -20 %d 100 40 %d 100 %s' % (Y, Y, MAT))
        must('fill 20 %d 84 20 %d 130 %s' % (Y, Y, MAT))
        for cx in (3, 15, 16):
            for y in range(Y, Y + 41):
                must('setblock %d %d 104 %s' % (cx, y, MAT))
    else:
        rcon('give %s %s 64' % (OPT['name'], MAT))
        c.send(m.SB_CARRIED, struct.pack('>h', 0))
        seq = [100]

        def place(x, y, z):
            seq[0] += 1
            c.send(m.SB_USE_ON, m.varint(0) + m.block_pos(x, y - 1, z) + m.varint(1) + struct.pack('>fff', 0.5, 1.0, 0.5) +
                   bytes([0, 0]) + m.varint(seq[0]))
            try:
                wait(lambda: w.block(x, y, z) not in (None, 0), 'placed %d %d %d' % (x, y, z), 4.0)
            except Exception:
                return False
            return True

        failed = 0
        for name, lst in lines():
            if name == 'deck':
                continue
            # a row is placed from a spot two blocks beside it, a column from the block beside its foot (moving up)
            for i, (x, y, z) in enumerate(lst):
                if name.startswith('col'):
                    if i % 4 == 0 or i == 0:
                        tp(x + 1.0, y + 1.0, z + 0.0, 0.6)
                elif name == 'rowx':
                    if i % 4 == 0:
                        tp(x + 3.0, y + 1.0, z + 2.0, 0.6)
                else:
                    if i % 4 == 0:
                        tp(x + 2.0, y + 1.0, z + 3.0, 0.6)
                if not place(x, y, z):
                    failed += 1
        print('  bot placements that got no block update: %d' % failed, flush=True)
        # the bot blocks the way for nothing, go back above the area
    settle(OPT['wait'])
    if OPT['away']:
        tp(5000, 120, 5000, 1.0)
        settle(float(OPT['away']))
        to_area()
        settle(2.0)
    cl = client_missing()
    miss = read_all()
    n = report('5s', miss, cl)
    if OPT['pregen']:
        print(rcon('pregen status'), flush=True)
    print(rcon('save-all'), flush=True)
    settle(3.0)
    miss2 = read_all()
    n2 = report('after-save', miss2, client_missing())
    print('RESULT %s' % ('PASS' if n == 0 and n2 == 0 else 'FAIL'), flush=True)
    if n or n2:
        raise m.Fail('blocks missing')


fake = types.ModuleType('mcbot_c1')
fake.c1_session = session
fake.c1_verify_session = session
sys.modules['mcbot_c1'] = fake

if __name__ == '__main__':
    argv = sys.argv
    for key, kind in (('rcon-port', int), ('phase', str), ('mode', str), ('y', int), ('away', int), ('pregen', int), ('wait', float),
                      ('material', str), ('password', str)):
        for i, a in enumerate(argv):
            if a == '--' + key:
                OPT[key.replace('-', '_')] = kind(argv[i + 1])
                del argv[i:i + 2]
                break
    for i, a in enumerate(argv):
        if a == '--name':
            OPT['name'] = argv[i + 1]
            break
    argv.append('--c1')
    mcbot.main()
