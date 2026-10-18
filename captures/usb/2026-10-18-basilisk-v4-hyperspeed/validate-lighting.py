#!/usr/bin/env python3
"""Receiver-scoped effect validation with raw original-state recovery."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

PROBE = Path('OpenSnek/.build/debug/OpenSnekProbe').resolve()
DEVICE = '1532:00ea:02150000:usb'
JOURNAL = Path(sys.argv[1]).resolve()
RECOVER = '--recover' in sys.argv[2:]


def command(cmd, args, size=None):
    size = len(args) if size is None else size
    print(f'cmd=0f:{cmd:02x} args={bytes(args).hex()} size={size}', flush=True)
    result = subprocess.run([str(PROBE), 'usb-raw', '--pid', '0x00ea', '--class', '0x0f',
                             '--cmd', hex(cmd), '--size', hex(size),
                             '--args', ','.join(f'{b:02x}' for b in args)],
                            text=True, capture_output=True, timeout=15)
    print(result.stdout, end='', flush=True)
    match = re.search(r'response\[90\]: ([0-9a-f ]+)', result.stdout)
    if result.returncode or DEVICE not in result.stdout or not match:
        raise RuntimeError('Exact device response unavailable')
    response = bytes.fromhex(match[1])
    if len(response) != 90 or response[0] != 2 or response[6:8] != bytes([15, cmd]):
        raise RuntimeError('Rejected or unavailable lighting command')
    return response[8:8+size]


def effect(target):
    data = command(0x82, [target, 10] + [0] * 10)
    if data[1] != 10:
        raise RuntimeError('Wrong lighting zone echo')
    return data


def snapshot():
    return {str(target): effect(target).hex() for target in (0, 1)}


def save(journal):
    temp = JOURNAL.with_suffix('.tmp')
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as stream:
        json.dump(journal, stream, indent=2)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temp, JOURNAL)


def restore(journal):
    journal['phase'] = 'restoring'
    save(journal)
    errors = []
    for target in (1, 0):
        try:
            original = bytes.fromhex(journal['original'][str(target)])
            if len(original) != 12 or original[1] != 10:
                raise RuntimeError('Invalid journal effect')
            command(2, [target] + list(original[1:]))
        except Exception as error:
            errors.append(str(error))
    if errors or snapshot() != journal['original']:
        raise RuntimeError('Restore failed; RETAIN JOURNAL: ' + '; '.join(errors))
    journal['phase'] = 'restored'
    save(journal)
    print('PASS: exact original live/stored effect state restored and verified.')


if subprocess.run(['pgrep', '-f', '/OpenSnek.app/Contents/MacOS/OpenSnek'], capture_output=True).returncode == 0:
    raise RuntimeError('Stop app and service first')
if RECOVER:
    journal = json.loads(JOURNAL.read_text())
    if journal.get('device_id') != DEVICE or journal.get('schema') != 'v4-lighting-1':
        raise RuntimeError('Journal identity/schema mismatch')
    restore(journal)
    sys.exit(0)
if JOURNAL.exists():
    raise RuntimeError('Existing journal must be retained; choose a new path')
journal = dict(schema='v4-lighting-1', device_id=DEVICE, phase='prepared', original=snapshot(), results=[])
save(journal)
# Standard mapped 0F:02 bodies. Validate the fields written, not unmodified tail bytes.
checks = [
    ('static', [1, 0, 0, 1, 0, 255, 64], {2: 1, 5: 1, 6: 0, 7: 255, 8: 64}),
    ('off', [0, 0, 0, 0], {2: 0}),
    ('spectrum', [3, 0, 0, 0], {2: 3}),
    ('wave-left', [4, 1, 40, 0], {2: 4, 3: 1}),
    ('wave-right', [4, 2, 40, 0], {2: 4, 3: 2}),
    ('reactive', [5, 0, 2, 1, 255, 64, 0], {2: 5, 4: 2, 6: 255, 7: 64, 8: 0}),
    ('pulse-random', [2, 0, 0, 0], {2: 2, 3: 0}),
    ('pulse-single', [2, 1, 0, 1, 0, 64, 255], {2: 2, 3: 1, 6: 0, 7: 64, 8: 255}),
    ('pulse-dual', [2, 2, 0, 2, 0, 255, 64, 255, 64, 0], {2: 2, 3: 2, 6: 0, 7: 255, 8: 64, 9: 255, 10: 64, 11: 0}),
]
try:
    for name, body, expected in checks:
        print('CHECK ' + name, flush=True)
        command(2, [1, 10] + body)
        readback = effect(1)
        if any(readback[index] != value for index, value in expected.items()):
            raise RuntimeError(f'{name} changed fields mismatch: {readback.hex()}')
        journal['results'].append(dict(name=name, readback=readback.hex()))
        save(journal)
    journal['result'] = 'pass'
finally:
    restore(journal)
