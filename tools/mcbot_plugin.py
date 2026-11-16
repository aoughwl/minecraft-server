"""Session for mcbot.py's --wasm-plugin: a WebAssembly plugin (src/plugin/pluginhostplayertest.aowl --write) in the server's
plugins/ folder sends a "welcome!" system message to a joining player and cancels chat messages that start with 'x'.

mcbot.py hands its own module in as `m`. Run it against a COPY of a world, with the plugin file in <server cwd>/plugins/.
"""
import struct
import time


def plugin_session(m, c, st, w, biomes, ctx, args):
    def wait(cond, what, seconds=10.0):
        m.pump(c, st, w, biomes, ctx, cond, what, seconds)

    def say(message):
        c.send(m.SB_CHAT, m.string(message) + struct.pack('>qq', int(time.time() * 1000), 42) + bytes([0]) + m.varint(0) +
               bytes([0, 0, 0]) + bytes([0]))

    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    wait(lambda: any('welcome!' in said for said in w.chat), 'the welcome message the plugin sends on join')
    print('  heard: %s' % [said for said in w.chat if 'welcome!' in said][0])
    st.hit('plugin_welcome')

    stamp = int(time.time())
    passes = 'hello plugin %d' % stamp
    say(passes)
    wait(lambda: any(passes in said for said in w.chat), 'a chat message the plugin lets through')
    st.hit('plugin_chat_passes')

    cancelled = 'xcancel me %d' % stamp
    say(cancelled)
    after = 'hello after %d' % stamp
    say(after)
    wait(lambda: any(after in said for said in w.chat), 'the message sent after the cancelled one')
    m.check(not any(cancelled in said for said in w.chat), 'the plugin cancelled %r but the server broadcast it' % cancelled)
    print('  %r was never broadcast, %r was' % (cancelled, after))
    st.hit('plugin_chat_cancelled')
