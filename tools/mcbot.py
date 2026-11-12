#!/usr/bin/env python3
"""A small Minecraft 1.21.11 (protocol 774) client that joins a server and checks what it is sent.

    python tools/mcbot.py --port 25599 [--host 127.0.0.1] [--name McBot] [--seconds 30]

Standard library only. It goes through status ping, login, configuration and play, answering what a client must
(known packs, finish configuration, keep-alive, teleport confirm, chunk batch), prints every packet id it receives,
and exits non-zero unless all of these held:

- every stage was reached, and a CLogin arrived;
- every registry entry and block entity is well-formed NBT;
- one chunk parses down to its section palettes, with block state ids below 1.21.11's 29671 and biome ids below the
  size of the biome registry the server sent, and no bytes left over;
- the server stayed up and answered keep-alives for --seconds;
- after a clean disconnect the server still answers a status ping, and no longer counts the player.

With --play it also plays, on a save it may change, in this order, asserting each answer:

- it gets its inventory as window 0, 46 slots, and a health packet;
- it walks and rotates, then pings;
- with --op (the server's data/ops.json must list it) it switches to creative, takes 64 stone from the creative
  inventory, and the server echoes nothing wrong;
- it sets its held slot, swings, sneaks, sprints;
- it breaks a block next to it (the block_update says air, block_changed_ack echoes the sequence);
- it places a stone in the hole (block_update says stone, the stack shrinks in creative not at all);
- it opens its inventory the only way a client can, by clicking in window 0: picks a stack up with the cursor and puts it
  back, and closes the window;
- it chats, and hears its own message back as a system message;
- it asks for command suggestions, and sends an unknown command;
- it leaves.

Then --verify <file> names a JSON file the first run wrote. A second run reads it, joins again and checks the placed block in
the chunk it is sent, its own position, its inventory and its game mode. Restart the server between the runs to test the disk.

--far-chunk X,Z walks far enough that the chunk at X,Z has to be generated, and fails unless it arrives parsed while
keep-alives keep coming.

--encrypt answers the server's encryption request (RSA and AES-CFB8, in pure Python, so it stops once it is in play: a
world's worth of chunks would take minutes through it). --expect-refusal TEXT wants a disconnect containing TEXT at login.
--dimension NAME wants CLogin to say that dimension.

--watch stays until another player has appeared, moved, swung, changed a block near it and chatted, and left: what a second
client must be told.

Ids and layouts are protocol 774's, the ones aoughwl.mcnet (the game client's decoder) reads.
"""
import argparse
import base64
import hashlib
import hmac
import os
import json
import socket
import struct
import sys
import time
import zlib

PROTOCOL = 774
BLOCK_STATES_1_21_11 = 29671  # block_state_remap's source table
DEFAULT_SECTIONS = 24

# Clientbound
LOGIN_DISCONNECT, LOGIN_HELLO, LOGIN_FINISHED, LOGIN_COMPRESSION = 0, 1, 2, 3
CFG_PAYLOAD, CFG_DISCONNECT, CFG_FINISH, CFG_KEEP_ALIVE, CFG_REGISTRY, CFG_FEATURES, CFG_TAGS, CFG_KNOWN_PACKS, CFG_LINKS = (
    1, 2, 3, 4, 7, 12, 13, 14, 16)
PLAY_BATCH_END, PLAY_BATCH_START, PLAY_DISCONNECT, PLAY_CHUNK, PLAY_KEEP_ALIVE, PLAY_LOGIN, PLAY_POSITION = (
    11, 12, 32, 44, 43, 48, 70)
PLAY_CENTER, PLAY_SPAWN_POS, PLAY_TIME, PLAY_SYSTEM_CHAT, PLAY_GAME_EVENT = 92, 95, 111, 119, 38
# Serverbound
SB_CFG_INFO, SB_CFG_FINISH, SB_CFG_KEEP_ALIVE, SB_CFG_KNOWN_PACKS = 0, 3, 4, 7
SB_LOGIN_HELLO, SB_LOGIN_KEY, SB_LOGIN_ACK = 0, 1, 3
SB_TELEPORT, SB_BATCH, SB_KEEP_ALIVE, SB_LOADED = 0, 10, 27, 43
SB_CHANGE_GAME_MODE, SB_CHAT_COMMAND, SB_CHAT, SB_CLIENT_COMMAND, SB_COMMAND_SUGGESTION, SB_CONTAINER_CLICK, SB_CONTAINER_CLOSE = (
    4, 6, 8, 11, 14, 17, 18)
SB_MOVE_POS, SB_MOVE_POS_ROT, SB_PING, SB_ACTION, SB_COMMAND, SB_INPUT, SB_CARRIED, SB_CREATIVE, SB_SWING, SB_USE_ON, SB_USE = (
    29, 30, 37, 40, 41, 42, 52, 55, 60, 63, 64)
# Clientbound, in play, for --play.
PLAY_BLOCK_ACK, PLAY_BLOCK_DESTRUCTION, PLAY_BLOCK_UPDATE, PLAY_SECTION_UPDATE, PLAY_CONTAINER_CONTENT, PLAY_CONTAINER_DATA = (
    4, 5, 8, 82, 18, 19)
PLAY_CONTAINER_SLOT, PLAY_FORGET_CHUNK, PLAY_PONG, PLAY_CURSOR, PLAY_EQUIPMENT, PLAY_EXPERIENCE, PLAY_HEALTH, PLAY_PLAYER_INV = (
    20, 37, 60, 94, 100, 101, 102, 106)
PLAY_ANIMATE, PLAY_SUGGESTIONS = 2, 15
PLAY_ADD_ENTITY, PLAY_MOVE_POS, PLAY_MOVE_POS_ROT, PLAY_ROTATE_HEAD, PLAY_REMOVE_ENTITIES = 1, 51, 52, 81, 75
STONE_ITEM = 1    # item id of minecraft:stone in 774
STONE_STATE = 1   # its default block state


class Fail(Exception):
    pass


def check(cond, why):
    if not cond:
        raise Fail(why)


class Reader:
    def __init__(self, data):
        self.data = bytes(data)
        self.at = 0

    def left(self):
        return len(self.data) - self.at

    def take(self, n):
        check(n >= 0 and self.at + n <= len(self.data), 'read past the end of a packet (want %d, %d left)' % (n, self.left()))
        out = self.data[self.at:self.at + n]
        self.at += n
        return out

    def u8(self):
        return self.take(1)[0]

    def boolean(self):
        return self.u8() != 0

    def i16(self):
        return struct.unpack('>h', self.take(2))[0]

    def i32(self):
        return struct.unpack('>i', self.take(4))[0]

    def i64(self):
        return struct.unpack('>q', self.take(8))[0]

    def f32(self):
        return struct.unpack('>f', self.take(4))[0]

    def f64(self):
        return struct.unpack('>d', self.take(8))[0]

    def varint(self):
        value = 0
        for shift in range(0, 35, 7):
            b = self.u8()
            value |= (b & 0x7F) << shift
            if not b & 0x80:
                return value - (1 << 32) if value >= (1 << 31) else value
        raise Fail('a VarInt longer than five bytes')

    def string(self):
        n = self.varint()
        check(0 <= n <= 0x7FFFF, 'a string of impossible length %d' % n)
        return self.take(n).decode('utf-8')


def varint(value):
    value &= 0xFFFFFFFF
    out = bytearray()
    while True:
        if value < 0x80:
            out.append(value)
            return bytes(out)
        out.append((value & 0x7F) | 0x80)
        value >>= 7


def string(s):
    b = s.encode('utf-8')
    return varint(len(b)) + b


def skip_nbt_payload(r, kind, depth=0):
    check(depth < 64, 'NBT nested too deep')
    if kind == 1:
        r.take(1)
    elif kind == 2:
        r.take(2)
    elif kind == 3 or kind == 5:
        r.take(4)
    elif kind == 4 or kind == 6:
        r.take(8)
    elif kind == 7:
        r.take(r.i32())
    elif kind == 8:
        n = struct.unpack('>H', r.take(2))[0]
        r.take(n)
    elif kind == 9:
        inner = r.u8()
        n = r.i32()
        check(inner != 0 or n <= 0, 'an NBT list of TAG_End with entries')
        for _ in range(n):
            skip_nbt_payload(r, inner, depth + 1)
    elif kind == 10:
        while True:
            t = r.u8()
            if t == 0:
                return
            n = struct.unpack('>H', r.take(2))[0]
            r.take(n)
            skip_nbt_payload(r, t, depth + 1)
    elif kind == 11:
        r.take(r.i32() * 4)
    elif kind == 12:
        r.take(r.i32() * 8)
    else:
        raise Fail('unknown NBT tag %d' % kind)


def skip_network_nbt(r):
    """Network NBT: one type byte, no root name."""
    kind = r.u8()
    check(kind != 0, 'an empty NBT document where one was required')
    skip_nbt_payload(r, kind)
    return kind


AES_SBOX = None


def aes_sbox():
    global AES_SBOX
    if AES_SBOX is None:
        box = [0] * 256
        p = q = 1
        while True:
            p = p ^ ((p << 1) & 0xFF) ^ (0x1B if p & 0x80 else 0)
            q ^= q << 1
            q ^= q << 2
            q ^= q << 4
            q &= 0xFF
            if q & 0x80:
                q ^= 0x09
            x = q ^ ((q << 1) | (q >> 7)) & 0xFF ^ ((q << 2) | (q >> 6)) & 0xFF ^ ((q << 3) | (q >> 5)) & 0xFF ^ \
                ((q << 4) | (q >> 4)) & 0xFF
            box[p] = (x ^ 0x63) & 0xFF
            if p == 1:
                break
        box[0] = 0x63
        AES_SBOX = box
    return AES_SBOX


class AesCfb8:
    """AES-128 in CFB8, the login stream cipher. One block cipher call per byte, so slow."""

    def __init__(self, key):
        box = aes_sbox()
        w = list(key)
        rcon = 1
        while len(w) < 176:
            t = w[-4:]
            if len(w) % 16 == 0:
                t = [box[t[1]] ^ rcon, box[t[2]], box[t[3]], box[t[0]]]
                rcon = (rcon << 1) ^ (0x11B if rcon & 0x80 else 0)
            w += [w[len(w) - 16 + i] ^ t[i] for i in range(4)]
        self.round_keys = w
        self.iv = bytearray(key)

    def block(self, data):
        box = aes_sbox()
        rk = self.round_keys
        st = [data[i] ^ rk[i] for i in range(16)]

        def xt(a):
            return ((a << 1) ^ 0x1B) & 0xFF if a & 0x80 else a << 1

        for r in range(1, 11):
            st = [box[b] for b in st]
            st = [st[0], st[5], st[10], st[15], st[4], st[9], st[14], st[3], st[8], st[13], st[2], st[7], st[12], st[1], st[6], st[11]]
            if r != 10:
                out = []
                for c in range(0, 16, 4):
                    a, b, cc, d = st[c:c + 4]
                    out += [xt(a) ^ xt(b) ^ b ^ cc ^ d, a ^ xt(b) ^ xt(cc) ^ cc ^ d, a ^ b ^ xt(cc) ^ xt(d) ^ d,
                            xt(a) ^ a ^ b ^ cc ^ xt(d)]
                st = out
            st = [st[i] ^ rk[r * 16 + i] for i in range(16)]
        return st

    def encrypt(self, data):
        out = bytearray()
        for b in data:
            c = b ^ self.block(self.iv)[0]
            out.append(c)
            self.iv = self.iv[1:] + bytes([c])
        return bytes(out)

    def decrypt(self, data):
        out = bytearray()
        for c in data:
            out.append(c ^ self.block(self.iv)[0])
            self.iv = self.iv[1:] + bytes([c])
        return bytes(out)


def der_read(data, at):
    """(tag, content start, content end, next) of the TLV at `at`."""
    tag = data[at]
    n = data[at + 1]
    at += 2
    if n & 0x80:
        count = n & 0x7F
        n = int.from_bytes(data[at:at + count], 'big')
        at += count
    return tag, at, at + n, at + n


def rsa_public_from_spki(der):
    _, a, _, _ = der_read(der, 0)
    _, _, _, b = der_read(der, a)       # the algorithm
    tag, c, _, _ = der_read(der, b)
    check(tag == 3, 'the public key is not a bit string')
    _, d, _, _ = der_read(der, c + 1)   # the RSAPublicKey
    _, n0, n1, e_at = der_read(der, d)
    _, e0, e1, _ = der_read(der, e_at)
    return int.from_bytes(der[n0:n1], 'big'), int.from_bytes(der[e0:e1], 'big')


def rsa_encrypt(n, e, message):
    k = (n.bit_length() + 7) // 8
    padding = bytes(b % 255 + 1 for b in os.urandom(k - len(message) - 3))
    em = b'\x00\x02' + padding + b'\x00' + message
    return pow(int.from_bytes(em, 'big'), e, n).to_bytes(k, 'big')


class Conn:
    def __init__(self, host, port, timeout=15.0):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self.buf = bytearray()
        self.threshold = -1
        self.enc = None
        self.dec = None

    def send(self, pid, body=b''):
        payload = varint(pid) + body
        if self.threshold >= 0:
            if len(payload) >= self.threshold:
                packed = zlib.compress(payload)
                payload = varint(len(payload)) + packed
            else:
                payload = varint(0) + payload
        data = varint(len(payload)) + payload
        self.sock.sendall(self.enc.encrypt(data) if self.enc else data)

    def _frame(self):
        # Length prefix, then the frame, if it has all arrived.
        value = 0
        for i in range(5):
            if i >= len(self.buf):
                return None
            b = self.buf[i]
            value |= (b & 0x7F) << (7 * i)
            if not b & 0x80:
                if len(self.buf) < i + 1 + value:
                    return None
                frame = bytes(self.buf[i + 1:i + 1 + value])
                del self.buf[:i + 1 + value]
                return frame
        raise Fail('a frame length longer than five bytes')

    def recv(self):
        """(id, Reader). A socket timeout propagates; a closed connection is a failure."""
        while True:
            frame = self._frame()
            if frame is not None:
                break
            chunk = self.sock.recv(262144)
            check(len(chunk) > 0, 'the server closed the connection')
            self.buf += self.dec.decrypt(chunk) if self.dec else chunk
        r = Reader(frame)
        if self.threshold >= 0:
            size = r.varint()
            if size != 0:
                check(size >= self.threshold, 'a packet of %d bytes compressed under the threshold %d' % (size, self.threshold))
                data = zlib.decompress(r.take(r.left()))
                check(len(data) == size, 'a compressed packet of the wrong length')
                r = Reader(data)
        pid = r.varint()
        return pid, r

    def close(self):
        self.sock.close()


def handshake(host, port, next_state):
    return varint(PROTOCOL) + string(host) + struct.pack('>H', port) + varint(next_state)


def status_ping(host, port):
    c = Conn(host, port)
    c.send(0, handshake(host, port, 1))
    c.send(0)
    pid, r = c.recv()
    check(pid == 0, 'status answered with packet %d' % pid)
    status = json.loads(r.string())
    token = int(time.time() * 1000)
    c.send(1, struct.pack('>q', token))
    pid, r = c.recv()
    check(pid == 1 and r.i64() == token, 'the pong did not echo the ping')
    c.close()
    return status


def read_container(r, entries, max_indirect, limit, what, out=None):
    """One paletted container, 774's: no length prefix on the data array. Returns (bits, palette, kind, distinct ids).
    With `out`, a list, the decoded entries are appended to it."""
    bits = r.u8()
    if bits == 0:
        value = r.varint()
        check(0 <= value < limit, '%s single value %d out of range (limit %d)' % (what, value, limit))
        if out is not None:
            out.extend([value] * entries)
        return bits, [value], 'single', {value}
    check(bits <= 31, '%s bits per entry %d' % (what, bits))
    per_long = 64 // bits
    longs = (entries + per_long - 1) // per_long
    if bits <= max_indirect:
        size = r.varint()
        check(0 < size <= (1 << bits), '%s palette size %d at %d bits' % (what, size, bits))
        palette = [r.varint() for _ in range(size)]
        for v in palette:
            check(0 <= v < limit, '%s palette id %d out of range (limit %d)' % (what, v, limit))
        mask = (1 << bits) - 1
        produced = 0
        for _ in range(longs):
            word = struct.unpack('>Q', r.take(8))[0]
            for k in range(per_long):
                if produced >= entries:
                    break
                index = (word >> (k * bits)) & mask
                check(index < size, '%s index %d past its palette of %d' % (what, index, size))
                if out is not None:
                    out.append(palette[index])
                produced += 1
        return bits, palette, 'indirect', set(palette)
    # Direct: the entries are registry ids.
    mask = (1 << bits) - 1
    seen = set()
    produced = 0
    for _ in range(longs):
        word = struct.unpack('>Q', r.take(8))[0]
        for k in range(per_long):
            if produced >= entries:
                break
            value = (word >> (k * bits)) & mask
            check(value < limit, '%s direct id %d out of range (limit %d)' % (what, value, limit))
            seen.add(value)
            if out is not None:
                out.append(value)
            produced += 1
    return bits, [], 'direct', seen


def bitcount_mask(r):
    n = r.varint()
    check(0 <= n <= 64, 'a light mask of %d longs' % n)
    words = [r.i64() & 0xFFFFFFFFFFFFFFFF for _ in range(n)]
    return words, sum(bin(w).count('1') for w in words)


def parse_chunk(r, sections, biome_limit, verbose, blocks_out=None):
    x = r.i32()
    z = r.i32()
    maps = r.varint()
    check(0 <= maps <= 64, 'heightmap count %d' % maps)
    for _ in range(maps):
        kind = r.varint()
        longs = r.varint()
        check(0 <= kind and 0 <= longs <= 4096, 'heightmap %d of %d longs' % (kind, longs))
        r.take(longs * 8)
    size = r.varint()
    check(0 <= size <= r.left(), 'chunk section array of %d with %d left' % (size, r.left()))
    s = Reader(r.take(size))
    non_air = 0
    all_states = set()
    kinds = {}
    for i in range(sections):
        count = s.i16()
        check(0 <= count <= 4096, 'section %d claims %d non-air blocks' % (i, count))
        non_air += count
        section_blocks = [] if blocks_out is not None else None
        _, _, kind, ids = read_container(s, 4096, 8, BLOCK_STATES_1_21_11, 'chunk %d,%d section %d blocks' % (x, z, i),
                                         section_blocks)
        if blocks_out is not None:
            blocks_out.append(section_blocks)
        kinds[kind] = kinds.get(kind, 0) + 1
        all_states |= ids
        read_container(s, 64, 3, biome_limit, 'chunk %d,%d section %d biomes' % (x, z, i))
    check(s.left() == 0, 'chunk %d,%d: %d bytes left over after %d sections' % (x, z, s.left(), sections))
    count = r.varint()
    check(0 <= count <= 4096, 'block entity count %d' % count)
    for _ in range(count):
        r.u8()
        r.i16()
        r.varint()
        skip_network_nbt(r)
    sky_words, sky_bits = bitcount_mask(r)
    # The topmost real section (light bit `sections`) of an overworld chunk is open sky: it must not read as dark.
    # The nether has a roof and the end's chunks may be dark, hence only for an overworld's height.
    check(sections != DEFAULT_SECTIONS or not sky_words or (sky_words[0] >> sections) & 1,
          'chunk %d,%d: top section has no sky light' % (x, z))
    block_words, block_bits = bitcount_mask(r)
    empty_sky, _ = bitcount_mask(r)
    empty_block, _ = bitcount_mask(r)
    for a, b, what in ((sky_words, empty_sky, 'sky'), (block_words, empty_block, 'block')):
        for u, v in zip(a, b):
            check((u & v) == 0, '%s light section both present and empty' % what)
    for bits, what in ((sky_bits, 'sky'), (block_bits, 'block')):
        n = r.varint()
        check(n == bits, '%s light: %d arrays for %d mask bits' % (what, n, bits))
        for _ in range(n):
            size = r.varint()
            check(size == 2048, '%s light array of %d bytes' % (what, size))
            r.take(size)
    check(r.left() == 0, 'chunk %d,%d: %d bytes left over at the end of the packet' % (x, z, r.left()))
    if verbose:
        print('  chunk %d,%d: %d sections, %d non-air blocks, %d distinct state ids (max %d), containers %s, '
              '%d block entities, sky light arrays %d, block light arrays %d'
              % (x, z, sections, non_air, len(all_states), max(all_states), kinds, count, sky_bits, block_bits))
        print('  state ids: %s' % sorted(all_states))
    return x, z


def read_spawn_position(r):
    r.string()
    r.i64()
    r.f32()
    r.f32()


def read_border(r):
    for _ in range(4):
        r.f64()
    r.varint()  # lerp time, a VarLong; small here
    r.varint()
    r.varint()
    r.varint()


def read_info_update(r):
    flags = r.u8()
    for _ in range(r.varint()):
        r.take(16)
        if flags & 0x01:
            r.string()
            for _ in range(r.varint()):
                r.string()
                r.string()
                if r.boolean():
                    r.string()
        if flags & 0x02:
            check(not r.boolean(), 'chat session unexpected here')
        if flags & 0x04:
            r.varint()
        if flags & 0x08:
            r.boolean()
        if flags & 0x10:
            r.varint()
        if flags & 0x20:
            check(not r.boolean(), 'display name unexpected here')
        if flags & 0x40:
            r.varint()
        if flags & 0x80:
            r.boolean()


def read_slot(r):
    """One item stack as 774 sends it: count, then id and component counts. Components are not expected yet.
    Returns (count, id)."""
    count = r.varint()
    if count <= 0:
        return 0, 0
    item = r.varint()
    added, removed = r.varint(), r.varint()
    check(added == 0 and removed == 0, 'a stack with %d+%d components: this bot does not read them' % (added, removed))
    return count, item


def write_slot(count, item):
    return varint(0) if count <= 0 else varint(count) + varint(item) + varint(0) + varint(0)


def block_pos(x, y, z):
    value = ((x & 0x3FFFFFF) << 38) | ((z & 0x3FFFFFF) << 12) | (y & 0xFFF)
    return struct.pack('>Q', value)


def read_block_pos(r):
    v = struct.unpack('>Q', r.take(8))[0]
    x, z, y = v >> 38, (v >> 12) & 0x3FFFFFF, v & 0xFFF
    if x >= 1 << 25:
        x -= 1 << 26
    if z >= 1 << 25:
        z -= 1 << 26
    if y >= 1 << 11:
        y -= 1 << 12
    return x, y, z


def offline_uuid(name):
    """net/mod.rs's offline_uuid: the first sixteen bytes of the name's SHA-256."""
    return hashlib.sha256(name.encode('utf-8')).digest()[:16]


COMMAND_TREE = {}     # What the last commands packet said: 'nodes' and 'root'.


def read_argument_properties(r, parser):
    """The properties of a parser, by its id in 1.21.11's minecraft:command_argument_type."""
    if parser in (1, 2, 3, 4):     # float, double, integer, long: min and max as the flags say
        flags = r.u8()
        size = 4 if parser in (1, 3) else 8
        if flags & 1:
            r.take(size)
        if flags & 2:
            r.take(size)
    elif parser == 5:              # string
        r.varint()
    elif parser in (6, 31):        # entity, score_holder
        r.u8()
    elif parser == 43:             # time
        r.take(4)
    elif parser in (44, 45, 46, 47):  # resource_or_tag, resource_or_tag_key, resource, resource_key
        r.string()


def read_commands(r):
    nodes = []
    for _ in range(r.varint()):
        flags = r.u8()
        kind = flags & 3
        check(kind != 3, 'node type 3 does not exist')
        children = [r.varint() for _ in range(r.varint())]
        redirect = r.varint() if flags & 8 else None
        name = r.string() if kind != 0 else None
        parser = None
        if kind == 2:
            parser = r.varint()
            read_argument_properties(r, parser)
        suggests = r.string() if flags & 16 else None
        nodes.append(dict(kind=kind, flags=flags, children=children, redirect=redirect, name=name, parser=parser,
                          suggests=suggests))
    root = r.varint()
    check(0 <= root < len(nodes) and nodes[root]['kind'] == 0, 'root index %d is not a root node' % root)
    for at, node in enumerate(nodes):
        for child in node['children'] + ([node['redirect']] if node['redirect'] is not None else []):
            check(0 <= child < len(nodes), 'node %d points at %d of %d' % (at, child, len(nodes)))
    COMMAND_TREE['nodes'] = nodes
    COMMAND_TREE['root'] = root


META_LOG = []   # (entity id, index, kind, value) of every item-stack metadata --world has seen


def read_metadata(r):
    entity = r.varint()
    while True:
        index = r.u8()
        if index == 0xFF:
            return
        kind = r.varint()
        # 774's serializer ids (generated/meta_data_type.aowl, v1_21_11). Holder-backed variants are one varint each.
        check(kind in (0, 1, 2, 3, 6, 7, 8, 10, 11, 12, 14, 15, 18, 19, 20, 21, 22, 23, 25, 26, 27, 30),
              'metadata type %d: this bot does not read it' % kind)
        if kind == 0 or kind == 8:
            r.u8()
        elif kind == 3:
            r.f32()
        elif kind == 6:
            if r.boolean():
                skip_network_nbt(r)
        elif kind == 7:
            META_LOG.append((entity, index, kind, read_slot(r)))
        elif kind == 18:
            r.varint(), r.varint(), r.varint()   # villager data: type, profession, level
        elif kind == 10:
            r.take(8)
        elif kind == 11:
            if r.boolean():
                r.take(8)
        else:
            r.varint()   # varint, varlong, direction, block states, optional int, pose and the variant holders


# 774's layouts for the rest of the join, as aoughwl.mcnet reads them; each must be consumed exactly.
EXACT_PLAY = {
    0x7D: lambda r: (r.f32(), r.boolean()),                        # ticking_state
    0x7E: lambda r: r.varint(),                                    # ticking_step
    0x22: lambda r: (r.i32(), r.u8()),                             # entity_event
    0x0A: lambda r: (r.u8(), r.boolean()),                         # change_difficulty
    0x10: read_commands,                                           # commands
    0x44: read_info_update,                                        # player_info_update
    0x61: read_metadata,                                           # set_entity_data
    0x3E: lambda r: (r.u8(), r.f32(), r.f32()),                    # player_abilities
    0x67: lambda r: r.u8(),                                        # set_held_slot
    PLAY_GAME_EVENT: lambda r: (r.u8(), r.f32()),                  # game_event
    0x2A: read_border,                                             # initialize_border
    PLAY_TIME: lambda r: (r.i64(), r.i64(), r.boolean()),          # set_time
    PLAY_SPAWN_POS: read_spawn_position,                           # set_default_spawn_position
    PLAY_CENTER: lambda r: (r.varint(), r.varint()),               # set_chunk_cache_center
    PLAY_SYSTEM_CHAT: lambda r: (skip_network_nbt(r), r.boolean()),  # system_chat
    PLAY_BATCH_START: lambda r: None,                              # chunk_batch_start
    PLAY_BLOCK_DESTRUCTION: lambda r: (r.varint(), r.take(8), r.u8()),  # block_destruction
    PLAY_ANIMATE: lambda r: (r.varint(), r.u8()),                  # animate
    PLAY_CONTAINER_DATA: lambda r: (r.varint(), r.i16(), r.i16()),  # container_set_data
    PLAY_EXPERIENCE: lambda r: (r.f32(), r.varint(), r.varint()),  # set_experience
    PLAY_FORGET_CHUNK: lambda r: r.take(8),                        # forget_level_chunk
}


def client_information():
    # locale, view distance, chat mode, chat colors, skin parts, main hand, text filtering, server listing,
    # particle status
    return string('en_us') + bytes([8]) + varint(0) + bytes([1]) + bytes([0x7F]) + varint(1) + bytes([0, 1]) + varint(0)


class World:
    """What a --play run has been told."""

    def __init__(self):
        self.chunks = {}        # (x, z) -> [section -> [4096 state ids]], the section at index 0 being min_y's
        self.min_y = -64
        self.overrides = {}     # (x, y, z) -> state id, from block updates after the chunk
        self.pos = None
        self.rot = None         # (yaw, pitch) of the last teleport
        self.window0 = None     # 46 (count, item)
        self.state_id = 0
        self.cursor = (0, 0)
        self.acked = -1
        self.health = None
        self.chat = []
        self.events = []        # scoreboard, team, bossbar, border and ticking packets, as tuples
        self.pongs = []
        self.suggestions = []
        self.mode = None
        self.flying_allowed = None
        self.time = None

    def block(self, x, y, z):
        at = (x, y, z)
        if at in self.overrides:
            return self.overrides[at]
        column = self.chunks.get((x >> 4, z >> 4))
        if column is None:
            return None
        section = (y - self.min_y) >> 4
        return column[section][((y - self.min_y) & 15) << 8 | (z & 15) << 4 | (x & 15)]


def text_of(nbt_bytes):
    """Every string in a network NBT text component, joined: enough to look for a chat message in."""
    found = []
    r = Reader(nbt_bytes)

    def walk(kind):
        if kind == 1:
            r.take(1)
        elif kind == 2:
            r.take(2)
        elif kind in (3, 5):
            r.take(4)
        elif kind in (4, 6):
            r.take(8)
        elif kind == 7:
            r.take(r.i32())
        elif kind == 8:
            n = struct.unpack('>H', r.take(2))[0]
            found.append(r.take(n).decode('utf-8', 'replace'))
        elif kind == 9:
            inner = r.u8()
            for _ in range(r.i32()):
                walk(inner)
        elif kind == 10:
            while True:
                t = r.u8()
                if t == 0:
                    return
                n = struct.unpack('>H', r.take(2))[0]
                r.take(n)
                walk(t)
        elif kind == 11:
            r.take(r.i32() * 4)
        elif kind == 12:
            r.take(r.i32() * 8)
    walk(r.u8())
    return ' '.join(found), r.at


PLAY_BOSS_EVENT, PLAY_BORDER_CENTER, PLAY_BORDER_LERP, PLAY_BORDER_SIZE = 9, 86, 87, 88
PLAY_SET_DISPLAY_OBJECTIVE, PLAY_SET_OBJECTIVE, PLAY_SET_PLAYER_TEAM, PLAY_SET_SCORE, PLAY_TICKING_STATE = 96, 104, 107, 108, 125
SCOREBOARD_PACKETS = (PLAY_BOSS_EVENT, PLAY_BORDER_CENTER, PLAY_BORDER_LERP, PLAY_BORDER_SIZE, PLAY_SET_DISPLAY_OBJECTIVE,
                      PLAY_SET_OBJECTIVE, PLAY_SET_PLAYER_TEAM, PLAY_SET_SCORE)


def record_scoreboard_packet(w, pid, r):
    """Reads what the scoreboard, team, bossbar and border packets carry first and keeps it in w.events, as tuples."""
    if pid == PLAY_SET_OBJECTIVE:
        name = r.string()
        w.events.append(('objective', name, r.u8()))
    elif pid == PLAY_SET_DISPLAY_OBJECTIVE:
        slot = r.varint()
        w.events.append(('display', slot, r.string()))
    elif pid == PLAY_SET_SCORE:
        entity, objective = r.string(), r.string()
        w.events.append(('score', entity, objective, r.varint()))
    elif pid == PLAY_SET_PLAYER_TEAM:
        name = r.string()
        method = r.u8()
        members = []
        if method in (0, 3, 4):
            if method == 0:
                # display name (NBT), flags, visibility, collision, color, prefix, suffix
                skip_network_nbt(r)
                flags = r.u8()
                vis, col, color = r.string(), r.string(), r.varint()
                skip_network_nbt(r)
                skip_network_nbt(r)
                members = [r.string() for _ in range(r.varint())]
                w.events.append(('team', name, method, flags, vis, col, color, members))
                return
            members = [r.string() for _ in range(r.varint())]
        elif method == 2:
            skip_network_nbt(r)
            flags = r.u8()
            vis, col, color = r.string(), r.string(), r.varint()
            skip_network_nbt(r)
            skip_network_nbt(r)
            w.events.append(('team', name, method, flags, vis, col, color, members))
            return
        w.events.append(('team', name, method, members))
    elif pid == PLAY_BOSS_EVENT:
        uid = r.take(16)
        action = r.varint()
        info = None
        if action == 2:
            info = r.f32()
        w.events.append(('boss', uid.hex(), action, info))
    elif pid == PLAY_BORDER_CENTER:
        w.events.append(('border_center', r.f64(), r.f64()))
    elif pid == PLAY_BORDER_SIZE:
        w.events.append(('border_size', r.f64()))
    elif pid == PLAY_BORDER_LERP:
        old, new = r.f64(), r.f64()
        w.events.append(('border_lerp', old, new, r.varint()))
    r.take(r.left())


def handle_play_extra(w, pid, r):
    """The packets --play reads. True when it consumed the packet."""
    if pid == PLAY_BLOCK_UPDATE:
        x, y, z = read_block_pos(r)
        w.overrides[(x, y, z)] = r.varint()
    elif pid == PLAY_SECTION_UPDATE:
        section = struct.unpack('>Q', r.take(8))[0]
        sx, sz, sy = section >> 42, (section >> 20) & 0x3FFFFF, section & 0xFFFFF
        if sx >= 1 << 21:
            sx -= 1 << 22
        if sz >= 1 << 21:
            sz -= 1 << 22
        if sy >= 1 << 19:
            sy -= 1 << 20
        for _ in range(r.varint()):
            v = 0
            for shift in range(0, 70, 7):
                b = r.u8()
                v |= (b & 0x7F) << shift
                if not b & 0x80:
                    break
            rel = v & 0xFFF
            w.overrides[(sx * 16 + (rel >> 8), sy * 16 + (rel & 15), sz * 16 + ((rel >> 4) & 15))] = v >> 12
    elif pid == PLAY_BLOCK_ACK:
        w.acked = max(w.acked, r.varint())
    elif pid == PLAY_CONTAINER_CONTENT:
        window = r.varint()
        w.state_id = r.varint()
        slots = [read_slot(r) for _ in range(r.varint())]
        w.cursor = read_slot(r)
        if window == 0:
            check(len(slots) == 46, 'window 0 has %d slots, not 46' % len(slots))
            w.window0 = slots
    elif pid == PLAY_CONTAINER_SLOT:
        window = struct.unpack('>b', r.take(1))[0]
        w.state_id = r.varint()
        slot = r.i16()
        stack = read_slot(r)
        if window == 0 and w.window0 is not None and 0 <= slot < 46:
            w.window0[slot] = stack
    elif pid == PLAY_CURSOR:
        w.cursor = read_slot(r)
    elif pid == PLAY_PLAYER_INV:
        slot = r.varint()
        stack = read_slot(r)
        # A main inventory index; in window 0 the hotbar comes after the 27 others, at 36.
        if w.window0 is not None and 0 <= slot < 9:
            w.window0[36 + slot] = stack
        elif w.window0 is not None and 9 <= slot < 36:
            w.window0[slot] = stack
    elif pid == PLAY_HEALTH:
        w.health = (r.f32(), r.varint(), r.f32())
    elif pid == PLAY_PONG:
        w.pongs.append(r.i64())
    elif pid == PLAY_EQUIPMENT:
        r.varint()
        while True:
            slot = r.u8()
            read_slot(r)
            if not slot & 0x80:
                break
    elif pid in SCOREBOARD_PACKETS:
        record_scoreboard_packet(w, pid, r)
    elif pid == PLAY_SUGGESTIONS:
        ident = r.varint()
        start, length = r.varint(), r.varint()
        matches = []
        for _ in range(r.varint()):
            matches.append(r.string())
            if r.boolean():
                skip_network_nbt(r)
        w.suggestions.append((ident, len(matches), start, length, matches))
    else:
        return False
    return True


class Stages:
    NAMES = ['status', 'login_start', 'compression', 'login_success', 'known_packs', 'registry_data', 'tags',
             'finish_configuration', 'play_login', 'teleport', 'chunk_batch', 'chunk_parsed', 'keep_alive',
             'stayed_up', 'clean_disconnect', 'server_alive_after']
    PLAY_NAMES = ['inventory_window', 'health', 'walked', 'pong', 'creative', 'creative_slot', 'held_slot', 'swing', 'input',
                  'block_broken', 'block_ack', 'block_placed', 'click_window', 'close_window', 'chat_heard', 'suggestion',
                  'unknown_command']
    VERIFY_NAMES = ['placed_block_persisted', 'position_persisted', 'inventory_persisted', 'gamemode_persisted']
    FAR_NAMES = ['far_chunk_generated', 'keep_alive_during_generation']
    COMMAND_NAMES = ['tree_parsed', 'tree_children', 'unknown_error', 'bad_block_error', 'bad_mode_error', 'kill_dead',
                      'kill_respawned', 'setblock_update', 'fill_update', 'give_slot', 'gamemode_creative',
                      'gamemode_survival', 'time_set', 'time_query', 'tp_moved', 'execute_run', 'suggest_root', 'suggest_arg']
    COMMANDS2_NAMES = ['tree2_children', 'clone_copied', 'clone_moved', 'place_template', 'place_structure', 'item_slot',
                       'item_mainhand', 'spreadplayers_teleport', 'rotate_absolute', 'rotate_facing', 'fillbiome_chunk',
                       'loot_given', 'ride_not_riding', 'spectate_self', 'spectate_stopped']
    COMMANDS3_NAMES = ['tree3_children', 'help_page', 'help_command', 'pumpkin_version', 'attribute_get', 'attribute_base_set',
                       'advancement_grant', 'advancement_revoke', 'advancement_revoke_again', 'dialog_show', 'dialog_clear']
    SCOREBOARD_NAMES = ['objective_added', 'sidebar_shown', 'score_enabled', 'trigger_score', 'team_created', 'team_joined',
                        'team_updated', 'bossbar_added', 'bossbar_health', 'bossbar_name', 'border_size', 'border_center',
                        'border_lerp', 'tick_rate', 'tick_frozen', 'tick_query', 'data_get_player']
    COMMAND_VERIFY_NAMES = ['setblock_persisted', 'fill_persisted', 'give_persisted', 'tp_persisted', 'alive_on_return']
    BLOCKS_NAMES = ['door_placed', 'door_opened', 'door_closed', 'lamp_line_placed', 'lamp_lit', 'lamp_dark', 'sand_fell',
                    'water_flowed']
    BLOCKS_VERIFY_NAMES = ['blocks_persisted']
    PLAYA_NAMES = ['pa_shift_click', 'pa_drag_split', 'pa_tab_complete', 'pa_chat_sent']
    PLAYA_LISTEN_NAMES = ['pa_chat_heard']
    PLUGIN_NAMES = ['plugin_welcome', 'plugin_chat_passes', 'plugin_chat_cancelled']
    PLUGMGR_NAMES = ['plugmgr_tree', 'plugmgr_chat_before', 'plugmgr_list', 'plugmgr_load_error', 'plugmgr_loaded', 'plugmgr_already_loaded',
                     'plugmgr_chat_cancelled', 'plugmgr_unloaded', 'plugmgr_chat_after_unload', 'plugmgr_reloaded']
    C2_NAMES = ['sign_placed', 'sign_text_set', 'bed_placed', 'bed_slept', 'piston_pushed']
    C2_VERIFY_NAMES = ['sign_persisted', 'bed_persisted', 'piston_persisted']
    CONTAINERS_NAMES = ['container_placed', 'container_opened', 'container_filled', 'window_opens', 'item_replace_block']
    CONTAINERS_VERIFY_NAMES = ['containers_persisted']
    WORLD_NAMES = ['world_survival', 'dirt_placed', 'dirt_broken', 'drop_spawned', 'drop_item', 'portal_built',
                   'portal_entered', 'nether_respawn', 'nether_position', 'nether_portal_found', 'night_set',
                   'mobs_spawned']
    PLAYER_NAMES = ['cow_summoned', 'mob_hit', 'damage_dealt', 'hunger_drained', 'fill_stairs_states', 'fill_portal_state',
                    'fill_bad_property', 'player_died', 'death_drops', 'player_respawned', 'respawn_point_used', 'cow_wandered', 'pig_followed']
    PLAYER_VERIFY_NAMES = ['entity_after_join']
    PARTSB_NAMES = {'pearl': ['pearl_cooldown_sent', 'pearl_blocked', 'pearl_again'],
                    'bed': ['bed_slept', 'night_skipped', 'bed_woken_by_skip', 'bed_woken_by_command'],
                    'villager': ['villager_summoned', 'villager_window_opened', 'villager_offers_sent', 'villager_result_shown',
                                 'villager_traded'],
                    'dragon': ['dragon_spawned', 'dragon_damaged'], 'cow': [], 'pig': ['pig_followed_carrot'], 'gaps': ['gaps_done']}
    WATCH_NAMES = ['other_appeared', 'other_moved', 'other_swung', 'other_block_change', 'other_chat', 'other_left']

    def __init__(self, extra=()):
        self.reached = []
        self.names = self.NAMES + list(extra)

    def hit(self, name):
        assert name in self.names
        if name not in self.reached:
            self.reached.append(name)
            print('STAGE %s' % name, flush=True)

    def missing(self):
        return [n for n in self.names if n not in self.reached]


def pump(c, st, w, biomes, ctx, until, what, seconds=8.0):
    """Reads and answers packets until `until()` holds, keeping the client side of the protocol going."""
    deadline = time.time() + seconds
    while True:
        if until():
            return
        if time.time() > deadline:
            raise Fail('timed out waiting for %s' % what)
        try:
            pid, r = c.recv()
        except socket.timeout:
            continue
        one_packet(c, st, w, biomes, ctx, pid, r)


def one_packet(c, st, w, biomes, ctx, pid, r):
    counts = ctx['counts']
    tap = ctx.get('tap')
    if tap:
        tap(pid, r.data[r.at:])
    counts[pid] = counts.get(pid, 0) + 1
    if counts[pid] <= 3 or pid in (PLAY_KEEP_ALIVE, PLAY_DISCONNECT):
        print('play   packet 0x%02x (%d bytes)' % (pid, r.left()), flush=True)
    if pid in EXACT_PLAY:
        if pid == PLAY_TICKING_STATE:
            w.events.append(('ticking', struct.unpack('>f', r.data[r.at:r.at + 4])[0], r.data[r.at + 4] != 0))
        if pid == PLAY_TIME:
            w.time = struct.unpack('>qq', r.data[r.at:r.at + 16])
        if pid == PLAY_SYSTEM_CHAT:
            start = r.at
            said, used = text_of(r.data[start:])
            w.chat.append(said)
        if pid == PLAY_GAME_EVENT:
            event, value = r.u8(), r.f32()
            check(r.left() == 0, 'game_event: %d bytes left over' % r.left())
            if event == 3:
                w.mode = int(value)
            return
        if pid == 0x3E:
            flags, _, _ = r.u8(), r.f32(), r.f32()
            w.flying_allowed = bool(flags & 4)
            check(r.left() == 0, 'player_abilities: %d bytes left over' % r.left())
            return
        EXACT_PLAY[pid](r)
        check(r.left() == 0, 'packet 0x%02x: %d bytes left over' % (pid, r.left()))
    elif pid == PLAY_LOGIN:
        entity = r.i32()
        hardcore = r.boolean()
        worlds = [r.string() for _ in range(r.varint())]
        maxp, view, sim = r.varint(), r.varint(), r.varint()
        r.boolean(), r.boolean(), r.boolean()
        dim = r.varint()
        world = r.string()
        seed = r.i64()
        mode, prev = r.u8(), struct.unpack('>b', r.take(1))[0]
        r.boolean(), r.boolean()
        if r.boolean():
            r.string()
            r.i64()
        portal, sea = r.varint(), r.varint()
        secure = r.boolean()
        check(r.left() == 0, 'CLogin: %d bytes left over' % r.left())
        check(0 <= dim < len(ctx['dims']), 'CLogin dimension %d of %d' % (dim, len(ctx['dims'])))
        print('  CLogin entity=%d hardcore=%s worlds=%s max=%d view=%d sim=%d dim=%d(%s) world=%s seed=%d mode=%d '
              'prev=%d portal=%d sea=%d secure=%s' % (entity, hardcore, worlds, maxp, view, sim, dim, ctx['dims'][dim],
                                                      world, seed, mode, prev, portal, sea, secure))
        ctx['entity'] = entity
        w.mode = mode
        ctx['world'] = world
        if world != 'minecraft:overworld':
            ctx['sections'], w.min_y = 16, 0
        ctx['secure'] = secure
        st.hit('play_login')
    elif pid == PLAY_POSITION:
        tid = r.varint()
        x, y, z = r.f64(), r.f64(), r.f64()
        r.take(24)
        w.rot = (r.f32(), r.f32())
        flags = r.i32()
        check(r.left() == 0, 'player position: %d bytes left over' % r.left())
        print('  teleport id=%d to %.2f %.2f %.2f flags=%d' % (tid, x, y, z, flags))
        w.pos = (x, y, z)
        c.send(SB_TELEPORT, varint(tid))
        st.hit('teleport')
    elif pid == PLAY_CHUNK:
        ctx['chunks'] += 1
        column = []
        x, z = parse_chunk(r, ctx['sections'], biomes, not ctx['chunk_parsed'], column)
        w.chunks[(x, z)] = column
        for key in [k for k in w.overrides if (k[0] >> 4, k[2] >> 4) == (x, z)]:
            del w.overrides[key]
        ctx['chunk_parsed'] = True
        st.hit('chunk_parsed')
    elif pid == PLAY_BATCH_END:
        r.varint()
        c.send(SB_BATCH, struct.pack('>f', 64.0))
        st.hit('chunk_batch')
        if not ctx['loaded_sent'] and ctx['chunk_parsed']:
            c.send(SB_LOADED)
            ctx['loaded_sent'] = True
    elif pid == PLAY_KEEP_ALIVE:
        token = r.i64()
        c.send(SB_KEEP_ALIVE, struct.pack('>q', token))
        ctx['keep_alives'] += 1
        print('  keep-alive %d answered at %.1fs' % (token, time.time() - ctx['start']), flush=True)
        st.hit('keep_alive')
    elif pid == PLAY_DISCONNECT:
        raise Fail('kicked %.1fs into play: %r' % (time.time() - ctx['start'], r.take(r.left())))
    elif handle_play_extra(w, pid, r):
        check(r.left() == 0, 'packet 0x%02x: %d bytes left over' % (pid, r.left()))


def move_flags(on_ground):
    return bytes([1 if on_ground else 0])


def play_session(c, st, w, biomes, ctx, args):
    """--play: the scripted game. See the module docstring."""
    def wait(cond, what, seconds=8.0):
        pump(c, st, w, biomes, ctx, cond, what, seconds)

    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    wait(lambda: w.window0 is not None, 'the inventory in window 0')
    print('  window 0: %d slots, state id %d' % (len(w.window0), w.state_id))
    st.hit('inventory_window')
    wait(lambda: w.health is not None, 'a health packet')
    print('  health %.1f food %d saturation %.1f' % w.health)
    check(w.health[0] > 0, 'dead on arrival')
    st.hit('health')

    # The ground under the player, from the chunk: walk on it, within the column it stands on.
    x, y, z = w.pos
    print('  standing at %.2f %.2f %.2f' % (x, y, z))
    wait(lambda: w.block(int(x // 1), int(y // 1) - 1, int(z // 1)) is not None, 'the chunk under the player', 20.0)
    for i in range(1, 6):
        x += 0.2
        z += 0.1
        c.send(SB_MOVE_POS, struct.pack('>ddd', x, y, z) + move_flags(True))
        time.sleep(0.05)
    c.send(SB_MOVE_POS_ROT, struct.pack('>dddff', x, y, z, 90.0, 10.0) + move_flags(True))
    w.pos = (x, y, z)
    ctx['walked_to'] = (x, y, z)
    st.hit('walked')

    token = 0x1234567890
    c.send(SB_PING, struct.pack('>q', token))
    wait(lambda: token in w.pongs, 'a pong')
    st.hit('pong')

    if args.op:
        c.send(SB_CHANGE_GAME_MODE, varint(1))
        wait(lambda: w.mode == 1 and w.flying_allowed, 'creative mode')
        st.hit('creative')
    else:
        raise Fail('--play needs --op: a survival bot has nothing to place')

    # Hotbar slot 2 of the window (index 1 of the hotbar), 64 stone from the creative inventory.
    c.send(SB_CREATIVE, struct.pack('>h', 37) + write_slot(64, STONE_ITEM))
    c.send(SB_CARRIED, struct.pack('>h', 1))
    c.send(SB_PING, struct.pack('>q', token + 1))
    wait(lambda: token + 1 in w.pongs, 'a pong after the creative slot')
    w.window0[37] = (64, STONE_ITEM)
    st.hit('creative_slot')
    st.hit('held_slot')

    c.send(SB_SWING, varint(0))
    st.hit('swing')
    c.send(SB_INPUT, bytes([32]))
    c.send(SB_INPUT, bytes([0]))
    c.send(SB_COMMAND, varint(ctx['entity']) + varint(1) + varint(0))  # start sprinting: 1 is 774's first
    c.send(SB_COMMAND, varint(ctx['entity']) + varint(2) + varint(0))
    st.hit('input')

    # The block one over, in front of the feet, at foot height minus one: a solid one if the world has it.
    bx, by, bz = int(x // 1) + 1, int(y // 1) - 1, int(z // 1)
    wait(lambda: w.block(bx, by, bz) is not None, 'the block to break', 20.0)
    before = w.block(bx, by, bz)
    print('  breaking state %d at %d %d %d' % (before, bx, by, bz))
    check(before != 0, 'the block to break is already air')
    c.send(SB_ACTION, varint(0) + block_pos(bx, by, bz) + bytes([1]) + varint(11))
    wait(lambda: w.block(bx, by, bz) == 0, 'the broken block to read air')
    st.hit('block_broken')
    wait(lambda: w.acked >= 11, 'block_changed_ack for the dig')
    print('  block_changed_ack %d' % w.acked)
    st.hit('block_ack')

    # Place stone back, against the block below the hole, on its top face.
    c.send(SB_USE_ON, varint(0) + block_pos(bx, by - 1, bz) + varint(1) + struct.pack('>fff', 0.5, 1.0, 0.5) +
           bytes([0, 0]) + varint(12))
    wait(lambda: w.block(bx, by, bz) == STONE_STATE, 'the placed stone')
    wait(lambda: w.acked >= 12, 'block_changed_ack for the placing')
    st.hit('block_placed')
    ctx['placed_at'] = (bx, by, bz)

    # Pick the stack up with the cursor and put it back. Both clicks carry a stale state id, which makes the server answer
    # with the whole window: that is what shows it did what was asked, since a click it agrees with gets no answer.
    def click(slot, cursor_after):
        changed = varint(1) + struct.pack('>h', slot) + (bytes([0]) if cursor_after[0] else
                                                         bytes([1]) + varint(STONE_ITEM) + varint(64) + varint(0) + varint(0))
        carried = (bytes([1]) + varint(STONE_ITEM) + varint(64) + varint(0) + varint(0)) if cursor_after[0] else bytes([0])
        w.window0 = None
        c.send(SB_CONTAINER_CLICK, varint(0) + varint(w.state_id + 1000) + struct.pack('>h', slot) + bytes([0]) + varint(0) +
               changed + carried)
        wait(lambda: w.window0 is not None, 'the window after a click')

    click(37, (64, STONE_ITEM))
    print('  after picking up: cursor %s, slot 37 %s' % (w.cursor, w.window0[37]))
    check(w.cursor == (64, STONE_ITEM) and w.window0[37] == (0, 0), 'picking up left %s, %s' % (w.cursor, w.window0[37]))
    click(37, (0, 0))
    print('  after putting back: cursor %s, slot 37 %s' % (w.cursor, w.window0[37]))
    check(w.cursor == (0, 0) and w.window0[37] == (64, STONE_ITEM), 'putting back left %s, %s' % (w.cursor, w.window0[37]))
    st.hit('click_window')
    c.send(SB_CONTAINER_CLOSE, varint(0))
    st.hit('close_window')

    # Chat, the shape aoughwl.mcnet sends: an unsigned message with an empty window and a zero checksum.
    check(not ctx.get('secure', True), 'the server said enforces_secure_chat: aoughwl.mcnet would refuse to chat')
    message = 'hello from the bot %d' % int(time.time())
    c.send(SB_CHAT, string(message) + struct.pack('>qq', int(time.time() * 1000), 42) + bytes([0]) + varint(0) + bytes([0, 0, 0]) + bytes([0]))
    wait(lambda: any(message in said for said in w.chat), 'our chat message back')
    st.hit('chat_heard')

    c.send(SB_COMMAND_SUGGESTION, varint(7) + string('/say he'))
    wait(lambda: any(s[0] == 7 for s in w.suggestions), 'command suggestions')
    st.hit('suggestion')

    c.send(SB_CHAT_COMMAND, string('nosuchcommand'))
    wait(lambda: any('nosuchcommand' in said for said in w.chat), 'an answer to the unknown command')
    st.hit('unknown_command')


def verify_session(c, st, w, biomes, ctx, args):
    """--verify: the second visit. What the first run left is all still there."""
    with open(args.verify) as f:
        saved = json.load(f)
    pump(c, st, w, biomes, ctx, lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    bx, by, bz = saved['placed_at']
    pump(c, st, w, biomes, ctx, lambda: w.block(bx, by, bz) is not None, 'the chunk of the placed block', 30.0)
    found = w.block(bx, by, bz)
    print('  block at %d %d %d: state %d' % (bx, by, bz, found))
    check(found == STONE_STATE, 'the placed stone is state %d after coming back' % found)
    st.hit('placed_block_persisted')
    sx, sy, sz = saved['walked_to']
    dx, dy, dz = w.pos[0] - sx, w.pos[1] - sy, w.pos[2] - sz
    print('  back at %.3f %.3f %.3f, left at %.3f %.3f %.3f' % (w.pos[0], w.pos[1], w.pos[2], sx, sy, sz))
    check(abs(dx) < 0.001 and abs(dy) < 0.001 and abs(dz) < 0.001, 'the position was not persisted')
    st.hit('position_persisted')
    pump(c, st, w, biomes, ctx, lambda: w.window0 is not None, 'the inventory')
    print('  slot 37: %s' % (w.window0[37],))
    check(w.window0[37] == (64, STONE_ITEM), 'the stack in slot 37 is %s' % (w.window0[37],))
    st.hit('inventory_persisted')
    check(w.mode == 1, 'game mode %s after coming back' % w.mode)
    st.hit('gamemode_persisted')


def far_session(c, st, w, biomes, ctx, args):
    """--far-chunk: move far enough that chunks must be generated; they arrive, and keep-alives never stop."""
    fx, fz = args.far_chunk
    pump(c, st, w, biomes, ctx, lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    x, y, z = fx * 16 + 8.0, 200.0, fz * 16 + 8.0
    c.send(SB_MOVE_POS, struct.pack('>ddd', x, y, z) + move_flags(False))
    before = ctx['keep_alives']
    started = time.time()
    pump(c, st, w, biomes, ctx, lambda: (fx, fz) in w.chunks, 'the generated chunk at %d,%d' % (fx, fz), 120.0)
    print('  chunk %d,%d arrived after %.1fs, %d chunks parsed, %d keep-alives since' % (
        fx, fz, time.time() - started, ctx['chunks'], ctx['keep_alives'] - before))
    st.hit('far_chunk_generated')
    pump(c, st, w, biomes, ctx, lambda: ctx['keep_alives'] > before, 'a keep-alive during generation', 40.0)
    st.hit('keep_alive_during_generation')


def commands_session(c, st, w, biomes, ctx, args):
    """--commands: the real dispatcher, over the wire. The bot must be an operator of level 4."""
    def wait(cond, what, seconds=10.0):
        pump(c, st, w, biomes, ctx, cond, what, seconds)

    def run_command(line):
        print('  /%s' % line, flush=True)
        c.send(SB_CHAT_COMMAND, string(line))

    def heard(fragment, since):
        return any(fragment in said for said in w.chat[since:])

    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    wait(lambda: w.window0 is not None and w.health is not None, 'the inventory and health')
    wait(lambda: 'nodes' in COMMAND_TREE, 'the command tree')
    nodes = COMMAND_TREE['nodes']
    root = nodes[COMMAND_TREE['root']]
    names = sorted(nodes[i]['name'] for i in root['children'])
    print('  tree: %d nodes, %d root children: %s' % (len(nodes), len(names), ' '.join(names)))
    st.hit('tree_parsed')
    for wanted in ('setblock', 'fill', 'give', 'gamemode', 'time', 'kill', 'say', 'msg', 'gamerule', 'tp', 'teleport', 'execute'):
        check(wanted in names, 'the root has no %s' % wanted)
    st.hit('tree_children')

    # What the bad commands answer.
    at = len(w.chat)
    run_command('nosuchcommand')
    wait(lambda: heard('nosuchcommand', at), 'the unknown command error')
    print('  said: %r' % w.chat[at:])
    st.hit('unknown_error')
    at = len(w.chat)
    run_command('setblock 0 64 0 not_a_block')
    wait(lambda: len(w.chat) > at, 'the bad block error')
    print('  said: %r' % w.chat[at:])
    check(any('not_a_block' in said for said in w.chat[at:]), 'no mention of the bad block')
    st.hit('bad_block_error')
    at = len(w.chat)
    run_command('gamemode nosuchmode')
    wait(lambda: len(w.chat) > at, 'the bad game mode error')
    print('  said: %r' % w.chat[at:])
    check(any('command.unknown.argument' in said for said in w.chat[at:]), 'no error for the bad game mode')
    st.hit('bad_mode_error')

    # Dying first: a respawn empties a survival inventory.
    run_command('kill @s')
    wait(lambda: w.health[0] <= 0.0, 'health to fall to nothing')
    print('  dead, health %.1f' % w.health[0])
    st.hit('kill_dead')
    c.send(SB_CLIENT_COMMAND, varint(0))
    wait(lambda: w.health[0] > 0.0, 'the respawn')
    print('  respawned, health %.1f' % w.health[0])
    st.hit('kill_respawned')

    x, y, z = int(w.pos[0] // 1), int(w.pos[1] // 1), int(w.pos[2] // 1)
    wait(lambda: w.block(x, y, z) is not None, 'the chunk under the player', 30.0)
    sx, sy, sz = x + 2, y + 6, z + 2
    run_command('setblock %d %d %d minecraft:stone' % (sx, sy, sz))
    wait(lambda: w.overrides.get((sx, sy, sz)) == 1, 'the stone from /setblock')
    print('  block at %d %d %d is state %d' % (sx, sy, sz, w.overrides[(sx, sy, sz)]))
    st.hit('setblock_update')
    run_command('fill %d %d %d %d %d %d granite' % (sx, sy + 2, sz, sx + 1, sy + 3, sz + 1))
    cube = [(sx + i, sy + 2 + j, sz + k) for i in (0, 1) for j in (0, 1) for k in (0, 1)]
    wait(lambda: all(w.overrides.get(p) == 2 for p in cube), 'the granite from /fill')
    print('  %d blocks of state 2 from /fill' % len(cube))
    st.hit('fill_update')

    run_command('give @s stone 5')
    wait(lambda: any(s == (5, STONE_ITEM) for s in w.window0), 'five stone in the window')
    print('  window 0 slot %d holds 5 stone' % w.window0.index((5, STONE_ITEM)))
    st.hit('give_slot')

    run_command('gamemode creative')
    wait(lambda: w.mode == 1, 'creative')
    st.hit('gamemode_creative')
    run_command('gamemode survival')
    wait(lambda: w.mode == 0, 'survival')
    st.hit('gamemode_survival')

    run_command('time set 1000')
    wait(lambda: w.time is not None and w.time[1] % 24000 in range(1000, 1200), 'the time packet')
    print('  world age %d, time of day %d' % w.time)
    st.hit('time_set')
    at = len(w.chat)
    run_command('time query daytime')
    wait(lambda: heard('commands.time.query', at), 'the time query')
    print('  said: %r' % w.chat[at:])
    st.hit('time_query')

    tx, ty, tz = x + 3.5, y + 10.0, z - 2.5
    run_command('tp @s %.1f %.1f %.1f' % (tx, ty, tz))
    wait(lambda: abs(w.pos[0] - tx) < 0.01 and abs(w.pos[1] - ty) < 0.01 and abs(w.pos[2] - tz) < 0.01, 'the teleport')
    print('  teleported to %.2f %.2f %.2f' % w.pos)
    st.hit('tp_moved')

    # /execute. As upstream, `run` reaches only the new dispatcher, so /tag is the command: its answer shows it ran, and
    # the tags are on the player the selector found through the modified source.
    ex, ey, ez = x + 5, y + 8, z + 5
    run_command('setblock %d %d %d stone' % (ex, ey, ez))
    wait(lambda: w.overrides.get((ex, ey, ez)) == 1, 'the stone for /execute')
    at = len(w.chat)
    run_command('execute as @s at @s positioned ~ ~1 ~ run tag @s add through_execute')
    wait(lambda: heard('through_execute', at), 'the tag through /execute as')
    print('  said: %r' % w.chat[at:])
    at = len(w.chat)
    run_command('execute unless block %d %d %d stone run tag @s add must_not_be' % (ex, ey, ez))
    run_command('execute if block %d %d %d stone run tag @s add must_be' % (ex, ey, ez))
    wait(lambda: heard('must_be', at), 'the tag through /execute if block')
    print('  said: %r' % w.chat[at:])
    check(not heard('must_not_be', at), 'execute unless block ran its command')
    at = len(w.chat)
    run_command('tag @s list')
    wait(lambda: heard('through_execute', at), 'the tags listed')
    print('  said: %r' % w.chat[at:])
    st.hit('execute_run')

    c.send(SB_COMMAND_SUGGESTION, varint(21) + string('/difficulty e'))
    wait(lambda: any(s[0] == 21 for s in w.suggestions), 'suggestions for /difficulty e')
    found = [s for s in w.suggestions if s[0] == 21][0]
    print('  /difficulty e suggests start %d length %d: %s' % (found[2], found[3], found[4]))
    check('easy' in found[4], 'easy is not among them')
    st.hit('suggest_root')
    # The brigadier side: /kill is on the new dispatcher, and the selector type lists what can follow the @.
    c.send(SB_COMMAND_SUGGESTION, varint(22) + string('/kill @'))
    wait(lambda: any(s[0] == 22 for s in w.suggestions), 'suggestions for /kill @')
    found = [s for s in w.suggestions if s[0] == 22][0]
    print('  /kill @ suggests start %d length %d: %s' % (found[2], found[3], found[4]))
    check('@s' in found[4], 'no @s among them')
    st.hit('suggest_arg')

    if args.save:
        with open(args.save, 'w') as f:
            json.dump(dict(setblock=[sx, sy, sz], fill=cube, tp=[tx, ty, tz]), f)


def commands3_session(c, st, w, biomes, ctx, args):
    """--commands3: /help, /pumpkin, /attribute, /advancement and /dialog, over the wire. The bot must be an operator of
    level 4. Each one is judged by what the server says back: feedback goes out as translation keys or plain text."""
    def wait(cond, what, seconds=10.0):
        pump(c, st, w, biomes, ctx, cond, what, seconds)

    def run_command(line):
        print('  /%s' % line, flush=True)
        c.send(SB_CHAT_COMMAND, string(line))

    def says(line, fragment, stage):
        at = len(w.chat)
        run_command(line)
        wait(lambda: any(fragment in said for said in w.chat[at:]), 'the answer to /%s containing %r' % (line, fragment))
        print('  said: %r' % w.chat[at:][-1][:160])
        st.hit(stage)

    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    wait(lambda: w.window0 is not None and w.health is not None, 'the inventory and health')
    wait(lambda: 'nodes' in COMMAND_TREE, 'the command tree')
    nodes = COMMAND_TREE['nodes']
    names = sorted(nodes[i]['name'] for i in nodes[COMMAND_TREE['root']]['children'])
    for wanted in ('help', 'dialog', 'attribute', 'advancement'):
        check(wanted in names, 'the root has no %s' % wanted)
    st.hit('tree3_children')
    says('help', 'Help - Page 1/', 'help_page')
    says('help gamemode', 'Help - /gamemode', 'help_command')
    says('pumpkin', 'Pumpkin ', 'pumpkin_version')
    says('attribute @s minecraft:max_health get', 'commands.attribute.value.get.success', 'attribute_get')
    says('attribute @s minecraft:max_health base set 30', 'commands.attribute.base_value.set.success', 'attribute_base_set')
    says('advancement grant @s only minecraft:story/root', 'commands.advancement.grant.one.to.one.success', 'advancement_grant')
    says('advancement revoke @s only minecraft:story/root', 'commands.advancement.revoke.one.to.one.success', 'advancement_revoke')
    says('advancement revoke @s only minecraft:story/root', 'commands.advancement.revoke.one.to.one.failure', 'advancement_revoke_again')
    says('dialog show @s {type:"minecraft:notice",title:"Hello"}', 'Showed dialog to', 'dialog_show')
    says('dialog clear @s', 'Cleared dialog for', 'dialog_clear')


def commands2_session(c, st, w, biomes, ctx, args):
    """--commands2: /clone, /place, /item, /spreadplayers, /rotate, /fillbiome, /loot, /ride and /spectate, over the wire.
    The bot must be an operator of level 4. Each command is judged by the packets it makes: the block updates a clone and a
    placed template send, the slot packet of /item, the teleport of /spreadplayers and /rotate, and the chunk /fillbiome sends."""
    def wait(cond, what, seconds=10.0):
        pump(c, st, w, biomes, ctx, cond, what, seconds)

    def run_command(line):
        print('  /%s' % line, flush=True)
        c.send(SB_CHAT_COMMAND, string(line))

    def heard(fragment, since):
        return any(fragment in said for said in w.chat[since:])

    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    wait(lambda: w.window0 is not None and w.health is not None, 'the inventory and health')
    wait(lambda: 'nodes' in COMMAND_TREE, 'the command tree')
    nodes = COMMAND_TREE['nodes']
    names = sorted(nodes[i]['name'] for i in nodes[COMMAND_TREE['root']]['children'])
    for wanted in ('clone', 'place', 'item', 'spreadplayers', 'rotate', 'fillbiome', 'loot', 'ride', 'spectate'):
        check(wanted in names, 'the root has no %s' % wanted)
    st.hit('tree2_children')

    x, y, z = int(w.pos[0] // 1), int(w.pos[1] // 1), int(w.pos[2] // 1)
    wait(lambda: w.block(x, y, z) is not None, 'the chunk under the player', 30.0)

    # /fill a pattern, /clone it elsewhere and read the copies back.
    bx, by, bz = x + 2, y + 8, z + 2
    run_command('fill %d %d %d %d %d %d granite' % (bx, by, bz, bx + 1, by + 1, bz + 1))
    src = [(bx + i, by + j, bz + k) for i in (0, 1) for j in (0, 1) for k in (0, 1)]
    wait(lambda: all(w.overrides.get(p) == 2 for p in src), 'the granite to clone')
    run_command('setblock %d %d %d stone' % (bx, by + 1, bz))
    wait(lambda: w.overrides.get((bx, by + 1, bz)) == 1, 'the stone in the pattern')
    dx, dy, dz = x + 8, y + 8, z + 2
    run_command('clone %d %d %d %d %d %d %d %d %d' % (bx, by, bz, bx + 1, by + 1, bz + 1, dx, dy, dz))
    copy = [(dx + (p[0] - bx), dy + (p[1] - by), dz + (p[2] - bz)) for p in src]
    expect = {q: (1 if p == (bx, by + 1, bz) else 2) for p, q in zip(src, copy)}
    wait(lambda: all(w.overrides.get(q) == expect[q] for q in copy), 'the cloned blocks')
    print('  cloned: %s' % [w.overrides[q] for q in copy])
    st.hit('clone_copied')
    mx, my, mz = x + 8, y + 8, z + 6
    run_command('clone %d %d %d %d %d %d %d %d %d replace move' % (dx, dy, dz, dx + 1, dy + 1, dz + 1, mx, my, mz))
    moved = [(mx + (p[0] - dx), my + (p[1] - dy), mz + (p[2] - dz)) for p in copy]
    wait(lambda: all(w.overrides.get(q) in (1, 2) for q in moved) and all(w.overrides.get(q) == 0 for q in copy),
         'the moved blocks, and the source cleared')
    print('  moved: %s, source now %s' % ([w.overrides[q] for q in moved], [w.overrides[q] for q in copy]))
    st.hit('clone_moved')

    # /place template and /place structure: blocks appear.
    before = len(w.overrides)
    run_command('place template minecraft:igloo/top %d %d %d' % (x - 6, y + 12, z + 6))
    wait(lambda: len(w.overrides) - before >= 20, 'the placed template blocks')
    print('  place template: %d more block updates' % (len(w.overrides) - before))
    st.hit('place_template')
    before = len(w.overrides)
    run_command('place structure minecraft:igloo %d %d %d' % (x - 8, y + 12, z - 8))
    wait(lambda: len(w.overrides) - before >= 20, 'the placed structure blocks')
    print('  place structure: %d more block updates' % (len(w.overrides) - before))
    st.hit('place_structure')

    # /item replace into a slot: the slot packet.
    run_command('item replace entity @s hotbar.0 minecraft:diamond 5')
    wait(lambda: w.window0[36][0] == 5, 'five items in the first hotbar slot')
    diamond = w.window0[36][1]
    print('  hotbar 0 holds 5 of item %d' % diamond)
    check(diamond != STONE_ITEM, 'the item in the slot is the stone, not the diamond')
    st.hit('item_slot')
    run_command('item replace entity @s weapon.mainhand with minecraft:stick')
    wait(lambda: w.window0[36][0] == 1 and w.window0[36][1] != diamond, 'the stick in the main hand slot')
    st.hit('item_mainhand')

    # /spreadplayers: a teleport onto the surface within the area.
    w.rot = None
    before_pos = w.pos
    run_command('spreadplayers %d %d 1 8 false @s' % (x + 20, z + 20))
    wait(lambda: abs(w.pos[0] - (x + 20.5)) < 8.6 and abs(w.pos[2] - (z + 20.5)) < 8.6 and w.pos != before_pos,
         'the spreadplayers teleport')
    print('  spread to %.2f %.2f %.2f' % w.pos)
    check(abs(w.pos[0] % 1.0 - 0.5) < 1e-6 and abs(w.pos[2] % 1.0 - 0.5) < 1e-6, 'not at a block centre')
    st.hit('spreadplayers_teleport')

    # /rotate: a teleport in place with the new rotation.
    here = w.pos
    run_command('rotate @s 90 30')
    wait(lambda: w.rot is not None and abs(w.rot[0] - 90.0) < 0.01 and abs(w.rot[1] - 30.0) < 0.01, 'the rotation teleport')
    check(w.pos == here, 'rotate moved the player: %r to %r' % (here, w.pos))
    print('  rotated to yaw %.1f pitch %.1f' % w.rot)
    st.hit('rotate_absolute')
    run_command('rotate @s facing %.1f %.2f %.1f' % (here[0] + 10.0, here[1] + 1.62, here[2]))
    wait(lambda: w.rot is not None and abs(w.rot[0] + 90.0) < 0.01 and abs(w.rot[1]) < 0.05, 'the facing rotation')
    print('  facing east: yaw %.1f pitch %.1f' % w.rot)
    st.hit('rotate_facing')

    # /fillbiome: the changed chunk is sent again.
    seen = ctx['chunks']
    at = len(w.chat)
    run_command('fillbiome %d %d %d %d %d %d minecraft:desert' % (x, y, z, x + 4, y + 4, z + 4))
    wait(lambda: ctx['chunks'] > seen and heard('commands.fillbiome.success', at), 'the chunk and the answer')
    print('  said: %r' % w.chat[at:])
    st.hit('fillbiome_chunk')

    # /loot into the player.
    filled = sum(1 for s in w.window0 if s[0] > 0)
    run_command('loot give @s loot minecraft:chests/simple_dungeon')
    wait(lambda: sum(1 for s in w.window0 if s[0] > 0) > filled, 'loot in the inventory')
    print('  %d stacks in the inventory, was %d' % (sum(1 for s in w.window0 if s[0] > 0), filled))
    st.hit('loot_given')

    # /ride and /spectate answer as upstream does for a lone player.
    at = len(w.chat)
    run_command('ride @s dismount')
    wait(lambda: heard('commands.ride.not_riding', at), 'the not riding error')
    st.hit('ride_not_riding')
    run_command('gamemode spectator')
    wait(lambda: w.mode == 3, 'spectator')
    at = len(w.chat)
    run_command('spectate @s')
    wait(lambda: heard('commands.spectate.self', at), 'the cannot spectate yourself error')
    st.hit('spectate_self')
    at = len(w.chat)
    run_command('spectate')
    wait(lambda: heard('commands.spectate.success.stopped', at), 'the spectate stopped message')
    st.hit('spectate_stopped')
    run_command('gamemode survival')
    wait(lambda: w.mode == 0, 'survival')


def plugin_session(c, st, w, biomes, ctx, args):
    """--plugin X Y Z: a plugin that scheduled a task at load has, by the time the bot is in, set the block at X Y Z and
    shown the bot a boss bar. Waits for both on the wire: a boss event (add, then health 0.5) and the block update."""
    def wait(cond, what, seconds=60.0):
        pump(c, st, w, biomes, ctx, cond, what, seconds)

    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    x, y, z = args.plugin
    base = len(w.events)
    before = w.block(x, y, z)
    print('  block %d %d %d before the plugin task: %r' % (x, y, z, before), flush=True)
    wait(lambda: any(e[0] == 'boss' for e in w.events[base:]), 'the boss bar of the plugin', 120.0)
    boss = [e for e in w.events[base:] if e[0] == 'boss']
    print('  boss events: %r' % (boss,), flush=True)
    check(boss[0][2] == 0, 'the first boss event is not an add: %r' % (boss[0],))
    wait(lambda: any(e[0] == 'boss' and e[2] == 2 for e in w.events[base:]), 'the boss bar health update', 20.0)
    health = [e for e in w.events[base:] if e[0] == 'boss' and e[2] == 2]
    check(abs(health[0][3] - 0.5) < 1e-6, 'boss bar health %r' % (health[0],))
    wait(lambda: w.block(x, y, z) is not None and w.block(x, y, z) != before, 'the block change of the plugin', 20.0)
    print('  block %d %d %d is now state %r' % (x, y, z, w.block(x, y, z)), flush=True)
    if args.plugin_state is not None:
        check(w.block(x, y, z) == args.plugin_state, 'block state %r, wanted %r' % (w.block(x, y, z), args.plugin_state))
    print('  plugin session ok', flush=True)


def scoreboard_session(c, st, w, biomes, ctx, args):
    """--scoreboard: /scoreboard, /trigger, /team, /bossbar, /worldborder, /tick and /data, over the wire, with the packets
    each one makes. The bot must be an operator of level 4. This is the second half of --commands."""
    def wait(cond, what, seconds=10.0):
        pump(c, st, w, biomes, ctx, cond, what, seconds)

    def run_command(line):
        print('  /%s' % line, flush=True)
        c.send(SB_CHAT_COMMAND, string(line))

    def heard(fragment, since):
        return any(fragment in said for said in w.chat[since:])

    def event(kind, since, where=lambda e: True):
        return next((e for e in w.events[since:] if e[0] == kind and where(e)), None)

    def expect(kind, where=lambda e: True, what=None):
        """Waits for a packet of this kind after now-ish, and returns it."""
        wait(lambda: event(kind, base, where) is not None, what or kind)
        return event(kind, base, where)

    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    wait(lambda: w.window0 is not None and w.health is not None, 'the inventory and health')
    wait(lambda: 'nodes' in COMMAND_TREE, 'the command tree')
    names = sorted(COMMAND_TREE['nodes'][i]['name'] for i in COMMAND_TREE['nodes'][COMMAND_TREE['root']]['children'])
    for wanted in ('scoreboard', 'team', 'bossbar', 'worldborder', 'tick', 'data', 'trigger'):
        check(wanted in names, 'the root has no %s' % wanted)
    me = args.name

    # Objectives and scores: an objective is announced, then shown on the sidebar; /scoreboard players enable primes
    # a trigger objective and sends its score, /trigger adds to it.
    base = len(w.events)
    run_command('scoreboard objectives add kills trigger Kill count')
    e = expect('objective', what='the objective packet')
    check(e[1:] == ('kills', 0), 'objective packet %r' % (e,))
    st.hit('objective_added')
    e = expect('display', what='the sidebar packet')
    check(e[2] == 'kills', 'display packet %r' % (e,))
    st.hit('sidebar_shown')
    base = len(w.events)
    run_command('scoreboard players enable %s kills' % me)
    e = expect('score', what='the score packet from enable')
    check(e[1:] == (me, 'kills', 0), 'enable score %r' % (e,))
    st.hit('score_enabled')
    base = len(w.events)
    run_command('trigger kills add 3')
    e = expect('score', what='the score packet from trigger')
    check(e[1:] == (me, 'kills', 3), 'trigger score %r' % (e,))
    st.hit('trigger_score')
    at = len(w.chat)
    run_command('trigger kills')
    wait(lambda: heard('commands.trigger.failed.unprimed', at), 'the unprimed error')

    # Teams: created with the packet's name, joined by the bot, then changed.
    base = len(w.events)
    run_command('team add red Red Team')
    e = expect('team', lambda e: e[1] == 'red' and e[2] == 0, 'the team create packet')
    st.hit('team_created')
    base = len(w.events)
    run_command('team join red %s' % me)
    e = expect('team', lambda e: e[1] == 'red' and e[2] == 3, 'the team add-players packet')
    check(e[3] == [me], 'team members %r' % (e,))
    st.hit('team_joined')
    base = len(w.events)
    run_command('team modify red color red')
    e = expect('team', lambda e: e[1] == 'red' and e[2] == 2, 'the team update packet')
    check(e[6] == 12, 'team colour red is 12, got %r' % (e,))
    st.hit('team_updated')
    at = len(w.chat)
    run_command('teammsg hello team')
    wait(lambda: heard('hello team', at), 'the team message')

    # Bossbar: nothing is sent until the bar has players; then it is added with its health.
    base = len(w.events)
    run_command('bossbar add test:bar "Dragon"')
    wait(lambda: heard('commands.bossbar.create.success', 0), 'the bossbar create message')
    run_command('bossbar set test:bar players %s' % me)
    e = expect('boss', lambda e: e[2] == 0, 'the bossbar add packet')
    st.hit('bossbar_added')
    base = len(w.events)
    run_command('bossbar set test:bar value 30')
    e = expect('boss', lambda e: e[2] == 2, 'the bossbar health packet')
    check(abs(e[3] - 0.3) < 1e-6, 'bossbar health %r' % (e,))
    st.hit('bossbar_health')
    base = len(w.events)
    run_command('bossbar set test:bar name "Wither"')
    expect('boss', lambda e: e[2] == 3, 'the bossbar title packet')
    st.hit('bossbar_name')
    at = len(w.chat)
    run_command('bossbar list')
    wait(lambda: heard('commands.bossbar.list.bars.some', at), 'the bossbar list')

    # World border.
    base = len(w.events)
    run_command('worldborder set 200')
    e = expect('border_size', what='the border size packet')
    check(e[1] == 200.0, 'border size %r' % (e,))
    st.hit('border_size')
    base = len(w.events)
    run_command('worldborder center 10.0 20.0')
    e = expect('border_center', what='the border centre packet')
    check(e[1:] == (10.0, 20.0), 'border centre %r' % (e,))
    st.hit('border_center')
    base = len(w.events)
    run_command('worldborder set 100 5')
    e = expect('border_lerp', what='the border lerp packet')
    check(e[1:] == (200.0, 100.0, 5000), 'border lerp %r' % (e,))
    st.hit('border_lerp')
    run_command('worldborder set 59999968')

    # Tick rate: the manager tells the client, and /tick query answers.
    base = len(w.events)
    run_command('tick rate 10')
    e = expect('ticking', what='the ticking state packet')
    check(e[1] == 10.0 and not e[2], 'ticking %r' % (e,))
    st.hit('tick_rate')
    base = len(w.events)
    run_command('tick freeze')
    e = expect('ticking', lambda e: e[2], 'the frozen ticking state')
    st.hit('tick_frozen')
    run_command('tick unfreeze')
    run_command('tick rate 20')
    wait(lambda: any(e[0] == 'ticking' and e[1] == 20.0 and not e[2] for e in w.events[base:]), 'the rate back to 20')
    at = len(w.chat)
    run_command('tick query')
    wait(lambda: heard('commands.tick.query.rate.running', at), 'the tick query')
    print('  said: %r' % w.chat[at:])
    st.hit('tick_query')

    # /data get entity: the player's own NBT, coloured.
    at = len(w.chat)
    run_command('data get entity %s' % me)
    wait(lambda: heard('commands.data.entity.query', at), 'the data answer')
    print('  said: %r' % w.chat[at:][0][:200])
    st.hit('data_get_player')


def commands_verify_session(c, st, w, biomes, ctx, args):
    """--commands-verify: on return, what the commands did is still there."""
    with open(args.commands_verify) as f:
        saved = json.load(f)
    pump(c, st, w, biomes, ctx, lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    pump(c, st, w, biomes, ctx, lambda: w.window0 is not None and w.health is not None, 'the inventory and health', 10.0)
    sx, sy, sz = saved['setblock']
    pump(c, st, w, biomes, ctx, lambda: w.block(sx, sy, sz) is not None, 'the chunk of the stone', 30.0)
    print('  /setblock block: state %d' % w.block(sx, sy, sz))
    check(w.block(sx, sy, sz) == 1, 'the stone is gone')
    st.hit('setblock_persisted')
    for p in saved['fill']:
        check(w.block(*p) == 2, 'granite at %r is state %r' % (p, w.block(*p)))
    print('  /fill blocks: %d of state 2' % len(saved['fill']))
    st.hit('fill_persisted')
    print('  stone stacks: %s' % [s for s in w.window0 if s[1] == STONE_ITEM])
    check((5, STONE_ITEM) in w.window0, 'the stone from /give is gone')
    st.hit('give_persisted')
    print('  back at %.2f %.2f %.2f' % w.pos)
    tx, ty, tz = saved['tp']
    check(abs(w.pos[0] - tx) < 0.01 and abs(w.pos[2] - tz) < 0.01, 'not where /tp left it')
    st.hit('tp_persisted')
    print('  health %.1f' % w.health[0])
    check(w.health[0] > 0.0, 'dead on return')
    st.hit('alive_on_return')



BLOCK_TABLE = {}





def load_block_table(path):

    """blocks.json of the pinned upstream: state id ranges and item ids, so the bot can name what it sees."""

    with open(path) as f:

        blocks = json.load(f)['blocks']

    BLOCK_TABLE['ranges'] = sorted((b['states'][0]['id'], len(b['states']), b['name'], b['default_state_id'], b.get('item_id'))

                                   for b in blocks)

    BLOCK_TABLE['by_name'] = {b['name']: b for b in blocks}





def block_name(state):

    if state is None:

        return None

    for first, count, name, default, item in BLOCK_TABLE['ranges']:

        if first <= state < first + count:

            return name

    return '?%d' % state





def blocks_session(c, st, w, biomes, ctx, args):

    """--blocks: what blocks do, over the wire. The bot must be an operator of level 4, on a COPY of a world.



    Builds a stone stage with /fill, then plays: a door placed (both halves arrive) and opened and closed; a lever, three

    dust and a lamp, the lamp lighting when the lever is thrown and going dark when it is thrown back; a sand block placed

    against a pillar with air under it, which falls; and, where the server has fluids, a water source that flows."""

    def wait(cond, what, seconds=10.0):

        pump(c, st, w, biomes, ctx, cond, what, seconds)



    def settle(seconds=0.6):

        """Keeps reading for a while: block updates are flushed on the server's tick."""

        end = time.time() + seconds

        while time.time() < end:

            try:

                pid, r = c.recv()

            except socket.timeout:

                continue

            one_packet(c, st, w, biomes, ctx, pid, r)



    def cmd(line):

        print('  /%s' % line, flush=True)

        c.send(SB_CHAT_COMMAND, string(line))



    token = [0x7000]



    def sync():

        token[0] += 1

        c.send(SB_PING, struct.pack('>q', token[0]))

        t = token[0]

        wait(lambda: t in w.pongs, 'a pong')



    def item_of(name):

        return BLOCK_TABLE['by_name'][name]['item_id']



    def hold(name):

        c.send(SB_CREATIVE, struct.pack('>h', 36) + write_slot(64, item_of(name)))

        c.send(SB_CARRIED, struct.pack('>h', 0))

        sync()



    seq = [100]



    def use_on(x, y, z, face, cursor=(0.5, 0.5, 0.5)):

        seq[0] += 1

        c.send(SB_USE_ON, varint(0) + block_pos(x, y, z) + varint(face) + struct.pack('>fff', *cursor) + bytes([0, 0]) +

               varint(seq[0]))



    def state_at(x, y, z):

        return w.block(x, y, z)



    def name_at(x, y, z):

        return block_name(state_at(x, y, z))



    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)

    wait(lambda: w.health is not None, 'health')

    c.send(SB_CHANGE_GAME_MODE, varint(1))

    wait(lambda: w.mode == 1, 'creative')

    px, py, pz = int(w.pos[0] // 1), int(w.pos[1] // 1), int(w.pos[2] // 1)

    wait(lambda: w.block(px, py - 1, pz) is not None, 'the chunk under the player', 30.0)



    # The stage: 12 wide, 7 deep, stone floor one below the feet, clear above, then stand in the middle of its south edge.

    sx, fy, sz = px + 2, py - 1, pz + 2

    cmd('fill %d %d %d %d %d %d minecraft:air' % (sx - 1, fy + 1, sz - 1, sx + 12, fy + 8, sz + 7))

    cmd('fill %d %d %d %d %d %d minecraft:stone' % (sx - 1, fy, sz - 1, sx + 12, fy, sz + 7))

    cmd('tp @s %d %d %d' % (sx + 6, fy + 1, sz + 6))

    wait(lambda: name_at(sx + 6, fy, sz + 6) == 'stone' and name_at(sx + 6, fy + 3, sz + 6) == 'air', 'the stage')

    settle(1.0)

    check(name_at(sx, fy, sz) == 'stone', 'the stage floor is %s' % name_at(sx, fy, sz))

    print('  stage floor y=%d from %d,%d' % (fy, sx, sz), flush=True)



    # --- A door: both halves, then open and shut.

    dx, dz = sx + 1, sz + 1

    hold('oak_door')

    use_on(dx, fy, dz, 1, (0.5, 1.0, 0.5))

    wait(lambda: name_at(dx, fy + 1, dz) == 'oak_door' and name_at(dx, fy + 2, dz) == 'oak_door', 'both halves of a door')

    closed = (state_at(dx, fy + 1, dz), state_at(dx, fy + 2, dz))

    print('  door: lower %s upper %s' % closed)

    check(closed[0] != closed[1], 'the two halves of a door are the same state')

    st.hit('door_placed')

    hold('stone')

    use_on(dx, fy + 1, dz, 3)  # right-click the door's south face with stone in hand: a door answers before the item

    wait(lambda: state_at(dx, fy + 1, dz) != closed[0] and state_at(dx, fy + 2, dz) != closed[1], 'the door to open')

    opened = (state_at(dx, fy + 1, dz), state_at(dx, fy + 2, dz))

    print('  door opened: lower %s upper %s' % opened)

    st.hit('door_opened')

    use_on(dx, fy + 1, dz, 3)

    wait(lambda: (state_at(dx, fy + 1, dz), state_at(dx, fy + 2, dz)) == closed, 'the door to close')

    st.hit('door_closed')



    # --- A lamp at the end of a dust line, fed by a lever.

    ly = fy + 1

    lx, lz = sx + 4, sz + 1

    hold('lever')

    use_on(lx, fy, lz, 1, (0.5, 1.0, 0.5))

    wait(lambda: name_at(lx, ly, lz) == 'lever', 'a lever')

    hold('redstone')

    for i in (1, 2, 3):

        use_on(lx + i, fy, lz, 1, (0.5, 1.0, 0.5))

        wait(lambda i=i: name_at(lx + i, ly, lz) == 'redstone_wire', 'dust %d' % i)

    hold('redstone_lamp')

    use_on(lx + 4, fy, lz, 1, (0.5, 1.0, 0.5))

    wait(lambda: name_at(lx + 4, ly, lz) == 'redstone_lamp', 'a lamp')

    settle(0.5)

    dark = state_at(lx + 4, ly, lz)

    check(dark == BLOCK_TABLE['by_name']['redstone_lamp']['default_state_id'], 'the lamp is not in its default state')

    print('  lever, 3 dust, lamp placed: lamp state %d (unlit)' % dark)

    st.hit('lamp_line_placed')

    hold('stone')

    use_on(lx, ly, lz, 1)

    wait(lambda: state_at(lx + 4, ly, lz) != dark, 'the lamp to light', 8.0)

    print('  lever thrown: lamp state %d' % state_at(lx + 4, ly, lz))

    st.hit('lamp_lit')

    use_on(lx, ly, lz, 1)

    wait(lambda: state_at(lx + 4, ly, lz) == dark, 'the lamp to go dark again', 8.0)

    st.hit('lamp_dark')



    # --- Sand placed against a pillar, with nothing under it.

    px2, pz2 = sx + 9, sz + 4

    cmd('fill %d %d %d %d %d %d minecraft:stone' % (px2, fy + 1, pz2, px2, fy + 4, pz2))

    wait(lambda: name_at(px2, fy + 4, pz2) == 'stone', 'the pillar')

    hold('sand')

    use_on(px2, fy + 4, pz2, 5, (1.0, 0.5, 0.5))  # its east face: sand at px2+1, fy+4, in the air

    sand_at = (px2 + 1, fy + 4, pz2)

    wait(lambda: name_at(*sand_at) == 'sand', 'sand in the air')

    print('  sand placed at %s' % (sand_at,), flush=True)

    wait(lambda: name_at(*sand_at) == 'air', 'the sand to fall', 8.0)

    wait(lambda: name_at(px2 + 1, fy + 1, pz2) == 'sand', 'the sand to land', 8.0)

    print('  sand landed at %d %d %d' % (px2 + 1, fy + 1, pz2))

    st.hit('sand_fell')

    ctx['blocks_state'] = dict(door=[dx, fy + 1, dz, closed[0], closed[1]], lamp=[lx + 4, ly, lz, dark],

                               sand=[px2 + 1, fy + 1, pz2])



    # --- Water, where the server has fluids.

    wx, wz = sx + 6, sz + 1

    cmd('setblock %d %d %d minecraft:water' % (wx, fy + 1, wz))

    wait(lambda: name_at(wx, fy + 1, wz) == 'water', 'water from /setblock')

    settle(3.0)

    spread = [(wx + i, fy + 1, wz + j) for i, j in ((1, 0), (-1, 0), (0, 1), (0, -1))]

    flowed = [p for p in spread if name_at(*p) == 'water']

    print('  water source placed; %d of 4 neighbours became water' % len(flowed))

    check(len(flowed) == 4, 'the water did not flow: %d of 4 neighbours' % len(flowed))

    st.hit('water_flowed')





def blocks_verify_session(c, st, w, biomes, ctx, args):

    """--blocks-verify FILE: after a restart, the door, the lamp and the sand are still in the chunk the server sends."""

    with open(args.blocks_verify) as f:

        saved = json.load(f)

    door, lamp, sand = saved['door'], saved['lamp'], saved['sand']

    pump(c, st, w, biomes, ctx, lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)

    pump(c, st, w, biomes, ctx, lambda: w.block(door[0], door[1], door[2]) is not None, 'the stage chunk', 30.0)

    check(w.block(door[0], door[1], door[2]) == door[3] and w.block(door[0], door[1] + 1, door[2]) == door[4],

          'the door: %s %s' % (block_name(w.block(door[0], door[1], door[2])), block_name(w.block(door[0], door[1] + 1, door[2]))))

    check(w.block(lamp[0], lamp[1], lamp[2]) == lamp[3], 'the lamp is %s' % block_name(w.block(lamp[0], lamp[1], lamp[2])))

    check(block_name(w.block(sand[0], sand[1], sand[2])) == 'sand', 'the sand is %s' % block_name(w.block(*sand)))

    st.hit('blocks_persisted')


PLAY_OPEN_SCREEN = 57


def containers_session(c, st, w, biomes, ctx, args):
    """--containers: a chest, a barrel and a trapped chest are opened over the wire and a stack is shift-clicked into each.
    The bot must be an operator of level 4, on a COPY of a world. --containers-verify FILE, after a restart, opens them again
    and wants the stacks still there."""
    log = []
    ctx['tap'] = lambda pid, data: log.append((pid, bytes(data)))

    def wait(cond, what, seconds=10.0):
        pump(c, st, w, biomes, ctx, cond, what, seconds)

    def settle(seconds=0.6):
        end = time.time() + seconds
        while time.time() < end:
            try:
                pid, r = c.recv()
            except socket.timeout:
                continue
            one_packet(c, st, w, biomes, ctx, pid, r)

    def cmd(line):
        print('  /%s' % line, flush=True)
        c.send(SB_CHAT_COMMAND, string(line))

    token = [0x7100]

    def sync():
        token[0] += 1
        c.send(SB_PING, struct.pack('>q', token[0]))
        t = token[0]
        wait(lambda: t in w.pongs, 'a pong')

    def item_of(name):
        return BLOCK_TABLE['by_name'][name]['item_id']

    def hold(name):
        """Puts 64 of the item in hotbar slot 0 by the server's own /give: the ids of --blocks' table are not 774's."""
        cmd('clear @s')
        cmd('give @s minecraft:%s 64' % name)
        c.send(SB_CARRIED, struct.pack('>h', 0))
        settle(0.6)
        sync()

    seq = [300]

    def use_on(x, y, z, face, cursor=(0.5, 0.5, 0.5)):
        seq[0] += 1
        c.send(SB_USE_ON, varint(0) + block_pos(x, y, z) + varint(face) + struct.pack('>fff', *cursor) + bytes([0, 0]) +
               varint(seq[0]))

    def name_at(x, y, z):
        return block_name(w.block(x, y, z))

    def window_content(sync_id):
        for p, d in log:
            if p == PLAY_CONTAINER_CONTENT:
                r2 = Reader(d)
                if r2.varint() == sync_id:
                    r2.varint()
                    return [read_slot(r2) for _ in range(r2.varint())]
        return None

    def open_window(x, y, z, face=1):
        """Right-clicks the block and answers (sync id, window type, [stacks of the window])."""
        del log[:]
        use_on(x, y, z, face, (0.5, 1.0, 0.5))
        wait(lambda: any(p == PLAY_OPEN_SCREEN for p, _ in log), 'an open screen packet')
        r = Reader([d for p, d in log if p == PLAY_OPEN_SCREEN][0])
        sync_id, wtype = r.varint(), r.varint()
        print('  opened window %d, type %d' % (sync_id, wtype), flush=True)
        wait(lambda: window_content(sync_id) is not None, 'the window content')
        return sync_id, wtype, window_content(sync_id)

    def slot_update(sync_id, slot):
        """The latest value of (window, slot) from the set-slot and whole-window packets, in the order they came, or None."""
        got = None
        for p, d in log:
            if p == PLAY_CONTAINER_SLOT:
                r2 = Reader(d)
                if struct.unpack('>b', r2.take(1))[0] == sync_id:
                    r2.varint()
                    if r2.i16() == slot:
                        got = read_slot(r2)
            elif p == PLAY_CONTAINER_CONTENT:
                r2 = Reader(d)
                if r2.varint() == sync_id:
                    r2.varint()
                    stacks = [read_slot(r2) for _ in range(r2.varint())]
                    if slot < len(stacks):
                        got = stacks[slot]
        return got

    def shift_click(sync_id, slot):
        c.send(SB_CONTAINER_CLICK, varint(sync_id) + varint(0) + struct.pack('>h', slot) + bytes([0]) + varint(1) +
               varint(0) + bytes([0]))

    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    wait(lambda: w.health is not None, 'health')
    c.send(SB_CHANGE_GAME_MODE, varint(1))
    wait(lambda: w.mode == 1, 'creative')
    px, py, pz = int(w.pos[0] // 1), int(w.pos[1] // 1), int(w.pos[2] // 1)
    wait(lambda: w.block(px, py - 1, pz) is not None, 'the chunk under the player', 30.0)
    sx, fy, sz = px + 2, py - 1, pz + 2
    cmd('fill %d %d %d %d %d %d minecraft:air' % (sx - 1, fy + 1, sz - 1, sx + 12, fy + 8, sz + 7))
    cmd('fill %d %d %d %d %d %d minecraft:stone' % (sx - 1, fy, sz - 1, sx + 12, fy, sz + 7))
    cmd('tp @s %d %d %d' % (sx + 6, fy + 1, sz + 6))
    wait(lambda: name_at(sx + 6, fy, sz + 6) == 'stone' and name_at(sx + 6, fy + 3, sz + 6) == 'air', 'the stage')
    settle(1.0)

    saved = {}
    stone = STONE_ITEM
    for k, name in enumerate(('chest', 'barrel', 'trapped_chest')):
        bx, bz = sx + 4 + 2 * k, sz + 4  # within reach of the bot at sx + 6, sz + 6
        hold(name)
        use_on(bx, fy, bz, 1, (0.5, 1.0, 0.5))
        # The bot's block table is not 774's for every state id, so a placement is a state that is not air.
        try:
            wait(lambda: w.block(bx, fy + 1, bz) not in (None, 0), 'a %s' % name)
        except Fail:
            raise Fail('no %s at %d %d %d: the state there is %s, chat %r' % (name, bx, fy + 1, bz, w.block(bx, fy + 1, bz), w.chat[-3:]))
        settle(0.4)
        print('  %s placed at %d %d %d' % (name, bx, fy + 1, bz), flush=True)
        st.hit('container_placed')
        hold('stone')
        sync_id, wtype, slots = open_window(bx, fy + 1, bz)
        check(wtype == 2, '%s: window type %d, not generic 9x3 (2)' % (name, wtype))
        check(len(slots) == 27 + 36, '%s: %d slots in its window' % (name, len(slots)))
        check(all(s[0] == 0 for s in slots[:27]), '%s is not empty to begin with' % name)
        st.hit('container_opened')
        # Hotbar slot 0 is window slot 54 of a 9x3 container.
        check(slots[54] == (64, stone), '%s: hotbar 0 reads %s' % (name, (slots[54],)))
        del log[:]
        shift_click(sync_id, 54)
        wait(lambda: slot_update(sync_id, 0) == (64, stone), 'the stone to arrive in slot 0 of the %s' % name, 8.0)
        print('  %s slot 0 now %s' % (name, slot_update(sync_id, 0)), flush=True)
        st.hit('container_filled')
        c.send(SB_CONTAINER_CLOSE, varint(sync_id))
        settle(1.0)
        saved[name] = [bx, fy + 1, bz, stone, 64, w.block(bx, fy + 1, bz)]
    # `/item replace block` reaches a block entity's inventory through the world's getBlockContainer.
    bx, by, bz = saved['barrel'][:3]
    cmd('item replace block %d %d %d container.1 with minecraft:stone 5' % (bx, by, bz))
    settle(0.8)
    sync_id, wtype, slots = open_window(bx, by, bz)
    check(slots[0] == (64, stone) and slots[1] == (5, stone), 'barrel after /item replace: %s' % (slots[:3],))
    print('  /item replace block: barrel slot 1 = %s' % (slots[1],), flush=True)
    st.hit('item_replace_block')
    c.send(SB_CONTAINER_CLOSE, varint(sync_id))
    settle(0.5)
    # Blocks that only open a window: the type each answers (generated/screen.aowl's order: generic 9x3 2, generic 3x3 6,
    # anvil 8, crafting 12, enchantment 13, hopper 16, stonecutter 24).
    for k, (name, want) in enumerate((('crafting_table', 12), ('ender_chest', 2), ('shulker_box', 2), ('hopper', 16),
                                      ('dropper', 6), ('anvil', 8), ('stonecutter', 24), ('enchanting_table', 13))):
        bx, bz = sx + 3 + k, sz + 5
        hold(name)
        use_on(bx, fy, bz, 1, (0.5, 1.0, 0.5))
        wait(lambda: w.block(bx, fy + 1, bz) not in (None, 0), 'a %s' % name)
        settle(0.4)
        sync_id, wtype, slots = open_window(bx, fy + 1, bz)
        check(wtype == want, '%s: window type %d, wanted %d' % (name, wtype, want))
        print('  %s opens window type %d with %d slots' % (name, wtype, len(slots)), flush=True)
        st.hit('window_opens')
        c.send(SB_CONTAINER_CLOSE, varint(sync_id))
        settle(0.5)
    ctx['containers_state'] = saved


def containers_verify_session(c, st, w, biomes, ctx, args):
    """--containers-verify FILE: after a restart each container opens with the stack still in slot 0."""
    with open(args.containers_verify) as f:
        saved = json.load(f)
    log = []
    ctx['tap'] = lambda pid, data: log.append((pid, bytes(data)))

    def settle(seconds):
        end = time.time() + seconds
        while time.time() < end:
            try:
                pid, r = c.recv()
            except socket.timeout:
                continue
            one_packet(c, st, w, biomes, ctx, pid, r)

    def window_content(sync_id):
        for p, d in log:
            if p == PLAY_CONTAINER_CONTENT:
                r2 = Reader(d)
                if r2.varint() == sync_id:
                    r2.varint()
                    return [read_slot(r2) for _ in range(r2.varint())]
        return None

    pump(c, st, w, biomes, ctx, lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    pump(c, st, w, biomes, ctx, lambda: w.health is not None, 'health')
    c.send(SB_CHANGE_GAME_MODE, varint(1))
    pump(c, st, w, biomes, ctx, lambda: w.mode == 1, 'creative')
    for name, (x, y, z, item, count, state) in saved.items():
        c.send(SB_CHAT_COMMAND, string('tp @s %d %d %d' % (x, y + 2, z)))
        pump(c, st, w, biomes, ctx, lambda: w.block(x, y, z) is not None, 'the chunk of the %s' % name, 30.0)
        settle(1.0)
        check(w.block(x, y, z) == state, 'the %s is state %s, was %s' % (name, w.block(x, y, z), state))
        del log[:]
        c.send(SB_USE_ON, varint(0) + block_pos(x, y, z) + varint(1) + struct.pack('>fff', 0.5, 1.0, 0.5) + bytes([0, 0]) +
               varint(900))
        pump(c, st, w, biomes, ctx, lambda: any(p == PLAY_OPEN_SCREEN for p, _ in log), 'an open screen packet')
        sync_id = Reader([d for p, d in log if p == PLAY_OPEN_SCREEN][0]).varint()
        pump(c, st, w, biomes, ctx, lambda: window_content(sync_id) is not None, 'the window content')
        slots = window_content(sync_id)
        print('  %s after the restart: slot 0 = %s' % (name, (slots[0],)))
        check(slots[0] == (count, item), '%s slot 0 is %s, wanted %s' % (name, slots[0], (count, item)))
        c.send(SB_CONTAINER_CLOSE, varint(sync_id))
    st.hit('containers_persisted')


PLAY_RESPAWN = 80
ITEM_META_INDEX = 8


def world_session(c, st, w, biomes, ctx, args):
    """--world: the world systems over the wire. The bot must be an operator of level 4, on a COPY of a world.

    1. Survival: a dirt block is placed with /setblock and broken as a player would; an item entity must appear on the
       wire next to the block, carrying dirt (the drop: loot table, then `drop_stack`).
    2. A nether portal: an obsidian frame and its portal blocks are placed with /fill, the bot is put inside and stays for
       longer than the survival portal delay; the server must send a Respawn into the Nether, a position there at one
       eighth of the overworld coordinates, and chunks that hold a portal block (the one it found or built).
    3. Back in the world it joined, /time set night and a wait: mobs must be spawned in the chunks around, none of them
       within 24 blocks of the bot, which is where natural spawning puts them."""
    def wait(cond, what, seconds=10.0):
        pump(c, st, w, biomes, ctx, cond, what, seconds)

    def settle(seconds=0.6):
        end = time.time() + seconds
        while time.time() < end:
            try:
                pid, r = c.recv()
            except socket.timeout:
                continue
            one_packet(c, st, w, biomes, ctx, pid, r)

    def cmd(line):
        print('  /%s' % line, flush=True)
        c.send(SB_CHAT_COMMAND, string(line))

    spawned = []     # (entity id, type, x, y, z)
    respawns = []    # dimension names

    def tap(pid, data):
        r = Reader(data)
        if pid == PLAY_ADD_ENTITY:
            eid = r.varint()
            r.take(16)
            kind = r.varint()
            spawned.append((eid, kind, r.f64(), r.f64(), r.f64()))
        elif pid == PLAY_RESPAWN:
            r.varint()
            name = r.string()
            respawns.append(name)
            if name != 'minecraft:overworld':
                ctx['sections'], w.min_y = 16, 0
            else:
                ctx['sections'], w.min_y = DEFAULT_SECTIONS, -64
            w.chunks.clear()
            w.overrides.clear()
            w.pos = None
    ctx['tap'] = tap

    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 60.0)
    wait(lambda: w.health is not None, 'a health packet')
    home = w.pos
    print('  joined at %.2f %.2f %.2f' % home)
    # Survival, so a break is a real break and the portal takes its delay.
    cmd('gamemode survival')
    wait(lambda: w.mode == 0, 'survival mode')
    st.hit('world_survival')
    x, y, z = int(home[0] // 1), int(home[1] // 1), int(home[2] // 1)

    # 1. The drop.
    bx, by, bz = x + 3, y, z
    dirt = BLOCK_TABLE['by_name']['dirt']
    cmd('setblock %d %d %d minecraft:dirt' % (bx, by, bz))
    wait(lambda: w.block(bx, by, bz) == dirt['default_state_id'], 'the dirt block', 15.0)
    st.hit('dirt_placed')
    settle(0.5)
    before = len(spawned)
    meta_before = len(META_LOG)
    seq = 31
    c.send(SB_ACTION, varint(0) + block_pos(bx, by, bz) + bytes([1]) + varint(seq))
    # The server counts the progress itself; a client that has seen it long enough says it is done.
    end = time.time() + 12.0
    stopped = False
    started = time.time()
    while time.time() < end and w.block(bx, by, bz) != 0:
        try:
            pid, r = c.recv()
        except socket.timeout:
            continue
        one_packet(c, st, w, biomes, ctx, pid, r)
        if time.time() > started + 2.0 and not stopped:
            seq += 1
            c.send(SB_ACTION, varint(2) + block_pos(bx, by, bz) + bytes([1]) + varint(seq))
            stopped = True
    check(w.block(bx, by, bz) == 0, 'the dirt block was not broken (state %r)' % w.block(bx, by, bz))
    st.hit('dirt_broken')
    wait(lambda: len(spawned) > before, 'an entity spawn for the drop', 10.0)
    settle(0.5)
    drops = [e for e in spawned[before:] if abs(e[2] - (bx + 0.5)) <= 0.75 and abs(e[4] - (bz + 0.5)) <= 0.75
             and abs(e[3] - (by + 0.5)) <= 1.0]
    print('  spawned after the break: %r' % (spawned[before:],))
    check(drops, 'no entity spawned within a block of the broken dirt')
    st.hit('drop_spawned')
    drop_ids = set(e[0] for e in drops)
    stacks = [m for m in META_LOG[meta_before:] if m[0] in drop_ids and m[1] == ITEM_META_INDEX]
    print('  drop stacks: %r' % (stacks,))
    check(stacks, 'the dropped entity carried no item stack metadata')
    dirt_item = 28   # minecraft:dirt in 774's item registry (blocks.json's item_id, 55, is 26.2's numbering)
    check(any(m[3] == (1, dirt_item) for m in stacks), 'the drop is not one dirt (item %d): %r' % (dirt_item, stacks))
    st.hit('drop_item')

    # 2. The nether portal, east of the bot, in the plane of constant z.
    px, py, pz = x + 8, y, z + 6
    cmd('fill %d %d %d %d %d %d minecraft:air' % (px - 1, py - 1, pz - 1, px + 2, py + 4, pz + 1))
    settle(0.8)
    cmd('fill %d %d %d %d %d %d minecraft:obsidian hollow' % (px - 1, py - 1, pz, px + 2, py + 3, pz))
    settle(0.8)
    cmd('fill %d %d %d %d %d %d minecraft:nether_portal' % (px, py, pz, px + 1, py + 2, pz))
    # blocks.json is 26.2's numbering and the wire is 774's, so the portal is known by the state the server sent for it.
    wait(lambda: w.block(px, py, pz) not in (None, 0), 'the portal blocks', 15.0)
    settle(1.0)
    portal_state = w.block(px, py, pz)
    print('  chat: %r' % (w.chat[-3:],))
    check(all(w.block(px + dx, py + dy, pz) == portal_state for dx in (0, 1) for dy in (0, 1, 2)),
          'the portal broke up: %r' % ([w.block(px + dx, py + dy, pz) for dx in (0, 1) for dy in (0, 1, 2)],))
    st.hit('portal_built')
    nether_target = (px + 1.0, py, pz + 0.5)
    cmd('tp @s %.1f %.1f %.1f' % nether_target)
    wait(lambda: w.pos is not None and abs(w.pos[0] - nether_target[0]) < 0.5, 'the teleport into the portal', 10.0)
    st.hit('portal_entered')
    # Survival's delay is 80 ticks; the nether chunks are generated meanwhile.
    wait(lambda: 'minecraft:the_nether' in respawns, 'a Respawn into the Nether', 240.0)
    print('  respawns: %r' % (respawns,))
    st.hit('nether_respawn')
    wait(lambda: w.pos is not None, 'a position in the Nether', 60.0)
    nx, ny, nz = w.pos
    print('  in the Nether at %.2f %.2f %.2f (the portal was at %d %d %d)' % (nx, ny, nz, px, py, pz))
    check(abs(nx - px / 8.0) <= 40 and abs(nz - pz / 8.0) <= 40, 'not at one eighth of the overworld coordinates')
    st.hit('nether_position')

    def portal_near():
        fx, fy, fz = int(nx // 1), int(ny // 1), int(nz // 1)
        for dx in range(-6, 7):
            for dy in range(-4, 6):
                for dz in range(-6, 7):
                    if w.block(fx + dx, fy + dy, fz + dz) == portal_state:
                        return True
        return False
    wait(portal_near, 'a nether portal block near the arrival', 120.0)
    st.hit('nether_portal_found')

    # 3. Night, and what spawns. Back home first: the Nether has its own mobs.
    cmd('tp @s %.1f %.1f %.1f' % (home[0], home[1], home[2]))
    mark = len(spawned)
    cmd('time set night')
    st.hit('night_set')
    wait(lambda: len([e for e in spawned[mark:] if e[1] != 0]) > 0, 'mobs to spawn at night', 120.0)
    mobs = spawned[mark:]
    print('  spawned at night: %d entities, types %s' % (len(mobs), sorted(set(e[1] for e in mobs))))
    for eid, kind, mx, my, mz in mobs:
        d2 = (mx - w.pos[0]) ** 2 + (mz - w.pos[2]) ** 2
        print('    entity %d type %d at %.1f %.1f %.1f (%.1f blocks)' % (eid, kind, mx, my, mz, d2 ** 0.5))
    st.hit('mobs_spawned')


PLAY_COMBAT_KILL = 66


def player_session(c, st, w, biomes, ctx, args):
    """--player: the player systems over the wire. The bot must be an operator of level 4, on a COPY of a world.

    1. A mob hits the player: a zombie is summoned on the bot, in survival at night, and the health packets must show the
       health fall below full (damage through `LivingEntity::damage`, armour and hurt cooldown included).
    2. Hunger drains: `/effect give @s hunger` and the food level in the health packets must fall (`HungerManager::tick`).
    3. Death, then respawn: a forced spawn point is set a few blocks away, the bot carries 64 stone, and is sent below the
       world. Health must reach nothing, a `CCombatDeath` must arrive, a stack must drop where it died, and a client
       command 0 must bring health back and a position at the spawn point (`calculate_respawn_point`).
    4. `/fill` takes block-state syntax: stairs facing east and facing west differ, a nether portal frame filled with
       `nether_portal[axis=x]` holds portal blocks, and a bad property answers with a proper error.
    5. An entity visible after join: a cow is summoned and recorded in --save; --player-verify joins again and must be
       told about it at once (`send_entities_to`)."""
    def wait(cond, what, seconds=10.0):
        pump(c, st, w, biomes, ctx, cond, what, seconds)

    def settle(seconds=0.6):
        end = time.time() + seconds
        while time.time() < end:
            try:
                pid, r = c.recv()
            except socket.timeout:
                continue
            one_packet(c, st, w, biomes, ctx, pid, r)

    def cmd(line):
        print('  /%s' % line, flush=True)
        c.send(SB_CHAT_COMMAND, string(line))

    spawned = []   # (entity id, type, x, y, z)
    deaths = []    # entity ids of the CCombatDeath packets
    respawns = []
    moves = {}     # entity id -> relative move packets seen
    where = {}     # entity id -> [x, y, z] kept from its spawn and its relative moves

    def tap(pid, data):
        r = Reader(data)
        if pid == PLAY_ADD_ENTITY:
            eid = r.varint()
            r.take(16)
            kind = r.varint()
            spawned.append((eid, kind, r.f64(), r.f64(), r.f64()))
            where[eid] = [spawned[-1][2], spawned[-1][3], spawned[-1][4]]
        elif pid == PLAY_COMBAT_KILL:
            deaths.append(r.varint())
        elif pid == PLAY_RESPAWN:
            respawns.append(len(respawns))
        elif pid in (PLAY_MOVE_POS, PLAY_MOVE_POS_ROT):
            eid = r.varint()
            moves[eid] = moves.get(eid, 0) + 1
            at = where.get(eid)
            if at is not None:   # relative moves are 1/4096 of a block
                at[0] += r.i16() / 4096.0
                at[1] += r.i16() / 4096.0
                at[2] += r.i16() / 4096.0
    ctx['tap'] = tap

    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 60.0)
    wait(lambda: w.health is not None, 'a health packet')
    home = w.pos
    x, y, z = int(home[0] // 1), int(home[1] // 1), int(home[2] // 1)
    print('  joined at %.2f %.2f %.2f' % home)
    cmd('gamemode survival')
    wait(lambda: w.mode == 0, 'survival mode')
    cmd('difficulty normal')
    cmd('time set night')
    settle(0.8)
    print('  said: %r' % (w.chat[-4:],))

    # 5 (first half). A cow, recorded for the second connection.
    mark = len(spawned)
    cmd('summon minecraft:cow %d %d %d' % (x + 4, y, z))
    def near(spawn_x, spawn_z, since):
        return [e for e in spawned[since:] if abs(e[2] - (spawn_x + 0.5)) <= 3.0 and abs(e[4] - (spawn_z + 0.5)) <= 3.0]
    wait(lambda: near(x + 4, z, mark), 'the cow to be spawned on the wire', 15.0)
    cow = near(x + 4, z, mark)[0]
    print('  cow: entity %d type %d at %.1f %.1f %.1f' % cow)
    ctx['player_state'] = dict(kind=cow[1], x=cow[2], y=cow[3], z=cow[4])
    if args.save:
        with open(args.save, 'w') as f:
            json.dump(ctx['player_state'], f)
    st.hit('cow_summoned')

    # 1. A mob hits the player.
    settle(0.5)
    wait(lambda: w.health[0] >= 19.5, 'full health first')
    mark = len(spawned)
    cmd('summon minecraft:zombie %d %d %d' % (x, y, z))
    wait(lambda: near(x, z, mark), 'the zombie to be spawned on the wire', 15.0)
    zombie = near(x, z, mark)[0]
    print('  zombie: entity %d type %d at %.1f %.1f %.1f, health %.1f' % (zombie + (w.health[0],)))
    mob_hit = True
    try:
        wait(lambda: w.health[0] < 20.0, 'the zombie to hurt the bot', 30.0)
        print('  health after the hit: %.1f' % w.health[0])
        st.hit('mob_hit')
    except Fail:
        print('  the zombie moved %d times (move packets for entity %d); health %r' % (moves.get(zombie[0], 0), zombie[0], w.health))
        print('  the cow (entity %d) moved %d times' % (cow[0], moves.get(cow[0], 0)))
        mob_hit = False   # reported at the end: the other steps still run
    cmd('kill @e[type=zombie]')
    settle(1.0)
    # With real mob AI the night brings real hostile mobs: the rest of the scenario must not be eaten by them.
    cmd('gamerule spawn_mobs false')
    cmd('time set day')
    settle(0.5)
    # The same damage without the mob: `/damage` goes through `damage_with_context` of the player (armour, hurt cooldown).
    before = w.health[0]
    cmd('damage @s 3 minecraft:generic')
    wait(lambda: w.health[0] < before, 'the damage command to hurt the bot', 10.0)
    print('  health %.1f -> %.1f' % (before, w.health[0]))
    check(abs((before - w.health[0]) - 3.0) < 0.6, 'damage 3 changed health by %.2f' % (before - w.health[0]))
    st.hit('damage_dealt')

    # 2. Hunger.
    food0 = w.health[1]
    print('  food %d saturation %.1f' % (food0, w.health[2]))
    cmd('effect give @s minecraft:hunger 30 255')
    wait(lambda: w.health[1] < food0, 'the food level to fall', 40.0)
    print('  food fell to %d' % w.health[1])
    st.hit('hunger_drained')
    cmd('effect clear @s')
    settle(0.5)

    # 1b. Mob AI over the wire: the cow wanders off by itself, and a pig follows the carrot the bot holds.
    cow_start = (cow[2], cow[4])
    def cow_walked():
        at = where[cow[0]]
        return ((at[0] - cow_start[0]) ** 2 + (at[2] - cow_start[1]) ** 2) ** 0.5
    wait(lambda: cow_walked() > 1.0, 'the cow to wander', 60.0)
    print('  the cow wandered %.1f blocks (%d move packets)' % (cow_walked(), moves.get(cow[0], 0)))
    st.hit('cow_wandered')


    # 4. /fill with block states.
    fx, fy, fz = x + 8, y + 3, z + 8
    cmd('fill %d %d %d %d %d %d minecraft:air' % (fx - 1, fy - 1, fz - 1, fx + 6, fy + 6, fz + 2))
    settle(0.8)
    at = len(w.chat)
    cmd('fill %d %d %d %d %d %d minecraft:oak_stairs[facing=east,half=top]' % (fx, fy, fz + 1, fx, fy, fz + 1))
    cmd('fill %d %d %d %d %d %d minecraft:oak_stairs[facing=west,half=top]' % (fx + 2, fy, fz + 1, fx + 2, fy, fz + 1))
    wait(lambda: w.block(fx, fy, fz + 1) not in (None, 0) and w.block(fx + 2, fy, fz + 1) not in (None, 0), 'both stairs', 15.0)
    check(w.block(fx, fy, fz + 1) != w.block(fx + 2, fy, fz + 1),
          'east and west stairs are the same state: %r' % w.block(fx, fy, fz + 1))
    check(not any('argument.block' in said or 'Unknown block' in said for said in w.chat[at:]),
          'the stairs were refused: %r' % w.chat[at:])
    st.hit('fill_stairs_states')
    cmd('fill %d %d %d %d %d %d minecraft:obsidian hollow' % (fx + 3, fy, fz, fx + 6, fy + 4, fz))
    settle(0.8)
    cmd('fill %d %d %d %d %d %d minecraft:nether_portal[axis=x]' % (fx + 4, fy + 1, fz, fx + 5, fy + 3, fz))
    wait(lambda: w.block(fx + 4, fy + 1, fz) not in (None, 0), 'the portal blocks', 15.0)
    settle(1.0)
    portal = w.block(fx + 4, fy + 1, fz)
    check(portal not in (None, 0) and w.block(fx + 5, fy + 3, fz) == portal, 'the portal broke up: %r' % portal)
    check(not any('argument.block.id.invalid' in said for said in w.chat[at:]),
          'nether_portal[axis=x] was refused: %r' % w.chat[at:])
    st.hit('fill_portal_state')
    at = len(w.chat)
    cmd('fill %d %d %d %d %d %d minecraft:oak_stairs[facing=sideways]' % (fx, fy + 4, fz, fx, fy + 4, fz))
    wait(lambda: len(w.chat) > at, 'the bad property error')
    print('  said: %r' % w.chat[at:])
    check(any('argument.block.property.invalid' in said or 'does not accept' in said for said in w.chat[at:]),
          'no property error: %r' % w.chat[at:])
    st.hit('fill_bad_property')

    # 3. Death, then respawn at a forced spawn point.
    cmd('give @s minecraft:stone 64')
    sp = (x + 5, y, z - 5)
    cmd('spawnpoint @s %d %d %d' % sp)
    settle(1.0)
    mark = len(spawned)
    deaths_before = len(deaths)
    cmd('tp @s %d -200 %d' % (x, z))
    wait(lambda: len(deaths) > deaths_before, 'the death screen (CCombatDeath)', 40.0)
    wait(lambda: w.health[0] <= 0.0, 'health to fall to nothing', 10.0)
    print('  dead, health %.1f' % w.health[0])
    st.hit('player_died')
    settle(1.0)
    drops = [e for e in spawned[mark:] if abs(e[2] - x) <= 3.0 and abs(e[4] - z) <= 3.0]
    print('  entities where it died: %r' % (drops,))
    check(drops, 'nothing dropped where the player died')
    st.hit('death_drops')
    w.pos = None
    c.send(SB_CLIENT_COMMAND, varint(0))
    wait(lambda: w.health[0] > 0.0, 'the respawn', 30.0)
    wait(lambda: w.pos is not None, 'a position after the respawn', 60.0)
    print('  respawned, health %.1f at %.2f %.2f %.2f' % ((w.health[0],) + w.pos))
    check(abs(w.pos[0] - (sp[0] + 0.5)) <= 1.5 and abs(w.pos[2] - (sp[2] + 0.5)) <= 1.5,
          'respawned at %r, the spawn point is %r' % (w.pos, sp))
    st.hit('player_respawned')
    check(len(respawns) >= 1, 'no Respawn packet')
    st.hit('respawn_point_used')

    # 6. A pig follows the carrot the bot holds (last: it leaves a carrot in the inventory and pigs round the bot).
    bx, by, bz = int(w.pos[0] // 1), int(w.pos[1] // 1), int(w.pos[2] // 1)
    # Pigs run TemptGoal only for the carrot in the SELECTED slot, and the hotbar already holds other things (the stone and
    # the rest of the earlier stages): pick the slot the /give changed, not the first one that is not empty.
    before = list(w.window0[36:45]) if w.window0 is not None else [(0, 0)] * 9
    cmd('give @s minecraft:carrot 4')
    wait(lambda: w.window0 is not None and any(tuple(w.window0[36 + i]) != tuple(before[i]) and w.window0[36 + i][0] > 0
                                                for i in range(9)), 'the carrot in the hotbar', 10.0)
    hand = next(i for i in range(9) if tuple(w.window0[36 + i]) != tuple(before[i]) and w.window0[36 + i][0] > 0)
    c.send(SB_CARRIED, struct.pack('>h', hand))   # the pigs look at the selected slot
    print('  carrot in hotbar slot %d, hotbar now %r' % (hand, [tuple(x) for x in w.window0[36:45]]))
    settle(0.8)
    pigs = []
    for dx, dz in ((-4, 0), (0, 6), (7, 0)):   # three directions: the ground round the spawn is not flat everywhere
        mark = len(spawned)
        cmd('summon minecraft:pig %d %d %d' % (bx + dx, by, bz + dz))
        wait(lambda: near(bx + dx, bz + dz, mark), 'a pig to be spawned on the wire', 15.0)
        pigs.append(near(bx + dx, bz + dz, mark)[0])
    def pig_distance(pig):
        at = where[pig[0]]
        return ((at[0] - w.pos[0]) ** 2 + (at[2] - w.pos[2]) ** 2) ** 0.5
    start_distances = [pig_distance(p) for p in pigs]
    print('  pigs %r at distances %r, carrot in the hand' % ([p[0] for p in pigs], ['%.1f' % d for d in start_distances]))
    wait(lambda: any(pig_distance(p) < 3.0 and d > 3.5 for p, d in zip(pigs, start_distances)), 'a pig to come to the carrot', 40.0)
    print('  the pigs followed the carrot: %r -> %r blocks' % (['%.1f' % d for d in start_distances],
                                                               ['%.1f' % pig_distance(p) for p in pigs]))
    st.hit('pig_followed')
    cmd('kill @e[type=pig]')
    settle(0.5)
    check(mob_hit, 'the zombie never hurt the bot (the rest of the scenario ran)')


def player_verify_session(c, st, w, biomes, ctx, args):
    """--player-verify FILE: join again; the cow summoned by --player must be spawned on the wire straight away."""
    with open(args.player_verify) as f:
        want = json.load(f)
    spawned = []

    def tap(pid, data):
        r = Reader(data)
        if pid == PLAY_ADD_ENTITY:
            eid = r.varint()
            r.take(16)
            kind = r.varint()
            spawned.append((eid, kind, r.f64(), r.f64(), r.f64()))
    ctx['tap'] = tap
    pump(c, st, w, biomes, ctx, lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 60.0)
    def cows_near():
        return [e for e in spawned if e[1] == want['kind'] and abs(e[2] - want['x']) <= 16 and abs(e[4] - want['z']) <= 16]
    pump(c, st, w, biomes, ctx, lambda: cows_near(), 'the cow after joining', 20.0)
    cows = [e for e in spawned if e[1] == want['kind']]
    print('  spawned at join: %r' % (cows,))
    near = [e for e in cows if abs(e[2] - want['x']) <= 16 and abs(e[4] - want['z']) <= 16]
    check(near, 'no cow near %r among %r' % (want, cows))
    st.hit('entity_after_join')


def watch_session(c, st, w, biomes, ctx, args):
    """--watch: another client's play as this one is told about it."""
    counts = ctx['counts']
    pump(c, st, w, biomes, ctx, lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    print('WATCHING', flush=True)
    pump(c, st, w, biomes, ctx, lambda: PLAY_ADD_ENTITY in counts, 'the other player to appear', 40.0)
    st.hit('other_appeared')
    pump(c, st, w, biomes, ctx, lambda: PLAY_MOVE_POS in counts or PLAY_MOVE_POS_ROT in counts, 'the other player to move', 30.0)
    pump(c, st, w, biomes, ctx, lambda: PLAY_ROTATE_HEAD in counts, 'the head to turn', 30.0)
    st.hit('other_moved')
    pump(c, st, w, biomes, ctx, lambda: PLAY_ANIMATE in counts, 'a swing', 30.0)
    st.hit('other_swung')
    pump(c, st, w, biomes, ctx, lambda: 0 in w.overrides.values(), 'a block to go', 30.0)
    st.hit('other_block_change')
    pump(c, st, w, biomes, ctx, lambda: any('hello from the bot' in said for said in w.chat), 'the other player to chat', 30.0)
    st.hit('other_chat')
    pump(c, st, w, biomes, ctx, lambda: PLAY_REMOVE_ENTITIES in counts, 'the other player to leave', 60.0)
    st.hit('other_left')


def run(args):
    extra = []
    if args.play:
        extra = Stages.PLAY_NAMES
    elif args.verify:
        extra = Stages.VERIFY_NAMES
    if args.far_chunk:
        extra = list(extra) + Stages.FAR_NAMES
    if args.watch:
        extra = list(extra) + Stages.WATCH_NAMES
    if args.commands:
        extra = list(extra) + Stages.COMMAND_NAMES
    if args.commands2:
        extra = list(extra) + Stages.COMMANDS2_NAMES
    if args.commands3:
        extra = list(extra) + Stages.COMMANDS3_NAMES
    if args.scoreboard:
        extra = list(extra) + Stages.SCOREBOARD_NAMES
    if args.commands_verify:
        extra = list(extra) + Stages.COMMAND_VERIFY_NAMES
    if args.blocks or args.blocks_verify or args.world or args.containers or args.containers_verify or args.c2 or args.c2_verify or args.c1 or args.c1_verify or args.last or args.partsb:
        load_block_table(args.assets)
    if args.world:
        extra = list(extra) + Stages.WORLD_NAMES
    if args.player:
        extra = list(extra) + Stages.PLAYER_NAMES
    if args.player_verify:
        extra = list(extra) + Stages.PLAYER_VERIFY_NAMES
    if args.blocks:
        extra = list(extra) + Stages.BLOCKS_NAMES
    if args.blocks_verify:
        extra = list(extra) + Stages.BLOCKS_VERIFY_NAMES
    if args.c2:
        extra = list(extra) + Stages.C2_NAMES
    if args.wasm_plugin:
        extra = list(extra) + Stages.PLUGIN_NAMES
    if args.plugmgr:
        extra = list(extra) + Stages.PLUGMGR_NAMES
    if args.playa:
        extra = list(extra) + (Stages.PLAYA_LISTEN_NAMES if args.playa == 'listen' else Stages.PLAYA_NAMES)
    if args.c2_verify:
        extra = list(extra) + Stages.C2_VERIFY_NAMES
    if args.partsb:
        only = [n for n in os.environ.get('PARTSB_ONLY', '').split(',') if n]
        for group, names in Stages.PARTSB_NAMES.items():
            if group in only if only else group in ('pearl', 'bed', 'villager', 'dragon'):
                extra = list(extra) + names
    if args.containers:
        extra = list(extra) + Stages.CONTAINERS_NAMES
    if args.containers_verify:
        extra = list(extra) + Stages.CONTAINERS_VERIFY_NAMES
    st = Stages(extra)
    status = status_ping(args.host, args.port)
    print('status: %s' % json.dumps(status))
    check(status['version']['protocol'] == PROTOCOL, 'status reports protocol %r' % status['version']['protocol'])
    st.hit('status')
    online_before = status['players']['online']

    fake = None
    if args.online_offline:
        fake = FakeSession(args.session_port)
    expect_id = None
    expect_props = 0
    address = args.host
    if args.proxy == 'bungee':
        props = json.dumps([{'name': 'textures', 'value': 'dmFsdWU=', 'signature': 'c2ln'}])
        address = '\x00'.join([args.host, args.proxy_ip, args.proxy_uuid, props])
        expect_id = bytes.fromhex(args.proxy_uuid)
        expect_props = 1
    c = Conn(args.host, args.port)
    c.send(0, handshake(address, args.port, 2))
    uuid = bytes(16)
    c.send(SB_LOGIN_HELLO, string(args.name) + uuid)
    print('offline uuid of %s: %s' % (args.name, offline_uuid(args.name).hex()))
    st.hit('login_start')

    # Login
    while True:
        pid, r = c.recv()
        print('login  packet 0x%02x (%d bytes)' % (pid, r.left()), flush=True)
        if pid == LOGIN_DISCONNECT:
            reason = r.string()
            if args.expect_refusal and args.expect_refusal in reason:
                print('  refused as expected: %s' % reason)
                c.close()
                if fake is not None:
                    print('  session server was asked %d times: %s' % (len(fake.seen), fake.seen))
                    fake.stop()
                st.names = list(st.reached)
                return st
            raise Fail('login refused: %s' % reason)
        if pid == LOGIN_HELLO:
            check(args.encrypt or args.online_offline, 'the server asked for encryption')
            r.string()
            der = r.take(r.varint())
            token = r.take(r.varint())
            authenticate = r.boolean()
            check(r.left() == 0, 'encryption request: %d bytes left over' % r.left())
            check(len(token) == 4, 'a verify token of %d bytes' % len(token))
            n, e = rsa_public_from_spki(der)
            print('  encryption: a %d-bit key, exponent %d, online=%s' % (n.bit_length(), e, authenticate))
            check(n.bit_length() == 1024 and e == 65537, 'not the key vanilla makes')
            secret = os.urandom(16)
            if args.online_offline:
                check(authenticate, 'an online server must ask for authentication')
                if not args.no_register:
                    fake.expected[args.name] = mc_digest(b'', secret, der)
                expect_id = bytes.fromhex(FakeSession.PROFILE_ID)
                expect_props = 1
            first = rsa_encrypt(n, e, secret)
            second = rsa_encrypt(n, e, token)
            c.send(SB_LOGIN_KEY, varint(len(first)) + first + varint(len(second)) + second)
            c.enc, c.dec = AesCfb8(secret), AesCfb8(secret)
            continue
        if pid == 4 and args.proxy == 'velocity':
            message_id = r.varint()
            channel = r.string()
            data = r.take(r.left())
            check(channel == 'velocity:player_info', 'plugin request channel %r' % channel)
            check(data == b'\x04', 'the highest forwarding version asked for: %r' % data)
            print('  velocity asked for forwarding up to version 4')
            body = varint(4) + string(args.proxy_ip) + bytes.fromhex(args.proxy_uuid) + string(args.name) + varint(1) \
                + string('textures') + string('dmFsdWU=') + b'\x01' + string('c2ln')
            sig = hmac.new(args.proxy_secret.encode(), body, hashlib.sha256).digest()
            c.send(2, varint(message_id) + b'\x01' + sig + body)
            expect_id = bytes.fromhex(args.proxy_uuid)
            expect_props = 1
            continue
        if pid == LOGIN_COMPRESSION:
            c.threshold = r.varint()
            check(r.left() == 0, 'trailing bytes in set compression')
            st.hit('compression')
            continue
        if pid == LOGIN_FINISHED:
            got_id = r.take(16)
            name = r.string()
            check(name == args.name, 'login success for %r' % name)
            if expect_id is not None:
                check(got_id == expect_id, 'login success for uuid %s, wanted %s' % (got_id.hex(), expect_id.hex()))
            props = 0
            for _ in range(r.varint()):
                r.string()
                r.string()
                if r.boolean():
                    r.string()
                props += 1
            if expect_id is not None:
                check(props == expect_props, 'login success carried %d properties, wanted %d' % (props, expect_props))
            if fake is not None:
                check(len(fake.seen) >= 1, 'the session server was never asked')
                print('  session server was asked: %s' % fake.seen[-1])
            check(r.left() == 0, 'trailing bytes in login success: %d' % r.left())
            st.hit('login_success')
            c.send(SB_LOGIN_ACK)
            break
        raise Fail('unexpected login packet 0x%02x' % pid)

    # Configuration
    c.send(SB_CFG_INFO, client_information())
    registries = {}
    while True:
        pid, r = c.recv()
        print('config packet 0x%02x (%d bytes)' % (pid, r.left()), flush=True)
        if pid == CFG_KNOWN_PACKS:
            packs = [(r.string(), r.string(), r.string()) for _ in range(r.varint())]
            print('  known packs offered: %s' % packs)
            # As aoughwl.mcnet does: we hold none, so the server must send every registry's data.
            c.send(SB_CFG_KNOWN_PACKS, varint(0))
            st.hit('known_packs')
        elif pid == CFG_REGISTRY:
            name = r.string()
            entries = []
            for _ in range(r.varint()):
                key = r.string()
                check(r.boolean(), 'registry %s entry %s has no data, though we claimed no packs' % (name, key))
                skip_network_nbt(r)
                entries.append(key)
            check(r.left() == 0, 'registry %s: %d bytes left over' % (name, r.left()))
            registries[name] = entries
            print('  registry %s: %d entries' % (name, len(entries)))
            st.hit('registry_data')
        elif pid == CFG_TAGS:
            for _ in range(r.varint()):
                reg = r.string()
                n = r.varint()
                for _ in range(n):
                    r.string()
                    for _ in range(r.varint()):
                        r.varint()
                print('  tags for %s: %d' % (reg, n))
            check(r.left() == 0, 'tags: %d bytes left over' % r.left())
            st.hit('tags')
        elif pid == CFG_FINISH:
            check(r.left() == 0, 'trailing bytes in finish configuration')
            st.hit('finish_configuration')
            c.send(SB_CFG_FINISH)
            break
        elif pid == CFG_KEEP_ALIVE:
            c.send(SB_CFG_KEEP_ALIVE, r.take(8))
        elif pid == CFG_DISCONNECT:
            raise Fail('disconnected in configuration: %r' % r.take(r.left()))
        elif pid in (CFG_PAYLOAD, CFG_FEATURES, CFG_LINKS):
            r.take(r.left())
        else:
            print('  (not read)')

    for needed in ('minecraft:worldgen/biome', 'minecraft:dimension_type'):
        check(registries.get(needed), 'no %s registry was sent' % needed)
    biomes = len(registries['minecraft:worldgen/biome'])
    dims = registries['minecraft:dimension_type']

    # Play
    c.sock.settimeout(1.0)
    start = time.time()
    deadline = start + args.seconds
    w = World()
    ctx = dict(sections=DEFAULT_SECTIONS, counts={}, keep_alives=0, chunks=0, chunk_parsed=False, loaded_sent=False, start=start, dims=dims)
    try:
        if args.encrypt:
            pump(c, st, w, biomes, ctx, lambda: w.pos is not None, 'a position, through the cipher', 120.0)
            print('  in play through the cipher, at %.2f %.2f %.2f' % w.pos)
            c.close()
            st.names = list(st.reached)
            return st
        if args.dimension:
            pump(c, st, w, biomes, ctx, lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 120.0)
            print('  world %s, at %.2f %.2f %.2f' % (ctx['world'], w.pos[0], w.pos[1], w.pos[2]))
            check(ctx['world'] == args.dimension, 'joined %s, wanted %s' % (ctx['world'], args.dimension))
        if args.play:
            play_session(c, st, w, biomes, ctx, args)
        elif args.verify:
            verify_session(c, st, w, biomes, ctx, args)
        if args.plugin:
            plugin_session(c, st, w, biomes, ctx, args)
        if args.commands:
            commands_session(c, st, w, biomes, ctx, args)
        if args.commands2:
            commands2_session(c, st, w, biomes, ctx, args)
        if args.commands3:
            commands3_session(c, st, w, biomes, ctx, args)
        if args.scoreboard:
            scoreboard_session(c, st, w, biomes, ctx, args)
        elif args.commands_verify:
            commands_verify_session(c, st, w, biomes, ctx, args)
        if args.world:
            world_session(c, st, w, biomes, ctx, args)
        if args.blocks:
            blocks_session(c, st, w, biomes, ctx, args)
        elif args.blocks_verify:
            blocks_verify_session(c, st, w, biomes, ctx, args)
        if args.playa:
            import mcbot_playa
            mcbot_playa.playa_session(sys.modules[__name__], c, st, w, biomes, ctx, args)
        if args.wasm_plugin:
            import mcbot_plugin
            mcbot_plugin.plugin_session(sys.modules[__name__], c, st, w, biomes, ctx, args)
        if args.plugmgr:
            import mcbot_plugmgr
            mcbot_plugmgr.plugmgr_session(sys.modules[__name__], c, st, w, biomes, ctx, args)
        if args.c2 or args.c2_verify:
            import mcbot_c2
            if args.c2:
                mcbot_c2.c2_session(sys.modules[__name__], c, st, w, biomes, ctx, args)
            else:
                mcbot_c2.c2_verify_session(sys.modules[__name__], c, st, w, biomes, ctx, args)
        if args.partsb:
            import mcbot_partsb
            mcbot_partsb.partsb_session(sys.modules[__name__], c, st, w, biomes, ctx, args)
        if args.last:
            import mcbot_last
            mcbot_last.last_session(sys.modules[__name__], c, st, w, biomes, ctx, args)
        if args.c1 or args.c1_verify:
            import mcbot_c1
            if args.c1:
                mcbot_c1.c1_session(sys.modules[__name__], c, st, w, biomes, ctx, args)
            else:
                mcbot_c1.c1_verify_session(sys.modules[__name__], c, st, w, biomes, ctx, args)
        if args.containers:
            containers_session(c, st, w, biomes, ctx, args)
        elif args.containers_verify:
            containers_verify_session(c, st, w, biomes, ctx, args)
        if args.player:
            player_session(c, st, w, biomes, ctx, args)
        elif args.player_verify:
            player_verify_session(c, st, w, biomes, ctx, args)
        if args.far_chunk:
            far_session(c, st, w, biomes, ctx, args)
        if args.watch:
            watch_session(c, st, w, biomes, ctx, args)
        while time.time() < deadline:
            try:
                pid, r = c.recv()
            except socket.timeout:
                continue
            one_packet(c, st, w, biomes, ctx, pid, r)
    except (ConnectionError, OSError) as e:
        raise Fail('connection lost %.1fs into play: %s' % (time.time() - start, e))
    counts, chunks, keep_alives = ctx['counts'], ctx['chunks'], ctx['keep_alives']
    if args.c1 and args.save:
        with open(args.save, 'w') as f:
            json.dump(ctx['c1_state'], f)
    if args.containers and args.save:
        with open(args.save, 'w') as f:
            json.dump(ctx['containers_state'], f)
    if args.c2 and args.save:
        with open(args.save, 'w') as f:
            json.dump(ctx['c2_state'], f)
    if args.blocks and args.save:
        with open(args.save, 'w') as f:
            json.dump(ctx['blocks_state'], f)
    if args.player and args.save:
        with open(args.save, 'w') as f:
            json.dump(ctx['player_state'], f)
    if args.play and args.save:
        with open(args.save, 'w') as f:
            json.dump(dict(placed_at=ctx['placed_at'], walked_to=ctx['walked_to']), f)
    print('packets in play, by id: %s' % ', '.join('0x%02x x%d' % (k, counts[k]) for k in sorted(counts)))
    print('%d chunks parsed, %d keep-alives answered' % (chunks, keep_alives))
    check(keep_alives >= 1, 'no keep-alive in %d seconds' % args.seconds)
    st.hit('stayed_up')
    c.close()
    st.hit('clean_disconnect')
    # The server removes a player as soon as it sees the socket close (vanilla does too), so a short poll is enough; a
    # count that stays up is a leave-path bug (the player is only dropped by the keep-alive timeout), not slowness.
    leave_start = time.time()
    while True:
        after = status_ping(args.host, args.port)
        if after['players']['online'] <= online_before or time.time() - leave_start > 3.0:
            break
        time.sleep(0.05)
    print('status after disconnect: online=%d (after %.2fs)' % (after['players']['online'], time.time() - leave_start))
    check(after['players']['online'] <= online_before, 'the server still counts the player: %r' % after['players'])
    if args.relogin:
        # A second login under the same name straight away: it must not be refused as a duplicate.
        again = Conn(args.host, args.port)
        again.send(0, handshake(args.host, args.port, 2))
        again.send(SB_LOGIN_HELLO, string(args.name) + bytes(16))
        pid, r = again.recv()
        reason = r.string() if pid == LOGIN_DISCONNECT else ''
        again.close()
        check(pid != LOGIN_DISCONNECT, 'the immediate re-login was refused: %s' % reason)
        print('  immediate re-login accepted (packet 0x%02x)' % pid)
        time.sleep(0.3)
    st.hit('server_alive_after')
    return st


# --- Network services: RCON, query, status, proxies and online mode ---------------------------------------------------------

def mc_digest(*parts):
    """Minecraft's signed-hex SHA-1, as the session server's serverId."""
    h = hashlib.sha1()
    for part in parts:
        h.update(part)
    n = int.from_bytes(h.digest(), 'big', signed=True)
    return format(n, 'x')


class FakeSession:
    """Stands in for sessionserver.mojang.com on a local port: answers hasJoined with a canned profile for exactly the
    (username, serverId) pairs the bot registered, 204 for any other. `seen` holds every request path."""
    PROFILE_ID = '069a79f444e94726a5befca90e38aaf5'

    def __init__(self, port):
        import threading
        from http.server import BaseHTTPRequestHandler, HTTPServer
        from urllib.parse import urlparse, parse_qs
        outer = self
        self.expected = {}
        self.seen = []
        self.texture = base64.b64encode(json.dumps({
            'timestamp': 0, 'profileId': self.PROFILE_ID, 'profileName': 'x',
            'textures': {'SKIN': {'url': 'http://textures.minecraft.net/texture/abc'}}}).encode()).decode()

        class H(BaseHTTPRequestHandler):
            def do_GET(self):
                u = urlparse(self.path)
                q = parse_qs(u.query)
                outer.seen.append(self.path)
                user = q.get('username', [''])[0]
                sid = q.get('serverId', [''])[0]
                if u.path != '/session/minecraft/hasJoined' or outer.expected.get(user) != sid:
                    self.send_response(204)
                    self.end_headers()
                    return
                body = json.dumps({'id': outer.PROFILE_ID, 'name': user,
                                   'properties': [{'name': 'textures', 'value': outer.texture, 'signature': 'c2ln'}]}).encode()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *a):
                pass

        self.httpd = HTTPServer(('127.0.0.1', port), H)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def stop(self):
        self.httpd.shutdown()


def rcon_packet(pid, ptype, body):
    data = struct.pack('<ii', pid, ptype) + body.encode() + b'\x00\x00'
    return struct.pack('<i', len(data)) + data


def rcon_read(sock):
    head = b''
    while len(head) < 4:
        chunk = sock.recv(4 - len(head))
        check(chunk, 'the RCON connection closed')
        head += chunk
    size = struct.unpack('<i', head)[0]
    check(10 <= size <= 4096, 'an RCON packet of size %d' % size)
    data = b''
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        check(chunk, 'the RCON connection closed mid-packet')
        data += chunk
    pid, ptype = struct.unpack('<ii', data[:8])
    check(data[-2:] == b'\x00\x00', 'an RCON packet without its two terminating zeros')
    return pid, ptype, data[8:-2].decode()


def rcon_session(args):
    """RCON: a wrong password is answered with id -1 and the connection closes; the right one is answered with the request
    id; a command is answered with type 0 output under its own id, and every command is answered."""
    host, port = args.host, args.rcon
    # Wrong password.
    s = socket.create_connection((host, port), timeout=10)
    s.sendall(rcon_packet(11, 3, 'definitely-wrong'))
    pid, ptype, body = rcon_read(s)
    check((pid, ptype) == (-1, 2), 'a wrong password was answered with id %d type %d' % (pid, ptype))
    print('RCON wrong password: refused with id -1')
    s.settimeout(5)
    check(s.recv(1) == b'', 'the connection stayed open after a wrong password')
    s.close()
    # A command before logging in is not answered, and not run.
    s = socket.create_connection((host, port), timeout=10)
    s.sendall(rcon_packet(12, 2, args.rcon_command))
    s.settimeout(1.0)
    try:
        got = s.recv(1)
        check(got == b'', 'a command before auth was answered')
    except socket.timeout:
        pass
    s.close()
    # The right password, then commands, one packet and several in one write.
    s = socket.create_connection((host, port), timeout=10)
    s.sendall(rcon_packet(21, 3, args.rcon_password))
    pid, ptype, body = rcon_read(s)
    check((pid, ptype, body) == (21, 2, ''), 'auth answered with %r' % ((pid, ptype, body),))
    print('RCON auth ok')
    s.sendall(rcon_packet(22, 2, args.rcon_command))
    pid, ptype, body = rcon_read(s)
    check(pid == 22 and ptype == 0, 'a command answered with id %d type %d' % (pid, ptype))
    check(body != '', 'the command printed nothing')
    print('RCON %r -> %r' % (args.rcon_command, body))
    wire = rcon_packet(23, 2, args.rcon_command) + rcon_packet(24, 2, args.rcon_command)
    s.sendall(wire[:7])
    time.sleep(0.2)
    s.sendall(wire[7:])
    first = rcon_read(s)
    check(first[0] == 23 and first[1] == 0, 'split write: first answer %r' % (first,))
    # Further output lines of the first command come before the second command's answer.
    answers = [first]
    while answers[-1][0] != 24:
        answers.append(rcon_read(s))
    check(answers[-1][0] == 24, 'the second command was never answered')
    print('RCON split and pipelined writes ok (%d answer packets)' % len(answers))
    # A command that prints nothing still gets an answer.
    if args.rcon_silent:
        s.sendall(rcon_packet(25, 2, args.rcon_silent))
        pid, ptype, body = rcon_read(s)
        check(pid == 25 and ptype == 0, 'a silent command was answered with id %d' % pid)
        print('RCON silent command answered with an empty packet')
    # An invalid length closes the connection.
    s.sendall(struct.pack('<i', 4))
    s.settimeout(5)
    check(s.recv(1) == b'', 'an invalid packet length did not close the connection')
    s.close()
    print('RCON invalid length closes the connection')
    st = Stages([])
    st.names = ['rcon_ok']
    st.hit('rcon_ok')
    return st


def query_stat(s, addr, session, token, full):
    pkt = struct.pack('>HBii', 0xFEFD, 0, session, token) + (b'\x00\x00\x00\x00' if full else b'')
    s.sendto(pkt, addr)
    data, _ = s.recvfrom(4096)
    return data


def query_session(args):
    """Query (GameSpy4 over UDP): handshake for a challenge token, then the basic and the full status."""
    addr = (args.host, args.query)
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(5)
    session = 0x01020304
    s.sendto(struct.pack('>HBi', 0xFEFD, 9, session), addr)
    data, _ = s.recvfrom(4096)
    check(data[0] == 9 and struct.unpack('>i', data[1:5])[0] == session and data[-1] == 0, 'handshake answer %r' % data)
    token = int(data[5:-1].decode())
    check(0 < token <= 0x7FFFFFFF, 'challenge token %d' % token)
    print('query handshake: token %d' % token)
    # A status with a token that was not handed out is not answered.
    s.settimeout(1.5)
    try:
        query_stat(s, addr, session, token + 1, False)
        raise Fail('a status with a made-up token was answered')
    except socket.timeout:
        pass
    s.settimeout(5)
    data = query_stat(s, addr, session, token, False)
    check(data[0] == 0 and struct.unpack('>i', data[1:5])[0] == session, 'basic status header %r' % data[:5])
    fields = data[5:].split(b'\x00')
    motd, gametype, world, online, maxp = [f.decode() for f in fields[:5]]
    skip = 5 + sum(len(f) + 1 for f in fields[:5])
    port_le = struct.unpack('<H', data[skip:skip + 2])[0]
    ip = data[skip + 2:].split(b'\x00')[0].decode()
    print('query basic: motd=%r gametype=%s map=%s players=%s/%s port=%d ip=%s' % (motd, gametype, world, online, maxp, port_le, ip))
    check(gametype == 'SMP' and world != '' and online.isdigit() and maxp.isdigit(), 'basic status fields')
    if args.query_motd is not None:
        check(motd == args.query_motd, 'motd %r, wanted %r' % (motd, args.query_motd))
    data = query_stat(s, addr, session, token, True)
    check(data[0] == 0 and data[5:16] == bytes([0x73, 0x70, 0x6C, 0x69, 0x74, 0x6E, 0x75, 0x6D, 0, 0x80, 0]), 'full status padding')
    tail = data[16:]
    marker = bytes([0x00, 0x01, 0x70, 0x6C, 0x61, 0x79, 0x65, 0x72, 0x5F, 0x00, 0x00])
    at = tail.index(marker)
    kv = tail[:at].split(b'\x00')
    pairs = {kv[i].decode(): kv[i + 1].decode() for i in range(0, len(kv) - 1, 2)}
    players = [p.decode() for p in tail[at + len(marker):].split(b'\x00') if p]
    print('query full: %s players=%s' % (pairs, players))
    check(pairs['gametype'] == 'SMP' and pairs['game_id'] == 'MINECRAFT', 'full status keys')
    check(pairs['numplayers'] == online and pairs['maxplayers'] == maxp and pairs['hostport'] == str(port_le), 'full and basic disagree')
    check(len(players) <= 4 and (args.query_players is None or players == args.query_players.split(',')), 'players %r' % players)
    # Garbage and a wrong magic are not answered.
    s.sendto(b'\xDE\xAD\x09\x00\x00\x00\x01', addr)
    s.settimeout(1.5)
    try:
        s.recvfrom(4096)
        raise Fail('a packet with the wrong magic was answered')
    except socket.timeout:
        pass
    print('query ignores a wrong magic')
    s.close()
    st = Stages([])
    st.names = ['query_ok']
    st.hit('query_ok')
    return st


def favicon_check(status):
    """A status response's favicon: a data URL of a 64x64 PNG."""
    icon = status.get('favicon')
    check(isinstance(icon, str) and icon.startswith('data:image/png;base64,'), 'no favicon in the status: %r' % (icon if not icon else icon[:30]))
    png = base64.b64decode(icon.split(',', 1)[1])
    check(png[:8] == b'\x89PNG\r\n\x1a\n', 'the favicon is not a PNG')
    w, h = struct.unpack('>II', png[16:24])
    check((w, h) == (64, 64), 'the favicon is %dx%d' % (w, h))
    return len(png)


def status_session(args):
    """The status's favicon, and its player sample while a bot is in the game: a thread pings after the bot has joined."""
    import threading
    box = {}

    def later():
        time.sleep(args.status_delay)
        try:
            box['status'] = status_ping(args.host, args.port)
        except Exception as e:  # reported after the join
            box['error'] = e
    t = threading.Thread(target=later)
    t.start()
    st = run(args)
    t.join()
    check('error' not in box, 'the status ping failed: %r' % box.get('error'))
    status = box['status']
    print('status while %s is online: %s' % (args.name, json.dumps(status)[:200]))
    size = favicon_check(status)
    print('favicon: a 64x64 PNG of %d bytes' % size)
    sample = status['players'].get('sample', [])
    names = [p['name'] for p in sample]
    check(args.name in names, 'the sample %r lacks %s' % (names, args.name))
    entry = [p for p in sample if p['name'] == args.name][0]
    check(entry['id'].replace('-', '') == offline_uuid(args.name).hex() or args.online_offline or args.proxy,
          'the sample id %r is not the offline uuid' % entry['id'])
    check(status['players']['online'] >= 1, 'online count %r' % status['players'])
    st.names = list(st.names) + ['status_favicon', 'status_sample']
    st.hit('status_favicon')
    st.hit('status_sample')
    return st


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--host', default='127.0.0.1')
    ap.add_argument('--port', type=int, required=True)
    ap.add_argument('--name', default='McBot')
    ap.add_argument('--seconds', type=int, default=30)
    ap.add_argument('--play', action='store_true', help='play the script in the module docstring')
    ap.add_argument('--op', action='store_true', help="the server's data/ops.json lists this bot")
    ap.add_argument('--save', help='where --play writes what --verify checks')
    ap.add_argument('--verify', help='a file from --save: check it is all still there')
    ap.add_argument('--commands', action='store_true', help='run real commands as an operator; see commands_session')
    ap.add_argument('--commands2', action='store_true', help='run /clone, /place, /item, /spreadplayers, /rotate, /fillbiome, /loot, /ride and /spectate; see commands2_session')
    ap.add_argument('--commands3', action='store_true', help='run /help, /pumpkin, /attribute, /advancement and /dialog; see commands3_session')
    ap.add_argument('--plugin', type=int, nargs=3, metavar=('X', 'Y', 'Z'), help='a plugin has set this block and shown the bot a boss bar; see plugin_session')
    ap.add_argument('--plugin-state', type=int, default=None, help='with --plugin: the state id the block must have on the wire')
    ap.add_argument('--scoreboard', action='store_true', help='run the scoreboard, team, bossbar, border, tick and data commands; see scoreboard_session')
    ap.add_argument('--commands-verify', help='a file from --commands --save: check what the commands did is still there')
    ap.add_argument('--world', action='store_true', help='drops, a nether portal and night spawns as an operator; see world_session')
    ap.add_argument('--blocks', action='store_true', help='play with blocks as an operator; see blocks_session')
    ap.add_argument('--blocks-verify', help='a file from --blocks --save: check the door, lamp and sand are still there')
    ap.add_argument('--assets', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'ref', 'pumpkin-1.21.11', 'assets', 'blocks.json'), help='blocks.json of the pinned upstream, for --blocks')
    ap.add_argument('--playa', choices=['act', 'listen'], help='play packets as an operator: shift-click, drag split, tab completion and chat (act), or hear the actor chat (listen); see mcbot_playa.py')
    ap.add_argument('--wasm-plugin', action='store_true', help='a wasm plugin welcomes the player and cancels chat starting with x; see mcbot_plugin.py')
    ap.add_argument('--plugmgr', action='store_true', help='the plugin manager at run time: /plugin list, load, unload, reload; see mcbot_plugmgr.py')
    ap.add_argument('--c2', action='store_true', help='a sign with text, a bed slept in and a piston push; see mcbot_c2.py')
    ap.add_argument('--c2-verify', help='a file from --c2 --save: the sign, bed and piston are still there')
    ap.add_argument('--last', action='store_true', help='command blocks, a cauldron, a flower pot and a dragon egg; see mcbot_last.py')
    ap.add_argument('--partsb', action='store_true', help='pearl cooldown, bed night skip, villager trading window and the dragon; see mcbot_partsb.py')
    ap.add_argument('--c1', action='store_true', help='a furnace smelts over the wire; see mcbot_c1.py')
    ap.add_argument('--c1-verify', help='a file from --c1 --save: the smelted output is still in the furnace')
    ap.add_argument('--containers', action='store_true', help='open a chest, a barrel and a trapped chest and fill them; see containers_session')
    ap.add_argument('--containers-verify', help='a file from --containers --save: check the stacks are still in the containers')
    ap.add_argument('--player', action='store_true', help='mob damage, hunger, death and respawn, /fill states, a cow; see player_session')
    ap.add_argument('--player-verify', help='a file from --player --save: the cow must be spawned on joining')
    ap.add_argument('--watch', action='store_true', help='watch another player play')
    ap.add_argument('--encrypt', action='store_true', help='answer the encryption request; stops once in play')
    ap.add_argument('--expect-refusal', help='wants a login disconnect containing this')
    ap.add_argument('--dimension', help='wants CLogin to name this dimension')
    ap.add_argument('--far-chunk', type=lambda v: tuple(int(n) for n in v.split(',')), help='X,Z: walk so far this must generate')
    ap.add_argument('--rcon', type=int, help='RCON port: test auth and commands against it; see rcon_session')
    ap.add_argument('--rcon-password', default='secret')
    ap.add_argument('--rcon-command', default='list')
    ap.add_argument('--rcon-silent', help='a command that prints nothing, which must still be answered')
    ap.add_argument('--query', type=int, help='query (UDP) port: handshake, basic and full status; see query_session')
    ap.add_argument('--query-motd', help='the motd the query must report')
    ap.add_argument('--query-players', help='comma separated names the full status must list')
    ap.add_argument('--status', action='store_true', help='join, and check the status holds a favicon and the player sample')
    ap.add_argument('--status-delay', type=float, default=6.0, help='seconds after the start that --status pings')
    ap.add_argument('--relogin', action='store_true', help='after the disconnect, log in again under the same name at once: the server must not call it a duplicate')
    ap.add_argument('--online-offline', action='store_true', help='an online-mode server whose session server is --session-port here')
    ap.add_argument('--session-port', type=int, help='the port the server was told to reach the session server on')
    ap.add_argument('--no-register', action='store_true', help='with --online-offline: do not tell the session server we joined')
    ap.add_argument('--proxy', choices=['bungee', 'velocity'], help='log in as a proxy forwards a player; see run')
    ap.add_argument('--proxy-secret', default='sekret')
    ap.add_argument('--proxy-uuid', default='069a79f444e94726a5befca90e38aaf5')
    ap.add_argument('--proxy-ip', default='203.0.113.9')
    args = ap.parse_args()
    st = Stages()
    try:
        if args.rcon:
            st = rcon_session(args)
        elif args.query:
            st = query_session(args)
        elif args.status:
            st = status_session(args)
        else:
            st = run(args)
    except (Fail, OSError, ValueError, KeyError, zlib.error, json.JSONDecodeError) as e:
        print('FAIL: %s: %s' % (type(e).__name__, e))
        return 1
    missing = st.missing()
    if missing:
        print('FAIL: stages not reached: %s' % missing)
        return 1
    print('OK: every stage reached')
    return 0


if __name__ == '__main__':
    sys.exit(main())
