#!/usr/bin/env python3
"""Prepares an aowlmony plugin for the engine's native (ahead-of-time) build, tools/aoe_native.js.

    python tools/native_prepare.py <plugin folder> <out dir>

The engine's ahead-of-time chain differs from the compiler the server's plugin build uses (`aowlmony check`) in three ways this works around,
without changing the SDK or your plugin:
  * it builds `.nim` files, so the plugin's modules and the SDK are written out with that extension (main.aowl as `plug.nim`);
  * it cannot choose between the `registerEvent` overloads, so each `registerEvent(handler)` call is rewritten to the uniquely named
    `register_<EventType>(handler)` (tools/gen_native_registers.py writes those into the SDK), the event type read from the handler's
    parameter, `proc handler(e: var <EventType>)`;
  * the hexer of that chain asserts on the one large `dispatchEvent` procedure, so each of its branches is moved into a procedure of its own.
The three entry procedures (`start`, `event`, `stop`) are added to the plugin the same way tools/build_plugin.sh adds them.
"""
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDK = os.path.join(HERE, '..', 'plugin_sdk', 'pluginsdk.aowl')


def split_dispatch(text):
    """dispatchEvent's `case name` branches become procedures of their own."""
    start = text.index('\nproc dispatchEvent*() =')
    # the procedure runs to the next top-level declaration
    m = re.compile(r'\n(?=[A-Za-z#])').search(text, start + 10)
    end = m.start() if m else len(text)
    block = text[start:end]
    head, _, cases = block.partition('\n  case name\n')
    if not cases:
        raise SystemExit('dispatchEvent has no `case name`')
    parts = re.split(r'\n(?=  (?:of "[^"]+":|else:))', '\n' + cases)
    procs = []
    calls = []
    for p in parts:
        p = p.strip('\n')
        if not p:
            continue
        m = re.match(r'  of "([^"]+)":\n(.*)$', p, re.S)
        if not m:
            calls.append(p)          # the else branch stays where it is
            continue
        event, body = m.group(1), m.group(2)
        ident = re.sub(r'[^A-Za-z0-9]', '_', event)
        lines = [ln[2:] if ln.startswith('  ') else ln for ln in body.split('\n')]
        procs.append('proc dispatchBranch_%s() =\n%s\n' % (ident, '\n'.join(lines)))
        calls.append('  of "%s":\n    dispatchBranch_%s()' % (event, ident))
    new = '\n'.join(procs) + head + '\n  case name\n' + '\n'.join(calls) + '\n'
    return text[:start] + '\n' + new + text[end:]


def prepare(folder, out):
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out)
    sdk = open(SDK, encoding='utf-8').read().replace('\r\n', '\n')
    sdk = split_dispatch(sdk)
    open(os.path.join(out, 'pluginsdk.nim'), 'w', encoding='utf-8', newline='\n').write(sdk)
    main = open(os.path.join(folder, 'main.aowl'), encoding='utf-8').read().replace('\r\n', '\n')
    kinds = {}
    for m in re.finditer(r'^proc (\w+)\((\w+): var (\w+)\)', main, re.M):
        kinds[m.group(1)] = m.group(3)

    def reg(m):
        name = m.group(1)
        if name not in kinds:
            raise SystemExit('registerEvent(%s): no `proc %s(e: var <EventType>)` in main.aowl to read the event type from' % (name, name))
        return 'register_%s(%s)' % (kinds[name], name)

    main = re.sub(r'^registerEvent\((\w+)\)', reg, main, flags=re.M)
    main += '\n\nproc start*() = startPlugin()\nproc event*() = dispatchEvent()\nproc stop*() = stopPlugin()\n'
    open(os.path.join(out, 'plug.nim'), 'w', encoding='utf-8', newline='\n').write(main)
    for f in sorted(os.listdir(folder)):
        full = os.path.join(folder, f)
        if f.startswith('.') or f == 'main.aowl' or not f.endswith('.aowl') or not os.path.isfile(full):
            continue
        shutil.copy(full, os.path.join(out, f[:-5] + '.nim'))


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    prepare(sys.argv[1], sys.argv[2])
    print('prepared', sys.argv[1], '->', sys.argv[2])
