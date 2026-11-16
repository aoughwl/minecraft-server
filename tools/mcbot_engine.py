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
    if args.engine_plugin == 'showcase':
      try:
            # the server runs examples/hello-world (aowlmony) and examples/hello-world-js; the bot is an operator (data/ops.json)
            name = args.name

            def command(line):
                c.send(m.SB_CHAT_COMMAND, m.string(line))

            def heard(fragment, since=0):
                return any(fragment in said for said in w.chat[since:])

            def expect(fragment, what, seconds=15.0):
                wait(lambda: heard(fragment), what, seconds)
                print('  heard: %s' % [said for said in w.chat if fragment in said][0], flush=True)

            status = m.status_ping(args.host, args.port)
            motd = status.get('description')
            motd = motd.get('text', '') if isinstance(motd, dict) else str(motd)
            m.check('hello-world server' in motd, 'the plugin did not set the server list MOTD: %r' % motd)
            print('  server list says: %s' % motd, flush=True)
            expect('Welcome, %s' % name, 'the aowlmony join message')
            expect('%s joined the game' % name, 'the join broadcast')
            st.hit('showcase_join')

            command('hello')
            expect('This plugin:', '/hello')
            command('jsping')
            expect('pong from JavaScript', '/jsping (the JavaScript plugin)')
            st.hit('showcase_commands')

            say('!ping')
            expect('pong!', 'the !ping chat command')
            say('!js')
            expect('This answer is written in JavaScript', 'the JavaScript chat feature')
            say('this has a badword in it')
            expect('Please keep it friendly', 'the chat filter')
            marker = 'smile test %d' % int(time.time())
            say(marker + ' :)')
            expect(marker + ' (smile)', 'the chat rewrite')
            st.hit('showcase_chat')

            command('where')
            expect('You are at', '/where')
            command('gm 1')
            wait(lambda: w.mode == 1, 'creative from /gm 1')
            expect('survival -> creative', 'the game mode change notice')
            command('tpme 100 80 100')
            wait(lambda: w.pos is not None and abs(w.pos[0] - 100.0) < 1.0 and abs(w.pos[2] - 100.0) < 1.0, 'the /tpme teleport')
            expect('Teleported to 100, 80, 100', '/tpme reply')
            st.hit('showcase_actions')

            command('remind 2 drink water')
            expect('I will remind you in 2 seconds', '/remind')
            expect('Reminder: drink water', 'the reminder two seconds later', 20.0)
            command('stats')
            expect('You joined 1 time', '/stats')
            command('online')
            expect('1 player online', '/online')
            command('announce hello everyone')
            expect('[%s] hello everyone' % name, '/announce')
            st.hit('showcase_tasks')

            command('block 2 70 2 minecraft:gold_block')
            expect('Placed minecraft:gold_block', '/block places a block from a plugin')
            command('block 2 70 2')
            expect('Block at 2 70 2: minecraft:gold_block', '/block reads it back')
            command('block 4 70 4 minecraft:bedrock')
            command('block 4 70 4')
            expect('Block at 4 70 4: minecraft:air', 'the block change event keeps bedrock out')
            c.send(m.SB_ACTION, m.varint(6) + m.block_pos(0, 0, 0) + bytes([0]) + m.varint(0))
            expect('Hands stay put.', 'the swap hands event')
            command('effect give %s minecraft:slowness 30 1' % name)
            expect('Slowness for 600 ticks', 'the potion effect event')
            command('pistonme 8 70 8')
            expect('Piston extends', 'the piston event')
            c.send(m.SB_COMMAND_SUGGESTION, m.varint(31) + m.string('/hello '))
            wait(lambda: any(s[0] == 31 for s in w.suggestions), 'suggestions for /hello', 15.0)
            offered = [s for s in w.suggestions if s[0] == 31][0][4]
            m.check('world' in offered and 'everyone' in offered, 'the tab complete event added nothing: %s' % offered)
            print('  /hello suggests %s' % offered, flush=True)
            command('tpme 0 66 0')
            expect('Teleported to 0, 66, 0', 'back near spawn, where the chunks are loaded')
            command('block 2 66 0 minecraft:crafting_table')
            expect('Placed minecraft:crafting_table', 'a crafting table to open')
            c.send(m.SB_USE_ON, m.varint(0) + m.block_pos(2, 66, 0) + m.varint(1) + struct.pack('>fff', 0.5, 1.0, 0.5) + bytes([0, 0]) + m.varint(7))
            expect('opens for %s' % name, 'the inventory open event')
            command('tpme 0 66 0')
            expect('Teleported to 0, 66, 0', 'back near spawn, where the chunks are loaded')
            command('giveme minecraft:snowball 1')
            expect('You now carry 1 of minecraft:snowball', 'a snowball to throw')
            c.send(m.SB_CARRIED, struct.pack('>h', 0))
            # look straight down, so the snowball lands at the bot's feet where the chunks are loaded
            c.send(m.SB_MOVE_POS_ROT, struct.pack('>dddff', w.pos[0], w.pos[1], w.pos[2], 0.0, 90.0) + bytes([1]))
            time.sleep(0.5)
            c.send(m.SB_USE, m.varint(0) + m.varint(90) + struct.pack('>ff', 0.0, 90.0))
            expect('Snowball hit', 'the projectile hit event')
            command('giveme minecraft:diamond 5')
            expect('You now carry 5 of minecraft:diamond', 'inventory: a plugin gives items and counts them')
            command('summon minecraft:cow 5 70 5')
            expect('Cow burns for 60 ticks', 'the combust event')
            expect('Cow teleports to 7', 'the entity teleport event')
            expect('Cow removed', 'entity control: health, move and remove a cow from a plugin')
            command('time set 6000')
            expect('Time set:', 'the time set event')
            command('effect give %s minecraft:instant_health 1 1' % name)
            expect('Healed', 'the heal event')
            command('effect give %s minecraft:saturation 1 1' % name)
            command('stats')
            expect('statistic events so far:', 'the statistic counter')
            command('xp add %s 3 levels' % name)
            expect('Level 0 -> 3', 'the level change event')
            command('save-all')
            expect('World saved', 'the world save event')
            command('food 12')
            expect('Food 20 -> 12', 'the food level event')
            command('plugins')
            expect('hello-world', '/plugins lists the plugins')
            command('plugin reload hello-world')
            expect('hello-world reloaded successfully', '/plugin reload')
            command('hello')
            base = len(w.chat)
            wait(lambda: heard('This plugin:', base - 0), '/hello after a reload', 15.0)
            st.hit('showcase_manager')

            command('kickme')
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
                    m.check('asked to be kicked' in str(e), 'disconnected for another reason: %s' % e)
                    m.check('[seen by hello-world]' in str(e), 'the kick event did not change the reason: %s' % e)
                    kicked = True
                    break
            m.check(kicked, '/kickme did not kick')
            st.hit('showcase_kick')
            print('  engine plugin showcase ok', flush=True)
            os._exit(0)

      except m.Fail:
        print('  the chat so far: %r' % ([x for x in w.chat if not x.startswith('Cow ')][-14:],), flush=True)
        raise

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
