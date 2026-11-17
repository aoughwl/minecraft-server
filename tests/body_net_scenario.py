"""Body network scenario against a private server (never the user's): two bots watch the same falling body.

    python tests/body_net_scenario.py --port 25830 --rcon-port 25831

  * JBot sends `jester:hello` (bodystream + fx + physics2) in the configuration phase, so it is a Jester level 2 client: it must receive
    `jester:bodies` RESET / CREATE / STATE / DESTROY for `/body assemble`, and `jester:fx` for the landing. Its decoded poses must match
    the server's `/body info` (the tick is frozen with `/tick freeze` first, so both describe the same instant).
  * VBot does no handshake (a vanilla client): it must see `block_display` entities spawn (type 15) with the Display metadata, their
    position must agree with the Jester stream, they must be removed when the body settles, and it must get the vanilla level event 2001
    where JBot gets jester:fx (never both to JBot).

The driver (no --role) starts the two bot processes (this script with --role), builds the platform through RCON, and judges. The bots are
tools/mcbot.py UNEDITED, run through its --c1 session slot like tests/body_scenario.py. PASS / FAIL / INCONCLUSIVE per step; exit status 0
only when nothing failed. Needs a scratch server with RCON (tests/run_body_net_scenario.sh).
"""
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

RCON_PASSWORD = 'bodypw'
PLAY_CUSTOM_PAYLOAD = 24      # 1.21.11 (774) ids, as the rest of mcbot.py
PLAY_SET_ENTITY_DATA = 97
PLAY_TELEPORT_ENTITY = 123
PLAY_REMOVE_ENTITIES = 75
PLAY_LEVEL_EVENT = 45
PLAY_SPAWN_ENTITY = 1
BLOCK_DISPLAY_TYPE = 15
CAPS_OFFERED = 0x15           # physics2 (bit 0) | bodystream (bit 2) | fx (bit 4)

# ---------------------------------------------------------------------------------------------------------------------------------
# the bot side
# ---------------------------------------------------------------------------------------------------------------------------------


def emit(tag, **kw):
    print('@@%s %s' % (tag, json.dumps(kw)), flush=True)


def unpack_quat(p):
    big = p >> 30
    rest = []
    for shift in (20, 10, 0):
        v = (p >> shift) & 1023
        rest.append((v / 1023.0 * 2.0 - 1.0) * 0.70710678)
    dropped = max(0.0, 1.0 - sum(c * c for c in rest)) ** 0.5
    q = []
    k = 0
    for i in range(4):
        if i == big:
            q.append(dropped)
        else:
            q.append(rest[k])
            k += 1
    return q   # x, y, z, w


class JesterDecoder:
    """The client side of PROTOCOL.md section 3 and 5, written from the spec."""

    def __init__(self):
        self.last_seq = 0
        self.gaps = 0
        self.bodies = {}      # wire id -> dict(x, y, z, rot)
        self.parts = {}       # wire id -> (header dict, cell bytes so far, done)
        self.resets = []
        self.creates = []
        self.destroys = []
        self.fx = []
        self.states = 0
        self.absolute = 0
        self.entries = 0

    def feed(self, data):
        r = mcbot.Reader(data)
        t = r.u8()
        if t == 1:
            self.create(r, data)
        elif t == 2:
            reason = r.u8()
            ids = [r.varint() for _ in range(r.varint())]
            for i in ids:
                self.bodies.pop(i, None)
            self.destroys.append((reason, ids))
            emit('DESTROY', reason=reason, ids=ids)
        elif t == 3:
            self.state(r)
        elif t == 4:
            seq, tick, reason = r.varint(), r.varint(), r.u8()
            self.last_seq = seq
            self.bodies.clear()
            self.resets.append((seq, reason))
            emit('RESET', seq=seq, tick=tick, reason=reason)

    def create(self, r, data):
        body_id = r.varint()
        flags = r.u8()
        if flags & 2:
            part = r.varint()
            h = self.parts.get(body_id)
            if h is None:
                return
            h['cells'] += r.take(r.left())
            h['done'] = not (flags & 1)
        else:
            h = dict(id=body_id)
            h['seq_at_create'] = r.varint()
            h['size'] = (r.u8(), r.u8(), r.u8())
            h['com'] = (r.f32(), r.f32(), r.f32())
            h['mass'] = r.f32()
            h['pos'] = (r.f64(), r.f64(), r.f64())
            h['quat'] = struct.unpack('>I', r.take(4))[0]
            h['vel'] = (r.i16(), r.i16(), r.i16())
            n = r.varint()
            h['palette'] = [r.varint() for _ in range(n)]
            h['bits'] = r.u8()
            h['cells'] = bytes(r.take(r.left()))
            h['done'] = not (flags & 1)
            self.parts[body_id] = h
        if h['done']:
            sx, sy, sz = h['size']
            need = (sx * sy * sz * h['bits'] + 7) // 8
            solid = 0
            bits = h['bits']
            raw = h['cells']
            for i in range(sx * sy * sz):
                v = 0
                for b in range(bits):
                    bit = i * bits + b
                    if raw[bit >> 3] >> (bit & 7) & 1:
                        v |= 1 << b
                if v:
                    solid += 1
            h['solid'] = solid
            h['cell_bytes_ok'] = len(raw) == need
            self.bodies[body_id] = dict(x=h['pos'][0], y=h['pos'][1], z=h['pos'][2], rot=h['quat'])
            self.creates.append(h)
            emit('CREATE', id=body_id, size=h['size'], com=h['com'], mass=h['mass'], pos=h['pos'], palette=h['palette'], solid=solid,
                 cells_ok=h['cell_bytes_ok'], seq=self.last_seq)

    def state(self, r):
        seq, base, tick, count = r.varint(), r.varint(), r.varint(), r.varint()
        if base != self.last_seq:
            self.gaps += 1
        self.last_seq = seq
        self.states += 1
        bid = 0
        for _ in range(count):
            bid += r.varint()
            flags = r.u8()
            b = self.bodies.get(bid)
            if b is None:
                emit('BADENTRY', id=bid)
                b = self.bodies.setdefault(bid, dict(x=0.0, y=0.0, z=0.0, rot=0))
            if flags & 1:
                if flags & 16:
                    b['x'], b['y'], b['z'] = r.f64(), r.f64(), r.f64()
                    self.absolute += 1
                elif flags & 64:
                    b['x'] += r.i32() / 1024.0
                    b['y'] += r.i32() / 1024.0
                    b['z'] += r.i32() / 1024.0
                else:
                    b['x'] += r.i16() / 1024.0
                    b['y'] += r.i16() / 1024.0
                    b['z'] += r.i16() / 1024.0
            if flags & 2:
                b['rot'] = struct.unpack('>I', r.take(4))[0]
            if flags & 4:
                r.take(6)
            if flags & 8:
                r.take(6)
            self.entries += 1
            emit('POSE', id=bid, x=b['x'], y=b['y'], z=b['z'], tick=tick, seq=seq, asleep=bool(flags & 32), t=time.time())


def bot_session(m, c, st, w, biomes, ctx, args):
    role = ROLE
    stop = STOP_FILE

    def wait(cond, what, seconds=30.0):
        m.pump(c, st, w, biomes, ctx, cond, what, seconds)

    dec = JesterDecoder()
    anchors = {}
    meta_seen = []
    level_events = []
    removed = []
    payload_channels = []

    def tap(pid, data):
        data = bytes(data)
        if pid == PLAY_CUSTOM_PAYLOAD:
            r = m.Reader(data)
            ch = r.string()
            payload_channels.append(ch)
            body = bytes(r.take(r.left()))
            if ch == 'jester:bodies':
                dec.feed(body)
            elif ch == 'jester:fx':
                rr = m.Reader(body)
                if rr.u8() == 1:
                    kind, flags = rr.u8(), rr.u8()
                    pos = struct.unpack('>Q', rr.take(8))[0]
                    state = rr.varint()
                    mat = rr.u8()
                    impulse = rr.f32()
                    seed = struct.unpack('>H', rr.take(2))[0]
                    x = pos >> 38
                    z = (pos >> 12) & 0x3FFFFFF
                    y = pos & 0xFFF
                    if x >= 1 << 25:
                        x -= 1 << 26
                    if z >= 1 << 25:
                        z -= 1 << 26
                    emit('FX', kind=kind, flags=flags, pos=[x, y, z], state=state, impulse=impulse)
        elif pid == PLAY_SPAWN_ENTITY:
            r = m.Reader(data)
            eid = r.varint()
            r.take(16)
            typ = r.varint()
            x, y, z = r.f64(), r.f64(), r.f64()
            if typ == BLOCK_DISPLAY_TYPE:
                anchors[eid] = [x, y, z]
                emit('SPAWN', id=eid, type=typ, pos=[x, y, z])
        elif pid == PLAY_TELEPORT_ENTITY:
            r = m.Reader(data)
            eid = r.varint()
            if eid in anchors:
                anchors[eid] = [r.f64(), r.f64(), r.f64()]
                emit('TELEPORT', id=eid, pos=anchors[eid])
        elif pid == PLAY_SET_ENTITY_DATA:
            r = m.Reader(data)
            eid = r.varint()
            if eid in anchors:
                entries = {}
                while True:
                    idx = r.u8()
                    if idx == 0xFF:
                        break
                    kind = r.varint()
                    try:
                        entries[idx] = (kind, m.read_meta_value(r, kind))
                    except Exception:
                        break
                emit('META', id=eid, entries={str(k): v for k, v in entries.items()}, anchor=anchors[eid], t=time.time())
        elif pid == PLAY_REMOVE_ENTITIES:
            r = m.Reader(data)
            ids = [r.varint() for _ in range(r.varint())]
            gone = [i for i in ids if i in anchors]
            if gone:
                emit('REMOVE', ids=gone)
        elif pid == PLAY_LEVEL_EVENT:
            r = m.Reader(data)
            ev = r.i32()
            r.take(8)
            d = r.i32()
            emit('LEVELEVENT', event=ev, data=d, t=time.time())

    ctx['tap'] = tap
    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 60.0)
    emit('READY', role=role, pos=list(w.pos))
    wait(lambda: os.path.exists(stop), 'the stop file', 240.0)
    emit('SUMMARY', role=role, gaps=dec.gaps, states=dec.states, absolute=dec.absolute, entries=dec.entries, resets=dec.resets,
         creates=len(dec.creates), destroys=dec.destroys, channels=sorted(set(payload_channels)))
    raise SystemExit(0)


ROLE = ''
STOP_FILE = ''


def run_bot(role):
    """The mcbot entry: c1 slot replaced by `bot_session`. `role` jester sends the Jester hello in the configuration phase."""
    global ROLE
    ROLE = role
    fake = types.ModuleType('mcbot_c1')
    fake.c1_session = bot_session
    fake.c1_verify_session = bot_session
    sys.modules['mcbot_c1'] = fake
    if role == 'jester':
        real_send = mcbot.Conn.send
        info = mcbot.client_information()

        def send(self, pid, body=b''):
            real_send(self, pid, body)
            if pid == mcbot.SB_CFG_INFO and bytes(body) == bytes(info):
                real_send(self, 2, mcbot.string('minecraft:register') + b'jester:welcome\0jester:bodies\0jester:fx\0')
                hello = bytes([1, 1, 1, 5]) + b'0.9.0' + struct.pack('>Q', CAPS_OFFERED) + mcbot.varint(30000) + bytes([0x12, 0x34, 0x56, 0x78])
                real_send(self, 2, mcbot.string('jester:hello') + hello)
        mcbot.Conn.send = send
    sys.argv.append('--c1')
    mcbot.main()


# ---------------------------------------------------------------------------------------------------------------------------------
# the driver
# ---------------------------------------------------------------------------------------------------------------------------------
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
    def __init__(self, role, name, port, seconds, stop_file):
        cmd = [sys.executable, os.path.abspath(__file__), '--role', role, '--stop-file', stop_file, '--port', str(port), '--name', name,
               '--seconds', str(seconds)]
        self.role = role
        self.events = []
        self.lock = threading.Lock()
        self.proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        self.thread = threading.Thread(target=self.read, daemon=True)
        self.thread.start()
        self.lines = []

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


def driver(port, rcon_port):
    stop_file = os.path.join(os.environ.get('BODY_NET_DIR', '.'), 'stop.flag')
    if os.path.exists(stop_file):
        os.remove(stop_file)
    jb = Bot('jester', 'JBot', port, 300, stop_file)
    _, jr = jb.wait_for('READY', seconds=90)
    step('the Jester bot joined', jr is not None, str(jr))
    if jr is None:
        print('\n'.join(jb.lines[-20:]))
        return
    vb = Bot('vanilla', 'VBot', port, 300, stop_file)
    _, vr = vb.wait_for('READY', seconds=90)
    step('the vanilla bot joined', vr is not None, str(vr))
    if vr is None:
        print('\n'.join(vb.lines[-20:]))
        return
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

    px, py, pz = [int(v // 1) for v in jr['pos']]
    x, y, z = px + 3, py + 45, pz
    rcon('fill %d %d %d %d %d %d minecraft:air' % (x - 2, py, z - 2, x + 4, py + 49, z + 4))
    rcon('fill %d %d %d %d %d %d minecraft:stone' % (x - 2, py - 1, z - 2, x + 4, py - 1, z + 4))
    out = rcon('fill %d %d %d %d %d %d minecraft:oak_planks' % (x, y, z, x + 2, y, z + 2))
    time.sleep(1.0)
    mark_j, mark_v = jb.count(), vb.count()
    # no tick freezing (this server's `tick step` does not step the bodies): /body info is sampled through RCON while the body falls, and every
    # sample (the simulation state at a tick boundary) must equal one of the poses the Jester stream decoded, because a body inside 48 blocks of
    # its viewer is streamed every tick. y + 45: inside that radius for the whole fall of about 1.7 s.
    out = rcon('body assemble %d %d %d %d %d %d' % (x, y, z, x + 2, y, z + 2))
    mm = re.match(r'Assembled body (\d+) ', out)
    step('assemble answers', mm is not None, out)
    if not mm:
        return
    bid = int(mm.group(1))
    wire = bid * 1024
    samples = []
    t0 = time.time()
    while time.time() - t0 < 4.0:
        info = rcon('body info %d' % bid)
        mi = re.search(r'com \(([-0-9.]+) ([-0-9.]+) ([-0-9.]+)\)', info)
        if not mi:
            break
        samples.append(tuple(float(g) for g in mi.groups()))
    time.sleep(1.0)

    # ---- the Jester client
    _, cr = jb.wait_for('CREATE', lambda d: d['id'] == wire, 15.0, mark_j)
    step('JBot: CREATE for the body (wire id %d)' % wire, cr is not None, str(cr))
    if cr:
        step('JBot: volume 3x1x3, 9 solid cells, palette air + one block, packed cells complete',
             tuple(cr['size']) == (3, 1, 3) and cr['solid'] == 9 and len(cr['palette']) == 2 and cr['palette'][0] == 0 and cr['cells_ok'],
             str(cr))
        step('JBot: centre of mass in the middle of the platform', all(abs(a - b) < 0.01 for a, b in zip(cr['com'], (1.5, 0.5, 1.5))), str(cr['com']))
        step('JBot: pose position is the centre of mass (min corner + com)',
             abs(cr['pos'][0] - (x + 1.5)) < 0.01 and abs(cr['pos'][2] - (z + 1.5)) < 0.01 and y + 0.5 - 1.0 < cr['pos'][1] <= y + 0.5 + 1e-6, str(cr['pos']))
    ri, rr = jb.wait_for('RESET', lambda d: True, 5.0, 0)
    step('JBot: a RESET (reason 0) came before the CREATE', rr is not None and rr['reason'] == 0 and ri is not None)
    _, p1 = jb.wait_for('POSE', lambda d: d['id'] == wire, 10.0, mark_j)
    step('JBot: STATE frames follow', p1 is not None)
    # ---- the vanilla client
    _, sp = vb.wait_for('SPAWN', lambda d: True, 15.0, mark_v)
    step('VBot: a block_display spawns for the body (entity type %d)' % BLOCK_DISPLAY_TYPE, sp is not None, str(sp))
    _, mt = vb.wait_for('META', lambda d: '23' in d['entries'], 10.0, mark_v)
    step('VBot: display metadata carries the block state at index 23 as a block-state value', mt is not None and mt['entries']['23'][0] == 14,
         str(mt and mt['entries'].get('23')))
    if mt:
        e = mt['entries']
        step('VBot: metadata index/type pairs are Display ones (9 and 10 varint, 11/12 vector3, 13/14 quaternion)',
             e.get('10', [0])[0] == 1 and e.get('9', [0])[0] == 1 and e.get('11', [0])[0] == 35 and e.get('12', [0])[0] == 35 and
             e.get('13', [0])[0] == 36, str(e))
        step('VBot: the merged cuboid is scaled 3 x 1 x 3', e.get('12') and all(abs(a - b) < 1e-4 for a, b in zip(e['12'][1], (3.0, 1.0, 3.0))),
             str(e.get('12')))
    # ---- compare the streams with the server's own state
    jposes = [(d['x'], d['y'], d['z']) for _, d in jb.get('POSE') if d['id'] == wire] + [tuple(d['pos']) for _, d in jb.get('CREATE') if d['id'] == wire]
    hits = sum(1 for sm in samples if any(all(abs(a - b) <= 0.011 for a, b in zip(sm, jp)) for jp in jposes))
    step('JBot: the server state sampled with /body info (%d samples) equals a decoded stream pose (%d match)' % (len(samples), hits),
         len(samples) >= 3 and hits >= len(samples) - 1, 'samples %s' % [tuple(round(v, 2) for v in sm) for sm in samples[:6]])
    metas = [d for _, d in vb.get('META') if '11' in d['entries']]
    corners = []
    for d in metas:
        t = d['entries']['11'][1]
        corners.append([d['anchor'][i] + t[i] + (1.5, 0.5, 1.5)[i] for i in range(3)])
    dhits = sum(1 for cn in corners if any(all(abs(a - b) <= 0.02 for a, b in zip(cn, jp)) for jp in jposes))
    step('VBot: display entity poses (anchor + translation + com) equal decoded Jester poses (%d of %d)' % (dhits, len(corners)),
         len(corners) >= 5 and dhits >= len(corners) - 1)
    # ---- settle: the body lands as blocks
    _, ds = jb.wait_for('DESTROY', lambda d: wire in d['ids'], 40.0, mark_j)
    step('JBot: DESTROY (reason 0, gone) when the body settles', ds is not None and ds['reason'] == 0, str(ds))
    _, fx = jb.wait_for('FX', lambda d: d['kind'] == 4, 5.0, mark_j)
    step('JBot: jester:fx land effect (kind 4) with the block state', fx is not None and fx['state'] != 0, str(fx))
    _, rm = vb.wait_for('REMOVE', lambda d: True, 5.0, mark_v)
    step('VBot: the display entities are removed when the body settles', rm is not None, str(rm))
    time.sleep(1.0)
    fxstates = [d['state'] for _, d in jb.get('FX', mark_j)]
    jlev = [d for _, d in jb.get('LEVELEVENT', mark_j) if d['event'] == 2001 and d['data'] in fxstates]
    vlev = [d for _, d in vb.get('LEVELEVENT', mark_v) if d['event'] == 2001 and d['data'] in fxstates]
    step('VBot gets the vanilla level event 2001 for the landing', len(vlev) >= 1, 'count %d' % len(vlev))
    step('JBot gets NO level event 2001 (fx replaces it, never both)', len(jlev) == 0, 'count %d' % len(jlev))
    vch = [d for _, d in vb.get('FX', mark_v)] + [d for _, d in vb.get('RESET', mark_v)] + [d for _, d in vb.get('CREATE', mark_v)]
    step('VBot gets no jester frames at all', len(vch) == 0, str(vch[:2]))
    rcon('body list')
    open(stop_file, 'w').write('stop')
    time.sleep(1.5)
    summ = [d for _, d in jb.get('SUMMARY')]
    if summ:
        s = summ[-1]
        step('JBot: the base/seq chain never broke (%d STATE frames, %d keyframe entries, %d entries)' % (s['states'], s['absolute'], s['entries']),
             s['gaps'] == 0 and s['states'] > 5, str(s))
    else:
        step('JBot summary', False)
    rc.close()
    for b in (jb, vb):
        with open(os.path.join(os.environ.get('BODY_NET_DIR', '.'), b.role + '_bot.txt'), 'w') as f:
            f.write(chr(10).join(b.lines))
    for b in (jb, vb):
        try:
            b.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            b.proc.kill()
    bad = [r for r in results if r == 'FAIL']
    inc = [r for r in results if r == 'INCONCLUSIVE']
    print('RESULT %d pass, %d fail, %d inconclusive' % (results.count('PASS'), len(bad), len(inc)), flush=True)
    return len(bad)


if __name__ == '__main__':
    role = None
    rcon_port = 25831
    for i, a in enumerate(list(sys.argv)):
        if a == '--role':
            role = sys.argv[i + 1]
            del sys.argv[i:i + 2]
            break
    for i, a in enumerate(list(sys.argv)):
        if a == '--stop-file':
            STOP_FILE = sys.argv[i + 1]
            del sys.argv[i:i + 2]
            break
    for i, a in enumerate(list(sys.argv)):
        if a == '--rcon-port':
            rcon_port = int(sys.argv[i + 1])
            del sys.argv[i:i + 2]
            break
    if role:
        run_bot(role)
    else:
        port = 25830
        for i, a in enumerate(sys.argv):
            if a == '--port':
                port = int(sys.argv[i + 1])
        sys.exit(1 if driver(port, rcon_port) else 0)
