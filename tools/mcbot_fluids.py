"""Fluid scenarios of mcbot.py's --blocks --fluids: water and lava flow, over the wire, as an operator on a COPY of a world.

blocks_session hands in its helpers (`h`, a dict of closures) after the stage is built. Every scenario gets its own stone
channel, one wide with walls, so that the lengths asked of a flow are exact: water flows seven blocks from a source, lava
three (in the overworld). Port of what pumpkin/src/block/fluid/ does, seen from the client: block updates for the flow.
"""
import time


def run(m, st, args, h):
    cmd, wait, settle, name_at, state_at = h['cmd'], h['wait'], h['settle'], h['name_at'], h['state_at']
    check = m.check
    sx, fy, sz = h['stage']

    def channel(z, x0=-2, x1=14, walls=3):
        """A floor at fy, walls at z-1 and z+1, clear air above: the row at z from sx+x0 to sx+x1."""
        cmd('fill %d %d %d %d %d %d minecraft:air' % (sx + x0, fy + 1, z - 1, sx + x1, fy + 8, z + 1))
        cmd('fill %d %d %d %d %d %d minecraft:stone' % (sx + x0, fy, z - 1, sx + x1, fy, z + 1))
        cmd('fill %d %d %d %d %d %d minecraft:stone' % (sx + x0, fy + 1, z - 1, sx + x1, fy + walls, z - 1))
        cmd('fill %d %d %d %d %d %d minecraft:stone' % (sx + x0, fy + 1, z + 1, sx + x1, fy + walls, z + 1))
        cmd('fill %d %d %d %d %d %d minecraft:stone' % (sx + x0, fy + 1, z - 1, sx + x0, fy + walls, z + 1))
        cmd('fill %d %d %d %d %d %d minecraft:stone' % (sx + x1, fy + 1, z - 1, sx + x1, fy + walls, z + 1))
        settle(0.5)

    def place(x, y, z, what):
        cmd('setblock %d %d %d %s' % (x, y, z, what))

    # The channels sit south of the stage, beyond its 7 rows, 4 blocks apart.
    zs = [sz + 10 + 4 * i for i in range(8)]

    # --- 1. Flow length and levels: a source flows seven blocks and no further, one level less each.
    z = zs[0]
    channel(z)
    place(sx, fy + 1, z, 'minecraft:water')
    wait(lambda: name_at(sx, fy + 1, z) == 'water', 'the source')
    source_state = state_at(sx, fy + 1, z)
    settle(6.0)
    print('  flow row after 6s: %s' % [m.block_name(state_at(sx + i, fy + 1, z)) for i in range(0, 9)], flush=True)
    wait(lambda: name_at(sx + 7, fy + 1, z) == 'water', 'water 7 blocks from its source', 20.0)
    settle(2.0)
    row = [state_at(sx + i, fy + 1, z) for i in range(0, 9)]
    names = [m.block_name(s) for s in row]
    print('  flow: %s' % names, flush=True)
    check(names[:8] == ['water'] * 8, 'water is not in the first 8 cells: %r' % names)
    check(names[8] == 'air', 'the water went past 7 blocks: %r' % names)
    check(len(set(row[:8])) == 8, 'the 8 cells do not hold 8 different levels: %r' % row)
    check(row[0] == source_state, 'the source changed')
    st.hit('fluid_flow_length')

    # --- 2. Falling water: a source on a 3-high pillar falls to the floor and spreads there.
    z = zs[1]
    channel(z, walls=5)
    cmd('fill %d %d %d %d %d %d minecraft:stone' % (sx + 2, fy + 1, z, sx + 2, fy + 3, z))
    place(sx + 2, fy + 4, z, 'minecraft:water')
    wait(lambda: name_at(sx + 3, fy + 1, z) == 'water', 'water that fell to the floor', 20.0)
    settle(2.0)
    col = [m.block_name(state_at(sx + 3, fy + i, z)) for i in (1, 2, 3, 4)]
    print('  fall: column %s, floor beside %s' % (col, name_at(sx + 4, fy + 1, z)), flush=True)
    check(col == ['water'] * 4, 'the falling column is not all water: %r' % col)
    check(name_at(sx + 4, fy + 1, z) == 'water', 'the water that fell did not spread on the floor')
    st.hit('fluid_falls')

    # --- 3. Two sources with a gap between them: the gap becomes a source.
    z = zs[2]
    channel(z)
    place(sx + 1, fy + 1, z, 'minecraft:water')
    wait(lambda: name_at(sx + 1, fy + 1, z) == 'water', 'the first source')
    src = state_at(sx + 1, fy + 1, z)
    place(sx + 3, fy + 1, z, 'minecraft:water')
    wait(lambda: state_at(sx + 2, fy + 1, z) == src, 'the gap between two sources to become a source', 20.0)
    print('  infinite source: the gap is a source', flush=True)
    st.hit('fluid_infinite_source')

    # --- 4. Lava beside water: the lava source turns to obsidian.
    z = zs[3]
    channel(z)
    place(sx + 2, fy + 1, z, 'minecraft:lava')
    wait(lambda: name_at(sx + 2, fy + 1, z) == 'lava', 'a lava source')
    settle(1.0)
    place(sx + 3, fy + 1, z, 'minecraft:water')
    wait(lambda: name_at(sx + 2, fy + 1, z) == 'obsidian', 'the lava source to turn into obsidian', 20.0)
    print('  lava source beside water: obsidian', flush=True)
    st.hit('fluid_obsidian')

    # --- 5. Lava flows three blocks; water meeting its flow makes cobblestone.
    z = zs[4]
    channel(z)
    place(sx, fy + 1, z, 'minecraft:lava')
    wait(lambda: name_at(sx + 3, fy + 1, z) == 'lava', 'lava three blocks from its source', 30.0)
    settle(3.0)
    lava = [name_at(sx + i, fy + 1, z) for i in range(0, 6)]
    print('  lava flow: %s' % lava, flush=True)
    check(lava[:4] == ['lava'] * 4, 'lava did not flow 3 blocks: %r' % lava)
    check(lava[4] == 'air', 'lava flowed past 3 blocks: %r' % lava)
    place(sx + 5, fy + 1, z, 'minecraft:water')
    wait(lambda: 'cobblestone' in [name_at(sx + i, fy + 1, z) for i in range(3, 6)], 'cobblestone where water met flowing lava', 30.0)
    print('  water against flowing lava: %s' % [name_at(sx + i, fy + 1, z) for i in range(0, 7)], flush=True)
    st.hit('fluid_cobblestone')

    # --- 6. Waterlogging: a waterlogged slab is a source, and spreads.
    z = zs[5]
    channel(z)
    place(sx + 2, fy + 1, z, 'minecraft:oak_slab[waterlogged=true,type=bottom]')
    wait(lambda: name_at(sx + 2, fy + 1, z) == 'oak_slab', 'a waterlogged slab')
    wait(lambda: name_at(sx + 3, fy + 1, z) == 'water', 'water beside a waterlogged slab', 20.0)
    print('  waterlogged slab spread water to its neighbour', flush=True)
    st.hit('fluid_waterlogged')

    # --- 7. A sponge soaks the water around it.
    z = zs[6]
    channel(z)
    place(sx + 1, fy + 1, z, 'minecraft:water')
    wait(lambda: name_at(sx + 6, fy + 1, z) == 'water', 'a flow to soak', 20.0)
    settle(1.0)
    h['hold']('sponge')
    h['use_on'](sx + 6, fy, z, 1, (0.5, 1.0, 0.5))
    wait(lambda: name_at(sx + 6, fy + 1, z) == 'wet_sponge', 'the sponge to turn wet', 20.0)
    wait(lambda: name_at(sx + 5, fy + 1, z) == 'air', 'the water beside the sponge to go', 20.0)
    print('  sponge: wet, and the water around it gone', flush=True)
    st.hit('fluid_sponge')

    # --- 8. Buckets: a bucket is used, not placed: look straight down inside the channel, pour water, pick it up again.
    z = zs[7]
    channel(z)
    seq = [900]

    def use_item_down():
        import struct
        seq[0] += 1
        h['c'].send(m.SB_USE, m.varint(0) + m.varint(seq[0]) + struct.pack('>ff', 0.0, 90.0))
        settle(0.8)

    cmd('tp @s %.1f %d %.1f 0 90' % (sx + 2.5, fy + 1, z + 0.5))
    settle(1.0)
    h['hold']('water_bucket')
    use_item_down()
    wait(lambda: name_at(sx + 2, fy + 1, z) == 'water', 'water poured from a bucket', 20.0)
    wait(lambda: name_at(sx + 5, fy + 1, z) == 'water', 'the poured water to flow', 20.0)
    print('  bucket: poured, and flowing 3 blocks away', flush=True)
    st.hit('fluid_bucket_place')
    cmd('tp @s %.1f %d %.1f 0 90' % (sx + 2.5, fy + 3, z + 0.5))
    settle(1.0)
    h['hold']('bucket')
    use_item_down()
    wait(lambda: name_at(sx + 5, fy + 1, z) == 'air', 'the water to drain after the pick-up', 30.0)
    print('  bucket: picked the source up, the flow drained', flush=True)
    st.hit('fluid_bucket_pickup')
