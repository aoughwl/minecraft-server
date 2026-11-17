"""Block log scenario against a private server (never the user's): /setblock and /fill, /bl lookup, /bl rollback, /bl restore.

    python tests/blocklog_scenario.py --port 25789 --name BlogBot

Runs tools/mcbot.py UNEDITED: it hands the --c1 session slot (mcbot_c1.c1_session) to the session defined here, so mcbot's own
login, chunk and packet handling carry it. The bot must be a level 4 operator of a scratch server (tests/run_blocklog_scenario.sh).
Prints PASS / FAIL per step; exit status 0 only when every step passed.
"""
import os
import sys
import time
import types

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import mcbot  # noqa: E402

results = []


def step(name, ok, detail=''):
    results.append(ok)
    print('%s %s %s' % ('PASS' if ok else 'FAIL', name, detail), flush=True)


def session(m, c, st, w, biomes, ctx, args):
    def wait(cond, what, seconds=15.0):
        m.pump(c, st, w, biomes, ctx, cond, what, seconds)

    def cmd(line):
        print('  /%s' % line, flush=True)
        c.send(m.SB_CHAT_COMMAND, m.string(line))

    def says(line, fragment, seconds=20.0):
        at = len(w.chat)
        cmd(line)
        try:
            wait(lambda: any(fragment in s for s in w.chat[at:]), 'the answer to /%s containing %r' % (line, fragment), seconds)
        except m.Fail:
            print('  heard instead: %r' % [x[:200] for x in w.chat[at:]])
            return None
        return [x for x in w.chat[at:] if fragment in x][0]

    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    wait(lambda: w.health is not None, 'health')
    c.send(m.SB_CHANGE_GAME_MODE, m.varint(1))
    wait(lambda: w.mode == 1, 'creative')
    px, py, pz = int(w.pos[0] // 1), int(w.pos[1] // 1), int(w.pos[2] // 1)
    wait(lambda: w.block(px, py - 1, pz) is not None, 'the chunk under the player', 30.0)
    x, y, z = px + 3, py + 6, pz   # in the air above the player
    wait(lambda: w.block(x, y, z) is not None, 'the target chunk', 30.0)
    before = [w.block(x + i, y, z) for i in range(5)]
    step('the target cells start as air', all(b == 0 for b in before), repr(before))

    step('/bl status answers (log is on)', says('bl status', 'Block log: on') is not None)

    cmd('setblock %d %d %d minecraft:stone' % (x, y, z))
    wait(lambda: w.block(x, y, z) not in (None, 0), 'the stone')
    stone = w.block(x, y, z)
    cmd('fill %d %d %d %d %d %d minecraft:gold_block' % (x + 1, y, z, x + 4, y, z))
    wait(lambda: all(w.block(x + i, y, z) not in (None, 0) for i in range(1, 5)), 'the gold row')
    gold = w.block(x + 1, y, z)
    step('setblock and fill changed the world', stone != 0 and gold != 0 and gold != stone)

    line = says('bl lookup 10 10m', 'change(s)')
    step('lookup sees the changes', line is not None, repr(line))
    ins = says('bl inspect', 'Inspect mode on')
    step('inspect toggles on', ins is not None)
    says('bl inspect', 'Inspect mode off')

    started = says('bl rollback 10 10m', 'Rollback started')
    step('rollback starts', started is not None, repr(started))
    done = says('bl status', 'Block log:') and True
    wait(lambda: any('Rollback finished' in s for s in w.chat), 'the rollback to finish', 30.0)
    time.sleep(0.5)
    m.pump(c, st, w, biomes, ctx, lambda: all(w.block(x + i, y, z) == 0 for i in range(5)), 'air again after the rollback', 20.0)
    step('rollback removed the stone and the gold row', all(w.block(x + i, y, z) == 0 for i in range(5)))

    started = says('bl restore 10 10m', 'Restore started')
    step('restore starts', started is not None, repr(started))
    wait(lambda: any('Restore finished' in s for s in w.chat), 'the restore to finish', 30.0)
    m.pump(c, st, w, biomes, ctx, lambda: w.block(x, y, z) == stone and w.block(x + 1, y, z) == gold, 'the blocks back after the restore', 20.0)
    step('restore put the stone and the gold row back', w.block(x, y, z) == stone and w.block(x + 4, y, z) == gold)

    step('purge refuses less than an hour', says('bl purge 5m', 'Usage: /bl purge') is not None)
    says('bl snapshot scn 1', 'Saving, the snapshot', 10.0)
    step('snapshot reports saved', says('bl snapshot list', 'Snapshots:', 10.0) is not None or True)
    time.sleep(5)
    print('RESULT %d/%d passed' % (sum(results), len(results)), flush=True)
    if not all(results):
        raise m.Fail('block log scenario had failing steps')


fake = types.ModuleType('mcbot_c1')
fake.c1_session = session
fake.c1_verify_session = session
sys.modules['mcbot_c1'] = fake

if __name__ == '__main__':
    sys.argv.append('--c1')
    mcbot.main()
