"""Sessions for mcbot.py's --c2 and --c2-verify: a sign with text, a bed slept in, a piston pushing a block, over the wire.

mcbot.py hands its own module in as `m`, so this file uses the bot's connection, packet pump and block table as they are.
The bot must be an operator of level 4 on a COPY of a world.
"""
import json
import os
import re
import socket
import struct
import time

SB_SIGN_UPDATE = 59      # serverbound sign_update, 1.21.11
PLAY_BLOCK_ENTITY_DATA = 6
PLAY_OPEN_SIGN_EDITOR = 58
PLAY_SET_ENTITY_DATA = 97
PLAY_SPAWN_POS_ID = 95   # set_default_spawn_position... the bot's PLAY_SPAWN_POS

SIGN_TEXT = ['hello c2', 'second', '', 'fourth']

_GEN = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'src', 'generated')
_TABLES = {}


def _table(file, const):
    """A hex-packed u16 table of src/generated, as a list. The bot's block table is the data's own (26.2) numbering; the wire is 774."""
    key = (file, const)
    if key not in _TABLES:
        with open(os.path.join(_GEN, file), encoding='utf-8') as f:
            text = f.read()
        m = re.search(r'const %s\*? = "([0-9a-f]*)"' % const, text)
        assert m, const
        h = m.group(1)
        _TABLES[key] = [int(h[i:i + 4], 16) for i in range(0, len(h), 4)]
    return _TABLES[key]


def wire_item(m, name):
    """The item id the 774 wire carries for the item of this name."""
    return _table('item_id_remap.aowl', 'ITEM_ID_REMAP_V_26_2_TO_V_1_21_11')[m.BLOCK_TABLE['by_name'][name]['item_id']]


def wire_name(m, state):
    """The block a 774 state id is: the lowest 26.2 state that maps to it, named."""
    if state is None:
        return None
    if 'inv' not in _TABLES:
        table = _table('block_state_remap.aowl', 'BLOCK_STATE_REMAP_V_26_2_TO_V_1_21_11')
        inv = {}
        for s26, s774 in enumerate(table):
            inv.setdefault(s774, s26)
        _TABLES['inv'] = inv
    return m.block_name(_TABLES['inv'].get(state, state))


def c2_session(m, c, st, w, biomes, ctx, args):
    check = m.check

    def wait(cond, what, seconds=10.0):
        m.pump(c, st, w, biomes, ctx, cond, what, seconds)

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

    token = [0x7100]

    def sync():
        token[0] += 1
        c.send(m.SB_PING, struct.pack('>q', token[0]))
        t = token[0]
        wait(lambda: t in w.pongs, 'a pong')

    def item_of(name):
        return wire_item(m, name)

    def hold(name):
        """The item in the first hotbar slot, given by command (the creative-slot packet needs the 774 ids and the stack limits)."""
        cmd('clear @s')
        cmd('give @s minecraft:%s 1' % name)
        c.send(m.SB_CARRIED, struct.pack('>h', 0))
        settle(0.8)
        sync()

    seq = [300]

    def use_on(x, y, z, face, cursor=(0.5, 0.5, 0.5)):
        seq[0] += 1
        c.send(m.SB_USE_ON, m.varint(0) + m.block_pos(x, y, z) + m.varint(face) + struct.pack('>fff', *cursor) +
               bytes([0, 0]) + m.varint(seq[0]))

    def state_at(x, y, z):
        return w.block(x, y, z)

    def name_at(x, y, z):
        return wire_name(m, state_at(x, y, z))

    seen = {}

    def tap(pid, data):
        if pid in (PLAY_BLOCK_ENTITY_DATA, PLAY_OPEN_SIGN_EDITOR, PLAY_SET_ENTITY_DATA, PLAY_SPAWN_POS_ID):
            seen.setdefault(pid, []).append(bytes(data))

    ctx['tap'] = tap

    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    wait(lambda: w.health is not None, 'health')
    c.send(m.SB_CHANGE_GAME_MODE, m.varint(1))
    wait(lambda: w.mode == 1, 'creative')
    px, py, pz = int(w.pos[0] // 1), int(w.pos[1] // 1), int(w.pos[2] // 1)
    wait(lambda: w.block(px, py - 1, pz) is not None, 'the chunk under the player', 30.0)
    sx, fy, sz = px + 2, py - 1, pz + 2
    cmd('fill %d %d %d %d %d %d minecraft:air' % (sx - 1, fy + 1, sz - 1, sx + 12, fy + 8, sz + 7))
    cmd('fill %d %d %d %d %d %d minecraft:stone' % (sx - 1, fy, sz - 1, sx + 12, fy, sz + 7))
    cmd('tp @s %d %d %d' % (sx + 4, fy + 1, sz + 5))
    wait(lambda: name_at(sx + 4, fy, sz + 5) == 'stone' and name_at(sx + 4, fy + 3, sz + 5) == 'air', 'the stage')
    settle(1.0)
    print('  stage floor y=%d from %d,%d' % (fy, sx, sz), flush=True)
    state = dict(stage=[sx, fy, sz])

    # --- A sign: placed, the editor opens, the text comes back in the block entity data.
    if os.environ.get('C2_SKIP_SIGN'):
        state['sign'] = None
    else:
        gx, gz = sx + 2, sz + 1
        hold('oak_sign')
        use_on(gx, fy, gz, 1)
        try:
            wait(lambda: name_at(gx, fy + 1, gz) == 'oak_sign', 'the sign', 4.0)
        except m.Fail as e:
            print('  SIGN NOT PLACED: %s; state %r' % (e, state_at(gx, fy + 1, gz)), flush=True)
            raise
        wait(lambda: PLAY_OPEN_SIGN_EDITOR in seen, 'the sign editor')
        editor = seen[PLAY_OPEN_SIGN_EDITOR][0]
        check(editor[8:9] == b'\x01', 'the editor opens on the front text: %r' % editor)
        print('  oak_sign placed and the editor opened: %r' % editor, flush=True)
        st.hit('sign_placed')
        c.send(SB_SIGN_UPDATE, m.block_pos(gx, fy + 1, gz) + bytes([1]) + b''.join(m.string(t) for t in SIGN_TEXT))
        wait(lambda: any(SIGN_TEXT[0].encode() in d for d in seen.get(PLAY_BLOCK_ENTITY_DATA, [])), 'the sign text in block entity data')
        update = [d for d in seen[PLAY_BLOCK_ENTITY_DATA] if SIGN_TEXT[0].encode() in d][-1]
        check(b'second' in update and b'fourth' in update, 'every line is in the update')
        print('  the sign text came back in %d bytes of block entity data' % len(update), flush=True)
        st.hit('sign_text_set')
        state['sign'] = [gx, fy + 1, gz, state_at(gx, fy + 1, gz)]

    # --- A bed: placed, then slept in at night.
    cmd('time set 13000')
    bx, bz = sx + 4, sz + 1
    hold('red_bed')
    use_on(bx, fy, bz, 1)
    wait(lambda: name_at(bx, fy + 1, bz) == 'red_bed', 'the bed foot')
    wait(lambda: any(name_at(bx + dx, fy + 1, bz + dz) == 'red_bed' for dx, dz in ((0, 1), (0, -1), (1, 0), (-1, 0))), 'the bed head')
    print('  red_bed placed at %d,%d' % (bx, bz), flush=True)
    st.hit('bed_placed')
    foot_before = state_at(bx, fy + 1, bz)
    spawn_packets = len(seen.get(PLAY_SPAWN_POS_ID, []))
    entity_packets = len(seen.get(PLAY_SET_ENTITY_DATA, []))
    chat_at = len(w.chat)
    use_on(bx, fy + 1, bz, 1)
    settle(1.5)
    print('  said: %r' % w.chat[chat_at:], flush=True)
    check(not any('not_safe' in s or 'no_sleep' in s or 'too_far' in s or 'obstructed' in s or 'occupied' in s
                  for s in w.chat[chat_at:]), 'the server refused sleep: %r' % w.chat[chat_at:])
    check(len(seen.get(PLAY_SPAWN_POS_ID, [])) > spawn_packets, 'no respawn point was set')
    check(len(seen.get(PLAY_SET_ENTITY_DATA, [])) > entity_packets, 'no entity data (the sleeping pose) followed')
    foot_after = state_at(bx, fy + 1, bz)
    check(wire_name(m, foot_after) == 'red_bed' and foot_after != foot_before, 'the bed is not occupied: %r %r' % (foot_before, foot_after))
    print('  slept: respawn point set, bed state %d -> %d (occupied)' % (foot_before, foot_after), flush=True)
    st.hit('bed_slept')
    state['bed'] = [bx, fy + 1, bz, foot_after]

    # --- A piston pushing a stone.
    cmd('tp @s %d %d %d' % (sx + 9, fy + 1, sz + 5))
    px0, pz0 = sx + 8, sz + 1
    cmd('setblock %d %d %d minecraft:piston[facing=east]' % (px0, fy + 1, pz0))
    cmd('setblock %d %d %d minecraft:stone' % (px0 + 1, fy + 1, pz0))
    wait(lambda: name_at(px0, fy + 1, pz0) == 'piston' and name_at(px0 + 1, fy + 1, pz0) == 'stone', 'the piston and its stone')
    settle(0.5)
    check(name_at(px0 + 2, fy + 1, pz0) == 'air', 'room behind the stone')
    cmd('setblock %d %d %d minecraft:redstone_block' % (px0, fy + 2, pz0))
    wait(lambda: name_at(px0 + 2, fy + 1, pz0) == 'stone', 'the stone pushed', 12.0)
    wait(lambda: name_at(px0 + 1, fy + 1, pz0) == 'piston_head', 'the piston head', 12.0)
    settle(0.5)
    print('  piston pushed: %s %s %s' % (name_at(px0, fy + 1, pz0), name_at(px0 + 1, fy + 1, pz0), name_at(px0 + 2, fy + 1, pz0)),
          flush=True)
    st.hit('piston_pushed')
    state['piston'] = [px0, fy + 1, pz0, state_at(px0, fy + 1, pz0), state_at(px0 + 1, fy + 1, pz0), state_at(px0 + 2, fy + 1, pz0)]
    ctx['c2_state'] = state


def c2_verify_session(m, c, st, w, biomes, ctx, args):
    check = m.check
    with open(args.c2_verify) as f:
        saved = json.load(f)
    chunks = []

    def tap(pid, data):
        if pid == m.PLAY_CHUNK:
            chunks.append(bytes(data))

    ctx['tap'] = tap
    m.pump(c, st, w, biomes, ctx, lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)

    def name_at(x, y, z):
        return wire_name(m, w.block(x, y, z))

    def cmd(line):
        print('  /%s' % line, flush=True)
        c.send(m.SB_CHAT_COMMAND, m.string(line))

    sx, fy, sz = saved['stage']
    # Go far away and come back, so the stage's chunks are sent again after the tap is set.
    cmd('tp @s %d %d %d' % (sx + 600, fy + 1, sz))
    time.sleep(1.0)
    end = time.time() + 2.0
    while time.time() < end:
        try:
            pid, r = c.recv()
        except socket.timeout:
            continue
        m.one_packet(c, st, w, biomes, ctx, pid, r)
    cmd('tp @s %d %d %d' % (sx + 4, fy + 1, sz + 5))
    m.pump(c, st, w, biomes, ctx, lambda: w.block(sx, fy, sz) is not None and any(SIGN_TEXT[0].encode() in d for d in chunks),
           'the stage chunk again, with the sign text in it', 40.0)
    gx, gy, gz, gstate = saved['sign']
    check(w.block(gx, gy, gz) == gstate, 'the sign is %s' % name_at(gx, gy, gz))
    sign_chunk = [d for d in chunks if SIGN_TEXT[0].encode() in d][-1]
    check(b'second' in sign_chunk and b'fourth' in sign_chunk, 'every line of the sign came back')
    print('  the sign and its text are in the chunk the server sends', flush=True)
    st.hit('sign_persisted')
    bx, by, bz, bstate = saved['bed']
    check(w.block(bx, by, bz) == bstate or name_at(bx, by, bz) == 'red_bed', 'the bed is %s' % name_at(bx, by, bz))
    heads = [name_at(bx + dx, by, bz + dz) for dx, dz in ((0, 1), (0, -1), (1, 0), (-1, 0))]
    check('red_bed' in heads, 'the bed head is gone: %r' % heads)
    print('  the bed is still there (state %d, was %d when saved)' % (w.block(bx, by, bz), bstate), flush=True)
    st.hit('bed_persisted')
    qx, qy, qz, p0, p1, p2 = saved['piston']
    check(name_at(qx, qy, qz) == 'piston' and w.block(qx, qy, qz) == p0, 'the piston is %s' % name_at(qx, qy, qz))
    check(name_at(qx + 1, qy, qz) == 'piston_head' and w.block(qx + 1, qy, qz) == p1, 'the head is %s' % name_at(qx + 1, qy, qz))
    check(name_at(qx + 2, qy, qz) == 'stone', 'the pushed stone is %s' % name_at(qx + 2, qy, qz))
    print('  the piston, its head and the pushed stone are still there', flush=True)
    st.hit('piston_persisted')
