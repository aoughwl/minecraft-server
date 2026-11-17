"""Body manager scenario against a private server (never the user's): a platform of planks is built in the air, `/body assemble`d (the
blocks vanish for the client), and watched falling through RCON `/body info` until it settles into blocks on the ground again.

    python tests/body_scenario.py --port 25811 --rcon-port 25812 --name BodyBot

Runs tools/mcbot.py UNEDITED through its --c1 session slot (like tests/blocklog_scenario.py). The bot must be a level 4 operator of a
scratch server with RCON enabled (tests/run_body_scenario.sh). PASS / FAIL per step; exit status 0 only when every step passed.
"""
import os
import re
import socket
import sys
import time
import types

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import mcbot  # noqa: E402

results = []
RCON_PORT = 25812
RCON_PASSWORD = 'bodypw'


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

    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    wait(lambda: w.health is not None, 'health')
    c.send(m.SB_CHANGE_GAME_MODE, m.varint(1))
    wait(lambda: w.mode == 1, 'creative')
    px, py, pz = int(w.pos[0] // 1), int(w.pos[1] // 1), int(w.pos[2] // 1)
    wait(lambda: w.block(px, py - 1, pz) is not None, 'the chunk under the player', 30.0)
    x, y, z = px + 3, py + 12, pz
    wait(lambda: w.block(x, y, z) is not None, 'the target chunk', 30.0)
    # a flat, clear patch under the platform: natural terrain would stop a falling slab tilted on a slope or in a tree
    cmd('fill %d %d %d %d %d %d minecraft:air' % (x - 2, py, z - 2, x + 4, py + 14, z + 4))
    cmd('fill %d %d %d %d %d %d minecraft:stone' % (x - 2, py - 1, z - 2, x + 4, py - 1, z + 4))
    wait(lambda: w.block(x, py, z) == 0 and w.block(x, py - 1, z) not in (None, 0), 'the flat patch', 20.0)
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

    step('/body status answers', 'Bodies:' in rcon('body status'))
    cmd('fill %d %d %d %d %d %d minecraft:oak_planks' % (x, y, z, x + 2, y, z + 2))
    wait(lambda: all(w.block(x + i, y, z + j) not in (None, 0) for i in range(3) for j in range(3)), 'the platform')
    planks = w.block(x, y, z)
    step('the platform stands in the air', planks != 0)
    out = rcon('body assemble %d %d %d %d %d %d' % (x, y, z, x + 2, y, z + 2))
    step('assemble answers', out.startswith('Assembled body'), out)
    m_id = re.match(r'Assembled body (\d+) ', out)
    bid = m_id.group(1) if m_id else '1'
    wait(lambda: all(w.block(x + i, y, z + j) == 0 for i in range(3) for j in range(3)), 'the platform to vanish for the client', 15.0)
    step('the blocks vanished on the client', all(w.block(x + i, y, z + j) == 0 for i in range(3) for j in range(3)))
    seen = []
    last = ''
    for k in range(80):
        info = rcon('body info %s' % bid)
        mm = re.search(r'com \(([-0-9.]+) ([-0-9.]+) ([-0-9.]+)\)', info)
        if mm:
            seen.append(float(mm.group(2)))
        last = info
        if info.startswith('No body'):
            break
        time.sleep(0.25)
    step('it fell (centre y %s -> %s)' % (seen[0] if seen else '?', seen[-1] if seen else '?'),
         len(seen) >= 2 and seen[-1] < seen[0] - 3.0)
    step('and then settled (the body is gone)', last.startswith('No body'), last)
    wait(lambda: any(w.block(x, yy, z) == planks for yy in range(y - 60, y)), 'the planks to come back below', 15.0)
    low = [yy for yy in range(y - 60, y) if w.block(x, yy, z) == planks]
    step('the planks are blocks again on the patch (y = %s, floor top y = %d)' % (low[0] if low else None, py), low == [py])
    n = sum(1 for i in range(3) for j in range(3) if low and w.block(x + i, low[0], z + j) == planks)
    step('all nine are back, identical', n == 9, 'found %d' % n)
    step('/body list is empty', 'No bodies' in rcon('body list'))
    rc.close()
    print('RESULT %d/%d passed' % (sum(results), len(results)), flush=True)
    if not all(results):
        raise m.Fail('body scenario had failing steps')


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
    sys.argv.append('--c1')
    mcbot.main()
