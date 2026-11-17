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
    # Offered by the server mods: physics2 (1), wind (2), body stream (4), fx (16) = 23. The showcase plugin adds wind; the body/fx/physics2 bits come from
    # bodysync.aowl. modsync (8) is on because the scenario runner writes a jester-mods.json; materials (32) and cui (64, WorldEdit) were not granted in this run (measured: 31).
    s.check(caps == 31, 'granted caps %d, wanted physics2+wind+modsync+bodystream+fx (31)' % caps)
    s.check(wl[at + 10:at + 14] == bytes([0x12, 0x34, 0x56, 0x78]), 'the nonce was not echoed')
    s.command('caps')
    s.expect('Jester: wind=true fx=true client=0.9.0', 'the capability report')
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


@scenario('fluids_finite')
def fluids_finite(s):
    """Finite fluids (src/server/fluids): OFF by default, vanilla water flows (a falling column appears under a source); `/fluids on`
    makes water a conserved volume: a stack of four source blocks above a 3x3 stone basin falls, fills the basin floor and the sources
    are GONE (vanilla never removes a source), the server's own `/fluids status` reports exactly 4 x 1024 water units, nothing spills
    over the rim; `/fluids off` leaves the world as it is."""
    s.wait(lambda: s.position() is not None and s.chunks() >= 9, 'the spawn chunks', 60.0)
    s.command('gamemode creative')
    px, py, pz = s.position()[0], s.position()[1], s.position()[2]
    cx, cz = int(px // 1) + 3, int(pz // 1) + 3
    y0 = int(py // 1) + 6                                  # an open-air slab a few blocks over the bot (inside the scanned sections)
    ids = _state_ids(s, cx, y0 + 12, cz, ['stone', 'water'])
    stone, wsrc = ids['stone'], ids['water']
    is_water = lambda b: b is not None and wsrc <= b < wsrc + 16

    def box(x0, y0_, z0, x1, y1, z1, name):
        s.command('fill %d %d %d %d %d %d minecraft:%s' % (x0, y0_, z0, x1, y1, z1, name))

    def build():
        box(cx - 2, y0, cz - 2, cx + 2, y0 + 6, cz + 2, 'air')
        s.wait(lambda: s.w.block(cx, y0 + 4, cz) == 0 and s.w.block(cx + 2, y0 + 1, cz + 2) == 0, 'the build area to be air', 20.0)
        box(cx - 2, y0, cz - 2, cx + 2, y0, cz + 2, 'stone')                 # floor 5x5
        box(cx - 2, y0 + 1, cz - 2, cx + 2, y0 + 1, cz + 2, 'stone')         # rim: a 5x5 block ...
        box(cx - 1, y0 + 1, cz - 1, cx + 1, y0 + 1, cz + 1, 'air')           # ... with a 3x3 hole = the basin
        s.wait(lambda: s.w.block(cx, y0 + 1, cz) == 0 and s.w.block(cx + 2, y0 + 1, cz) == stone, 'the basin', 20.0)

    n = len(s.w.chat)
    s.command('fluids status')
    s.expect('finite fluids: off', 'the default is off', since=n)

    # OFF: vanilla. A source above the basin makes a falling column below it (vanilla fluid ticks run).
    build()
    s.command('setblock %d %d %d minecraft:water' % (cx, y0 + 4, cz))
    s.wait(lambda: is_water(s.w.block(cx, y0 + 3, cz)), 'vanilla water to fall from the source (fluids are off)', 20.0)
    s.check(is_water(s.w.block(cx, y0 + 4, cz)), 'the vanilla source vanished while the fluids were off')
    build()                                                # wipes it again (fill air then stone)

    # ON: the conserved model
    n = len(s.w.chat)
    s.command('fluids on')
    s.expect('Finite fluids ON', '/fluids on', since=n)
    time.sleep(3.0)                                        # natural water near the bot is adopted by the first scans
    import re

    def status():
        n_ = len(s.w.chat)
        s.command('fluids status')
        ln = s.expect('water units', '/fluids status', since=n_)
        m_ = re.search(r'\((\d+) water units.*injected (\d+) drained (\d+)', ln)
        s.check(m_ is not None, 'unparsable status line %r' % ln)
        return ln, int(m_.group(1)), int(m_.group(2)), int(m_.group(3))
    _, w_before, inj_before, dr_before = status()
    box(cx, y0 + 2, cz, cx, y0 + 5, cz, 'water')           # four sources in a column over the basin
    s.wait(lambda: is_water(s.w.block(cx, y0 + 2, cz)) and is_water(s.w.block(cx, y0 + 5, cz)), 'the four sources to appear', 20.0)
    floor = [(cx + dx, y0 + 1, cz + dz) for dx in (-1, 0, 1) for dz in (-1, 0, 1)]
    s.wait(lambda: all(is_water(s.w.block(*c)) for c in floor), 'water on all nine basin cells (the model moved the sources)', 40.0)
    s.wait(lambda: s.w.block(cx, y0 + 5, cz) == 0 and s.w.block(cx, y0 + 3, cz) == 0, 'the sources to be gone (water is a volume, not a source)', 40.0)
    time.sleep(2.0)
    line, w_after, inj_after, dr_after = status()
    print('  status before: %d water units, injected %d drained %d; after: %d, %d, %d' % (w_before, inj_before, dr_before, w_after, inj_after, dr_after))
    # (the status totals also include natural water adopted around the bot meanwhile, so they are printed, not asserted)
    s.check(dr_after == dr_before, 'the model drained %d units for no reason' % (dr_after - dr_before))
    outside = [(cx + dx, y0 + 1, cz + dz) for dx in (-2, 2) for dz in range(-2, 3)] + [(cx + dx, y0 + 2, cz + dz) for dx in range(-2, 3) for dz in range(-2, 3)]
    s.check(not any(is_water(s.w.block(*c)) for c in outside), 'water went over the rim or onto the rim')
    levels = sorted(s.w.block(*c) - wsrc for c in floor)
    print('  basin levels (block-state offsets): %r' % levels)
    # 4 x 1024 units over 9 cells = 455 each = ceil(8*455/1024) = 4 eighths = flowing level 8-4 = block-state offset 4 (volume check)
    s.check(levels == [4] * 9, 'the nine basin cells should all be level offset 4 (4096 units over 9 cells): %r' % levels)

    # OFF again: the blocks stay
    before = [s.w.block(*c) for c in floor]
    n = len(s.w.chat)
    s.command('fluids off')
    s.expect('Finite fluids off', '/fluids off', since=n)
    time.sleep(1.5)
    s.check([s.w.block(*c) for c in floor] == before, 'turning the model off changed the basin')
    s.command('fill %d %d %d %d %d %d minecraft:air' % (cx - 2, y0, cz - 2, cx + 2, y0 + 6, cz + 2))


# ---- physics wiring (src/server/physwire): climate feed, fire spread, explosions, erosion -------------------------------------------
# These change settings of the scratch world and take minutes, so `all` skips them: name them (--scenario phys_climate,phys_fire,...).

import math
import re

EXPLICIT_ONLY = set()


def explicit(name):
    EXPLICIT_ONLY.add(name)
    return name


def _idle(s, seconds):
    """Waits while still answering the server (keep-alives): a plain sleep would get the bot kicked."""
    end = time.time() + seconds
    try:
        s.wait(lambda: time.time() >= end, 'time', seconds + 10.0)
    except Exception:
        pass


def _ask(s, line, fragment, what, seconds=20.0):
    """Runs a command and waits for a reply line containing `fragment`; returns every reply line since the command."""
    n = len(s.w.chat)
    s.command(line)
    try:
        s.expect(fragment, what, seconds, since=n)
    except Exception:
        print('  chat since /%s: %r' % (line, s.w.chat[n:]), flush=True)
        raise
    return list(s.w.chat[n:])


def _num(text, pattern):
    mm = re.search(pattern, text)
    return float(mm.group(1)) if mm else None


def _wind_updates(s):
    """The decoded jester:wind UPDATE messages so far: (mask, baseSpeed, baseYaw) (None for a field the message does not carry)."""
    out = []
    for d in s.payloads('jester:wind'):
        if d[0] != 2:
            continue
        i = 1
        while d[i] & 0x80:
            i += 1
        i += 1
        mask = (d[i] << 8) | d[i + 1]
        i += 2
        speed = yaw = None
        if mask & 1:
            speed = struct.unpack('>f', d[i:i + 4])[0]
            i += 4
        if mask & 2:
            yaw = struct.unpack('>f', d[i:i + 4])[0]
            i += 4
        out.append((mask, speed, yaw))
    return out


@scenario(explicit('phys_climate'))
def phys_climate(s):
    """Climate feed: with `climate_feed` ON the real date, weather and position drive the wind. Off by default (no UPDATE, status says off);
    on + an override pushes baseSpeed/baseYaw to a client holding the wind capability; without the override the published base speed equals
    the climate model's synoptic speed at the player; the season follows /time (half a year later the temperature differs by 10+ C);
    real thunder raises the resulting wind; off restores the default parameters."""
    s.wait(lambda: s.position() is not None and s.chunks() >= 9, 'the spawn chunks', 60.0)
    welcome = s.config_payloads('jester:welcome')
    if not welcome:
        s.inconclusive('no jester:welcome: the wind capability was not offered')
    s.wait_payload('jester:wind', 'the wind INIT after joining', 30.0)
    s.command('gamemode creative')
    lines = _ask(s, 'climate status', 'climate_feed', 'the climate status')
    s.check(any('climate_feed off' in l for l in lines), 'default is off: %r' % lines)
    _idle(s, 3.0)
    s.check(not _wind_updates(s), 'with the feed off no UPDATE was sent: %r' % _wind_updates(s))
    # on, pinned wind toward +x 8 b/s: base speed 8, yaw -pi/2
    _ask(s, 'climate on', 'climate_feed is now on', 'climate on')
    _ask(s, 'climate override 8 0', 'climate override: synoptic wind', 'the override')
    s.wait(lambda: any(sp is not None and abs(sp - 8.0) < 0.01 for _, sp, _ in _wind_updates(s)), 'an UPDATE with baseSpeed 8', 25.0)
    last = [u for u in _wind_updates(s) if u[1] is not None and abs(u[1] - 8.0) < 0.01][-1]
    s.check(last[2] is not None and abs(last[2] + math.pi / 2) < 0.01, 'yaw for a +x wind is -pi/2, got %r' % (last,))
    # pinned toward +z 6 b/s: yaw 0
    _ask(s, 'climate override 0 6', 'climate override: synoptic wind', 'the second override')
    s.wait(lambda: any(sp is not None and abs(sp - 6.0) < 0.01 and yw is not None and abs(yw) < 0.01 for _, sp, yw in _wind_updates(s)),
           'an UPDATE with baseSpeed 6, yaw 0', 25.0)
    # no override: the climate model's own wind; published speed == synoptic speed printed by status
    _ask(s, 'climate override off', 'climate override cleared', 'override off')
    _idle(s, 2.0)
    lines = _ask(s, 'climate status', 'published jester:wind', 'status')
    text = ' '.join(lines)
    sx = _num(text, r'synoptic wind (-?[0-9.]+),')
    sz = _num(text, r'synoptic wind -?[0-9.]+, (-?[0-9.]+) b/s')
    pub = _num(text, r'base speed (-?[0-9.]+) b/s')
    s.check(sx is not None and sz is not None and pub is not None, 'status fields: %r' % text)
    syn = math.hypot(sx, sz)
    s.check(abs(pub - min(syn, 20.0)) < 0.25, 'published base speed %.1f equals the synoptic speed %.1f (hysteresis 0.1)' % (pub, syn))
    temp0 = _num(text, r'\): (-?[0-9.]+) C')
    season0 = re.search(r'\((spring|summer|autumn|winter)\)', text)
    s.check(temp0 is not None and season0 is not None, 'temperature and season in the status: %r' % text)
    # half a year later (24 day year): the season and the temperature change
    _ask(s, 'time add 288000', 'time', 'time add')
    _idle(s, 1.5)
    lines = _ask(s, 'climate at', 'synoptic wind', 'status after the time jump')
    text2 = ' '.join(lines)
    temp1 = _num(text2, r'\): (-?[0-9.]+) C')
    season1 = re.search(r'\((spring|summer|autumn|winter)\)', text2)
    s.check(temp1 is not None and season1 is not None and season1.group(1) != season0.group(1),
            'season changed with the date: %s -> %s' % (season0.group(1), season1.group(1) if season1 else None))
    s.check(abs(temp1 - temp0) >= 10.0, 'temperature moved by %.1f C half a year later (%.1f -> %.1f)' % (abs(temp1 - temp0), temp0, temp1))
    # real thunder multiplies the wind the server field uses
    _ask(s, 'time add 288000', 'time', 'time back')
    _ask(s, 'weather clear', 'clear', 'weather clear')
    _idle(s, 2.0)
    l0 = ' '.join(_ask(s, 'climate at', 'with the real weather', 'calm status'))
    calm = math.hypot(_num(l0, r'real weather (-?[0-9.]+),'), _num(l0, r'real weather -?[0-9.]+, (-?[0-9.]+)'))
    _ask(s, 'weather thunder', 'thunder', 'weather thunder')
    big = 0.0
    for _ in range(40):
        _idle(s, 1.5)
        l1 = ' '.join(_ask(s, 'climate at', 'with the real weather', 'storm status'))
        big = math.hypot(_num(l1, r'real weather (-?[0-9.]+),'), _num(l1, r'real weather -?[0-9.]+, (-?[0-9.]+)'))
        if calm > 0.05 and big > calm * 1.15:
            break
    s.check(calm > 0.05 and big > calm * 1.15, 'real thunder raised the wind with the real weather: calm %.2f, storm %.2f' % (calm, big))
    _ask(s, 'weather clear', 'clear', 'weather clear again')
    # off restores the defaults
    n = len(_wind_updates(s))
    _ask(s, 'climate off', 'climate_feed is now off', 'climate off')
    s.wait(lambda: any(sp is not None and abs(sp - 3.2) < 0.01 for _, sp, _ in _wind_updates(s)[n:]), 'an UPDATE back to the default 3.2 b/s', 25.0)


def _plank_row_state(s, bx, y, bz, n):
    return [s.block(bx + i, y, bz) for i in range(n)]


@scenario(explicit('phys_fire'))
def phys_fire(s):
    """Fire spread by material, wind and rain, behind `physics_fire` (default off). Off: /fire ignite refuses. On with a pinned +x wind of
    10 b/s: a 17 plank row lit in the middle burns downwind (+x) far faster than upwind, the burnt cells are real air on the client AND counted
    by the model (`/fire status` burnt out > 0, fire ticks adopted > 0). In rain the same row burns far less."""
    s.wait(lambda: s.position() is not None and s.chunks() >= 9, 'the spawn chunks', 60.0)
    s.command('gamemode creative')
    px, pz = int(s.position()[0] // 1), int(s.position()[2] // 1)
    y0 = 200
    bx = px + 2
    ids = _state_ids(s, bx, y0 + 12, pz + 2, ['oak_planks'])
    planks = ids['oak_planks']
    lines = _ask(s, 'fire status', 'physics_fire', 'fire status')
    s.check(any('physics_fire off' in l for l in lines), 'default is off: %r' % lines)
    _ask(s, 'fire ignite %d %d %d' % (bx + 8, y0, pz + 2), 'physics_fire is off', 'ignite while off')
    _ask(s, 'fire on', 'physics_fire is now on', 'fire on')
    _ask(s, 'climate on', 'climate_feed is now on', 'climate on')
    _ask(s, 'climate override 10 0', 'climate override: synoptic wind', 'wind +x')
    _ask(s, 'weather clear', 'clear', 'weather clear')

    def run_row(z, seconds, label):
        s.command('fill %d %d %d %d %d %d minecraft:air' % (bx - 4, y0 - 2, z - 3, bx + 22, y0 + 6, z + 3))
        s.command('fill %d %d %d %d %d %d minecraft:oak_planks' % (bx, y0, z, bx + 16, y0, z))
        s.wait(lambda: all(b == planks for b in _plank_row_state(s, bx, y0, z, 17)), 'the plank row ' + label, 40.0)
        _ask(s, 'fire ignite %d %d %d' % (bx + 8, y0, z), 'Ignited', 'ignite ' + label)
        t0 = time.time()
        while time.time() - t0 < seconds:
            _idle(s, 2.0)
            row = _plank_row_state(s, bx, y0, z, 17)
            if row.count(planks) == 0:
                break
            if row[9:].count(planks) == 0 and row[:8].count(planks) == 8 and row[8] != planks:
                break
        row = _plank_row_state(s, bx, y0, z, 17)
        up = sum(1 for b in row[:8] if b != planks)
        down = sum(1 for b in row[9:] if b != planks)
        print('  %s: planks upwind gone %d/8, downwind gone %d/8, centre %s after %.0fs' % (label, up, down, 'gone' if row[8] != planks else 'stands',
                                                                                         time.time() - t0), flush=True)
        return up, down, row[8] != planks

    up, down, mid = run_row(pz + 2, 80.0, 'dry, wind +x')
    st = ' '.join(_ask(s, 'fire status', 'world changed under the model', 'fire status after the dry row'))
    burnt = _num(st, r'burnt out ([0-9]+)')
    adopted = _num(st, r'adopted ([0-9]+)')
    s.check(burnt is not None and burnt >= 3, 'the model burnt cells out (burnt out %s)' % burnt)
    s.check(adopted is not None and adopted >= 1, 'vanilla fire ticks were handed to the model (adopted %s)' % adopted)
    s.check(down >= 5, 'the fire went downwind: %d of 8 downwind planks gone' % down)
    s.check(down >= up + 3, 'wind carries the fire: downwind gone %d, upwind gone %d' % (down, up))
    # rain: the same row 60 blocks away puts itself out
    _ask(s, 'weather rain', 'rain', 'weather rain')
    _idle(s, 25.0)
    up2, down2, mid2 = run_row(pz + 62, 80.0, 'rain, wind +x')
    gone_dry = up + down + (1 if mid else 0)
    gone_rain = up2 + down2 + (1 if mid2 else 0)
    s.check(gone_rain + 6 <= gone_dry, 'rain limits the fire: %d planks gone in the rain vs %d dry' % (gone_rain, gone_dry))
    _ask(s, 'weather clear', 'clear', 'weather clear')
    _ask(s, 'climate off', 'climate_feed is now off', 'climate off')
    _ask(s, 'fire off', 'physics_fire is now off', 'fire off')


def _count_cells(s, box, state):
    x0, y0, z0, x1, y1, z1 = box
    return sum(1 for y in range(y0, y1 + 1) for z in range(z0, z1 + 1) for x in range(x0, x1 + 1) if s.block(x, y, z) == state)


@scenario(explicit('phys_blast'))
def phys_blast(s):
    """Explosions through the blast model. Default (`physics_triggers` off): /explode is the vanilla blast, the model counts no blast. With
    `/body triggers full`: the same blast goes through blast.aowl (`/body triggers status` counts blasts), makes a crater of real air on
    the client and spawns debris bodies (`/body status` created > 0), and soft dirt loses far more than stone for the same power."""
    s.wait(lambda: s.position() is not None and s.chunks() >= 9, 'the spawn chunks', 60.0)
    s.command('gamemode creative')
    px, pz = int(s.position()[0] // 1), int(s.position()[2] // 1)
    gy = int(s.position()[1] // 1) - 1          # the block under the bot's feet: the cubes stand IN the ground so a collapse check keeps them
    ids = _state_ids(s, px + 2, gy + 14, pz + 2, ['stone', 'dirt'])
    stone, dirt = ids['stone'], ids['dirt']

    def cube(x, z, name, state, label):
        s.command('fill %d %d %d %d %d %d minecraft:air' % (x - 1, gy + 1, z - 1, x + 9, gy + 12, z + 9))
        s.command('fill %d %d %d %d %d %d minecraft:%s' % (x, gy - 4, z, x + 8, gy + 4, z + 8, name))
        box = (x, gy - 4, z, x + 8, gy + 4, z + 8)
        try:
            s.wait(lambda: _count_cells(s, box, state) == 729, 'the %s cube' % label, 40.0)
        except Exception:
            print('  cube %s: %d of 729, a sample column %r' % (label, _count_cells(s, box, state), [s.block(x + 4, yy, z + 4) for yy in range(gy - 4, gy + 5)]), flush=True)
            raise
        return box

    def blast(box, state, label):
        x, y, z = box[0], box[1], box[2]
        before = _count_cells(s, box, state)
        s.command('explode %d %d %d 4' % (x + 4, y + 8, z + 4))
        s.wait(lambda: _count_cells(s, box, state) < before, 'the %s crater to reach the client' % label, 30.0)
        _idle(s, 4.0)
        return before - _count_cells(s, box, state)

    try:
        lines = ' '.join(_ask(s, 'body triggers status', 'blasts', 'trigger status'))
        s.check('physics_triggers' in lines and ': off' in lines, 'default is off: %r' % lines)
        b0 = _num(lines, r'blasts ([0-9]+)')
        # every cube is built while the triggers are off (a built dirt tower would be collapse checked and could fall on its own)
        sbox0 = cube(px + 3, pz + 3, 'stone', stone, 'stone')
        sbox = cube(px + 3, pz - 13, 'stone', stone, 'stone')
        dbox = cube(px - 13, pz + 3, 'dirt', dirt, 'dirt')
        vanilla = blast(sbox0, stone, 'stone')
        lines = ' '.join(_ask(s, 'body triggers status', 'blasts', 'trigger status after the vanilla blast'))
        s.check(_num(lines, r'blasts ([0-9]+)') == b0, 'off: the blast model was not used (%r)' % lines)
        s.check(vanilla > 0, 'off: the vanilla blast still made a crater (%d stone cells)' % vanilla)
        _ask(s, 'body triggers full', 'now full', 'triggers full')
        crater_stone = blast(sbox, stone, 'stone')
        crater_dirt = blast(dbox, dirt, 'dirt')
        lines = ' '.join(_ask(s, 'body triggers status', 'blasts', 'trigger status after the model blasts'))
        nb = _num(lines, r'blasts ([0-9]+)')
        debris = _num(lines, r'debris bodies ([0-9]+)')
        print('  craters: vanilla stone %d, model stone %d, model dirt %d; %s' % (vanilla, crater_stone, crater_dirt, lines), flush=True)
        s.check(nb is not None and b0 is not None and nb >= b0 + 2, 'full: both blasts went through the blast model (blasts %s)' % nb)
        s.check(crater_stone > 0 and crater_dirt > 0, 'full: craters appeared on the client (%d stone, %d dirt)' % (crater_stone, crater_dirt))
        s.check(crater_dirt > crater_stone, 'the model: dirt loses more than stone for the same power (%d vs %d cells)' % (crater_dirt, crater_stone))
        s.check(debris is not None and debris >= 1, 'full: the blast spawned debris bodies (%s)' % debris)
        st = ' '.join(_ask(s, 'body status', 'created', 'body status'))
        s.check((_num(st, r'created ([0-9]+)') or 0) >= 1, 'bodies were created: %r' % st)
    finally:
        s.command('body triggers off')
        _idle(s, 1.0)


@scenario(explicit('phys_erosion'))
def phys_erosion(s):
    """The erosion job: nothing happens until `/erosion run`; a 45 degree dirt ramp (steeper than dirt can lie) slumps to a gentler slope with
    the number of dirt blocks unchanged (volume conserved) and blocks that really moved on the client; a second run on the settled shape
    changes nothing; a stone ramp does not move."""
    s.wait(lambda: s.position() is not None and s.chunks() >= 9, 'the spawn chunks', 60.0)
    s.command('gamemode creative')
    px, pz = int(s.position()[0] // 1), int(s.position()[2] // 1)
    y0 = 200
    bx, bz = px + 2, pz + 2
    ids = _state_ids(s, bx, y0 + 20, bz, ['dirt', 'stone'])
    dirt, stone = ids['dirt'], ids['stone']
    _ask(s, 'erosion status', 'no erosion job', 'status before any job')

    N = 6           # a 45 degree dirt ramp: column i is i + 1 blocks high, 4 wide, on a stone platform wide enough to catch the slump

    def build():
        s.command('fill %d %d %d %d %d %d minecraft:air' % (bx - 9, y0 - 1, bz - 11, bx + 21, y0 + 20, bz + 11))
        s.command('fill %d %d %d %d %d %d minecraft:stone' % (bx - 8, y0, bz - 10, bx + 20, y0, bz + 10))
        for i in range(N):
            s.command('fill %d %d %d %d %d %d minecraft:dirt' % (bx + i, y0 + 1, bz, bx + i, y0 + 1 + i, bz + 3))
        box = (bx - 8, y0 + 1, bz - 10, bx + 20, y0 + 14, bz + 10)
        s.wait(lambda: _count_cells(s, box, dirt) == sum((i + 1) * 4 for i in range(N)), 'the dirt ramp', 60.0)
        return box

    def tops():
        return [max([y for y in range(y0 + 1, y0 + 14) if s.block(bx + i, y, bz + 1) == dirt] or [0]) for i in range(N)]

    def run_job(args, what):
        _ask(s, 'erosion run ' + args, 'erosion job started', what)
        st = ''
        for _ in range(60):
            _idle(s, 1.0)
            st = ' '.join(_ask(s, 'erosion status', 'jobs started', what + ' status'))
            if 'finished' in st:
                break
        return st

    box = build()
    total = _count_cells(s, box, dirt)
    top_before = tops()
    s.command('tp @s %d %d %d' % (bx + 3, y0 + 10, bz + 2))
    s.wait(lambda: s.position() is not None and abs(s.position()[1] - (y0 + 10)) < 6, 'the teleport', 20.0)
    _idle(s, 1.0)
    s.check(_count_cells(s, box, dirt) == total and tops() == top_before, 'nothing erodes by itself')
    st = run_job('20 7 0', 'the job')
    print('  job: %s' % st, flush=True)
    s.check('finished' in st, 'the job finished: %r' % st)
    changed = _num(st, r'([0-9]+) cells changed')
    s.check(changed is not None and changed > 0, 'the job changed cells (%s)' % changed)
    s.wait(lambda: tops() != top_before, 'the changes to reach the client', 20.0)
    s.wait(lambda: _count_cells(s, box, dirt) == total, 'the dirt count to settle at the old total %d (volume conserved)' % total, 30.0)
    after = tops()
    print('  ramp top before %r' % top_before, flush=True)
    print('  ramp top after  %r' % after, flush=True)
    s.check(after[N - 1] < top_before[N - 1], 'the high end of the ramp lost height on the client (%d -> %d)' % (top_before[N - 1], after[N - 1]))
    steep_before = max(top_before[i + 3] - top_before[i] for i in range(N - 3))
    steep_after = max(after[i + 3] - after[i] for i in range(N - 3))
    s.check(steep_after < steep_before, 'the steepest 3 column rise fell from %d to %d' % (steep_before, steep_after))
    st2 = run_job('20 7 0', 'the second job')
    s.check(_num(st2, r'([0-9]+) cells changed') == 0, 'a settled slope is stable: %r' % st2)
    s.command('fill %d %d %d %d %d %d minecraft:stone replace minecraft:dirt' % (bx - 8, y0 + 1, bz - 10, bx + 20, y0 + 14, bz + 10))
    s.wait(lambda: _count_cells(s, box, dirt) == 0, 'the ramp to turn to stone', 40.0)
    st3 = run_job('20 7 0', 'the stone job')
    s.check(_num(st3, r'([0-9]+) cells changed') == 0, 'stone stays: %r' % st3)


# ---- Fabric gaps (docs/FABRIC_GAPS.md): driven by tools/run_fabric_live.py, which sets the environment ----------------------------

@scenario('world_flat')
def world_flat(s):
    """On a server whose world_type is "flat" the column under the player is bedrock, dirt, dirt, grass and then air only."""
    import os
    if os.environ.get('EXPECT_WORLD_TYPE') != 'flat':
        s.inconclusive('the server is not a flat world (EXPECT_WORLD_TYPE=flat not set)')
    s.wait(lambda: s.position() is not None and s.chunks() > 4, 'the world', 60.0)
    x, z = int(s.position()[0]), int(s.position()[2])
    s.wait(lambda: s.block(x, -64, z) is not None, 'the spawn column', 30.0)
    col = [s.block(x, y, z) for y in range(-64, 40)]
    solid = [i for i, b in enumerate(col) if b]
    print('  flat column at %d,%d: solid cells %s (y %d..%d)' % (x, z, len(solid), -64 + solid[0] if solid else 0, -64 + solid[-1] if solid else 0), flush=True)
    s.check(solid == [0, 1, 2, 3], 'a flat world has exactly 4 solid layers at y -64..-61, got solid indexes %s' % solid)
    s.check(col[1] == col[2] and col[0] != col[1] and col[3] != col[2], 'layers are bedrock, dirt, dirt, grass (distinct states)')


@scenario('terrain_world')
def terrain_world(s):
    """On a noise world (default, amplified, large_biomes) the spawn column is solid from the bottom to well above y=60."""
    import os
    if os.environ.get('EXPECT_WORLD_TYPE') not in ('default', 'amplified', 'large_biomes'):
        s.inconclusive('EXPECT_WORLD_TYPE is not default/amplified/large_biomes')
    s.wait(lambda: s.position() is not None and s.chunks() > 20, 'the world', 120.0)
    x, z = int(s.position()[0]), int(s.position()[2])
    col = [s.block(x, y, z) for y in range(-60, 100)]
    solid = sum(1 for b in col if b)
    print('  %s world: %d chunk columns, %d solid cells in the spawn column' % (os.environ.get('EXPECT_WORLD_TYPE'), s.chunks(), solid), flush=True)
    s.check(solid > 60, 'a noise world has a deep solid column below the surface')


@scenario('player_roundtrip_set')
def player_roundtrip_set(s):
    """Phase A: creative, 7 diamonds, an obsidian stack in the ender chest, moved to 12 90 -34."""
    import os
    if os.environ.get('PHASE') != 'set':
        s.inconclusive('PHASE=set not given')
    s.wait(lambda: s.position() is not None and s.chunks() > 4, 'the world', 60.0)
    n = len(s.w.chat)
    s.command('gamemode creative')
    s.command('give %s minecraft:diamond 7' % os.environ.get('BOT', 'ScenBot'))
    s.command('item replace entity %s enderchest.3 with minecraft:obsidian 5' % os.environ.get('BOT', 'ScenBot'))
    s.command('tp %s 12 90 -34' % os.environ.get('BOT', 'ScenBot'))
    s.wait(lambda: abs(s.position()[0] - 12.0) < 1.5 and abs(s.position()[2] + 34.0) < 1.5, 'the teleport', 20.0)
    s.command('data get entity %s EnderItems' % os.environ.get('BOT', 'ScenBot'))
    s.expect('obsidian', 'the ender chest holds obsidian before saving', 20.0, since=n)
    s.command('save-all')
    s.wait(lambda: True, 'a moment', 1.0)


@scenario('player_roundtrip_check')
def player_roundtrip_check(s):
    """Phase B (after a stop and a restart): the same player rejoins at 12 90 -34, creative, with the diamonds and the ender chest."""
    import os
    if os.environ.get('PHASE') != 'check':
        s.inconclusive('PHASE=check not given')
    bot = os.environ.get('BOT', 'ScenBot')
    s.wait(lambda: s.position() is not None, 'a position', 60.0)
    p = s.position()
    print('  rejoined at %.2f %.2f %.2f' % tuple(p[:3]), flush=True)
    s.check(abs(p[0] - 12.0) < 2.0 and abs(p[2] + 34.0) < 2.0 and p[1] > 60.0, 'the saved position (12, 90, -34) was restored, got %s' % (p[:3],))
    n = len(s.w.chat)
    s.command('data get entity %s Inventory' % bot)
    said = s.expect('diamond', 'the diamonds after the restart', 20.0, since=n)
    s.check('7' in said, 'seven diamonds: %s' % said)
    n = len(s.w.chat)
    s.command('data get entity %s playerGameType' % bot)
    s.wait(lambda: len(s.w.chat) > n, 'the game mode answer', 20.0)
    said = s.w.chat[n]
    print('  game mode answer: %r' % said, flush=True)
    s.check(' %s 1 ' % bot in said or said.rstrip().endswith(' 1'), 'creative game mode (1): %s' % said)
    n = len(s.w.chat)
    s.command('data get entity %s EnderItems' % bot)
    s.expect('obsidian', 'the ender chest kept its obsidian', 20.0, since=n)

@scenario('stop_server')
def stop_server(s):
    """Stops the (scratch) server through its own /stop, the graceful path that saves everything; only when asked for."""
    import os
    if os.environ.get('STOP_SERVER') != '1':
        s.inconclusive('STOP_SERVER=1 not given')
    s.command('stop')
    try:
        s.wait(lambda: False, 'the server to stop', 4.0)
    except Exception:
        pass   # the connection ends with the server: that is the point

@scenario('java_world_join')
def java_world_join(s):
    """A Java-format save (copied): the saved player rejoins where the save put him, with the saved inventory, and chunks load."""
    import os
    if os.environ.get('EXPECT_POS') is None:
        s.inconclusive('EXPECT_POS=x,y,z not given')
    bot = os.environ.get('BOT', 'ScenBot')
    if os.environ['EXPECT_POS'] == 'any':
        # a player the save does not know (the test bot cannot parse the saved player's item components): only the world is checked
        s.wait(lambda: s.position() is not None and s.chunks() > 20, 'chunks of the Java world', 120.0)
        p = s.position()
        x, z = int(p[0]), int(p[2])
        col = [s.block(x, y, z) for y in range(-60, 120)]
        solid = sum(1 for v in col if v)
        print('  joined at %.1f %.1f %.1f, %d chunk columns, %d solid cells in this column of the copied Java world' % (p[0], p[1], p[2], s.chunks(), solid), flush=True)
        s.check(solid > 20, 'the copied Java world has terrain under the spawn')
        return
    ex, ey, ez = [float(v) for v in os.environ['EXPECT_POS'].split(',')]
    s.wait(lambda: s.position() is not None and s.chunks() > 20, 'the saved position and chunks', 120.0)
    p = s.position()
    print('  joined at %.2f %.2f %.2f with %d chunk columns (save says %.2f %.2f %.2f)' % (p[0], p[1], p[2], s.chunks(), ex, ey, ez), flush=True)
    s.check(abs(p[0] - ex) < 1.0 and abs(p[2] - ez) < 1.0, 'the saved position was restored')
    n = len(s.w.chat)
    s.command('data get entity %s Inventory' % bot)
    s.expect(os.environ.get('EXPECT_ITEM', 'sand'), 'the saved inventory', 20.0, since=n)


@scenario('datapack_live')
def datapack_live(s):
    """A pack in world/datapacks (made by run_fabric_live.py): listed, its function runs and its say reaches chat, reload works."""
    import os
    if os.environ.get('EXPECT_DATAPACK') != '1':
        s.inconclusive('EXPECT_DATAPACK=1 not given')
    s.wait(lambda: s.position() is not None, 'a position', 60.0)
    n = len(s.w.chat)
    s.command('datapack list')
    s.expect('livepack', 'the pack in /datapack list', 20.0, since=n)
    s.expect('2 functions, 2 tags, 2 recipes', 'its counts', 5.0, since=n)
    n = len(s.w.chat)
    s.command('function live:hello')
    s.expect('Executed 2 command(s) from function live:hello', 'the function result', 20.0, since=n)
    s.expect('commands.data.entity.query', 'the data command of the function answering the sender', 10.0, since=n)
    n = len(s.w.chat)
    s.command('function live:nothing')
    s.expect('Unknown function', 'an unknown function is refused', 20.0, since=n)
    n = len(s.w.chat)
    s.command('datapack reload')
    s.expect('datapacks: 1 found, 1 loaded', 'reload summary', 20.0, since=n)



@scenario('modsync', needs_plugin='showcase')
def modsync(s):
    """With a jester-mods.json the welcome announces modsync, the manifest arrives in the configuration phase, the join was held for the
    STATUS and the server recorded it (the plugin reports it back)."""
    s.require_plugin()
    welcome = s.config_payloads('jester:welcome')
    s.check(len(welcome) == 1, 'no welcome')
    wl = welcome[0]
    at = 3 + wl[2]
    s.check(wl[at + 9] & 2, 'welcome flags %d: bit1 (modsync follows) is not set' % wl[at + 9])
    manifest = s.config_payloads('jester:modsync')
    s.check(len(manifest) == 1 and manifest[0][0] == 1, 'no MANIFEST in the configuration phase')
    s.check(manifest[0][1] == 0, 'the scenario manifest is advisory, got policy %d' % manifest[0][1])
    s.command('modstate test:present')
    s.expect('Mod test:present: state 0', 'the reported state of the installed mod')
    s.command('modstate test:absent')
    s.expect('Mod test:absent: state 1', 'the reported state of the missing mod')
    s.command('modstate test:nothing')
    s.expect('Mod test:nothing: state -1', 'a mod nobody asked about')


@scenario('physics_js')
def physics_js(s):
    """The same physics API from a JavaScript snippet: material table, wind field and solver over the host functions."""
    s.command('script var m = server.materialByName("stone"); print("jsmat=" + m.known + " " + (m.density > 1000))')
    s.expect('jsmat=true true', 'the material of stone from JS', 30.0)
    s.command('script var w = server.windAt(0, 70, 0); print("jswind=" + (w.speed >= 0))')
    s.expect('jswind=true', 'the wind field from JS', 30.0)
    s.command('script var r = server.solveRegion(0, 200, 0, 4, 4, 4, {floorAnchored: true}); print("jssolve=" + r.ok + " " + r.broken.length)')
    s.expect('jssolve=true 0', 'the solver from JS', 30.0)


@scenario('physics_api', needs_plugin='showcase')
def physics_api(s):
    """A plugin reaches the material table, the wind field and the structural solver."""
    s.require_plugin()
    s.command('physapi')
    s.expect('Physics material: stone known=true dense=true air=true', 'the material table', 30.0)
    s.expect('Physics wind: ok=true massOfStone=true', 'the wind field and mass', 30.0)
    s.expect('Physics solve: ok=true broken=0', 'the structural solver', 30.0)


def run(m, c, st, w, biomes, ctx, args):
    wanted = [n for n in (args.scenario or 'all').split(',') if n]
    known = [n for n, _, _ in SCENARIOS]
    for n in wanted:
        if n != 'all' and n not in known:
            raise m.Fail('no scenario %r (have: %s)' % (n, ', '.join(known)))
    s = Scn(m, c, st, w, biomes, ctx, args)
    results = []
    for name, needs, fn in SCENARIOS:
        if ('all' not in wanted or name in EXPLICIT_ONLY) and name not in wanted:
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


# ---- live verification of features that were only unit tested (docs/PACKS.md, CREATE_PORT.md, DESIGN_20_HOSTING.md, FABRIC_GAPS.md) ----
# Needs a server started with PACKS_FROM=examples/packs and DATAPACK_FROM=tools/live_fixtures/datapacks (tools/run_scenarios.sh).

def _pause(s, seconds):
    """Waits while still reading the connection (time.sleep would let the server's packets pile up unread)."""
    until = time.time() + seconds
    s.wait(lambda: time.time() >= until, 'a pause', seconds + 10.0)


def _say(s, line, fragment, what, seconds=20.0):
    """Runs a command and returns the chat line that holds `fragment` (only lines that arrived after the command)."""
    n = len(s.w.chat)
    s.command(line)
    try:
        return s.expect(fragment, what, seconds, since=n)
    except Exception:
        print('  chat since %r: %r' % (line, s.w.chat[n:]))
        raise


def _reply(s, line, wait=1.5):
    """Runs a command, waits a moment and returns every chat line it produced."""
    n = len(s.w.chat)
    s.command(line)
    _pause(s, wait)
    return list(s.w.chat[n:])


def _ready(s):
    s.wait(lambda: s.position() is not None and s.chunks() >= 9, 'the spawn chunks', 60.0)
    s.command('gamemode creative')
    _pause(s, 0.5)


def _body_mass(s, x, y, z):
    """Builds a 2x2x2 stone cube at x y z (open air high up), makes it a body, returns (id, mass kg, info) from /body info."""
    s.command('fill %d %d %d %d %d %d minecraft:stone' % (x, y, z, x + 1, y + 1, z + 1))
    s.wait(lambda: s.w.block(x, y, z) not in (None, 0) and s.w.block(x + 1, y + 1, z + 1) not in (None, 0), 'the stone cube', 20.0)
    line = _say(s, 'body assemble %d %d %d %d %d %d' % (x, y, z, x + 1, y + 1, z + 1), 'ody', 'body assemble')
    n = len(s.w.chat)
    s.command('body list')
    _pause(s, 1.0)
    out = ' | '.join(s.w.chat[n:])
    ids = re.findall(r'(?:body|#)\s*(\d+)', line + ' | ' + out)
    s.check(ids, 'no body id in %r / %r' % (line, out))
    bid = ids[-1]
    n = len(s.w.chat)
    s.command('body info %s' % bid)
    _pause(s, 1.2)
    info = ' | '.join(s.w.chat[n:])
    m_ = re.search(r'mass\D{0,12}([0-9]+(?:\.[0-9]+)?)', info)
    s.check(m_ is not None, 'no mass in /body info: %r (assemble said %r, list %r)' % (info, line, out))
    return bid, float(m_.group(1)), info


@scenario('packs_live')
def packs_live(s):
    """examples/packs/example_pack is loaded at start (stone density 300, commands /rules and /echo2); /packs info shows it;
    a body of 8 stone cells weighs 8 * 300 kg with the pack and 8 * 5000 after materials.json changed on disk and /packs reload ran; with
    the pack removed and reloaded the stone is back at its default density; a pack with a bad number is refused and the rest still loads."""
    _ready(s)
    import os, shutil
    lst = _reply(s, 'packs list')
    print('  /packs list: %r' % lst)
    s.check(any('example_pack' in l and 'active' in l for l in lst), '/packs list does not show example_pack active: %r' % lst)
    info = _reply(s, 'packs info example_pack')
    print('  /packs info: %r' % info)
    s.check(any('example_pack' in l for l in info) and any('materials' in l for l in info), '/packs info lacks the pack or its materials: %r' % info)
    bare_rules = _reply(s, 'rules', 2.0)           # a command with no arguments must be runnable, not only `/rules <text>`
    print('  bare /rules: %r' % [l for l in bare_rules if 'scoreboard' not in l])
    bare_ok = any('bridges' in l for l in bare_rules)
    r = _say(s, 'rules now', 'Rules:', '/rules now from commands.json') if not bare_ok else ''
    n = len(s.w.chat)
    s.command('echo2 hello there')
    s.wait(lambda: sum(1 for l in s.w.chat[n:] if 'hello there' in l) >= 2, '/echo2 answers the text twice', 15.0)
    px, py, pz = s.position()[0], s.position()[1], s.position()[2]
    x, z = int(px // 1) + 4, int(pz // 1) + 4
    y = 220
    s.command('fill %d %d %d %d %d %d minecraft:air' % (x - 1, y - 1, z - 1, x + 12, y + 4, z + 4))
    _pause(s, 1.0)
    bid1, m1, info1 = _body_mass(s, x, y, z)
    print('  mass with the pack stone=300: %s kg (%s)' % (m1, info1))
    s.check(abs(m1 - 8 * 300) < 1.0, 'stone density 300 from the pack should give 2400 kg for 8 cells, got %s' % m1)
    s.command('body settle %s' % bid1)
    _pause(s, 1.0)
    mf = os.path.join('packs', 'example_pack', 'materials.json')
    orig = open(mf).read()
    off = '_example_off'          # outside packs/ (a folder in there would be discovered as a pack of the same id)
    try:
        open(mf, 'w').write(orig.replace('"density": 300', '"density": 5000'))
        rep = _reply(s, 'packs reload', 2.5)
        print('  /packs reload: %r' % rep)
        s.check(any('1 active' in l for l in rep), 'reload did not report 1 active pack: %r' % rep)
        bid2, m2, _ = _body_mass(s, x + 4, y, z)
        print('  mass after density 5000 + reload: %s kg' % m2)
        s.check(abs(m2 - 8 * 5000) < 1.0, 'reload should change stone to 5000 -> 40000 kg, got %s' % m2)
        s.command('body settle %s' % bid2)
        _pause(s, 1.0)
        bad = os.path.join('packs', 'bad_pack')
        os.makedirs(bad, exist_ok=True)
        open(os.path.join(bad, 'pack.json'), 'w').write('{"format":1,"id":"bad_pack","name":"bad"}')
        open(os.path.join(bad, 'materials.json'), 'w').write('{"blocks":{"minecraft:stone":{"damping":7}}}')
        rep = _reply(s, 'packs reload', 2.5)
        print('  reload with a bad pack: %r' % rep)
        s.check(any('ERROR' in l and 'bad_pack' in l for l in rep), 'no ERROR line for bad_pack: %r' % rep)
        s.check(any('1 active' in l for l in rep), 'the good pack is no longer the one active pack: %r' % rep)
        shutil.rmtree(bad)
        shutil.move(os.path.join('packs', 'example_pack'), off)
        _reply(s, 'packs reload', 2.5)
        bid3, m3, _ = _body_mass(s, x + 8, y, z)
        print('  mass with no pack: %s kg' % m3)
        s.check(m3 > 1000 and abs(m3 - 2400) > 1.0 and abs(m3 - 40000) > 1.0, 'default stone density expected, got %s' % m3)
        s.command('body settle %s' % bid3)
    finally:
        if os.path.isdir(off):
            shutil.move(off, os.path.join('packs', 'example_pack'))
        open(mf, 'w').write(orig)
        shutil.rmtree(os.path.join('packs', 'bad_pack'), ignore_errors=True)
    rep = _reply(s, 'packs reload', 2.0)
    s.check(any('1 active' in l for l in rep), 'restoring the pack did not make it active again: %r' % rep)
    s.check(bare_ok, 'bare /rules (a pack command with no arguments) is "unknown argument"; only /rules <text> ran')


@scenario('invite_live')
def invite_live(s):
    """/invite <ip> <port> prints a code and /invite decode <code> shows the same address back; several addresses and ports round trip;
    garbage is refused with a message."""
    _ready(s)
    for ip, port in (('192.168.1.5', 25565), ('10.0.0.7', 1), ('203.0.113.250', 65535), ('8.8.4.4', 25690)):
        line = _say(s, 'invite %s %d' % (ip, port), 'invite code for', '/invite %s %d' % (ip, port))
        s.check('%s:%d' % (ip, port) in line, 'invite line names another address: %r' % line)
        code = line.rsplit(': ', 1)[1].strip()
        s.check(len(code) >= 8, 'code looks empty: %r' % line)
        back = _say(s, 'invite decode %s' % code, 'invite points at', '/invite decode')
        s.check('%s:%d' % (ip, port) in back, 'decode of %s gave %r' % (code, back))
        print('  %s:%d -> %s -> %s' % (ip, port, code, back))
    rep = _reply(s, 'invite decode notacode!!', 1.5)
    s.check(any('invite' in l.lower() for l in rep) and not any('points at' in l for l in rep), 'garbage code not refused: %r' % rep)
    rep = _reply(s, 'invite 999.1.1.1 25565', 1.5)
    s.check(not any('invite code for' in l for l in rep), 'an invalid IPv4 produced a code: %r' % rep)
    rep = _reply(s, 'invite 1.2.3.4 70000', 1.5)
    s.check(not any('invite code for' in l for l in rep), 'port 70000 produced a code: %r' % rep)


def _gametime(s):
    n_ = len(s.w.chat)
    s.command('time query gametime')
    _pause(s, 0.8)
    for l_ in s.w.chat[n_:]:
        m_ = re.search(r'(\d+)\s*$', l_) if 'scoreboard' not in l_ else None
        if m_:
            return int(m_.group(1))
    return None


def _score(s, holder, obj, stamp=None):
    n = len(s.w.chat)
    if stamp is not None:
        stamp.append(time.time())
    s.command('scoreboard players get %s %s' % (holder, obj))
    _pause(s, 0.8)
    for l in s.w.chat[n:]:
        m_ = re.search(r'has (-?\d+)', l)
        if m_ and holder in l:
            return int(m_.group(1))
    return None


@scenario('datapack_tick_live')
def datapack_tick_live(s):
    """tools/live_fixtures/datapacks/ticktest: #minecraft:load ran at start (score #loads = 1), #minecraft:tick adds 1 to #t every server
    tick (about 20 per second of wall time), /function runs a function by hand, and /datapack reload runs #load again (a marker set by
    hand is overwritten) while the tick function keeps running."""
    _ready(s)
    lst = _reply(s, 'datapack list')
    print('  /datapack list: %r' % lst)
    s.check(any('ticktest' in l for l in lst), 'ticktest pack not listed: %r' % lst)
    loads = _score(s, '#loads', 'ticks')
    s.check(loads == 1, '#minecraft:load did not run at start: #loads=%r' % loads)
    # the score and the game clock are read by two commands: their growth must agree (the tick function runs once per tick)
    t_a = _score(s, '#t', 'ticks')
    g_a = _gametime(s)
    _pause(s, 5.0)
    t_b = _score(s, '#t', 'ticks')
    g_b = _gametime(s)
    s.check(None not in (t_a, t_b, g_a, g_b), 'no score or game time answer: %r' % [t_a, t_b, g_a, g_b])
    print('  #t %d -> %d (+%d) while the game clock went %d -> %d (+%d ticks)' % (t_a, t_b, t_b - t_a, g_a, g_b, g_b - g_a))
    s.check(abs((t_b - t_a) - (g_b - g_a)) <= 30 and (t_b - t_a) > 60, 'the tick function did not run once per tick')
    _say(s, 'function ticktest:hello', 'Executed 2 command', '/function ticktest:hello')
    s.check(_score(s, '#hello', 'ticks') == 1, '/function did not run the line that adds to #hello')
    s.command('scoreboard players set #loads ticks 77')
    _pause(s, 0.5)
    s.check(_score(s, '#loads', 'ticks') == 77, 'could not set the marker')
    rep = _reply(s, 'datapack reload', 2.0)
    print('  /datapack reload: %r' % rep)
    s.check(_score(s, '#loads', 'ticks') == 1, '/datapack reload did not run #minecraft:load again')
    t_c = _score(s, '#t', 'ticks')
    _pause(s, 1.0)
    s.check(_score(s, '#t', 'ticks') > t_c, 'the tick function stopped after /datapack reload')


_ITEM = {}


def _item_pos(s):
    """Position of the platform's rider item from `/data get entity` (the first call pins the nearest item by UUID), or None."""
    n = len(s.w.chat)
    sel = _ITEM.get('uuid') or '@e[type=item,limit=1,sort=nearest]'
    s.command('data get entity %s Pos' % sel)
    _pause(s, 0.7)
    for l in s.w.chat[n:]:
        if 'scoreboard' in l or '[' not in l:
            continue
        if 'uuid' not in _ITEM:
            u = re.search(r'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})', l)
            if u:
                _ITEM['uuid'] = u.group(1)
        m_ = re.findall(r'(-?\d+(?:\.\d+)?(?:E-?\d+)?)\s*(?:gold )?d', l.split('[', 1)[1])
        if len(m_) >= 3:
            return tuple(float(v) for v in m_[:3])
    print('  no item data in %r' % [l for l in s.w.chat[n:] if 'scoreboard' not in l])
    return None


@scenario('create_live')
def create_live(s):
    """/create on a real server: a motor beside a gearbox drives a bearing, the 5x5 platform above it becomes ONE body that turns
    (`/create status` turned angle grows at the commanded rpm, the status line says 'running'), a dropped item standing on the platform is
    carried round the pivot (its radius stays, its angle follows the platform), `/create scan|speed` report the network, and
    `/create release` at the end puts the blocks back (25 again in the footprint, none left in the air)."""
    _ready(s)
    px, py, pz = s.position()[0], s.position()[1], s.position()[2]
    cx, cz = int(px // 1) + 6, int(pz // 1) + 6
    y = 220
    s.command('fill %d %d %d %d %d %d minecraft:air' % (cx - 4, y - 2, cz - 4, cx + 4, y + 6, cz + 4))
    _pause(s, 1.0)
    s.command('fill %d %d %d %d %d %d minecraft:stone' % (cx - 2, y + 1, cz - 2, cx + 2, y + 1, cz + 2))
    s.command('setblock %d %d %d minecraft:copper_block' % (cx, y - 1, cz))       # the gearbox stand-in
    s.wait(lambda: s.w.block(cx, y + 1, cz) not in (None, 0) and s.w.block(cx, y - 1, cz) not in (None, 0), 'the rig', 20.0)
    r = _say(s, 'create motor %d %d %d 12 east' % (cx - 1, y - 1, cz), 'Motor', '/create motor')
    print('  ' + r)
    r = _say(s, 'create bearing %d %d %d up %d %d %d %d %d %d' % (cx, y, cz, cx - 2, y + 1, cz - 2, cx + 2, y + 1, cz + 2), 'earing', '/create bearing')
    print('  ' + r)
    s.check('25 blocks' in r, 'the platform did not become one 25 block body: %r' % r)
    sc = _reply(s, 'create scan', 1.0)
    print('  scan: %r' % [l for l in sc if 'scoreboard' not in l])
    s.check(any('running' in l for l in sc), 'scan does not report a running network: %r' % sc)
    sp = _reply(s, 'create speed %d %d %d' % (cx, y - 1, cz), 1.0)
    print('  speed: %r' % [l for l in sp if 'scoreboard' not in l])
    speed_ok = any('12' in l and 'rpm' in l for l in sp)

    def status():
        lines = _reply(s, 'create status', 0.8)
        for l in lines:
            m_ = re.search(r'turned (-?[0-9.]+) degrees, riders carried last tick (\d+)', l)
            if m_:
                return float(m_.group(1)), int(m_.group(2)), l
        return None, None, lines

    a0, _, l0 = status()
    s.check(a0 is not None, 'no bearing line in /create status: %r' % (l0,))
    # an item on the platform (top surface y+2), 1.5 blocks from the pivot axis
    ix, iz = cx + 0.5 + 1.5, cz + 0.5
    _ITEM.clear()
    s.command('kill @e[type=item]')
    _pause(s, 0.4)
    s.command('summon item %.2f %.2f %.2f {Item:{id:"minecraft:cobblestone",count:1},PickupDelay:32767}' % (ix, y + 2.0, iz))
    _pause(s, 0.3)
    # the server is frozen and stepped in exact blocks of 25 ticks (= 90 degrees at 12 rpm), so the numbers do not depend on wall time
    s.command('tick freeze')
    _pause(s, 0.8)
    s.command('tick step 5')
    _pause(s, 1.0)
    samples = []
    a_first, _, _ = status()
    for k in range(7):
        p = _item_pos(s)
        a, carried, _l = status()
        samples.append((k * 25, p, a, carried))
        s.command('tick step 25')
        _pause(s, 2.0)
    s.command('tick unfreeze')
    print('  samples (ticks stepped, item pos, turned deg, carried): %r' % samples)
    s.check(all(sm[2] is not None for sm in samples), 'status unreadable')
    per = [samples[k + 1][2] - samples[k][2] for k in range(len(samples) - 1)]
    print('  turned per 25 ticks: %r (12 rpm = -90.0 each)' % per)
    s.check(all(abs(p_ + 90.0) < 0.6 for p_ in per), 'the platform does not turn 90 degrees per 25 ticks at 12 rpm: %r' % per)
    turned = samples[-1][2] - samples[0][2]
    pts = [sm[1] for sm in samples if sm[1] is not None]
    s.check(len(pts) >= 5, 'could not read the item position: %r' % [sm[1] for sm in samples])
    import math
    rad = [math.hypot(p[0] - (cx + 0.5), p[2] - (cz + 0.5)) for p in pts]
    ang = [math.degrees(math.atan2(p[2] - (cz + 0.5), p[0] - (cx + 0.5))) for p in pts]
    print('  item radius %r angle %r' % ([round(v, 2) for v in rad], [round(v, 1) for v in ang]))
    swing = max(abs(((a - ang[0] + 180) % 360) - 180) for a in ang)
    # the item's own angle against the platform's: both advance together (compare the change between the first and the last sample)
    d_item = ((ang[-1] - ang[0] + 180) % 360) - 180
    d_plat = -(samples[-1][2] - samples[0][2])           # (kept below)           # a negative yaw delta in Minecraft = counter clockwise seen from above
    print('  item angle change %.1f (mod 360), platform %.1f (mod 360)' % (d_item, d_plat % 360))
    s.check(abs((((d_item - d_plat) + 180) % 360) - 180) < 15.0, 'the item angle follows the platform: item %.1f platform %.1f' % (d_item, d_plat % 360))
    s.check(swing > 40.0, 'the item was not carried round: its angle moved only %.1f degrees while the platform turned %.1f' % (swing, abs(turned)))
    s.check(all(abs(r_ - 1.5) < 0.35 for r_ in rad), 'the item left its circle (radius %r)' % rad)
    s.check(abs(pts[-1][1] - (y + 2.0)) < 0.6, 'the item fell off the platform: y=%.2f' % pts[-1][1])
    # release: the blocks come back
    _say(s, 'create release %d %d %d' % (cx, y, cz), 'released', '/create release')
    _pause(s, 1.0)
    s.wait(lambda: sum(1 for xx in range(cx - 3, cx + 4) for zz in range(cz - 3, cz + 4) if s.w.block(xx, y + 1, zz) not in (None, 0)) == 25,
           'the 25 platform blocks to be back in the footprint', 20.0)
    s.command('kill @e[type=item]')
    s.command('create clear')
    s.check(speed_ok, '/create speed on the gearbox gave %r instead of 12 rpm (the scan itself said running)' % [l for l in sp if 'scoreboard' not in l])
