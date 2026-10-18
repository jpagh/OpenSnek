#!/usr/bin/env python3
"""Explicitly scoped live DPI table check; journal before writes, exact restore."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

PROBE = Path('OpenSnek/.build/debug/OpenSnekProbe').resolve()
DEVICE = '1532:00ea:02150000:usb'
JOURNAL = Path(sys.argv[1]).resolve()

def command(cls, cmd, size, args):
    result = subprocess.run([str(PROBE), 'usb-raw', '--pid', '0x00ea',
                             '--class', hex(cls), '--cmd', hex(cmd), '--size', hex(size),
                             '--args', ','.join(f'{b:02x}' for b in args)],
                            text=True, capture_output=True, timeout=15)
    print(result.stdout, end='', flush=True)
    if result.returncode or DEVICE not in result.stdout:
        raise RuntimeError('Exact device unavailable: ' + result.stderr)
    match = re.search(r'response\[90\]: ([0-9a-f ]+)', result.stdout)
    if not match:
        raise RuntimeError('Missing response')
    response = bytes.fromhex(match[1])
    if response[0] != 2 or response[6:8] != bytes([cls, cmd]):
        raise RuntimeError('Command rejected or timed out')
    return response[8:8+size]

def read_table():
    data = command(4, 0x86, 38, [0])
    if data[0] != 0 or data[2] != 5 or len(set(data[3::7])) != 5:
        raise RuntimeError('Unexpected baseline table layout')
    return data

def save(journal):
    temp = JOURNAL.with_suffix('.tmp')
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as stream:
        json.dump(journal, stream, indent=2)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temp, JOURNAL)

if JOURNAL.exists():
    raise RuntimeError('Use a new journal path; existing recovery data must be retained')
if subprocess.run(['pgrep', '-f', '/OpenSnek.app/Contents/MacOS/OpenSnek'], capture_output=True).returncode == 0:
    raise RuntimeError('Stop OpenSnek app and service first')
original = read_table()
scalar = command(4, 0x85, 7, [0])
persistent = command(4, 0x86, 38, [1])
persistent_scalar = command(4, 0x85, 7, [1])
journal = dict(device_id=DEVICE, phase='prepared', table=original.hex(), scalar=scalar.hex(),
               persistent_table=persistent.hex(), persistent_scalar=persistent_scalar.hex())
save(journal)
try:
    changed = bytearray(original)
    changed[1] = changed[3]  # Resolve active token from the original first row ID.
    changed[4:10] = bytes.fromhex('03e803e803e8')
    command(4, 6, 38, changed)
    if read_table() != changed:
        raise RuntimeError('Changed table did not read back exactly')
    active_scalar = command(4, 0x85, 7, [0])
    if active_scalar[1:5] != bytes.fromhex('03e803e8'):
        raise RuntimeError('Scalar DPI does not match active changed stage')
    journal['changed_readback'] = changed.hex()
    changed[1] = changed[31]  # Last original row ID, not an assumed index.
    command(4, 6, 38, changed)
    if read_table() != changed:
        raise RuntimeError('Active-stage-only transition did not read back')
    journal['active_transition_readback'] = changed.hex()
    journal['result'] = 'pass'
finally:
    journal['phase'] = 'restoring'
    save(journal)
    if command(4, 0x86, 38, [1]) != persistent or command(4, 0x85, 7, [1]) != persistent_scalar:
        command(4, 6, 38, persistent)
        command(4, 5, 7, persistent_scalar)
    command(4, 6, 38, original)
    command(4, 5, 7, scalar)
    if (read_table() != original or command(4, 0x85, 7, [0]) != scalar
            or command(4, 0x86, 38, [1]) != persistent
            or command(4, 0x85, 7, [1]) != persistent_scalar):
        raise RuntimeError('RESTORE FAILED: retain journal for exact recovery')
    journal['phase'] = 'restored'
    save(journal)
    print('Exact original live table and scalar restored and verified.')
