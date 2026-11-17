"""Automatic collapse triggers against a private server (never the user's): a 12 long plank bridge between two stone pillars, 9 iron blocks
PLACED BY THE BOT on it (use-item-on, so the block log records cause=place), with `physics_triggers`
  1. at its default (off): nothing happens, the bridge keeps standing and no body appears;
  2. structures (switched on with /body triggers structures over RCON): the debounced trigger runs the solver, the deck breaks and a body
     appears (`/body status` created >= 1, blocks vanish on the client).

    python tests/trigger_scenario.py --port 25840 --rcon-port 25841 --name TrigBot --op

Runs tools/mcbot.py UNEDITED through its --c1 session slot (like tests/body_scenario.py). The bot must be a level 4 operator of a scratch
server with RCON enabled (tests/run_trigger_scenario.sh). PASS / FAIL per step; INCONCLUSIVE when the bot could not place the iron blocks
(then no verdict on the triggers is claimed). Exit status 0 only when every step passed.
"""
import os
import re
import socket
import struct
import sys
import time
import types

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import mcbot  # noqa: E402

results = []
RCON_PORT = 25841
RCON_PASSWORD = 'trigpw'
NAME = 'TrigBot'


def step(name, ok, detail=''):
    results.append(ok)
    print('%s %s %s' % ('PASS' if ok else 'FAIL', name, detail), flush=True)


def rcon_cmd(sock, ident, line):
    sock.sendall(mcbot.rcon_packet(ident, 2, line))
    body = ''
    sock.settimeout(3.0)
    try:
        while True:
            pid, ptype, text = mcbot.rcon_read(sock)
            if pid == ident:
                body += text + '\n'
                sock.settimeout(0.4)
    except (socket.timeout, OSError):
        pass
    sock.settimeout(10)
    return body.strip()


def session(m, c, st, w, biomes, ctx, args):
    def wait(cond, what, seconds=15.0):
        m.pump(c, st, w, biomes, ctx, cond, what, seconds)

    def cmd(line):
        print('  /%s' % line, flush=True)
        c.send(m.SB_CHAT_COMMAND, m.string(line))

    def settle(seconds):
        end = time.time() + seconds
        try:
            m.pump(c, st, w, biomes, ctx, lambda: time.time() > end, 'time', seconds + 5.0)
        except Exception:
            pass

    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    wait(lambda: w.health is not None, 'health')
    c.send(m.SB_CHANGE_GAME_MODE, m.varint(1))
    wait(lambda: w.mode == 1, 'creative')
    px, py, pz = int(w.pos[0] // 1), int(w.pos[1] // 1), int(w.pos[2] // 1)
    wait(lambda: w.block(px, py - 1, pz) is not None, 'the chunk under the player', 30.0)
    rc = socket.create_connection(('127.0.0.1', RCON_PORT), timeout=10)
    rc.sendall(mcbot.rcon_packet(1, 3, RCON_PASSWORD))
    pid, _, _ = mcbot.rcon_read(rc)
    step('RCON login', pid == 1)
    ident = [10]

    def rcon(line):
        ident[0] += 1
        out = rcon_cmd(rc, ident[0], line)
        print('  rcon %s -> %s' % (line, out.replace('\n', ' | ')), flush=True)
        return out

    status0 = rcon('body triggers status')
    step('the default setting is off', 'Physics triggers: off' in status0, status0.split('\n')[0])

    seq = [100]

    def place_iron(x, y, z):
        """Use the held iron block on the top face of the block under (x, y, z)."""
        seq[0] += 1
        c.send(m.SB_USE_ON, m.varint(0) + m.block_pos(x, y - 1, z) + m.varint(1) + struct.pack('>fff', 0.5, 1.0, 0.5) +
               bytes([0, 0]) + m.varint(seq[0]))
        try:
            wait(lambda: w.block(x, y, z) not in (None, 0), 'iron at %d %d %d' % (x, y, z), 6.0)
        except Exception:
            return False
        return True

    def build_bridge(bx, by, bz):
        # a flat, clear patch, a stone floor, two pillars and the 12 plank deck (all by command: the iron is what the bot places)
        wait(lambda: w.block(bx, by, bz) is not None, 'the chunk of the bridge', 30.0)
        cmd('fill %d %d %d %d %d %d minecraft:air' % (bx - 3, by, bz - 3, bx + 17, by + 20, bz + 3))
        cmd('fill %d %d %d %d %d %d minecraft:stone' % (bx - 3, by - 1, bz - 3, bx + 17, by - 1, bz + 3))
        cmd('fill %d %d %d %d %d %d minecraft:stone' % (bx, by, bz, bx, by + 4, bz))
        cmd('fill %d %d %d %d %d %d minecraft:stone' % (bx + 13, by, bz, bx + 13, by + 4, bz))
        cmd('fill %d %d %d %d %d %d minecraft:oak_planks' % (bx + 1, by + 4, bz, bx + 12, by + 4, bz))
        wait(lambda: all(w.block(bx + i, by + 4, bz) not in (None, 0) for i in range(0, 14)), 'the bridge', 25.0)

    def deck_states(bx, by, bz):
        return [w.block(bx + i, by + 4, bz) for i in range(1, 13)]

    def deck_intact(bx, by, bz):
        return all(w.block(bx + i, by + 4, bz) not in (None, 0) for i in range(1, 13))

    def load_iron(bx, by, bz):
        rcon('give %s minecraft:iron_block 9' % NAME)
        c.send(m.SB_CARRIED, struct.pack('>h', 0))
        placed = 0
        for k in range(9):
            y = by + 5 + k
            cmd('tp %s %d %d %d' % (NAME, bx + 8, y, bz))
            settle(1.2)
            if place_iron(bx + 6, y, bz):
                placed += 1
            else:
                break
        return placed

    def created():
        out = rcon('body status')
        mm = re.search(r'created (\d+)', out)
        return int(mm.group(1)) if mm else -1

    # ---------------------------------------------------------------- A: triggers off (the default)
    # the deck and pillars (x + 1 .. x + 14) stay inside ONE chunk column: a plank on a chunk border (x = 16k) was seen to vanish
    # without any block log record, with every trigger off (server side observation, see the report)
    ax, ay, az = ((px >> 4) + 1) * 16 + 1, py, pz + 4
    build_bridge(ax, ay, az)
    step('bridge A stands', deck_intact(ax, ay, az))
    print('  deck after build: %s' % deck_states(ax, ay, az), flush=True)
    placedA = load_iron(ax, ay, az)
    print('  bridge A: %d iron blocks placed by the bot' % placedA, flush=True)
    if placedA < 9:
        print('INCONCLUSIVE the bot could only place %d of 9 iron blocks (use-item-on / give did not work); no verdict on the triggers' % placedA)
        rc.close()
        raise m.Fail('inconclusive: iron placement')
    print('  deck after iron: %s' % deck_states(ax, ay, az), flush=True)
    step('9 iron blocks stand on bridge A', all(w.block(ax + 6, ay + 5 + k, az) not in (None, 0) for k in range(9)))
    settle(25.0)
    srv = [rcon('fill %d %d %d %d %d %d minecraft:oak_planks replace minecraft:oak_planks' % (ax + i, ay + 4, az, ax + i, ay + 4, az)) for i in (11, 12)]
    print('  server side planks at x+11, x+12: %s' % srv, flush=True)
    step('triggers off: bridge A is still intact after 25 s', deck_intact(ax, ay, az), str(deck_states(ax, ay, az)))
    step('triggers off: no body was created', created() == 0)
    stA = rcon('body triggers status')
    step('triggers off: no check was started', 'checks 0' in stA, [l for l in stA.split('\n') if l.startswith('checks')][:1])

    # ---------------------------------------------------------------- B: structures
    out = rcon('body triggers structures')
    step('/body triggers structures answers', 'now structures' in out, out.split('\n')[0])
    st_out = rcon('body triggers status')
    step('status says structures', 'Physics triggers: structures' in st_out)
    bx, by, bz = ((px >> 4) + 1) * 16 + 1, py, pz + 70
    build_bridge(bx, by, bz)
    settle(6.0)
    step('structures: the bare bridge B holds (checked, nothing breaks)', deck_intact(bx, by, bz))
    placedB = load_iron(bx, by, bz)
    print('  bridge B: %d iron blocks placed by the bot' % placedB, flush=True)
    step('iron placed on bridge B (all 9, or until the deck gave way: %d)' % placedB, placedB >= 2)
    seen_body = False
    gone = False
    for k in range(120):
        settle(0.5)
        gone = gone or (not deck_intact(bx, by, bz))
        if k % 4 == 0:
            lst = rcon('body list')
            if lst and 'No bodies' not in lst:
                seen_body = True
        if gone and seen_body:
            break
    n = created()
    step('structures: a deck block disappeared on the client', gone)
    step('structures: a body was created (created %d)' % n, n >= 1)
    stB = rcon('body triggers status')
    step('structures: the trigger started a check', not any(l.startswith('checks 0') for l in stB.split('\n')), [l for l in stB.split('\n') if l.startswith('checks')][:1])
    cmd('tp %s %d %d %d' % (NAME, ax + 6, ay + 6, az + 3))
    settle(8.0)
    wait(lambda: w.block(ax + 6, ay + 4, az) is not None, 'chunk of bridge A', 30.0)
    step('structures: bridge A (outside the 48 block reach, started under off) is unchanged', deck_intact(ax, ay, az), str(deck_states(ax, ay, az)))
    lst = rcon('body list')
    print('  final body list: %s' % lst.replace('\n', ' | '), flush=True)
    rcon('body triggers off')
    step('/body triggers off switches back', 'Physics triggers: off' in rcon('body triggers status'))
    rc.close()
    print('RESULT %d/%d passed' % (sum(results), len(results)), flush=True)
    if not all(results):
        raise m.Fail('trigger scenario had failing steps')


fake = types.ModuleType('mcbot_c1')
fake.c1_session = session
fake.c1_verify_session = session
sys.modules['mcbot_c1'] = fake

if __name__ == '__main__':
    for i, a in enumerate(sys.argv):
        if a == '--rcon-port':
            RCON_PORT = int(sys.argv[i + 1])
            del sys.argv[i:i + 2]
            break
    for i, a in enumerate(sys.argv):
        if a == '--name':
            NAME = sys.argv[i + 1]
            break
    sys.argv.append('--c1')
    mcbot.main()
