#!/usr/bin/env python3
"""A small Minecraft Bedrock (protocol 1001, RakNet 11) client that logs in to a server and checks what it is sent.

    python tools/bedrockbot.py --port 41234 [--host 127.0.0.1] [--name "Bot Steve"] [--no-encrypt] [--ping-only]

Standard library only. P-384 (ECDH and ECDSA), AES-256 and the RakNet layer are written here from the RakNet and Bedrock
login layouts, not from the server's code, so it is an independent check of it. The scenario, each step asserted:

  1. unconnected ping -> pong, with the server info string (protocol 1001);
  2. open connection request 1 (wrong RakNet version first -> incompatible protocol) -> reply 1; request 2 -> reply 2;
     guid and MTU are BIG-endian and the address is a RakNet SystemAddress (IPv4 octets inverted), checked field by field;
  3. connection request -> accepted; new incoming connection; connected ping -> pong;
  4. RequestNetworkSettings -> NetworkSettings, then zlib (raw deflate) compression both ways;
  5. Login with a self-signed ES384 token (a client key, `cpk`, name, xid) -> the server's handshake JWT (its ES384 signature is
     verified against its `x5u`), ECDH, SHA-256(salt ++ secret) as the AES-256-CTR key, ClientToServerHandshake;
  6. PlayStatus LoginSuccess then ResourcePacksInfo, both encrypted;
  7. ResourcePackResponse HaveAllPacks -> ResourcePackStack; Completed (the server's join hook); it stays up and keeps
     answering connected pings, then disconnects.

  8. With --play --extended (after the walk and the chat): the join's CraftingData, attributes, commands and abilities; a hotbar
     selection; a modal form answered (--form, the server started with PUMPKIN_BEDROCK_TEST_FORM); the Java `give` arriving
     as inventory content; creative mode; a creative pick through an ItemStackRequest; a block placed and broken; a chest
     opened, filled, closed, opened again and emptied; OpenInventory; a block pick; an emote; a dropped item arriving as an
     item actor; a cow arriving as an actor and hit with a UseItemOnEntity attack. Lines starting `@console ` ask the driver
     (tools/runbedrockfull.py) to run a server console command and `@expect ` lines are looked for in the server log.
  9. With --oidc-key/--oidc-kid/--oidc-issuer the login is an online-mode one (AuthenticationType 0): an OIDC token signed
     by a key the driver published in a local JWKS.

Exit status 0 only if every step held. `--ping-only` stops after step 1. `--expect-full` wants the server to answer open
connection request 1 with NoFreeIncomingConnections. Run it against src/server/net/bedrock/bedrockdemo.aowl (see
tools/runbedrock.py) or a full server with Bedrock enabled; it never uses a fixed port.
"""
import argparse
import base64
import hashlib
import json
import math
import os
import socket
import struct
import sys
import time
import zlib

MAGIC = bytes.fromhex('00ffff00fefefefefdfdfdfd12345678')

# --- P-384 -----------------------------------------------------------------------------------------------------------
P = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeffffffff0000000000000000ffffffff
A = P - 3
B = 0xb3312fa7e23ee7e4988e056be3f82d19181d9c6efe8141120314088f5013875ac656398d8a2ed19d2a85c8edd3ec2aef
N = 0xffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973
GX = 0xaa87ca22be8b05378eb1c71ef320ad746e1d3b628ba79b9859f741e082542a385502f25dbf55296c3a545e3872760ab7
GY = 0x3617de4a96262c6f5d9e98bf9292dc29f8f41dbd289a147ce9da3113b5f0b8c00a60b1ce1d7e819d7a431d7c90ea0e5f
G = (GX, GY)


def pt_add(p1, p2):
    if p1 is None:
        return p2
    if p2 is None:
        return p1
    x1, y1 = p1
    x2, y2 = p2
    if x1 == x2:
        if (y1 + y2) % P == 0:
            return None
        l = (3 * x1 * x1 + A) * pow(2 * y1, -1, P) % P
    else:
        l = (y2 - y1) * pow(x2 - x1, -1, P) % P
    x3 = (l * l - x1 - x2) % P
    return x3, (l * (x1 - x3) - y1) % P


def pt_mul(k, pt):
    r = None
    while k:
        if k & 1:
            r = pt_add(r, pt)
        pt = pt_add(pt, pt)
        k >>= 1
    return r


SPKI_PREFIX = bytes.fromhex('3076301006072a8648ce3d020106052b81040022036200')


def spki(pt):
    return SPKI_PREFIX + b'\x04' + pt[0].to_bytes(48, 'big') + pt[1].to_bytes(48, 'big')


def point_from_spki(der):
    raw = der[-97:]
    assert raw[0] == 4, 'uncompressed point expected'
    return int.from_bytes(raw[1:49], 'big'), int.from_bytes(raw[49:], 'big')


def ecdsa_sign(d, msg):
    z = int.from_bytes(hashlib.sha384(msg).digest(), 'big')
    while True:
        k = int.from_bytes(os.urandom(48), 'big') % N
        if k == 0:
            continue
        r = pt_mul(k, G)[0] % N
        s = pow(k, -1, N) * (z + r * d) % N
        if r and s:
            return r.to_bytes(48, 'big') + s.to_bytes(48, 'big')


def ecdsa_verify(pub, msg, sig):
    r = int.from_bytes(sig[:48], 'big')
    s = int.from_bytes(sig[48:], 'big')
    if not (0 < r < N and 0 < s < N):
        return False
    z = int.from_bytes(hashlib.sha384(msg).digest(), 'big')
    w = pow(s, -1, N)
    p = pt_add(pt_mul(z * w % N, G), pt_mul(r * w % N, pub))
    return p is not None and p[0] % N == r


# --- AES-256 CTR (counter = the whole block, big-endian) --------------------------------------------------------------
def _sbox():
    def rotl(x, n):
        return ((x << n) | (x >> (8 - n))) & 0xFF
    box = [0] * 256
    p = q = 1
    while True:
        p = (p ^ (p << 1) ^ (0x1B if p & 0x80 else 0)) & 0xFF
        q ^= q << 1
        q ^= q << 2
        q ^= q << 4
        q &= 0xFF
        if q & 0x80:
            q ^= 0x09
        box[p] = q ^ rotl(q, 1) ^ rotl(q, 2) ^ rotl(q, 3) ^ rotl(q, 4) ^ 0x63
        if p == 1:
            break
    box[0] = 0x63
    return box


SBOX = _sbox()


def _xt(a):
    return ((a << 1) ^ 0x1B) & 0xFF if a & 0x80 else a << 1


def expand_key(key):
    w = [list(key[i:i + 4]) for i in range(0, 32, 4)]
    rcon = 1
    for i in range(8, 60):
        t = list(w[i - 1])
        if i % 8 == 0:
            t = [SBOX[t[1]] ^ rcon, SBOX[t[2]], SBOX[t[3]], SBOX[t[0]]]
            rcon = _xt(rcon)
        elif i % 8 == 4:
            t = [SBOX[b] for b in t]
        w.append([w[i - 8][j] ^ t[j] for j in range(4)])
    return [sum(w[4 * r:4 * r + 4], []) for r in range(15)]


def aes_block(rk, block):
    s = [block[i] ^ rk[0][i] for i in range(16)]
    for r in range(1, 15):
        s = [SBOX[b] for b in s]
        s = [s[(i + 4 * (i % 4)) % 16] for i in range(16)]  # ShiftRows (column-major state)
        if r != 14:
            o = []
            for c in range(4):
                a = s[4 * c:4 * c + 4]
                t = a[0] ^ a[1] ^ a[2] ^ a[3]
                o += [a[0] ^ t ^ _xt(a[0] ^ a[1]), a[1] ^ t ^ _xt(a[1] ^ a[2]), a[2] ^ t ^ _xt(a[2] ^ a[3]), a[3] ^ t ^ _xt(a[3] ^ a[0])]
            s = o
        s = [s[i] ^ rk[r][i] for i in range(16)]
    return bytes(s)


class Ctr:
    def __init__(self, key, iv):
        self.rk = expand_key(key)
        self.counter = int.from_bytes(iv, 'big')
        self.stream = b''

    def apply(self, data):
        out = bytearray()
        for b in data:
            if not self.stream:
                self.stream = aes_block(self.rk, self.counter.to_bytes(16, 'big'))
                self.counter = (self.counter + 1) % (1 << 128)
            out.append(b ^ self.stream[0])
            self.stream = self.stream[1:]
        return bytes(out)


def self_test_aes():
    # FIPS-197 C.3: AES-256 of 00112233445566778899aabbccddeeff under key 00..1f.
    rk = expand_key(bytes(range(32)))
    got = aes_block(rk, bytes.fromhex('00112233445566778899aabbccddeeff')).hex()
    assert got == '8ea2b7ca516745bfeafc49904b496089', got


# --- encodings --------------------------------------------------------------------------------------------------------
def varuint(v):
    out = bytearray()
    while True:
        b = v & 0x7F
        v >>= 7
        if v:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def read_varuint(buf, pos):
    shift = 0
    v = 0
    while True:
        b = buf[pos]
        pos += 1
        v |= (b & 0x7F) << shift
        if not b & 0x80:
            return v, pos
        shift += 7


def b64(data, url=False, pad=True):
    s = (base64.urlsafe_b64encode if url else base64.b64encode)(data).decode()
    return s if pad else s.rstrip('=')


def b64d(s):
    s = s.replace('-', '+').replace('_', '/')
    return base64.b64decode(s + '=' * (-len(s) % 4))


def rak_addr(ip, port):
    return b'\x04' + bytes((~int(o)) & 0xFF for o in ip.split('.')) + struct.pack('>H', port)


def parse_rak_addr(buf, pos):
    assert buf[pos] == 4, 'ipv4 SystemAddress expected'
    ip = '.'.join(str((~b) & 0xFF) for b in buf[pos + 1:pos + 5])
    return (ip, struct.unpack('>H', buf[pos + 5:pos + 7])[0]), pos + 7


# --- the session ------------------------------------------------------------------------------------------------------
class Fail(Exception):
    pass


def check(cond, what):
    if not cond:
        raise Fail(what)
    print('  ok  ' + what, flush=True)


class Bot:
    def __init__(self, host, port, name, encrypt):
        self.addr = (host, port)
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(('127.0.0.1', 0))
        self.local = self.sock.getsockname()
        self.guid = struct.unpack('>Q', os.urandom(8))[0] >> 1
        self.name = name
        self.encrypt = encrypt
        self.seq = 0
        self.reliable = 0
        self.ordered = 0
        self.split_id = 0
        self.mtu = 1400
        self.compress = False
        self.enc = None
        self.dec = None
        self.send_counter = 0
        self.recv_counter = 0
        self.fragments = {}
        self.expected_order = 0
        self.held = {}
        self.queue = []  # delivered frame payloads
        self.acked_by_server = 0
        self.scene = None   # fed every game packet that is read (the extended scenario)

    # offline
    def offline(self, data, wait=8.0):
        self.sock.sendto(data, self.addr)
        return self.recv_offline(wait)

    def recv_offline(self, wait=8.0):
        self.sock.settimeout(wait)
        d, _ = self.sock.recvfrom(4096)
        return d

    # connected
    def send_datagram(self, frames, split=None):
        out = bytes([0x84]) + self.seq.to_bytes(3, 'little') + frames
        self.seq += 1
        self.sock.sendto(out, self.addr)

    def frame(self, payload, split=None, order=None):
        flags = 3 << 5  # ReliableOrdered
        if split:
            flags |= 0x10
        b = bytes([flags]) + struct.pack('>H', len(payload) * 8) + self.reliable.to_bytes(3, 'little')
        self.reliable += 1
        b += order.to_bytes(3, 'little') + b'\x00'
        if split:
            b += struct.pack('>IHI', *split)
        return b + payload

    def send_rak(self, payload):
        limit = 1100
        if len(payload) <= limit:
            self.send_datagram(self.frame(payload, order=self.ordered))
            self.ordered += 1
            return
        parts = [payload[i:i + limit] for i in range(0, len(payload), limit)]
        sid = self.split_id
        self.split_id += 1
        order = self.ordered
        self.ordered += 1
        for i, part in enumerate(parts):
            self.send_datagram(self.frame(part, split=(len(parts), sid, i), order=order))

    def send_game(self, pid, body):
        inner = varuint(len(varuint(pid)) + len(body)) + varuint(pid) + body
        if self.compress:
            data = b'\x00' + zlib.compress(inner)[2:-4] if False else b'\x00' + _raw_deflate(inner)
        else:
            data = inner
        if self.enc:
            payload = data + hashlib.sha256(struct.pack('<Q', self.send_counter) + data + self.key).digest()[:8]
            self.send_counter += 1
            data = self.enc.apply(payload)
        self.send_rak(b'\xfe' + data)

    def pump(self, wait):
        """Reads one datagram; returns False on timeout."""
        self.sock.settimeout(wait)
        try:
            d, _ = self.sock.recvfrom(4096)
        except socket.timeout:
            return False
        h = d[0]
        if h == 0xC0:
            self.acked_by_server += 1
            return True
        if h == 0xA0:
            return True
        if not (0x80 <= h <= 0x8D):
            raise Fail('unexpected datagram header %02x' % h)
        seq = int.from_bytes(d[1:4], 'little')
        self.sock.sendto(b'\xc0' + struct.pack('>H', 1) + b'\x01' + seq.to_bytes(3, 'little'), self.addr)
        pos = 4
        while pos < len(d):
            flags = d[pos]
            rel = flags >> 5
            split = flags & 0x10
            bits = struct.unpack('>H', d[pos + 1:pos + 3])[0]
            n = (bits + 7) // 8
            pos += 3
            if rel in (2, 3, 4, 6, 7):
                pos += 3
            if rel == 4:
                pos += 3
            order = None
            if rel in (1, 3, 4, 7):
                order = int.from_bytes(d[pos:pos + 3], 'little')
                pos += 4
            sinfo = None
            if split:
                sinfo = struct.unpack('>IHI', d[pos:pos + 10])
                pos += 10
            payload = d[pos:pos + n]
            pos += n
            if sinfo:
                size, sid, idx = sinfo
                got = self.fragments.setdefault(sid, {})
                got[idx] = payload
                if len(got) < size:
                    continue
                payload = b''.join(got[i] for i in range(size))
                del self.fragments[sid]
            if rel == 3 and order is not None:
                self.held[order] = payload
                while self.expected_order in self.held:
                    self.queue.append(self.held.pop(self.expected_order))
                    self.expected_order += 1
            else:
                self.queue.append(payload)
        return True

    def next_payload(self, wait=3.0):
        end = time.time() + wait
        while not self.queue:
            left = end - time.time()
            if left <= 0 or not self.pump(left):
                raise Fail('timed out waiting for the server')
        return self.queue.pop(0)

    def next_rak(self, wait=3.0):
        p = self.next_payload(wait)
        if p[0] == 0xfe:
            raise Fail('a game packet where a RakNet message was expected')
        return p

    def next_game(self, wait=3.0):
        while True:
            p = self.next_payload(wait)
            if p[0] != 0xfe:
                continue
            data = p[1:]
            if self.dec:
                data = self.dec.apply(data)
                body, sumv = data[:-8], data[-8:]
                want = hashlib.sha256(struct.pack('<Q', self.recv_counter) + body + self.key).digest()[:8]
                if want != sumv:
                    raise Fail('bad checksum on an encrypted packet from the server')
                self.recv_counter += 1
                data = body
            if self.compress:
                m = data[0]
                data = data[1:]
                if m == 0:
                    data = zlib.decompress(data, -15)
                elif m != 0xFF:
                    raise Fail('compression method %02x' % m)
            out = []
            pos = 0
            while pos < len(data):
                ln, pos = read_varuint(data, pos)
                end = pos + ln
                hdr, pos = read_varuint(data, pos)
                out.append((hdr & 0x3FF, data[pos:end]))
                pos = end
            self.game_in = getattr(self, 'game_in', []) + out
            if out:
                break
        first = self.game_in.pop(0)
        if self.scene is not None:
            self.scene.take(first[0], first[1])
        return first


def _raw_deflate(data):
    c = zlib.compressobj(6, zlib.DEFLATED, -15)
    return c.compress(data) + c.flush()


def bstr(text):
    raw = text.encode()
    return varuint(len(raw)) + raw


def zigzag32(v):
    return ((v << 1) ^ (v >> 31)) & 0xFFFFFFFF


def unzigzag(v):
    return (v >> 1) ^ -(v & 1)


def auth_input(pos, yaw, pitch, tick, delta=(0.0, 0.0, 0.0), flags=0):
    """A PlayerAuthInput (144) with no optional parts: the fixed fields, then the three trailing vectors."""
    body = struct.pack('<ff', pitch, yaw) + struct.pack('<fff', *pos) + struct.pack('<ff', 0.0, 0.0) + struct.pack('<f', yaw)
    body += varuint(flags) + varuint(1) + varuint(0) + varuint(0)       # input data, input mode, play mode, interaction model
    body += struct.pack('<ff', pitch, yaw) + varuint(tick) + struct.pack('<fff', *delta)
    body += struct.pack('<ff', 0.0, 0.0) + struct.pack('<fff', 0.0, 0.0, 0.0) + struct.pack('<ff', 0.0, 0.0)
    return body


def play_phase(bot, args):
    """Runs after the resource packs: start game, chunk radius, chunks, spawn, move, chat. Returns the summary dict."""
    got = {'start': False, 'item_registry': False, 'creative': False, 'chunks': 0, 'publisher': 0, 'spawn': False,
           'radius': None, 'texts': [], 'moves': 0, 'other': {}}
    runtime = None
    pos = None
    if args.extended:
        bot.scene = Scene(bot, 0)
    sent_radius = False
    initialized = False
    deadline = time.time() + args.play_seconds
    sent_chat = False
    next_move = 0
    tick = 0
    while time.time() < deadline:
        try:
            pid, body = bot.next_game(0.5 if initialized else 2.0)
        except Fail:
            if initialized and time.time() >= next_move and not sent_chat:
                pid, body = None, b''   # nothing is coming: go on with the script
            else:
                continue
        if pid is None:
            pass
        elif pid == 11:
            got['start'] = True
            _, p = read_varuint(body, 0)                       # unique id (zigzag VarLong)
            runtime, p = read_varuint(body, p)
            _, p = read_varuint(body, p)                       # gamemode (zigzag VarInt)
            pos = struct.unpack('<fff', body[p:p + 12])
            print('      StartGame: runtime id %d (%d bytes)' % (runtime, len(body)))
            if not sent_radius:
                sent_radius = True
                bot.send_game(69, varuint(zigzag32(args.radius)) + bytes([args.radius]))
        elif pid == 162:
            got['item_registry'] = True
        elif pid == 145:
            got['creative'] = True
        elif pid == 70:
            v, _ = read_varuint(body, 0)
            got['radius'] = unzigzag(v)
        elif pid == 121:
            got['publisher'] += 1
        elif pid == 58:
            got['chunks'] += 1
        elif pid == 2 and len(body) == 4 and struct.unpack('>i', body)[0] == 3:
            got['spawn'] = True
            print('      PlayStatus PlayerSpawn after %d chunks' % got['chunks'])
            bot.send_game(113, varuint(runtime or 0))
            initialized = True
            deadline = time.time() + max(args.play_seconds, 8)
            next_move = time.time() + 0.2
        elif pid == 9:
            got['texts'].append(body)
        elif pid in (19, 18):
            got['moves'] += 1
        else:
            got['other'][pid] = got['other'].get(pid, 0) + 1
        if initialized and time.time() >= next_move and not sent_chat:
            # walk 2 blocks along +x over 10 inputs, then speak
            got['start_pos'] = pos
            for i in range(10):
                tick += 1
                # StartGame's position is the eye position, which is what PlayerAuthInput carries
                bot.send_game(144, auth_input((pos[0] + 0.2 * (i + 1), pos[1], pos[2]), 0.0, 0.0, tick, (0.2, 0.0, 0.0)))
                time.sleep(0.05)
            got['end_pos'] = (pos[0] + 2.0, pos[1], pos[2])
            print('      walked from (%.2f, %.2f, %.2f) to (%.2f, %.2f, %.2f)' % (pos + got['end_pos']), flush=True)
            msg = args.chat
            bot.send_game(9, bytes([0, 1, 1]) + bstr(args.name) + bstr(msg) + bstr('') + bstr('') + bytes([0]))
            if args.command:
                bot.send_game(77, bstr(args.command) + bstr('player') + b'\x00' * 16 + bstr('1') + struct.pack('<q', -1) + bytes([0]) + bstr('1'))
            sent_chat = True
            print('      sent chat', flush=True)
            hold_end = time.time() + args.hold
            while time.time() < hold_end:
                try:
                    pid, body = bot.next_game(0.3)
                except Fail:
                    continue
                if pid == 9:
                    got['texts'].append(body)
                elif pid == 58:
                    got['chunks'] += 1
                elif pid == 12:
                    got['players_seen'] = got.get('players_seen', 0) + 1
                else:
                    got['other'][pid] = got['other'].get(pid, 0) + 1
            if args.extended:
                extended_phase(bot, args, got, runtime or 0, pos)
            if args.followups:
                followups_phase(bot, args, got, runtime or 0, pos)
            quiet = time.time() + 2.0
            while time.time() < quiet:
                try:
                    pid, body = bot.next_game(1.0)
                except Fail:
                    break
                if pid == 9:
                    got['texts'].append(body)
                elif pid == 58:
                    got['chunks'] += 1
                else:
                    got['other'][pid] = got['other'].get(pid, 0) + 1
            break
    return got


# --- the follow-ups scenario: effects, weather, title, boss bar, equipment, metadata, death and respawn -----------------------
# Every packet layout checked here is the HAND-LAID one of src/protocol/bedrock/client/play_extra.aowl (no real client has
# read them): the bot proves the server writes them as laid out, not that a real Bedrock client accepts them.

def gather(bot, seconds):
    """Every game packet that arrives in `seconds`, as (id, body)."""
    out = []
    end = time.time() + seconds
    while time.time() < end:
        try:
            out.append(bot.next_game(0.3))
        except Fail:
            continue
    return out


def expect_packet(packets, what, pred):
    ok = any(pred(pid, body) for pid, body in packets)
    print(('  ok  ' if ok else 'FAIL  ') + what, flush=True)
    if not ok:
        SOFT_FAILS.append(what)
    return ok


def followups_phase(bot, args, got, runtime, start):
    x, y, z = int(start[0]) + 2, int(start[1]) + 1, int(start[2])
    rt = varuint(runtime)
    # 1. effects: speed 2 for 30 s, then cleared
    console('effect give %s minecraft:speed 30 1' % args.name.replace(' ', '_'))
    pk = gather(bot, 2.0)
    # MobEffect (28): runtime, event 1 add, effect 1 (speed) zigzag 2, amplifier 1 zigzag 2, particles
    expect_packet(pk, 'MobEffect add for speed', lambda i, b: i == 28 and b.startswith(rt + bytes([1, 2, 2])))
    console('effect clear %s' % args.name.replace(' ', '_'))
    pk = gather(bot, 2.0)
    expect_packet(pk, 'MobEffect remove', lambda i, b: i == 28 and b.startswith(rt + bytes([3, 2])))
    # 2. weather
    console('weather rain')
    pk = gather(bot, 2.0)
    expect_packet(pk, 'LevelEvent start rain (3001)', lambda i, b: i == 25 and b.startswith(bytes([0xf2, 0x2e])))
    console('weather clear')
    pk = gather(bot, 2.0)
    expect_packet(pk, 'LevelEvent stop rain (3003)', lambda i, b: i == 25 and b.startswith(varuint(zigzag32(3003))))
    # 3. title and action bar
    console('title %s title {"text":"Hello"}' % args.name.replace(' ', '_'))
    pk = gather(bot, 2.0)
    expect_packet(pk, 'SetTitle (88) with the title text', lambda i, b: i == 88 and b.startswith(bytes([4]) + bstr('Hello')))
    console('title %s actionbar {"text":"Bar"}' % args.name.replace(' ', '_'))
    pk = gather(bot, 2.0)
    expect_packet(pk, 'SetTitle action bar text', lambda i, b: i == 88 and b.startswith(bytes([8]) + bstr('Bar')))
    # 4. boss bar
    console('bossbar add bot:bar {"text":"Boss"}')
    console('bossbar set bot:bar players %s' % args.name.replace(' ', '_'))
    pk = gather(bot, 2.0)
    expect_packet(pk, 'BossEvent (74) add', lambda i, b: i == 74)
    # 5. a zombie in an iron helmet and sword (the Java equipment packet becomes MobEquipment 31 and MobArmorEquipment 32)
    console('summon minecraft:zombie %d %d %d' % (x, y, z))
    console('item replace entity @e[type=minecraft:zombie,limit=1] armor.head with minecraft:iron_helmet')
    console('item replace entity @e[type=minecraft:zombie,limit=1] weapon.mainhand with minecraft:iron_sword')
    pk = gather(bot, 3.0)
    expect_packet(pk, 'MobArmorEquipment (32) for the zombie', lambda i, b: i == 32)
    expect_packet(pk, 'MobEquipment (31) for the zombie', lambda i, b: i == 31)
    # 6. a baby sheep with a name: SetActorData (39) carries the metadata
    console("summon minecraft:sheep %d %d %d {Age:-24000,CustomName:'{\"text\":\"Dolly\"}',Color:5}" % (x + 1, y, z))
    pk = gather(bot, 3.0)
    expect_packet(pk, 'AddActor (13) or SetActorData (39) for the sheep', lambda i, b: i in (13, 39))
    expect_packet(pk, 'the sheep name Dolly is in a packet', lambda i, b: i in (13, 39) and b'Dolly' in b)
    # 7. death and respawn
    console('kill %s' % args.name.replace(' ', '_'))
    pk = gather(bot, 3.0)
    expect_packet(pk, 'SetHealth (42) with health 0', lambda i, b: i == 42 and b == bytes([0]))
    expect_packet(pk, 'ActorEvent (27) death animation', lambda i, b: i == 27 and b.startswith(rt + bytes([3])))
    expect_packet(pk, 'UpdateAttributes (29) health 0', lambda i, b: i == 29 and b'minecraft:health' in b)
    # PlayerAction (36): runtime, action 7 (respawn, zigzag 14), block pos 0 0 0, result pos 0 0 0, face 0
    bot.send_game(36, rt + varuint(zigzag32(7)) + block_pos(0, 0, 0) + block_pos(0, 0, 0) + varuint(zigzag32(0)))
    pk = gather(bot, 4.0)
    expect_packet(pk, 'Respawn (45) searching for spawn', lambda i, b: i == 45 and len(b) == 12 + 1 + len(rt) and b[12] == 0)
    expect_packet(pk, 'Respawn (45) ready to spawn', lambda i, b: i == 45 and b[12] == 1)
    expect_packet(pk, 'MovePlayer (19) teleport to the spawn', lambda i, b: i == 19)
    expect_packet(pk, 'SetHealth (42) back to 20', lambda i, b: i == 42 and b == bytes([40]))
    # the client confirms (state 2); the server must stay up and answer a chat afterwards
    bot.send_game(45, struct.pack('<fff', start[0], start[1], start[2]) + bytes([2]) + rt)
    bot.send_game(9, bytes([0, 1, 1]) + bstr(args.name) + bstr('alive after respawn') + bstr('') + bstr('') + bytes([0]))
    pk = gather(bot, 2.0)
    expect_packet(pk, 'chat still answered after the respawn', lambda i, b: i == 9 and b'alive after respawn' in b)


# --- the extended scenario: hotbar, inventory, place and break, a chest, forms ---------------------------------------------

def container_names():
    """The ContainerName ordinals, read from the server source's enum (the wire value is the ordinal)."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'src', 'protocol', 'bedrock', 'network_item.aowl')
    names = {}
    try:
        text = open(path, encoding='utf-8').read()
        block = text.split('ContainerName* = enum')[1].split('FullContainerName*')[0]
        for i, line in enumerate(l.strip() for l in block.splitlines() if l.strip().startswith('cn')):
            names[line] = i
    except OSError:
        pass
    return names


def varint(v):
    return varuint(zigzag32(v))


def read_varint(buf, pos):
    v, pos = read_varuint(buf, pos)
    return unzigzag(v), pos


def block_pos(x, y, z):
    return varint(x) + varint(y) + varint(z)


def desc(item_id, count, aux=0, block_rid=0):
    """A NetworkItemDescriptor as the server reads it (UseItem and MobEquipment)."""
    if item_id == 0:
        return varint(0)
    return varint(item_id) + struct.pack('<H', count) + varuint(aux) + b'\x00' + varint(block_rid) + varuint(0)


def read_stack(b, p):
    """A NetworkItemStackDescriptor as the server writes it: id, count, aux, optional net id, block runtime id, extra data."""
    item_id = struct.unpack('<h', b[p:p + 2])[0]
    count = struct.unpack('<H', b[p + 2:p + 4])[0]
    p += 4
    aux, p = read_varuint(b, p)
    has_net = b[p]
    p += 1
    if has_net:
        _, p = read_varuint(b, p)
        _, p = read_varuint(b, p)
    rid, p = read_varuint(b, p)
    n, p = read_varuint(b, p)
    return (item_id, count), p + n


def read_full_name(b, p):
    name = b[p]
    p += 1
    dyn = b[p]
    p += 1
    if dyn:
        p += 4
    return name, p


class Scene:
    """What the bot has been told so far, kept up to date from the packets that arrive."""

    def __init__(self, bot, runtime):
        self.bot = bot
        self.runtime = runtime
        self.windows = {}      # window id -> {slot: (item id, count)}
        self.slot_names = {}   # (window, slot) -> container name
        self.blocks = []       # (x, y, z, runtime id) from UpdateBlock
        self.opened = []       # (container id, type, (x, y, z))
        self.closed = []
        self.responses = []    # (request id, result)
        self.forms = []        # (id, json)
        self.texts = []
        self.counts = {}
        self.actors = []
        self.cows = []
        self.commands = 0
        self.attributes = 0
        self.crafting = 0
        self.gamemode = None
        self.abilities = 0

    def take(self, pid, body):
        self.counts[pid] = self.counts.get(pid, 0) + 1
        try:
            if pid == 49:
                window, p = read_varuint(body, 0)
                n, p = read_varuint(body, p)
                slots = {}
                for i in range(n):
                    st, p = read_stack(body, p)
                    slots[i] = st
                self.windows[window] = slots
            elif pid == 50:
                window, p = read_varuint(body, 0)
                slot, p = read_varuint(body, p)
                if body[p]:
                    name, p = read_full_name(body, p + 1)
                    self.slot_names[(window, slot)] = name
                else:
                    p += 1
                if body[p]:
                    _, p = read_stack(body, p + 1)
                else:
                    p += 1
                st, p = read_stack(body, p)
                self.windows.setdefault(window, {})[slot] = st
            elif pid == 21:
                x, p = read_varint(body, 0)
                y, p = read_varint(body, p)
                z, p = read_varint(body, p)
                rid, p = read_varuint(body, p)
                self.blocks.append((x, y, z, rid))
            elif pid == 46:
                cid, ctype = body[0], body[1]
                x, p = read_varint(body, 2)
                y, p = read_varint(body, p)
                z, p = read_varint(body, p)
                self.opened.append((cid, ctype, (x, y, z)))
            elif pid == 47:
                self.closed.append((body[0], body[1], body[2]))
            elif pid == 148:
                n, p = read_varuint(body, 0)
                for _ in range(n):
                    result = body[p]
                    p += 1
                    rid, p = read_varint(body, p)
                    self.responses.append((rid, result))
                    if result == 0:
                        infos, p = read_varuint(body, p)
                        for _ in range(infos):
                            _, p = read_full_name(body, p)
                            slots, p = read_varuint(body, p)
                            for _ in range(slots):
                                p += 3
                                _, p = read_varint(body, p)
                                for _ in range(2):
                                    ln, p = read_varuint(body, p)
                                    p += ln
                                _, p = read_varint(body, p)
            elif pid == 100:
                fid, p = read_varint(body, 0)
                ln, p = read_varuint(body, p)
                self.forms.append((fid, body[p:p + ln].decode()))
            elif pid == 9:
                self.texts.append(body)
            elif pid == 62:
                self.gamemode = unzigzag(read_varuint(body, 0)[0])
            elif pid == 76:
                self.commands += 1
            elif pid == 29:
                self.attributes += 1
            elif pid == 52:
                self.crafting += 1
            elif pid == 187:
                self.abilities += 1
            elif pid == 13:
                self.actors.append(pid)
                _, p = read_varint(body, 0)
                rid, p = read_varuint(body, p)
                ln, p = read_varuint(body, p)
                if body[p:p + ln] == b'minecraft:cow':
                    self.cows.append(rid)
            elif pid == 15:
                self.actors.append(pid)
        except (IndexError, struct.error) as e:
            raise Fail('could not parse packet %d (%d bytes): %r' % (pid, len(body), e))

    def pump(self, seconds):
        end = time.time() + seconds
        while time.time() < end:
            try:
                self.bot.next_game(min(0.3, max(0.05, end - time.time())))
            except Fail:
                continue

    def wait_for(self, what, pred, seconds=6.0):
        end = time.time() + seconds
        while time.time() < end:
            if pred():
                return True
            self.pump(0.2)
        raise Fail('timed out waiting for %s (packets seen: %s)' % (what, sorted(self.counts.items())))


SOFT_FAILS = []


def soft_wait(scene, what, pred, seconds=6.0):
    """Like wait_for, but a miss is recorded and the scenario goes on (the exit status still says it failed)."""
    try:
        scene.wait_for(what, pred, seconds)
        print('  ok  ' + what, flush=True)
        return True
    except Fail as e:
        print('FAIL  ' + str(e), flush=True)
        SOFT_FAILS.append(str(e))
        return False


def console(cmd):
    """Asks the driver to run a server console command (its answer goes to the server log)."""
    print('@console ' + cmd, flush=True)
    time.sleep(1.6)


def use_item_transaction(action, pos, face, hotbar_slot, item, player_pos, click):
    body = varint(0) + b'\x00' + b'\x01' + varuint(2) + b'\x01' + b'\x00'
    body += varuint(action) + b'\x00' + block_pos(*pos) + bytes([face]) + varint(hotbar_slot) + item
    body += struct.pack('<fff', *player_pos) + struct.pack('<fff', *click) + varuint(0) + b'\x00\x00'
    return body


def extended_phase(bot, args, got, runtime, start):
    """Runs after the join, the walk and the chat. Every step asserts something the server did, and the driver checks the
    server's own view (`@console` lines are run by tools/runbedrockfull.py, `@expect` lines are looked for in its log)."""
    names = container_names()
    scene = bot.scene
    scene.runtime = runtime
    scene.pump(1.5)
    check(scene.windows.get(0) is not None and len(scene.windows[0]) == 36, 'InventoryContent (49) for window 0 holds 36 slots')
    check(scene.crafting >= 1, 'CraftingData (52) came with the join (%d)' % scene.crafting)
    check(scene.attributes >= 1, 'UpdateAttributes (29) came with the join (%d)' % scene.attributes)
    check(scene.commands >= 1, 'AvailableCommands (76) came with the join (%d)' % scene.commands)
    check(scene.abilities >= 1, 'UpdateAbilities (187) came with the join (%d)' % scene.abilities)
    check(120 in scene.windows and len(scene.windows[120]) == 4 and 119 in scene.windows, 'armor (120) and offhand (119) contents')

    # hotbar
    bot.send_game(31, varuint(runtime) + varint(0) + bytes([5, 5, 0]))
    scene.pump(0.5)
    console('data get entity Bot_Steve')
    print('@expect SelectedItemSlot: 5', flush=True)
    print('      hotbar slot 5 selected', flush=True)

    # a form, when the server was asked to send one
    if args.form:
        scene.wait_for('ModalFormRequest (100)', lambda: scene.forms, 6.0)
        fid, text = scene.forms[0]
        check('"modal"' in text, 'form %d is the modal form: %s' % (fid, text[:60]))
        bot.send_game(101, varint(fid) + b'\x01' + bstr('true'))
        print('@expect Bedrock form %d answered by Bot_Steve: true' % fid, flush=True)
        scene.pump(1.0)

    # the server gives the player stone: the inventory comes down as Bedrock inventory content
    console('give Bot_Steve minecraft:stone 64')
    scene.pump(1.5)
    stone = [(i, st) for i, st in scene.windows[0].items() if st[0] != 0 and st[1] == 64]
    check(stone, 'the Java give shows in the Bedrock inventory (window 0): %s' % scene.windows[0])
    slot, (item_id, count) = stone[0]
    print('      stone is item %d in slot %d' % (item_id, slot), flush=True)

    # creative: pick from the creative menu into the hotbar through an ItemStackRequest
    console('gamemode creative Bot_Steve')
    scene.pump(0.8)
    check(scene.gamemode == 1, 'SetPlayerGameType (62) says creative: %r' % scene.gamemode)
    hot = names.get('cnHotBar', 28)
    created = names.get('cnCreatedOutput', 59)
    request_id = -3
    action_craft = bytes([14]) + varuint(1) + bytes([1])
    slot_info = lambda name, slot_id: bytes([name, 0, slot_id]) + varint(0)
    action_take = bytes([0, 16]) + slot_info(created, 50) + slot_info(hot, 8)
    bot.send_game(147, varuint(1) + varint(request_id) + varuint(2) + action_craft + action_take + varuint(0) + struct.pack('<i', 0))
    scene.wait_for('ItemStackResponse (148)', lambda: any(r[0] == request_id for r in scene.responses), 4.0)
    check((request_id, 0) in scene.responses, 'creative pick: ItemStackResponse success for request %d' % request_id)
    scene.pump(1.0)
    check(scene.windows[0][8][0] != 0, 'the picked item sits in hotbar slot 8: %r' % (scene.windows[0][8],))
    console('data get entity Bot_Steve')
    print('@expect Slot: 8b', flush=True)

    # place a block: the stone, on the block under the feet two blocks along +x
    feet_y = math.floor(start[1] - 1.62 + 0.001)
    px, pz = math.floor(start[0] + 2.0) + 3, math.floor(start[2])
    target = (px, feet_y - 1, pz)
    console('setblock %d %d %d minecraft:stone' % target)
    console('setblock %d %d %d minecraft:air' % (px, feet_y, pz))
    scene.blocks.clear()
    held = stone[0][0]
    if held < 9:
        bot.send_game(31, varuint(runtime) + varint(0) + bytes([held, held, 0]))
        scene.pump(0.3)
    use = use_item_transaction(0, target, 1, held if held < 9 else 0, desc(item_id, 64), (start[0] + 2.0, start[1], start[2]), (0.5, 1.0, 0.5))
    bot.send_game(30, use)
    soft_wait(scene, 'an UpdateBlock for the placed block', lambda: any((b[0], b[1], b[2]) == (px, feet_y, pz) for b in scene.blocks), 8.0)
    placed = [b for b in scene.blocks if (b[0], b[1], b[2]) == (px, feet_y, pz)]
    print('      block updates after the click: %s' % scene.blocks[:4], flush=True)
    check(placed, 'UpdateBlock (21) for the block placed at %s' % ((px, feet_y, pz),))
    placed_rid = placed[-1][3] if placed else -1

    # break it: StartBreak in creative is instant
    scene.blocks.clear()
    bot.send_game(36, varint(runtime) + varint(0) + block_pos(px, feet_y, pz) + block_pos(px, feet_y, pz) + varint(1))
    soft_wait(scene, 'an UpdateBlock for the broken block', lambda: any((b[0], b[1], b[2]) == (px, feet_y, pz) for b in scene.blocks), 8.0)
    broken = [b for b in scene.blocks if (b[0], b[1], b[2]) == (px, feet_y, pz)]
    check(broken and broken[-1][3] != placed_rid, 'UpdateBlock (21) for the block broken at %s: %s' % ((px, feet_y, pz), broken))

    # a chest: opened with an empty hand, taken from, closed again
    cx, cy, cz = px, feet_y, pz + 2
    console('setblock %d %d %d minecraft:chest' % (cx, cy, cz))
    scene.opened.clear()
    scene.pump(0.5)
    bot.send_game(30, use_item_transaction(0, (cx, cy, cz), 1, 8, desc(0, 0), (cx - 1.0, start[1], cz), (0.5, 1.0, 0.5)))
    scene.wait_for('ContainerOpen (46)', lambda: scene.opened, 6.0)
    cid, ctype, cpos = scene.opened[0]
    check(ctype == 0 and cpos == (cx, cy, cz), 'ContainerOpen (46): chest window %d at %s' % (cid, cpos))
    scene.pump(1.0)
    chest = scene.windows.get(cid, {})
    check(len(chest) == 27, 'the chest has 27 slots: %d' % len(chest))
    level = names.get('cnLevelEntity', 7)
    picked = scene.windows[0][8]
    check(picked[0] != 0 and picked[1] >= 2, 'the creative pick in hotbar 8 can be shared: %r' % (picked,))
    # put 2 of the picked item into chest slot 0, over the container protocol
    bot.send_game(147, varuint(1) + varint(-4) + varuint(1) + bytes([1, 2]) + slot_info(hot, 8) + slot_info(level, 0)
                  + varuint(0) + struct.pack('<i', 0))
    scene.wait_for('ItemStackResponse (148)', lambda: any(r[0] == -4 for r in scene.responses), 4.0)
    check((-4, 0) in scene.responses, 'placing 2 items into the chest: ItemStackResponse success')
    # close and open again: the chest keeps them (the contents come from the server's own container)
    bot.send_game(47, bytes([cid, ctype, 0]))
    scene.wait_for('ContainerClose echo', lambda: scene.closed, 4.0)
    scene.closed.clear()
    scene.opened.clear()
    bot.send_game(30, use_item_transaction(0, (cx, cy, cz), 1, 8, desc(0, 0), (cx - 1.0, start[1], cz), (0.5, 1.0, 0.5)))
    scene.wait_for('ContainerOpen (46) again', lambda: scene.opened, 6.0)
    cid, ctype, cpos = scene.opened[0]
    scene.pump(1.0)
    chest = scene.windows.get(cid, {})
    check(chest.get(0, (0, 0)) == (picked[0], 2), 'the chest kept 2 of the item in slot 0: %r' % (chest.get(0),))
    # take them back out into hotbar slot 7
    bot.send_game(147, varuint(1) + varint(-5) + varuint(1) + bytes([0, 2]) + slot_info(level, 0) + slot_info(hot, 7)
                  + varuint(0) + struct.pack('<i', 0))
    scene.wait_for('ItemStackResponse (148)', lambda: any(r[0] == -5 for r in scene.responses), 4.0)
    check((-5, 0) in scene.responses, 'taking the items out of the chest: ItemStackResponse success')
    console('data get entity Bot_Steve')
    print('@expect Slot: 7b', flush=True)
    bot.send_game(47, bytes([cid, ctype, 0]))
    scene.wait_for('ContainerClose echo', lambda: scene.closed, 4.0)
    check(scene.closed[0][0] == cid, 'ContainerClose (47) answered for window %d' % cid)

    # the inventory screen: Interaction OpenInventory, then close
    scene.opened.clear()
    scene.closed.clear()
    bot.send_game(33, bytes([6]) + varuint(0) + b'\x00')
    scene.wait_for('ContainerOpen (46) for the inventory', lambda: scene.opened, 4.0)
    check(scene.opened[0][:2] == (0, 255), 'OpenInventory answered with ContainerOpen of window 0, type 255: %r' % (scene.opened[0],))
    bot.send_game(47, bytes([0, 255, 0]))
    scene.wait_for('ContainerClose echo', lambda: scene.closed, 4.0)

    # block pick: the stone under the player goes to hotbar slot 4 (creative takes it from nothing)
    scene.counts[48] = 0
    bot.send_game(34, block_pos(px, feet_y - 1, pz) + b'\x00' + bytes([4]))
    scene.wait_for('PlayerHotbar (48) after the block pick', lambda: scene.counts.get(48, 0) >= 1, 4.0)
    scene.pump(0.5)
    check(scene.windows[0][4][0] != 0, 'the picked block sits in hotbar slot 4: %r' % (scene.windows[0][4],))

    # an emote: the server must keep the connection (nobody else is there to see it)
    bot.send_game(138, varuint(runtime) + bstr('emote-1') + struct.pack('<I', 5) + bstr('') + bstr('') + bytes([0]))
    scene.pump(0.5)

    # a legacy world action: dropping one of the stone makes an item entity, which arrives as AddItemActor (15)
    scene.actors.clear()
    drop = varint(0) + b'\x00' + b'\x01' + varuint(0) + b'\x01' + b'\x01' + varuint(1)
    drop += varuint(2) + varuint(0) + varuint(0) + desc(0, 0) + desc(item_id, 1)
    bot.send_game(30, drop)
    soft_wait(scene, 'AddItemActor (15) for the dropped stone', lambda: 15 in scene.actors, 6.0)

    # a cow: AddActor (13) with its type, hit with a UseItemOnEntity attack
    scene.actors.clear()
    console('summon minecraft:cow %d %d %d' % (px - 6, feet_y, pz))
    if soft_wait(scene, 'AddActor (13) for the cow', lambda: scene.cows, 6.0):
        cow = scene.cows[0]
        print('      cow runtime id %d' % cow, flush=True)
    else:
        cow = 0
    attack = varint(0) + b'\x00' + b'\x01' + varuint(3) + b'\x01' + b'\x00'
    attack += varuint(cow) + varuint(1) + varint(0) + desc(0, 0) + struct.pack('<fff', 0, 0, 0) + struct.pack('<fff', 0, 0, 0)
    bot.send_game(30, attack)
    scene.pump(1.0)
    console('list')
    print('@expect There are 1 of a max of 1000 players online: Bot_Steve', flush=True)

    # PlayerAction DropItem
    bot.send_game(36, varint(runtime) + varint(4) + block_pos(0, 0, 0) + block_pos(0, 0, 0) + varint(0))
    scene.pump(1.0)
    got['scene'] = scene
    if SOFT_FAILS:
        raise Fail('%d step(s) failed: %s' % (len(SOFT_FAILS), '; '.join(SOFT_FAILS)))
    return scene


def run(args):
    self_test_aes()
    bot = Bot(args.host, args.port, args.name, not args.no_encrypt)
    t0 = time.time()
    print('bedrock bot -> %s:%d as %r (local %s:%d)' % (args.host, args.port, args.name, *bot.local), flush=True)

    # 1. unconnected ping
    ping_time = 0x0102030405
    ping = b'\x01' + struct.pack('>Q', ping_time) + MAGIC + struct.pack('>Q', bot.guid)
    d = None
    for attempt in range(6):
        # a busy server (a Java player joining) can answer late: ask again before giving up
        try:
            d = bot.offline(ping, 3.0)
            break
        except socket.timeout:
            continue
    if d is None:
        raise Fail('no answer to the unconnected ping')
    bot.sock.settimeout(0.5)
    try:
        while True:
            bot.sock.recvfrom(4096)     # the late answers to the repeated pings
    except socket.timeout:
        pass
    check(d[0] == 0x1C, 'unconnected pong id 0x1c')
    check(struct.unpack('>Q', d[1:9])[0] == ping_time, 'pong echoes the ping time (big-endian)')
    server_guid = struct.unpack('>Q', d[9:17])[0]
    check(d[17:33] == MAGIC, 'pong magic')
    strlen = struct.unpack('>H', d[33:35])[0]
    check(len(d) == 35 + strlen, 'pong string length is big-endian and exact')
    info = d[35:].decode().split(';')
    print('      server info:', info)
    check(info[0] == 'MCPE' and info[2] == '1001' and info[3] == '1.26.30', 'server info: edition and protocol 1001')
    check(int(info[6]) == server_guid, 'server info carries the same guid')
    if args.ping_only:
        return 0

    # 2. open connection
    d = bot.offline(b'\x05' + MAGIC + bytes([10]) + b'\x00' * 1400)
    if args.expect_full:
        check(d[0] == 0x14 and d[1:17] == MAGIC and struct.unpack('>Q', d[17:25])[0] == server_guid, 'no free incoming connections')
        return 0
    check(d[0] == 0x19 and d[1] == 11 and d[2:18] == MAGIC and struct.unpack('>Q', d[18:26])[0] == server_guid,
          'wrong RakNet version -> incompatible protocol 11 (guid big-endian)')
    d = bot.offline(b'\x05' + MAGIC + bytes([11]) + b'\x00' * (bot.mtu - 28 - 18))
    check(d[0] == 0x06 and d[1:17] == MAGIC, 'open connection reply 1')
    check(struct.unpack('>Q', d[17:25])[0] == server_guid, 'reply 1 guid is big-endian and matches the pong')
    check(d[25] == 0, 'reply 1: no security')
    check(struct.unpack('>H', d[26:28])[0] == 1400 and len(d) == 28, 'reply 1 MTU 1400, big-endian')
    d = bot.offline(b'\x07' + MAGIC + rak_addr(args.host, args.port) + struct.pack('>H', 1400) + struct.pack('>Q', bot.guid))
    check(d[0] == 0x08 and d[1:17] == MAGIC and struct.unpack('>Q', d[17:25])[0] == server_guid, 'open connection reply 2')
    addr, pos = parse_rak_addr(d, 25)
    check(addr == bot.local, 'reply 2 shows our address as an inverted-octet SystemAddress: %s:%d' % addr)
    check(struct.unpack('>H', d[pos:pos + 2])[0] == 1400 and d[pos + 2] == 0 and len(d) == pos + 3, 'reply 2: MTU big-endian, no encryption')

    # 3. connection request
    bot.send_rak(b'\x09' + struct.pack('>QQ', bot.guid, 0x1234) + b'\x00')
    p = bot.next_rak()
    check(p[0] == 0x10, 'connection request accepted (0x10)')
    addr, pos = parse_rak_addr(p, 1)
    check(addr == bot.local, 'accepted shows our address')
    check(struct.unpack('>H', p[pos:pos + 2])[0] == 0, 'system index big-endian zero')
    pos += 2
    for _ in range(10):
        _, pos = parse_rak_addr(p, pos)
    check(struct.unpack('>Q', p[pos:pos + 8])[0] == 0x1234, 'accepted echoes the request time (big-endian)')
    check(len(p) == pos + 16, 'accepted length')
    bot.send_rak(b'\x13' + rak_addr(args.host, args.port) + rak_addr('127.0.0.1', bot.local[1]) * 1 + struct.pack('>QQ', 0x1234, 0x1235))
    bot.send_rak(b'\x00' + struct.pack('>Q', 0xABCDEF))
    p = bot.next_rak()
    check(p[0] == 0x03 and struct.unpack('>Q', p[1:9])[0] == 0xABCDEF and len(p) == 17, 'connected pong echoes the ping time (big-endian)')

    # 4. network settings
    bot.send_game(0xC1, struct.pack('>i', 1001))
    pid, body = bot.next_game()
    check(pid == 143, 'NetworkSettings (143)')
    threshold, method = struct.unpack('<HH', body[:4])
    check(method == 0, 'compression: zlib (method 0), threshold %d' % threshold)
    bot.compress = True

    # 5. login
    key = int.from_bytes(os.urandom(48), 'big') % N or 1
    pub = pt_mul(key, G)
    pub_b64 = b64(spki(pub))
    header = b64(json.dumps({'alg': 'ES384', 'x5u': pub_b64}, separators=(',', ':')).encode(), True, False)
    payload = b64(json.dumps({'cpk': pub_b64, 'xname': args.name, 'xid': '2535400000000042', 'exp': int(time.time()) + 3600,
                              'iss': 'bot'}, separators=(',', ':')).encode(), True, False)
    token = header + '.' + payload + '.' + b64(ecdsa_sign(key, (header + '.' + payload).encode()), True, False)
    auth_type = 2
    if args.oidc_key:
        # online mode: an OIDC token signed by the key the driver published in its local JWKS (the Xbox keys cannot be had offline)
        oidc_header = b64(json.dumps({'alg': 'ES384', 'kid': args.oidc_kid, 'typ': 'JWT'}, separators=(',', ':')).encode(), True, False)
        oidc_payload = b64(json.dumps({'iss': args.oidc_issuer, 'aud': 'api://auth-minecraft-services/multiplayer', 'cpk': pub_b64,
                                       'xname': args.name, 'xid': '2535400000000042', 'exp': int(time.time()) + 3600},
                                      separators=(',', ':')).encode(), True, False)
        oidc_sig = b64(ecdsa_sign(int(args.oidc_key, 16), (oidc_header + '.' + oidc_payload).encode()), True, False)
        token = oidc_header + '.' + oidc_payload + '.' + oidc_sig
        auth_type = 0
    identity = json.dumps({'AuthenticationType': auth_type, 'Token': token, 'Certificate': ''}, separators=(',', ':')).encode()
    client_data = json.dumps({'ClientRandomId': -1234567890123, 'DeviceOS': 7, 'DeviceId': 'bot-1', 'GameVersion': '1.26.30',
                              'LanguageCode': 'en_US', 'CurrentInputMode': 1, 'DefaultInputMode': 1, 'UIProfile': 0,
                              'ServerAddress': '%s:%d' % (args.host, args.port), 'MaxViewDistance': 8},
                             separators=(',', ':')).encode()
    raw = (b64(b'{"alg":"ES384"}', True, False) + '.' + b64(client_data, True, False) + '.' + b64(b'sig', True, False)).encode()
    body = struct.pack('>i', 1001) + varuint(4 + len(identity) + 4 + len(raw)) + struct.pack('<I', len(identity)) + identity \
        + struct.pack('<I', len(raw)) + raw
    bot.send_game(0x01, body)
    if bot.encrypt:
        t_hs = time.time()
        pid, body = bot.next_game(30.0)
        print('      handshake came after %.2fs' % (time.time() - t_hs))
        check(pid == 3, 'server-to-client handshake (3)')
        ln, pos = read_varuint(body, 0)
        jwt = body[pos:pos + ln].decode()
        h, pl, sg = jwt.split('.')
        x5u = json.loads(b64d(h))['x5u']
        server_pub = point_from_spki(b64d(x5u))
        check(ecdsa_verify(server_pub, (h + '.' + pl).encode(), b64d(sg)), 'handshake JWT is signed ES384 by its x5u key')
        salt = b64d(json.loads(b64d(pl))['salt'])
        check(len(salt) == 16, 'salt is 16 bytes')
        shared = pt_mul(key, server_pub)[0].to_bytes(48, 'big')
        bot.key = hashlib.sha256(salt + shared).digest()
        iv = bot.key[:12] + b'\x00\x00\x00\x02'
        bot.enc = Ctr(bot.key, iv)
        bot.dec = Ctr(bot.key, iv)
        bot.send_game(0x04, b'')
    pid, body = bot.next_game()
    check(pid == 2 and body == b'\x00\x00\x00\x00', 'PlayStatus LoginSuccess (big-endian 0)' + (', encrypted' if bot.encrypt else ''))
    pid, body = bot.next_game()
    check(pid == 6, 'ResourcePacksInfo (6)')
    check(body[0] == 0 and len(body) >= 4 + 16 + 1 + 2, 'packs info: not required, no packs')

    # 6. resource packs
    bot.send_game(129, b'\x00')  # ClientCacheStatus: no blob cache
    bot.send_game(8, bytes([3]) + struct.pack('<H', 0))
    pid, body = bot.next_game()
    check(pid == 7, 'ResourcePackStack (7)')
    check(b'1.26.30' in body, 'stack names game version 1.26.30')
    bot.send_game(8, bytes([4]) + struct.pack('<H', 0))
    if args.play:
        got = play_phase(bot, args)
        print('      play: %s' % {k: v for k, v in got.items() if k != 'texts'})
        check(got['start'], 'StartGame (11) received')
        check(got['item_registry'] and got['creative'], 'ItemRegistry (162) and CreativeContent (145) received')
        check(got['radius'] is not None and got['radius'] >= 2, 'ChunkRadiusUpdate (70) answers the request: %s' % got['radius'])
        check(got['chunks'] >= 9, 'LevelChunk (58) packets received: %d' % got['chunks'])
        check(got['publisher'] >= 1, 'NetworkChunkPublisherUpdate (121) received')
        check(got['spawn'], 'PlayStatus PlayerSpawn received')
        if args.expect_block:
            check(got['other'].get(21, 0) >= 1, 'UpdateBlock (21) arrived for the block the console changed: %d' % got['other'].get(21, 0))
        if got.get('players_seen') or got['other'].get(12):
            print('      AddPlayer (12) for other players: %d' % (got.get('players_seen', 0) + got['other'].get(12, 0)))
        said = [t for t in got['texts'] if args.chat.encode() in t]
        check(said, 'the chat message came back as a Text packet (%d texts)' % len(got['texts']))
        if args.command:
            print('      texts after the command:', [t[-60:] for t in got['texts']][-3:])
        bot.send_rak(b'\x15')
        print('done in %.1fs' % (time.time() - t0))
        return 0
    time.sleep(0.3)

    # 7. alive after the exchange
    bot.send_rak(b'\x00' + struct.pack('>Q', 0x7777))
    for _ in range(20):
        p = bot.next_payload(2.0)
        if p[0] == 0x03:
            check(struct.unpack('>Q', p[1:9])[0] == 0x7777, 'still answering connected pings after joining')
            break
    else:
        raise Fail('no pong after the exchange')
    bot.send_rak(b'\x15')  # disconnect notification
    print('done in %.1fs' % (time.time() - t0))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--host', default='127.0.0.1')
    ap.add_argument('--port', type=int, required=True)
    ap.add_argument('--name', default='Bot Steve')
    ap.add_argument('--no-encrypt', action='store_true', help='the server runs without encryption')
    ap.add_argument('--ping-only', action='store_true')
    ap.add_argument('--play', action='store_true', help='after the login: StartGame, chunks, spawn, move, chat (needs the full server)')
    ap.add_argument('--play-seconds', type=float, default=40.0)
    ap.add_argument('--radius', type=int, default=4)
    ap.add_argument('--chat', default='hello from the bedrock bot')
    ap.add_argument('--command', default='')
    ap.add_argument('--expect-block', action='store_true', help='with --play: an UpdateBlock (21) must arrive while holding (a driver changes a block)')
    ap.add_argument('--hold', type=float, default=0.0, help='with --play: stay this long after the chat (a driver can ask the server things)')
    ap.add_argument('--x', type=float, default=None)
    ap.add_argument('--y', type=float, default=None)
    ap.add_argument('--z', type=float, default=None)
    ap.add_argument('--expect-full', action='store_true')
    ap.add_argument('--oidc-key', default='', help='hex scalar of the key the local JWKS publishes: log in with AuthenticationType 0')
    ap.add_argument('--oidc-kid', default='')
    ap.add_argument('--oidc-issuer', default='')
    ap.add_argument('--extended', action='store_true', help='with --play: hotbar, inventory, place and break, chest, form (see extended_phase)')
    ap.add_argument('--followups', action='store_true', help='with --play: effects, weather, title, boss bar, equipment, metadata, death and respawn (see followups_phase)')
    ap.add_argument('--form', action='store_true', help='with --extended: the server was started to send a form (PUMPKIN_BEDROCK_TEST_FORM)')
    args = ap.parse_args()
    try:
        return run(args)
    except Fail as e:
        print('FAIL: ' + str(e))
        return 1
    except socket.timeout:
        print('FAIL: timed out')
        return 1


if __name__ == '__main__':
    sys.exit(main())
