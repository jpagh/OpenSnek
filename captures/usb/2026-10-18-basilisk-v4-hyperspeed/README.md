# Basilisk V4 HyperSpeed: receiver and wired bring-up

Local maintainer hardware, 2026-10-18; owner/physical confirmations: Jack.
Identity: Razer Basilisk V4 HyperSpeed, VID:PID `1532:00EA`, supplied 2.4 GHz
receiver. Firmware read `00:81` payload `01 00 10 00`. Naga Pro remained attached;
all probes selected PID `00EA` and all mutating tests required exact device ID
`1532:00ea:02150000:usb`. No serials or personal profile metadata are included.

## Expanded wired controls (current wired scope)

After the initial polling-only pass, owner requested the remaining wired controls.
All mutations used exact identity `1532:00eb:02141000:usb`, receiver unplugged,
app/service stopped, new journals and verified raw-original restoration.

- `wired-controls-read-only.txt`: scalar DPI 2200, two stages 1200/2200, sleep
  300 s, low-battery raw 77, underglow brightness 255, effect Off, nine standard/
  tilt binding reads; battery raw 136 -> 53%, charging=yes (one sample only).
- `wired-dpi-validation.txt` and `wired-dpi-diagnostic.txt`: initial **fail** from
  an incorrect test expectation, not a device protocol failure. The X-only stage
  patch intentionally preserved Y, so observed scalar was X=1000/Y=1200 rather
  than the test's assumed 1000/1000. Both journals have phase `restored`, archived
  as `wired-dpi-initial-restored.json` / `wired-dpi-diagnostic-restored.json`.
- `BasiliskV4DPITests/testHardwareUSBStageTransitionsAndExactRestore`,
  `wired-dpi-pairs-pass.txt`, `wired-dpi-restored.json`: **pass** with explicit
  linked X/Y pair edits, active-stage-only selection, count expansion/reduction,
  and exact original live/persistent raw stage/scalar restoration. No independent
  X/Y editor or high-DPI ceiling-write validation is claimed.
- `BasiliskV4OnboardingTests/testHardwareReceiverButtonsAndPowerRestoreExactly`,
  `wired-buttons-power-pass.txt`, `wired-buttons-power-restored.json`: **pass**
  for right-click + Default on all nine slots, sleep/low-battery/brightness changed
  writes/readbacks and exact originals restored. The legacy test name is retained
  for recovery, but scope and archived journal identify the wired device.
- `BasiliskV4LightingTests/testHardwareEffectApplyReadbackAndExactRestore`,
  `wired-lighting-pass.txt`, `wired-lighting-restored.json`: **pass**, seven
  supported modes via app apply + direct readback with exact raw original restore.
- Owner confirmed all wired sections appeared and worked, original standard/tilt
  buttons worked, and checked Static/Spectrum/Wave/Pulse rendering over the cable.
  Reactive stays hidden following the previous physical failure; it was not
  re-enabled on wired. AI/Hypershift mapping, profile CRUD, software frames and
  Bluetooth remain unclaimed. No wired lifecycle/persistence or charging-transition
  validation was added.
- Owner reported four polling choices overflowed the fixed 220-point control.
  Picker now uses intrinsic horizontal size with a 220-point minimum and trailing
  alignment, retaining three-choice alignment without clipping the fourth.
  Owner confirmed the rebuilt four-choice picker is contained and right-aligned.

## Initial wired polling follow-up

Owner unplugged receiver and connected the mouse by USB data cable. Discovered
identity `1532:00EB`, exact ID `1532:00eb:02141000:usb`, is distinct from receiver
`00EA`. Read-only `00:85` rejects on both, and `00:C0` rejects on receiver but
succeeds on wired. Wired `00:C0` payload is `<target> <rate>`; original target 0/1
raw rate `08` = 1000 Hz. Size 1 requests still return the rate in args[1]; size 2
also succeeds and is used by the app. See `poll-rate-read-only.txt` and
`wired-poll-rate-read-only.txt`.

[OpenRazer's polling-rate2 implementation](https://github.com/openrazer/openrazer/blob/477f4d6d3ab7e9deb6310d5bd3742560c5cbe80d/driver/razerchromacommon.c)
provided the candidate `00:C0/40` contract. Wired changed writes through `00:40`,
size 2, args `<target> <rate>` passed for both targets and these values:

| Hz | Raw |
|---|---|
| 125 | `40` |
| 250 | `20` |
| 500 | `10` |
| 1000 | `08` |

- `validate-wired-poll.py`, `wired-poll-validation.txt`,
  `wired-poll-restored.json`: **pass** with exact original target 0/1 restoration;
  raw recovery supports `--recover` and requires the exact wired device.
- `BasiliskV4PollingTests/testHardwareWiredPollApplyReadbackAndExactRestore`,
  `wired-app-poll-validation.txt`, `wired-app-poll-restored.json`: **pass** through
  actual app apply/readback, with exact original values restored and verified.
- Initial app profile `basilisk_v4_hyperspeed_wired` was polling-only: four validated
  choices, extended encoding, strict immediate target-0 readback after writes.
  Other wired controls were subsequently validated independently as documented
  above. Receiver polling remains disabled; its original rate was never read or changed.
- No above-1000 Hz test, physical report-cadence measurement, persistence,
  wired reconnect, or receiver cross-projection validation was performed. A raw
  register readback is not a physical cadence measurement. Wired original rate
  after automated tests is 1000 Hz.
- Owner confirmed the rebuilt foreground app showed all four choices, successfully
  changed rate while remaining Connected, and returned to 1000 Hz.
  `wired-poll-final-ui-readback.txt` independently confirms target-0 raw `08`
  after that manual UI check. This still does not measure physical report cadence.

## Expanded lighting follow-up (current receiver scope)

The initial brightness-only scope below is retained as bring-up history. Subsequent
`0F:82` reads at LED `0A` established a valid 12-byte effect body for both live 0
and stored 1. Original payload `00 0a 03 01 28 01 00 ff 00 00 ff 00` reports
Spectrum, agreeing with the owner's slowly cycling physical lighting.

- `validate-lighting.py`, `lighting-effects-validation.txt`,
  `lighting-effects-restored.json`: scoped raw effect transitions, **pass** with
  exact original live/stored raw restoration. Explicit `--recover` supported.
- `BasiliskV4LightingTests/testHardwareEffectApplyReadbackAndExactRestore`,
  `app-lighting-effects-validation.txt`, `app-lighting-effects-restored.json`:
  app apply -> strict readback -> state telemetry, **pass**; exact original raw
  live/stored effect snapshot restored and verified.
- All eight standard mode bodies returned expected written fields, including both
  Wave directions and both Pulse colors. The owner then checked rendering:
  **Reactive failed** despite successful register readback; other modes worked.
  Reactive is excluded from the profile/picker and filtered from saved/backend
  effect patches. The owner was asked to finish on Spectrum; a later read-only
  check (`final-live-effect.txt`) instead reports Static green. This records the
  current setting, not a claim of exact original-state restoration after manual
  UI edits. The automated test journals above separately verify exact restore.
- Current UI supports brightness, Off, Static color, Spectrum, Wave, and Pulse
  (random/single/dual). The observed effect travels through Codable service state,
  stable telemetry merges and DPI-only projections, and hydrates the editor.
  Effect writes require one authoritative readback of changed fields; no retries.
- No custom software frames or persistence validation was added. An initial launch
  lacked a visible-window acknowledgment; `./run.sh --show-window` subsequently
  verified a foreground window before physical checks.

## Extra-button mapping blocker

`extra-buttons-passive.txt` received no reports before Input Monitoring approval.
`extra-buttons-passive-approved.txt` then captured left click and one auxiliary
report `05 31 6e ...`; this alone is not an authoritative configuration-slot ID.
The longer isolated capture `extra-buttons-passive-isolated.txt` captured only
motion reports even though the owner confirmed both controls were pressed.
Candidate read-only register results are retained in `extra-buttons-candidates.txt`
and `extra-buttons-layers.txt`: several success frames contain invalid lengths,
unrecognised function classes, or incorrect live slot echoes. They must not be
used as factory defaults or justification for blind remap writes. No extra-button
mutation was attempted.

AI Prompt Master and Hypershift remapping remains **blocked**, not implemented.
Owner has Windows/Synapse available but needs Wireshark/USBPcap installed. Required
next evidence is a receiver-scoped USB capture of each physical control's official
assignment read, changed remap, and Default restore. Preserve original settings and
avoid typing personal text during a USB capture. BTVS is not the USB capture path.

## Sources

- [Razer support/specifications, RZ01-0568](https://mysupport.razer.com/app/answers/detail/a_id/21065/~/razer-basilisk-v4-hyperspeed-%7C-rz01-0568-support-%26-faqs)
  (owner supplied an offline HTML copy): 33,000 DPI, 1-zone underglow RGB,
  wheel tilt, Hypershift, AI Prompt Master, five hardware profiles, and three
  physical transports. Specifications alone do not validate protocol support.
- [Razer product page](https://www.razer.com/gaming-mice/razer-basilisk-v4-hyperspeed)

## Initial bring-up evidence matrix (lighting superseded above)

| Feature | Read | Changed write/readback | Exact restore | Physical / limits |
|---|---|---|---|---|
| DPI/stages | 1600; active token 3; IDs 1..5, 400/800/1600/3200/6400 | Pass: first row 1000, active token 1, then active-token-only change to 5 | Pass: live + persistent table/scalar compared with originals | App readings accepted by owner; independent X/Y and ceiling writes not tested |
| Buttons 1,2,3,4,5,9,10 | Both persistent 1 and direct 0 | Pass: right-click and Default on every slot, both targets | Pass: original blocks on both targets, persistent before live | Original standard controls accepted by owner; no physical test while remapped |
| Tilt 52,53 | Native `0e 01 68/69 00 14 00 00` | Pass: right-click and Default, both targets | Pass | Owner confirmed both physical tilt directions after restore; no turbo/custom horizontal-scroll validation |
| Power | Sleep 300 sec; low-battery raw 77 | Pass: sleep 360, threshold 51 | Pass: raw original threshold 77, not editor-clamped | Threshold UI remains existing 12..63 write range; threshold scale not independently calibrated |
| Battery | raw 123 -> 48%, not charging | No write | N/A | Midrange sample only; no charging-transition validation |
| Underglow brightness | LED `0A`, original 85; `01`/`04` reject | Pass: 128 readback through app apply | Pass: original 85 | Owner observed brightness change and restoration; colors/effects/streaming disabled |
| Poll rate | `00:85` and exploratory `00:8B` return status 05 while other reads succeed | Not tested | N/A | Disabled, not inferred from vendor specs |
| AI / Hypershift | Candidate extra-slot payloads are not trustworthy standard 7-byte function blocks | Not tested | N/A | Owner and vendor confirm physical buttons; no guessed writable IDs |
| Profile management / scroll-mode controls | Count read exists; not sufficient for CRUD | Not tested | N/A | Disabled; physical scroll toggle remains hardware-controlled |
| Receiver lifecycle | Owner confirmed unavailable after unplug and Connected/readings after replug + movement | N/A | N/A | Windowed app only; closed-window service/sleep/wake not validated |
| Persistence / other transports | Initially not tested | See wired polling follow-up above | N/A | No persistence or Bluetooth support claim; wired polling independently validated |

## Lighting presentation regression

Owner observed slowly cycling physical lighting while the first build displayed
Static. The brightness-only profile has no supported effect list; the card had
used the editor's fallback Static effect and fake fallback color. Regression test
`LightingSummaryPresentationTests/testBrightnessOnlySummaryDoesNotInventStaticEffectOrColor`
failed before the fix. The corrected summary says `Brightness only · Effect unknown`,
hides effect/color controls and swatches, and USB patch filtering omits unsupported
RGB/effect writes (including saved-profile requests). No hardware effect was
changed to make it agree with the UI. This does not establish an effect read map.

## Files and outcomes

- `linked-read-only.txt`: successful read-only baseline; earlier `read-only.txt`
  and `awake-read-only.txt` contain receiver timeouts. An off/on cycle in 2.4 GHz
  mode restored the link; this is not proof of the cause of those timeouts.
- `extra-controls-read.txt`: raw extra-control responses and successful underglow
  brightness target `0A` discovery. Do not interpret arbitrary bytes from an
  unrecognised slot as a valid binding just because status is success.
- `validate-dpi.py`, `dpi-validation.txt`, `dpi-restored.json`: scoped raw DPI
  transition test, **pass**. Archive says `restored`; no pending recovery.
- `buttons-power-validation.txt`: initial **fail**. Editor clamp changed an
  original threshold of 77 to 63 during restore. Direct raw restore/readback
  recovered 77; the corrected hardware helper restores raw originals.
- `post-failure-readback.txt`: all original buttons/sleep intact; threshold 63.
- `buttons-power-recovery*.txt`: failed recovery while unavailable, followed by
  **pass** after owner off/on wake (`buttons-power-recovery-awake.txt`).
- `initial-buttons-power-restored.json`: original failed run's journal after
  successful verified recovery; retained rather than deleted.
- `buttons-power-pass.txt`: corrected standard buttons/power **pass**.
- `extended-pass.txt`: tilt and brightness added, **pass**.
- `extended-defaults-pass.txt`, `extended-restored.json`: final **pass**, all nine
  button right-click/Default transitions plus changed power/brightness and exact
  final restoration. Test: `BasiliskV4OnboardingTests/testHardwareReceiverButtonsAndPowerRestoreExactly`.

Hardware tests must stop app/service, keep the mouse awake, set `OPEN_SNEK_HW=1`,
set the exact `OPEN_SNEK_HW_DEVICE_ID` above, and use a new absolute
`OPEN_SNEK_HW_JOURNAL`. Recovery uses `OPEN_SNEK_HW_RECOVER_JOURNAL` with the same
test. Recovery resolves a working control interface before writes. The DPI script
is a focused evidence harness, not a general recovery tool; preserve its journal
and restore its exact recorded raw payloads if an interrupted run needs recovery.

These finite checks establish only the listed transitions, not long-term
reliability or power-cycle persistence. App launched with `./run.sh`; foreground
main window was verified by the launch receipt.
