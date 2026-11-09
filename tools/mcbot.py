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

Ids and layouts are protocol 774's, the ones aoughwl.mcnet (the game client's decoder) reads.
"""
import argparse
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
SB_LOGIN_HELLO, SB_LOGIN_ACK = 0, 3
SB_TELEPORT, SB_BATCH, SB_KEEP_ALIVE, SB_LOADED = 0, 10, 27, 43


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


class Conn:
    def __init__(self, host, port, timeout=15.0):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self.buf = bytearray()
        self.threshold = -1

    def send(self, pid, body=b''):
        payload = varint(pid) + body
        if self.threshold >= 0:
            if len(payload) >= self.threshold:
                packed = zlib.compress(payload)
                payload = varint(len(payload)) + packed
            else:
                payload = varint(0) + payload
        self.sock.sendall(varint(len(payload)) + payload)

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
            self.buf += chunk
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


def read_container(r, entries, max_indirect, limit, what):
    """One paletted container, 774's: no length prefix on the data array. Returns (bits, palette, kind, distinct ids)."""
    bits = r.u8()
    if bits == 0:
        value = r.varint()
        check(0 <= value < limit, '%s single value %d out of range (limit %d)' % (what, value, limit))
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
            produced += 1
    return bits, [], 'direct', seen


def bitcount_mask(r):
    n = r.varint()
    check(0 <= n <= 64, 'a light mask of %d longs' % n)
    words = [r.i64() & 0xFFFFFFFFFFFFFFFF for _ in range(n)]
    return words, sum(bin(w).count('1') for w in words)


def parse_chunk(r, sections, biome_limit, verbose):
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
        _, _, kind, ids = read_container(s, 4096, 8, BLOCK_STATES_1_21_11, 'chunk %d,%d section %d blocks' % (x, z, i))
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
    check(not sky_words or (sky_words[0] >> sections) & 1, 'chunk %d,%d: top section has no sky light' % (x, z))
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
        check(kind == 0, 'metadata type %d: this bot only reads bytes' % kind)
        r.u8()


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
}


def client_information():
    # locale, view distance, chat mode, chat colors, skin parts, main hand, text filtering, server listing,
    # particle status
    return string('en_us') + bytes([8]) + varint(0) + bytes([1]) + bytes([0x7F]) + varint(1) + bytes([0, 1]) + varint(0)


class Stages:
    NAMES = ['status', 'login_start', 'compression', 'login_success', 'known_packs', 'registry_data', 'tags',
             'finish_configuration', 'play_login', 'teleport', 'chunk_batch', 'chunk_parsed', 'keep_alive',
             'stayed_up', 'clean_disconnect', 'server_alive_after']

    def __init__(self):
        self.reached = []

    def hit(self, name):
        assert name in self.NAMES
        if name not in self.reached:
            self.reached.append(name)
            print('STAGE %s' % name, flush=True)

    def missing(self):
        return [n for n in self.NAMES if n not in self.reached]


def run(args):
    st = Stages()
    status = status_ping(args.host, args.port)
    print('status: %s' % json.dumps(status))
    check(status['version']['protocol'] == PROTOCOL, 'status reports protocol %r' % status['version']['protocol'])
    st.hit('status')
    online_before = status['players']['online']

    c = Conn(args.host, args.port)
    c.send(0, handshake(args.host, args.port, 2))
    uuid = bytes(16)
    c.send(SB_LOGIN_HELLO, string(args.name) + uuid)
    st.hit('login_start')

    # Login
    while True:
        pid, r = c.recv()
        print('login  packet 0x%02x (%d bytes)' % (pid, r.left()), flush=True)
        if pid == LOGIN_DISCONNECT:
            raise Fail('login refused: %s' % r.string())
        if pid == LOGIN_HELLO:
            raise Fail('the server asked for encryption')
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
    counts = {}
    sections = DEFAULT_SECTIONS
    keep_alives = 0
    chunks = 0
    chunk_parsed = False
    loaded_sent = False
    while time.time() < deadline:
        try:
            pid, r = c.recv()
        except socket.timeout:
            continue
        except (ConnectionError, OSError) as e:
            raise Fail('connection lost %.1fs into play: %s' % (time.time() - start, e))
        counts[pid] = counts.get(pid, 0) + 1
        if counts[pid] <= 3 or pid in (PLAY_KEEP_ALIVE, PLAY_DISCONNECT):
            print('play   packet 0x%02x (%d bytes)' % (pid, r.left()), flush=True)
        if pid in EXACT_PLAY:
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
            check(0 <= dim < len(dims), 'CLogin dimension %d of %d' % (dim, len(dims)))
            print('  CLogin entity=%d hardcore=%s worlds=%s max=%d view=%d sim=%d dim=%d(%s) world=%s seed=%d mode=%d '
                  'prev=%d portal=%d sea=%d secure=%s' % (entity, hardcore, worlds, maxp, view, sim, dim, dims[dim],
                                                          world, seed, mode, prev, portal, sea, secure))
            st.hit('play_login')
        elif pid == PLAY_POSITION:
            tid = r.varint()
            x, y, z = r.f64(), r.f64(), r.f64()
            r.take(24 + 8)
            flags = r.i32()
            check(r.left() == 0, 'player position: %d bytes left over' % r.left())
            print('  teleport id=%d to %.2f %.2f %.2f flags=%d' % (tid, x, y, z, flags))
            c.send(SB_TELEPORT, varint(tid))
            st.hit('teleport')
        elif pid == PLAY_CHUNK:
            chunks += 1
            x, z = parse_chunk(r, sections, biomes, not chunk_parsed)
            chunk_parsed = True
            st.hit('chunk_parsed')
        elif pid == PLAY_BATCH_END:
            n = r.varint()
            c.send(SB_BATCH, struct.pack('>f', 64.0))
            st.hit('chunk_batch')
            if not loaded_sent and chunk_parsed:
                c.send(SB_LOADED)
                loaded_sent = True
        elif pid == PLAY_KEEP_ALIVE:
            token = r.i64()
            c.send(SB_KEEP_ALIVE, struct.pack('>q', token))
            keep_alives += 1
            print('  keep-alive %d answered at %.1fs' % (token, time.time() - start), flush=True)
            st.hit('keep_alive')
        elif pid == PLAY_DISCONNECT:
            raise Fail('kicked %.1fs into play: %r' % (time.time() - start, r.take(r.left())))
    print('packets in play, by id: %s' % ', '.join('0x%02x x%d' % (k, counts[k]) for k in sorted(counts)))
    print('%d chunks parsed, %d keep-alives answered' % (chunks, keep_alives))
    check(keep_alives >= 1, 'no keep-alive in %d seconds' % args.seconds)
    st.hit('stayed_up')
    c.close()
    st.hit('clean_disconnect')
    time.sleep(0.5)
    after = status_ping(args.host, args.port)
    print('status after disconnect: online=%d' % after['players']['online'])
    check(after['players']['online'] == online_before, 'the server still counts the player: %r' % after['players'])
    st.hit('server_alive_after')
    return st


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--host', default='127.0.0.1')
    ap.add_argument('--port', type=int, required=True)
    ap.add_argument('--name', default='McBot')
    ap.add_argument('--seconds', type=int, default=30)
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
