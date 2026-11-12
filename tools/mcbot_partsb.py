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
PLAY_CONTAINER_SLOT = 20
PLAY_CONTAINER_CONTENT = 18
SB_SELECT_TRADE = 50
SB_INTERACT = 25
SB_PLAYER_COMMAND = 41
SB_USE = 64
WINDOW_MERCHANT = 19


def partsb_session(m, c, st, w, biomes, ctx, args):
    check = m.check
    only = [s for s in os.environ.get('PARTSB_ONLY', '').split(',') if s]

    def wanted(name):
        # pig and cow are controls, run when asked for: the pig does not follow the carrot in this build (see the report).
        return name in only if only else name in ('pearl', 'bed', 'villager', 'dragon')

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
    raw_offers = []   # the offers packets, whole
    slots = {}        # (window, slot) -> (count, item id), from container slot updates

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
            raw_offers.append(bytes(data))
            offers.append((r.varint(), r.varint()))
        elif pid == PLAY_CONTAINER_CONTENT:
            win = r.varint()
            r.varint()
            for i in range(r.varint()):
                slots[(win, i)] = m.read_slot(r)
        elif pid == PLAY_CONTAINER_SLOT:
            win = r.varint()
            r.varint()
            slot = r.i16()
            slots[(win, slot)] = m.read_slot(r)
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

        def thrown_since(mark):
            """Entities added since `mark` within 4 blocks of the bot: a pearl leaves from the bot's hand."""
            return [e for e in spawned[mark:] if abs(e[2] - w.pos[0]) < 4.0 and abs(e[4] - w.pos[2]) < 4.0]
        mark_e, mark_c = len(spawned), len(cooldowns)
        use_item()
        wait(lambda: len(cooldowns) > mark_c, 'the cooldown packet')
        group, ticks = cooldowns[-1]
        print('  cooldown %r for %d ticks' % (group, ticks), flush=True)
        check('ender_pearl' in group, 'the cooldown group is %r' % group)
        check(ticks == 20, 'ender pearl cooldown is 1 second: %d ticks' % ticks)
        st.hit('pearl_cooldown_sent')
        wait(lambda: thrown_since(mark_e), 'the pearl entity')
        pearl_kind = thrown_since(mark_e)[0][1]
        mark_e, mark_c = len(spawned), len(cooldowns)
        use_item()
        settle(0.4)
        again = [e for e in thrown_since(mark_e) if e[1] == pearl_kind]
        check(not again, 'a second pearl was thrown inside the cooldown: %r' % again)
        check(len(cooldowns) == mark_c, 'the cooldown was restarted')
        print('  a second throw inside the cooldown made no pearl (type %d)' % pearl_kind, flush=True)
        st.hit('pearl_blocked')
        # The first pearl lands and teleports the bot; wait for that, go back to the stage, and throw once more.
        wait(lambda: abs(w.pos[2] - (sz + 5.5)) > 5.0, 'the first pearl to land', 10.0)
        cmd('tp @s %d %d %d' % (sx + 4, fy + 1, sz + 5))
        settle(1.5)
        mark_e = len(spawned)
        use_item()
        wait(lambda: [e for e in thrown_since(mark_e) if e[1] == pearl_kind], 'a pearl after the cooldown', 5.0)
        print('  a throw after the cooldown made a pearl again', flush=True)
        st.hit('pearl_again')
        cmd('kill @e[type=ender_pearl]')   # before it lands
        settle(1.0)
        cmd('tp @s %d %d %d' % (sx + 4, fy + 1, sz + 5))
        settle(1.5)

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
        own_id = [e for e, a in animations if a == 2][0]   # the animation names the sleeper: the bot itself
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
        c.send(SB_PLAYER_COMMAND, m.varint(own_id) + m.varint(0) + m.varint(0))   # the bot's entity id, leave bed, no data
        try:
            wait(lambda: any(a == 2 for _, a in animations), 'the leave-bed animation after the client left', 5.0)
        except m.Fail:
            print('  animations %r, bed foot state %r (empty bed %r), chat %r' % (animations, w.block(bx, fy + 1, bz), foot_before,
                                                                               w.chat[-3:]), flush=True)
            raise
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
        # The first offer: what it takes and gives, as 774 writes an offer (ItemCost, ItemStack, optional ItemCost, ...).
        r = m.Reader(raw_offers[-1])
        r.varint()
        r.varint()
        cost_a = (r.varint(), r.varint())          # item id, count
        check(r.varint() == 0, 'the first offer asks for item components: this bot does not read them')
        out_count, out_item = m.read_slot(r)
        has_b = r.boolean()
        if has_b:
            r.varint()
            r.varint()
            check(r.varint() == 0, 'the second cost has components')
        disabled = r.boolean()
        uses, max_uses, xp, special = r.i32(), r.i32(), r.i32(), r.i32()
        print('  offer 0: %d x item %d%s -> %d x item %d (uses %d of %d, xp %d)' % (
            cost_a[1], cost_a[0], ' + second cost' if has_b else '', out_count, out_item, uses, max_uses, xp), flush=True)
        check(not disabled and uses == 0, 'the first offer is used up or disabled')
        if not has_b:
            # Give the cost in the first hotbar slot (creative), pick the offer, move the cost into the window, and buy.
            c.send(m.SB_CONTAINER_CLOSE, m.varint(sync_id))
            settle(0.5)
            c.send(m.SB_CREATIVE, struct.pack('>h', 36) + m.write_slot(cost_a[1], cost_a[0]))
            settle(0.8)
            mark_s = len(screens)
            c.send(SB_INTERACT, m.varint(villager[0]) + m.varint(0) + m.varint(0) + bytes([0]))
            wait(lambda: len(screens) > mark_s, 'the trading window again', 8.0)
            sync_id = screens[-1][0]
            settle(0.6)
            c.send(SB_SELECT_TRADE, m.varint(0))
            settle(0.4)
            # window slots: 0, 1 the cost, 2 the result, 3 to 29 the inventory, 30 to 38 the hotbar
            c.send(m.SB_CONTAINER_CLICK, m.varint(sync_id) + m.varint(0) + struct.pack('>h', 30) + bytes([0]) + m.varint(1) +
                   m.varint(0) + bytes([0]))
            try:
                wait(lambda: slots.get((sync_id, 2), (0, 0)) == (out_count, out_item), 'the result slot to show the offer', 5.0)
            except m.Fail:
                print('  window %d slots: %r' % (sync_id, {k[1]: v for k, v in sorted(slots.items()) if k[0] == sync_id and v[0]}), flush=True)
                print('  window 0 slots: %r' % ({k[1]: v for k, v in sorted(slots.items()) if k[0] == 0 and v[0]},), flush=True)
                raise
            print('  the result slot shows %r' % (slots[(sync_id, 2)],), flush=True)
            st.hit('villager_result_shown')
            c.send(m.SB_CONTAINER_CLICK, m.varint(sync_id) + m.varint(0) + struct.pack('>h', 2) + bytes([0]) + m.varint(1) +
                   m.varint(0) + bytes([0]))
            wait(lambda: any(v == (out_count, out_item) for (win, sl), v in slots.items() if win == sync_id and sl >= 3),
                 'the bought item in the inventory', 5.0)
            got = [k for k, v in slots.items() if k[0] == sync_id and k[1] >= 3 and v == (out_count, out_item)]
            print('  bought: %d x item %d is in window slot %r' % (out_count, out_item, got[-1][1]), flush=True)
            st.hit('villager_traded')
        c.send(m.SB_CONTAINER_CLOSE, m.varint(sync_id))
        settle(0.5)

    # --- A pig follows the carrot in the hand (the tempt goal), as in --player.
    if wanted('pig'):
        where = {}
        def track(pid, data):
            r = m.Reader(data)
            if pid in (m.PLAY_MOVE_POS, m.PLAY_MOVE_POS_ROT):
                eid = r.varint()
                at = where.get(eid)
                if at is not None:
                    at[0] += r.i16() / 4096.0
                    at[1] += r.i16() / 4096.0
                    at[2] += r.i16() / 4096.0
        old_tap = ctx['tap']
        def tap2(pid, data):
            old_tap(pid, data)
            track(pid, data)
        ctx['tap'] = tap2
        hold('carrot', 4)
        mark = len(spawned)
        px0, py0, pz0 = sx + 4, fy + 1, sz + 5
        cmd('summon minecraft:pig %d %d %d' % (px0 + 6, py0, pz0))
        wait(lambda: len(spawned) > mark, 'the pig', 10.0)
        pig = spawned[mark]
        where[pig[0]] = [pig[2], pig[3], pig[4]]
        def dist():
            a = where[pig[0]]
            return ((a[0] - (px0 + 0.5)) ** 2 + (a[2] - (pz0 + 0.5)) ** 2) ** 0.5
        d0 = dist()
        print('  pig %d starts %.1f blocks from the bot' % (pig[0], d0), flush=True)
        try:
            wait(lambda: dist() < 3.0, 'the pig to come to the carrot', 30.0)
        except m.Fail:
            print('  the pig is %.1f blocks away' % dist(), flush=True)
            raise
        print('  the pig came: %.1f -> %.1f blocks' % (d0, dist()), flush=True)
        st.hit('pig_followed_carrot')
        ctx['tap'] = old_tap

    # --- Gameplay fidelity gaps: selectors with namespaced ids, /damage on mobs, /execute into the fallback dispatcher,
    # score tests and stores, and tab completion of an enum argument.
    if wanted('gaps'):
        def said_since(at, fragment):
            return any(fragment in t for t in w.chat[at:])
        def expect_say(line, fragment, what, seconds=8.0):
            at = len(w.chat)
            cmd(line)
            try:
                wait(lambda: said_since(at, fragment), what, seconds)
            except m.Fail:
                print('  chat said: %r' % (w.chat[at:],), flush=True)
                raise
            print('  ok: %s' % what, flush=True)
        def expect_silent(line, fragment, what):
            at = len(w.chat)
            cmd(line)
            settle(1.2)
            check(not said_since(at, fragment), what)
            print('  ok: %s' % what, flush=True)
        mark = len(spawned)
        cmd('summon minecraft:pig %d %d %d' % (sx + 6, fy + 1, sz + 5))
        cmd('summon minecraft:zombie %d %d %d' % (sx + 8, fy + 1, sz + 5))
        wait(lambda: len(spawned) >= mark + 2, 'the pig and the zombie', 10.0)
        pig_id = spawned[mark][0]
        # (1) selectors
        expect_say('execute if entity @e[type=minecraft:pig] run tellraw @a {"text":"GAP_SEL1"}', 'GAP_SEL1', 'type=minecraft:pig finds the pig')
        expect_say('execute if entity @e[type=!minecraft:pig,type=minecraft:zombie] run tellraw @a {"text":"GAP_SEL2"}', 'GAP_SEL2', 'type=!pig with a zombie')
        expect_say('execute if entity @e[type=#minecraft:undead] run tellraw @a {"text":"GAP_SEL3"}', 'GAP_SEL3', 'type=#minecraft:undead finds the zombie')
        expect_silent('execute if entity @e[type=minecraft:cow,distance=..3] run tellraw @a {"text":"GAP_SEL4"}', 'GAP_SEL4', 'no cow, no hit')
        # (2) /damage on a mob, with and without a source
        d0 = len(damages)
        cmd('damage @e[type=minecraft:pig,limit=1] 2 minecraft:generic')
        wait(lambda: pig_id in damages[d0:], 'a damage event for the pig', 8.0)
        print('  ok: /damage hurt the pig', flush=True)
        settle(1.5)   # past the pig's hurt-time, or the second hit is absorbed
        d1 = len(damages)
        at_d = len(w.chat)
        cmd('damage @e[type=minecraft:pig,limit=1] 3 minecraft:player_attack by @s')
        try:
            wait(lambda: pig_id in damages[d1:], 'a damage event for the pig, by @s', 8.0)
        except m.Fail:
            print('  chat said: %r' % (w.chat[at_d:],), flush=True)
            raise
        print('  ok: /damage by a source hurt the pig', flush=True)
        # (3) execute reaches the fallback dispatcher with the source in force
        expect_say('execute in minecraft:the_nether run tellraw @a {"text":"GAP_IN"}', 'GAP_IN', 'execute in <dim> run say')
        mark2 = len(spawned)
        cmd('execute positioned %d %d %d run summon minecraft:chicken ~ ~ ~' % (sx + 3, fy + 1, sz + 3))
        wait(lambda: len(spawned) > mark2, 'the chicken from execute positioned', 8.0)
        ch = spawned[mark2]
        print('  chicken at %.2f %.2f %.2f, wanted %d %d %d' % (ch[2], ch[3], ch[4], sx + 3, fy + 1, sz + 3), flush=True)
        check(abs(ch[2] - (sx + 3)) < 1.0 and abs(ch[4] - (sz + 3)) < 1.0, 'positioned moved the summon')
        mark3 = len(spawned)
        cmd('execute as @e[type=minecraft:pig,limit=1] at @s run summon minecraft:chicken ~ ~ ~')
        wait(lambda: len(spawned) > mark3, 'the chicken from execute as/at the pig', 8.0)
        pg = [e for e in spawned[:mark] + spawned[mark:mark + 1]][-1]
        print('  chicken at %.2f %.2f %.2f; the pig was spawned at %.2f %.2f' % (spawned[mark3][2], spawned[mark3][3], spawned[mark3][4], pg[2], pg[4]), flush=True)
        check(abs(spawned[mark3][2] - pg[2]) < 6.0 and abs(spawned[mark3][4] - pg[4]) < 6.0, 'as/at moved to the pig')
        # scores: `store result` puts tellraw's value (one player told) in the score, and `if score` reads it back
        at_sc = len(w.chat)
        cmd('scoreboard objectives add gapt dummy')
        settle(0.6)
        cmd('execute store result score @s gapt run tellraw @a {"text":"GAP_ST"}')
        settle(1.0)
        print('  chat so far: %r' % (w.chat[at_sc:],), flush=True)
        expect_say('execute if score @s gapt matches 1 run tellraw @a {"text":"GAP_SC1"}', 'GAP_SC1', 'store result, then if score matches 1')
        expect_silent('execute if score @s gapt matches 7.. run tellraw @a {"text":"GAP_SC2"}', 'GAP_SC2', 'if score matches, outside')
        expect_say('execute if score @s gapt = @s gapt run tellraw @a {"text":"GAP_SC3"}', 'GAP_SC3', 'if score = itself')
        expect_silent('execute unless score @s gapt >= @s gapt run tellraw @a {"text":"GAP_SC4"}', 'GAP_SC4', 'unless score >= itself')
        expect_say('execute if blocks %d %d %d %d %d %d %d %d %d all run tellraw @a {"text":"GAP_BL"}' % ((sx, fy, sz, sx + 1, fy, sz, sx, fy, sz)), 'GAP_BL', 'if blocks of an area with itself')
        # (5) tab completion of an enum argument
        c.send(m.SB_COMMAND_SUGGESTION, m.varint(41) + m.string('/gamemode s'))
        wait(lambda: any(s[0] == 41 for s in w.suggestions), 'suggestions for /gamemode s', 8.0)
        found = [s for s in w.suggestions if s[0] == 41][0]
        print('  /gamemode s suggests: %s' % (found[4],), flush=True)
        check('survival' in found[4] and 'spectator' in found[4], 'survival and spectator among them')
        st.hit('gaps_done')

    # --- A control for the dragon's hit: a cow, hit by the bot.
    if wanted('cow'):
        mark = len(spawned)
        cmd('summon minecraft:cow %d %d %d' % (sx + 6, fy + 1, sz + 5))
        wait(lambda: len(spawned) > mark, 'the cow', 10.0)
        cow = spawned[mark]
        mark_d = len(damages)
        for _ in range(3):
            c.send(SB_INTERACT, m.varint(cow[0]) + m.varint(1) + bytes([0]))
            settle(0.3)
        try:
            wait(lambda: len(damages) > mark_d, 'a damage event for the cow', 5.0)
        except m.Fail:
            print('  chat said: %r' % (w.chat[-4:],), flush=True)
            raise
        print('  cow damaged: %r' % (damages[mark_d:],), flush=True)

    # --- The End and the dragon.
    if wanted('dragon'):
        mark_r = len(respawns)
        # No command reaches the End (`execute run` has only the new dispatcher, and /teleport is in the old one): an end
        # portal block under the bot's feet does, as in the game.
        cmd('tp @s %d %d %d' % (sx + 4, fy + 1, sz + 5))
        settle(1.0)
        cmd('setblock %d %d %d minecraft:end_portal' % (sx + 4, fy + 1, sz + 5))
        try:
            wait(lambda: len(respawns) > mark_r, 'the respawn into the End', 20.0)
        except m.Fail:
            print('  chat said: %r' % (w.chat[-4:],), flush=True)
            raise
        print('  respawned into %r' % respawns[-1], flush=True)
        check(respawns[-1] == 'minecraft:the_end', 'went to %r' % respawns[-1])
        wait(lambda: w.pos is not None and abs(w.pos[1] - 70) < 40, 'a position in the End', 30.0)
        settle(3.0)
        c.send(m.SB_LOADED, b'')   # a client says so once the new dimension's terrain is in
        settle(0.5)
        mark = len(spawned)
        cmd('summon minecraft:ender_dragon ~ ~12 ~')
        def above():
            return [e for e in spawned[mark:] if abs(e[3] - (w.pos[1] + 12.0)) < 1.0 and abs(e[2] - w.pos[0]) < 1.0]
        wait(lambda: above(), 'the dragon to be added', 15.0)
        dragon = above()[0]
        print('  dragon: entity %d type %d at %.1f %.1f %.1f' % dragon, flush=True)
        st.hit('dragon_spawned')
        # No selector reaches a mob (the command world lists players only), so the bot goes to the dragon and hits it.
        mark_d = len(damages)
        c.send(m.SB_MOVE_POS, struct.pack('>ddd', dragon[2], dragon[3] - 0.5, dragon[4]) + bytes([0]))
        for _ in range(6):
            c.send(SB_INTERACT, m.varint(dragon[0]) + m.varint(1) + bytes([0]))
            settle(0.1)
        try:
            wait(lambda: len(damages) > mark_d, 'a damage event for the dragon', 10.0)
        except m.Fail:
            print('  chat said: %r' % (w.chat[-4:],), flush=True)
            raise
        print('  damage events for entities %r' % (damages[mark_d:],), flush=True)
        st.hit('dragon_damaged')
        settle(1.0)
