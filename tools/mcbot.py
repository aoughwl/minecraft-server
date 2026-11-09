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
import hashlib
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


def read_commands(r):
    for _ in range(r.varint()):
        flags = r.u8()
        check(flags & 3 == 0, 'only a root node is expected yet')
        for _ in range(r.varint()):
            r.varint()
    r.varint()


def read_metadata(r):
    r.varint()
    while True:
        index = r.u8()
        if index == 0xFF:
            return
        kind = r.varint()
        check(kind in (0, 20), 'metadata type %d: this bot only reads bytes and arms' % kind)
        if kind == 0:
            r.u8()
        else:
            r.varint()


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
        self.window0 = None     # 46 (count, item)
        self.state_id = 0
        self.cursor = (0, 0)
        self.acked = -1
        self.health = None
        self.chat = []
        self.pongs = []
        self.suggestions = []
        self.mode = None
        self.flying_allowed = None

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
    elif pid == PLAY_SUGGESTIONS:
        ident = r.varint()
        r.varint(), r.varint()
        n = r.varint()
        w.suggestions.append((ident, n))
        check(n == 0, 'suggestions without a dispatcher: %d' % n)
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
    counts[pid] = counts.get(pid, 0) + 1
    if counts[pid] <= 3 or pid in (PLAY_KEEP_ALIVE, PLAY_DISCONNECT):
        print('play   packet 0x%02x (%d bytes)' % (pid, r.left()), flush=True)
    if pid in EXACT_PLAY:
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
        r.take(24 + 8)
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
    st = Stages(extra)
    status = status_ping(args.host, args.port)
    print('status: %s' % json.dumps(status))
    check(status['version']['protocol'] == PROTOCOL, 'status reports protocol %r' % status['version']['protocol'])
    st.hit('status')
    online_before = status['players']['online']

    c = Conn(args.host, args.port)
    c.send(0, handshake(args.host, args.port, 2))
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
                st.names = list(st.reached)
                return st
            raise Fail('login refused: %s' % reason)
        if pid == LOGIN_HELLO:
            check(args.encrypt, 'the server asked for encryption')
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
            first = rsa_encrypt(n, e, secret)
            second = rsa_encrypt(n, e, token)
            c.send(SB_LOGIN_KEY, varint(len(first)) + first + varint(len(second)) + second)
            c.enc, c.dec = AesCfb8(secret), AesCfb8(secret)
            continue
        if pid == LOGIN_COMPRESSION:
            c.threshold = r.varint()
            check(r.left() == 0, 'trailing bytes in set compression')
            st.hit('compression')
            continue
        if pid == LOGIN_FINISHED:
            r.take(16)
            name = r.string()
            check(name == args.name, 'login success for %r' % name)
            for _ in range(r.varint()):
                r.string()
                r.string()
                if r.boolean():
                    r.string()
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
    if args.play and args.save:
        with open(args.save, 'w') as f:
            json.dump(dict(placed_at=ctx['placed_at'], walked_to=ctx['walked_to']), f)
    print('packets in play, by id: %s' % ', '.join('0x%02x x%d' % (k, counts[k]) for k in sorted(counts)))
    print('%d chunks parsed, %d keep-alives answered' % (chunks, keep_alives))
    check(keep_alives >= 1, 'no keep-alive in %d seconds' % args.seconds)
    st.hit('stayed_up')
    c.close()
    st.hit('clean_disconnect')
    time.sleep(0.5)
    after = status_ping(args.host, args.port)
    print('status after disconnect: online=%d' % after['players']['online'])
    check(after['players']['online'] <= online_before, 'the server still counts the player: %r' % after['players'])
    st.hit('server_alive_after')
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
    ap.add_argument('--watch', action='store_true', help='watch another player play')
    ap.add_argument('--encrypt', action='store_true', help='answer the encryption request; stops once in play')
    ap.add_argument('--expect-refusal', help='wants a login disconnect containing this')
    ap.add_argument('--dimension', help='wants CLogin to name this dimension')
    ap.add_argument('--far-chunk', type=lambda v: tuple(int(n) for n in v.split(',')), help='X,Z: walk so far this must generate')
    args = ap.parse_args()
    st = Stages()
    try:
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
