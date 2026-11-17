"""Replay scenario against a private server (never the user's): record a body fall, stop, list, export, play it back to a bot, restore.

    python tests/replay_scenario.py --port 25850 --rcon-port 25851

One vanilla bot (no Jester handshake, an operator) joins. RCON builds a 3x1x3 oak platform 45 blocks above the floor. The bot types
`/replay record fall1 ...`, RCON runs `body assemble` (the platform falls and settles), the bot stops the recording and lists and exports
it, then `/replay play fall1`: the bot must receive block_display entities for the body (spawn, metadata, teleports) and fake block updates
(single and section packets), must be switched to spectator, and RCON must see that the REAL blocks never changed during the playback.
`/replay pause`, `seek`, `speed` are exercised. `/replay stop` must remove the entities, resend the real block states and put the game
mode back. PASS / FAIL / INCONCLUSIVE per step; exit status 0 only when nothing failed.
Bot = tools/mcbot.py UNEDITED through its --c1 session slot, like tests/body_net_scenario.py.
"""
import glob
import json
import os
import re
import socket
import struct
import subprocess
import sys
import threading
import time
import types

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import mcbot  # noqa: E402

RCON_PASSWORD = 'replaypw'
PLAY_CUSTOM_PAYLOAD = 24
PLAY_SET_ENTITY_DATA = 97
PLAY_TELEPORT_ENTITY = 123
PLAY_REMOVE_ENTITIES = 75
PLAY_SPAWN_ENTITY = 1
PLAY_BLOCK_UPDATE = 8
PLAY_SECTION_UPDATE = 82
PLAY_LEVEL_EVENT = 45
BLOCK_DISPLAY_TYPE = 15


def emit(tag, **kw):
    print('@@%s %s' % (tag, json.dumps(kw)), flush=True)


ROLE = ''
STOP_FILE = ''
CMD_FILE = ''


def bot_session(m, c, st, w, biomes, ctx, args):
    disp = set()
    cnt = dict(dmeta=0, bu=0, su=0, su_cells=0, spawn=0, meta=0, tele=0, remove=0, level=0, jester=0)
    blocks = {}                 # (x, y, z) -> latest state from update packets
    history = {}                # watched cell -> list of states seen in updates
    watched = set()
    chat_at = [0]
    cmd_at = [0]

    def note(pos, state):
        blocks[pos] = state
        if pos in watched:
            history.setdefault(pos, []).append(state)

    def tap(pid, data):
        data = bytes(data)
        r = m.Reader(data)
        if pid == PLAY_CUSTOM_PAYLOAD:
            if r.string().startswith('jester:'):
                cnt['jester'] += 1
        elif pid == PLAY_BLOCK_UPDATE:
            x, y, z = mcbot.read_block_pos(r)
            cnt['bu'] += 1
            note((x, y, z), r.varint())
        elif pid == PLAY_SECTION_UPDATE:
            section = struct.unpack('>Q', r.take(8))[0]
            sx, sz, sy = section >> 42, (section >> 20) & 0x3FFFFF, section & 0xFFFFF
            if sx >= 1 << 21:
                sx -= 1 << 22
            if sz >= 1 << 21:
                sz -= 1 << 22
            if sy >= 1 << 19:
                sy -= 1 << 20
            cnt['su'] += 1
            for _ in range(r.varint()):
                v = 0
                for shift in range(0, 70, 7):
                    b = r.u8()
                    v |= (b & 0x7F) << shift
                    if not b & 0x80:
                        break
                rel = v & 0xFFF
                cnt['su_cells'] += 1
                note((sx * 16 + (rel >> 8), sy * 16 + (rel & 15), sz * 16 + ((rel >> 4) & 15)), v >> 12)
        elif pid == PLAY_SPAWN_ENTITY:
            eid = r.varint()
            r.take(16)
            typ = r.varint()
            cnt['spawn'] += 1
            if typ == BLOCK_DISPLAY_TYPE:
                disp.add(eid)
                cnt.setdefault('spawn_display', 0)
                cnt['spawn_display'] += 1
        elif pid == PLAY_SET_ENTITY_DATA:
            cnt['meta'] += 1
            if r.varint() in disp:
                cnt['dmeta'] += 1
        elif pid == PLAY_TELEPORT_ENTITY:
            cnt['tele'] += 1
        elif pid == PLAY_REMOVE_ENTITIES:
            cnt['remove'] += 1
        elif pid == PLAY_LEVEL_EVENT:
            cnt['level'] += 1

    ctx['tap'] = tap

    def cur(x, y, z):
        if (x, y, z) in blocks:
            return blocks[(x, y, z)]
        return w.block(x, y, z)

    def pump_cmds():
        while chat_at[0] < len(w.chat):
            emit('CHAT', text=w.chat[chat_at[0]])
            chat_at[0] += 1
        if os.path.exists(CMD_FILE):
            with open(CMD_FILE) as f:
                lines = f.read().splitlines()
            while cmd_at[0] < len(lines):
                line = lines[cmd_at[0]]
                cmd_at[0] += 1
                if line.startswith('say '):
                    c.send(m.SB_CHAT_COMMAND, m.string(line[4:]))
                elif line.startswith('watch '):
                    p = tuple(int(v) for v in line.split()[1:4])
                    watched.add(p)
                    history[p] = []
                elif line.startswith('probe '):
                    p = tuple(int(v) for v in line.split()[1:4])
                    emit('PROBE', pos=list(p), state=cur(*p), history=history.get(p, []), mode=w.mode)
                elif line == 'snap':
                    emit('SNAP', counters=dict(cnt), mode=w.mode, history={'%d,%d,%d' % k: v for k, v in history.items()})
        return os.path.exists(STOP_FILE)

    def wait(cond, what, seconds=30.0):
        m.pump(c, st, w, biomes, ctx, cond, what, seconds)

    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 90.0)
    emit('READY', pos=list(w.pos), mode=w.mode)
    wait(pump_cmds, 'the stop file', 400.0)
    emit('SUMMARY', counters=dict(cnt), mode=w.mode)
    raise SystemExit(0)


def run_bot():
    fake = types.ModuleType('mcbot_c1')
    fake.c1_session = bot_session
    fake.c1_verify_session = bot_session
    sys.modules['mcbot_c1'] = fake
    sys.argv.append('--c1')
    mcbot.main()


results = []


def step(name, ok, detail='', inconclusive=False):
    tag = 'INCONCLUSIVE' if inconclusive else ('PASS' if ok else 'FAIL')
    results.append(tag)
    print('%s %s %s' % (tag, name, detail), flush=True)


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


class Bot:
    def __init__(self, name, port, seconds, stop_file, cmd_file):
        cmd = [sys.executable, os.path.abspath(__file__), '--role', 'bot', '--stop-file', stop_file, '--cmd-file', cmd_file,
               '--port', str(port), '--name', name, '--seconds', str(seconds)]
        self.events = []
        self.lines = []
        self.lock = threading.Lock()
        self.cmd_file = cmd_file
        self.proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        self.thread = threading.Thread(target=self.read, daemon=True)
        self.thread.start()

    def read(self):
        for line in self.proc.stdout:
            line = line.rstrip('\n')
            self.lines.append(line)
            if line.startswith('@@'):
                tag, _, payload = line[2:].partition(' ')
                try:
                    data = json.loads(payload)
                except ValueError:
                    continue
                with self.lock:
                    self.events.append((tag, data))

    def get(self, tag, since=0):
        with self.lock:
            return [(i, d) for i, (t, d) in enumerate(self.events) if t == tag and i >= since]

    def count(self):
        with self.lock:
            return len(self.events)

    def wait_for(self, tag, cond=lambda d: True, seconds=30.0, since=0):
        end = time.time() + seconds
        while time.time() < end:
            for i, d in self.get(tag, since):
                if cond(d):
                    return i, d
            if self.proc.poll() is not None:
                break
            time.sleep(0.1)
        return None, None

    def send(self, line):
        with open(self.cmd_file, 'a') as f:
            f.write(line + '\n')

    def chat_since(self, mark):
        return [d['text'] for _, d in self.get('CHAT', mark)]

    def say(self, command, expect=None, seconds=20.0):
        """Types a command; returns (chat lines, mark). Waits for a chat line containing `expect` (any new line when None)."""
        mark = self.count()
        self.send('say ' + command)
        end = time.time() + seconds
        while time.time() < end:
            lines = self.chat_since(mark)
            if lines and (expect is None or any(expect in l for l in lines)):
                time.sleep(0.3)
                return self.chat_since(mark), mark
            time.sleep(0.1)
        return self.chat_since(mark), mark

    def snap(self):
        mark = self.count()
        self.send('snap')
        _, d = self.wait_for('SNAP', seconds=10.0, since=mark)
        return d

    def probe(self, x, y, z):
        mark = self.count()
        self.send('probe %d %d %d' % (x, y, z))
        _, d = self.wait_for('PROBE', seconds=10.0, since=mark)
        return d


def driver(port, rcon_port):
    run_dir = os.environ.get('REPLAY_DIR', '.')
    stop_file = os.path.join(run_dir, 'stop.flag')
    cmd_file = os.path.join(run_dir, 'cmds.txt')
    for f in (stop_file, cmd_file):
        if os.path.exists(f):
            os.remove(f)
    bot = Bot('RBot', port, 400, stop_file, cmd_file)
    _, rd = bot.wait_for('READY', seconds=120)
    step('the bot joined', rd is not None, str(rd))
    if rd is None:
        print('\n'.join(bot.lines[-20:]))
        return 1
    orig_mode = rd['mode']
    rc = socket.create_connection(('127.0.0.1', rcon_port), timeout=10)
    rc.sendall(mcbot.rcon_packet(1, 3, RCON_PASSWORD))
    pid, _, _ = mcbot.rcon_read(rc)
    step('RCON login', pid == 1)
    ident = [10]

    def rcon(line):
        ident[0] += 1
        out = rcon_cmd(rc, ident[0], line)
        print('  rcon %s -> %s' % (line, out.replace('\n', ' | ')), flush=True)
        return out

    px, py, pz = [int(v // 1) for v in rd['pos']]
    x, y, z = px + 3, py + 45, pz
    top = (x + 1, y, z + 1)
    land = (x + 1, py, z + 1)
    rcon('fill %d %d %d %d %d %d minecraft:air' % (x - 2, py, z - 2, x + 4, py + 49, z + 4))
    rcon('fill %d %d %d %d %d %d minecraft:stone' % (x - 2, py - 1, z - 2, x + 4, py - 1, z + 4))
    rcon('fill %d %d %d %d %d %d minecraft:oak_planks' % (x, y, z, x + 2, y, z + 2))
    time.sleep(1.5)
    bot.send('watch %d %d %d' % top)
    bot.send('watch %d %d %d' % land)
    p0 = bot.probe(*top)
    planks = p0['state'] if p0 else None
    step('the bot sees the platform in the air (state %s)' % planks, p0 is not None and planks not in (None, 0), str(p0))
    # ---- record
    radius = 32
    lines = []
    for attempt in range(8):
        lines, _ = bot.say('replay record fall1 %d 30' % radius, None, 20)
        if any("Recording 'fall1'" in l for l in lines):
            break
        print('  record attempt %d: %s' % (attempt, lines), flush=True)
        time.sleep(6)
    step('/replay record answers', any("Recording 'fall1'" in l for l in lines), str(lines))
    if not any("Recording 'fall1'" in l for l in lines):
        open(stop_file, 'w').write('stop')
        return 1
    st_lines, _ = bot.say('replay status', 'Recording', 10)
    step('/replay status while recording', any("Recording 'fall1'" in l for l in st_lines), str(st_lines))
    time.sleep(0.6)
    out = rcon('body assemble %d %d %d %d %d %d' % (x, y, z, x + 2, y, z + 2))
    step('assemble answers', 'Assembled body' in out, out)
    time.sleep(10.0)
    # ---- stop, list, export
    stop_lines, _ = bot.say('replay stop', 'saved', 15)
    saved = [l for l in stop_lines if 'saved' in l]
    step('/replay stop saves the recording', bool(saved), str(stop_lines))
    m_ = re.search(r'saved: (\d+) bytes, (\d+) s, (\d+) records \((\d+) bytes/s\)', ' '.join(saved))
    size = int(m_.group(1)) if m_ else 0
    secs = int(m_.group(2)) if m_ else 0
    print('INFO recording: %s' % (m_.group(0) if m_ else saved), flush=True)
    list_lines, _ = bot.say('replay list', 'fall1', 10)
    step('/replay list shows fall1', any('fall1' in l for l in list_lines), str(list_lines))
    files = glob.glob(os.path.join(run_dir, '**', 'replays', 'fall1.rpl'), recursive=True)
    disk = os.path.getsize(files[0]) if files else 0
    step('the file exists on disk and its size equals the reported size', bool(files) and disk == size, 'disk %d reported %d' % (disk, size))
    exp_lines, _ = bot.say('replay export fall1', 'Wrote', 15)
    jfiles = glob.glob(os.path.join(run_dir, '**', 'replays', 'fall1.json'), recursive=True)
    summary = {}
    if jfiles:
        with open(jfiles[0]) as f:
            summary = json.load(f)
    step('/replay export writes a JSON summary with the body timeline',
         bool(summary) and len(summary.get('bodies', [])) >= 1 and summary.get('blockChanges', 0) > 0 and summary.get('cleanStop') is True,
         'bodies %s blockChanges %s impacts %d fx %s duration %s s' % (len(summary.get('bodies', [])), summary.get('blockChanges'),
                                                                        len(summary.get('impacts', [])), summary.get('effects'),
                                                                        summary.get('durationSeconds')))
    if summary.get('bodies'):
        b0 = summary['bodies'][0]
        step('the recorded body: 9 cells, fell from about y+45 to the floor', b0['cells'] == 9 and b0['maxY'] - b0['minY'] > 30,
             json.dumps(b0))
    # ---- play
    before_top = bot.probe(*top)['state']
    before_land = bot.probe(*land)['state']
    snap0 = bot.snap()
    mark = bot.count()
    play_lines, _ = bot.say('replay play fall1 1', "Playing 'fall1'", 15)
    step('/replay play starts', any("Playing 'fall1'" in l for l in play_lines), str(play_lines))
    _, ready = bot.wait_for('CHAT', lambda d: 'ready:' in d['text'], 30.0, mark)
    step('the baseline is loaded ("ready")', ready is not None, str(ready))
    time.sleep(2.0)
    snap1 = bot.snap()
    c0, c1 = snap0['counters'], snap1['counters']
    step('the bot became a spectator (game mode %s -> %s)' % (orig_mode, snap1['mode']), snap1['mode'] == 3)
    step('fake block updates arrived (single %d, section %d with %d cells)' % (c1['bu'] - c0['bu'], c1['su'] - c0['su'], c1['su_cells'] - c0['su_cells']),
         (c1['bu'] - c0['bu']) + (c1['su'] - c0['su']) > 0)
    step('block_display entities were spawned for the body (%d)' % (c1.get('spawn_display', 0) - c0.get('spawn_display', 0)),
         c1.get('spawn_display', 0) - c0.get('spawn_display', 0) >= 1)
    step('display metadata and teleports were sent (meta %d)' % (c1['meta'] - c0['meta']), c1['meta'] - c0['meta'] >= 1)
    step('no jester:* payloads were sent to the vanilla bot', c1['jester'] == c0['jester'])
    # the REAL world must be untouched while the bot sees the recording
    # non-mutating probes: a fill that only replaces planks by planks tells what the real block is
    r_top = rcon('fill %d %d %d %d %d %d minecraft:stone replace minecraft:oak_planks' % (top + top))
    r_land = rcon('fill %d %d %d %d %d %d minecraft:oak_planks replace minecraft:oak_planks' % (land + land))
    step('RCON: the real world is unchanged during playback (top cell is not planks, landing cell is still planks)',
         (re.search('[1-9][0-9]* blocks? filled', r_top) is None) and (re.search('1 blocks? filled', r_land) is not None), '%r | %r' % (r_top, r_land))
    st_play, _ = bot.say('replay status', 'Replay', 10)
    step('/replay status while playing', any("Replay 'fall1'" in l for l in st_play), str(st_play))
    # pause / seek / speed
    pl, _ = bot.say('replay pause', 'Paused', 10)
    step('/replay pause', any('Paused' in l for l in pl), str(pl))
    s_a = bot.snap()['counters']
    time.sleep(1.5)
    s_b = bot.snap()['counters']
    step('paused: no new display updates (display meta %d -> %d)' % (s_a['dmeta'], s_b['dmeta']), s_b['dmeta'] == s_a['dmeta'] and s_b['tele'] == s_a['tele'])
    sk, _ = bot.say('replay seek 0', 'At 0', 10)
    step('/replay seek 0', any('At 0.0 s' in l for l in sk), str(sk))
    sp, _ = bot.say('replay speed 4', 'Speed', 10)
    step('/replay speed 4', any('Speed 4.00' in l for l in sp), str(sp))
    rs, _ = bot.say('replay resume', 'Playing', 10)
    step('/replay resume', any('Playing' in l for l in rs), str(rs))
    s_c = bot.snap()['counters']
    time.sleep(3.0)
    s_d = bot.snap()['counters']
    step('resumed: display updates flow again (display meta %d -> %d)' % (s_c['dmeta'], s_d['dmeta']), s_d['dmeta'] > s_c['dmeta'])
    time.sleep(4.0)
    fin, _ = bot.say('replay status', 'Replay', 10)
    step('playback reaches the end at speed 4', any('finished' in l for l in fin), str(fin))
    snap2 = bot.snap()
    h = snap2['history']
    ht = h.get('%d,%d,%d' % top, [])
    hl = h.get('%d,%d,%d' % land, [])
    step('the bot saw the platform appear at the top (planks %s) and the landing cells change' % planks,
         planks in ht and len(hl) >= 1, 'top history %s land history %s' % (ht, hl))
    # ---- stop
    mark_remove = snap2['counters']['remove']
    stp, _ = bot.say('replay stop', 'stopped', 15)
    step('/replay stop restores', any('stopped' in l and 'restored' in l for l in stp), str(stp))
    time.sleep(1.5)
    snap3 = bot.snap()
    step('display entities and fake entities were removed on stop', snap3['counters']['remove'] > mark_remove)
    step('the game mode is back (%s)' % snap3['mode'], snap3['mode'] == orig_mode)
    a_top = bot.probe(*top)['state']
    a_land = bot.probe(*land)['state']
    step('the bot sees the REAL blocks again (top %s == %s, landing %s == %s)' % (a_top, before_top, a_land, before_land),
         a_top == before_top and a_land == before_land)
    r_top2 = rcon('fill %d %d %d %d %d %d minecraft:stone replace minecraft:oak_planks' % (top + top))
    step('RCON: the real world is unchanged after the playback (top cell is not planks)', re.search('[1-9][0-9]* blocks? filled', r_top2) is None, r_top2)
    again, _ = bot.say('replay stop', None, 5)
    step('a second stop says nothing is running', any('Nothing' in l for l in again), str(again))
    print('INFO size per second of recording: %s bytes over %s s (about %s bytes/s, baseline radius %d included)' %
          (size, secs, size // max(1, secs), radius), flush=True)
    open(stop_file, 'w').write('stop')
    time.sleep(1.5)
    rc.close()
    with open(os.path.join(run_dir, 'bot.txt'), 'w') as f:
        f.write(chr(10).join(bot.lines))
    try:
        bot.proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        bot.proc.kill()
    bad = [r for r in results if r == 'FAIL']
    inc = [r for r in results if r == 'INCONCLUSIVE']
    print('RESULT %d pass, %d fail, %d inconclusive' % (results.count('PASS'), len(bad), len(inc)), flush=True)
    return len(bad)


if __name__ == '__main__':
    role = None
    rcon_port = 25851
    for flag in ('--role', '--stop-file', '--cmd-file', '--rcon-port'):
        for i, a in enumerate(list(sys.argv)):
            if a == flag:
                val = sys.argv[i + 1]
                del sys.argv[i:i + 2]
                if flag == '--role':
                    role = val
                elif flag == '--stop-file':
                    STOP_FILE = val
                elif flag == '--cmd-file':
                    CMD_FILE = val
                else:
                    rcon_port = int(val)
                break
    if role:
        run_bot()
    else:
        port = 25850
        for i, a in enumerate(sys.argv):
            if a == '--port':
                port = int(sys.argv[i + 1])
        sys.exit(1 if driver(port, rcon_port) else 0)
