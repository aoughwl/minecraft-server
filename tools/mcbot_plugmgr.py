"""Session for mcbot.py's --plugmgr: the plugin manager at run time, over the wire (src/plugin/pluginserver.aowl).

The server starts with plugins/wasidemo.wasm (a WASI plugin, src/plugin/wit/witwasitest.aowl --write) and the chat plugin of
src/plugin/pluginhostplayertest.aowl --write sits in staging/chatplug.wasm, which cancels chat that starts with 'x'. The bot
is an operator. It checks that: chat starting with x passes before the chat plugin is loaded; `/plugin list` names the WASI
plugin; `/plugin load staging/chatplug.wasm` loads it, and chat starting with x is cancelled; `/plugin unload` takes it away
again and chat starting with x passes; `/plugin reload` of the WASI plugin works; a bad path fails with the error message.
The caller reads the server log for the WASI plugin's stdout line (it appears at start-up and again after the reload).

mcbot.py hands its own module in as `m`. Run it against a COPY of a world.
"""
import struct
import time


def plugmgr_session(m, c, st, w, biomes, ctx, args):
    def wait(cond, what, seconds=10.0):
        m.pump(c, st, w, biomes, ctx, cond, what, seconds)

    def say(message):
        c.send(m.SB_CHAT, m.string(message) + struct.pack('>qq', int(time.time() * 1000), 42) + bytes([0]) + m.varint(0) +
               bytes([0, 0, 0]) + bytes([0]))

    def run_command(line):
        print('  /%s' % line, flush=True)
        c.send(m.SB_CHAT_COMMAND, m.string(line))

    def heard(fragment, since=0):
        return any(fragment in said for said in w.chat[since:])

    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    wait(lambda: 'nodes' in m.COMMAND_TREE, 'the command tree')
    root = m.COMMAND_TREE['nodes'][m.COMMAND_TREE['root']]
    names = sorted(m.COMMAND_TREE['nodes'][i]['name'] for i in root['children'])
    m.check('plugin' in names, '/plugin is not in the command tree: %s' % names)
    st.hit('plugmgr_tree')

    stamp = int(time.time())
    before = 'xbefore %d' % stamp
    say(before)
    wait(lambda: heard(before), 'x chat passing before the chat plugin is loaded')
    st.hit('plugmgr_chat_before')

    at = len(w.chat)
    run_command('plugin list')
    wait(lambda: heard('There is 1 plugin loaded', at), 'the plugin list')
    m.check(heard('wasidemo', at), 'the list does not name the WASI plugin: %r' % w.chat[at:])
    print('  said: %r' % w.chat[at:])
    st.hit('plugmgr_list')

    at = len(w.chat)
    run_command('plugin load staging/nothing.wasm')
    wait(lambda: heard('Failed to load plugin staging/nothing.wasm', at), 'the error for a plugin that is not there')
    print('  said: %r' % w.chat[at:])
    st.hit('plugmgr_load_error')

    at = len(w.chat)
    run_command('plugin load staging/chatplug.wasm')
    wait(lambda: heard('loaded successfully', at), 'the load answer')
    print('  said: %r' % w.chat[at:])
    st.hit('plugmgr_loaded')
    run_command('plugin load staging/chatplug.wasm')
    wait(lambda: heard('is already loaded', at), 'the answer to loading it twice')
    st.hit('plugmgr_already_loaded')

    cancelled = 'xcancel me %d' % stamp
    say(cancelled)
    after = 'hello after %d' % stamp
    say(after)
    wait(lambda: heard(after), 'the chat after the cancelled one')
    m.check(not heard(cancelled), 'the chat plugin was loaded but %r was broadcast' % cancelled)
    st.hit('plugmgr_chat_cancelled')

    at = len(w.chat)
    run_command('plugin unload staging/chatplug.wasm')
    wait(lambda: heard('unloaded successfully', at), 'the unload answer')
    print('  said: %r' % w.chat[at:])
    st.hit('plugmgr_unloaded')
    unloaded = 'xunloaded %d' % stamp
    say(unloaded)
    wait(lambda: heard(unloaded), 'x chat passing again after the unload')
    st.hit('plugmgr_chat_after_unload')

    at = len(w.chat)
    run_command('plugin reload plugins/wasidemo.wasm')
    wait(lambda: heard('reloaded successfully', at), 'the reload answer')
    print('  said: %r' % w.chat[at:])
    st.hit('plugmgr_reloaded')
