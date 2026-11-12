"""Disconnect lifecycle scenario: python tools/mcbot_disconnect.py PORT fin rst shut config. Against a running offline test server (never 25565): logs in as DiscBot, leaves by FIN, RST, half-close or during configuration, and checks the status ping drops to 0 online within 3 s and an immediate re-login is accepted."""
import sys, time, struct, socket, subprocess, os, shutil, json
sys.path.insert(0, r'C:\Users\timbuktu\dev\minecraft-server\tools')
import mcbot
from mcbot import *

def login_to_play(host, port, name, wait_play=True):
    c = Conn(host, port)
    c.send(0, handshake(host, port, 2))
    c.send(SB_LOGIN_HELLO, string(name) + bytes(16))
    while True:
        pid, r = c.recv()
        if pid == LOGIN_DISCONNECT:
            raise Fail('login refused: %s' % r.string())
        if pid == LOGIN_COMPRESSION:
            c.threshold = r.varint(); continue
        if pid == LOGIN_FINISHED:
            c.send(SB_LOGIN_ACK); break
    c.send(SB_CFG_INFO, client_information())
    while True:
        pid, r = c.recv()
        if pid == CFG_KNOWN_PACKS:
            c.send(SB_CFG_KNOWN_PACKS, varint(0))
        elif pid == CFG_FINISH:
            c.send(SB_CFG_FINISH); break
        elif pid == CFG_KEEP_ALIVE:
            c.send(SB_CFG_KEEP_ALIVE, r.take(8))
        elif pid == CFG_DISCONNECT:
            raise Fail('config disconnect')
    if wait_play:
        c.sock.settimeout(2.0)
        t = time.time()
        n = 0
        while time.time() - t < 3:
            try: c.recv(); n += 1
            except socket.timeout: break
    return c

def online(host, port):
    return status_ping(host, port)['players']['online']

def scenario(host, port, mode):
    name = 'DiscBot'
    c = login_to_play(host, port, name, wait_play=(mode != 'config'))
    print(mode, 'online while in:', online(host, port))
    if mode == 'rst':
        c.sock.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack('ii', 1, 0)); c.sock.close()
    elif mode == 'fin':
        c.sock.close()
    elif mode == 'shut':
        c.sock.shutdown(socket.SHUT_WR); time.sleep(0.2); c.sock.close()
    elif mode == 'config':
        c.sock.close()
    t0 = time.time()
    seen = None
    while time.time() - t0 < 3:
        seen = online(host, port)
        if seen == 0:
            break
        time.sleep(0.05)
    dt = time.time() - t0
    print(mode, 'online after: %s (waited %.2fs)' % (seen, dt))
    ok = seen == 0
    t1 = time.time()
    try:
        c2 = login_to_play(host, port, name, wait_play=False)
        c2.sock.settimeout(1.5)
        try:
            pid, r = c2.recv()
            print(mode, 'relogin first packet', hex(pid))
        except socket.timeout:
            pass
        c2.close()
        print(mode, 'relogin ok in %.2fs' % (time.time() - t1))
    except Fail as e:
        print(mode, 'RELOGIN FAILED', e); ok = False
    time.sleep(1.0)
    return ok

if __name__ == '__main__':
    host, port = '127.0.0.1', int(sys.argv[1])
    res = {m: scenario(host, port, m) for m in sys.argv[2:]}
    print(res)
    sys.exit(0 if all(res.values()) else 1)
