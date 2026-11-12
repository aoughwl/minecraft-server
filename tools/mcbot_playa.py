"""Sessions for mcbot.py's --playa act and --playa listen: the serverbound play packets of the java handlers, over the wire.

act: as an operator in creative mode, a stack is shift-clicked from the hotbar into the main inventory, a picked-up stack is
dragged (a left quick-craft) over two slots and splits evenly, a command is tab-completed, and a chat message is sent.
listen: a second bot that must hear the actor's chat message as a system chat message.
mcbot.py hands its own module in as `m`. The bot must be an operator of level 4 on a COPY of a world.
Every click carries a stale revision, which makes the server answer with the whole window: that is what shows what it did.
"""
import struct

SB_CONTAINER_CLICK = None
CHAT_TEXT = 'playa chat line 1'


def _pump(m, c, st, w, biomes, ctx, until, what, seconds=10.0):
    m.pump(c, st, w, biomes, ctx, until, what, seconds)


def playa_session(m, c, st, w, biomes, ctx, args):
    wait = lambda cond, what, seconds=10.0: _pump(m, c, st, w, biomes, ctx, cond, what, seconds)
    varint, check = m.varint, m.check
    stone = m.STONE_ITEM
    import time
    t0 = time.time()
    if args.playa == 'listen':
        ctx['tap'] = lambda pid, data: print('  [%.1fs] packet 0x%02x (%d bytes)' % (time.time() - t0, pid, len(data)), flush=True) if pid in (0x77, 0x3f, 0x44, 0x45, 0x3e, 0x02) else None
    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 60.0)
    wait(lambda: w.health is not None, 'health')
    if args.playa == 'listen':
        try:
            wait(lambda: any(CHAT_TEXT in said for said in w.chat), 'the other bot chatting', 70.0)
        except m.Fail:
            print('  chat heard: %r; packets by id %r' % (w.chat, sorted(ctx['counts'].items())), flush=True)
            raise
        print('  heard: %r' % [s for s in w.chat if CHAT_TEXT in s], flush=True)
        st.hit('pa_chat_heard')
        return

    c.send(m.SB_CHANGE_GAME_MODE, varint(1))
    wait(lambda: w.mode == 1, 'creative')

    def click(slot, button, mode, changed=0):
        w.window0 = None
        c.send(m.SB_CONTAINER_CLICK, varint(0) + varint(w.state_id + 1000) + struct.pack('>h', slot) + struct.pack('>b', button) +
               varint(mode) + varint(0) + bytes([0]))
        wait(lambda: w.window0 is not None, 'the window after a click')

    # Empty the inventory by creative slots, then 64 stone in hotbar slot 1 (window slot 37).
    for slot in range(9, 46):
        c.send(m.SB_CREATIVE, struct.pack('>h', slot) + m.write_slot(0, 0))
    c.send(m.SB_CREATIVE, struct.pack('>h', 37) + m.write_slot(64, stone))
    # Shift-click (mode 1) the hotbar stack: it goes to the first free main inventory slot, 9.
    click(37, 0, 1)
    print('  after shift-click: slot 37 %s, slot 9 %s' % (w.window0[37], w.window0[9]), flush=True)
    check(w.window0[37] == (0, 0) and w.window0[9] == (64, stone), 'shift-click moved %s, %s' % (w.window0[37], w.window0[9]))
    st.hit('pa_shift_click')

    # Pick the stack up (mode 0), then drag it (mode 5) over slots 10 and 11: button 0 starts a left drag, 1 adds a slot, 2 ends.
    click(9, 0, 0)
    check(w.cursor == (64, stone), 'picked up %s' % (w.cursor,))
    click(-999, 0, 5)
    click(10, 1, 5)
    click(11, 1, 5)
    click(-999, 2, 5)
    print('  after the drag: slots 10, 11 = %s, %s, cursor %s' % (w.window0[10], w.window0[11], w.cursor), flush=True)
    check(w.window0[10] == (32, stone) and w.window0[11] == (32, stone) and w.cursor == (0, 0),
          'the drag split %s, %s, cursor %s' % (w.window0[10], w.window0[11], w.cursor))
    st.hit('pa_drag_split')

    # Tab completion: the range is the last word, from its byte + 2 (the slash is dropped) for its length. /difficulty is a
    # fallback command, /kill is on the brigadier dispatcher.
    for ident, line, start, length, want in ((21, '/difficulty e', 12, 1, 'easy'), (22, '/kill @', 6, 1, '@s')):
        c.send(m.SB_COMMAND_SUGGESTION, varint(ident) + m.string(line))
        wait(lambda: any(s[0] == ident for s in w.suggestions), 'the suggestions for ' + line)
        got = [s for s in w.suggestions if s[0] == ident][0]
        print('  %s suggests start %d length %d: %s' % (line, got[2], got[3], got[4]), flush=True)
        check(got[2] == start and got[3] == length, '%s: range start %d length %d' % (line, got[2], got[3]))
        check(want in got[4], '%s: %r is not among %r' % (line, want, got[4]))
    # A line with no space has no last word: no answer is sent, and the server goes on.
    c.send(m.SB_COMMAND_SUGGESTION, varint(23) + m.string('/diffic'))
    st.hit('pa_tab_complete')

    # Chat, unsigned as aoughwl.mcnet sends it; the other bot must hear it as well.
    import time
    wait(lambda: True, '', 1.0)
    time.sleep(3.0)  # the listener is slow to read the join flood: the line is sent once it has been in the world a while
    c.send(m.SB_CHAT_COMMAND, m.string('tp @s PlayHear'))
    time.sleep(2.0)
    wait(lambda: True, '', 1.0)
    print('  DEBUG tp said: %r' % (w.chat[-3:],), flush=True)
    c.send(m.SB_CHAT, m.string(CHAT_TEXT) + struct.pack('>qq', int(time.time() * 1000), 42) + bytes([0]) + varint(0) + bytes([0, 0, 0]) + bytes([0]))
    wait(lambda: any(CHAT_TEXT in said for said in w.chat), 'our chat message back')
    st.hit('pa_chat_sent')
