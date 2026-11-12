#!/usr/bin/env python3
"""Runs the full server (src/main.aowl built to --exe) with Bedrock on, on a COPY of a world, a random TCP port for Java and a
random high UDP port for Bedrock, and drives tools/bedrockbot.py --play against it (start game, chunks, spawn, move, chat). If
--java is given, a Java bot (tools/mcbot.py) joins first so the two see each other. The server is stopped by PID. Never uses
25565 or 19132, never touches another server process.

    python tools/runbedrockfull.py --exe path/to/srv.exe --work path/to/scratch [--world SRC] [--java] [--command "say hi"]
"""
import argparse
import os
import re
import shutil
import json
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
import bedrockbot as bb  # noqa: E402  (its P-384 and ECDSA make the local OIDC key and token)

DEFAULT_WORLD = r'C:\Users\timbuktu\AppData\LocalLow\savannt\UnityHost\mcserver\instances\default\world'


def free_port(udp):
    while True:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM if udp else socket.SOCK_STREAM)
        s.bind(('127.0.0.1', 0))
        port = s.getsockname()[1]
        s.close()
        if port > 40000 and port not in (25565, 19132):
            return port


def start_oidc_server(port):
    """A local stand-in for the Xbox discovery document, the OpenID configuration and the JWKS, with a key made here (the
    Xbox keys cannot be had offline). Returns (server, private scalar, kid, issuer)."""
    key = int.from_bytes(os.urandom(48), 'big') % bb.N or 1
    pub = bb.pt_mul(key, bb.G)
    kid = 'local-test-key'
    issuer = 'http://127.0.0.1:%d/issuer' % port
    jwks = {'keys': [{'kty': 'EC', 'crv': 'P-384', 'alg': 'ES384', 'kid': kid,
                      'x': bb.b64(pub[0].to_bytes(48, 'big'), True, False), 'y': bb.b64(pub[1].to_bytes(48, 'big'), True, False)}]}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            base = 'http://127.0.0.1:%d' % port
            if self.path.startswith('/discovery'):
                body = {'result': {'serviceEnvironments': {'auth': {'prod': {'serviceUri': base + '/svc'}}}}}
            elif self.path == '/svc/.well-known/openid-configuration':
                body = {'issuer': issuer, 'jwks_uri': base + '/jwks'}
            elif self.path == '/jwks':
                body = jwks
            else:
                self.send_response(404)
                self.end_headers()
                return
            data = json.dumps(body).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, *a):
            pass

    server = HTTPServer(('127.0.0.1', port), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, key, kid, issuer


def set_key(text, section_pred, key, value):
    """Sets `key = value` inside the first table whose header satisfies section_pred; adds it when absent."""
    lines = text.split('\n')
    start = None
    for i, line in enumerate(lines):
        m = re.match(r'^\s*\[([^\]]+)\]\s*$', line)
        if m and section_pred(m.group(1)):
            start = i
            break
    if start is None:
        raise SystemExit('no table matched for %s' % key)
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if re.match(r'^\s*\[', lines[j]):
            end = j
            break
    for j in range(start + 1, end):
        if re.match(r'^\s*%s\s*=' % re.escape(key), lines[j]):
            lines[j] = '%s = %s' % (key, value)
            return '\n'.join(lines)
    lines.insert(start + 1, '%s = %s' % (key, value))
    return '\n'.join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--exe', required=True)
    ap.add_argument('--work', required=True, help='scratch folder; the world copy and the server config live here')
    ap.add_argument('--world', default=DEFAULT_WORLD)
    ap.add_argument('--fresh', action='store_true')
    ap.add_argument('--no-encrypt', action='store_true')
    ap.add_argument('--java', action='store_true')
    ap.add_argument('--chat', default='hello from the bedrock bot')
    ap.add_argument('--command', default='')
    ap.add_argument('--seconds', type=float, default=60.0)
    ap.add_argument('--extended', action='store_true', help='hotbar, inventory, place and break, chest (bedrockbot --extended)')
    ap.add_argument('--followups', action='store_true', help='effects, weather, title, boss bar, equipment, metadata, death and respawn (bedrockbot --followups)')
    ap.add_argument('--form', action='store_true', help='the server sends a modal form at join; the bot answers it')
    ap.add_argument('--online-wrong-key', action='store_true', help='with --online: the bot signs with a key that is not in the JWKS; the login must be refused')
    ap.add_argument('--online', action='store_true', help='online mode against a local OIDC server and a token signed with a key made here')
    args = ap.parse_args()
    run = os.path.join(args.work, 'run')
    if args.fresh or not os.path.isdir(os.path.join(run, 'world')):
        shutil.rmtree(run, ignore_errors=True)
        os.makedirs(run)
        shutil.copytree(args.world, os.path.join(run, 'world'), ignore=shutil.ignore_patterns('session.lock'))
    env = dict(os.environ)
    env['PATH'] = r'C:\msys64\ucrt64\bin;' + env['PATH']
    cfg = os.path.join(run, 'cfg')
    toml = os.path.join(cfg, 'pumpkin.toml')
    if not os.path.exists(toml):
        subprocess.run([args.exe, '--config:cfg', '--world:world', '--max-seconds:1'], cwd=run, env=env, capture_output=True,
                       text=True, timeout=180)
    if not os.path.exists(toml):
        os.makedirs(cfg, exist_ok=True)
        raise SystemExit('the server did not create %s' % toml)
    tcp, udp = free_port(False), free_port(True)
    text = open(toml, encoding='utf-8').read()
    is_bedrock = lambda h: h.endswith('bedrock') and 'networking' in h and 'resource' not in h and 'authentication' not in h
    is_java = lambda h: h.endswith('java') and 'networking' in h and 'resource' not in h
    text = set_key(text, is_bedrock, 'address', '"127.0.0.1:%d"' % udp)
    oidc = None
    if args.online:
        oidc_port = free_port(False)
        oidc = start_oidc_server(oidc_port)
        text = set_key(text, is_bedrock, 'online_mode', 'true')
        is_auth = lambda h: h == 'networking.bedrock.authentication'
        text = set_key(text, is_auth, 'enabled', 'true')
        text = set_key(text, is_auth, 'url', '"http://127.0.0.1:%d/discovery"' % oidc_port)
    else:
        text = set_key(text, is_bedrock, 'online_mode', 'false')
    text = set_key(text, is_bedrock, 'encryption', 'false' if args.no_encrypt else 'true')
    text = set_key(text, is_bedrock, 'enabled', 'true')
    for table in ('networking.query', 'networking.rcon', 'networking.lan_broadcast'):
        # the defaults bind 25565 UDP, 25575 and the LAN multicast port: a test run must not touch a real server's
        text = set_key(text, (lambda h, t=table: h == t), 'enabled', 'false')
    text = set_key(text, is_java, 'address', '"127.0.0.1:%d"' % tcp)
    text = set_key(text, is_java, 'online_mode', 'false')
    text = set_key(text, is_java, 'encryption', 'false')
    open(toml, 'w', encoding='utf-8').write(text)
    log = open(os.path.join(run, 'server.log'), 'wb')
    if args.form:
        env['PUMPKIN_BEDROCK_TEST_FORM'] = '1'
    proc = subprocess.Popen([args.exe, '--config:cfg', '--world:world', '--port:%d' % tcp, '--max-seconds:%d' % int(args.seconds + 120)],
                            cwd=run, env=env, stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.PIPE)
    print('server pid %d, java tcp %d, bedrock udp %d' % (proc.pid, tcp, udp), flush=True)
    rc = 1
    try:
        deadline = time.time() + 180
        while time.time() < deadline:
            try:
                socket.create_connection(('127.0.0.1', tcp), 1).close()
                break
            except OSError:
                if proc.poll() is not None:
                    raise SystemExit('server died: %r' % proc.returncode)
                time.sleep(0.5)
        java = None
        if args.java:
            javalog = open(os.path.join(run, 'java.log'), 'wb')
            java = subprocess.Popen([sys.executable, os.path.join(here, 'mcbot.py'), '--port', str(tcp), '--name', 'JavaPal', '--seconds', '60'],
                                    stdout=javalog, stderr=subprocess.STDOUT)
            # wait until the server lists the Java bot, so it is in the world before the Bedrock bot joins
            for _ in range(40):
                proc.stdin.write(b'list' + bytes([10]))
                proc.stdin.flush()
                time.sleep(3)
                if 'JavaPal' in open(os.path.join(run, 'server.log'), errors='replace').read():
                    break
        bot = [sys.executable, os.path.join(here, 'bedrockbot.py'), '--port', str(udp), '--play', '--chat', args.chat]
        if args.no_encrypt:
            bot.append('--no-encrypt')
        if args.command:
            bot += ['--command', args.command]
        bot += ['--hold', '6', '--expect-block']
        if args.extended:
            bot.append('--extended')
        if args.followups:
            bot.append('--followups')
        if args.form:
            bot.append('--form')
        if oidc is not None:
            key = oidc[1] if not args.online_wrong_key else (oidc[1] ^ 0x1234567) or 1
            bot += ['--oidc-key', '%x' % key, '--oidc-kid', oidc[2], '--oidc-issuer', oidc[3]]
        b = subprocess.Popen(bot, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        lines = []
        expects = []
        walked = None
        for line in b.stdout:
            lines.append(line.rstrip())
            if line.startswith('@console '):
                proc.stdin.write(line[len('@console '):].rstrip().encode() + bytes([10]))
                proc.stdin.flush()
                continue
            if line.startswith('@expect '):
                expects.append(line[len('@expect '):].rstrip())
                continue
            m = re.search(r'walked from \(([-0-9.]+), ([-0-9.]+), ([-0-9.]+)\)', line)
            if m:
                walked = tuple(float(v) for v in m.groups())
            if 'sent chat' in line:
                # the bot holds for a few seconds: change a block next to it (inside its view, whatever the world), ask the
                # server where its player is, and who is there
                time.sleep(1.5)
                x, y, z = (int(walked[0]) + 1, int(walked[1]) + 3, int(walked[2])) if walked else (9, 99, 0)
                proc.stdin.write(('setblock %d %d %d minecraft:diamond_block' % (x, y, z)).encode() + bytes([10]) + b'data get entity Bot_Steve' + bytes([10]) + b'list' + bytes([10]))
                proc.stdin.flush()
        b.wait(timeout=240)
        print(chr(10).join(lines))
        rc = b.returncode
        if expects:
            time.sleep(1.0)
            logtext = open(os.path.join(run, 'server.log'), errors='replace').read()
            for want in expects:
                if want in logtext:
                    print('  ok  server log has: ' + want)
                else:
                    print('FAIL  server log lacks: ' + want)
                    rc = rc or 1
        if java is not None:
            try:
                java.wait(timeout=90)
            except subprocess.TimeoutExpired:
                java.kill()
            javalog.close()
            out = open(os.path.join(run, 'java.log'), errors='replace').read()
            print('--- java bot (stages and tail) ---')
            print(chr(10).join([l for l in out.splitlines() if l.startswith('STAGE')]))
            print(chr(10).join(out.splitlines()[-3:]))
    finally:
        proc.terminate()
        try:
            proc.wait(30)
        except subprocess.TimeoutExpired:
            proc.kill()
        log.close()
        print('--- server log (tail) ---')
        print(open(os.path.join(run, 'server.log'), errors='replace').read()[-3000:])
    return rc


if __name__ == '__main__':
    sys.exit(main())
