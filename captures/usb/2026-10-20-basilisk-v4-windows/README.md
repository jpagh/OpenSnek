# Basilisk V4 HyperSpeed — Windows receiver evidence

Source: Jack's private `v4-capture-kit/evidence-2026-10-20-v4hs-receiver`,
Windows 11 / Synapse 4.0.827, receiver `1532:00EA`, firmware 1.0.16.0,
2026-10-20 through 2026-10-21 (CDT, UTC-05:00). Cable disconnected.
Raw pcaps/logs/exports, serials, account IDs, and personal profile metadata are
not imported. These findings do not establish wired/Bluetooth equivalence.

**The full raw-USB audit supersedes the original bundle summaries and the initial
48-read analysis.** The kit checker omitted control-IN completion payloads; its
zero-success counts and the resulting claims of absent readbacks were incorrect.
In particular, receiver polling has authoritative changed/restored readbacks, and
the reconnect capture contains normal-layer Default button reads.

This remains **Synapse capture evidence**, not macOS OpenSnek hardware validation.
New polling/button behavior is **Mapped** pending scoped app changed-write,
readback, exact-original restore, and physical checks.

## Audit coverage and reproducibility

All 15 nonempty action pcaps were decoded, including raw control-IN completions:
29,157 checksum-valid 90-byte reports, comprising 28,746 requests, 407 successes,
and four busy/failure/timeout reports, across 33 distinct class/command pairs.
The two other passes have no pcap. Both descriptor-only discovery pcaps were also
inspected, along with the decoded exports and final Synapse middleware logs.

Method: parse pcapng section/interface/enhanced-packet blocks (USBPcap link type
249), scope bus 2 and receiver addresses 5/6/7, respect the USBPcap header length
(28 for these control transfers), and separate setup/data/status stages.
SET_REPORT setup payloads contain eight setup bytes before the 90-byte request;
GET_REPORT data completions contain the 90-byte response directly. Validate
size/protocol/reserved fields and XOR bytes 2..87, then pair responses with the
preceding request by pass, transaction ID, class and command. Do not scan arbitrary
packet offsets or infer response absence from missing Wireshark decoded fields.

[feature-exchanges.json](feature-exchanges.json) retains 177 exact sanitized
request/response pairs with source pass/frame references: 72 button reads,
66 button writes, 23 polling reads, two polling writes, ten Smart Dimming candidate
writes, and four profile inventory/count reads. Tests consume these real fixtures,
including all 36 normal-layer button reads and 19 bank-1 polling reads. Metadata,
serial responses, unrelated keyboard input and user profile names are excluded.

Standalone pcap SHA-256:
`e17f330f64508ca1e483c1a63cda3c96a64c5c297d8f54044460e722e8e7c2e3`.

## Receiver polling: query/change/restore established

`…-poll-read-change-500-2`:

| Request / response frames | Command | Request args | Successful response args |
|---|---|---|---|
| 5703 / 5706 | `00:8E` | `01 00` | `01 01` (original 1000 Hz) |
| 5707 / 5710 | `00:0E` | `01 02` | `01 02` (write ACK) |
| 5713 / 5716 | `00:8E` | `01 00` | `01 02` (changed 500 Hz) |

`…-poll-restore-1000`:

| Request / response frames | Command | Request args | Successful response args |
|---|---|---|---|
| 4351 / 4354 | `00:8E` | `01 00` | `01 02` (500 Hz) |
| 4357 / 4360 | `00:0E` | `01 01` | `01 01` (write ACK) |
| 4363 / 4366 | `00:8E` | `01 00` | `01 01` (restored 1000 Hz) |

All declare size 2 and match transaction/class/command/checksum. This is a query,
not an unexplained commit envelope. Bank-2 queries also return `02 01`, but only
bank-1 writes were captured. App polling therefore uses bank 1, `00:0E/8E`, and
one strict changed-value readback. It never sends wired `00:40/C0` or legacy
`00:05/85` for this receiver. Choices are **500/1000 Hz only**: 125 Hz is offered
by Synapse but was never selected, so its code is not guessed. Measured cadence,
power-cycle persistence and macOS runtime validation are still unclaimed.

## Configuration slots, defaults and standalone operation

`02:0C`, size 10: `<bank> <slot> <layer> <seven-byte function>`.
Passive HID key IDs are not configuration slot IDs.

| Physical control | Slot | Captured changed function | Official Default write |
|---|---|---|---|
| AI Prompt Master | `80` | Right click `01 01 02 00 00 00 00`; 5 `02 02 00 22 00 00 00` | `00 00 00 00 00 00 00` |
| Hypershift Clutch | `39` | Right click `01 01 02 00 00 00 00`; Left Alt `02 02 00 E2 00 00 00` | `0C 01 01 00 00 00 00` |
| Bottom / profile button | `0E` | DPI Cycle Up `06 01 06 00 00 00 00` | `07 01 04 00 00 00 00` |

Host AI remap/Default are `…-ai-remap-rightclick` 6219/6222 and
`…-ai-restore-default` 5999/6002. Hypershift remap/Default are
`…-hypershift-remap-rightclick-retry` 5147/5150 and 10175/10178. These are
ACKs, not immediate assignment queries. Jack confirmed right-click behavior.

The **reconnect** pass has 24 assignment query responses, not zero:

- Normal Hypershift: request 3099 (`01 39 00`), response 3112
  (`01 39 00 0C 01 39 00 00 00 00`). Thus `0C 01 39` is also a normal-layer
  Default read representation, not solely a shifted default.
- Normal AI: request 3135 (`01 80 00`), response 3150
  (`01 80 01 00 00 00 00 00 00 00`). The stored flag can be 1 even for a
  normal request. Keep function bytes at report offsets 11..17; do not use
  layer-echo mismatch as a reason to shift the function block left.
- Normal wheel tilt: responses 3086/3092 contain `0E 03 68/69 00 14 00 00`.
  Earlier local macOS captures also validated `0E 01 68/69 00 14 00 00`.
  Both hydrate as Default; explicit horizontal-scroll assignments use the
  captured class-`0E`, length-3 body, not a generic class-`01` click.

The standalone pass adds 48 bank-1/2, normal/shifted `02:8C` query responses.
Selected normal readings also appear in [normal-bindings.csv](normal-bindings.csv).
Normal custom keyboard blocks must remain custom, not be normalized to Default.
With Synapse closed, endpoint `83` emitted `00 00 22 …` (AI) and `00 00 E2 …`
(Hypershift); Jack confirmed 5 and Alt worked. Onboard mappings execute without
Synapse, unlike host-injected behavior seen in earlier passes.

Bank-2 changes are followed by bank-1 projection writes. No bank-0 Synapse
assignment access is captured; existing local nine-button bank-0/1 validation
must not be generalized into a new-controls validation claim. App/probe new-control
writes are serialized and checked against one same-bank/slot readback. They
require exact function bytes, except the narrowly captured Hypershift Default
write `0C 01 01` → read `0C 01 39` representation. Raw originals are not rewritten
through this normalization. Any other mismatch/missing response fails, with no
command-level retry. Shifted-layer editing remains out of scope.

## Keyboard turbo timing

Page Up/Down turbo writes and reads use `0D 04 00 4B/4E 00 53 00`.
Exports label both **12 presses/sec**; Synapse's host mapping labels the same
interval `delay:83`. The `0x53` field is therefore an 83 ms interval, not the old
linear 1..255-to-20..1 UI scale. Receiver UI conversion uses milliseconds and
preserves the captured 12/s → 83 ms → 12/s case. The existing raw clamp is retained,
so the receiver picker uses the representable **4..20/s** range; other devices
and transports keep their prior mapping. This is mapped timing, not a measured
physical-rate claim. Existing raw turbo values remain byte-preserved on hydration.

## Additional research, deliberately not writable support

- **Profiles:** `05:8A` returns maximum 5; `05:80` returns assigned count 1 then
  2; `05:81` changes from `05 01` to `05 01 02`. Middleware confirms
  `maxProfilesSupported:5`, `numOfProfiles:2`, `profileIdList:[1,2]`.
  `05:80` must not be mistaken for active-bank identity. Four `05:88` metadata
  chunks read bank 2 at offsets 0/64/128/192, corroborating the exported onboard
  profile. Creation occurred outside the pcap; selection is settings projection,
  not proof of a profile-selector command. CRUD/direct active selection stay hidden.
- **Smart Dimming:** `07:13` writes `01 01 01` (host enabled) versus `01 00 01`
  (onboard disabled), with ACKs and timestamp-matched middleware enabled messages.
  This maps an enable/value write candidate, but there is no authoritative getter,
  threshold sweep, physical dimming check or verified raw-original restore.
  Exported 25% and middleware `value:1` are insufficient to infer a full value scale.
- **Smart Tracking/calibration:** settings appear in cached logs, but calibration
  operations log errors. `06:8E` is macro-storage information per the middleware,
  not a tracking register. No new calibration support is inferred.
- **Lighting stream:** the supposed `0F:03` heartbeat is 28,334 size-8 RGB writes
  (`00 00 00 00 00 R G B`), roughly 20 Hz during the host effect. They have no
  per-frame response in these captures. This maps a stream candidate, not verified
  software-frame rendering/recovery or additional built-in effects. Reactive remains
  hidden after the earlier failed physical validation.
- No unequal X/Y edits, high-DPI ceiling writes, 125 Hz change, full native
  Hypershift layer workflow, macOS AI integration or Bluetooth/wired extra-control
  equivalence was captured.

## State safety and test scope

The user-created onboard profile remains active with custom AI/Alt/scroll/DPI
mappings. It was intentionally retained, not restored to the initial host profile.
Offline analysis sent no hardware commands. Future hardware tests must journal all
selected-bank originals before mutation and restore persistent before live.
**Default is not a substitute for the user's original assignment.**

Regression coverage includes the real report fixtures, receiver-only capabilities,
strict polling parsing/write verification, native Default representations, turbo
and horizontal-scroll bytes, and editor action-to-patch behavior. A fresh app build
is for user testing, not a claim that every newly mapped feature has passed macOS
hardware validation.

## Build/check result (2026-10-21)

- **Pass:** full fresh `./OpenSnek/scripts/pre_push_checks.sh`: 23 developer-tool
  Python tests and 821 Swift tests, zero failures; 13 opt-in hardware tests skipped.
  Includes strict Swift format, SwiftLint, compiler-body diagnostics and the
  device-validation manifest check. The narrower affected suite also passed
  (188 tests, five hardware skips).
- **Pass:** `./run.sh --show-window` freshly built the debug app through Xcode,
  staged `OpenSnek/.dist/OpenSnek.app`, and verified one visible foreground main
  window. Build uses the standard local development version `0.1.0` (build 1),
  with an ad-hoc signature and stable bundle identifier.
- Executable SHA-256:
  `f769232ed368f3bedec63e09e02523861dae6b56d85a45332be145c7a50fd8da`.
- **Skipped:** live feature mutation/restore, measured polling/turbo cadence,
  new-button physical checks, and persistence checks. Launch verification is not
  feature-level hardware validation. No raw probes were sent.
