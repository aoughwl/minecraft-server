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

Exit status 0 only if every step held. `--ping-only` stops after step 1. `--expect-full` wants the server to answer open
connection request 1 with NoFreeIncomingConnections. Run it against src/server/net/bedrock/bedrockdemo.aowl (see
tools/runbedrock.py) or a full server with Bedrock enabled; it never uses a fixed port.
"""
import argparse
import base64
import hashlib
import json
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

    # offline
    def offline(self, data, wait=2.0):
        self.sock.sendto(data, self.addr)
        return self.recv_offline(wait)

    def recv_offline(self, wait=2.0):
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
    sent_radius = False
    initialized = False
    deadline = time.time() + args.play_seconds
    sent_chat = False
    next_move = 0
    tick = 0
    while time.time() < deadline:
        try:
            pid, body = bot.next_game(2.0)
        except Fail:
            if initialized:
                break
            continue
        if pid == 11:
            got['start'] = True
            _, p = read_varuint(body, 0)                       # unique id (zigzag VarLong)
            runtime, p = read_varuint(body, p)
            pos = struct.unpack('<fff', body[p + 1:p + 13]) if False else None
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
            for i in range(10):
                tick += 1
                bot.send_game(144, auth_input((0.5 + 0.2 * (i + 1) + (args.x or 0), (args.y or 100.0) + 1.62, 0.5 + (args.z or 0)), 0.0, 0.0, tick, (0.2, 0.0, 0.0)))
                time.sleep(0.05)
            msg = args.chat
            bot.send_game(9, bytes([0, 1, 1]) + bstr(args.name) + bstr(msg) + bstr('') + bstr('') + bytes([0]))
            if args.command:
                bot.send_game(77, bstr(args.command) + bstr('player') + b'\x00' * 16 + bstr('1') + struct.pack('<q', -1) + bytes([0]) + bstr('1'))
            sent_chat = True
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


def run(args):
    self_test_aes()
    bot = Bot(args.host, args.port, args.name, not args.no_encrypt)
    t0 = time.time()
    print('bedrock bot -> %s:%d as %r (local %s:%d)' % (args.host, args.port, args.name, *bot.local), flush=True)

    # 1. unconnected ping
    ping_time = 0x0102030405
    d = bot.offline(b'\x01' + struct.pack('>Q', ping_time) + MAGIC + struct.pack('>Q', bot.guid))
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
    identity = json.dumps({'AuthenticationType': 2, 'Token': token, 'Certificate': ''}, separators=(',', ':')).encode()
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
    ap.add_argument('--x', type=float, default=None)
    ap.add_argument('--y', type=float, default=None)
    ap.add_argument('--z', type=float, default=None)
    ap.add_argument('--expect-full', action='store_true')
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
