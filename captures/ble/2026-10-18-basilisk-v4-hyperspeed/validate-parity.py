#!/usr/bin/env python3
"""Scoped V4 BLE parity experiment using the canonical Swift probe, never retries.

Requires app/service stopped, one matching BLE mouse, exact discovered ID, and a
new absolute journal. --recover restores originals without repeating experiments.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

NAME = "BSK V4 HS"
READS = {"threshold": "05820000", "effect0": "1083000a", "effect1": "1083010a",
         "brightness0": "1085000a", "brightness1": "1085010a"}
WRITES = {"threshold": "05020000", "effect0": "1003000a", "effect1": "1003010a",
          "brightness0": "1005000a", "brightness1": "1005010a"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--probe", type=Path, required=True)
    parser.add_argument("--device-id", required=True)
    parser.add_argument("--journal", type=Path, required=True)
    parser.add_argument("--recover", action="store_true")
    args = parser.parse_args()
    if not args.journal.is_absolute():
        parser.error("journal must be absolute")

    def command(*parts):
        result = subprocess.run([str(args.probe.resolve()), *parts, "--name", NAME],
                                capture_output=True, text=True, timeout=25)
        print(result.stdout, end="", flush=True)
        print(result.stderr, end="", flush=True)
        result.check_returncode()
        return result.stdout

    discovery = command("bt-profile-hid-watch", "--pid", "0x00ec", "--duration", "0.5", "--max-reports", "1")
    ids = re.findall(r"candidate\[\d+\] (\S+) vid=0x068e pid=0x00ec", discovery)
    if ids != [args.device_id]:
        raise RuntimeError(f"Ambiguous or mismatched exact scope: {ids}")

    def read(field):
        output = command("bt-raw-read", "--key", READS[field], "--timeout-ms", "1200")
        match = re.search(r"payload\[(\d+)\]: ([0-9a-f ]+)\n", output)
        expected = 10 if field.startswith("effect") else 1
        if not match or int(match[1]) != expected:
            raise RuntimeError(f"Incomplete {field} read")
        data = bytes.fromhex(match[2]).hex()
        if len(data) != expected * 2:
            raise RuntimeError(f"Short {field} payload")
        return data

    def write(field, payload):
        output = command("bt-raw-write", "--key", WRITES[field], "--payload", payload, "--timeout-ms", "1200")
        if "ack status=0x02" not in output:
            raise RuntimeError(f"{field} write rejected")

    if args.recover:
        journal = json.loads(args.journal.read_text())
        if journal["device_id"] != args.device_id or journal["schema"] != "v4-ble-parity-1":
            raise RuntimeError("Mismatched recovery journal")
        for field in READS:
            value = bytes.fromhex(journal["originals"][field])
            if len(value) != (10 if field.startswith("effect") else 1):
                raise RuntimeError("Invalid original payload length")
    else:
        originals = {field: read(field) for field in READS}
        journal = {"schema": "v4-ble-parity-1", "device_id": args.device_id,
                   "originals": originals, "phase": "captured", "results": []}
        fd = os.open(args.journal, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as file:
            json.dump(journal, file, indent=2)
            file.flush()
            os.fsync(file.fileno())

    def save():
        with tempfile.NamedTemporaryFile(mode="w", dir=args.journal.parent, delete=False) as file:
            temporary = Path(file.name)
            try:
                json.dump(journal, file, indent=2)
                file.flush()
                os.fsync(file.fileno())
                os.replace(temporary, args.journal)
            finally:
                temporary.unlink(missing_ok=True)

    def restore():
        journal["phase"] = "restoring"
        try:
            save()
        except OSError as error:
            # Never let a status update prevent cleanup from the in-memory baseline.
            print(f"Journal status update failed; attempting restore: {error}", flush=True)
        errors = []
        # Restore projection/stored target first, hardware-active target last.
        for field in ("threshold", "effect1", "effect0", "brightness1", "brightness0"):
            try:
                write(field, journal["originals"][field])
            except Exception as error:
                errors.append(str(error))
        observed = {field: read(field) for field in READS}
        if observed != journal["originals"]:
            errors.append(f"Restore mismatch: {observed}")
        if errors:
            journal["phase"] = "restore_failed"
            save()
            raise RuntimeError(f"Retain recovery journal: {errors}")
        journal["phase"] = "restored"
        save()
        print("PASS exact original restore", flush=True)

    if args.recover:
        restore()
        return
    try:
        journal["phase"] = "mutating"
        save()
        threshold = "33" if journal["originals"]["threshold"] != "33" else "30"
        write("threshold", threshold)
        observed = read("threshold")
        if observed != threshold:
            raise RuntimeError("Threshold readback mismatch")
        journal["results"].append({"threshold_changed": observed})
        save()
        # Target 0 previously ACKed without readback change. Test the known V3
        # projection target 1 with its captured original before enabling anything.
        write("effect1", "0100000100ff40000000")
        journal["results"].append({field: read(field) for field in READS})
        save()
    finally:
        restore()


if __name__ == "__main__":
    main()
