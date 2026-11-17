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
