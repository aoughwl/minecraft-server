"""Light-update scenario against a PRIVATE server (tests/run_lightupdate_scenario.sh): a block change that changes light must reach the client
as a light update packet (CLightUpdate, 0x2F on protocol 774), not only as a block update.

The bot (an operator) digs sealed, dark cavities underground and then, with real commands:
  1. /setblock torch               -> a light update must arrive whose block light is 14 at the torch and 13 around it (14 - distance everywhere)
  2. /fill glowstone (a line)      -> same for the bulk path (15 in each glowstone, 14 beside it, ...)
  3. /setblock torch near a chunk border -> the NEIGHBOUR chunk's light update arrives with the spread light
  4. removing that torch           -> the darkness arrives too
It also bounds the packets: a handful per command (no storm).

Runs tools/mcbot.py through its --commands slot (like the earlier light probe). Exit status 0 only when every check passes.
"""
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import mcbot  # noqa: E402
from mcbot import Reader  # noqa: E402

LIGHT_UPDATE_ID = int(os.environ.get('LU_PACKET_ID', '47'))   # 0x2F in 1.21.11 (protocol 774)
MIN_Y = -64
UPDATES = []   # (time, cx, cz, sky arrays by mask bit, block arrays by mask bit, empty block bits, empty sky bits)
FAILS = []


def parse_light(data):
    r = Reader(data)
    cx = r.varint()
    cz = r.varint()
    masks = []
    for _ in range(4):
        words, _n = mcbot.bitcount_mask(r)
        bits = []
        for wi, w in enumerate(words):
            for b in range(64):
                if (w >> b) & 1:
                    bits.append(wi * 64 + b)
        masks.append(bits)
    sky_bits, blk_bits, esky, eblk = masks
    arrays = []
    for bits in (sky_bits, blk_bits):
        n = r.varint()
        assert n == len(bits), 'array count %d for %d mask bits' % (n, len(bits))
        out = {}
        for b in bits:
            size = r.varint()
            assert size == 2048, 'light array of %d bytes' % size
            out[b] = bytes(r.take(2048))
        arrays.append(out)
    assert r.left() == 0, '%d trailing bytes in the light update' % r.left()
    return cx, cz, arrays[0], arrays[1], set(eblk), set(esky)


def nib(arr, x, y, z):
    i = y * 256 + z * 16 + x
    b = arr[i >> 1]
    return (b >> 4) if (i & 1) else (b & 15)


def block_light_in(updates, x, y, z):
    """The block light at a cell according to the LAST light update for its chunk (None when no update names that section)."""
    got = None
    for (_t, cx, cz, _sky, blk, eblk, _esky) in updates:
        if cx != (x >> 4) or cz != (z >> 4):
            continue
        sec = (y - MIN_Y) // 16 + 1
        if sec in blk:
            got = nib(blk[sec], x & 15, (y - MIN_Y) % 16, z & 15)
        elif sec in eblk:
            got = 0
    return got


def check(ok, what):
    print(('  ok   ' if ok else '  FAIL ') + what, flush=True)
    if not ok:
        FAILS.append(what)


def expected(sources, cells):
    out = {}
    for (x, y, z) in cells:
        best = 0
        for (sx, sy, sz, lv) in sources:
            best = max(best, lv - (abs(sx - x) + abs(sy - y) + abs(sz - z)))
        out[(x, y, z)] = max(best, 0)
    return out


def tap(pid, data):
    if pid == LIGHT_UPDATE_ID:
        try:
            cx, cz, sky, blk, eblk, esky = parse_light(data)
        except Exception as e:  # a malformed packet is itself a failure
            FAILS.append('light update does not parse: %r' % (e,))
            return
        UPDATES.append((time.time(), cx, cz, sky, blk, eblk, esky))


def per_chunk_counts(new):
    out = {}
    for u in new:
        out[(u[1], u[2])] = out.get((u[1], u[2]), 0) + 1
    return out


def session(c, st, w, biomes, ctx, args):
    ctx['tap'] = tap

    def wait(cond, what, seconds=10.0):
        mcbot.pump(c, st, w, biomes, ctx, cond, what, seconds)

    def settle(sec):
        end = time.time() + sec
        while time.time() < end:
            try:
                pid, r = c.recv()
            except Exception:
                continue
            mcbot.one_packet(c, st, w, biomes, ctx, pid, r)

    def cmd(line):
        print('  /%s' % line, flush=True)
        c.send(mcbot.SB_CHAT_COMMAND, mcbot.string(line))

    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'pos+chunk', 40.0)
    settle(4.0)
    px, py, pz = w.pos
    base_x = (int(px) // 16) * 16
    cz0 = (int(pz) // 16) * 16 + 8
    y0 = -40
    cx = base_x + 8
    print('spawn', w.pos, 'chunk base x', base_x, flush=True)
    cmd('gamemode creative')
    settle(0.5)

    # Site A: a cavity inside one chunk (x base+3..13); site B: a cavity row across the chunk border at x = base+16.
    cmd('fill %d %d %d %d %d %d stone' % (cx - 6, y0 - 1, cz0 - 6, cx + 6, y0 + 6, cz0 + 6))
    settle(1.0)
    cmd('fill %d %d %d %d %d %d air' % (cx - 5, y0, cz0 - 5, cx + 5, y0 + 4, cz0 + 5))
    settle(1.0)
    zb = cz0 + 12
    # (one /fill per chunk column: a fill across a chunk border is not what is under test)
    for (xa, xb) in ((base_x + 10, base_x + 15), (base_x + 16, base_x + 22)):
        cmd('fill %d %d %d %d %d %d stone' % (xa, y0 - 1, zb - 2, xb, y0 + 3, zb + 2))
        settle(1.0)
    for (xa, xb) in ((base_x + 11, base_x + 15), (base_x + 16, base_x + 21)):
        cmd('fill %d %d %d %d %d %d air' % (xa, y0, zb - 1, xb, y0 + 2, zb + 1))
        settle(1.0)
    settle(1.0)
    print('light updates during setup (not asserted): %d' % len(UPDATES), flush=True)

    # 1. a torch via /setblock
    n0 = len(UPDATES)
    cmd('setblock %d %d %d torch' % (cx, y0, cz0))
    settle(2.5)
    new = UPDATES[n0:]
    check(len(new) >= 1, 'torch: a light update (0x%02x) arrived after /setblock (got %d)' % (LIGHT_UPDATE_ID, len(new)))
    pc = per_chunk_counts(new)
    check(all(v <= 2 for v in pc.values()) and len(new) <= 4, 'torch: no storm (%s)' % pc)
    cells = [(x, y, z) for x in range(cx - 5, cx + 6) for y in range(y0, y0 + 5) for z in range(cz0 - 5, cz0 + 6)]
    src = [(cx, y0, cz0, 14)]
    exp = expected(src, cells)
    check(block_light_in(new, cx, y0, cz0) == 14, 'torch: block light 14 at the torch (got %r)' % (block_light_in(new, cx, y0, cz0),))
    for d, p in (('+x', (cx + 1, y0, cz0)), ('-x', (cx - 1, y0, cz0)), ('+z', (cx, y0, cz0 + 1)), ('-z', (cx, y0, cz0 - 1)),
                 ('+y', (cx, y0 + 1, cz0))):
        check(block_light_in(new, *p) == 13, 'torch: block light 13 at %s (got %r)' % (d, block_light_in(new, *p)))
    bad = [(p, e, block_light_in(new, *p)) for p, e in exp.items() if block_light_in(new, *p) != e]
    check(not bad, 'torch: the whole cavity (%d cells) matches 14 - distance; %d wrong %s' % (len(cells), len(bad), bad[:4]))

    # 2. a glowstone line via /fill (the bulk path)
    n0 = len(UPDATES)
    cmd('fill %d %d %d %d %d %d glowstone' % (cx - 5, y0 + 4, cz0 - 3, cx - 5, y0 + 4, cz0 + 3))
    settle(2.5)
    new = UPDATES[n0:]
    check(len(new) >= 1, 'fill glowstone: a light update arrived (got %d)' % len(new))
    pc = per_chunk_counts(new)
    check(all(v <= 2 for v in pc.values()) and len(new) <= 4, 'fill glowstone: no storm (%s)' % pc)
    gs = [(cx - 5, y0 + 4, z, 15) for z in range(cz0 - 3, cz0 + 4)]
    cells2 = [(x, y, z) for x in range(cx - 4, cx + 6) for y in range(y0, y0 + 4) for z in range(cz0 - 5, cz0 + 6)]
    exp2 = expected(src + gs, cells2)
    check(block_light_in(new, cx - 5, y0 + 4, cz0) == 15, 'fill glowstone: block light 15 in the glowstone (got %r)' % (block_light_in(new, cx - 5, y0 + 4, cz0),))
    check(block_light_in(new, cx - 4, y0 + 4, cz0) == 14, 'fill glowstone: 14 beside it (got %r)' % (block_light_in(new, cx - 4, y0 + 4, cz0),))
    bad = [(p, e, block_light_in(new, *p)) for p, e in exp2.items() if block_light_in(new, *p) != e]
    check(not bad, 'fill glowstone: cavity matches max(torch, glowstone) light; %d of %d wrong %s' % (len(bad), len(cells2), bad[:4]))

    # 3. near the chunk border: a torch at x = base+14, the light spreads into the next chunk (x >= base+16)
    n0 = len(UPDATES)
    tx = base_x + 14
    cmd('setblock %d %d %d torch' % (tx, y0, zb))
    settle(2.5)
    new = UPDATES[n0:]
    chunks = sorted(set((u[1], u[2]) for u in new))
    check((base_x >> 4, zb >> 4) in chunks and ((base_x >> 4) + 1, zb >> 4) in chunks,
          'border: light updates for the torch chunk AND the neighbour chunk (got %s)' % chunks)
    check(block_light_in(new, tx, y0, zb) == 14, 'border: 14 at the torch (got %r)' % (block_light_in(new, tx, y0, zb),))
    check(block_light_in(new, tx + 2, y0, zb) == 12, 'border: 12 two cells away, in the neighbour chunk (got %r)' % (block_light_in(new, tx + 2, y0, zb),))
    check(block_light_in(new, tx + 5, y0, zb) == 9, 'border: 9 five cells away (got %r)' % (block_light_in(new, tx + 5, y0, zb),))
    check(len(new) <= 6, 'border: no storm (%d packets)' % len(new))

    # 4. removing the torch: the darkness must be sent too
    n0 = len(UPDATES)
    cmd('setblock %d %d %d air' % (tx, y0, zb))
    settle(2.5)
    new = UPDATES[n0:]
    check(block_light_in(new, tx + 2, y0, zb) == 0, 'removal: 0 two cells away in the neighbour chunk (got %r)' % (block_light_in(new, tx + 2, y0, zb),))
    check(block_light_in(new, tx, y0, zb) == 0, 'removal: 0 at the old torch cell (got %r)' % (block_light_in(new, tx, y0, zb),))

    print('RESULT %s (%d light updates in all)' % ('PASS' if not FAILS else 'FAIL: %d' % len(FAILS), len(UPDATES)), flush=True)
    c.close()
    raise SystemExit(0 if not FAILS else 1)


mcbot.commands_session = session
if __name__ == '__main__':
    argv = sys.argv
    if '--commands' not in argv:
        argv.append('--commands')
    if '--op' not in argv:
        argv.append('--op')
    mcbot.main()
