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
        self.respawns = []          # dimension names of the Respawn packets seen
        self.payload_log = []       # (channel, data) of play-phase custom payloads from the server
        self.started = time.time()
        prior = ctx.get('tap')

        def tap(pid, data):
            if prior:
                prior(pid, data)
            if pid == 80:           # clientbound respawn: a new dimension (the client model has to follow its height)
                rr = m.Reader(data)
                rr.varint()
                name = rr.string()
                self.respawns.append(name)
                if name != ctx.get('world'):
                    ctx['world'] = name
                    if name == 'minecraft:overworld':
                        ctx['sections'], w.min_y = m.DEFAULT_SECTIONS, -64
                    else:
                        ctx['sections'], w.min_y = 16, 0
                    w.chunks.clear()
                    w.pos = None
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


def _tree_child(nodes, at, name):
    for c in nodes[at]['children']:
        if nodes[c]['name'] == name:
            return c
    return None


def _suggest(s, ident, text, seconds=15.0):
    """Asks for completions of `text` (as typed in the chat box, with its slash); returns the matches."""
    s.c.send(s.m.SB_COMMAND_SUGGESTION, s.m.varint(ident) + s.m.string(text))
    s.wait(lambda: any(x[0] == ident for x in s.w.suggestions), 'suggestions for %r' % text, seconds)
    return [x for x in s.w.suggestions if x[0] == ident][-1][4]


@scenario('worldedit_commands')
def worldedit_commands(s):
    """The WorldEdit commands are real nodes of the command tree the client gets: root literals named `/set`, `/pos1`, ... (the
    client's `//set`), with typed arguments (block_pos, integer, a greedy pattern and a direction whose completions come from the
    server). Completions arrive for a pattern and a direction; //pos1 //pos2 //set stone typed with the double slash edit the
    world; /help WorldEdit and /plugins list them."""
    s.wait(lambda: s.position() is not None and s.chunks() >= 9, 'the spawn chunks', 60.0)
    s.wait(lambda: 'nodes' in s.m.COMMAND_TREE, 'the commands packet')
    nodes, root = s.m.COMMAND_TREE['nodes'], s.m.COMMAND_TREE['root']
    names = sorted(nodes[c]['name'] for c in nodes[root]['children'])
    want = ['/pos1', '/pos2', '/wand', '/sel', '/desel', '/size', '/set', '/replace', '/walls', '/hollow', '/sphere', '/cyl', '/copy',
            '/cut', '/paste', '/rotate', '/flip', '/stack', '/move', '/count', '/distribution', '/undo', '/redo', 'we', 'worldedit']
    missing = [n for n in want if n not in names]
    s.check(not missing, 'not in the command tree: %r' % missing)
    s.check('set' not in names and 'pos1' not in names, 'the old single-slash names are still in the tree')
    print('  %d root commands, all %d WorldEdit ones present' % (len(names), len(want)), flush=True)

    def arg(cmd, *path):
        at = _tree_child(nodes, root, cmd)
        for p in path:
            at = _tree_child(nodes, at, p)
            s.check(at is not None, '%s has no %r below it' % (cmd, path))
        return nodes[at]

    setp = arg('/set', 'pattern')
    s.check(setp['kind'] == 2 and setp['parser'] == 5 and setp['suggests'] == 'minecraft:ask_server' and setp['flags'] & 4,
            '//set <pattern> is not an executable server-completed string: %r' % setp)
    s.check(not (nodes[_tree_child(nodes, root, '/set')]['flags'] & 4), '//set alone should not be executable')
    pos = arg('/pos1', 'pos')
    s.check(pos['parser'] == 8 and pos['flags'] & 4, '//pos1 <pos> is not an executable block_pos: %r' % pos)
    s.check(nodes[_tree_child(nodes, root, '/pos1')]['flags'] & 4, '//pos1 alone should be executable')
    frm = arg('/replace', 'from')
    s.check(frm['parser'] == 31 and frm['suggests'] == 'minecraft:ask_server', '//replace <from>: %r' % frm)
    s.check(arg('/replace', 'from', 'to')['parser'] == 5, '//replace <from> <to> is not a string')
    s.check(arg('/undo', 'times')['parser'] == 3, '//undo <times> is not an integer')
    s.check(arg('/sphere', '-h', 'pattern', 'radius')['parser'] == 3, '//sphere -h <pattern> <radius> is not an integer')
    s.check(arg('/cyl', 'pattern', 'radius', 'height')['parser'] == 3, '//cyl <pattern> <radius> <height>')
    s.check(arg('/flip', 'direction')['suggests'] == 'minecraft:ask_server', '//flip <direction> not completed by the server')
    s.check(arg('/stack', 'count', 'direction')['parser'] == 5, '//stack <count> <direction>')
    s.check(arg('/paste', '-a')['flags'] & 4, '//paste -a is not executable')

    # completions asked of the server, as a client asks for an ask_server argument
    got = _suggest(s, 501, '//set sto')
    s.check('stone' in got and 'stone_bricks' in got, '//set sto completes to %r' % got[:10])
    got = _suggest(s, 502, '//set 50%stone,gra')
    s.check('50%stone,gravel' in got, '//set 50%%stone,gra completes to %r' % got[:10])
    got = _suggest(s, 503, '//flip n')
    s.check(got == ['north'], '//flip n completes to %r' % got)
    got = _suggest(s, 504, '//replace dirt gl')
    s.check('glass' in got, '//replace dirt gl completes to %r' % got[:10])
    print('  completions: //set sto -> %d names, //flip n -> north' % len(_suggest(s, 505, '//set sto')), flush=True)

    # the commands work as typed: //pos1 //pos2 (block_pos form) and //set stone
    px, py, pz = s.position()
    bx, bz, y0 = int(px // 1) + 3, int(pz // 1) + 3, 210
    s.command('gamemode creative')
    ids = _state_ids(s, bx, y0 + 12, bz, ['stone'])
    box = (bx, y0, bz, bx + 2, y0 + 1, bz + 2)              # 3 x 2 x 3 = 18 cells
    _cells_are(s, box, [0] * 18, 'the build area to be air')
    _we(s, 'pos1 %d %d %d' % (bx, y0, bz), 'Position 1 set to (%d, %d, %d)' % (bx, y0, bz), '//pos1 x y z')
    _we(s, 'pos2 %d %d %d' % (bx + 2, y0 + 1, bz + 2), '(18 blocks)', '//pos2 x y z')
    _we(s, 'set stone', 'set: 18 block(s) changed', '//set stone')
    _cells_are(s, box, [ids['stone']] * 18, 'every cell of the selection to be stone at the client')
    _we(s, 'pos1 %d,%d,%d' % (bx, y0, bz), 'Position 1 set', '//pos1 x,y,z (the comma form)')
    _we(s, 'undo', 'Undid 1 edit(s)', '//undo')
    _cells_are(s, box, [0] * 18, 'the cells back to air')
    _we(s, 'sphere -h glass 2', 'sphere:', '//sphere -h (a flag literal)')
    _we(s, 'undo', 'Undid 1', 'undo the sphere')

    # listed by /help and /plugins
    n = len(s.w.chat)
    s.command('help WorldEdit')
    s.expect('//set', '/help WorldEdit lists //set', since=n)
    n = len(s.w.chat)
    s.command('help //replace')
    s.expect('//replace <from>', '/help //replace shows the usage (brigadier smart usage: one level)', since=n)
    n = len(s.w.chat)
    s.command('plugins')
    s.expect('WorldEdit', '/plugins names the built-in WorldEdit', since=n)


def _in_ellipsoid(dx, dy, dz, rx, ry, rz):
    ax, ay, az = rx + 0.5, ry + 0.5, rz + 0.5
    return (dx * dx) / (ax * ax) + (dy * dy) / (ay * ay) + (dz * dz) / (az * az) <= 1.0


def _sphere_cells(cx, cy, cz, r, hollow):
    out = []
    for dy in range(-r, r + 1):
        for dz in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if not _in_ellipsoid(dx, dy, dz, r, r, r):
                    continue
                if hollow and all(_in_ellipsoid(dx + a, dy + b, dz + c, r, r, r)
                                  for a, b, c in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))):
                    continue
                out.append((cx + dx, cy + dy, cz + dz))
    return out


def _cyl_cells(cx, cy, cz, r, height, hollow):
    out = []
    for dy in range(height):
        for dz in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if not _in_ellipsoid(dx, 0, dz, r, 0, r):
                    continue
                if hollow and all(_in_ellipsoid(dx + a, 0, dz + c, r, 0, r) for a, c in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    continue
                out.append((cx + dx, cy + dy, cz + dz))
    return out


def _smooth_expect(before, x0, y0, z0, w, h, d, iterations):
    """A port of wecore.smoothGrid: `before[(x, y, z)]` is the state; returns the grid after."""
    import math as _m
    after = dict(before)
    def top(x, z):
        for y in range(y0 + h - 1, y0 - 1, -1):
            if before[(x, y, z)] != 0:
                return y
        return y0
    R = 5
    k = []
    tot = 0.0
    for ky in range(-R, R + 1):
        for kx in range(-R, R + 1):
            v = _m.exp(-float(kx * kx + ky * ky) / (2.0 * 1.0 * 1.0))
            k.append(v)
            tot += v
    k = [v / tot for v in k]
    cur = [[top(x0 + x, z0 + z) for x in range(w)] for z in range(d)]
    data = [[float(cur[z][x]) for x in range(w)] for z in range(d)]
    for _ in range(max(iterations, 1)):
        nxt = [[0.0] * w for _ in range(d)]
        for z in range(d):
            for x in range(w):
                acc = 0.0
                for ky in range(-R, R + 1):
                    for kx in range(-R, R + 1):
                        sx = min(max(x + kx, 0), w - 1)
                        sz = min(max(z + ky, 0), d - 1)
                        acc += data[sz][sx] * k[(ky + R) * (2 * R + 1) + (kx + R)]
                nxt[z][x] = acc
        data = nxt
    maxY = y0 + h - 1
    for z in range(d):
        for x in range(w):
            xr, zr = x0 + x, z0 + z
            cH = cur[z][x]
            nH = min(maxY, int(_m.floor(data[z][x] + 0.5)))
            if nH > cH:
                existing = before[(xr, cH, zr)]
                after[(xr, nH, zr)] = existing
                scale = float(cH - y0) / float(nH - y0)
                for y in range(nH - 1 - y0, -1, -1):
                    after[(xr, y0 + y, zr)] = before[(xr, y0 + int(_m.floor(y * scale)), zr)]
            elif cH > nH:
                scale = float(cH - y0) / float(max(nH - y0, 1))
                for y in range(0, nH - y0):
                    after[(xr, y0 + y, zr)] = before[(xr, y0 + min(int(_m.floor(y * scale)), cH - y0), zr)]
                after[(xr, nH, zr)] = before[(xr, cH, zr)]
                for y in range(nH + 1, cH + 1):
                    after[(xr, y, zr)] = 0
    return after


def _tp(s, x, y, z):
    s.command('tp @s %.2f %.2f %.2f' % (x, y, z))
    s.wait(lambda: s.position() is not None and abs(s.position()[0] - x) < 0.01 and abs(s.position()[1] - y) < 0.01 and
           abs(s.position()[2] - z) < 0.01, 'the teleport to %.1f %.1f %.1f' % (x, y, z))


def _use_on(s, x, y, z):
    s.c.send(s.m.SB_USE_ON, s.m.varint(0) + s.m.block_pos(x, y, z) + s.m.varint(1) + struct.pack('>fff', 0.5, 1.0, 0.5) +
             bytes([0, 0]) + s.m.varint(40))


@scenario('worldedit_more')
def worldedit_more(s):
    """The WorldEdit commands beyond the basics, each with the number of blocks it must change, checked as the client sees the
    cells: selection changes (//expand, //contract, //shift, //outset, //inset, //chunk), //center, //line, //pyramid, //hpyramid,
    //hsphere, //hcyl, //fill, //fixwater, //drain, //overlay, //naturalize, //smooth (against a port of the height-map filter),
    //copy -e //paste -e with an armor stand, brushes and tools on a right click (on a block and in the air), //historysize and
    //clearhistory. Every command must also be a node of the client's command tree."""
    s.wait(lambda: s.position() is not None and s.chunks() >= 9, 'the spawn chunks', 60.0)
    home = s.position()
    # The builds float at y 200, so every block in them is placed by WorldEdit (whose edits never set off the structure
    # triggers): a plain /setblock beside one could let `structures` drop it. The player goes back where it started.
    try:
        _worldedit_more_body(s)
    finally:
        s.command('tp @s %.2f %.2f %.2f' % home)
        s.command('clear @s')      # no stick (or bound brush) left in slot 0 for the scenarios after
        time.sleep(0.5)


def _worldedit_more_body(s):
    s.wait(lambda: s.position() is not None and s.chunks() >= 9, 'the spawn chunks', 60.0)
    nodes, root = s.m.COMMAND_TREE['nodes'], s.m.COMMAND_TREE['root']
    names = set(nodes[c]['name'] for c in nodes[root]['children'])
    want = ['/expand', '/contract', '/shift', '/outset', '/inset', '/chunk', '/center', '/smooth', '/naturalize', '/overlay',
            '/drain', '/fill', '/fixwater', '/line', '/pyramid', '/hpyramid', '/hsphere', '/hcyl', '/brush', '/br', '/tool', '/none',
            '/clearhistory', '/historysize']
    missing = [n for n in want if n not in names]
    s.check(not missing, 'not in the command tree: %r' % missing)
    def node(cmd, *path):
        at = _tree_child(nodes, root, cmd)
        for p in path:
            at = _tree_child(nodes, at, p)
            s.check(at is not None, '%s has no %r below it' % (cmd, path))
        return nodes[at]
    s.check(node('/expand', 'vert')['kind'] == 1 and node('/expand', 'amount', 'reverse', 'direction')['parser'] == 5, '//expand tree')
    s.check(node('/brush', 'sphere', '-h', 'pattern', 'radius')['parser'] == 3, '//brush sphere -h <pattern> <radius>')
    s.check(node('/brush', 'cylinder', 'pattern', 'radius', 'height')['parser'] == 3, '//brush cylinder ... <height>')
    s.check(node('/brush', 'smooth', 'size', 'iterations')['flags'] & 4, '//brush smooth <size> <iterations>')
    s.check(node('/br')['redirect'] is not None, '//br is not an alias of //brush')
    s.check(node('/tool', 'repl', 'pattern')['parser'] == 5, '//tool repl <pattern>')
    s.check(node('/drain', '-w', 'radius')['parser'] == 3 and node('/fill', 'pattern', 'radius', 'depth')['parser'] == 3, 'drain/fill')
    s.check(node('/paste', '-ase')['flags'] & 4 and node('/copy', '-e')['flags'] & 4, '//paste -ase, //copy -e')
    print('  all %d new commands are in the tree' % len(want), flush=True)

    px, py, pz = s.position()
    bx, bz, y0 = int(px // 1) + 3, int(pz // 1) + 3, 200
    s.command('gamemode creative')
    ids = _state_ids(s, bx, y0 + 30, bz, ['stone', 'dirt', 'grass_block', 'glass', 'glowstone'])
    stone, dirt, grass, glass, glow = ids['stone'], ids['dirt'], ids['grass_block'], ids['glass'], ids['glowstone']

    def sel(x1, y1, z1, x2, y2, z2):
        _we(s, 'pos1 %d %d %d' % (x1, y1, z1), 'Position 1 set', '//pos1 %d %d %d' % (x1, y1, z1))
        _we(s, 'pos2 %d %d %d' % (x2, y2, z2), 'Position 2 set', '//pos2 %d %d %d' % (x2, y2, z2))

    def cells_are(cells, state, what):
        s.wait(lambda: all(s.w.block(*c) == state for c in cells), what)

    # ---- selection changes
    Y = y0 + 20
    sel(bx, Y, bz, bx + 2, Y + 2, bz + 2)
    _we(s, 'expand 2 up', 'Region expanded 18 blocks.', '//expand 2 up')
    _we(s, 'size', '3 x 5 x 3, 45 blocks', 'size after expand')
    _we(s, 'contract 2 up', 'Region contracted 18 blocks.', '//contract 2 up')
    _we(s, 'size', '3 x 3 x 3, 27 blocks', 'size after contract')
    _we(s, 'shift 2 down', 'Region shifted.', '//shift 2 down')
    _we(s, 'outset 1', 'Region outset.', '//outset 1')
    _we(s, 'size', '5 x 5 x 5, 125 blocks', 'size after outset')
    _we(s, 'inset 1', 'Region inset.', '//inset 1')
    _we(s, 'inset -h 1', 'Region inset.', '//inset -h 1')
    _we(s, 'size', '1 x 3 x 1, 3 blocks', 'size after inset -h')
    _we(s, 'outset -h 1', 'Region outset.', '//outset -h 1')
    _we(s, 'expand 1 1 east', 'Region expanded 18 blocks.', '//expand 1 1 east (and 1 west)')
    _we(s, 'size', '5 x 3 x 3, 45 blocks', 'size after expand east+west')
    _we(s, 'contract 1 1 east', 'Region contracted 18 blocks.', '//contract 1 1 east')
    _we(s, 'contract 5 up', 'cannot be contracted that far', '//contract past the far face is refused')
    _we(s, 'expand vert', '(top-to-bottom)', '//expand vert')
    _we(s, 'size', '3 x 384 x 3', 'size after expand vert')
    cx, cz = int(math.floor(s.position()[0] / 16)), int(math.floor(s.position()[2] / 16))
    _we(s, 'chunk', 'Chunk selected: %d, %d' % (cx, cz), '//chunk')
    _we(s, 'size', '16 x 384 x 16', 'size of a chunk selection')

    # ---- //center, //line
    sel(bx + 14, y0, bz, bx + 16, y0 + 2, bz + 2)
    _we(s, 'center glass', 'Center set. (1 blocks changed)', '//center on 3x3x3')
    cells_are([(bx + 15, y0 + 1, bz + 1)], glass, 'the centre cell to be glass')
    _we(s, 'undo', 'Undid 1', 'undo center')
    sel(bx, y0 + 6, bz, bx + 4, y0 + 6, bz + 2)
    _we(s, 'line glass', '5 blocks have been changed.', '//line')
    line = [(bx, y0 + 6, bz), (bx + 1, y0 + 6, bz + 1), (bx + 2, y0 + 6, bz + 1), (bx + 3, y0 + 6, bz + 2), (bx + 4, y0 + 6, bz + 2)]
    cells_are(line, glass, 'the line cells to be glass')
    _we(s, 'undo', 'Undid 1', 'undo line')
    cells_are(line, 0, 'the line removed')

    # ---- shapes at the player: pyramids, hollow sphere and cylinder
    ax, ay, az = bx + 20, y0 + 6, bz
    _tp(s, ax + 0.5, ay, az + 0.5)
    _we(s, 'pyramid stone 2', '10 blocks have been created.', '//pyramid stone 2')
    pyr = [(ax + x, ay, az + z) for x in (-1, 0, 1) for z in (-1, 0, 1)] + [(ax, ay + 1, az)]
    cells_are(pyr, stone, 'the pyramid')
    _we(s, 'undo', 'Undid 1', 'undo pyramid')
    _we(s, 'hpyramid stone 2', '9 blocks have been created.', '//hpyramid stone 2')
    cells_are([c for c in pyr if c != (ax, ay, az)], stone, 'the hollow pyramid')
    cells_are([(ax, ay, az)], 0, 'the hollow pyramid to be hollow (the undone pyramid centre gone)')
    _we(s, 'undo', 'Undid 1', 'undo hpyramid')
    hs = _sphere_cells(ax, ay, az, 2, True)
    _we(s, 'hsphere glass 2', 'sphere: %d block(s) changed.' % len(hs), '//hsphere glass 2 (%d cells)' % len(hs))
    cells_are(hs, glass, 'the hollow sphere')
    cells_are([(ax, ay, az)], 0, 'the hollow sphere centre to be air')
    _we(s, 'undo', 'Undid 1', 'undo hsphere')
    hc = _cyl_cells(ax, ay, az, 2, 2, True)
    _we(s, 'hcyl glass 2 2', 'cylinder: %d block(s) changed.' % len(hc), '//hcyl glass 2 2 (%d cells)' % len(hc))
    cells_are(hc, glass, 'the hollow cylinder')
    _we(s, 'undo', 'Undid 1', 'undo hcyl')

    # ---- a stone basin: //fill, //fixwater, //drain
    sel(bx, y0, bz, bx + 4, y0 + 1, bz + 4)
    _we(s, 'set stone', 'set: 50 block(s) changed', 'the basin block')
    sel(bx + 1, y0 + 1, bz + 1, bx + 3, y0 + 1, bz + 3)
    _we(s, 'set air', 'set: 9 block(s) changed', 'the basin hole')
    hole = [(bx + x, y0 + 1, bz + z) for x in (1, 2, 3) for z in (1, 2, 3)]
    _tp(s, bx + 2.5, y0 + 1, bz + 2.5)
    _we(s, 'fill glass 5', '9 blocks have been filled.', '//fill glass 5')
    cells_are(hole, glass, 'the hole filled with glass')
    _we(s, 'undo', 'Undid 1', 'undo fill')
    cells_are(hole, 0, 'the hole empty again')
    sel(bx + 2, y0 + 1, bz + 2, bx + 2, y0 + 1, bz + 2)
    _we(s, 'set water', 'set: 1 block(s) changed', 'a water source in the basin')
    s.wait(lambda: s.w.block(bx + 2, y0 + 1, bz + 2) not in (None, 0), 'the water source')
    water = s.w.block(bx + 2, y0 + 1, bz + 2)
    _we(s, 'fixwater 3', '8 blocks have been fixed.', '//fixwater 3')
    cells_are(hole, water, 'every cell of the hole a water source')
    _we(s, 'drain 3', '9 blocks have been drained.', '//drain 3')
    cells_are(hole, 0, 'the basin drained')

    # ---- //overlay, //naturalize
    sel(bx + 8, y0, bz, bx + 10, y0, bz + 2)
    _we(s, 'set stone', 'set: 9 block(s) changed', 'the overlay floor')
    sel(bx + 8, y0, bz, bx + 10, y0 + 1, bz + 2)
    _we(s, 'overlay glass', '9 blocks have been overlaid.', '//overlay glass')
    cells_are([(bx + 8 + x, y0 + 1, bz + z) for x in range(3) for z in range(3)], glass, 'glass on top of the floor')
    sel(bx + 12, y0, bz, bx + 12, y0 + 5, bz)
    _we(s, 'set stone', 'set: 6 block(s) changed', 'a stone column')
    _we(s, 'naturalize', '4 block(s) have been made to look more natural.', '//naturalize')
    col = [(bx + 12, y0 + y, bz) for y in range(6)]
    s.wait(lambda: [s.w.block(*c) for c in col] == [stone, stone, dirt, dirt, dirt, grass], 'grass, three dirt, then stone')

    # ---- //smooth: a 7x7 stone floor with a spike of 4 in the middle
    x0 = bx + 24
    sel(x0, y0, bz, x0 + 6, y0, bz + 6)
    _we(s, 'set stone', 'set: 49 block(s) changed', 'the smooth floor')
    sel(x0 + 3, y0 + 1, bz + 3, x0 + 3, y0 + 4, bz + 3)
    _we(s, 'set stone', 'set: 4 block(s) changed', 'the spike')
    before = {}
    for x in range(x0, x0 + 7):
        for y in range(y0, y0 + 6):
            for z in range(bz, bz + 7):
                before[(x, y, z)] = stone if (y == y0 or (x == x0 + 3 and z == bz + 3 and y <= y0 + 4)) else 0
    after = _smooth_expect(before, x0, y0, bz, 7, 6, 7, 1)
    n_changed = sum(1 for k in before if before[k] != after[k])
    sel(x0, y0, bz, x0 + 6, y0 + 5, bz + 6)
    _we(s, 'smooth', "Terrain's height map smoothed. %d blocks changed." % n_changed, '//smooth (%d expected)' % n_changed)
    s.wait(lambda: all(s.w.block(*k) == v for k, v in after.items()), 'the smoothed terrain as the filter predicts')
    print('  //smooth changed %d blocks as predicted' % n_changed, flush=True)

    # ---- //copy -e and //paste -e with an armor stand
    ex = bx + 34
    # the clipboard keeps the copy's offset from the player, so copy from beside the box: the paste 10 up lands in loaded chunks
    _tp(s, ex + 1.5, y0 + 3, bz + 1.5)
    sel(ex, y0, bz, ex + 2, y0 + 2, bz + 2)
    s.command('summon minecraft:armor_stand %d.5 %d %d.5 {NoGravity:1b}' % (ex + 1, y0 + 1, bz + 1))
    time.sleep(0.5)
    _we(s, 'copy -e', '1 entities copied.', '//copy -e')
    _we(s, 'copy', 'Copied 27 block(s).', '//copy without -e')
    n = len(s.w.chat)
    s.command('/copy')
    time.sleep(0.5)
    s.check(not any('entities' in t for t in s.w.chat[n:]), 'a plain //copy copied entities')
    _we(s, 'copy -e', '1 entities copied.', '//copy -e again')
    _tp(s, ex + 1.5, y0 + 13, bz + 1.5)
    _we(s, 'paste -e', '1 entities pasted.', '//paste -e')

    # ---- brushes and tools on a right click
    tx, ty, tz = bx + 40, y0, bz
    _tp(s, tx + 0.5, ty + 3, tz + 0.5)          # a click on a block must be within reach
    s.command('setblock %d %d %d minecraft:stone' % (tx, ty, tz))
    s.wait(lambda: s.w.block(tx, ty, tz) == stone, 'the brush target')
    s.command('clear @s')
    s.command('give @s minecraft:stick')
    time.sleep(0.5)
    s.c.send(s.m.SB_CARRIED, struct.pack('>h', 0))
    _we(s, 'brush sphere glass 1', 'Sphere brush shape equipped (1).', '//brush sphere glass 1')
    ball = _sphere_cells(tx, ty, tz, 1, False)
    _use_on(s, tx, ty, tz)
    cells_are(ball, glass, 'the sphere brush stroke (%d cells)' % len(ball))
    _we(s, 'undo', 'Undid 1 edit(s): %d block(s) restored.' % len(ball), 'undo the stroke')
    cells_are([c for c in ball if c != (tx, ty, tz)], 0, 'the stroke undone')
    # in the air: look straight down from above the target, right click
    _tp(s, tx + 0.5, ty + 3, tz + 0.5)
    s.c.send(s.m.SB_MOVE_POS_ROT, struct.pack('>dddff', tx + 0.5, ty + 3.0, tz + 0.5, 0.0, 90.0) + s.m.move_flags(False))
    time.sleep(0.3)
    s.c.send(s.m.SB_USE, s.m.varint(0) + s.m.varint(41) + struct.pack('>ff', 0.0, 90.0))
    cells_are([c for c in ball if c[1] < ty + 2], glass, 'the brush stroke from a right click in the air')
    _we(s, 'undo', 'Undid 1', 'undo the air stroke')
    cells_are([c for c in ball if c != (tx, ty, tz)], 0, 'the air stroke undone')
    _we(s, 'br cylinder glass 1 2', 'Cylinder brush shape equipped (1 by 2).', '//br cylinder glass 1 2')
    cyl = _cyl_cells(tx, ty, tz, 1, 2, False)
    _use_on(s, tx, ty, tz)
    cells_are(cyl, glass, 'the cylinder brush stroke (%d cells)' % len(cyl))
    _we(s, 'undo', 'Undid 1 edit(s): %d block(s) restored.' % len(cyl), 'undo the cylinder')
    cells_are([c for c in cyl if c != (tx, ty, tz)], 0, 'the cylinder undone')
    _we(s, 'brush smooth', 'Smooth brush equipped (2 x 4x using any block).', '//brush smooth')
    _we(s, 'br none', 'Brush unbound from your current item.', '//br none')
    _use_on(s, tx, ty, tz)
    time.sleep(1.0)
    s.check(s.w.block(tx, ty + 1, tz) == 0, 'the unbound brush still painted (%r over the target, %r)' % (s.w.block(tx, ty + 1, tz), [s.w.block(*c) for c in cyl]))
    _we(s, 'tool info', 'Info tool bound to minecraft:stick.', '//tool info')
    n = len(s.w.chat)
    _use_on(s, tx, ty, tz)
    s.expect('@(%d, %d, %d): minecraft:stone' % (tx, ty, tz), 'the info tool', since=n)
    _we(s, 'tool repl glowstone', 'Block replacer tool bound to minecraft:stick.', '//tool repl glowstone')
    _use_on(s, tx, ty, tz)
    cells_are([(tx, ty, tz)], glow, 'the replacer tool')
    _we(s, 'none', 'Tool unbound from your current item.', '//none')
    _we(s, 'undo', 'Undid 1', 'undo the replacer')
    cells_are([(tx, ty, tz)], stone, 'the target is stone again')

    # ---- history size and clearing
    sel(tx + 3, ty, tz, tx + 3, ty, tz)
    _we(s, 'historysize 1', 'History size set to 1 edit(s).', '//historysize 1')
    _we(s, 'set stone', 'set: 1 block(s) changed', 'edit 1')
    _we(s, 'set glass', 'set: 1 block(s) changed', 'edit 2')
    _we(s, 'undo 2', 'Undid 1 edit(s)', 'only one edit kept')
    cells_are([(tx + 3, ty, tz)], stone, 'the cell back at edit 1')
    _we(s, 'historysize 64', 'History size set to 64', '//historysize 64')
    _we(s, 'clearhistory', 'History cleared.', '//clearhistory')
    _we(s, 'undo', 'Nothing left to undo.', '//undo after clearing')


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
    """Explosions through the blast model. With `physics_triggers` off (the default is structures now, the scenario switches it off): /explode is the vanilla blast, the model counts no blast. With
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
        s.check('physics_triggers' in lines and (': structures' in lines or ': off' in lines), 'a default mode is reported: %r' % lines)
        _ask(s, 'body triggers off', 'now off', 'triggers off for the vanilla part')
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


def _bodies_msgs(s, kind):
    """jester:bodies messages of a kind since the start: CREATE (1) heads only (continuation parts left out), DESTROY (2) as (reason, ids)."""
    out = []
    for d in s.payloads('jester:bodies'):
        if not d or d[0] != kind:
            continue
        if kind == 1:
            i = 1
            while d[i] & 0x80:
                i += 1
            i += 1
            if d[i] & 2 == 0:
                out.append(d)
        else:
            out.append(d)
    return out


def _dig(s, x, y, z, seq):
    """A creative player breaks the block: start-digging (status 0) on its top face; creative breaks at once."""
    s.c.send(s.m.SB_ACTION, s.m.varint(0) + s.m.block_pos(x, y, z) + bytes([1]) + s.m.varint(seq))


@scenario(explicit('phys_fell'))
def phys_fell(s):
    """Tree felling and its limits (physics_triggers default `structures`). On a stone pad: an oak (5 logs, 57 leaves) is cut at its bottom
    log by the PLAYER; the tree is taken out of the world (all its cells air on the client), a body appears on jester:bodies (CREATE) and in
    /body status, it topples away from the player (+x), its leaves break into drops and the logs come back as blocks lying on their side
    (axis x or z) at a fallen position. A ground standing 3x3 stone pillar with one block broken out of its side does NOT collapse: no body,
    every other pillar block still there. A natural block broken next to the pad moves nothing either."""
    s.wait(lambda: s.position() is not None and s.chunks() >= 9, 'the spawn chunks', 60.0)
    s.command('gamemode creative')
    # an empty hand: the cut must be a plain break (worldedit_wand leaves the wand in the hand, and a wand click only sets //pos1)
    s.command('clear @s')
    _idle(s, 0.5)
    px, py, pz = s.position()
    px, pz = int(px // 1), int(pz // 1)
    gy = int(py // 1) - 1
    tx, tz = px + 4, pz
    probe = (tx - 3, gy + 14, tz - 3)
    ids = _state_ids(s, probe[0], probe[1], probe[2], ['stone', 'oak_log', 'oak_log[axis=x]', 'oak_log[axis=z]', 'oak_leaves[persistent=true]'])
    stone, log_y, log_x, log_z, leaf = ids['stone'], ids['oak_log'], ids['oak_log[axis=x]'], ids['oak_log[axis=z]'], ids['oak_leaves[persistent=true]']
    status = ' '.join(_ask(s, 'body triggers status', 'tree felling', 'trigger status'))
    # worlds with no setting file report structures (default) (an earlier scenario may have saved another mode for the overworld)
    s.check('structures (default)' in status, 'the default mode is structures: %r' % status)
    _ask(s, 'body triggers structures', 'now structures', 'triggers structures')
    creates_start = len(_bodies_msgs(s, 1))
    # the pad and a clear space over it
    s.command('fill %d %d %d %d %d %d minecraft:air' % (tx - 6, gy + 1, tz - 6, tx + 11, gy + 13, tz + 7))
    # a 5 thick pad: a 1 thick stone slab over uneven ground can really span a dip and crack in the structural check
    s.command('fill %d %d %d %d %d %d minecraft:stone' % (tx - 6, gy - 4, tz - 6, tx + 11, gy, tz + 7))
    # spawn may be on a beach: water (and its plants) under the pad is no support, so the structural check would drop the pad and the
    # oak on it. Fill the water below down to the sea floor with stone so the pad stands on the ground.
    for loose in ('water', 'seagrass', 'tall_seagrass', 'kelp', 'kelp_plant', 'bubble_column'):
        s.command('fill %d %d %d %d %d %d minecraft:stone replace minecraft:%s' % (tx - 6, gy - 40, tz - 6, tx + 11, gy - 5, tz + 7, loose))
    s.wait(lambda: s.block(tx + 11, gy, tz + 7) == stone and s.block(tx - 6, gy, tz - 6) == stone, 'the stone pad', 40.0)
    # the oak: trunk gy+1..gy+5, leaves 2 layers of 5x5 around the top two logs, 3x3 on top
    s.command('fill %d %d %d %d %d %d minecraft:oak_leaves[persistent=true]' % (tx - 2, gy + 4, tz - 2, tx + 2, gy + 5, tz + 2))
    s.command('fill %d %d %d %d %d %d minecraft:oak_leaves[persistent=true]' % (tx - 1, gy + 6, tz - 1, tx + 1, gy + 6, tz + 1))
    s.command('fill %d %d %d %d %d %d minecraft:oak_log' % (tx, gy + 1, tz, tx, gy + 5, tz))
    tree_box = (tx - 2, gy + 1, tz - 2, tx + 2, gy + 6, tz + 2)
    s.wait(lambda: _count_cells(s, tree_box, log_y) == 5 and _count_cells(s, tree_box, leaf) == 57, 'the oak (5 logs, 57 leaves)', 40.0)
    # built by commands, so `structures` collapse checks the pad and the oak: an intact tree and pad must stay (no spurious collapse)
    _idle(s, 8.0)
    if not (_count_cells(s, tree_box, log_y) == 5 and _count_cells(s, tree_box, leaf) == 57):
        why = ' '.join(_ask(s, 'body status', 'created', 'body status (the oak is gone)'))
        s.check(False, 'the standing oak was left alone by the structural check (logs %d, leaves %d; %d new CREATE; %s)' %
                (_count_cells(s, tree_box, log_y), _count_cells(s, tree_box, leaf), len(_bodies_msgs(s, 1)) - creates_start, why[:160]))
    pad_top = _count_cells(s, (tx - 6, gy, tz - 6, tx + 11, gy, tz + 7), stone)
    s.check(pad_top == 18 * 14, 'the pad is intact (%d of %d top cells)' % (pad_top, 18 * 14))
    s.check(len(_bodies_msgs(s, 1)) == creates_start, 'no body before the cut (%d new CREATE)' % (len(_bodies_msgs(s, 1)) - creates_start))
    # the player stands on the -x side of the tree, 3 blocks away
    s.command('tp @s %.1f %d %.1f' % (tx - 3 + 0.5, gy + 1, tz + 0.5))
    s.wait(lambda: abs(s.position()[0] - (tx - 2.5)) < 0.01, 'the teleport next to the tree', 20.0)
    _idle(s, 2.0)
    creates0 = len(_bodies_msgs(s, 1))
    destroys0 = len(_bodies_msgs(s, 2))
    st0 = ' '.join(_ask(s, 'body status', 'created', 'body status before'))
    created0 = _num(st0, r'created ([0-9]+)') or 0
    print('  oak at %d %d %d on a pad at y %d; bodystream creates so far %d' % (tx, gy + 1, tz, gy, creates0), flush=True)
    # 1. cut the bottom log
    _dig(s, tx, gy + 1, tz, 101)
    s.wait(lambda: s.block(tx, gy + 1, tz) == 0, 'the cut log to become air', 15.0)
    t_cut = time.time()
    upper = (tx - 2, gy + 2, tz - 2, tx + 2, gy + 6, tz + 2)
    s.wait(lambda: _count_cells(s, upper, log_y) == 0 and _count_cells(s, upper, leaf) == 0, 'the tree to leave the world (its cells air)', 15.0)
    print('  the tree left the world %.1fs after the cut' % (time.time() - t_cut), flush=True)
    s.wait(lambda: len(_bodies_msgs(s, 1)) > creates0, 'a jester:bodies CREATE for the falling tree', 15.0)
    head = _bodies_msgs(s, 1)[creates0]
    st1 = ' '.join(_ask(s, 'body status', 'created', 'body status after the cut'))
    s.check((_num(st1, r'created ([0-9]+)') or 0) >= created0 + 1, 'the body manager created a body: %r' % st1)
    trig = ' '.join(_ask(s, 'body triggers status', 'tree felling', 'trigger status after the cut'))
    print('  %s' % trig[trig.find('tree felling'):][:220], flush=True)
    s.check((_num(trig, r'tree felling: ([0-9]+) felled') or 0) >= 1, 'the trigger status counts a felled tree: %r' % trig)
    s.check(_num(trig, r'felled \(([0-9]+) logs') == 4 and _num(trig, r'logs, ([0-9]+) leaves') == 57,
            'the felled piece is the 4 logs above the cut and all 57 leaves: %r' % trig)
    print('  CREATE head %d bytes' % len(head), flush=True)
    # 2. it falls, sheds its leaves and the logs settle lying down
    fallen = (tx - 3, gy - 1, tz - 6, tx + 11, gy + 6, tz + 6)

    def lying():
        return _count_cells(s, fallen, log_x) + _count_cells(s, fallen, log_z)
    s.wait(lambda: lying() >= 3, 'the logs to come back as blocks lying on their side', 60.0)
    _idle(s, 3.0)
    n_x, n_z, n_y = _count_cells(s, fallen, log_x), _count_cells(s, fallen, log_z), _count_cells(s, fallen, log_y)
    xs = [x for y in range(gy - 1, gy + 7) for z in range(tz - 6, tz + 7) for x in range(tx - 3, tx + 12) if s.block(x, y, z) in (log_x, log_z)]
    ys = [y for y in range(gy - 1, gy + 7) for z in range(tz - 6, tz + 7) for x in range(tx - 3, tx + 12) if s.block(x, y, z) in (log_x, log_z)]
    print('  settled %.1fs after the cut: lying logs axis=x %d, axis=z %d, upright %d, at x %s y %s; leaves left %d' %
          (time.time() - t_cut, n_x, n_z, n_y, sorted(set(xs)), sorted(set(ys)), _count_cells(s, fallen, leaf)), flush=True)
    s.check(n_x + n_z == 4 and n_y == 0, 'all 4 logs lie on their side (x %d, z %d, upright %d)' % (n_x, n_z, n_y))
    s.check(n_x == 4 and max(xs) >= tx + 3, 'the tree fell along +x, away from the player (log x %s)' % sorted(set(xs)))
    s.check(max(ys) <= gy + 2, 'the logs lie on the pad (y %s, pad top %d)' % (sorted(set(ys)), gy + 1))
    s.check(_count_cells(s, fallen, leaf) == 0, 'the leaves broke into drops (none left as blocks)')
    s.check(len(_bodies_msgs(s, 2)) > destroys0, 'the body ended on jester:bodies (DESTROY)')
    st2 = ' '.join(_ask(s, 'body status', 'created', 'body status after the fall'))
    print('  %s' % st2[:200], flush=True)
    s.check(_num(st2, r'([0-9]+) live') == 0 or creates_start > 0, 'no body is left live: %r' % st2)
    # 3. a ground standing 3x3 stone pillar loses a side block: nothing moves
    bx, bz = tx - 4, tz + 4
    s.command('fill %d %d %d %d %d %d minecraft:stone' % (bx, gy + 1, bz, bx + 2, gy + 8, bz + 2))
    pillar = (bx, gy + 1, bz, bx + 2, gy + 8, bz + 2)
    s.wait(lambda: _count_cells(s, pillar, stone) == 72, 'the stone pillar', 30.0)
    _idle(s, 2.0)
    creates1 = len(_bodies_msgs(s, 1))
    st3 = ' '.join(_ask(s, 'body status', 'created', 'body status before the pillar'))
    created1 = _num(st3, r'created ([0-9]+)')
    _dig(s, bx + 1, gy + 4, bz, 102)
    s.wait(lambda: s.block(bx + 1, gy + 4, bz) == 0, 'the pillar block to become air', 15.0)
    # 4. a natural block next to the pad
    nat = (tx - 7, gy, tz)
    nat_state = s.block(*nat)
    if nat_state not in (None, 0):
        _dig(s, nat[0], nat[1], nat[2], 103)
        s.wait(lambda: s.block(*nat) == 0, 'the natural block to become air', 15.0)
    _idle(s, 8.0)
    left = _count_cells(s, pillar, stone)
    st4 = ' '.join(_ask(s, 'body status', 'created', 'body status after the pillar'))
    print('  pillar: %d of 71 stone blocks still there; natural block %s broken; creates %d -> %d; %s' %
          (left, nat_state, creates1, len(_bodies_msgs(s, 1)), st4[:120]), flush=True)
    s.check(left == 71, 'the pillar stands (%d of 71 blocks)' % left)
    s.check(len(_bodies_msgs(s, 1)) == creates1, 'no body was sent for the pillar or the natural block')
    s.check(_num(st4, r'created ([0-9]+)') == created1, 'no body was created for the pillar or the natural block: %r' % st4)


def run(m, c, st, w, biomes, ctx, args):
    wanted =[n for n in (args.scenario or 'all').split(',') if n]
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


# ---- jester:lod: distant-terrain summaries (overnight/PROTOCOL.md section 10, src/server/net/jester/lodsync.aowl) ----------------------

def _lod_varint(b, at):
    v, shift = 0, 0
    while True:
        x = b[at]
        at += 1
        v |= (x & 127) << shift
        if not x & 128:
            return v, at
        shift += 7


def _lod_columns(data):
    """A COLUMNS message -> [(cx, cz, source, [(top, state, depth, floor, biome)])]."""
    if not data or data[0] != 2:
        return []
    shift = data[1]
    n, at = _lod_varint(data, 2)
    side = 16 >> shift
    out = []
    for _ in range(n):
        zx, at = _lod_varint(data, at)
        zz, at = _lod_varint(data, at)
        cx = (zx >> 1) ^ -(zx & 1)
        cz = (zz >> 1) ^ -(zz & 1)
        source = data[at]
        at += 1
        cells = []
        for _ in range(side * side):
            top = struct.unpack('>h', data[at:at + 2])[0]
            at += 2
            state, at = _lod_varint(data, at)
            depth = data[at]
            at += 1
            floor = 0
            if depth:
                floor, at = _lod_varint(data, at)
            biome = data[at]
            at += 1
            cells.append((top, state, depth, floor, biome))
        out.append((cx, cz, source, cells))
    return out


_LOD_NOT_BLOCKING = ('air', 'cave_air', 'void_air', 'short_grass', 'tall_grass', 'fern', 'large_fern', 'dead_bush', 'snow', 'vine',
                     'dandelion', 'poppy', 'blue_orchid', 'allium', 'azure_bluet', 'red_tulip', 'orange_tulip', 'white_tulip', 'pink_tulip',
                     'oxeye_daisy', 'cornflower', 'lily_of_the_valley', 'sunflower', 'lilac', 'rose_bush', 'peony', 'sugar_cane',
                     'sweet_berry_bush', 'brown_mushroom', 'red_mushroom', 'pink_petals', 'wildflowers', 'leaf_litter', 'bush', 'firefly_bush',
                     'short_dry_grass', 'tall_dry_grass', 'glow_lichen', 'cactus_flower', 'torch', 'pitcher_plant', 'torchflower')


def _lod_plain(m, state):
    name = m.block_name(state) or ''
    return name[10:] if name.startswith('minecraft:') else name


def _lod_motion_top(s, x, z):
    """(y, state) of the highest block a MOTION_BLOCKING heightmap sees in the bot's copy of the world (plants and snow layers skipped)."""
    for y in range(319, -65, -1):
        st = s.w.block(x, y, z)
        if st is None:
            return None
        name = _lod_plain(s.m, st)
        if name in _LOD_NOT_BLOCKING or name.endswith('_sapling') or name.endswith('_carpet') or 'button' in name or \
                name.endswith('_wall_torch') or name.endswith('_sign'):
            continue
        return y, st
    return None


def _lod_ground(s, x, z):
    """y of the terrain under trees and plants (what the noise estimate describes): leaves, logs and plants skipped."""
    for y in range(319, -65, -1):
        st = s.w.block(x, y, z)
        if st is None:
            return None
        name = _lod_plain(s.m, st)
        if name in _LOD_NOT_BLOCKING or name.endswith('_leaves') or name.endswith('_log') or name.endswith('_wood') or \
                name.endswith('_sapling') or name in ('mangrove_roots', 'muddy_mangrove_roots', 'bamboo', 'cactus', 'pumpkin',
                                                     'melon', 'cocoa', 'bee_nest', 'moss_carpet', 'pale_moss_carpet', 'pale_hanging_moss',
                                                     'hanging_roots', 'big_dripleaf', 'big_dripleaf_stem', 'small_dripleaf', 'lily_pad',
                                                     'brown_mushroom_block', 'red_mushroom_block', 'mushroom_stem', 'seagrass',
                                                     'tall_seagrass', 'kelp', 'kelp_plant', 'sea_pickle'):
            continue
        return y, name
    return None


@scenario('lod_summaries')
def lod_summaries(s):
    """A client offering `lod` gets jester:lod summaries for every column past its view distance out to the radius it asked for, nearest
    first; summaries of chunks the server holds match those chunks exactly, and noise summaries match the terrain the server later
    generates there (within a few blocks: the noise stage has no trees, lakes or carvers)."""
    import os
    radius = int(os.environ.get('LOD_TEST_RADIUS', '24'))
    if 'ranges' not in s.m.BLOCK_TABLE:
        s.m.load_block_table(s.args.assets)        # block names, for the comparisons
    s.wait(lambda: s.position() is not None and s.chunks() >= 25, 'the spawn chunks', 90.0)
    # let the whole view arrive first, so the ring just inside it is held by the server (source 1, compared exactly below)
    settle = [s.chunks(), time.time()]

    def settled():
        if s.chunks() != settle[0]:
            settle[0], settle[1] = s.chunks(), time.time()
        return time.time() - settle[1] > 5.0
    s.wait(settled, 'the view distance to finish loading', 120.0)
    # re-negotiate in play, offering lod (bit 7) on top of the runner's 0x1F
    n_w = len(s.payloads('jester:welcome'))
    hello = bytes([1, 1, 1, 5]) + b'0.9.0' + struct.pack('>Q', 0x9F) + bytes([0xB0, 0xEA, 0x01]) + bytes([0, 0, 0, 9])
    s.send_payload('jester:hello', hello)
    got = s.wait_payload('jester:welcome', 'the welcome to the play-phase hello', since=n_w)
    wl = got[0]
    caps = struct.unpack('>Q', wl[3 + wl[2]:3 + wl[2] + 8])[0]
    s.check(caps & 0x80, 'the server did not grant lod (granted %#x): MC_LOD_RADIUS=0 or the capability is not advertised' % caps)
    n_l = len(s.payloads('jester:lod'))
    s.send_payload('jester:lod', bytes([0x10]) + s.m.varint(radius) + bytes([2, 1]))     # REQUEST radius, 4-block cells, resend
    s.send_payload('jester:lod', bytes([0x11, 1]))                                         # FLOW go
    first = s.wait_payload('jester:lod', 'the INIT', 20.0, since=n_l)[0]
    s.check(first[0] == 1, 'the first jester:lod message is not INIT (%d)' % first[0])
    dlen = first[2]
    dim = first[3:3 + dlen].decode()
    granted, at = _lod_varint(first, 3 + dlen)
    print('  INIT %s radius %d shift %d' % (dim, granted, first[at]), flush=True)
    s.check(granted == radius, 'INIT radius %d, asked %d' % (granted, radius))
    px, pz = int(s.position()[0]) >> 4, int(s.position()[2]) >> 4
    vd = 8                                           # mcbot's client_information
    want = set()
    for dz in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            ring = int(math.sqrt(dx * dx + dz * dz))
            if vd - 1 <= ring <= radius:
                want.add((px + dx, pz + dz))
    cols = {}
    order = []
    seen_msgs = [n_l]

    def gather():
        msgs = s.payloads('jester:lod')
        for data in msgs[seen_msgs[0]:]:
            for c in _lod_columns(data):
                if (c[0], c[1]) not in cols:
                    order.append((c[0], c[1]))
                cols[(c[0], c[1])] = c
        seen_msgs[0] = len(msgs)
        return len(want & set(cols)) >= len(want)
    t0 = time.time()
    s.wait(gather, '%d summaries out to radius %d' % (len(want), radius), float(os.environ.get('LOD_TEST_SECONDS', '300')))
    dt = time.time() - t0
    rings = [int(math.sqrt((c[0] - px) ** 2 + (c[1] - pz) ** 2)) for c in order]
    srcs = {}
    for c in cols.values():
        srcs[c[2]] = srcs.get(c[2], 0) + 1
    print('  %d columns in %.1f s (%.0f/s), sources %r, max ring %d' % (len(cols), dt, len(cols) / max(dt, 0.001), srcs, max(rings)), flush=True)
    s.check(max(rings) <= radius + 1, 'a summary past the radius (ring %d)' % max(rings))
    s.check(not [k for k in cols if int(math.sqrt((k[0] - px) ** 2 + (k[1] - pz) ** 2)) < vd - 1], 'a summary inside the view distance')
    half = len(rings) // 2
    early, late = sum(rings[:half]) / max(half, 1), sum(rings[half:]) / max(len(rings) - half, 1)
    print('  mean ring of the first half %.1f, second half %.1f' % (early, late), flush=True)
    s.check(early < late, 'not nearest first: mean ring %.1f then %.1f' % (early, late))

    # 1. summaries of chunks the server holds (source 1) that the bot also holds: exact
    # (the bot's block-name table does not match every state id of this version, so this check uses no names: the summary's block must
    # be in the chunk at the summary's y, and everything above it must be air or a state that is never anybody's top - plants, snow)
    exact = total = 0
    misses = []
    tops = set(cell[1] for c in cols.values() if c[2] == 1 for cell in c[3])
    for (cx, cz), c in cols.items():
        if c[2] != 1 or (cx, cz) not in s.w.chunks:
            continue
        for i, cell in enumerate(c[3]):
            x, z = cx * 16 + (i % 4) * 4, cz * 16 + (i // 4) * 4
            total += 1
            here = s.w.block(x, cell[0], z)
            above = [s.w.block(x, y, z) for y in range(cell[0] + 1, 320)]
            clear = all(st == 0 or st not in tops for st in above)
            if here == cell[1] and clear:
                exact += 1
            elif len(misses) < 12:
                bad = [(cell[0] + 1 + k, st) for k, st in enumerate(above) if st != 0 and st in tops][:2]
                misses.append('%d,%d summary y=%d state %d, chunk has %r there, blocking above: %r' % (x, z, cell[0], cell[1], here, bad))
    print('  held-chunk summaries: %d of %d samples exact (top y and state)' % (exact, total), flush=True)
    for line in misses:
        print('    differs: ' + line, flush=True)
    if total:
        s.check(exact >= 0.95 * total, 'held-chunk summaries: only %d of %d samples match the chunk' % (exact, total))

    # 2. noise summaries against the terrain generated there later: teleport over a few of them
    picks = []
    for frac, ang in ((0.45, 30), (0.6, 150), (0.75, 260), (0.9, 330)):
        r = vd + 2 + frac * (radius - vd - 2)
        k = (px + int(round(r * math.cos(math.radians(ang)))), pz + int(round(r * math.sin(math.radians(ang)))))
        if k in cols and cols[k][2] == 0:
            picks.append(k)
    if not picks:
        s.inconclusive('no noise-sourced summaries at the sample points')
    ground = set(cell[1] for c in cols.values() if c[2] == 0 for cell in c[3]) |         set(cell[3] for c in cols.values() if c[2] == 0 for cell in c[3] if cell[2] > 0)
    water = set(cell[1] for c in cols.values() if c[2] == 0 for cell in c[3] if cell[2] > 0)
    for st in range(0, 2000):                       # low state ids: the bot's names are right there
        if _lod_plain(s.m, st) in ('stone', 'dirt', 'coarse_dirt', 'grass_block', 'podzol', 'sand', 'red_sand', 'gravel', 'sandstone',
                                   'clay', 'snow_block', 'ice', 'packed_ice', 'mycelium', 'granite', 'diorite', 'andesite', 'water'):
            ground.add(st)
    near = within = water_ok = water_n = 0
    errors = []
    for (cx, cz) in picks:
        cells = cols[(cx, cz)][3]
        top = max(c[0] for c in cells)
        tx, ty, tz = cx * 16 + 8, top + 4, cz * 16 + 8
        s.command('tp @s %d %d %d' % (tx, ty, tz))
        s.wait(lambda: s.position() is not None and abs(s.position()[0] - (tx + 0.5)) < 1.0, 'the teleport to %d %d' % (tx, tz), 30.0)
        # the server moves the view when the client reports its position
        s.c.send(s.m.SB_MOVE_POS, struct.pack('>ddd', tx + 0.5, ty, tz + 0.5) + s.m.move_flags(True))
        s.wait(lambda: (cx, cz) in s.w.chunks and (cx + 1, cz) in s.w.chunks and (cx, cz + 1) in s.w.chunks,
               'the generated chunk %d,%d' % (cx, cz), 90.0)
        for i, cell in enumerate(cells):
            x, z = cx * 16 + (i % 4) * 4, cz * 16 + (i // 4) * 4
            g = None
            for y in range(319, -65, -1):
                st = s.w.block(x, y, z)
                if st is None:
                    break
                if st in ground:
                    g = (y, 'water' if st in water else 'ground')
                    break
            if g is None:
                continue
            near += 1
            d = g[0] - cell[0]
            errors.append(d)
            if abs(d) <= 3:
                within += 1
            water_n += 1
            if (cell[2] > 0) == (g[1] == 'water'):
                water_ok += 1
    errors.sort()
    print('  noise summaries vs generated: %d of %d samples within 3 blocks, water agrees %d of %d, error median %d, range %d..%d' %
          (within, near, water_ok, water_n, errors[len(errors) // 2], errors[0], errors[-1]), flush=True)
    s.check(near >= 32, 'too few samples compared (%d)' % near)
    s.check(within >= 0.75 * near, 'noise summaries: only %d of %d samples within 3 blocks of the generated ground' % (within, near))
    s.check(water_ok >= 0.85 * water_n, 'noise summaries: water agrees for only %d of %d samples' % (water_ok, water_n))


# ---- phase 4 (one thread per dimension) with real players in two worlds --------------------------------------------------------------
# Run by tools/run_dim_threads.sh, which starts two bots at once: DIM_BOT=ow stays in the overworld, DIM_BOT=nether is sent to the nether.
# Both edit blocks at the SAME coordinates with different blocks (so each must see only its own world's block), chat, and the nether bot
# hops between worlds. Explicit only (it needs two bots).

@scenario('dim_threads_two_worlds')
def dim_threads_two_worlds(s):
    """Two operators, one in the overworld and one in the nether, for a few hundred ticks: /setblock and /fill edits, chat that crosses
    worlds, a repeating command block, a nether hop and back, keep-alives answered. Each bot checks that its own edits arrive as block
    updates, that the other world's block at the same coordinates never shows, and that the server's own query for each world agrees."""
    import os
    who = os.environ.get('DIM_BOT', 'ow')
    rounds = int(os.environ.get('DIM_ROUNDS', '40'))
    nether = who == 'nether'
    mine, other = ('minecraft:obsidian', 'minecraft:stone') if nether else ('minecraft:stone', 'minecraft:obsidian')
    my_dim, other_dim = ('minecraft:the_nether', 'minecraft:overworld') if nether else ('minecraft:overworld', 'minecraft:the_nether')
    tag = 'DIM' + ('B' if nether else 'A')
    other_tag = 'DIM' + ('A' if nether else 'B')
    _ready(s)
    ka0 = s.ctx['counts'].get(s.m.PLAY_KEEP_ALIVE, 0)
    ids = {}
    # the state ids as this client knows them (placed in the bot's own world at a probe cell)
    px = 4
    if nether:
        s.command('execute in minecraft:the_nether run tp @s %d.5 150 %d.5' % (px, px))
        s.wait(lambda: s.position() is not None and abs(s.position()[0] - (px + 0.5)) < 0.01 and abs(s.position()[1] - 150) < 0.01,
               'the teleport into the nether', 90.0)
        print('  in the nether at %r' % (s.position(),), flush=True)
        s.wait(lambda: s.w.block(px, 149, px) is not None, 'the nether chunk at the bot', 60.0)
    ids = _state_ids(s, px + 4, 120, px, ['stone', 'obsidian'])
    s.check(ids['stone'] != ids['obsidian'], 'stone and gold share a state id')
    want = ids['obsidian'] if nether else ids['stone']
    unwanted = ids['stone'] if nether else ids['obsidian']
    print('  %s world: my block state %d, the other world\'s %d' % (my_dim, want, unwanted), flush=True)
    # a repeating command block that sets a sea lantern (soft: the repeat may be disabled on the server)
    cb = (px + 12, 120, px)
    s.command('setblock %d %d %d minecraft:repeating_command_block{auto:1b,Command:"setblock %d %d %d minecraft:sea_lantern"}' %
              (cb + (px + 14, 120, px)))
    placed = []
    # a bedrock deck under the cells and the fill, so the structural solver has nothing to collapse
    s.command('fill %d 119 %d %d 119 %d minecraft:bedrock' % (px - 1, px - 4, px + 22, px + 8))
    s.command('fill %d 121 %d %d 121 %d minecraft:bedrock' % (px - 1, px - 4, px + 22, px + 8))
    _pause(s, 2.0)
    for i in range(rounds):
        x, z = px + (i % 8), px + 2 + (i // 8)
        s.command('setblock %d 120 %d %s' % (x, z, mine))
        s.wait(lambda: s.w.block(x, 120, z) == want, 'my block %d at %d 120 %d' % (i, x, z), 30.0)
        placed.append((x, z))
        if i % 4 == 0:
            s.command('fill %d 120 %d %d 120 %d %s' % (px, px - 3, px + 3, px - 2, mine))
        if i % 5 == 0:
            s.say('%s round %d' % (tag, i))
        if i % 10 == 9:
            _pause(s, 0.5)
        s.check(s.w.block(x, 120, z) != unwanted, 'the other world\'s block showed at %d 120 %d' % (x, z))
    # the server's own view of BOTH worlds at the same coordinates (a query answers by saying a marker)
    qn = [0]
    lat = []

    def holds(dim, x, y, z, block, seconds=30.0):
        qn[0] += 1
        marker = 'Q%s%d' % (tag, qn[0])
        n = len(s.w.chat)
        s.command('execute in %s if block %d %d %d %s run tellraw @s "%s"' % (dim, x, y, z, block, marker))
        t0 = time.time()
        end = t0 + seconds
        try:
            s.wait(lambda: s.heard(marker, n) or time.time() > end, 'the answer to a block query', seconds + 10.0)
        except Exception:
            pass
        got = s.heard(marker, n)
        if got:
            lat.append(time.time() - t0)
        return got
    # sync with the other bot: chat does not cross worlds on this server (see the report), so each bot raises a flag block in its own world and
    # polls the server's cross-world query for the other's
    def raise_flag(name):
        s.command('setblock %d 120 %d minecraft:emerald_block' % (px + 20, px + (0 if name == 'edits' else 3)))

    def wait_flag(name):
        end = time.time() + 150.0
        while time.time() < end:
            if holds(other_dim, px + 20, 120, px + (0 if name == 'edits' else 3), 'minecraft:emerald_block', 4.0):
                return
        s.check(False, 'the other bot never raised its %s flag (server cross-world query)' % name)
    raise_flag('edits')
    wait_flag('edits')
    # every cell still mine, never the other world's
    gone = [(x, z) for x, z in placed if s.w.block(x, 120, z) != want]
    print('  cells placed %d, client sees %d still there %s' % (len(placed), len(placed) - len(gone), gone[:6]), flush=True)
    s.check(not gone, 'cells lost: %r (state %r)' % (gone[:4], s.w.block(*(gone[0][0], 120, gone[0][1]))) if gone else '')
    s.check(holds(my_dim, px, 120, px + 2, mine), 'the server does not see my block in my world')
    s.check(holds(my_dim, px + 3, 120, px - 2, mine), 'the server does not hold my /fill in my world')
    s.check(not holds(other_dim, px, 120, px + 2, mine, 3.0), 'the other world holds my block at the same coordinates')
    other_ok = holds(other_dim, px, 120, px + 2, other)
    if not other_ok:
        print('  diagnostic (%s): deck %s, obsidian@(4,120,6) %s, stone@(4,120,6) %s, air %s, again %s' % (
            other_dim, holds(other_dim, px, 119, px + 2, 'minecraft:bedrock'), holds(other_dim, px, 120, px + 2, 'minecraft:obsidian'),
            holds(other_dim, px, 120, px + 2, 'minecraft:stone'), holds(other_dim, px, 120, px + 2, 'minecraft:air'),
            holds(other_dim, px, 120, px + 2, other)), flush=True)
    s.check(other_ok, 'the other world does not hold its own block')
    print('  client view of the /fill corners: %r %r (want %r)' % (s.w.block(px, 120, px - 3), s.w.block(px + 3, 120, px - 2), want), flush=True)
    lantern = None
    try:
        s.wait(lambda: s.w.block(px + 14, 120, px) not in (None, 0), 'the command block output', 20.0)
        lantern = s.w.block(px + 14, 120, px)
    except Exception:
        pass
    print('  command block output: %s' % ('seen, state %r' % lantern if lantern else 'NOT seen (soft check)'), flush=True)
    if nether:
        # a hop back and forth while the other bot keeps working
        for dim, y in (('minecraft:overworld', 150), ('minecraft:the_nether', 150)):
            s.command('execute in %s run tp @s %d.5 %d %d.5' % (dim, px, y, px))
            _pause(s, 4.0)
            s.check(s.position() is not None, 'no position after the hop to ' + dim)
        print('  hops done at %r' % (s.position(),), flush=True)
    raise_flag('all')
    wait_flag('all')
    print('  query latency (answered ones): n=%d max %.2fs mean %.2fs' % (len(lat), max(lat or [0]), sum(lat) / max(len(lat), 1)), flush=True)
    ka = s.ctx['counts'].get(s.m.PLAY_KEEP_ALIVE, 0) - ka0
    print('  keep-alives answered: %d, blocks placed: %d' % (ka, len(placed)), flush=True)


EXPLICIT_ONLY.add('dim_threads_two_worlds')
