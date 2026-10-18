#!/usr/bin/env python3
"""Exact wired-device polling check. Never routes to the receiver or another mouse."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

PROBE = Path('OpenSnek/.build/debug/OpenSnekProbe').resolve()
DEVICE = '1532:00eb:02141000:usb'
JOURNAL = Path(sys.argv[1]).resolve()
RECOVER = '--recover' in sys.argv[2:]


def command(cmd, args):
    if subprocess.run(['pgrep', '-f', '/OpenSnek.app/Contents/MacOS/OpenSnek'], capture_output=True).returncode == 0:
        raise RuntimeError('Stop app and service first')
    print(f'00:{cmd:02x} args={bytes(args).hex()}', flush=True)
    result = subprocess.run([str(PROBE), 'usb-raw', '--pid', '0x00eb', '--class', '0',
                             '--cmd', hex(cmd), '--size', '2',
                             '--args', ','.join(f'{b:02x}' for b in args)],
                            text=True, capture_output=True, timeout=15)
    print(result.stdout, end='', flush=True)
    match = re.search(r'response\[90\]: ([0-9a-f ]+)', result.stdout)
    if result.returncode or DEVICE not in result.stdout or not match:
        raise RuntimeError('Exact wired device unavailable')
    response = bytes.fromhex(match[1])
    if len(response) != 90 or response[0] != 2 or response[6:8] != bytes([0, cmd]):
        raise RuntimeError('Command rejected or timed out')
    return response


def read(target):
    response = command(0xC0, [target, 0])
    if response[8] != target or response[9] not in (1, 2, 4, 8, 16, 32, 64):
        raise RuntimeError('Unrecognised polling response')
    return response[9]


def snapshot():
    return [read(0), read(1)]


def save(journal):
    temp = JOURNAL.with_suffix('.tmp')
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as stream:
        json.dump(journal, stream, indent=2)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temp, JOURNAL)


def restore(journal):
    originals = journal['original']
    if len(originals) != 2 or any(value not in (1, 2, 4, 8, 16, 32, 64) for value in originals):
        raise RuntimeError('Invalid recovery payload')
    journal['phase'] = 'restoring'
    save(journal)
    errors = []
    for target in (1, 0):
        try:
            command(0x40, [target, originals[target]])
        except Exception as error:
            errors.append(str(error))
    if errors or snapshot() != originals:
        raise RuntimeError('RESTORE FAILED; retain journal: ' + '; '.join(errors))
    journal['phase'] = 'restored'
    save(journal)
    print('PASS: exact original polling values restored and verified on both targets.')


if RECOVER:
    journal = json.loads(JOURNAL.read_text())
    if journal.get('schema') != 'v4-wired-poll-1' or journal.get('device_id') != DEVICE:
        raise RuntimeError('Journal identity/schema mismatch')
    restore(journal)
    sys.exit(0)
if JOURNAL.exists():
    raise RuntimeError('Use a new journal path; retain existing recovery data')
journal = dict(schema='v4-wired-poll-1', device_id=DEVICE, phase='prepared', original=snapshot(), results=[])
save(journal)
try:
    for target in (0, 1):
        for hz, raw in ((125, 64), (250, 32), (500, 16), (1000, 8)):
            print(f'CHECK target={target} hz={hz}', flush=True)
            command(0x40, [target, raw])
            if read(target) != raw:
                raise RuntimeError('Changed polling value did not read back')
            journal['results'].append(dict(target=target, hz=hz, snapshot=snapshot()))
            save(journal)
    journal['result'] = 'pass'
finally:
    restore(journal)
