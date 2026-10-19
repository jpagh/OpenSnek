# USB/BLE parity follow-up

Local maintainer hardware, Jack, 2026-10-18. Owner authorized stopping the app/service and exact-scope, journaled, reversible probes. One V4 Bluetooth HID candidate (`068E:00EC`, `BSK V4 HS`) was present. All vendor exchanges were serialized with app/service stopped. No DPI, profile-assignment, device-mode, or polling-rate writes were sent.

## Outcomes

| Wired feature | BLE finding / implementation | Result / limit |
|---|---|---|
| Sleep timeout | Already mapped `05 84/04 00 00` | Prior changed-write/readback/restore retained |
| Low-battery threshold | `05 82/02 00 00`; original raw `4D` (77) | **pass**: `4D -> 33 -> 4D`; app apply then checked `33`, `30`, lower clamp `0C`, upper clamp `3F`, full-state telemetry, and exact raw restore to `4D` |
| Brightness | Projection `10 85 01 0A` = `FF`; hardware-active `10 85 00 0A` = `3F` | Distinct original banks retained, restored, and verified; do not assume projection and active banks always agree or infer physical rendering from register readback |
| Color/effects | Target `1` static candidate `10 03 01 0A`, payload `01 00 00 01 00 FF 40 00 00 00` | **fail** for changed state: ACK `02`, both target `0` and `1` reads remained ten zero bytes. Prior target `0` candidate had the same limitation. Both originals restored/verified; no new physical rendering claim |
| DPI writes/stage selection | Target `1` projection is 15 bytes, only two visible rows, last marker absent. `0B 82 01 00` exposes five pairs but no stage IDs | **skipped**: full original hidden IDs/reserved bytes are not recoverable from the current reads. Stored targets `2/3` expose a longer factory-shaped table, but it is not an authoritative original live baseline. Do not combine those tables into a guessed restore |
| Poll rate | `01 85 00 00` and USB-like extended candidate `01 C0 00 00` return `05` | No mapped BLE setter; wired 125/250/500/1000 Hz settings are not inferred to exist over BLE |
| Device mode | `01 82 00 00` -> `00 00` | Read only; no mode mutation or new editor control |
| Profile management | `03 80` inventory and `03 82` active target -> `01`; stored lighting targets `2..5` contain spectrum-shaped bodies | Reads do not validate assignment/CRUD; remains hidden, as on V4 USB |
| Charging | Vendor status meaning remains unvalidated | App now leaves charging unknown without a trustworthy USB fallback rather than interpreting status `1` as charging |
| Extra buttons / scroll controls | No new authoritative mapping | Still hidden on both V4 transports |

Unsupported saved/backend color/effect patches are filtered before BLE writes. The regular probe color command rejects a brightness-only profile before a vendor mutation; the explicit raw command remains available for journaled research. App and probe now share the profile-owned zone-addressing decision. Probe reads distinguish unsupported color from a failed read.

## Evidence and checks

- `parity-read-only.txt`, `parity-read-only-extra.txt`: finite read-only discovery, no serial/profile metadata.
- `validate-parity.py`, `parity-roundtrip.txt`, `parity-restored.json`: threshold changed write and alternate color-address experiment; exact originals captured before mutation, verified phase `restored`. This is a focused research harness using Swift `OpenSnekProbe`, not a second protocol implementation.
- `parity-recovery.txt`: explicit recovery-only path passed with all original readbacks matching.
- `BasiliskV4BluetoothParityTests/testHardwareThresholdApplyReadbackAndExactRestore`, `threshold-app-pass.txt`, `threshold-app-restored.json`: **pass**, actual app bridge apply/delta/full read path, raw original 77 restored without editor clamping. Initial attempt used the HID-watch suffix rather than the app ID and failed exact selection before any mutation; the corrected exact app identity passed.
- Focused software suite: 159 tests, 2 opt-in hardware skips, 0 failures. The V4 BLE threshold hardware gate was then run separately and passed; this does not validate the skipped USB hardware test.
- Probe build passed; read-only lighting probe prints `color=unsupported`, and regular color writes reject before mutation. Formatting, validation manifest, and `git diff --check` passed. Additional patch-merge/recovery-adapter and editor regression suites passed; no full pre-push/publishing run or power-cycle/persistence check.
- Rebuilt/restarted with `./run.sh`; foreground app/window verified and service running. Jack confirmed the new Bluetooth Low Battery Threshold card appears and the mouse/lighting otherwise look normal. This is UI/normal-behavior confirmation, not physical validation of a new lighting encoder.

For a new hardware threshold run, stop app/service, keep only the selected V4 connected, and use a **new absolute journal**:

```bash
OPEN_SNEK_HW=1 \
OPEN_SNEK_HW_DEVICE_ID='068e:00ec:97eee623:bluetooth' \
OPEN_SNEK_HW_JOURNAL=/tmp/v4-ble-threshold-NEW.json \
swift test --package-path OpenSnek \
  --filter BasiliskV4BluetoothParityTests/testHardwareThresholdApplyReadbackAndExactRestore
```

That exact app ID was observed locally; rediscover the device if its location changes. The passive HID research command prints `:bluetooth-hid`, whereas `BridgeClient` scopes the same identity with `:bluetooth`. Do not choose the first available mouse. Recovery uses the same test, same exact app ID, and `OPEN_SNEK_HW_RECOVER_JOURNAL` in place of the new journal variable. Preserve failed journals; never substitute factory defaults.

Next lighting evidence should be a V4-specific official Synapse BLE capture of a changed static color/effect followed by restore, including its setup traffic. Neither an ACK nor a readable unrelated stored bank establishes a working live lighting encoder. See the Windows BTVS workflow in `captures/README.md`.
