#!/usr/bin/env python
"""Bounded-workload memory test for the chunk workers (docs/MULTITHREADING.md, 'Memory growth: leak or high-water mark').

  python tools/mem_soak.py <server exe> <label> [KEY=VAL ...]     e.g. ... C:/m/int_final.exe w4 MC_CHUNK_WORKERS=4
  environment: SOAK_PORT=26020 WANDER_SECS=0 (>0: no pregen; an operator bot teleports around, scenario mem_wander, for that long, then disconnects) RADIUS=20 (chunks) PASSES=1 PASS_SHIFT=0 IDLE_SECS=360 SAMPLE_SECS=30 CAP_MB=4500 (abort above) SOAK_OUT=<csv>

Fresh world (fixed seed), RCON only, no players. Runs `/pregen start <R>c 0 0` PASSES times (waiting for each to finish, a second
pass over the same area), then idles IDLE_SECS. Working set / private bytes of the server (found by its listening port) are
sampled every SAMPLE_SECS from a thread for the whole run into <SOAK_OUT> (label,t_s,phase,ws_mb,priv_mb). Only the process
listening on our port is ever killed.
"""
import os, sys, time, socket, struct, subprocess, shutil, re, threading

exe, label = sys.argv[1], sys.argv[2]
envs = dict(a.split('=', 1) for a in sys.argv[3:])
PORT = int(os.environ.get('SOAK_PORT', '26020'))
RADIUS = int(os.environ.get('RADIUS', '20'))
PASSES = int(os.environ.get('PASSES', '1'))
IDLE = int(os.environ.get('IDLE_SECS', '360'))
EVERY = int(os.environ.get('SAMPLE_SECS', '30'))
CAP = int(os.environ.get('CAP_MB', '4500'))
RUN = os.environ.get('SOAK_DIR', 'C:/m2/memsoak_' + label)
OUT = os.environ.get('SOAK_OUT', RUN + '.csv')
PW = 'bench'
WANDER = int(os.environ.get('WANDER_SECS', '0'))
SAVE_AT = int(os.environ.get('SAVE_AT', '0'))   # with WANDER_SECS: a manual `save-all flush` this many seconds into the walk (0 = none)
SHIFT = int(os.environ.get('PASS_SHIFT', '0'))   # blocks east per pass: 0 = every pass over the same area, 2000 = disjoint areas

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
        while True:
            rid, body = self.read()
            if rid == self.n:      # answers to earlier requests (a command's output may come in several packets) are skipped
                return body
    def read(self):
        h = b''
        while len(h) < 4:
            c = self.s.recv(4 - len(h)); assert c, 'rcon closed'; h += c
        size = struct.unpack('<i', h)[0]; d = b''
        while len(d) < size:
            c = self.s.recv(size - len(d)); assert c, 'rcon closed'; d += c
        return struct.unpack('<i', d[:4])[0], d[8:-2].decode(errors='replace')

shutil.rmtree(RUN, ignore_errors=True)
os.makedirs(RUN + '/data')
env = dict(os.environ)
env['PATH'] = '/c/msys64/ucrt64/bin:' + env.get('PATH', '')
for k in list(env):
    if k.startswith('MC_'):
        del env[k]
env.update(envs)
p = subprocess.Popen([exe], cwd=RUN, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    p.wait(timeout=8)
except subprocess.TimeoutExpired:
    p.kill(); p.wait()
toml = open(RUN + '/minecraft-server.toml').read()
toml = re.sub(r'(?m)^seed = .*', 'seed = "123456789"', toml)
toml = toml.replace('0.0.0.0:25565', '0.0.0.0:%d' % PORT).replace('0.0.0.0:19132', '0.0.0.0:%d' % (PORT + 2))
toml = toml.replace('0.0.0.0:25575', '0.0.0.0:%d' % (PORT + 1))
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
srv = subprocess.Popen([exe], cwd=RUN, env=env, stdout=log, stderr=subprocess.STDOUT)

def winpid():  # owner of the RCON socket (the server closes its listener after our connect, so ESTABLISHED counts too)
    for line in sh(['netstat', '-ano']).splitlines():
        m = re.search(r'^\s*TCP\s+\S+:%d\s+\S+\s+(?:LISTENING|ESTABLISHED)\s+(\d+)' % (PORT + 1), line)
        if m:
            return int(m.group(1))
    return None

phase = ['boot']
stop = threading.Event()
T0 = time.time()
pid = [None]
peak = [0]
aborted = [False]
dumped = [False]
BLOWUP = int(os.environ.get('BLOWUP_MB', '2500'))   # first sample above this writes threads_at_blowup.txt
f = open(OUT, 'w'); f.write('label,t_s,phase,ws_mb,priv_mb\n'); f.flush()

def sample():
    while not stop.is_set():
        if pid[0]:
            o = sh(['powershell', '-NoProfile', '-Command',
                    "$p=Get-Process -Id %d -ErrorAction SilentlyContinue; if($p){'{0:N0} {1:N0}' -f ($p.WorkingSet64/1MB),($p.PrivateMemorySize64/1MB)}" % pid[0]]).split()
            if len(o) == 2:
                ws, pv = int(o[0].replace(',', '')), int(o[1].replace(',', ''))
                peak[0] = max(peak[0], ws)
                f.write('%s,%d,%s,%d,%d\n' % (label, time.time() - T0, phase[0], ws, pv)); f.flush()
                if ws > BLOWUP and not dumped[0]:
                    dumped[0] = True       # a jump of GBs: record which threads burn CPU (twice, 1.5 s apart) before anything else
                    cmd = ("$p=Get-Process -Id %d; $p.Threads | %%{ '{0} {1} {2:N2} {3}' -f $_.Id,$_.ThreadState,$_.TotalProcessorTime.TotalSeconds,$_.WaitReason }" % pid[0])
                    with open(RUN + '/threads_at_blowup.txt', 'w') as tf:
                        for k in range(2):
                            tf.write('--- sample %d at t=%d ws=%d\n' % (k, time.time() - T0, ws))
                            tf.write(sh(['powershell', '-NoProfile', '-Command', cmd]))
                            time.sleep(1.5)
                if ws > CAP and not aborted[0]:
                    aborted[0] = True
                    subprocess.run(['taskkill', '/PID', str(pid[0]), '/F'], capture_output=True)
        stop.wait(EVERY)

try:
    rc = None
    for _ in range(120):
        try:
            rc = Rcon(PORT + 1); break
        except Exception:
            time.sleep(1)
    assert rc, 'rcon never came up'
    for _ in range(10):
        pid[0] = winpid()
        if pid[0]:
            break
        time.sleep(2)
    assert pid[0], 'no listener pid'
    print(label, 'server pid', pid[0], flush=True)
    th = threading.Thread(target=sample, daemon=True); th.start()
    time.sleep(5)
    rc.send(2, 'setworldspawn 0 80 0')
    rc.send(2, 'pregen inflight 256')
    if WANDER:
        import hashlib, uuid, json
        ops = [{"uuid": str(uuid.UUID(bytes=hashlib.md5(("OfflinePlayer:Wander").encode()).digest(), version=3)), "name": "Wander",
                "level": 4, "bypasses_player_limit": False}]
        json.dump(ops, open(RUN + '/data/ops.json', 'w'))
        rc.send(2, 'op Wander')   # (the file is read at start; the command covers a running server)
        phase[0] = 'wander'
        here = os.path.dirname(os.path.abspath(__file__))
        benv = dict(os.environ, WANDER_SECS=str(WANDER))
        bl = open(RUN + '/bot.txt', 'wb')
        bp = subprocess.Popen([sys.executable, here + '/mcbot.py', '--port', str(PORT), '--name', 'Wander', '--seconds', str(WANDER + 120),
                               '--scenario', 'mem_wander'], env=benv, stdout=bl, stderr=subprocess.STDOUT)
        tb = time.time()
        saved = SAVE_AT <= 0
        while bp.poll() is None and not aborted[0]:
            time.sleep(1)
            if not saved and time.time() - tb >= SAVE_AT:
                saved = True
                t1 = time.time()
                phase[0] = 'manual_save'
                r = rc.send(2, 'save-all')
                print(label, 'manual save-all flush at +%ds took %.1fs: %s' % (SAVE_AT, time.time() - t1, r.strip()[:80]), flush=True)
                phase[0] = 'wander'
        print(label, 'bot done', flush=True)
        phase[0] = 'after_bot'
    for ps in range(1, 1 if WANDER else PASSES + 1):
        phase[0] = 'pregen%d' % ps
        t = time.time()
        print(label, rc.send(2, 'pregen start %dc %d 0' % (RADIUS, (ps - 1) * SHIFT)), flush=True)
        while not aborted[0]:
            time.sleep(2)
            st = rc.send(2, 'pregen status')
            if 'nothing running' in st or re.search(r': done \d+/\d+ chunks', st):
                break
        print(label, 'pass', ps, 'wall_s', round(time.time() - t, 1), 'last status:', st, flush=True)
        phase[0] = 'gap%d' % ps
        if ps < PASSES:
            time.sleep(10)
    phase[0] = 'idle'
    t = time.time()
    while time.time() - t < IDLE and not aborted[0]:
        time.sleep(5)
    rc.send(2, 'save-all')
    phase[0] = 'idle_after_save'
    time.sleep(60)
    rc.send(2, 'stop')
except Exception as e:
    print(label, 'ERROR', repr(e), flush=True)
finally:
    stop.set()
    print(label, 'peak_ws_mb', peak[0], 'aborted_on_cap', aborted[0], flush=True)
    time.sleep(3)
    if pid[0]:
        subprocess.run(['taskkill', '/PID', str(pid[0]), '/F'], capture_output=True)
    srv.kill()
