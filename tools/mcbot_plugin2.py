"""Session for mcbot.py's --wasm-plugin2: a WebAssembly plugin (src/plugin/wit/witeventsplayer2test.aowl --write) in the server's
plugins/ folder cancels player-drop-item-event when one item is dropped (count == 1) and lets bigger drops through.

Needs --op (the bot gives itself stone). The drop is observed as the item entity the server spawns (an add-entity packet).
mcbot.py hands its own module in as `m`. Run it against a COPY of a world, with the plugin file in <server cwd>/plugins/.
"""
import time


def plugin2_session(m, c, st, w, biomes, ctx, args):
    spawned = []

    def tap(pid, data):
        if pid == m.PLAY_ADD_ENTITY:
            r = m.Reader(data)
            eid = r.varint()
            r.take(16)
            kind = r.varint()
            spawned.append((eid, kind, r.f64(), r.f64(), r.f64()))
    ctx['tap'] = tap

    def near(entry):
        # a dropped item appears at the player's eye, whatever the mobs of the loaded chunks do
        return w.pos is not None and abs(entry[2] - w.pos[0]) <= 3.0 and abs(entry[4] - w.pos[2]) <= 3.0 and abs(entry[3] - w.pos[1]) <= 4.0

    def new_near(since):
        return [e for e in spawned[since:] if near(e)]

    def wait(cond, what, seconds=10.0):
        m.pump(c, st, w, biomes, ctx, cond, what, seconds)

    def run_command(line):
        print('  /%s' % line, flush=True)
        c.send(m.SB_CHAT_COMMAND, m.string(line))

    def stone_slot():
        found = [i for i, s in enumerate(w.window0) if s == (5, m.STONE_ITEM)]
        return found[0] if found else None

    def settle(seconds):
        end = time.time() + seconds
        m.pump(c, st, w, biomes, ctx, lambda: time.time() > end, 'a quiet moment', seconds + 5.0)

    def drop(status):
        c.send(m.SB_ACTION, m.varint(status) + m.block_pos(0, 0, 0) + bytes([0]) + m.varint(0))

    def give_and_hold():
        run_command('give @s stone 5')
        settle(1.0)
        wait(lambda: stone_slot() is not None, 'five stone in the inventory')
        at = stone_slot()
        m.check(36 <= at <= 44, 'the stone went to window slot %d, not the hotbar' % at)
        c.send(m.SB_CARRIED, m.struct.pack('>h', at - 36))
        settle(0.5)
        print('  holding 5 stone in hotbar %d' % (at - 36))

    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    wait(lambda: w.window0 is not None, 'the inventory')
    settle(1.0)

    # a drop of the whole stack (count 5): the plugin lets it through, so the item entity appears
    give_and_hold()
    st.hit('plugin2_given')
    before = len(spawned)
    drop(3)
    wait(lambda: new_near(before), 'the item entity of the dropped stack')
    print('  the dropped stack spawned entity type %d next to the player' % new_near(before)[0][1])
    st.hit('plugin2_drop_stack_allowed')

    # a drop of one item (count 1): the plugin cancels it, so nothing spawns and the stack stays whole
    settle(0.5)
    give_and_hold()
    settle(1.0)
    before = len(spawned)
    drop(4)
    settle(2.5)
    m.check(not new_near(before), 'the plugin cancelled a drop of one stone but %r spawned next to the player' % (new_near(before),))
    print('  dropping one stone was cancelled: nothing spawned next to the player')
    st.hit('plugin2_drop_one_cancelled')
