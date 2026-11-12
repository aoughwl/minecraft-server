"""Session for mcbot.py --meta / --meta-verify: entity data (set_entity_data) as a 1.21.11 (protocol 774) client reads it.

The bot must be an operator of level 4 on a COPY of a world. mcbot.py hands its own module in as `m`; every entry of every
set_entity_data packet lands in m.META_ALL as (entity id, index, serializer id, value) through m.read_metadata, which fails on
a serializer id that 774 does not have (the bot once reported 'metadata type 42': HUMANOID_ARM, a 26.x id).

  --meta         summons a named baby sheep with a colour, a pig with a health, an armor stand with flags, a villager, two
                 mobs wearing a helmet (/item replace entity, and `equipment` in the summon NBT), then sneaks and goes under
                 water: every entry must be at the index and serializer type 774 has (Entity 0-7, LivingEntity 8-14,
                 Mob 15, AgeableMob 16, Sheep 18, ArmorStand 15-21, Villager 18, the player's own flags, pose and air)
  --meta-verify  a second player joins the same running server: the entities of --meta come into its view, and each one's
                 data must arrive again after its spawn packet (the join path, not the summon path)
"""
import socket
import struct
import time

SB_INPUT = 42

SHEEP_NBT = '{CustomName:\'"Bob"\',Age:-24000,Color:5}'
ZOMBIE_NBT = '{NoAI:1b,Invulnerable:1b,equipment:{head:{id:"minecraft:iron_helmet",count:1}}}'


def meta_session(m, c, st, w, biomes, ctx, args, verify=False):
    check = m.check

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

    spawned = []     # (entity id, type id, (x, y, z)), in the order of arrival
    equipment = []   # (entity id, slot byte, count, item id)
    own = []         # the bot's own entity id (the login packet starts with it)

    def tap(pid, data):
        r = m.Reader(data)
        if pid == m.PLAY_LOGIN:
            own.append(r.i32())
        elif pid == m.PLAY_ADD_ENTITY:
            eid = r.varint()
            r.take(16)
            kind = r.varint()
            spawned.append((eid, kind, struct.unpack('>ddd', r.take(24))))
        elif pid == m.PLAY_EQUIPMENT:
            eid = r.varint()
            while True:
                slot = r.u8()
                count = r.varint()
                item = r.varint() if count > 0 else 0
                equipment.append((eid, slot & 0x7F, count, item))
                if count > 0:
                    added, removed = r.varint(), r.varint()
                    if added or removed:
                        break    # components: this bot does not size them; the first stack of the packet is enough
                if not slot & 0x80:
                    break
    ctx['tap'] = tap

    def entries(eid, index=None):
        return [(i, k, v) for (e, i, k, v) in m.META_ALL if e == eid and (index is None or i == index)]

    def has(eid, index, kind, value=None):
        for i, k, v in entries(eid, index):
            if k == kind and (value is None or v == value):
                return True
        return False

    def show(label, eid):
        print('  %s (entity %d): %s' % (label, eid, ', '.join('%d:%s=%r' % (i, m.META_KINDS_774[k], v)
                                                              for i, k, v in entries(eid))), flush=True)

    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 60.0)
    wait(lambda: w.health is not None and w.window0 is not None, 'health and the inventory')
    # Nothing of the join may have a serializer id that is not 774's: read_metadata already failed the run on one.
    print('  %d metadata entries so far, all with 774 serializer ids' % len(m.META_ALL), flush=True)

    if verify:
        # The summoned entities are still in the world: they come into view with the join.
        wait(lambda: len(spawned) >= 5, 'the entities of --meta to spawn', 30.0)
        settle(1.5)
        named = [e for e, _, _ in spawned if has(e, 2, 6, 'Bob')]
        check(named, 'no entity came with its custom name (index 2, optional component)')
        eid = named[0]
        show('named', eid)
        check(has(eid, 16, 8, True), 'the named sheep is not a baby (index 16, boolean) after the join')
        check(has(eid, 18, 0, 5), 'the sheep colour (index 18, byte 5) did not arrive with the join')
        check(has(eid, 9, 3, 8.0), 'the sheep health (index 9, float 8.0) did not arrive with the join')
        stands = [e for e, _, _ in spawned if any(i == 15 and k == 0 and v & 5 == 5 for i, k, v in entries(e))]
        check(stands, 'no armor stand with its flags (index 15 byte, small and arms) after the join')
        check(all(has(stands[0], i, 9) for i in range(16, 22)), 'the armor stand poses (index 16-21, rotation) are missing')
        helmets = [e for (e, slot, count, item) in equipment if slot == 5 and count > 0]
        check(len(set(helmets)) >= 2, 'the two helmets did not arrive with the join: %r' % equipment)
        ctx['tap'] = None
        print('meta-verify: all entity data arrived after the spawn packets', flush=True)
        return

    cmd('gamemode creative')
    cmd('difficulty easy')
    cmd('time set midnight')
    settle(4.0)   # the entities of the world's own chunks arrive first; they are not ours
    wait(lambda: w.mode == 1, 'creative mode')
    said_at = len(w.chat)

    def summon(label, line, dx, dy, dz):
        """The spawn that lands where the command put it: the world's own entities spawn around the bot all the time."""
        before = len(spawned)
        bx, by, bz = w.pos
        cmd(line)

        def mine():
            for eid, kind, (x, y, z) in spawned[before:]:
                if abs(x - (bx + dx)) < 1.5 and abs(z - (bz + dz)) < 1.5:
                    return eid, kind
            return None
        wait(lambda: mine() is not None, 'the %s to spawn' % label, 15.0)
        settle(0.7)
        eid, kind = mine()
        print('  %s is entity %d, type %d' % (label, eid, kind), flush=True)
        return eid

    print('--- summon with NBT', flush=True)
    sheep = summon('baby sheep', 'summon minecraft:sheep ~2 ~ ~ ' + SHEEP_NBT, 2, 0, 0)
    show('sheep', sheep)
    check(has(sheep, 2, 6, 'Bob'), 'no custom name (index 2, optional component Bob)')
    check(has(sheep, 16, 8, True), 'Age:-24000 is not a baby (index 16, boolean true)')
    check(has(sheep, 18, 0, 5), 'Color:5 is not the sheep colour (index 18, byte 5)')
    check(has(sheep, 9, 3, 8.0), 'no health (index 9, float 8.0)')
    pig = summon('pig', 'summon minecraft:pig ~-2 ~ ~ {Health:5f,Silent:1b,NoGravity:0b}', -2, 0, 0)
    show('pig', pig)
    check(has(pig, 9, 3, 5.0), 'Health:5f did not reach the client as index 9 float 5.0')
    check(has(pig, 4, 8, True), 'Silent:1b did not reach the client as index 4 boolean')
    check(not any(('Incorrect' in s or 'Unknown' in s) for s in w.chat[said_at:]), 'a summon was rejected: %r' % w.chat[said_at:])
    stand = summon('armor stand', 'summon minecraft:armor_stand ~ ~ ~2 {ShowArms:1b,Small:1b}', 0, 0, 2)
    show('armor stand', stand)
    flags = [v for i, k, v in entries(stand, 15) if k == 0]
    check(flags and flags[-1] & 5 == 5, 'armor stand flags (index 15 byte) lack small|arms: %r' % flags)
    check(all(has(stand, i, 9) for i in range(16, 22)), 'armor stand poses (index 16-21, rotation) are missing')
    villager = summon('villager', 'summon minecraft:villager ~ ~ ~-2 {NoAI:1b}', 0, 0, -2)
    show('villager', villager)
    check(has(villager, 15, 0, 1), 'NoAI:1b is not mob flag 1 (index 15, byte)')
    check(any(i == 18 and k == 18 for i, k, v in entries(villager)), 'no villager data (index 18, villager data)')
    zombie = summon('zombie in a helmet', 'summon minecraft:zombie ~4 ~ ~ ' + ZOMBIE_NBT, 4, 0, 0)
    show('zombie', zombie)
    check(any(e == zombie and slot == 5 and count == 1 for (e, slot, count, item) in equipment),
          'the summoned zombie\'s helmet (equipment slot 5) was not sent: %r' % equipment)

    print('--- /item replace entity', flush=True)
    mark = len(equipment)
    cmd('item replace entity @e[type=minecraft:armor_stand,limit=1] armor.head with minecraft:diamond_helmet')
    wait(lambda: any(e == stand and slot == 5 for (e, slot, count, item) in equipment[mark:]), 'the armor stand helmet packet', 10.0)
    print('  equipment %r' % (equipment[mark:],), flush=True)
    check(not any('Incorrect' in s or 'No such slot' in s for s in w.chat[said_at:]), 'the /item command failed: %r' % w.chat[said_at:])

    print('--- pose and flags of the player', flush=True)
    cmd('gamemode survival')
    wait(lambda: w.mode == 0, 'survival mode')
    settle(2.0)
    me = own[0]
    mark = len(m.META_ALL)
    c.send(SB_INPUT, bytes([0x20]))   # sneak bit of the input flags
    settle(1.0)
    got = [(e, i, k, v) for (e, i, k, v) in m.META_ALL[mark:] if e == me]
    print('  after sneaking: %r' % (got,), flush=True)
    check(any(i == 6 and k == 20 and v == 5 for (e, i, k, v) in got), 'no crouching pose (index 6, pose 5) for the player')
    check(any(i == 0 and k == 0 and v & 2 for (e, i, k, v) in got), 'no sneaking flag (index 0, byte bit 2) for the player')
    mark = len(m.META_ALL)
    c.send(SB_INPUT, bytes([0x00]))
    settle(1.0)
    got = [(e, i, k, v) for (e, i, k, v) in m.META_ALL[mark:] if e == me]
    check(any(i == 6 and k == 20 and v == 0 for (e, i, k, v) in got), 'no standing pose (index 6, pose 0) after standing up')

    print('--- air supply', flush=True)
    cmd('fill ~-1 ~ ~-1 ~1 ~3 ~1 minecraft:water')
    mark = len(m.META_ALL)
    wait(lambda: any(e == me and i == 1 and k == 1 and v < 300 for (e, i, k, v) in m.META_ALL[mark:]),
         'the air supply to fall under water (index 1, varint under 300)', 30.0)
    print('  air: %r' % [v for (e, i, k, v) in m.META_ALL[mark:] if e == me and i == 1][:4], flush=True)
    cmd('fill ~-1 ~ ~-1 ~1 ~3 ~1 minecraft:air')
    ctx['tap'] = None
    print('meta: all scenarios passed', flush=True)
