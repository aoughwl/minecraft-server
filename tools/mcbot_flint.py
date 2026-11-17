"""Session for mcbot.py --flint: flint and steel and fire charges used on blocks (`use_item_on` -> the item's `useOn`).

The bot must be an operator of level 4 on a COPY of a world. FLINT_ONLY=fire,campfire,charge,creative,portal limits it.
  fire      survival: flint and steel on the top of a stone block -> minecraft:fire above it, the flint takes 1 damage
  campfire  survival: flint and steel on an unlit campfire -> the same campfire, lit (lit=false -> true)
  charge    survival: a fire charge on stone -> fire, the stack loses one
  creative  creative: flint and steel places fire and is not damaged
  portal    flint and steel inside an obsidian frame -> minecraft:nether_portal (the fire's onPlace)
"""
import os
import socket
import struct
import time

DAMAGE_COMPONENT = 3   # 774 `minecraft:damage`


def flint_session(m, c, st, w, biomes, ctx, args):
    check = m.check
    only = [s for s in os.environ.get('FLINT_ONLY', '').split(',') if s]
    m.BLOCK_TABLE['translate'] = True

    def wanted(name):
        return name in only if only else True

    def wait(cond, what, seconds=10.0):
        m.pump(c, st, w, biomes, ctx, cond, what, seconds)

    def settle(seconds=0.6):
        end = time.time() + seconds
        while time.time() < end:
            try:
                pid, r = c.recv()
            except socket.timeout:
                continue
            m.one_packet(c, st, w, biomes, ctx, pid, r)

    def cmd(line):
        print('  /%s' % line, flush=True)
        c.send(m.SB_CHAT_COMMAND, m.string(line))

    damage = {}   # item id -> last damage seen on a stack of it

    def tolerant_read_slot(r):
        count = r.varint()
        if count <= 0:
            return 0, 0
        item = r.varint()
        added, removed = r.varint(), r.varint()
        for _ in range(added):
            comp = r.varint()
            if comp == DAMAGE_COMPONENT:
                damage[item] = r.varint()
            elif comp == 2:   # max_damage
                r.varint()
            else:
                raise m.Fail('unknown component %d' % comp)
        for _ in range(removed):
            r.varint()
        if added == 0:
            damage[item] = 0
        return count, item
    m.read_slot = tolerant_read_slot

    def state_info(state):
        data = m.BLOCK_TABLE.get('to_data', {}).get(state, state)
        for first, count, name, default, item in m.BLOCK_TABLE['ranges']:
            if first <= data < first + count:
                b = m.BLOCK_TABLE['by_name'][name]
                return name, b['states'][data - first].get('luminance', 0)
        return '?%d' % state, 0

    def name_at(x, y, z):
        s = w.block(x, y, z)
        return None if s is None else state_info(s)[0]

    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 60.0)
    wait(lambda: w.health is not None and w.window0 is not None, 'health and the inventory')
    cmd('time set day')
    cmd('weather clear')
    cmd('gamerule doFireTick false')
    seq = [100]
    bx, by, bz = int(w.pos[0]) + 3, int(w.pos[1]) + 3, int(w.pos[2]) + 3

    def mode(name, num):
        cmd('gamemode %s' % name)
        wait(lambda: w.mode == num, '%s mode' % name)

    def give(item, count=1):
        cmd('clear @s')
        settle(0.5)
        cmd('give @s minecraft:%s %d' % (item, count))
        wait(lambda: w.window0[36][0] > 0, 'the %s in hotbar slot 0' % item, 10.0)
        c.send(m.SB_CARRIED, struct.pack('>h', 0))
        settle(0.4)

    def stage_at(x, y, z):
        # Stand next to the work, flying in place so the bot does not fall through the cleared space.
        cmd('tp @s %.1f %d %.1f' % (x + 0.5, y, z + 2.5))
        settle(0.8)

    def use_on(x, y, z, face, cursor=(0.5, 0.5, 0.5)):
        seq[0] += 1
        c.send(m.SB_USE_ON, m.varint(0) + m.block_pos(x, y, z) + m.varint(face) + struct.pack('>fff', *cursor) +
               bytes([0, 0]) + m.varint(seq[0]))

    def floor(x, y, z):
        cmd('fill %d %d %d %d %d %d minecraft:air' % (x - 2, y, z - 2, x + 2, y + 4, z + 2))
        cmd('setblock %d %d %d minecraft:stone' % (x, y, z))
        settle(0.8)
        wait(lambda: name_at(x, y, z) == 'stone' and name_at(x, y + 1, z) == 'air', 'stone with air above', 10.0)

    results = []

    if wanted('fire'):
        print('--- fire (survival flint and steel)', flush=True)
        mode('survival', 0)
        x, y, z = bx, by, bz
        floor(x, y, z)
        give('flint_and_steel')
        flint = w.window0[36][1]
        before = damage.get(flint, 0)
        stage_at(x, y + 1, z)
        use_on(x, y, z, 1, (0.5, 1.0, 0.5))
        wait(lambda: name_at(x, y + 1, z) == 'fire', 'minecraft:fire above the stone', 8.0)
        wait(lambda: damage.get(flint, 0) == before + 1, 'the flint and steel to take 1 damage', 5.0)
        wait(lambda: w.acked >= seq[0], 'the block changed ack for sequence %d' % seq[0], 5.0)
        print('  fire at %d %d %d; flint damage %d -> %d; acked seq %d (sent %d)' % (x, y + 1, z, before, damage[flint],
              w.acked, seq[0]))
        results.append('fire')

    if wanted('campfire'):
        print('--- campfire (lit=false -> true)', flush=True)
        mode('survival', 0)
        x, y, z = bx + 6, by, bz
        floor(x, y, z)
        cmd('setblock %d %d %d minecraft:campfire[lit=false]' % (x, y + 1, z))
        wait(lambda: name_at(x, y + 1, z) == 'campfire', 'an unlit campfire', 8.0)
        check(state_info(w.block(x, y + 1, z))[1] == 0, 'the campfire is lit before the use')
        give('flint_and_steel')
        flint = w.window0[36][1]
        before = damage.get(flint, 0)
        stage_at(x, y + 1, z)
        use_on(x, y + 1, z, 3, (0.5, 0.3, 1.0))   # south face
        wait(lambda: name_at(x, y + 1, z) == 'campfire' and state_info(w.block(x, y + 1, z))[1] == 15, 'the campfire to be lit', 8.0)
        wait(lambda: damage.get(flint, 0) == before + 1, 'the flint and steel to take 1 damage', 5.0)
        check(name_at(x, y + 1, z + 1) != 'fire', 'a fire was placed beside the campfire as well')
        print('  campfire lit (state %d), flint damage %d' % (w.block(x, y + 1, z), damage[flint]))
        results.append('campfire')

    if wanted('charge'):
        print('--- charge (fire charge)', flush=True)
        mode('survival', 0)
        x, y, z = bx + 12, by, bz
        floor(x, y, z)
        give('fire_charge', 3)
        stage_at(x, y + 1, z)
        use_on(x, y, z, 1, (0.5, 1.0, 0.5))
        wait(lambda: name_at(x, y + 1, z) == 'fire', 'minecraft:fire from the fire charge', 8.0)
        wait(lambda: w.window0[36][0] == 2, 'the fire charge stack to lose one', 5.0)
        print('  fire placed, fire charges left %d' % w.window0[36][0])
        results.append('charge')

    if wanted('creative'):
        print('--- creative (no damage)', flush=True)
        mode('creative', 1)
        x, y, z = bx, by, bz + 6
        floor(x, y, z)
        give('flint_and_steel')
        flint = w.window0[36][1]
        stage_at(x, y + 1, z)
        use_on(x, y, z, 1, (0.5, 1.0, 0.5))
        wait(lambda: name_at(x, y + 1, z) == 'fire', 'minecraft:fire in creative', 8.0)
        settle(1.0)
        check(damage.get(flint, 0) == 0, 'the flint and steel was damaged in creative (%d)' % damage.get(flint, 0))
        print('  fire placed, flint undamaged')
        results.append('creative')

    if wanted('portal'):
        print('--- portal (obsidian frame)', flush=True)
        mode('survival', 0)
        x, y, z = bx + 6, by, bz + 6
        cmd('fill %d %d %d %d %d %d minecraft:air' % (x - 2, y, z - 2, x + 5, y + 6, z + 2))
        # A 4 x 5 frame on the X axis: inside x+1..x+2, y+1..y+3.
        cmd('fill %d %d %d %d %d %d minecraft:obsidian' % (x, y, z, x + 3, y, z))
        cmd('fill %d %d %d %d %d %d minecraft:obsidian' % (x, y + 4, z, x + 3, y + 4, z))
        cmd('fill %d %d %d %d %d %d minecraft:obsidian' % (x, y + 1, z, x, y + 3, z))
        cmd('fill %d %d %d %d %d %d minecraft:obsidian' % (x + 3, y + 1, z, x + 3, y + 3, z))
        settle(1.0)
        wait(lambda: name_at(x, y, z) == 'obsidian' and name_at(x + 3, y + 4, z) == 'obsidian', 'the obsidian frame', 10.0)
        give('flint_and_steel')
        stage_at(x + 1, y + 1, z)
        use_on(x + 1, y, z, 1, (0.5, 1.0, 0.5))
        wait(lambda: all(name_at(x + dx, y + dy, z) == 'nether_portal' for dx in (1, 2) for dy in (1, 2, 3)),
             'six nether_portal blocks inside the frame', 8.0)
        print('  portal lit')
        results.append('portal')

    print('flint: all scenarios passed: %s' % ', '.join(results), flush=True)
