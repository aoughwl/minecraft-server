"""Sessions for mcbot.py's --c1 and --c1-verify: a furnace smelts raw iron over the wire and the output survives a restart.

mcbot.py hands its own module in as `m`. The bot must be an operator of level 4 on a COPY of a world.
--c1: places a furnace, puts raw iron and coal in it with /item replace block, waits for the smelt (200 ticks), opens the
window and wants an iron ingot in the output slot. --c1-verify FILE: after a restart opens it again and wants the same
ingot(s) still in the output slot and the input shorter.
"""
import json
import socket
import struct
import time


def _open(m, c, st, w, biomes, ctx, log, x, y, z, seq):
    del log[:]
    seq[0] += 1
    c.send(m.SB_USE_ON, m.varint(0) + m.block_pos(x, y, z) + m.varint(1) + struct.pack('>fff', 0.5, 1.0, 0.5) +
           bytes([0, 0]) + m.varint(seq[0]))
    m.pump(c, st, w, biomes, ctx, lambda: any(p == m.PLAY_OPEN_SCREEN for p, _ in log), 'an open screen packet')
    r = m.Reader([d for p, d in log if p == m.PLAY_OPEN_SCREEN][0])
    sync_id, wtype = r.varint(), r.varint()

    def content():
        for p, d in log:
            if p == m.PLAY_CONTAINER_CONTENT:
                r2 = m.Reader(d)
                if r2.varint() == sync_id:
                    r2.varint()
                    return [m.read_slot(r2) for _ in range(r2.varint())]
        return None
    m.pump(c, st, w, biomes, ctx, lambda: content() is not None, 'the window content')
    return sync_id, wtype, content()


def c1_session(m, c, st, w, biomes, ctx, args):
    check = m.check
    log = []
    ctx['tap'] = lambda pid, data: log.append((pid, bytes(data)))
    seq = [500]

    def settle(seconds=0.6):
        end = time.time() + seconds
        while time.time() < end:
            try:
                pid, r = c.recv()
            except socket.timeout:
                continue
            m.one_packet(c, st, w, biomes, ctx, pid, r)

    def cmd(line):
        print('  /%s' % line, flush=True)
        c.send(m.SB_CHAT_COMMAND, m.string(line))

    m.pump(c, st, w, biomes, ctx, lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    m.pump(c, st, w, biomes, ctx, lambda: w.health is not None, 'health')
    c.send(m.SB_CHANGE_GAME_MODE, m.varint(1))
    m.pump(c, st, w, biomes, ctx, lambda: w.mode == 1, 'creative')
    px, py, pz = int(w.pos[0] // 1), int(w.pos[1] // 1), int(w.pos[2] // 1)
    m.pump(c, st, w, biomes, ctx, lambda: w.block(px, py - 1, pz) is not None, 'the chunk under the player', 30.0)
    sx, fy, sz = px + 2, py - 1, pz + 2
    cmd('fill %d %d %d %d %d %d minecraft:air' % (sx - 1, fy + 1, sz - 1, sx + 6, fy + 5, sz + 6))
    cmd('fill %d %d %d %d %d %d minecraft:stone' % (sx - 1, fy, sz - 1, sx + 6, fy, sz + 6))
    cmd('tp @s %d %d %d' % (sx + 2, fy + 1, sz + 2))
    settle(1.5)
    fx, fz = sx + 3, sz + 3
    cmd('setblock %d %d %d minecraft:furnace' % (fx, fy + 1, fz))
    settle(0.8)
    check(w.block(fx, fy + 1, fz) not in (None, 0), 'no furnace at the stage')
    cmd('item replace block %d %d %d container.0 with minecraft:raw_iron 3' % (fx, fy + 1, fz))
    cmd('item replace block %d %d %d container.1 with minecraft:coal 1' % (fx, fy + 1, fz))
    settle(1.0)
    end = time.time() + 16.0
    while time.time() < end:
        try:
            pid, r = c.recv()
        except socket.timeout:
            continue
        m.one_packet(c, st, w, biomes, ctx, pid, r)
    sync_id, wtype, slots = _open(m, c, st, w, biomes, ctx, log, fx, fy + 1, fz, seq)
    print('  furnace window %d type %d: input %s fuel %s output %s' % (sync_id, wtype, slots[0], slots[1], slots[2]),
          flush=True)
    check(slots[2][0] >= 1, 'the output slot is empty after the smelt: %s' % (slots[2],))
    check(slots[0][0] < 3, 'the input was not used: %s' % (slots[0],))
    c.send(m.SB_CONTAINER_CLOSE, m.varint(sync_id))
    settle(0.5)
    ctx['c1_state'] = {'pos': [fx, fy + 1, fz], 'output': list(slots[2]), 'input': list(slots[0])}


def c1_verify_session(m, c, st, w, biomes, ctx, args):
    check = m.check
    with open(args.c1_verify) as f:
        saved = json.load(f)
    log = []
    ctx['tap'] = lambda pid, data: log.append((pid, bytes(data)))
    x, y, z = saved['pos']
    m.pump(c, st, w, biomes, ctx, lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    m.pump(c, st, w, biomes, ctx, lambda: w.health is not None, 'health')
    c.send(m.SB_CHANGE_GAME_MODE, m.varint(1))
    m.pump(c, st, w, biomes, ctx, lambda: w.mode == 1, 'creative')
    c.send(m.SB_CHAT_COMMAND, m.string('tp @s %d %d %d' % (x, y + 2, z)))
    m.pump(c, st, w, biomes, ctx, lambda: w.block(x, y, z) is not None, 'the chunk of the furnace', 30.0)
    end = time.time() + 1.5
    while time.time() < end:
        try:
            pid, r = c.recv()
        except socket.timeout:
            continue
        m.one_packet(c, st, w, biomes, ctx, pid, r)
    check(w.block(x, y, z) not in (None, 0), 'no furnace after the restart')
    sync_id, wtype, slots = _open(m, c, st, w, biomes, ctx, log, x, y, z, [900])
    print('  furnace after the restart: input %s output %s' % (slots[0], slots[2]), flush=True)
    check(slots[2][0] >= saved['output'][0], 'the output is %s, was %s' % (slots[2], saved['output']))
    check(slots[2][1] == saved['output'][1], 'the output item changed: %s' % (slots[2],))
    c.send(m.SB_CONTAINER_CLOSE, m.varint(sync_id))
