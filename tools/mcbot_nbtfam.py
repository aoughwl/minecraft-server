"""Sessions for mcbot.py's --nbtfam and --nbtfam-verify: /data on storage and a chest, /execute store, over the wire.

mcbot.py hands its own module in as `m`. The bot must be an operator of level 4 on a COPY of a world.
--nbtfam: /data modify storage, /data get with a scale, /execute store result storage, a chest's Items read and written
through /data ... block and /execute store result block; the numbers it saw are written to --save.
--nbtfam-verify: after the server was restarted, the same storage and the same chest still hold them.
"""
import json
import socket
import time


def _make(m, c, st, w, biomes, ctx):
    def settle(seconds=0.6):
        end = time.time() + seconds
        while time.time() < end:
            try:
                pid, r = c.recv()
            except socket.timeout:
                continue
            m.one_packet(c, st, w, biomes, ctx, pid, r)

    def run(line, key, since_override=None, seconds=12.0):
        """Sends the command and waits for a chat line holding `key` (a translation key); returns the joined text."""
        at = len(w.chat) if since_override is None else since_override
        print('  /%s' % line, flush=True)
        c.send(m.SB_CHAT_COMMAND, m.string(line))
        m.pump(c, st, w, biomes, ctx, lambda: any(key in said for said in w.chat[at:]), 'chat with %s after /%s' % (key, line), seconds)
        return next(said for said in w.chat[at:] if key in said)

    def fails(line, seconds=4.0):
        """Sends a command that must NOT say a success: returns the chat it caused."""
        at = len(w.chat)
        print('  /%s' % line, flush=True)
        c.send(m.SB_CHAT_COMMAND, m.string(line))
        settle(seconds)
        return ' | '.join(w.chat[at:])

    m.pump(c, st, w, biomes, ctx, lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    m.pump(c, st, w, biomes, ctx, lambda: w.health is not None, 'health')
    c.send(m.SB_CHANGE_GAME_MODE, m.varint(1))
    m.pump(c, st, w, biomes, ctx, lambda: w.mode == 1, 'creative')
    return settle, run, fails


def nbtfam_session(m, c, st, w, biomes, ctx, args):
    check = m.check
    settle, run, fails = _make(m, c, st, w, biomes, ctx)
    px, py, pz = int(w.pos[0] // 1), int(w.pos[1] // 1), int(w.pos[2] // 1)
    m.pump(c, st, w, biomes, ctx, lambda: w.block(px, py - 1, pz) is not None, 'the chunk under the player', 30.0)
    bx, by, bz = px + 3, py, pz + 3
    out = {'chest': [bx, by, bz]}

    # --- storage: modify, get, merge, remove
    run('data modify storage nbtfam:test count set value 41', 'commands.data.storage.modified')
    run('data modify storage nbtfam:test list set value [1,2]', 'commands.data.storage.modified')
    run('data modify storage nbtfam:test list append value 3', 'commands.data.storage.modified')
    run('data modify storage nbtfam:test list prepend value 0', 'commands.data.storage.modified')
    run('data modify storage nbtfam:test list insert 2 value 99', 'commands.data.storage.modified')
    said = run('data get storage nbtfam:test list', 'commands.data.storage.query')
    print('    ->', said, flush=True)
    for needle in ('0', '1', '99', '2', '3'):
        check(needle in said, 'list element %s in %r' % (needle, said))
    said = run('data get storage nbtfam:test count 2', 'commands.data.storage.get')
    check('82' in said and '2.00' in said, 'get with a scale: %r' % said)
    said = run('data modify storage nbtfam:test str set value "abcdef"', 'commands.data.storage.modified')
    run('data modify storage nbtfam:test part set string storage nbtfam:test str 1 4', 'commands.data.storage.modified')
    said = run('data get storage nbtfam:test part', 'commands.data.storage.query')
    check('bcd' in said, 'string source 1..4: %r' % said)
    run('data merge storage nbtfam:test {merged:1b}', 'commands.data.storage.modified')
    run('data remove storage nbtfam:test merged', 'commands.data.storage.modified')
    said = fails('data remove storage nbtfam:test merged')
    check('commands.data.merge.failed' in said, 'removing twice fails: %r' % said)

    # --- /execute store result storage
    run('execute store result storage nbtfam:test fromexec int 1 run data get storage nbtfam:test count',
        'commands.data.storage.query')
    said = run('data get storage nbtfam:test fromexec', 'commands.data.storage.query')
    check('41' in said, 'execute store result storage: %r' % said)
    run('execute store result storage nbtfam:test halved double 0.5 run data get storage nbtfam:test count',
        'commands.data.storage.query')
    said = run('data get storage nbtfam:test halved', 'commands.data.storage.query')
    check('20.5' in said, 'store with a scale as a double: %r' % said)
    said = run('execute if data storage nbtfam:test halved run data get storage nbtfam:test count', 'commands.data.storage.query')
    said = fails('execute unless data storage nbtfam:test halved run data get storage nbtfam:test count')
    check('commands.data.storage.query' not in said, 'unless data on a present path runs nothing: %r' % said)

    # --- a chest
    run('setblock %d %d %d minecraft:chest' % (bx, by, bz), 'commands.setblock.success')
    settle(1.0)
    run('item replace block %d %d %d container.0 with minecraft:diamond 5' % (bx, by, bz), 'commands.item.block.set.success')
    said = run('data get block %d %d %d Items[0].id' % (bx, by, bz), 'commands.data.block.query')
    check('diamond' in said, 'chest slot 0 holds a diamond: %r' % said)
    said = run('data get block %d %d %d Items[0].count' % (bx, by, bz), 'commands.data.block.query')
    check('5' in said, 'count 5: %r' % said)
    run('data modify block %d %d %d Items[0].count set value 9' % (bx, by, bz), 'commands.data.block.modified')
    said = run('data get block %d %d %d Items[0].count' % (bx, by, bz), 'commands.data.block.query')
    check('9' in said, 'count 9 after modify: %r' % said)
    # store the length of the storage list (5) into the chest
    run('execute store result block %d %d %d Items[0].count int 1 run data get storage nbtfam:test list' % (bx, by, bz),
        'commands.data.storage.query')
    said = run('data get block %d %d %d Items[0].count' % (bx, by, bz), 'commands.data.block.query')
    check('5' in said, 'execute store result block: %r' % said)
    said = fails('data get block %d %d %d Items' % (bx, by + 5, bz))
    check('commands.data.block.invalid' in said, 'no block entity up there: %r' % said)
    run('data get block %d %d %d' % (bx, by, bz), 'commands.data.block.query')

    if args.save:
        with open(args.save, 'w') as f:
            json.dump(out, f)
    print('nbtfam: all checks passed', flush=True)


def nbtfam_verify_session(m, c, st, w, biomes, ctx, args):
    check = m.check
    settle, run, fails = _make(m, c, st, w, biomes, ctx)
    saved = json.load(open(args.nbtfam_verify))
    bx, by, bz = saved['chest']
    said = run('data get storage nbtfam:test count', 'commands.data.storage.query')
    check('41' in said, 'storage count survived the restart: %r' % said)
    said = run('data get storage nbtfam:test fromexec', 'commands.data.storage.query')
    check('41' in said, 'the execute-stored value survived: %r' % said)
    said = run('data get storage nbtfam:test part', 'commands.data.storage.query')
    check('bcd' in said, 'the string survived: %r' % said)
    m.pump(c, st, w, biomes, ctx, lambda: w.block(bx, by, bz) is not None, 'the chunk of the chest', 30.0)
    said = run('data get block %d %d %d Items[0].count' % (bx, by, bz), 'commands.data.block.query')
    check('5' in said, 'the chest count written by execute store survived: %r' % said)
    print('nbtfam-verify: all checks passed', flush=True)
