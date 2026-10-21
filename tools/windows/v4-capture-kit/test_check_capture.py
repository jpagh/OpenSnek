"""Synthetic offline tests; no hardware, OpenSnek, TShark, or third-party packages."""

import contextlib
import csv
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

import check_capture as checker


def fix_checksum(body):
    body[88] = 0
    for value in body[2:88]:
        body[88] ^= value
    return bytes(body)


def report(status=0, command=0x8C, arguments=b"\x01\x04\x00", size=None):
    body = bytearray(90)
    body[0] = status
    body[1] = 0x1F
    body[5] = len(arguments) if size is None else size
    body[6] = 2
    body[7] = command
    body[8:8 + len(arguments)] = arguments
    return fix_checksum(body)


def packet(root, number, payload, bus=1, device=7, name="usb.capdata", alias=False):
    node = ET.SubElement(root, "packet")
    proto = ET.SubElement(node, "proto", name="usb")
    for key, value in [("frame.number", number), ("frame.time_epoch", f"177000000{number}.125"),
                       ("usb.bus_id", bus), ("usb.device_address", device),
                       ("usb.endpoint_address", "0x00"), ("usb.urb_id", number),
                       ("usb.urb_type", "URB_COMPLETE")]:
        ET.SubElement(proto, "field", name=key, show=str(value))
    ET.SubElement(proto, "field", name=name, value=payload.hex())
    if alias:
        ET.SubElement(proto, "field", name="data.data", value=payload.hex())
    return node


class FramingTests(unittest.TestCase):
    def test_exact_body_and_arguments(self):
        parsed, error = checker.decode_report(report())
        self.assertEqual(error, "")
        self.assertEqual(parsed.offset, 0)
        self.assertEqual(parsed.status, "request")
        self.assertEqual(parsed.body[8:11], b"\x01\x04\x00")

    def test_single_report_id_prefix(self):
        parsed, error = checker.decode_report(b"\x00" + report(2))
        self.assertEqual(error, "")
        self.assertEqual(parsed.offset, 1)
        self.assertEqual(parsed.status, "success")

    def test_no_arbitrary_scan_or_truncation(self):
        for payload in [report()[:-1], b"\x00\x00" + report(), report() + report(), b"\x05\x31\x6e"]:
            with self.subTest(length=len(payload)):
                self.assertIsNone(checker.decode_report(payload)[0])

    def test_bad_checksum_rejected(self):
        body = bytearray(report())
        body[12] ^= 1
        self.assertEqual(checker.decode_report(bytes(body))[1], "checksum mismatch")

    def test_header_guards_independent_of_checksum(self):
        for offset, value, reason in [(0, 6, "unknown status"), (4, 1, "nonzero protocol byte"),
                                      (5, 81, "argument size exceeds 80"), (89, 1, "nonzero reserved byte")]:
            with self.subTest(offset=offset):
                body = bytearray(report())
                body[offset] = value
                self.assertEqual(checker.decode_report(fix_checksum(body))[1], reason)

    def test_rejection_is_not_success(self):
        for status in [1, 3, 4, 5]:
            with self.subTest(status=status):
                parsed, error = checker.decode_report(report(status))
                self.assertEqual(error, "")
                self.assertNotEqual(parsed.status, "success")

    def test_checksum_covers_bytes_beyond_declared_size(self):
        body = bytearray(report(size=0))
        body[87] = 0xEA
        parsed, error = checker.decode_report(fix_checksum(body))
        self.assertEqual(error, "")
        self.assertEqual(parsed.body[87], 0xEA)


class CaptureTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.pdml = self.root / "sample.pdml"
        self.tree = ET.Element("pdml")

    def save(self):
        ET.ElementTree(self.tree).write(self.pdml, encoding="utf-8")
        return self.pdml

    def extract(self):
        return checker.extract_rows(self.save(), bus=1, device=7)

    def run_cli(self, *extra):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return checker.main(["--pdml", str(self.save()), "--bus", "1", "--device", "7",
                                 "--out", str(self.root / "analysis"), *extra])

    def test_scope_excludes_other_bus_and_device(self):
        packet(self.tree, 1, report(), device=8)
        packet(self.tree, 2, report(), bus=2)
        packet(self.tree, 3, report())
        rows, stats = self.extract()
        self.assertEqual([row["frame"] for row in rows], ["3"])
        self.assertEqual(stats["packets"], 3)
        self.assertEqual(stats["scoped_packets"], 1)

    def test_payload_alias_deduplication_is_only_per_packet(self):
        packet(self.tree, 1, report(), alias=True)
        packet(self.tree, 2, report(), alias=True)
        rows, _ = self.extract()
        self.assertEqual(len(rows), 2)

    def test_short_hid_is_counted_not_guessed_as_configuration(self):
        packet(self.tree, 1, b"\x05\x31\x6e")
        rows, stats = self.extract()
        self.assertEqual(rows, [])
        self.assertEqual(stats["short_or_other_payloads"], 1)

    def test_unknown_field_is_not_scanned(self):
        packet(self.tree, 1, report(), name="unrecognized.raw")
        rows, _ = self.extract()
        self.assertEqual(rows, [])

    def test_rejected_candidate_is_retained(self):
        bad = bytearray(report())
        bad[88] ^= 1
        packet(self.tree, 1, bytes(bad))
        rows, _ = self.extract()
        self.assertEqual(rows[0]["problem"], "checksum mismatch")
        self.assertEqual(rows[0]["status"], "unrecognized")

    def test_malformed_hex_is_reported(self):
        node = packet(self.tree, 1, report())
        node.find(".//field[@name='usb.capdata']").set("value", "zz")
        rows, stats = self.extract()
        self.assertEqual(rows, [])
        self.assertEqual(stats["malformed_hex"], 1)

    def test_zero_declared_size_keeps_raw_response_tail(self):
        body = bytearray(report(2, size=0))
        body[8] = 3
        packet(self.tree, 1, fix_checksum(body))
        rows, _ = self.extract()
        self.assertEqual(rows[0]["arguments_hex"], "")
        self.assertEqual(bytes.fromhex(rows[0]["report_hex"])[8], 3)

    def test_complete_cli_writes_csv_and_limitations(self):
        packet(self.tree, 1, report())
        packet(self.tree, 2, report(2))
        self.assertEqual(self.run_cli(), 0)
        out = self.root / "analysis"
        with (out / "reports.csv").open(newline="", encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle))
        self.assertEqual([row["status"] for row in rows], ["request", "success"])
        self.assertEqual(rows[1]["epoch"], "1770000002.125")
        self.assertIn("NOT paired", (out / "visibility.md").read_text())

    def test_request_without_success_is_inconclusive(self):
        packet(self.tree, 1, report())
        packet(self.tree, 2, report(5))
        self.assertEqual(self.run_cli(), 2)
        self.assertIn("INCONCLUSIVE", (self.root / "analysis" / "visibility.md").read_text())

    def test_empty_capture_is_inconclusive(self):
        self.assertEqual(self.run_cli(), 2)

    def test_existing_output_is_not_overwritten(self):
        out = self.root / "analysis"
        out.mkdir()
        marker = out / "keep.txt"
        marker.write_text("original")
        self.assertEqual(self.run_cli(), 1)
        self.assertEqual(marker.read_text(), "original")
        self.assertEqual(list(out.iterdir()), [marker])

    def test_invalid_xml_returns_error(self):
        self.pdml.write_text("<broken>")
        with contextlib.redirect_stderr(io.StringIO()):
            result = checker.main(["--pdml", str(self.pdml), "--bus", "1", "--device", "7",
                                   "--out", str(self.root / "analysis")])
        self.assertEqual(result, 1)
        self.assertFalse((self.root / "analysis").exists())

    def test_pcap_path_invokes_only_offline_tshark(self):
        def fake_run(command, *, stdout, check):
            self.assertEqual(command, ["tshark-test", "-n", "-r", "input.pcapng", "-T", "pdml"])
            self.assertTrue(check)
            stdout.write(b"<pdml />")

        with patch.object(checker.shutil, "which", return_value="tshark-test"), \
                patch.object(checker.subprocess, "run", side_effect=fake_run), \
                contextlib.redirect_stdout(io.StringIO()):
            result = checker.main(["--pcap", "input.pcapng", "--bus", "1", "--device", "7",
                                   "--out", str(self.root / "analysis")])
        self.assertEqual(result, 2)


if __name__ == "__main__":
    unittest.main()
