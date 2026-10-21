#!/usr/bin/env python3
"""Read-only, standard-library checks for scoped Razer USB capture evidence.

Accept a pcap via TShark or a TShark PDML export. Never opens a HID device or
sends a device command. Report framing checks are not hardware validation.
"""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET


# Only whole payload fields are considered, never arbitrary packet-byte scans.
PAYLOAD_FIELDS = {"usb.capdata", "usb.data_fragment", "usbhid.data", "data.data"}
STATUSES = {0: "request", 1: "busy", 2: "success", 3: "failure", 4: "timeout", 5: "unsupported"}
COLUMNS = [
    "frame", "epoch", "bus", "device", "endpoint", "urb_id", "urb_type",
    "payload_field", "body_offset", "status", "class", "command", "size",
    "arguments_hex", "report_hex", "problem",
]


@dataclass(frozen=True)
class Report:
    body: bytes
    offset: int

    @property
    def status(self) -> str:
        return STATUSES[self.body[0]]


def decode_report(payload: bytes) -> tuple[Report | None, str]:
    """Accept only an exact 90-byte body or one leading report-ID byte.

    A 91-byte payload is a framing candidate, not proof that the leading byte
    really is a report ID. Confirm the boundary against descriptors/setup data.
    No truncation, stream reassembly, or heuristic sliding-window search.
    """
    if len(payload) not in (90, 91):
        return None, "not a whole 90/91-byte report"
    offset = len(payload) - 90
    body = payload[offset:]
    if body[0] not in STATUSES:
        return None, "unknown status"
    if body[4] != 0:
        return None, "nonzero protocol byte"
    if body[5] > 80:
        return None, "argument size exceeds 80"
    if body[89] != 0:
        return None, "nonzero reserved byte"
    checksum = 0
    for value in body[2:88]:
        checksum ^= value
    if checksum != body[88]:
        return None, "checksum mismatch"
    return Report(body, offset), ""


def field_text(fields: dict[str, ET.Element], name: str) -> str:
    field = fields.get(name)
    if field is None:
        return ""
    return field.get("show", field.get("value", ""))


def field_integer(fields: dict[str, ET.Element], name: str) -> int | None:
    field = fields.get(name)
    if field is None:
        return None
    try:
        shown = field.get("show")
        if shown is not None:
            return int(shown, 16 if shown.lower().startswith("0x") else 10)
        return int(field.get("value", ""), 16)
    except ValueError:
        return None


def extract_rows(pdml: Path, bus: int, device: int) -> tuple[list[dict], dict]:
    rows = []
    stats = {"packets": 0, "scoped_packets": 0, "payload_fields": 0,
             "short_or_other_payloads": 0, "malformed_hex": 0}
    # Remove processed packets from the root to bound XML memory, not just text.
    context = ET.iterparse(pdml, events=("start", "end"))
    _, root = next(context)
    for event, packet in context:
        if event != "end" or packet.tag != "packet":
            continue
        stats["packets"] += 1
        all_fields = list(packet.iter("field"))
        fields = {field.get("name", ""): field for field in all_fields}
        if (field_integer(fields, "usb.bus_id") == bus
                and field_integer(fields, "usb.device_address") == device):
            stats["scoped_packets"] += 1
            # Avoid duplicate payload aliases within a packet, not across URBs.
            seen = set()
            for field in all_fields:
                name = field.get("name", "")
                if name not in PAYLOAD_FIELDS:
                    continue
                stats["payload_fields"] += 1
                try:
                    payload = bytes.fromhex(field.get("value", "").replace(":", ""))
                except ValueError:
                    stats["malformed_hex"] += 1
                    continue
                if len(payload) not in (90, 91):
                    stats["short_or_other_payloads"] += 1
                    continue
                if payload in seen:
                    continue
                seen.add(payload)
                report, problem = decode_report(payload)
                body = report.body if report else b""
                row = dict.fromkeys(COLUMNS, "")
                row.update(
                    frame=field_text(fields, "frame.number"),
                    epoch=field_text(fields, "frame.time_epoch"), bus=bus, device=device,
                    endpoint=field_text(fields, "usb.endpoint_address"),
                    urb_id=field_text(fields, "usb.urb_id"),
                    urb_type=field_text(fields, "usb.urb_type"),
                    payload_field=name, body_offset=report.offset if report else "",
                    status=report.status if report else "unrecognized",
                    report_hex=body.hex(" ") if report else payload.hex(" "), problem=problem,
                )
                if report:
                    row.update({"class": f"{body[6]:02x}", "command": f"{body[7]:02x}",
                                "size": body[5], "arguments_hex": body[8:8 + body[5]].hex(" ")})
                rows.append(row)
        root.remove(packet)
        packet.clear()
    return rows, stats


def write_results(out: Path, rows: list[dict], stats: dict, bus: int, device: int) -> bool:
    valid = [row for row in rows if not row["problem"]]
    requests = sum(row["status"] == "request" for row in valid)
    successes = sum(row["status"] == "success" for row in valid)
    # This is a minimum visibility gate, deliberately not an exchange matcher.
    visible = requests > 0 and successes > 0
    with (out / "reports.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=COLUMNS)
        writer.writeheader()
        writer.writerows(rows)
    lines = [
        "# USB capture visibility check", "",
        f"Scope: USB bus {bus}, device address {device} (verify identity separately).", "",
        f"- Packets: {stats['packets']}; in scope: {stats['scoped_packets']}",
        f"- Candidate payload fields: {stats['payload_fields']}",
        f"- Other payload lengths (not decoded): {stats['short_or_other_payloads']}",
        f"- Malformed hex fields: {stats['malformed_hex']}",
        f"- Structurally valid reports: {len(valid)}; rejected candidates: {len(rows) - len(valid)}",
        f"- Requests: {requests}; vendor success reports: {successes}", "",
        "Result: " + ("REQUEST/RESPONSE VISIBILITY PRESENT" if visible else "INCONCLUSIVE"), "",
        "This is a framing/visibility check only. Requests and responses are NOT paired.",
        "It does not verify VID/PID, control-transfer type, echoes, assignment identity,",
        "changed-value readback, restore, physical behavior, or measured poll cadence.",
        "Inspect setup/URB details in Wireshark; confirm payload boundaries, especially offset 1.",
        "Missing candidates may mean cached reads, another payload field, fragmentation,",
        "truncation, wrong scope, or a nonstandard protocol—not an unsupported feature.",
        "Declared arguments are in arguments_hex; report_hex retains ALL 90 bytes,",
        "including bytes beyond the declared size. Short input reports remain in the pcap.",
        "Keep the original pcap and correlate reports.csv frame/epoch values with UI/log events.", "",
    ]
    (out / "visibility.md").write_text("\n".join(lines), encoding="utf-8")
    return visible


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--pcap", type=Path, help="Read capture with TShark; never live-captures")
    source.add_argument("--pdml", type=Path, help="Read an existing tshark -T pdml export")
    parser.add_argument("--tshark", default="tshark", help="TShark executable path")
    parser.add_argument("--bus", required=True, type=int, help="Verified USB bus, decimal")
    parser.add_argument("--device", required=True, type=int, help="Verified USB address, decimal")
    parser.add_argument("--out", required=True, type=Path, help="New output directory; must not exist")
    args = parser.parse_args(argv)
    if args.bus < 0 or not 0 <= args.device <= 127:
        parser.error("USB bus must be nonnegative and device address must be 0..127")
    try:
        if args.out.exists():
            raise ValueError("Output directory already exists; use a fresh path")
        if args.pdml:
            rows, stats = extract_rows(args.pdml, args.bus, args.device)
        else:
            executable = shutil.which(args.tshark)
            if executable is None:
                raise ValueError(f"TShark not found: {args.tshark}")
            with tempfile.TemporaryDirectory(prefix="opensnek-usb-") as tmp:
                pdml = Path(tmp) / "capture.pdml"
                with pdml.open("wb") as handle:
                    subprocess.run([executable, "-n", "-r", str(args.pcap), "-T", "pdml"],
                                   stdout=handle, check=True)
                rows, stats = extract_rows(pdml, args.bus, args.device)
        args.out.mkdir(parents=True, exist_ok=False)
        visible = write_results(args.out, rows, stats, args.bus, args.device)
    except (OSError, ValueError, ET.ParseError, subprocess.CalledProcessError, StopIteration) as error:
        print(f"Capture check failed: {error}", file=sys.stderr)
        return 1
    print(f"Read {args.out / 'visibility.md'} and {args.out / 'reports.csv'}")
    return 0 if visible else 2


if __name__ == "__main__":
    sys.exit(main())
