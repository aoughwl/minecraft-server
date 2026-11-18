#!/usr/bin/env python3
"""Compares two saved worlds (tools/run_world_hash.sh output) block-state by block-state.

  python tools/hash_world.py <worldA> <worldB> [--show N]

Per dimension it reads every region file, decodes each chunk's NBT, and compares only what is comparable: the chunks present in BOTH worlds
(the set of generated/saved chunks depends on timing: more chunk workers generate more of the view distance before the save), by the per-chunk
digest of (section y, block palette names+properties expanded per block, biome palette, block entities with their coordinates and NBT).
Masked: region header timestamps (bytes 4096..8191), chunk LastUpdate/InhabitedTime, light arrays, Heightmaps, entity UUIDs. It also hashes the
raw region files (timestamps masked) to show that byte equality is not expected, and prints the level.dat fields that differ.
"""
import gzip, hashlib, os, struct, sys, zlib


def read_nbt(buf):
    pos = [0]

    def take(n):
        s = buf[pos[0]:pos[0] + n]
        pos[0] += n
        return s

    def payload(t):
        if t == 1: return struct.unpack('>b', take(1))[0]
        if t == 2: return struct.unpack('>h', take(2))[0]
        if t == 3: return struct.unpack('>i', take(4))[0]
        if t == 4: return struct.unpack('>q', take(8))[0]
        if t == 5: return struct.unpack('>f', take(4))[0]
        if t == 6: return struct.unpack('>d', take(8))[0]
        if t == 7:
            n = struct.unpack('>i', take(4))[0]
            return ('bytes', bytes(take(n)))
        if t == 8:
            n = struct.unpack('>H', take(2))[0]
            return take(n).decode('utf-8', 'replace')
        if t == 9:
            it = take(1)[0]
            n = struct.unpack('>i', take(4))[0]
            return [payload(it) for _ in range(n)]
        if t == 10:
            d = {}
            while True:
                tt = take(1)[0]
                if tt == 0:
                    return d
                n = struct.unpack('>H', take(2))[0]
                name = take(n).decode('utf-8', 'replace')
                d[name] = payload(tt)
        if t == 11:
            n = struct.unpack('>i', take(4))[0]
            return list(struct.unpack('>%di' % n, take(4 * n)))
        if t == 12:
            n = struct.unpack('>i', take(4))[0]
            return list(struct.unpack('>%dq' % n, take(8 * n)))
        raise ValueError('nbt tag %d' % t)
    t = take(1)[0]
    n = struct.unpack('>H', take(2))[0]
    take(n)
    return payload(t)


def lz4_block(src, size):
    out = bytearray()
    i = 0
    while i < len(src):
        tok = src[i]
        i += 1
        lit = tok >> 4
        if lit == 15:
            while True:
                b = src[i]
                i += 1
                lit += b
                if b != 255:
                    break
        out += src[i:i + lit]
        i += lit
        if i >= len(src):
            break
        off = src[i] | src[i + 1] << 8
        i += 2
        ml = tok & 15
        if ml == 15:
            while True:
                b = src[i]
                i += 1
                ml += b
                if b != 255:
                    break
        ml += 4
        for _ in range(ml):
            out.append(out[-off])
    return bytes(out[:size]) if size else bytes(out)


def lz4_java_stream(body):
    """The LZ4BlockOutputStream framing that region type 4 uses: 'LZ4Block', token, compressed len, original len, checksum, data."""
    out = bytearray()
    i = 0
    while i + 21 <= len(body) and body[i:i + 8] == b'LZ4Block':
        method = body[i + 8] & 0xF0
        comp, orig = struct.unpack('<II', body[i + 9:i + 17])
        i += 21
        blk = body[i:i + comp]
        i += comp
        if orig == 0:
            break
        out += blk if method == 0x10 else lz4_block(blk, orig)
    return bytes(out)


def chunks_of(path):
    data = open(path, 'rb').read()
    for i in range(1024):
        o = int.from_bytes(data[i * 4:i * 4 + 3], 'big')
        cnt = data[i * 4 + 3]
        if not o:
            continue
        raw = data[o * 4096:o * 4096 + 4096 * cnt]
        ln, ct = struct.unpack('>IB', raw[:5])
        body = raw[5:4 + ln]
        if ct == 2:
            nbt = zlib.decompress(body)
        elif ct == 1:
            nbt = gzip.decompress(body)
        elif ct == 3:
            nbt = body
        elif ct == 4:
            nbt = lz4_java_stream(body)
        else:
            nbt = None
        yield i, ct, nbt


SKIP = ('LastUpdate', 'InhabitedTime', 'Heightmaps', 'BlockLight', 'SkyLight', 'isLightOn', 'UUID', 'UUIDMost', 'UUIDLeast', 'Pos', 'Motion')


def strip(v):
    if isinstance(v, dict):
        return {k: strip(x) for k, x in sorted(v.items()) if k not in SKIP}
    if isinstance(v, list):
        return [strip(x) for x in v]
    return v


def block_digest(chunk):
    h = hashlib.sha256()
    secs = chunk.get('sections') or chunk.get('Level', {}).get('Sections') or []
    for s in sorted(secs, key=lambda s: s.get('Y', 0)):
        bs = s.get('block_states') or {}
        pal = bs.get('palette') or []
        names = [(p['Name'], tuple(sorted((p.get('Properties') or {}).items()))) for p in pal]
        data = bs.get('data')
        if data is None:
            cells = [0] * 4096
        else:
            bits = max(4, (len(names) - 1).bit_length())
            per = 64 // bits
            mask = (1 << bits) - 1
            cells = []
            for word in data:
                word &= (1 << 64) - 1
                for k in range(per):
                    cells.append((word >> (k * bits)) & mask)
            cells = cells[:4096]
        h.update(repr((s.get('Y'), [names[c] if c < len(names) else None for c in cells])).encode())
        b = s.get('biomes') or {}
        h.update(repr((b.get('palette'), b.get('data') is None)).encode())
    for be in sorted(chunk.get('block_entities') or [], key=lambda e: (e.get('x', 0), e.get('y', 0), e.get('z', 0))):
        h.update(repr(strip(be)).encode())
    return h.hexdigest()


def world_chunks(root, sub):
    out = {}
    raw = hashlib.sha256()
    d = os.path.join(root, sub)
    for f in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        if not f.endswith('.mca'):
            continue
        path = os.path.join(d, f)
        blob = open(path, 'rb').read()
        raw.update(blob[:4096] + blob[8192:])
        for i, ct, nbt in chunks_of(path):
            if nbt is None:
                out[(f, i)] = ('unreadable-compression-%d' % ct, '', {})
                continue
            ch = read_nbt(nbt)
            if not ch:
                raise SystemExit('empty chunk nbt in %s: the comparison would be vacuous' % path)
            out[(f, i)] = (block_digest(ch), hashlib.sha256(repr(strip(ch)).encode()).hexdigest(), ch)
    return out, raw.hexdigest()


# The det_world workload's edit volumes (tools/mcbot_scenarios.py): (label, dimension, x0, y0, z0, x1, y1, z1)
BOXES = [
    ('ow bedrock deck', 'region', 190, 149, 190, 230, 149, 230),
    ('ow stone box + air + roof', 'region', 192, 150, 192, 200, 155, 200),
    ('ow clone destination', 'region', 215, 150, 190, 223, 155, 198),
    ('ow cobble slab + hollow moss', 'region', 205, 150, 205, 215, 151, 215),
    ('ow glowstone/diamond tower', 'region', 220, 150, 220, 225, 160, 225),
    ('ow carve air + gold floor (terrain-dependent)', 'region', 140, 100, 140, 160, 110, 160),
    ('ow ore replace (terrain-dependent)', 'region', 100, 90, 100, 120, 95, 120),
    ('nether deck + obsidian + markers', 'DIM-1/region', 2, 150, 2, 20, 155, 20),
]


def cell_reader(root, sub):
    cache = {}
    regions = {}

    def chunk(cx, cz):
        key = (cx >> 5, cz >> 5)
        if key not in regions:
            path = os.path.join(root, sub, 'r.%d.%d.mca' % key)
            regions[key] = {i: (ct, nbt) for i, ct, nbt in chunks_of(path)} if os.path.exists(path) else {}
        ent = regions[key].get((cz & 31) * 32 + (cx & 31))
        if ent is None or ent[1] is None:
            return None
        if (cx, cz) not in cache:
            cache[(cx, cz)] = read_nbt(ent[1])
        return cache[(cx, cz)]

    def secs(ch):
        out = {}
        for s in ch.get('sections') or []:
            bs = s.get('block_states') or {}
            pal = bs.get('palette') or []
            names = [(p['Name'], tuple(sorted((p.get('Properties') or {}).items()))) for p in pal]
            data = bs.get('data')
            if data is None:
                cells = [0] * 4096
            else:
                bits = max(4, (len(names) - 1).bit_length())
                per = 64 // bits
                mask = (1 << bits) - 1
                cells = []
                for word in data:
                    word &= (1 << 64) - 1
                    for k in range(per):
                        cells.append((word >> (k * bits)) & mask)
            out[s.get('Y')] = (names, cells)
        return out
    sec_cache = {}

    def at(x, y, z):
        ch = chunk(x >> 4, z >> 4)
        if ch is None:
            return 'nochunk'
        if str(ch.get('Status')) != 'minecraft:full':
            return 'notfull'
        key = (x >> 4, z >> 4)
        if key not in sec_cache:
            sec_cache[key] = secs(ch)
        s = sec_cache[key].get(y >> 4)
        if s is None:
            return ('minecraft:air', ())
        names, cells = s
        c = cells[((y & 15) << 8) | ((z & 15) << 4) | (x & 15)] if len(cells) > 0 else 0
        return names[c] if c < len(names) else None
    return at


def compare_cells(a, b):
    ra = {}
    rb = {}
    total_bad = 0
    for label, sub, x0, y0, z0, x1, y1, z1 in BOXES:
        ra.setdefault(sub, cell_reader(a, sub))
        rb.setdefault(sub, cell_reader(b, sub))
        n = eq = skip = 0
        bad = []
        for y in range(y0, y1 + 1):
            for z in range(z0, z1 + 1):
                for x in range(x0, x1 + 1):
                    va, vb = ra[sub](x, y, z), rb[sub](x, y, z)
                    if isinstance(va, str) or isinstance(vb, str):
                        skip += 1
                        continue
                    n += 1
                    if va == vb:
                        eq += 1
                    elif len(bad) < 3:
                        bad.append(((x, y, z), va[0] if va else va, vb[0] if vb else vb))
        total_bad += n - eq
        print('  %-48s cells compared %6d, identical %6d, differing %5d, skipped (chunk missing/not full in one) %5d %s' % (label, n, eq, n - eq, skip, bad))
    print('CELLS: %d differing cells in the edited volumes' % total_bad)


def main():
    a, b = sys.argv[1], sys.argv[2]
    if '--cells' in sys.argv:
        compare_cells(a, b)
        return
    show = int(sys.argv[sys.argv.index('--show') + 1]) if '--show' in sys.argv else 5
    worst = 0
    for label, sub in (('overworld region', 'region'), ('nether region', 'DIM-1/region')):
        ca, ra = world_chunks(a, sub)
        cb, rb = world_chunks(b, sub)
        def status(c, k):
            return str(c[k][2].get('Status'))
        stat_ab = {}
        for k in set(ca) & set(cb):
            stat_ab[(status(ca, k), status(cb, k))] = stat_ab.get((status(ca, k), status(cb, k)), 0) + 1
        print('  chunk Status pairs (A, B) among common chunks: %r' % sorted(stat_ab.items()))
        # a chunk saved at an earlier generation stage in one run (features/light not finished when the world was saved) is not comparable
        both = sorted(k for k in set(ca) & set(cb) if status(ca, k) == status(cb, k) == 'minecraft:full')
        if '--edited-only' in sys.argv:
            # only the chunks the det_world workload edits: overworld x/z 100..230 (chunks 6..14), nether x/z 0..20 (chunks 0..1)
            lo, hi = (6, 14) if sub == 'region' else (0, 1)

            def at(k):
                parts = k[0].split('.')
                return int(parts[1]) * 32 + k[1] % 32, int(parts[2]) * 32 + k[1] // 32
            both = [k for k in both if lo <= at(k)[0] <= hi and lo <= at(k)[1] <= hi]
        blocks_diff = [k for k in both if ca[k][0] != cb[k][0]]
        full_diff = [k for k in both if ca[k][1] != cb[k][1]]
        print('%s: chunks A %d, B %d, comparable (Status full in both) %d, only-A %d, only-B %d' % (label, len(ca), len(cb), len(both), len(set(ca) - set(cb)), len(set(cb) - set(ca))))
        print('  common chunks with identical block states+block entities: %d / %d; differing: %d' % (len(both) - len(blocks_diff), len(both), len(blocks_diff)))
        print('  common chunks identical after stripping clocks/light/heightmaps (whole NBT): %d / %d' % (len(both) - len(full_diff), len(both)))
        print('  raw region bytes (timestamps masked) equal: %s' % (ra == rb))
        for k in blocks_diff[:show]:
            print('   differs (blocks):', k)
        for k in [k for k in full_diff if k not in blocks_diff][:show]:
            x, y = ca[k][2], cb[k][2]
            ks = sorted(k2 for k2 in set(x) | set(y) if strip({k2: x.get(k2)}) != strip({k2: y.get(k2)}))
            print('   differs (other fields only):', k, ks)
        worst += len(blocks_diff)
    try:
        la = read_nbt(gzip.open(os.path.join(a, 'level.dat')).read())
        lb = read_nbt(gzip.open(os.path.join(b, 'level.dat')).read())
        da, db = la.get('Data', la), lb.get('Data', lb)
        print('level.dat fields that differ:')
        for k in sorted(set(da) | set(db)):
            if da.get(k) != db.get(k):
                print('   %-24s A=%s  B=%s' % (k, str(da.get(k))[:70], str(db.get(k))[:70]))
    except Exception as e:
        print('level.dat unreadable:', e)
    print('RESULT: %d common chunks differ in block state' % worst)


if __name__ == '__main__':
    main()
