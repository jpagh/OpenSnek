# Evidence test plan — Windows only, no OpenSnek runtime

Read `README.md` for setup, identity, capture commands, and safety. Run these in
order. A “pass” means the **evidence case** is complete, not that OpenSnek supports
the feature. Jack must perform/confirm physical and Synapse actions; an agent's
inference from a successful USB transfer is insufficient.

## Result vocabulary

- **Pass:** required observations and files exist; any mutation was restored.
- **Fail:** the case ran but observed behavior contradicted the expectation, or
  restoration failed. Preserve the failure and recovery journal.
- **Blocked:** a prerequisite is missing, a UI action is unavailable, or safe
  original-state restoration cannot be established. Describe the exact blocker.
- **Not attempted:** deliberately skipped; give the reason.

Missing logs/readbacks are evidence gaps, not invented successes. Report checks
individually, for example “physical remap passed; raw readback unavailable.” Keep
**factory Default**, **session-original assignment**, **host behavior**, and
**on-device storage** distinct throughout.

## T0 — Offline kit tests (automated, no hardware)

```powershell
# Run from this folder. Python 3.10+; no pip dependencies.
py -3 -m unittest discover -s . -p 'test_*.py' -v
```

The tests cover:

- exact 90-byte framing and one-byte prefix candidates;
- status/size/protocol/reserved-byte guards and checksum;
- preservation of all response bytes even when declared argument size is zero;
- rejection of truncation, arbitrary packet scanning, and guessed short-HID decoding;
- exact bus/address filtering and per-packet payload-alias deduplication;
- malformed fields and malformed XML;
- CSV output and explicit incomplete-visibility results;
- refusal to overwrite an existing analysis directory;
- offline TShark invocation (`-r`), never live capture/device access.

**Pass:** all tests pass. Save command, Python version, and output with the session.
These synthetic tests do not validate any actual button or poll-rate mapping.

## T1 — Receiver capture visibility (hardware, read-only)

**Precondition:** `1532:00EA`, exact selected receiver, cable disconnected, Synapse
open; journal and privacy precautions in place.

1. Record USB hub, bus, address, interfaces and current UI settings.
2. Save a 15-second idle capture.
3. In a separate pass, capture opening the V4 device and assignment page without
   editing. If cached, try a separately labeled Synapse startup/reconnect capture
   with Jack's approval, rechecking USB scope after reconnect.
4. Run `check_capture.py` using that pass's bus/address. Check `visibility.md` and
   `reports.csv`, then inspect setup/URBs in Wireshark. Pair an actual Feature
   SET_REPORT request and GET_REPORT response, checking transaction/class/command
   and relevant target echoes. A vendor command ending in `8x` can still be
   transmitted by SET_REPORT before its response is retrieved by GET_REPORT.
5. Record matched frame numbers, complete body bytes, status and direction.

**Pass:** configuration request/response visibility is demonstrated for the
receiver, not just motion reports or another device. Checker exit `0` is a useful
signal, not sufficient evidence of a matched exchange. Checker exit `2` does not
by itself fail an idle pass or prove the protocol is unsupported.

**Blocked:** configuration bytes cannot be captured/identified. Resolve that
before making edits; keep the discovery captures for diagnosis.

## T2 — AI Prompt Master control (hardware + Synapse)

**Precondition:** T1 passes; original assignment/layer/profile is recorded and
recoverable. Use only official Synapse UI changes; no raw writes/replays.

1. Capture selecting the AI control in Synapse without editing. Save its exact
   label, available categories, current action, and selected layer.
2. Propose one safe, distinctive alternative that Synapse actually offers (right
   click is an example). Obtain Jack's approval, then capture only that edit and
   Apply. Note any automatic changes to other controls/profiles.
3. In a separate press pass, have Jack press just the control 2–3 times with
   several seconds between presses. Observe the expected result in a harmless
   local test window. Avoid private text and AI prompt submission.
4. If safely reversible, capture selecting **Default** and Apply. Save its exact
   bytes; never substitute a familiar standard-button default.
5. Restore the **original assignment**, which may differ from Default. Capture
   the restoration and have Jack verify the original physical behavior.

**Pass:** physical control and UI identity are established; changed/default/
original transitions have frame/log references; changed behavior and original
restoration are independently confirmed. Report whether configuration readback
was actually present and matched — ACK alone is not readback.

**Blocked/limited:** UI locks the control, no safe remap exists, no device-side
configuration is emitted, or the action appears host-only. Record screenshots,
logs, and bytes without claiming a standard hardware slot. An honest software-only
observation is a useful result; it is not a failed capture installation.

## T3 — Hypershift physical modifier (hardware + Synapse)

Run the T2 sequence on the **physical Hypershift modifier**, not merely a random
button viewed while the shifted-layer UI is selected. Restore AI state before
starting this case. Do not assume this control shares a slot/encoding with AI.

If the modifier is fixed/non-editable, record that UI restriction. With approval,
run a distinct press-only comparison using one known standard button: unmodified
press, modifier hold + same button press, release. Journal that button's existing
normal/shifted assignments first; do not modify them just to produce traffic.

**Pass:** physical modifier identity, normal-versus-shifted semantics and all
permitted reversible transitions are captured, with limitations explicit. A
shifted-layer write on another button is not proof that the modifier is remappable.

## T4 — Receiver polling (hardware + Synapse)

**Precondition:** T1 passes, AI/Hypershift original settings restored; capture
scope is still receiver `00EA`, not cable `00EB`.

1. Capture opening polling/Performance UI and record all choices/current value.
2. If offered and reversible, capture one changed rate and Apply.
3. Look for the actual command family, argument order/target/rate, vendor response
   and any subsequent query returning the changed value. Retain the full sequence.
4. Capture restoring the original rate. Verify the UI value and authoritative
   device readback if available. Record any need to reconnect as an observation,
   not an instruction to retry until a capture looks successful.

**Pass:** official receiver query/change/restore path is evidenced at the actual
verification level available. If the UI has no polling option, mark the change
branch blocked and retain the screenshot/read traffic.

**Not established:** measured physical cadence, rates not selected, persistence,
or wired-to-receiver equivalence. A UI number or register ACK cannot prove these.
The wired `00:C0/40` contract is a comparison hint, never a command to try on the
receiver; receiver reads previously rejected it.

## T5 — Optional wired comparison

**Precondition:** receiver cases restored; Jack agrees to another independent
baseline. Unplug receiver, connect USB data cable, identify `1532:00EB`, journal
wired originals, and reselect the correct USBPcap interface/address.

Run a separate T1 and any useful T2/T3/T4 variants labeled `wired-*`. Known wired
poll choices are 125/250/500/1000 Hz, using extended `00:C0/40`. Let Synapse choose
its commands. Capture exact per-target values, readback and restoration.

**Pass:** independent wired evidence and restore. It does not close a receiver gap.
Skip other wired controls already validated on macOS unless specifically needed
to distinguish a new command shape. Keep unrequested profile CRUD, reset, DPI,
lighting and firmware-update operations out of this session.

## T6 — Evidence integrity and final restoration

1. Review the original-state journal against each actual mutation. Have Jack
   confirm current UI values and physical behavior. Where available, cite final
   configuration readbacks and compare their relevant raw original fields.
2. Record any gap between UI/physical restoration and exact raw-byte restoration.
   Leave unresolved failures visible; stop further testing if restore failed.
3. Ensure every pass has capture, metadata, timestamped notes, logs or missing-log
   explanation, correlation and summary. Retain accidental/mis-action captures
   labeled as such rather than treating them as clean proof.
4. Review privacy before sharing; raw originals remain private. Do not publish
   mouse serials, account data, unrelated keyboard input or personal profile names.
5. Generate SHA-256 checksums for all files in the finished bundle (exclude the
   manifest itself). Use relative paths so the checks survive USB-drive copying.
   After copying, recompute and compare every file, not just the ZIP's size.

Example integrity commands in PowerShell, after all capture/log/summary files
have stopped changing (replace paths with the real session roots):

```powershell
$ErrorActionPreference = 'Stop'
$bundle = (Resolve-Path 'C:\captures\completed-session').Path.TrimEnd('\')
$manifest = Join-Path $bundle 'SHA256.csv'
if (Test-Path -LiteralPath $manifest) { throw 'Manifest exists; review before replacing it.' }
$entries = @(Get-ChildItem -LiteralPath $bundle -Recurse -File -Force | ForEach-Object {
    [pscustomobject]@{
        Path = $_.FullName.Substring($bundle.Length + 1)
        SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
})
if ($entries.Count -eq 0) { throw 'Evidence bundle is empty.' }
$entries | Export-Csv -LiteralPath $manifest -NoTypeInformation -Encoding UTF8

# Copy the completed-session directory to the drive, then verify the copy.
$copy = (Resolve-Path 'E:\completed-session').Path
foreach ($entry in $entries) {
    $actual = (Get-FileHash -LiteralPath (Join-Path $copy $entry.Path) -Algorithm SHA256).Hash
    if ($actual -ne $entry.SHA256) { throw "Copy mismatch: $($entry.Path)" }
}
if ((Get-FileHash -LiteralPath $manifest).Hash -ne
    (Get-FileHash -LiteralPath (Join-Path $copy 'SHA256.csv')).Hash) {
    throw 'Copied manifest differs.'
}
'All copied evidence files and the manifest verified.'
```

**Pass:** originals restored to the stated verification level, all capture claims
traceable, bundle hashes agree on the USB-drive copy, and the next agent knows
exactly which mappings remain unknown.

## Suggested case report / recovery journal fields

```text
Case ID / status / reason:
UTC start/end, local time zone:
Device model / VID:PID / transport / distinguishing identity:
USBPcap interface / bus / address / configuration interface(s):
Windows / Synapse / firmware / Wireshark / USBPcap versions:
Synapse profile / selected normal-or-shifted layer:
Original UI action/rate + screenshots/export location:
Intended edit + approved restoration steps:
Timestamped actual actions and mistakes:
Packet frames: assignment read / changed write / readback / Default / original restore:
Raw before/change/restore bytes, target/layer/slot interpretations and confidence:
Synapse event timestamps/source files:
Physical changed behavior observed by Jack:
Final original-state restore proof (UI / physical / raw readback separately):
Unresolved setting or mapping / smallest follow-up:
Privacy review / evidence bundle location:
OpenSnek runtime validation: NOT RUN — Windows capture-only session.
```
