"""Light-update storm check on a PRIVATE server (tests/run_lightupdate_scenario.sh runs it after the scenario, same server): the bot flies
over fresh terrain so chunks generate around it, and the light updates (0x2F) it receives are counted per second and per chunk.
A storm is more than one light update for one chunk within a tick (50 ms) or a rate that scales with the chunk count. Reports the numbers.

    python tests/lightupdate_storm.py --port 25890 --name LightBot --seconds 120 --commands --op
"""
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import mcbot  # noqa: E402

LU = int(os.environ.get('LU_PACKET_ID', '47'))
CHUNK = int(os.environ.get('LU_CHUNK_ID', '44'))   # level_chunk_with_light on 774
EV = []   # (time, pid, (cx, cz) or None)


def tap(pid, data):
    now = time.time()
    if pid == LU:
        r = mcbot.Reader(data)
        EV.append((now, pid, (r.varint(), r.varint())))
    elif pid == CHUNK:
        r = mcbot.Reader(data)
        EV.append((now, pid, (r.i32(), r.i32())))


def session(c, st, w, biomes, ctx, args):
    ctx['tap'] = tap

    def settle(sec):
        end = time.time() + sec
        while time.time() < end:
            try:
                pid, r = c.recv()
            except Exception:
                continue
            mcbot.one_packet(c, st, w, biomes, ctx, pid, r)

    mcbot.pump(c, st, w, biomes, ctx, lambda: w.pos is not None and ctx['chunk_parsed'], 'pos+chunk', 40.0)
    settle(3.0)
    c.send(mcbot.SB_CHAT_COMMAND, mcbot.string('gamemode creative'))
    settle(0.5)
    x0, y, z0 = w.pos
    t_start = time.time()
    for step in range(1, 13):   # 12 hops of 64 blocks: fresh chunks every hop
        c.send(mcbot.SB_CHAT_COMMAND, mcbot.string('tp %s %f %f %f' % (args.name, x0 + 64.0 * step * 3, y + 20, z0 + 64.0 * step * 3)))
        settle(6.0)
    dur = time.time() - t_start
    lus = [e for e in EV if e[1] == LU and e[0] >= t_start]
    chunks = [e for e in EV if e[1] == CHUNK and e[0] >= t_start]
    per_chunk = {}
    for e in lus:
        per_chunk.setdefault(e[2], []).append(e[0])
    worst_tick = 0
    for ts in per_chunk.values():
        ts.sort()
        for i in range(len(ts)):
            n = sum(1 for t in ts if ts[i] <= t < ts[i] + 0.05)
            worst_tick = max(worst_tick, n)
    per_sec = {}
    for e in lus:
        per_sec[int(e[0] - t_start)] = per_sec.get(int(e[0] - t_start), 0) + 1
    print('STORM chunks_received=%d light_updates=%d distinct_light_chunks=%d max_per_chunk=%d worst_per_chunk_in_50ms=%d '
          'max_per_second=%d duration=%.0fs' % (len(chunks), len(lus), len(per_chunk), max([len(v) for v in per_chunk.values()] or [0]),
                                                 worst_tick, max(per_sec.values() or [0]), dur), flush=True)
    ok = worst_tick <= 1 and len(lus) <= max(8, len(chunks))
    print('RESULT %s' % ('PASS' if ok else 'FAIL'), flush=True)
    c.close()
    raise SystemExit(0 if ok else 1)


mcbot.commands_session = session
if __name__ == '__main__':
    for a in ('--commands', '--op'):
        if a not in sys.argv:
            sys.argv.append(a)
    mcbot.main()
