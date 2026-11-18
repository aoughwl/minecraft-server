#!/usr/bin/env python
"""Honest multithreading benchmark on a real server (docs/MULTITHREADING.md, 'Measured on a real server').

  python tools/bench_server.py <server exe> <label> [KEY=VAL ...]      e.g.  ... C:/m/int_final.exe w4 MC_CHUNK_WORKERS=4
  environment: BENCH_PORT=26010  BENCH_RADIUS=12 (chunks)  BENCH_DIR=<scratch>  BENCH_FILLS=150  BENCH_RESULTS=<jsonl file>

One fresh world (fixed seed) per run, RCON as the only client (no bots). Phases, each under its own /profile session:
  gen   /pregen start <R>c, wall time until `pregen status` says nothing is running; tick MSPT during it
  fill  BENCH_FILLS /fill commands (32768 blocks each, stone then air, near spawn: block updates, relight, packets to nobody)
  save  `save-all flush` wall time (RCON round trip), right after the fill phase
Prints one JSON line (also appended to BENCH_RESULTS) with the numbers, the gate lines the server printed, and the env.
"""
import os, sys, json, time, socket, struct, subprocess, shutil, re, hashlib

exe, label = sys.argv[1], sys.argv[2]
envs = dict(a.split('=', 1) for a in sys.argv[3:])
PORT = int(os.environ.get('BENCH_PORT', '26010'))
RADIUS = int(os.environ.get('BENCH_RADIUS', '8'))
FILLS = int(os.environ.get('BENCH_FILLS', '12'))
RUN = os.environ.get('BENCH_DIR', 'C:/m2/bench_run_' + str(PORT))
OUT = os.environ.get('BENCH_RESULTS', '')
PW = 'bench'
INFLIGHT = int(os.environ.get('BENCH_INFLIGHT', '256'))
SEED = '123456789'

def sh(cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout

class Rcon:
    def __init__(self, port):
        self.s = socket.create_connection(('127.0.0.1', port), timeout=600)
        self.n = 0
        self.send(3, PW)
    def send(self, t, body):
        self.n += 1
        d = struct.pack('<ii', self.n, t) + body.encode() + b'\0\0'
        self.s.sendall(struct.pack('<i', len(d)) + d)
        return self.read()
    def read(self):
        h = b''
        while len(h) < 4:
            c = self.s.recv(4 - len(h)); assert c, 'rcon closed'; h += c
        size = struct.unpack('<i', h)[0]; d = b''
        while len(d) < size:
            c = self.s.recv(size - len(d)); assert c, 'rcon closed'; d += c
        return d[8:-2].decode(errors='replace')
    def cmd(self, c, drain=0.3):
        # a command's output may arrive as several packets: take the first (blocking), then drain what follows quickly
        out = self.send(2, c)
        self.s.settimeout(drain)
        try:
            while True:
                out += chr(10) + self.read()
        except socket.timeout:
            pass
        self.s.settimeout(600)
        return out

shutil.rmtree(RUN, ignore_errors=True)
os.makedirs(RUN + '/data')
env = dict(os.environ)
env['PATH'] = '/c/msys64/ucrt64/bin:' + env.get('PATH', '')
for k in list(env):
    if k.startswith('MC_'):
        del env[k]
env.update(envs)
subprocess.run([exe], cwd=RUN, env=env, capture_output=True, timeout=30) if False else None
p = subprocess.Popen([exe], cwd=RUN, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    p.wait(timeout=8)
except subprocess.TimeoutExpired:
    p.kill(); p.wait()
toml = open(RUN + '/minecraft-server.toml').read()
toml = re.sub(r'(?m)^seed = .*', 'seed = "%s"' % SEED, toml)
toml = toml.replace('0.0.0.0:25565', '0.0.0.0:%d' % PORT).replace('0.0.0.0:19132', '0.0.0.0:%d' % (PORT + 2))
toml = toml.replace('0.0.0.0:25575', '0.0.0.0:%d' % (PORT + 1))
toml = re.sub(r'(?m)^(address = "0\.0\.0\.0:\d+")', lambda m: m.group(1), toml)
toml = re.sub(r'(?ms)(\[networking\.rcon\]\nenabled = )false(\naddress = ")[^"]*("\npassword = ")[^"]*"',
              lambda m: m.group(1) + 'true' + m.group(2) + '0.0.0.0:%d' % (PORT + 1) + m.group(3) + PW + '"', toml)
toml = re.sub(r'(?ms)(\[networking\.query\]\nenabled = )true(\naddress = ")[^"]*"', lambda m: m.group(1) + 'false' + m.group(2) + '0.0.0.0:%d"' % (PORT + 3), toml)
toml = re.sub(r'(?m)^view_distance = \d+', 'view_distance = 6', toml)
toml = re.sub(r'(?m)^simulation_distance = \d+', 'simulation_distance = 4', toml)
toml = re.sub(r'(?ms)(\[networking\.java\].*?)^encryption = true', lambda m: m.group(1) + 'encryption = false', toml, count=1)
toml = re.sub(r'(?ms)(\[networking\.java\].*?)^online_mode = true', lambda m: m.group(1) + 'online_mode = false', toml, count=1)
shutil.rmtree(RUN + '/world', ignore_errors=True)
open(RUN + '/minecraft-server.toml', 'w').write(toml)
log = open(RUN + '/server.txt', 'wb')
t0 = time.time()
srv = subprocess.Popen([exe], cwd=RUN, env=env, stdout=log, stderr=subprocess.STDOUT)
def cpu():
    o = sh(['powershell', '-NoProfile', '-Command', r"(Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 2 -MaxSamples 2).CounterSamples | % { [math]::Round($_.CookedValue,1) }"])
    v = [float(x) for x in o.split() if x.replace('.', '').isdigit()]
    return sum(v) / len(v) if v else None

def nbuild():
    t = sh(['tasklist'])
    return sum(t.count(n) for n in ('cc1.exe', 'gcc.exe', 'aowlmony.exe', 'cc1plus.exe'))

bot = None
WATCH = os.environ.get('BENCH_WATCH', '')   # set: sample the server's per-thread CPU/wait state every 8 s (stall diagnosis)
samples = []
def watcher():
    import threading
    def run():
        ps = ("$p=Get-Process -Id %d; $p.Threads | %% { '{0},{1},{2},{3}' -f $_.Id,$_.ThreadState,$_.WaitReason,[math]::Round($_.TotalProcessorTime.TotalMilliseconds) }" % srv.pid)
        while srv.poll() is None:
            t = round(time.time() - t0, 1)
            o = sh(['powershell', '-NoProfile', '-Command', ps])
            cur = {}
            for l in o.splitlines():
                q = l.strip().split(',')
                if len(q) == 4 and q[3].isdigit():
                    cur[q[0]] = int(q[3])
            samples.append({'t': t, 'threads': [l.strip() for l in o.splitlines() if l.strip()]})
            # stall trap: one thread burning ~100% of the interval, every other thread idle, twice in a row -> stack dump with gdb
            if WATCH == 'gdb' and watcher.prev is not None:
                d = {k: v - watcher.prev.get(k, v) for k, v in cur.items()}
                hot = [k for k, v in d.items() if v > 7000]
                if len(hot) == 1 and sum(1 for v in d.values() if v > 150) == 1:
                    watcher.hits += 1
                else:
                    watcher.hits = 0
                if watcher.hits == 2 and not watcher.dumped:
                    watcher.dumped = True
                    g = subprocess.run(['gdb', '-p', str(srv.pid), '-batch', '-ex', 'info threads', '-ex', 'thread apply all bt 14',
                                        '-ex', 'detach'], capture_output=True, text=True, timeout=120)
                    samples.append({'t': t, 'hot_thread': hot[0], 'gdb': (g.stdout + g.stderr)[-12000:]})
            watcher.prev = cur
            time.sleep(8)
    threading.Thread(target=run, daemon=True).start()
watcher.prev = None; watcher.hits = 0; watcher.dumped = False
if WATCH:
    watcher()
res = {'label': label, 'env': envs, 'radius': RADIUS, 'fills': FILLS}
try:
    rc = None
    for _ in range(120):
        try:
            rc = Rcon(PORT + 1); break
        except Exception:
            time.sleep(1)
    assert rc, 'rcon never came up'
    res['cpu_before_pct'] = cpu(); res['build_procs_before'] = nbuild()
    res['boot_s'] = round(time.time() - t0, 1)
    time.sleep(3)

    def profile(name, work):
        rc.cmd('profile start')
        t = time.time()
        extra = work()
        wall = time.time() - t
        rc.cmd('profile stop')
        rc.cmd('profile export bench_' + name)
        res[name] = {'wall_s': round(wall, 2), **(extra or {})}
        try:
            j = json.load(open(RUN + '/world/profiles/bench_' + name + '.json'))
            st = j['session']['stats']
            res[name].update(ticks=st['ticks'], mspt_mean=st['mean_ms'], mspt_p50=st['p50_ms'], mspt_p95=st['p95_ms'],
                             mspt_p99=st['p99_ms'], mspt_max=st['max_ms'])
            res[name]['outside_tick_ms'] = {o['name']: o['self_ms'] for o in j.get('outside_tick', [])}
            res[name]['tick_scopes_ms'] = {o['name']: o['self_ms'] for o in j.get('scopes', [])[:4]}
        except Exception as e:
            res[name]['profile_error'] = repr(e)

    def gen():
        if os.environ.get('BENCH_IDLE'):   # no pregen: profile an idle server for N seconds (what a gate costs by itself)
            time.sleep(float(os.environ['BENCH_IDLE']))
            return {'idle': True}
        rc.cmd('setworldspawn 0 80 0')
        rc.cmd('pregen inflight %d' % INFLIGHT)
        out = rc.cmd('pregen start %dc 0 0' % RADIUS)
        n = 0
        while True:
            time.sleep(1.0)
            st = rc.cmd('pregen status')
            if 'nothing running' in st or re.search(r': done \d+/\d+ chunks', st):
                break
            n += 1
            if n > 1800:
                return {'timeout': True}
        return {'chunks': (2 * RADIUS + 1) ** 2 if 'chunks' not in out else None, 'start_reply': out[:120]}

    def fill():
        c = 0
        # /fill needs loaded chunks: one idle bot (tools/mcbot.py, no scenario) joins at the spawn (0 80 0), view distance 6
        global bot
        bot = subprocess.Popen([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'mcbot.py'), '--port', str(PORT),
                                '--name', 'BenchBot', '--seconds', '900'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(10)
        res['players'] = rc.cmd('list')[:80]
        for i in range(FILLS):
            x = (i % 4) * 32 - 64; z = ((i // 4) % 4) * 32 - 64
            blk = 'stone' if (i // 16) % 2 == 0 else 'air'
            r = rc.cmd('fill %d 70 %d %d 77 %d %s' % (x, z, x + 31, z + 31, blk), 0.03)
            if i == 0: res['fill_first_reply'] = r[:100]
            c += 1
        return {}

    def save():
        return {}

    if os.environ.get('BENCH_WARM'):   # a tiny pregen far away first (outside any profile): one-time cold costs are paid before 'gen'
        rc.cmd('setworldspawn 0 80 0')
        rc.cmd('pregen start 1c 4000 4000')
        for _ in range(300):
            time.sleep(1.0)
            st = rc.cmd('pregen status')
            if 'nothing running' in st or re.search(r': done \d+/\d+ chunks', st):
                break
        res['warm_done_s'] = round(time.time() - t0, 1)
    profile('gen', gen)
    profile('fill', fill)
    t = time.time()
    res['save_all_flush_s'] = None
    out = rc.cmd('save-all', 0.05)
    res['save_all_flush_s'] = round(time.time() - t, 3)
    res['save_reply'] = out[:100]
    t = time.time()
    rc.cmd('save-all', 0.05)
    res['save_all_flush2_s'] = round(time.time() - t, 3)
    try:
        rc.cmd('stop')
    except Exception:
        pass
    time.sleep(4)
finally:
    try:
        bot.kill()
    except Exception:
        pass
    srv.kill()
    log.close()
txt = open(RUN + '/server.txt', errors='replace').read()
res['gate_lines'] = [l.strip()[:160] for l in txt.splitlines()
                     if re.search(r'refus|pool|worker|MC_|gate|violation|assert|panic|exception', l, re.I)][:12]
res['build_procs_after'] = nbuild()
if WATCH:
    res['thread_samples'] = samples
line = json.dumps(res)
print(line)
if OUT:
    open(OUT, 'a').write(line + '\n')
