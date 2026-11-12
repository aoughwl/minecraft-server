"""Session for mcbot.py --itemuse: the player's item use, experience and pose over the wire. mcbot.py hands its own module in as `m`.

The bot must be an operator of level 4 on a COPY of a world. ITEMUSE_ONLY=eat,bow,shield,xp,pose limits the scenarios.
  eat     hunger is drained, a bread is eaten (use item, 32 ticks): the food level rises and the stack loses one
  bow     a bow is drawn and released (`Status::ReleaseItemInUse` -> `on_stopped_using`): an arrow entity is added and the
          arrow stack loses one
  shield  a shield in the off hand is raised: the using flag (living flags bit 0, off hand bit 1) is sent, and cleared on release
  xp      an experience orb is summoned on the bot: the experience packet shows the points
  pose    sneaking sends the crouching pose (`update_player_pose`), standing again sends the standing pose
"""
import os
import socket
import struct
import time

PLAY_SET_ENTITY_DATA = 0x61
SB_ACTION = 40
SB_USE = 64
SB_INPUT = 42


def itemuse_session(m, c, st, w, biomes, ctx, args):
    check = m.check
    only = [s for s in os.environ.get('ITEMUSE_ONLY', '').split(',') if s]

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

    spawned = []     # (entity id, type id)
    flags = []       # (entity id, living flags byte)
    poses = []       # (entity id, pose id)
    xp = []          # (progress, level, total)

    def tap(pid, data):
        r = m.Reader(data)
        if pid == m.PLAY_ADD_ENTITY:
            eid = r.varint()
            r.take(16)
            spawned.append((eid, r.varint()))
        elif pid == m.PLAY_EXPERIENCE:
            xp.append((r.f32(), r.varint(), r.varint()))
        elif pid == PLAY_SET_ENTITY_DATA:
            eid = r.varint()
            while True:
                index = r.u8()
                if index == 0xFF:
                    break
                kind = r.varint()
                if kind == 0:
                    v = r.u8()
                    if index == 8:
                        flags.append((eid, v))
                elif kind == 21:   # pose
                    poses.append((eid, r.varint()))
                elif kind in (1, 2, 12, 14, 15):
                    r.varint()
                elif kind == 3:
                    r.f32()
                elif kind == 8:
                    r.u8()
                else:
                    break
    ctx['tap'] = tap

    def tolerant_read_slot(r):
        # A bow or a shield is sent with one component (a diff against the prototype): its id and the rest of the
        # packet is kept for the log, and the stack is read as (count, id).
        count = r.varint()
        if count <= 0:
            return 0, 0
        item = r.varint()
        added, removed = r.varint(), r.varint()
        if added or removed:
            comp = r.varint() if added else -1
            print('  [stack %d x%d with %d+%d components, first id %d, next bytes %s]' % (item, count, added, removed, comp, r.data[r.at:r.at + 6].hex()), flush=True)
            if added == 1 and removed == 0 and comp in (2, 3):   # max_damage, damage: a varint
                print('  [component %d = %d]' % (comp, r.varint()), flush=True)
            elif added == 1 and removed == 0:
                raise m.Fail('unknown component %d' % comp)
        return count, item
    m.read_slot = tolerant_read_slot

    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 60.0)
    wait(lambda: w.health is not None and w.window0 is not None, 'health and the inventory')
    cmd('gamemode survival')
    wait(lambda: w.mode == 0, 'survival mode')
    cmd('difficulty easy')
    cmd('time set day')
    settle(0.8)
    seq = [100]

    def hotbar():
        return [(i - 36, w.window0[i]) for i in range(36, 45)]

    def give(item, count):
        cmd('give @s minecraft:%s %d' % (item, count))
        settle(0.5)
        wait(lambda: slot_with() is not None, 'the %s in the hotbar' % item, 10.0)
        settle(0.5)

    def slot_with(count_min=1):
        for i, s in hotbar():
            if s[0] >= count_min:
                return i, s
        return None

    def select(i):
        c.send(m.SB_CARRIED, struct.pack('>h', i))
        settle(0.3)

    def use(hand=0):
        seq[0] += 1
        c.send(SB_USE, m.varint(hand) + m.varint(seq[0]) + struct.pack('>ff', 0.0, 0.0))

    def release():
        seq[0] += 1
        c.send(SB_ACTION, m.varint(5) + m.block_pos(0, 0, 0) + bytes([0]) + m.varint(seq[0]))

    def clear():
        cmd('clear @s')
        settle(0.8)

    if wanted('eat'):
        print('--- eat', flush=True)
        clear()
        cmd('effect give @s minecraft:hunger 30 60 true')
        wait(lambda: w.health[1] <= 16, 'hunger to take food away', 40.0)
        cmd('effect clear @s')
        settle(0.5)
        before = w.health[1]
        give('bread', 3)
        found = slot_with()
        check(found, 'no bread in the hotbar')
        i, s = found
        select(i)
        print('  food %d, bread %s in slot %d' % (before, s, i))
        use()
        wait(lambda: w.window0[36 + i][0] == s[0] - 1 or w.health[1] > before, 'the bread to be eaten', 10.0)
        settle(1.0)
        print('  after: food %d, stack %s' % (w.health[1], w.window0[36 + i]))
        check(w.window0[36 + i][0] == s[0] - 1, 'the bread stack did not lose one')
        check(w.health[1] >= before + 4 or w.health[1] == 20, 'eating bread did not restore hunger')
        print('  eat OK')

    if wanted('bow'):
        print('--- bow', flush=True)
        clear()
        give('bow', 1)
        found = slot_with()
        check(found, 'no bow in the hotbar')
        bow_slot = found[0]
        cmd('give @s minecraft:arrow 5')
        settle(1.0)
        arrow_slots = [k for k in range(46) if w.window0[k][0] == 5]
        check(arrow_slots, 'no stack of 5 arrows')
        select(bow_slot)
        mark = len(spawned)
        use()
        settle(1.4)   # 28 ticks of draw
        release()
        wait(lambda: len(spawned) > mark, 'an arrow entity', 5.0)
        settle(0.5)
        after = [w.window0[k][0] for k in arrow_slots]
        print('  spawned %s, arrow stack now %s' % (spawned[mark:], after))
        check(any(n == 4 for n in after), 'the arrow stack did not lose one')
        print('  bow OK')

    if wanted('shield'):
        print('--- shield', flush=True)
        clear()
        cmd('item replace entity @s weapon.offhand with minecraft:shield')
        settle(0.8)
        mark = len(flags)
        use(1)
        settle(0.6)
        got = flags[mark:]
        print('  living flags: %s' % (got,))
        check(any(v & 1 and v & 2 for _, v in got), 'the using flag with the off hand bit was not sent')
        release()
        settle(0.4)
        check(any(not (v & 1) for _, v in flags[mark:]), 'the using flag was not cleared on release')
        print('  shield OK')

    if wanted('xp'):
        print('--- xp', flush=True)
        cmd('xp set @s 0 levels')
        cmd('xp set @s 0 points')
        settle(0.6)
        mark = len(xp)
        x, y, z = w.pos
        cmd('summon minecraft:experience_orb %.2f %.2f %.2f' % (x, y, z))
        wait(lambda: len(xp) > mark and xp[-1][2] > 0, 'the experience packet', 15.0)
        print('  experience packets %s' % (xp[mark:],))
        print('  xp OK')

    if wanted('pose'):
        print('--- pose', flush=True)
        settle(0.5)
        mark = len(poses)
        c.send(SB_INPUT, bytes([0x20]))   # sneak bit of the input flags
        settle(0.8)
        print('  poses %s' % (poses[mark:],))
        check(any(p == 5 for _, p in poses[mark:]), 'no crouching pose (5) after sneaking')
        mark = len(poses)
        c.send(SB_INPUT, bytes([0x00]))
        settle(0.8)
        check(any(p == 0 for _, p in poses[mark:]), 'no standing pose after standing up')
        print('  pose OK')
    ctx['tap'] = None
    print('itemuse: all scenarios passed', flush=True)
