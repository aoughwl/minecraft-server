#!/usr/bin/env python3
"""Starts the Bedrock-only demo server (src/server/net/bedrock/bedrockdemo.aowl, built to --exe) on a random high UDP port,
runs tools/bedrockbot.py against it, checks the server's own log, and stops the server by PID.

    python tools/runbedrock.py --exe path/to/demo.exe

Never uses a fixed port and never kills by image name."""
import argparse
import os
import random
import socket
import subprocess
import sys
import time

here = os.path.dirname(os.path.abspath(__file__))


def free_udp_port():
    while True:
        port = random.randint(41000, 60000)
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.bind(('127.0.0.1', port))
            return port
        except OSError:
            continue
        finally:
            s.close()


def run_case(exe, title, server_args, bot_args, expect_log):
    port = free_udp_port()
    env = dict(os.environ)
    env['PATH'] = r'C:\msys64\ucrt64\bin;' + env.get('PATH', '')
    log = []
    proc = subprocess.Popen([exe, '--port:%d' % port, '--max-seconds:60'] + server_args, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, env=env, text=True, errors='replace')
    try:
        first = proc.stdout.readline()
        log.append(first)
        if 'LISTENING' not in first:
            print('FAIL %s: server did not start: %r' % (title, first))
            return 1
        r = subprocess.run([sys.executable, os.path.join(here, 'bedrockbot.py'), '--port', str(port)] + bot_args,
                           capture_output=True, text=True, timeout=120)
        print('== %s (udp %d)' % (title, port))
        print(r.stdout.rstrip())
        if r.stderr.strip():
            print(r.stderr.rstrip())
        time.sleep(0.5)
    finally:
        proc.terminate()
        try:
            out, _ = proc.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            out, _ = proc.communicate()
        log.append(out or '')
    text = ''.join(log)
    ok = r.returncode == 0
    for needle in expect_log:
        if needle not in text:
            print('FAIL %s: server log lacks %r' % (title, needle))
            ok = False
    if not ok:
        print('--- server log ---')
        print(text)
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--exe', required=True)
    args = ap.parse_args()
    rc = 0
    rc |= run_case(args.exe, 'encrypted login', [], [], ['READY name=Bot_Steve', 'PACKS COMPLETED'])
    rc |= run_case(args.exe, 'unencrypted login', ['--no-encryption'], ['--no-encrypt'], ['READY name=Bot_Steve', 'PACKS COMPLETED'])
    rc |= run_case(args.exe, 'full server', ['--max-players:0'], ['--expect-full'], [])
    print('ALL OK' if rc == 0 else 'FAILED')
    return rc


if __name__ == '__main__':
    sys.exit(main())
