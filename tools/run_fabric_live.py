#!/usr/bin/env python3
"""Live checks for the Fabric gaps (docs/FABRIC_GAPS.md) against a real server in a scratch folder, headless, with tools/mcbot.py.

    python tools/run_fabric_live.py <server exe> worldtype flat|default|amplified|large_biomes
    python tools/run_fabric_live.py <server exe> playerdata
    python tools/run_fabric_live.py <server exe> javaworld <world folder>     (the folder is COPIED first, never touched)

Prints PASS / FAIL / INCONCLUSIVE lines of the bot scenarios and exits non-zero on FAIL. Port 25610+ (never a running game).
"""
import hashlib, json, os, shutil, subprocess, sys, time, uuid

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE = os.path.abspath(sys.argv[1])
MODE = sys.argv[2]
ARG = sys.argv[3] if len(sys.argv) > 3 else ''
PORT = int(os.environ.get('PORT', '25610'))
NAME = os.environ.get('BOT_NAME', 'ScenBot')
RUN = os.path.abspath(os.path.join(HERE, '..', 'fabric_run_' + MODE + ('_' + ARG if MODE == 'worldtype' else '')))
env = dict(os.environ)
engine = os.path.abspath(os.path.join(HERE, '..', 'aoughwl-engine', 'build', 'dll'))
env['PATH'] = r'C:\msys64\ucrt64\bin;' + engine + ';' + env.get('PATH', '')


def start():
    out = open(os.path.join(RUN, 'server.txt'), 'ab')
    return subprocess.Popen([EXE], cwd=RUN, stdout=out, stderr=subprocess.STDOUT, env=env)


def bot(scenario, extra_env):
    e = dict(env)
    e.update(extra_env)
    e['BOT'] = NAME
    r = subprocess.run([sys.executable, os.path.join(HERE, 'tools', 'mcbot.py'), '--port', str(PORT), '--name', NAME, '--seconds', '150',
                        '--scenario', scenario], env=e, capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    return r.returncode, r.stdout


def prepare(world_type=None, copy_world=None):
    shutil.rmtree(RUN, ignore_errors=True)
    os.makedirs(os.path.join(RUN, 'data'))
    if copy_world:
        # a COPY of the parts that matter (a 3 GB world is not needed to prove loading): level.dat, playerdata, and the four regions around the
        # origin; the source is only ever read
        dst = os.path.join(RUN, 'world')
        os.makedirs(os.path.join(dst, 'region'))
        shutil.copy2(os.path.join(copy_world, 'level.dat'), dst)
        shutil.copytree(os.path.join(copy_world, 'playerdata'), os.path.join(dst, 'playerdata'))
        if os.environ.get('PLAYER_OLD') == '1':
            # the .dat_old is the file the real play session wrote (a later test run rewrote the .dat)
            pdir = os.path.join(dst, 'playerdata')
            for n in os.listdir(pdir):
                if n.endswith('.dat_old'):
                    shutil.copy2(os.path.join(pdir, n), os.path.join(pdir, n[:-4]))
        for rx in (-1, 0):
            for rz in (-1, 0):
                src = os.path.join(copy_world, 'region', 'r.%d.%d.mca' % (rx, rz))
                if os.path.exists(src):
                    shutil.copy2(src, os.path.join(dst, 'region'))
    p = start()
    time.sleep(8)
    p.kill()
    p.wait()
    if not copy_world:
        shutil.rmtree(os.path.join(RUN, 'world'), ignore_errors=True)   # the first start only made the config; the world is made by the real run
    toml = os.path.join(RUN, 'minecraft-server.toml')
    text = open(toml, encoding='utf-8').read()
    text = text.replace('0.0.0.0:25565', '0.0.0.0:%d' % PORT).replace('0.0.0.0:25575', '0.0.0.0:%d' % (PORT + 1)).replace('0.0.0.0:19132', '0.0.0.0:%d' % (PORT + 2))
    lines, out, sect = text.split('\n'), [], ''
    for l in lines:
        if l.startswith('['):
            sect = l.strip()
        if sect == '[networking.java]' and l.startswith(('encryption =', 'online_mode =')):
            l = l.split('=')[0] + '= false'
        out.append(l)
        if l.startswith('enforce_whitelist =') and world_type:
            out.append('world_type = "%s"' % world_type)
    open(toml, 'w', encoding='utf-8').write('\n'.join(out))
    uid = str(uuid.UUID(bytes=hashlib.md5(('OfflinePlayer:' + NAME).encode()).digest(), version=3))
    json.dump([{'uuid': uid, 'name': NAME, 'level': 4, 'bypasses_player_limit': False}], open(os.path.join(RUN, 'data', 'ops.json'), 'w'))
    return uid


def run_phase(scenarios, extra_env, stops=False):
    p = start()
    time.sleep(12)
    rc, out = bot(scenarios, extra_env)
    if stops:
        try:
            p.wait(timeout=20)
        except subprocess.TimeoutExpired:
            print('  the server did not stop by itself in 20 s; killing it', flush=True)
            p.kill()
            p.wait()
    else:
        p.kill()
        p.wait()
    return rc, out, p.returncode


if MODE == 'worldtype':
    wt = ARG
    prepare(None if wt == 'default' else wt)
    rc, out, _ = run_phase('world_flat,terrain_world', {'EXPECT_WORLD_TYPE': wt})
    lvl = os.path.join(RUN, 'world', 'data', 'minecraft', 'world_gen_settings.dat')   # 1.21.9+ keeps the generator here, not in level.dat
    import gzip
    data = gzip.open(lvl, 'rb').read()
    expect = {'flat': b'minecraft:flat', 'amplified': b'minecraft:amplified', 'large_biomes': b'minecraft:large_biomes', 'default': b'minecraft:overworld'}[wt]
    ok = expect in data
    print('WORLD_GEN_SETTINGS contains %s: %s' % (expect.decode(), ok), flush=True)
    sys.exit(0 if rc == 0 and ok else 1)
elif MODE == 'playerdata':
    prepare()
    rcA, outA, _ = run_phase('player_roundtrip_set,stop_server', {'PHASE': 'set', 'STOP_SERVER': '1'}, stops=True)
    rc_stop = _
    print('server exit code after /stop: %s' % rc_stop, flush=True)
    uid = str(uuid.UUID(bytes=hashlib.md5(('OfflinePlayer:' + NAME).encode()).digest(), version=3))
    f = os.path.join(RUN, 'world', 'playerdata', uid + '.dat')
    print('playerdata file %s exists: %s (%d bytes)' % (os.path.basename(f), os.path.exists(f), os.path.getsize(f) if os.path.exists(f) else 0), flush=True)
    rcB, outB, _ = run_phase('player_roundtrip_check', {'PHASE': 'check'})
    sys.exit(0 if rcA == 0 and rcB == 0 and os.path.exists(f) else 1)
elif MODE == 'datapack':
    prepare()
    pk = os.path.join(RUN, 'world', 'datapacks', 'livepack')
    os.makedirs(os.path.join(pk, 'data', 'live', 'function'))
    os.makedirs(os.path.join(pk, 'data', 'live', 'recipe'))
    os.makedirs(os.path.join(pk, 'data', 'minecraft', 'tags', 'function'))
    open(os.path.join(pk, 'pack.mcmeta'), 'w').write('{"pack":{"pack_format":94,"description":"live"}}')
    open(os.path.join(pk, 'data', 'live', 'function', 'hello.mcfunction'), 'w').write('# live\ndata get entity ScenBot Health\ntime query daytime\n')
    open(os.path.join(pk, 'data', 'live', 'function', 'loaded.mcfunction'), 'w').write('say live pack loaded\n')
    open(os.path.join(pk, 'data', 'minecraft', 'tags', 'function', 'load.json'), 'w').write('{"values":["live:loaded"]}')
    open(os.path.join(pk, 'data', 'live', 'recipe', 'a.json'), 'w').write('{"type":"minecraft:crafting_shapeless","ingredients":["minecraft:dirt"],"result":{"id":"minecraft:diamond","count":2}}')
    open(os.path.join(pk, 'data', 'live', 'recipe', 'b.json'), 'w').write('{"type":"minecraft:smelting","ingredient":"minecraft:dirt","result":"minecraft:glass","experience":0.1}')
    open(os.path.join(pk, 'data', 'live', 'tags_dummy'), 'w').write('')
    os.makedirs(os.path.join(pk, 'data', 'live', 'tags', 'block'))
    open(os.path.join(pk, 'data', 'live', 'tags', 'block', 'special.json'), 'w').write('{"values":["minecraft:stone","minecraft:dirt"]}')
    rc, out, _ = run_phase('datapack_live', {'EXPECT_DATAPACK': '1'})
    srv = open(os.path.join(RUN, 'server.txt'), 'rb').read().decode('utf-8', 'replace')
    loaded = '#minecraft:load ran 1 command(s)' in srv
    print('server log shows [datapack] summary: %s; #minecraft:load ran 1 command: %s' % ('[datapack]' in srv, loaded), flush=True)
    sys.exit(0 if rc == 0 and loaded else 1)
elif MODE == 'javaworld':
    prepare(None, copy_world=ARG)
    # the saved position of the player in the copy, read from his own file
    import gzip
    sys.path.insert(0, os.path.join(HERE, 'tools'))
    uid = str(uuid.UUID(bytes=hashlib.md5(('OfflinePlayer:' + NAME).encode()).digest(), version=3))
    pos = os.environ.get('EXPECT_POS')
    rc, out, _ = run_phase('java_world_join', {'EXPECT_POS': pos or '0,0,0', 'EXPECT_ITEM': os.environ.get('EXPECT_ITEM', 'sand')}, stops=False)
    sys.exit(rc)
else:
    sys.exit('unknown mode')
