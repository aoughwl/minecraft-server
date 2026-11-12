"""Session for mcbot.py --partsb: the core-partials batch B over the wire. mcbot.py hands its own module in as `m`.

The bot must be an operator of level 4 on a COPY of a world. Scenarios (PARTSB_ONLY=a,b limits them):
  pearl    an ender pearl is thrown, the item cooldown is sent, a second throw inside it makes no entity, a third after it does
  bed      a bed is slept in, the night skips after 100 ticks and the sleeper is woken (leave-bed animation, bed unoccupied);
           then slept in again and left by the leave-bed command of the client
  villager a villager next to a composter becomes a farmer, a right click opens the trading window and sends the offers
  dragon   the bot goes to the End, a dragon is summoned, it is told about it, and damage to it shows
"""
import os
import socket
import struct
import time

PLAY_ANIMATE = 2
PLAY_BOSS_EVENT = 9
PLAY_COOLDOWN = 22
PLAY_DAMAGE_EVENT = 25
PLAY_OPEN_SCREEN = 57
PLAY_MERCHANT_OFFERS = 50
SB_INTERACT = 25
SB_PLAYER_COMMAND = 41
SB_USE = 64
WINDOW_MERCHANT = 19


def partsb_session(m, c, st, w, biomes, ctx, args):
    check = m.check
    only = [s for s in os.environ.get('PARTSB_ONLY', '').split(',') if s]

    def wanted(name):
        return not only or name in only

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

    token = [0x7200]

    def sync():
        token[0] += 1
        c.send(m.SB_PING, struct.pack('>q', token[0]))
        t = token[0]
        wait(lambda: t in w.pongs, 'a pong')

    spawned = []      # (entity id, type, x, y, z)
    cooldowns = []    # (group, ticks)
    animations = []   # (entity id, action)
    screens = []      # (sync id, window type)
    offers = []       # (window id, count)
    damages = []      # entity ids that took a damage event
    respawns = []

    def tap(pid, data):
        r = m.Reader(data)
        if pid == m.PLAY_ADD_ENTITY:
            eid = r.varint()
            r.take(16)
            kind = r.varint()
            spawned.append((eid, kind, r.f64(), r.f64(), r.f64()))
        elif pid == PLAY_COOLDOWN:
            cooldowns.append((r.string(), r.varint()))
        elif pid == PLAY_ANIMATE:
            animations.append((r.varint(), r.u8()))
        elif pid == PLAY_OPEN_SCREEN:
            screens.append((r.varint(), r.varint()))
        elif pid == PLAY_MERCHANT_OFFERS:
            offers.append((r.varint(), r.varint()))
        elif pid == PLAY_DAMAGE_EVENT:
            damages.append(r.varint())
        elif pid == m.PLAY_RESPAWN:
            r.varint()
            name = r.string()
            respawns.append(name)
            if name != 'minecraft:overworld':
                ctx['sections'], w.min_y = 16, 0
            else:
                ctx['sections'], w.min_y = m.DEFAULT_SECTIONS, -64
            w.chunks.clear()
            w.overrides.clear()

    ctx['tap'] = tap

    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    wait(lambda: w.health is not None, 'health')
    c.send(m.SB_CHANGE_GAME_MODE, m.varint(1))
    wait(lambda: w.mode == 1, 'creative')
    px, py, pz = int(w.pos[0] // 1), int(w.pos[1] // 1), int(w.pos[2] // 1)
    wait(lambda: w.block(px, py - 1, pz) is not None, 'the chunk under the player', 30.0)
    sx, fy, sz = px + 2, py - 1, pz + 2
    cmd('fill %d %d %d %d %d %d minecraft:air' % (sx - 1, fy + 1, sz - 1, sx + 12, fy + 8, sz + 7))
    cmd('fill %d %d %d %d %d %d minecraft:stone' % (sx - 1, fy, sz - 1, sx + 12, fy, sz + 7))
    cmd('tp @s %d %d %d' % (sx + 4, fy + 1, sz + 5))
    wait(lambda: w.block(sx + 4, fy, sz + 5) not in (None, 0) and w.block(sx + 4, fy + 3, sz + 5) == 0, 'the stage')
    settle(1.0)
    print('  stage floor y=%d from %d,%d' % (fy, sx, sz), flush=True)

    def hold(name, count=1):
        cmd('clear @s')
        cmd('give @s minecraft:%s %d' % (name, count))
        c.send(m.SB_CARRIED, struct.pack('>h', 0))
        settle(0.8)
        sync()

    seq = [900]

    def use_item(pitch=-45.0):
        seq[0] += 1
        c.send(SB_USE, m.varint(0) + m.varint(seq[0]) + struct.pack('>ff', 0.0, pitch))

    def use_on(x, y, z, face, cursor=(0.5, 0.5, 0.5)):
        seq[0] += 1
        c.send(m.SB_USE_ON, m.varint(0) + m.block_pos(x, y, z) + m.varint(face) + struct.pack('>fff', *cursor) +
               bytes([0, 0]) + m.varint(seq[0]))

    # --- An ender pearl and its cooldown.
    if wanted('pearl'):
        hold('ender_pearl', 8)
        mark_e, mark_c = len(spawned), len(cooldowns)
        use_item()
        wait(lambda: len(cooldowns) > mark_c, 'the cooldown packet')
        group, ticks = cooldowns[-1]
        print('  cooldown %r for %d ticks' % (group, ticks), flush=True)
        check('ender_pearl' in group, 'the cooldown group is %r' % group)
        check(ticks == 20, 'ender pearl cooldown is 1 second: %d ticks' % ticks)
        st.hit('pearl_cooldown_sent')
        wait(lambda: len(spawned) > mark_e, 'the pearl entity')
        first = len(spawned) - mark_e
        mark_e, mark_c = len(spawned), len(cooldowns)
        use_item()
        settle(0.4)
        check(len(spawned) == mark_e, 'a second pearl was thrown inside the cooldown: %r' % spawned[mark_e:])
        check(len(cooldowns) == mark_c, 'the cooldown was restarted')
        print('  a second throw inside the cooldown made %d entities' % (len(spawned) - mark_e), flush=True)
        st.hit('pearl_blocked')
        settle(1.2)
        use_item()
        wait(lambda: len(spawned) > mark_e, 'a pearl after the cooldown', 5.0)
        print('  a throw after the cooldown made %d entities (the first made %d)' % (len(spawned) - mark_e, first), flush=True)
        st.hit('pearl_again')
        cmd('kill @e[type=minecraft:ender_pearl]')
        settle(0.5)

    # --- A bed: slept in at night, the night skips, the sleeper wakes; then slept in and left by command.
    if wanted('bed'):
        bx, bz = sx + 4, sz + 1
        hold('red_bed')
        use_on(bx, fy, bz, 1)
        wait(lambda: w.block(bx, fy + 1, bz) not in (None, 0), 'the bed foot')
        settle(0.5)
        foot_before = w.block(bx, fy + 1, bz)
        w.time = None
        cmd('time set 13000')
        wait(lambda: w.time is not None and 12000 <= w.time[1] % 24000 <= 14000, 'the time to be night', 5.0)
        del animations[:]
        chat_at = len(w.chat)
        use_on(bx, fy + 1, bz, 1)
        settle(1.0)
        check(not any('not_safe' in s or 'no_sleep' in s or 'too_far' in s or 'obstructed' in s or 'occupied' in s
                      for s in w.chat[chat_at:]), 'the server refused sleep: %r' % w.chat[chat_at:])
        foot_slept = w.block(bx, fy + 1, bz)
        check(foot_slept != foot_before, 'the bed is not occupied: %r' % foot_slept)
        print('  slept: bed state %d -> %d' % (foot_before, foot_slept), flush=True)
        st.hit('bed_slept')
        # 100 ticks asleep is 5 seconds; the skip sets the time to the next morning and wakes everyone.
        wait(lambda: w.time is not None and w.time[1] % 24000 < 1000, 'the night to be skipped', 20.0)
        print('  night skipped: time of day %d' % (w.time[1] % 24000), flush=True)
        st.hit('night_skipped')
        wait(lambda: any(a == 2 for _, a in animations), 'the leave-bed animation', 5.0)
        settle(0.5)
        foot_after = w.block(bx, fy + 1, bz)
        check(foot_after == foot_before, 'the bed is still occupied after waking: %d (was %d)' % (foot_after, foot_before))
        print('  woken: leave-bed animation sent, bed state back to %d' % foot_after, flush=True)
        st.hit('bed_woken_by_skip')
        # Again, but the client leaves the bed itself.
        cmd('time set 13000')
        settle(0.8)
        del animations[:]
        use_on(bx, fy + 1, bz, 1)
        settle(1.0)
        check(w.block(bx, fy + 1, bz) != foot_before, 'the bed was not slept in the second time')
        c.send(SB_PLAYER_COMMAND, m.varint(0) + m.varint(0) + m.varint(0))   # entity id (ignored), leave bed, no data
        wait(lambda: any(a == 2 for _, a in animations), 'the leave-bed animation after the client left', 5.0)
        settle(0.5)
        check(w.block(bx, fy + 1, bz) == foot_before, 'the bed is occupied after the client left it')
        print('  left by command: animation sent, bed unoccupied', flush=True)
        st.hit('bed_woken_by_command')
        cmd('time set 6000')
        settle(0.5)

    # --- A villager: a farmer by a composter, a trading window.
    if wanted('villager'):
        vx, vz = sx + 8, sz + 3
        cmd('setblock %d %d %d minecraft:composter' % (vx + 2, fy + 1, vz))
        settle(0.6)
        mark = len(spawned)
        cmd('summon minecraft:villager %d %d %d' % (vx, fy + 1, vz))

        def mine():
            return [e for e in spawned[mark:] if abs(e[2] - (vx + 0.5)) < 2 and abs(e[4] - (vz + 0.5)) < 2]
        wait(lambda: mine(), 'the villager', 10.0)
        villager = mine()[0]
        print('  villager entity %d' % villager[0], flush=True)
        settle(1.5)   # the job site is found in the AI tick
        st.hit('villager_summoned')
        cmd('tp @s %d %d %d' % (vx - 1, fy + 1, vz))
        settle(1.0)
        mark_s, mark_o = len(screens), len(offers)
        c.send(SB_INTERACT, m.varint(villager[0]) + m.varint(0) + m.varint(0) + bytes([0]))
        wait(lambda: len(screens) > mark_s, 'the trading window', 8.0)
        sync_id, wtype = screens[-1]
        print('  window %d of type %d' % (sync_id, wtype), flush=True)
        check(wtype == WINDOW_MERCHANT, 'the window type is %d, not the merchant (%d)' % (wtype, WINDOW_MERCHANT))
        st.hit('villager_window_opened')
        wait(lambda: len(offers) > mark_o, 'the offers', 5.0)
        win, count = offers[-1]
        check(win == sync_id and count >= 1, 'offers for window %d: %d trades (window is %d)' % (win, count, sync_id))
        print('  %d offers for window %d' % (count, win), flush=True)
        st.hit('villager_offers_sent')
        c.send(m.SB_CONTAINER_CLOSE, m.varint(sync_id))
        settle(0.5)

    # --- The End and the dragon.
    if wanted('dragon'):
        mark_r = len(respawns)
        cmd('execute in minecraft:the_end run tp @s 0 70 0')
        wait(lambda: len(respawns) > mark_r, 'the respawn into the End', 20.0)
        print('  respawned into %r' % respawns[-1], flush=True)
        check(respawns[-1] == 'minecraft:the_end', 'went to %r' % respawns[-1])
        wait(lambda: w.pos is not None and abs(w.pos[1] - 70) < 40, 'a position in the End', 30.0)
        settle(3.0)
        mark = len(spawned)
        cmd('summon minecraft:ender_dragon 0 90 0')
        wait(lambda: len(spawned) > mark, 'the dragon to be added', 15.0)
        print('  entities added: %r' % (spawned[mark:],), flush=True)
        st.hit('dragon_spawned')
        settle(2.0)
        mark_d = len(damages)
        cmd('damage @e[type=minecraft:ender_dragon,limit=1] 10')
        wait(lambda: len(damages) > mark_d, 'a damage event for the dragon', 10.0)
        print('  damage event for entity %d' % damages[-1], flush=True)
        st.hit('dragon_damaged')
        cmd('kill @e[type=minecraft:ender_dragon]')
        settle(1.0)
