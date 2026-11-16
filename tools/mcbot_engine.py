"""Session for mcbot.py's --engine-plugin: a JavaScript plugin on the aoughwl engine (tools/engine_live_plugin.js, copied to
<server cwd>/plugins/live/main.js) acts on the connected player from chat messages.

    actions: welcome message on join (player_message_to), 'gm1' sets creative (player_set_gamemode), 'tp' teleports to
             100 80 100 (player_teleport), 'pos' reports the x it sees (player_pos), 'x...' is cancelled.
    kick:    'bye' kicks the player (player_kick); the connection must then close with the plugin's reason, and the server
             must still answer a status ping.

mcbot.py hands its own module in as `m`. Run it against a server started in a directory holding plugins/live/main.js and an
online_mode = false pumpkin.toml.
"""
import os
import socket
import struct
import time


def engine_session(m, c, st, w, biomes, ctx, args):
    def wait(cond, what, seconds=15.0):
        m.pump(c, st, w, biomes, ctx, cond, what, seconds)

    def say(message):
        c.send(m.SB_CHAT, m.string(message) + struct.pack('>qq', int(time.time() * 1000), 42) + bytes([0]) + m.varint(0) +
               bytes([0, 0, 0]) + bytes([0]))

    wait(lambda: w.pos is not None and ctx['chunk_parsed'], 'a position and a chunk', 40.0)
    wait(lambda: any('engine welcome' in said for said in w.chat), 'the welcome message the engine plugin sends on join')
    print('  heard: %s' % [said for said in w.chat if 'engine welcome' in said][0], flush=True)
    st.hit('engine_welcome')

    if args.engine_plugin == 'events':
        # run with --play --op: play_session has already walked and placed a stone by now
        wait(lambda: any('engine saw a move' in said for said in w.chat), 'on_player_move reported through chat')
        st.hit('engine_move_event')
        wait(lambda: any('engine saw place minecraft:stone' in said for said in w.chat), 'on_block_place reported a stone')
        print('  heard: %s' % [said for said in w.chat if 'engine saw place' in said][0], flush=True)
        st.hit('engine_place_event')
        wait(lambda: any('engine broadcast' in said for said in w.chat), 'server_broadcast from a scheduled task', 20.0)
        st.hit('engine_broadcast')
        print('  engine plugin events ok', flush=True)
        return

    if args.engine_plugin == 'actions':
        m.check(w.mode != 1, 'the bot starts in creative (%r), the gamemode check would prove nothing' % (w.mode,))
        say('gm1')
        wait(lambda: w.mode == 1, 'creative mode set by player_set_gamemode')
        st.hit('engine_gamemode')

        say('tp')
        wait(lambda: w.pos is not None and abs(w.pos[0] - 100.0) < 1.0 and abs(w.pos[2] - 100.0) < 1.0,
             'the teleport of player_teleport')
        print('  teleported to %r' % (w.pos,), flush=True)
        st.hit('engine_teleport')

        say('pos')
        wait(lambda: any('engine pos 100' in said for said in w.chat), 'player_pos reported x = 100')
        st.hit('engine_pos')

        cancelled = 'xnot broadcast %d' % int(time.time())
        say(cancelled)
        after = 'hello after %d' % int(time.time())
        say(after)
        wait(lambda: any(after in said for said in w.chat), 'a message the plugin lets through')
        m.check(not any(cancelled in said for said in w.chat), 'the plugin cancelled %r but it was broadcast' % cancelled)
        st.hit('engine_chat_cancelled')
        print('  engine plugin actions ok', flush=True)
        return

    # kick: the next thing the server does is close the connection
    say('bye')
    kicked = False
    deadline = time.time() + 15.0
    while time.time() < deadline:
        try:
            pid, r = c.recv()
        except socket.timeout:
            continue
        except (ConnectionError, OSError, m.Fail):
            kicked = True
            break
        try:
            m.one_packet(c, st, w, biomes, ctx, pid, r)
        except m.Fail as e:
            # one_packet raises on a play disconnect; the one wanted here carries the plugin's reason
            m.check('engine kick' in str(e), 'disconnected for another reason: %s' % e)
            print('  the server disconnected us: %s' % str(e)[:80], flush=True)
            kicked = True
            break
    m.check(kicked, 'the connection stayed open after player_kick')
    print('  the connection was closed by player_kick', flush=True)
    st.hit('engine_kick')
    m.status_ping(args.host, args.port)
    print('  the server still answers a status ping', flush=True)
    st.hit('engine_server_alive_after_kick')
    print('  engine plugin kick ok', flush=True)
    for name in st.missing():
        # the run ended early on purpose: the stages after play (stayed_up, clean_disconnect) belong to a full run
        pass
    os._exit(0)
