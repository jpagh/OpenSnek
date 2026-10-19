# Basilisk V4 HyperSpeed Bluetooth bring-up

Local maintainer hardware, 2026-10-18. The connected device identified as `Razer / BSK V4 HS`, Bluetooth VID:PID `068E:00EC`. No serials, device UUIDs, or profile metadata are included.

All vendor probes ran with the OpenSnek app and background service stopped, using the preferred peripheral name `BSK V4 HS`. The HID discovery probe found one Bluetooth HID candidate with `usage=0x01:0x02`, `input=9`, and `feature=1`; a 3-second passive watch observed no reports.

## Mapped Bluetooth surface

- DPI stage read: `0B 84 01 00`, two visible stages, active stage token `0x02`; the payload uses stage IDs and the shared BLE parser.
- Battery reads: `05 81 00 01` -> `FF`; status read: `05 80 00 01` -> `01`. Battery interpretation uses the observed 0-255 scale; charging semantics were not physically confirmed.
- Power/sleep timeout: `05 84 00 00` / `05 04 00 00`, baseline `300` seconds.
- Lighting zone catalog: `10 80 00 01` -> LED `0A` (underglow).
- Underglow brightness: `10 85 01 0A` / `10 05 01 0A`, baseline `FF`.
- Button reads: `08 84 00 <slot>` and writes: `08 04 01 <slot>`. Readback covered slots `01..05`, `09`, `0A`, `34`, and `35`; slot `06` and unrelated profile slots were not claimed.
- Bluetooth onboard profiles, poll rate, scroll controls, and advanced/software lighting remain hidden.

## Validation results

- Brightness changed `FF -> 60 -> FF`, with successful ACK and authoritative readback at each step.
- Power timeout changed `300 -> 240 -> 300` seconds, with successful ACK and authoritative readback at each step.
- Button slot `01` changed from factory left-click to right-click and was restored using the exact original payload; readback matched before, after, and after restore.
- Wheel-tilt slot `34` changed to right-click and was restored with its exact native short horizontal-scroll payload. The V4 native default block is `0E 01 68 00 14 00 00` (right is `0E 01 69 00 14 00 00`).
- A static-color candidate write to `10 03 00 0A` ACKed, but `10 83 00 0A` remained all-zero before and after. Color/effect controls are therefore not exposed.
- DPI changed-write/readback and persistence were not run because the short active table read does not expose a complete raw restore journal for the hidden tail entries. The shipped DPI write path preserves stage IDs and permits the V4 33,000-DPI ceiling in code, but the V4 Bluetooth write remains mapped rather than hardware-validated here.

See the initial transcripts in `read-only-discovery.txt` and `roundtrips.txt`.

## USB parity follow-up

The [parity follow-up](parity-followup.md) adds hardware-validated low-battery
threshold reads/writes through the app bridge and editor, including clamping and
exact original raw restoration. An alternate target-1 static-color candidate
also ACKed without changing readback; colors/effects stay hidden, including in
saved/backend patches and regular probe writes. Charging stays unknown without
a trustworthy USB fallback. DPI writes remain mapped, not hardware-validated:
additional pair-list/stored-table reads do not recover the original hidden live
stage IDs/reserved bytes needed for an exact restore. No polling setter was mapped.
