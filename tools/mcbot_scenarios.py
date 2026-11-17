"""Scenario runner for server mods: mcbot.py --scenario <name>[,<name>...|all] plays registered scenarios on one connection and
reports each as PASS, FAIL or INCONCLUSIVE.

    PASS          every check held
    FAIL          a check did not hold (the process exits non-zero)
    INCONCLUSIVE  the scenario could not test what it is about: a precondition is missing (the plugin it needs is not installed, the
                  server never sent the world), so it says nothing for or against the change. Never counted as a pass or a failure.

Run it with tools/run_scenarios.sh (a scratch server directory, the showcase plugins, a spare port). To add a scenario write a function
taking the helper `s` and register it:

    @scenario('my_case', needs_plugin='showcase')      # needs_plugin: the scenario needs the showcase plugins loaded
    def my_case(s):
        s.command('giveme minecraft:stone 3')
        s.expect('You now carry', 'the give notice')
        s.check(s.block(0, 63, 0) is not None, 'the column under the spawn was sent')

`s` offers: command, say, expect, heard, wait, check, inconclusive, block, setblock, send_payload, payloads (what the server sent on a
channel), wait_payload, position, chunks, config_payloads. Everything runs against the bot's world model (World in mcbot.py), so a
scenario reads what a real client would know: chunks, block updates, chat, payloads. Entity state is not modelled by the bot yet; a
scenario that needs it says so with s.inconclusive().
"""
import struct
import time

SCENARIOS = []      # (name, needs_plugin, function)


class Inconclusive(Exception):
    pass


def scenario(name, needs_plugin=None):
    def wrap(fn):
        SCENARIOS.append((name, needs_plugin, fn))
        return fn
    return wrap


class Scn:
    def __init__(self, m, c, st, w, biomes, ctx, args):
        self.m, self.c, self.st, self.w, self.biomes, self.ctx, self.args = m, c, st, w, biomes, ctx, args
        self.payload_log = []       # (channel, data) of play-phase custom payloads from the server
        self.started = time.time()
        prior = ctx.get('tap')

        def tap(pid, data):
            if prior:
                prior(pid, data)
            if pid == 24:           # clientbound custom_payload (play)
                r = m.Reader(data)
                self.payload_log.append((r.string(), bytes(data[r.at:])))
        ctx['tap'] = tap
        self.plugins = bool(args.scenario_plugins)

    # ---- waiting and checking
    def wait(self, cond, what, seconds=15.0):
        self.m.pump(self.c, self.st, self.w, self.biomes, self.ctx, cond, what, seconds)

    def check(self, cond, why):
        if not cond:
            raise self.m.Fail(why)

    def inconclusive(self, why):
        raise Inconclusive(why)

    # ---- chat and commands (the bot is an operator on the scratch server)
    def command(self, line):
        self.c.send(self.m.SB_CHAT_COMMAND, self.m.string(line))

    def say(self, message):
        self.c.send(self.m.SB_CHAT, self.m.string(message) + struct.pack('>qq', int(time.time() * 1000), 42) + bytes([0]) +
                    self.m.varint(0) + bytes([0, 0, 0]) + bytes([0]))

    def heard(self, fragment, since=0):
        return any(fragment in said for said in self.w.chat[since:])

    def expect(self, fragment, what, seconds=15.0, since=0):
        self.wait(lambda: self.heard(fragment, since), what, seconds)
        return [said for said in self.w.chat[since:] if fragment in said][0]

    # ---- the world as the client knows it
    def chunks(self):
        return len(self.w.chunks)

    def position(self):
        return self.w.pos

    def block(self, x, y, z):
        return self.w.block(x, y, z)

    def setblock(self, x, y, z, name, state, seconds=15.0):
        """Places a block with /setblock and waits until the client was told its state id is `state`."""
        self.command('setblock %d %d %d %s' % (x, y, z, name))
        self.wait(lambda: self.w.block(x, y, z) == state, 'the block at %d %d %d to become %s (state %d)' % (x, y, z, name, state), seconds)

    # ---- custom payloads
    def send_payload(self, channel, data=b'', phase='play'):
        self.c.send(21 if phase == 'play' else 2, self.m.string(channel) + bytes(data))

    def register(self, *channels):
        self.send_payload('minecraft:register', b''.join(ch.encode() + b'\x00' for ch in channels))

    def payloads(self, channel):
        return [d for ch, d in self.payload_log if ch == channel]

    def wait_payload(self, channel, what=None, seconds=15.0, since=0):
        self.wait(lambda: len(self.payloads(channel)) > since, what or ('a payload on ' + channel), seconds)
        return self.payloads(channel)[since:]

    def config_payloads(self, channel):
        return [d for ch, d in self.m.CONFIG_PAYLOADS if ch == channel]

    def require_plugin(self, which='showcase'):
        if not self.plugins:
            raise Inconclusive('the %s plugins are not loaded on this server (run with --scenario-plugins)' % which)


# ---- the scenarios ------------------------------------------------------------------------------------------------------------------

@scenario('join_chunks')
def join_chunks(s):
    """Joining delivers a position and a growing number of chunk columns; reports how fast."""
    s.wait(lambda: s.position() is not None and s.chunks() > 0, 'a position and a first chunk', 60.0)
    t0 = time.time()
    first = s.chunks()
    s.wait(lambda: s.chunks() >= 25, '25 chunk columns', 90.0)
    dt = max(time.time() - t0, 0.001)
    print('  chunks: %d columns, %.1f columns/s after the first %d' % (s.chunks(), (s.chunks() - first) / dt, first), flush=True)
    s.check(s.block(int(s.position()[0]) >> 0, 0, int(s.position()[2]) >> 0) is not None or s.chunks() >= 25, 'the spawn column was not sent')


@scenario('block_roundtrip')
def block_roundtrip(s):
    """/setblock changes reach the client as block updates, both ways."""
    s.wait(lambda: s.position() is not None and s.chunks() > 4, 'the world', 60.0)
    x, z = int(s.position()[0]) + 2, int(s.position()[2]) + 2
    y = int(s.position()[1]) + 3
    s.setblock(x, y, z, 'minecraft:stone', 1)
    s.setblock(x, y, z, 'minecraft:air', 0)


@scenario('payload_roundtrip', needs_plugin='showcase')
def payload_roundtrip(s):
    """The showcase plugin answers a payload on showcase:echo with the bytes reversed on showcase:reply, and sees the declared channels."""
    s.require_plugin()
    s.register('showcase:echo')
    s.send_payload('showcase:echo', bytes([1, 2, 3, 250, 0, 7]))
    got = s.wait_payload('showcase:reply', 'the echo reply')
    s.check(got[0] == bytes([7, 0, 250, 3, 2, 1]), 'the reply was %r' % got[0])
    s.expect('Payload: 6 bytes', 'the payload event on the server')
    # a larger frame, and a payload on a channel nothing listens to: the server must neither answer nor drop the connection
    s.send_payload('showcase:echo', bytes(range(256)) * 20)
    s.wait_payload('showcase:reply', 'the reply to 5120 bytes', since=1)
    s.send_payload('nobody:listens', b'x')
    s.say('!ping')
    s.expect('pong!', 'the server still answering after an unknown channel')


@scenario('capability_handshake', needs_plugin='showcase')
def capability_handshake(s):
    """Hello in the configuration phase is answered there; the capabilities show on the server; a second hello in play re-negotiates."""
    s.require_plugin()
    welcome = s.config_payloads('jester:welcome')
    s.check(len(welcome) == 1, 'no jester:welcome in the configuration phase')
    wl = welcome[0]
    s.check(wl[0] == 1 and wl[1] == 1, 'welcome format/proto %r' % wl[:2])
    at = 3 + wl[2]
    caps = struct.unpack('>Q', wl[at:at + 8])[0]
    s.check(caps == 2, 'granted caps %d, wanted wind (2): the plugin advertises only wind' % caps)
    s.check(wl[at + 10:at + 14] == bytes([0x12, 0x34, 0x56, 0x78]), 'the nonce was not echoed')
    s.command('caps')
    s.expect('Jester: wind=true fx=false client=0.9.0', 'the capability report')
    # a hello offering nothing in play: granted caps become 0
    hello = bytes([1, 1, 1, 5]) + b'0.9.1' + struct.pack('>Q', 0) + bytes([0xB0, 0xEA, 0x01]) + bytes([0, 0, 0, 7])
    s.send_payload('jester:hello', hello)
    got = s.wait_payload('jester:welcome', 'the welcome to the play-phase hello')
    s.check(struct.unpack('>Q', got[0][3 + got[0][2]:3 + got[0][2] + 8])[0] == 0, 'a client offering nothing was granted something')
    s.command('caps')
    s.expect('Jester: wind=false fx=false client=0.9.1', 'the capability report after the second hello')


@scenario('script_console')
def script_console(s):
    """/script runs a JavaScript snippet on the engine and answers with what it printed; errors come back too; @file runs a file."""
    s.command('script print("sum=" + (1 + 2) + " online=" + server.onlineCount())')
    s.expect('sum=3 online=1', 'the snippet output', 30.0)
    s.command('script throw new Error("boom")')
    s.expect('error: Error: boom', 'the thrown error', 30.0)
    s.command('script @snippet.js')
    s.expect('from the file', 'the output of a snippet file', 30.0)


@scenario('wind_init')
def wind_init(s):
    """A client granted `wind` gets jester:wind INIT after joining: the world seed of its welcome, the default parameters, then TIME_SYNC later."""
    welcome = s.config_payloads('jester:welcome')
    s.check(len(welcome) == 1, 'no jester:welcome in the configuration phase')
    wl = welcome[0]
    at = 3 + wl[2]
    caps = struct.unpack('>Q', wl[at:at + 8])[0]
    s.check(caps & 2, 'wind was not granted (caps %d)' % caps)
    # the welcome's server_tick varint and world seed
    i = at + 14
    while wl[i] & 0x80:
        i += 1
    seed = struct.unpack('>q', wl[i + 1:i + 9])[0]
    got = s.wait_payload('jester:wind', 'the wind INIT after joining', 30.0)
    init = got[0]
    s.check(init[0] == 1 and init[1] == 1, 'INIT type/algo %r' % init[:2])
    s.check(struct.unpack('>q', init[2:10])[0] == seed, 'INIT seed %r is not the welcome seed %d' % (init[2:10], seed))
    j = 10
    while init[j] & 0x80:
        j += 1
    j += 1
    floats = struct.unpack('>7f', init[j:j + 28])
    want = (3.2, 0.0, 0.5, 48.0, 200.0, 0.15, 0.6)
    s.check(all(abs(a - b) < 1e-5 for a, b in zip(floats, want)), 'INIT parameters %r, wanted %r' % (floats, want))
    s.check(init[j + 28] == 0 and len(init) == j + 29, 'INIT flags/length: %r' % init[j + 28:])


# ---- WorldEdit (src/server/worldedit) -----------------------------------------------------------------------------------------------

def _we(s, line, fragment, what, seconds=30.0):
    """Runs a WorldEdit command and waits for the reply that contains `fragment`; returns the chat line."""
    n = len(s.w.chat)
    s.command('/' + line)          # typed as //line: the client strips one slash
    try:
        return s.expect(fragment, what, seconds, since=n)
    except Exception:
        print('  chat since the command: %r' % s.w.chat[n:])
        raise


def _state_ids(s, x, y, z, names):
    """The block-state id a client sees for each block name (placed with /setblock at a probe cell, then cleared)."""
    ids = {'air': 0}
    for name in names:
        s.command('setblock %d %d %d minecraft:%s' % (x, y, z, name))
        s.wait(lambda: s.w.block(x, y, z) not in (None, 0) and s.w.block(x, y, z) not in ids.values(), 'the probe block ' + name)
        ids[name] = s.w.block(x, y, z)
    s.command('setblock %d %d %d minecraft:air' % (x, y, z))
    s.wait(lambda: s.w.block(x, y, z) == 0, 'the probe cell to clear')
    return ids


def _cells(s, x0, y0, z0, x1, y1, z1):
    return [s.w.block(x, y, z) for y in range(y0, y1 + 1) for z in range(z0, z1 + 1) for x in range(x0, x1 + 1)]


def _cells_are(s, box, want, what, seconds=30.0):
    s.wait(lambda: _cells(s, *box) == want, what, seconds)


@scenario('worldedit')
def worldedit(s):
    """Selection, //set //replace //undo //redo, //copy //paste, //hollow, //stack, //sphere, //count through a bot (an operator): the
    blocks are checked as the client learns them AND on the server (//count reads server storage), and //undo must restore every
    cell exactly. Then the worldedit:cui channel: a client that registered it gets the selection."""
    s.wait(lambda: s.position() is not None and s.chunks() >= 9, 'the spawn chunks', 60.0)
    px, py, pz = s.position()[0], s.position()[1], s.position()[2]
    bx, bz = int(px // 1) + 2, int(pz // 1) + 2
    y0 = 200
    s.command('gamemode creative')
    ids = _state_ids(s, bx, y0 + 12, bz, ['stone', 'dirt', 'glowstone', 'oak_planks', 'glass'])
    stone, dirt, glow, planks, glass = ids['stone'], ids['dirt'], ids['glowstone'], ids['oak_planks'], ids['glass']
    box = (bx, y0, bz, bx + 4, y0 + 3, bz + 4)             # 5 x 4 x 5 = 100 cells of open air
    _cells_are(s, box, [0] * 100, 'the build area to be air')

    # selection
    _we(s, 'pos1 %d,%d,%d' % (bx, y0, bz), 'Position 1 set', '//pos1')
    _we(s, 'pos2 %d,%d,%d' % (bx + 4, y0 + 3, bz + 4), '(100 blocks)', '//pos2 and the volume')
    _we(s, 'size', '5 x 4 x 5, 100 blocks', '//size')

    # set, with the server's own count of what it stored
    _we(s, 'set 50%stone,50%dirt', 'set: 100 block(s) changed', '//set a random pattern')
    s.wait(lambda: 0 not in _cells(s, *box), 'every cell to arrive at the client')
    base = _cells(s, *box)
    s.check(set(base) <= {stone, dirt} and base.count(stone) > 25 and base.count(dirt) > 25, 'the pattern gave other blocks or a lopsided mix')
    n_stone = base.count(stone)
    line = _we(s, 'count stone', 'Counted', '//count stone (server side)')
    s.check('Counted %d block(s)' % n_stone in line, 'server counted %r but the client saw %d stone' % (line, n_stone))

    # replace with a mask, then overwrite, then undo both: every cell back, exactly
    _we(s, 'replace stone glowstone', 'replace: %d block(s) changed' % n_stone, '//replace')
    _cells_are(s, box, [glow if b == stone else b for b in base], 'stone to become glowstone, dirt untouched')
    _we(s, 'set oak_planks', 'set: 100 block(s) changed', '//set over it')
    _cells_are(s, box, [planks] * 100, 'all planks')
    _we(s, 'undo 2', 'Undid 2 edit(s)', '//undo 2')
    _cells_are(s, box, base, 'the first pattern restored cell for cell')
    line = _we(s, 'count stone', 'Counted', '//count after undo')
    s.check('Counted %d block(s)' % n_stone in line, 'server count after undo: %r' % line)
    _we(s, 'redo', 'Redid 1 edit(s)', '//redo')
    _cells_are(s, box, [glow if b == stone else b for b in base], 'the replace redone')
    _we(s, 'undo 3', 'Undid', '//undo everything')
    _cells_are(s, box, [0] * 100, 'back to air after undoing all')

    # copy + paste (the copier stands where the paste happens: same cells), hollow
    _we(s, 'set stone', 'set: 100 block(s) changed', 'a solid block to copy')
    _we(s, 'copy', 'Copied 100 block(s)', '//copy')
    _we(s, 'set air', 'set: 100 block(s) changed', 'clearing it')
    _cells_are(s, box, [0] * 100, 'cleared')
    _we(s, 'paste', 'paste: 100 block(s) changed', '//paste')
    _cells_are(s, box, [stone] * 100, 'the paste put the stone back at the copier position')
    _we(s, 'undo 2', 'Undid 2', 'undo the paste and the clear')
    _cells_are(s, box, [stone] * 100, 'stone again after undoing paste and clear')
    _we(s, 'hollow', 'hollow: %d block(s) changed' % (3 * 2 * 3), '//hollow')
    want = []
    for yy in range(4):
        for zz in range(5):
            for xx in range(5):
                inner = 0 < xx < 4 and 0 < zz < 4 and 0 < yy < 3
                want.append(0 if inner else stone)
    _cells_are(s, box, want, 'a hollow shell of stone')
    _we(s, 'undo 2', 'Undid 2', 'undo hollow and set')
    _cells_are(s, box, [0] * 100, 'air once more')

    # stack: 3 more copies of a single block along +x
    _we(s, 'pos2 %d,%d,%d' % (bx, y0, bz), '(1 blocks)', 'a 1-block selection')
    _we(s, 'set glowstone', 'set: 1 block(s) changed', 'a single block')
    _we(s, 'stack 3 east', 'stack: 3 block(s) changed', '//stack 3 east')
    _cells_are(s, (bx, y0, bz, bx + 3, y0, bz), [glow] * 4, 'a row of four')
    _we(s, 'undo 2', 'Undid 2', 'undo stack and set')
    _cells_are(s, (bx, y0, bz, bx + 3, y0, bz), [0] * 4, 'the row removed')

    # a sphere centred on the player, then undone
    _we(s, 'pos1 %d,%d,%d' % (bx - 5, y0 - 5, bz - 5), 'Position 1', 'big selection corner 1')
    _we(s, 'pos2 %d,%d,%d' % (bx + 5, y0 + 5, bz + 5), 'Position 2', 'big selection corner 2')
    _we(s, 'sphere glass 3', 'sphere:', '//sphere (centred on the player)')
    _we(s, 'undo', 'Undid 1', 'undo the sphere')

    # the cui channel: register, say hello, the selection arrives as text
    s.register('worldedit:cui')
    s.send_payload('worldedit:cui', b'v|4')
    _we(s, 'pos1 %d,%d,%d' % (bx + 1, y0 + 1, bz + 1), 'Position 1', 'pos1 for the cui')
    s.wait(lambda: any(b.startswith(b'p|0|') for b in s.payloads('worldedit:cui')), 'a p|0 point on worldedit:cui')
    texts = [b.decode() for b in s.payloads('worldedit:cui')]
    s.check('s|cuboid' in texts, 'no s|cuboid shape message: %r' % texts)
    s.check(any(t.startswith('p|0|%d|%d|%d|' % (bx + 1, y0 + 1, bz + 1)) for t in texts), 'point 0 not at the pos1 cell: %r' % texts)
    _we(s, 'pos2 %d,%d,%d' % (bx + 3, y0 + 2, bz + 3), 'Position 2', 'pos2 for the cui')
    want = 'p|1|%d|%d|%d|%d' % (bx + 3, y0 + 2, bz + 3, 3 * 2 * 3)
    s.wait(lambda: want.encode() in s.payloads('worldedit:cui'), 'the new p|1 point on worldedit:cui (%s)' % want)


@scenario('worldedit_wand')
def worldedit_wand(s):
    """//wand puts the wooden axe in the bot's hand; digging a block (creative) with it sets position 1 and does not break the block,
    and using a block with it sets position 2."""
    s.wait(lambda: s.position() is not None and s.chunks() >= 9, 'the spawn chunks', 60.0)
    s.command('gamemode creative')
    _we(s, 'wand', 'wooden axe', '//wand')
    px, py, pz = s.position()[0], s.position()[1], s.position()[2]
    bx, by, bz = int(px // 1) + 1, int(py // 1) - 1, int(pz // 1)
    s.wait(lambda: s.w.block(bx, by, bz) not in (None, 0), 'a block to click', 20.0)
    before = s.w.block(bx, by, bz)
    s.c.send(s.m.SB_CARRIED, struct.pack('>h', 0))
    n = len(s.w.chat)
    s.c.send(s.m.SB_ACTION, s.m.varint(0) + s.m.block_pos(bx, by, bz) + bytes([1]) + s.m.varint(31))
    s.expect('Position 1 set to (%d, %d, %d)' % (bx, by, bz), 'the wand left click', 20.0, since=n)
    time.sleep(0.5)
    s.check(s.w.block(bx, by, bz) == before, 'the left click with the wand broke the block')
    n = len(s.w.chat)
    s.c.send(s.m.SB_USE_ON, s.m.varint(0) + s.m.block_pos(bx + 1, by, bz) + s.m.varint(1) + struct.pack('>fff', 0.5, 1.0, 0.5) +
             bytes([0, 0]) + s.m.varint(32))
    s.expect('Position 2 set to (%d, %d, %d)' % (bx + 1, by, bz), 'the wand right click', 20.0, since=n)
    _we(s, 'size', '2 x 1 x 1, 2 blocks', '//size after the wand')


def run(m, c, st, w, biomes, ctx, args):
    wanted = [n for n in (args.scenario or 'all').split(',') if n]
    known = [n for n, _, _ in SCENARIOS]
    for n in wanted:
        if n != 'all' and n not in known:
            raise m.Fail('no scenario %r (have: %s)' % (n, ', '.join(known)))
    s = Scn(m, c, st, w, biomes, ctx, args)
    results = []
    for name, needs, fn in SCENARIOS:
        if 'all' not in wanted and name not in wanted:
            continue
        t0 = time.time()
        try:
            fn(s)
            outcome, detail = 'PASS', ''
        except Inconclusive as e:
            outcome, detail = 'INCONCLUSIVE', str(e)
        except m.Fail as e:
            outcome, detail = 'FAIL', str(e)
        results.append((name, outcome, detail))
        print('SCENARIO %-22s %-12s %5.1fs %s' % (name, outcome, time.time() - t0, detail), flush=True)
    print('SCENARIOS: %d pass, %d fail, %d inconclusive' % tuple(sum(1 for r in results if r[1] == o) for o in ('PASS', 'FAIL', 'INCONCLUSIVE')),
          flush=True)
    st.hit('scenarios_done')
    failed = [r[0] for r in results if r[1] == 'FAIL']
    if failed:
        raise m.Fail('scenarios failed: %s' % ', '.join(failed))
