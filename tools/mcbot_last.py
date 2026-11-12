"""Sessions for mcbot.py's --last: the last block drafts over the wire.

mcbot.py hands its own module in as `m`. The bot must be an operator of level 4 on a COPY of a world.
--last: a command block set with the Set Command Block packet runs its command when a redstone block powers it, and a chain
command block behind it runs after it; a comparator reads a water cauldron; a poppy goes into a flower pot; a dragon egg
jumps when it is used.
"""
import socket
import struct
import time

from mcbot_c2 import wire_name


def last_session(m, c, st, w, biomes, ctx, args):
    check = m.check
    seq = [700]

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

    def name_at(x, y, z):
        return wire_name(m, w.block(x, y, z))

    def use_on(x, y, z, face=1):
        seq[0] += 1
        c.send(m.SB_USE_ON, m.varint(0) + m.block_pos(x, y, z) + m.varint(face) + struct.pack('>fff', 0.5, 1.0, 0.5) +
               bytes([0, 0]) + m.varint(seq[0]))

    def set_command_block(x, y, z, command, mode, flags):
        # Set Command Block: position, command, mode (0 chain, 1 repeating, 2 impulse), flags (1 track, 2 conditional, 4 auto).
        c.send(53, m.block_pos(x, y, z) + m.string(command) + m.varint(mode) + struct.pack('>b', flags))

    m.pump(c, st, w, biomes, ctx, lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    m.pump(c, st, w, biomes, ctx, lambda: w.health is not None, 'health')
    c.send(m.SB_CHANGE_GAME_MODE, m.varint(1))
    m.pump(c, st, w, biomes, ctx, lambda: w.mode == 1, 'creative')
    px, py, pz = int(w.pos[0] // 1), int(w.pos[1] // 1), int(w.pos[2] // 1)
    m.pump(c, st, w, biomes, ctx, lambda: w.block(px, py - 1, pz) is not None, 'the chunk under the player', 30.0)
    sx, fy, sz = px + 2, py - 1, pz + 2
    cmd('fill %d %d %d %d %d %d minecraft:air' % (sx - 1, fy + 1, sz - 1, sx + 12, fy + 6, sz + 8))
    cmd('fill %d %d %d %d %d %d minecraft:stone' % (sx - 1, fy, sz - 1, sx + 12, fy, sz + 8))
    cmd('tp @s %d %d %d' % (sx + 4, fy + 1, sz + 6))
    settle(2.0)
    print('  stage: floor %s, air %s' % (name_at(sx + 4, fy, sz + 6), name_at(sx + 4, fy + 3, sz + 6)), flush=True)
    m.pump(c, st, w, biomes, ctx, lambda: name_at(sx + 4, fy, sz + 6) == 'stone' and name_at(sx + 4, fy + 3, sz + 6) == 'air',
           'the stage', 30.0)
    y = fy + 1

    cmd('weather clear')   # the copied world may be mid-rain, which is not what this scenario is about
    settle(0.5)
    # --- A command block and a chain block behind it, east of the impulse block.
    bx, bz = sx, sz
    cmd('setblock %d %d %d minecraft:command_block[facing=east]' % (bx, y, bz))
    cmd('setblock %d %d %d minecraft:chain_command_block[facing=east]' % (bx + 1, y, bz))
    settle(1.0)
    print('  command block: %s, chain: %s' % (name_at(bx, y, bz), name_at(bx + 1, y, bz)), flush=True)
    check(name_at(bx, y, bz) == 'command_block', 'no command block: %s' % name_at(bx, y, bz))
    check(name_at(bx + 1, y, bz) == 'chain_command_block', 'no chain command block: %s' % name_at(bx + 1, y, bz))
    set_command_block(bx, y, bz, '/setblock %d %d %d minecraft:gold_block' % (bx, y + 2, bz), 2, 0)
    set_command_block(bx + 1, y, bz, 'setblock %d %d %d minecraft:iron_block' % (bx + 1, y + 2, bz), 0, 4)
    settle(1.0)
    check(name_at(bx, y + 2, bz) == 'air', 'the command ran before the block was powered')
    # Power the impulse block from behind (west of it).
    cmd('setblock %d %d %d minecraft:redstone_block' % (bx - 1, y, bz))
    m.pump(c, st, w, biomes, ctx, lambda: name_at(bx, y + 2, bz) == 'gold_block', 'the command block to run its command', 8.0)
    print('  after power: %s above the command block' % name_at(bx, y + 2, bz), flush=True)
    m.pump(c, st, w, biomes, ctx, lambda: name_at(bx + 1, y + 2, bz) == 'iron_block', 'the chain block to run after it', 8.0)
    print('  the chain block ran: %s' % name_at(bx + 1, y + 2, bz), flush=True)

    # --- A comparator reads a water cauldron: the lamp beyond it lights.
    cx, cz = sx + 3, sz + 3
    cmd('setblock %d %d %d minecraft:redstone_lamp' % (cx + 2, y, cz))
    cmd('setblock %d %d %d minecraft:comparator[facing=west]' % (cx + 1, y, cz))
    settle(1.0)
    lamp_off = w.block(cx + 2, y, cz)
    # The cauldron arrives last: its neighbour update is what wakes the comparator.
    cmd('setblock %d %d %d minecraft:water_cauldron[level=2]' % (cx, y, cz))
    settle(2.0)
    lamp_on = w.block(cx + 2, y, cz)
    print('  lamp %s -> %s' % (lamp_off, lamp_on), flush=True)
    check(name_at(cx + 2, y, cz) == 'redstone_lamp', 'the lamp is %s' % name_at(cx + 2, y, cz))
    check(lamp_on != lamp_off, 'the lamp did not light from the cauldron through the comparator')

    # --- A poppy into a flower pot with the item in hand.
    fx, fz = sx + 6, sz + 3
    cmd('setblock %d %d %d minecraft:flower_pot' % (fx, y, fz))
    cmd('item replace entity @s weapon.mainhand with minecraft:poppy 1')
    settle(1.0)
    use_on(fx, y, fz)
    m.pump(c, st, w, biomes, ctx, lambda: name_at(fx, y, fz) == 'potted_poppy', 'the pot to take the poppy', 8.0)
    print('  flower pot: %s' % name_at(fx, y, fz), flush=True)

    # --- A dragon egg jumps when used (empty hand).
    cmd('item replace entity @s weapon.mainhand with minecraft:air')
    ex, ez = sx + 9, sz + 3
    cmd('setblock %d %d %d minecraft:dragon_egg' % (ex, y, ez))
    settle(1.0)
    check(name_at(ex, y, ez) == 'dragon_egg', 'no dragon egg: %s' % name_at(ex, y, ez))
    use_on(ex, y, ez)
    m.pump(c, st, w, biomes, ctx, lambda: name_at(ex, y, ez) != 'dragon_egg', 'the egg to leave', 8.0)
    print('  the egg left its place (now %s there)' % name_at(ex, y, ez), flush=True)
    settle(0.5)
