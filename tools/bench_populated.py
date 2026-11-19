#!/usr/bin/env python
"""Populated-tick profile (docs/MULTITHREADING_PHASE5_NEXT.md, section 7).

  python tools/bench_populated.py <server exe> <label> [KEY=VAL ...]      env: BENCH_PORT=26800 BENCH_BOTS=3 BENCH_STEPS=0,100,300 BENCH_SECS=25
One fresh world, pregen radius 8, BENCH_BOTS idle bots (tools/mcbot.py) at spawn, then for each step: /summon enough mobs (alternating
zombie / cow / skeleton / chicken, random x,z within 40 blocks of spawn, y 100) to reach the step's count, wait 5 s, /profile for BENCH_SECS.
Prints one JSON line (per-step ticks, mspt, tick scopes self ms, entity count as the server reports it).
"""
import os, sys, json, time, socket, struct, subprocess, shutil, re, random
exe, label = sys.argv[1], sys.argv[2]
envs = dict(a.split('=', 1) for a in sys.argv[3:])
PORT = int(os.environ.get('BENCH_PORT', '26800')); BOTS = int(os.environ.get('BENCH_BOTS', '3'))
STEPS = [int(x) for x in os.environ.get('BENCH_STEPS', '0,100,300').split(',')]
SECS = float(os.environ.get('BENCH_SECS', '25'))
RUN = os.environ.get('BENCH_DIR', 'C:/m3/prof_run_%d' % PORT); PW = 'bench'
HERE = os.path.dirname(os.path.abspath(__file__))

class Rcon:
    def __init__(self, port):
        self.s = socket.create_connection(('127.0.0.1', port), timeout=600); self.n = 0; self.send(3, PW)
    def send(self, t, body):
        self.n += 1; d = struct.pack('<ii', self.n, t) + body.encode() + b'\0\0'
        self.s.sendall(struct.pack('<i', len(d)) + d); return self.read()
    def read(self):
        h = b''
        while len(h) < 4:
            c = self.s.recv(4 - len(h)); assert c; h += c
        size = struct.unpack('<i', h)[0]; d = b''
        while len(d) < size:
            c = self.s.recv(size - len(d)); assert c; d += c
        return d[8:-2].decode(errors='replace')
    def cmd(self, c, drain=0.3):
        out = self.send(2, c); self.s.settimeout(drain)
        try:
            while True: out += '\n' + self.read()
        except socket.timeout: pass
        self.s.settimeout(600); return out

shutil.rmtree(RUN, ignore_errors=True); os.makedirs(RUN + '/data')
env = dict(os.environ); env['PATH'] = '/c/msys64/ucrt64/bin:' + env.get('PATH', '')
for k in list(env):
    if k.startswith('MC_'): del env[k]
env.update(envs)
p = subprocess.Popen([exe], cwd=RUN, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try: p.wait(timeout=8)
except subprocess.TimeoutExpired: p.kill(); p.wait()
t = open(RUN + '/minecraft-server.toml').read()
t = re.sub(r'(?m)^seed = .*', 'seed = "123456789"', t)
t = t.replace('0.0.0.0:25565', '0.0.0.0:%d' % PORT).replace('0.0.0.0:19132', '0.0.0.0:%d' % (PORT + 2)).replace('0.0.0.0:25575', '0.0.0.0:%d' % (PORT + 1))
t = re.sub(r'(?ms)(\[networking\.rcon\]\nenabled = )false(\naddress = ")[^"]*("\npassword = ")[^"]*"', lambda m: m.group(1) + 'true' + m.group(2) + '0.0.0.0:%d' % (PORT + 1) + m.group(3) + PW + '"', t)
t = re.sub(r'(?ms)(\[networking\.query\]\nenabled = )true(\naddress = ")[^"]*"', lambda m: m.group(1) + 'false' + m.group(2) + '0.0.0.0:%d"' % (PORT + 3), t)
t = re.sub(r'(?m)^view_distance = \d+', 'view_distance = 6', t); t = re.sub(r'(?m)^simulation_distance = \d+', 'simulation_distance = 4', t)
t = re.sub(r'(?ms)(\[networking\.java\].*?)^encryption = true', lambda m: m.group(1) + 'encryption = false', t, count=1)
t = re.sub(r'(?ms)(\[networking\.java\].*?)^online_mode = true', lambda m: m.group(1) + 'online_mode = false', t, count=1)
shutil.rmtree(RUN + '/world', ignore_errors=True); open(RUN + '/minecraft-server.toml', 'w').write(t)
log = open(RUN + '/server.txt', 'wb')
srv = subprocess.Popen([exe], cwd=RUN, env=env, stdout=log, stderr=subprocess.STDOUT)
bots = []; res = {'label': label, 'env': envs, 'bots': BOTS, 'secs': SECS, 'steps': []}
try:
    rc = None
    for _ in range(120):
        try: rc = Rcon(PORT + 1); break
        except Exception: time.sleep(1)
    assert rc; time.sleep(3)
    rc.cmd('setworldspawn 0 80 0'); rc.cmd('pregen inflight 256'); rc.cmd('pregen start 8c 0 0')
    for _ in range(600):
        time.sleep(1); st = rc.cmd('pregen status')
        if 'nothing running' in st or re.search(r': done \d+/\d+ chunks', st): break
    for i in range(BOTS):
        bots.append(subprocess.Popen([sys.executable, os.path.join(HERE, 'mcbot.py'), '--port', str(PORT), '--name', 'PBot%d' % i, '--seconds', '900'],
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        time.sleep(2)
    time.sleep(8); res['players'] = rc.cmd('list')[:100]
    rnd = random.Random(7); have = 0; kinds = ['zombie', 'cow', 'skeleton', 'chicken']
    for n in STEPS:
        while have < n:
            rc.cmd('summon minecraft:%s %d 100 %d' % (kinds[have % 4], rnd.randint(-40, 40), rnd.randint(-40, 40)), 0.01); have += 1
        time.sleep(5)
        cnt = ' '.join('%s=%s' % (k, ' '.join(rc.cmd('execute if entity @e[type=minecraft:%s]' % k).split())[:40]) for k in kinds)
        rc.cmd('profile start'); time.sleep(SECS); rc.cmd('profile stop'); rc.cmd('profile export pop_%d' % n)
        s = {'summoned': n, 'entity_count_reply': cnt[:300], 'players_after': rc.cmd('list')[:60]}
        try:
            j = json.load(open(RUN + '/world/profiles/pop_%d.json' % n)); st = j['session']['stats']
            s.update(ticks=st['ticks'], mspt_mean=st['mean_ms'], p50=st['p50_ms'], p95=st['p95_ms'], p99=st['p99_ms'], max=st['max_ms'],
                     scopes_self_ms={o['name']: o['self_ms'] for o in j.get('scopes', [])},
                     outside_tick_ms={o['name']: o['self_ms'] for o in j.get('outside_tick', [])})
        except Exception as e: s['profile_error'] = repr(e)
        res['steps'].append(s)
    try: rc.cmd('stop')
    except Exception: pass
    time.sleep(3)
finally:
    for b in bots:
        try: b.kill()
        except Exception: pass
    srv.kill(); log.close()
print(json.dumps(res))
