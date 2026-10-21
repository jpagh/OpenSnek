# Windows 11 agent handoff: Basilisk V4 HyperSpeed USB + Synapse capture

> This handoff records the pre-capture research scope, not the current support
> matrix. The completed session and corrected findings are documented in
> [the sanitized evidence report](../../../captures/usb/2026-10-20-basilisk-v4-windows/README.md).
> **Known checker limitation:** USBPcap control-IN completion bytes may be absent
> from the decoded payload fields this checker reads. The V4 session demonstrated
> valid responses in raw URB data that it missed. Zero reported successes do not
> establish absent device readback; inspect raw control transfers before making
> support claims. The bundled offline tests use synthetic PDML, not a full raw-URB decoder.

Copy this **entire folder** to the Windows machine and give this README to its
AI agent. It contains the handoff, `TEST_PLAN.md`, a read-only capture checker,
and offline unit tests. A repository checkout is optional. Keep captures on the
Windows local disk until capture has stopped, then copy the finished evidence
bundle back to the USB drive.

## Start here — no OpenSnek installation needed

OpenSnek is a **macOS** mouse-configuration app. The Windows agent is collecting
vendor-protocol evidence for a later macOS implementation. It should **not** try
to build/run OpenSnek, Swift, Xcode, `OpenSnekProbe`, or the repository's macOS
hardware tests on Windows. This folder supplies the relevant background and
Windows-compatible checks; missing access to the rest of the repo is not a blocker.

1. Read this README and `TEST_PLAN.md` before making changes to mouse settings.
2. Check for Python 3.10+ (`py -3 --version`, or `python --version`). If absent,
   request installation from <https://www.python.org/downloads/windows/>. All
   Python code here uses the standard library; no pip packages are needed.
3. In PowerShell, change to the copied kit folder and run the offline self-tests:

   ```powershell
   py -3 -m unittest discover -s . -p 'test_*.py' -v
   ```

   Use `python` instead of `py -3` if that is how Python is installed. These tests
   work without the mouse, Synapse, Wireshark, network access, or administrator
   permissions. They check synthetic report parsing and evidence-safety behavior,
   **not** the mouse's actual capabilities. Stop and report any self-test failure.
4. Install/verify Wireshark + USBPcap as below, then run hardware evidence cases
   in `TEST_PLAN.md`. Ask Jack for each required physical/UI action.
5. Return a private capture bundle, not an app build or a claim that support ships.

## Assignment

Help Jack capture what **Razer Synapse actually sends** to a **Basilisk V4
HyperSpeed** on Windows 11. Prepare tools, coordinate one action at a time with
Jack, save USB traffic and matching Synapse logs, analyze the exchanges, and
return evidence suitable for implementing missing OpenSnek support later.

**This is capture/research, not an implementation or raw-write probing task.**
The first priority is the two unmapped physical controls: **AI Prompt Master**
and **Hypershift**. The second is **receiver polling-rate configuration**.
Treat wired USB as a separate follow-up, not interchangeable evidence.

Ask Jack to perform physical actions, Synapse UI edits, installer/UAC approvals,
and any reboot. Do the discovery, capture orchestration, log collection, packet
analysis, and documentation yourself where the available tools allow it. Ask for
an explicit ready signal before each timed pass.

### Known facts and limits

| Transport | Expected identity | Current evidence / question |
|---|---|---|
| Supplied 2.4 GHz receiver | Razer VID `1532`, PID `00EA` | Nine standard/tilt buttons work; AI/Hypershift configuration identities are unknown. Poll reads `00:85`, `00:8B`, and `00:C0` returned unsupported. |
| USB data cable | Razer VID `1532`, PID `00EB` | Independently validated DPI, power, nine standard/tilt buttons, lighting, and 125/250/500/1000 Hz polling. Polling uses extended `00:C0/40`, not legacy `00:85/05`. |
| Bluetooth | PID `00EC`, advertised `BSK V4 HS` | Separate protocol/transport; not the primary assignment here. |

Existing extra-slot reads sometimes returned success with invalid function
lengths/classes or mismatched slot echoes. A passive report `05 31 6e ...` did
**not** establish a configuration-slot ID. Capture the official Synapse path;
leave control IDs unknown until the evidence establishes them. Do not copy V3
button/profile assumptions or attempt guessed slot writes.

If a checkout is available, read these before interpreting results:

- `AGENTS.md`
- `captures/usb/2026-10-18-basilisk-v4-hyperspeed/README.md`
- `docs/protocol/USB_PROTOCOL.md`
- `docs/development/VALIDATION.md`

Those are optional deeper references, not Windows prerequisites. All device
commands mentioned below are **recognition hints for captured bytes**, not
instructions to transmit commands or replay captured writes.

Online source: <https://github.com/jpagh/OpenSnek>. The handoff was prepared
against commit `786dc68`; record the actual checkout commit if different.

## 1. Establish scope and a recovery baseline

1. Confirm the model, firmware shown by Synapse, Synapse version, Windows build,
   and which physical controls Jack means by AI Prompt Master and Hypershift.
   Record their Synapse labels/screenshots rather than inferring from location.
2. Start with the supplied receiver only: mouse in 2.4 GHz mode, USB cable
   disconnected. Disconnect other Razer mice/receivers where practical. Verify
   `VID_1532&PID_00EA` in Device Manager or USBPcap's device tree and record the
   USB root hub, bus/device address, and exposed interfaces. A PID alone does not
   distinguish two identical receivers. Recheck the address after reconnects.
3. Keep Synapse running for official configuration captures. Stop other mouse
   configuration/probe clients so Synapse is the only configuration writer.
4. Before editing, create a private `original-state.md` recovery journal:
   - exact device/transport identity and current profile name/GUID if available;
   - original assignments for both controls, including normal/Hypershift layers;
   - original poll rate and relevant Hypershift/AI settings;
   - screenshots and a Synapse profile export if supported;
   - the precise UI steps required to restore each changed setting.
   Distinguish an existing custom assignment from Synapse's factory **Default**.
5. Explain that USB capture can record other devices on the same root hub,
   including keyboard input. Close private apps; avoid passwords, personal text,
   AI prompt submission, and unrelated keyboard/mouse activity while capturing.
   Keep originals private and obtain approval before publishing any artifacts.

**Gate:** proceed to mutations only when the selected device is unambiguous,
original settings are recorded, and Jack agrees to the proposed reversible edit.
If the original assignment cannot be recovered safely, capture reads/presses only
and report the missing baseline as a blocker.

## 2. Install and verify USB capture tools

Use **Wireshark + USBPcap**. BTVS captures Bluetooth and is not the USB path.

- Wireshark: <https://www.wireshark.org/download.html>
- USBPcap project: <https://github.com/desowin/usbpcap>

Check what is installed first. Install Wireshark with TShark and the USBPcap
component if offered; otherwise use the official USBPcap release installer.
USBPcap is a driver: request administrator approval and reboot if required.
Npcap alone does not capture USB. Keep a second input device available in case
a driver installation/reboot temporarily interrupts the mouse.

In PowerShell:

```powershell
$tshark = 'C:\Program Files\Wireshark\tshark.exe'
& $tshark --version
& $tshark -D
```

If the path differs, locate the installed executable. Run capture from an
administrator-approved elevated session if permissions require it. Identify the
USBPcap interface/root hub containing `1532:00EA`, using USBPcap/Wireshark's
device tree. Do not select an Ethernet, loopback, or BTVS interface instead.
If USBPcap does not appear, resolve installation/reboot/permissions first.

### Prove the capture path before editing

1. Capture a short receiver baseline with Synapse open and no edits. If descriptor
   discovery is needed, start capture before reconnecting the receiver, label it
   as a discovery pass, and re-identify its assigned bus/device address afterward.
2. Open the saved capture and find traffic for the receiver. Check that full
   control-transfer payloads are present, not just ordinary mouse movement.
3. Capture opening the device/assignment page in Synapse without changing an
   assignment. Look for configuration SET_REPORT/GET_REPORT traffic. Synapse may
   cache reads; absence of a read must be reported, not filled in by assumption.
   A separate controlled Synapse startup capture can help if needed.

**Gate:** a nonempty file is insufficient. Verify receiver traffic and at least
one recognizable configuration exchange before asking Jack to change mappings.
Use the bundled checker as an initial sanity check, then inspect URBs/setup in
Wireshark; the checker does not pair transactions or prove a setting changed.

### Run the bundled offline capture checker

From the kit folder, substitute the **verified decimal bus and device address**
and real file paths (the numbers below are examples, not device identities):

```powershell
py -3 .\check_capture.py --pcap 'C:\captures\pass-1\capture.pcapng' `
  --tshark 'C:\Program Files\Wireshark\tshark.exe' `
  --bus 1 --device 7 --out 'C:\captures\pass-1\analysis'
$LASTEXITCODE
```

The output directory must be new. The checker reads an existing file, never
captures live traffic, opens a HID device, sends commands, or edits the pcap.
It writes `reports.csv` (absolute timestamps, frame IDs, raw report bytes,
framing errors) and `visibility.md` (counts and limits).

Exit codes:

- `0`: at least one structurally valid request and one vendor-success report
  were visible in scope. **They are not necessarily a matched pair.**
- `2`: inconclusive — no such request/response visibility. An idle pass can
  legitimately return this. Inspect the scope, fields, caching and full pcap.
- `1`: execution/input error, including an existing output directory. Fix the
  error before using the result.

If TShark is available only on another machine, export a PDML file there using
TShark's `-r capture.pcapng -T pdml` options with stdout redirected to a file;
use `--pdml capture.pdml` instead of `--pcap`. Avoid Windows PowerShell's default
UTF-16 text redirection: an XML declaration claiming UTF-8 with UTF-16 content
will not parse. The checker's `--pcap` path avoids this encoding problem entirely.
Keep the original pcap. Only whole 90-byte payloads and 91-byte candidates with a
single leading byte are checked; short input reports and fragmented/nonstandard
configuration traffic are deliberately left to Wireshark analysis. Checksum or
header rejection means **unrecognized by this checker**, not invalid hardware.
The Python tests have been run on macOS with synthetic PDML; live Windows
USBPcap/TShark compatibility still needs the capture-path check above.

## 3. Run small, named capture passes

Use one folder per pass, for example:

```text
captures/usb/windows/YYYY-MM-DD-HHMMSS-v4hs-receiver-ai-remap-pass-1/
```

Without a checkout, use the same layout under a local working directory.
Keep 15 seconds for idle and approximately 30–60 seconds for action passes.
The following is a capture template, not a script already provided by OpenSnek:

```powershell
$root = Join-Path $env:USERPROFILE 'Desktop\OpenSnek-captures\usb\windows'
$out = Join-Path $root ((Get-Date -Format 'yyyy-MM-dd-HHmmss') + '-v4hs-receiver-ai-remap-pass-1')
New-Item -ItemType Directory -Path $out -Force | Out-Null
# Replace this with the exact USBPcap interface name/number from tshark -D.
$captureInterface = '<USBPcap interface>'
(Get-Date).ToString('o') | Set-Content (Join-Path $out 'capture-start.txt')
& $tshark -i $captureInterface -s 0 -a duration:45 -w (Join-Path $out 'capture.pcapng')
$captureExitCode = $LASTEXITCODE
(Get-Date).ToString('o') | Set-Content (Join-Path $out 'capture-end.txt')
if ($captureExitCode -ne 0) { throw "Capture failed: $captureExitCode" }
```

Set a fresh folder/name and appropriate duration for every pass. Record the local
time zone/UTC offset. The start/end files bracket process execution; actual
packet timestamps and action markers determine the relevant window.

Coordinate a capture console and a separate agent/UI channel. Tell Jack to act
only after TShark reports it is capturing (or Wireshark visibly receives packets).
After each action, allow a few seconds of quiet traffic before stopping. Use a
separate timestamped note for each physical press, click, Apply/Save, and restore;
record intended action **and** observed result, including mistakes.

### Required receiver passes, in priority order

| Pass | Action | Evidence sought |
|---|---|---|
| `receiver-idle-baseline` | No edits or deliberate button presses, Synapse open | Same-session background traffic. |
| `receiver-ai-assignment-read` | Open/select the AI control's assignment UI, no edit | Official label, selected layer, any assignment reads. |
| `receiver-ai-remap` | If Synapse permits it, change only this control to a harmless observable action, e.g. right click, and Apply | Exact official write sequence and any readback. |
| `receiver-ai-press-remapped` | Press only that physical control a few times with spacing | HID traffic and physical proof of the changed behavior. |
| `receiver-ai-default` | Select Synapse Default and Apply, if reversible | Native/default sequence, distinct from original custom settings. |
| `receiver-ai-original-restore` | Restore the journaled original assignment and verify it | Final original state and behavior; combine with Default only if they truly match. |
| `receiver-hypershift-*` | Repeat assignment-read/remap/press/default/original-restore for the physical Hypershift control | Its own control identity and configuration path, separate from AI. |
| `receiver-poll-read` | Open Performance/polling UI, no edit | Available choices, current value, query traffic. |
| `receiver-poll-change` | If the UI offers a reversible choice, select one different rate and Apply | Actual receiver-specific write/readback; never inject wired `00:40` as a guess. |
| `receiver-poll-original-restore` | Restore the original rate and verify in Synapse | Restoration sequence and authoritative evidence available. |

Finish and verify restoration of one control before starting the next. If Synapse
requires multiple UI actions, record their order/times and retain a narrow repeat
pass if the first attempt is noisy.

**Hypershift distinction:** assigning the physical button to act as the
Hypershift modifier is different from editing another button's shifted layer.
Record which one is being captured. If Synapse locks the modifier or offers no
remap, screenshot and report that limit. If useful and approved, run a separate
pass holding the modifier while pressing one known standard button, without
changing that standard button's mapping. Keep this separate from remap evidence.

**Software-only possibility:** if AI opens a host application or a Hypershift
operation produces logs but no USB configuration write, report that observation.
Do not force an assumed hardware slot. If receiver polling is absent/disabled in
Synapse, record that fact and stop that branch rather than probing raw commands.

### Optional wired comparison, after receiver restoration

Unplug the receiver; connect a USB **data** cable; verify `1532:00EB` and record
the new hub/address. Make a separate original-state journal for wired mode.
Repeat AI/Hypershift passes only if needed and reversible. A wired polling
baseline/change/restore capture can serve as a known-protocol control:
`00:C0` reads and `00:40` writes use target/rate arguments; known wired rate
bytes are `40=125`, `20=250`, `10=500`, `08=1000` Hz. Observe Synapse rather than
sending these commands yourself. Do not infer receiver support from wired results.

## 4. Preserve matching Synapse logs and action times

Record which Synapse processes/version were running and whether the UI, background
engine, and services were active. An initial candidate log directory is:

```powershell
$logRoot = Join-Path $env:LOCALAPPDATA 'Razer\RazerAppEngine\User Data\Logs'
Get-ChildItem -LiteralPath $logRoot -File | Sort-Object LastWriteTime -Descending |
    Select-Object -First 20 Name, Length, LastWriteTime
```

That directory is used by the existing OpenSnek Bluetooth wrapper; other Synapse
versions may differ. If absent, discover the installed version's logs and record
the actual paths. Preserve relevant log files immediately after each pass, since
logs may rotate. Copy files rather than moving or clearing them. Report locked
or unavailable logs explicitly.

Keep raw copies privately. Extract timestamped events around the capture window,
including button/assignment changes, mapping errors, device identity, profile
GUIDs/slots, Apply, and polling changes. Search actual current logs; existing
`products_170_*` filenames belong to earlier research and may not match V4 logs.
A lack of matching text is not proof that no action occurred.

Produce `synapse-events.md` and `correlation.md` manually or with a small analysis
helper if needed. There is currently **no USB equivalent** of the repository's
`tools/windows/capture-btvs.ps1`; do not run that Bluetooth parser on USB traffic.

## 5. Decode and correlate without overstating evidence

1. Preserve the original pcap. Make receiver-filtered analysis views/copies using
   the verified USB bus/device address. A USB root-hub capture may contain other
   devices. Do not discard interrupt/input reports: they may be essential for
   AI/Hypershift behavior. Reconnects can change addresses.
2. Inspect the control-transfer setup and payload bytes for HID Feature
   SET_REPORT/GET_REPORT. Pair requests/completions by URB identity and timing;
   USB transfer completion is not the same as a vendor success response.
   Wireshark field names vary; inspect `tshark -G fields` before writing an
   exporter. Preserve raw nonstandard reports instead of forcing a parser.
3. Standard Razer USB configuration bodies are 90 bytes. Capture framing may
   include setup bytes or a HID report ID; establish the body boundary first:
   - byte 0: request/status (`02` success, `03` failure, `04` timeout, `05` unsupported);
   - byte 1: transaction ID; byte 5: declared argument size;
   - bytes 6/7: command class/ID; bytes 8–87: arguments;
   - byte 88: XOR of bytes 2–87; byte 89: reserved.
4. Existing standard button configuration uses `02:8C` reads / `02:0C` writes,
   with profile, slot, layer, and a seven-byte function block. Treat this only as
   a candidate family for extra controls: verify actual payload shape, declared
   lengths, echoes, and changed/default transitions from Synapse.
5. Compare against the idle baseline and correlate wire exchanges to exact action
   times and Synapse events. Include frame numbers, absolute times, direction,
   interface/report identity, raw request/response bytes, and interpretation.
   Preserve distinct live/persistent targets and layer values rather than
   collapsing repeated writes as duplicates.
6. Separate these claims in `summary.md`: observed bytes, candidate interpretation,
   authoritative configuration readback, physical behavior, and unresolved gaps.
   An ACK alone proves neither a working mapping nor physical polling cadence.
   Host software behavior is not automatically a persistently stored device action.

**Gate:** for each proposed mapping, cite the assignment change and Default/original
restore frames, corresponding Synapse/UI evidence, and physical result. If one
is missing, label the mapping incomplete/research-only rather than implemented.

## 6. Restore, package, and hand back

After every mutation, restore the **original journaled state**, not merely Default.
Verify via Synapse's displayed assignment/rate, configuration readback where
available, and Jack's physical check. Keep factory-default captures separate from
custom-original restoration. If exact raw restoration cannot be verified with the
available Windows tools, say so explicitly; a UI-only check is not an exact-byte
restore claim.

If restore fails, stop further mutations, preserve the journal/captures, and report
the exact unresolved setting to Jack. Never factory-reset or overwrite another
profile to make the run look successful. Do not retry blind configuration writes.

For every pass retain:

```text
capture.pcapng
metadata.json            # device, transport, tools/OS/Synapse versions, time zone,
                         # capture interval, hub/address/interfaces, action, profile/layer
original-state.md        # private recovery journal or link to session journal
notes.md                 # timestamped actions, UI screenshots, physical results, mistakes
synapse-logs/            # relevant raw copies, private
synapse-events.md        # extracted events, source file/time references, or explicit missing-log note
correlation.md           # UI/log event -> USB frames/exchanges
summary.md               # findings, raw payloads/frame references, limits, restore status
```

Optionally add a decoded CSV/JSON, but keep the pcap as primary evidence. At the
session root, write a short README listing passes and per-feature outcomes:
`captured`, `blocked`, or `not attempted`; changed-state proof; restoration proof;
and the smallest remaining follow-up. Include a SHA-256 manifest for the finished
files, then copy the bundle to the USB drive and verify copied hashes.

Review the bundle for personal profile names, serials, account identifiers,
keyboard data, and log content before sharing. Keep private originals intact;
prepare separately labeled sanitized derivatives for any future public upload.
Do not publish to GitHub or change repository settings without Jack's approval.
No app/probe code changes or support claims are part of this capture handoff.

### Return summary for the next agent

For each case in `TEST_PLAN.md`, provide: device/transport; pass folder; exact
before/change/after state; relevant packet frames and Synapse log times; physical
result; restoration method and strength of verification; and unresolved questions.
Use `pass`, `fail`, `blocked`, or `not attempted` for the evidence case, and state
explicitly that no OpenSnek runtime validation was performed on Windows.

### Completion checklist

- [ ] Receiver identity and verified configuration-capture path documented.
- [ ] Same-session idle baseline retained.
- [ ] AI and Hypershift each have focused read/change/physical/default/restore evidence,
      or a precise limitation explaining which steps Synapse does not permit.
- [ ] Receiver polling captured or its missing/disabled UI recorded.
- [ ] Wired evidence, if any, independently identified and never substituted for receiver evidence.
- [ ] Matching Synapse logs and action timestamps retained, or collection gaps stated.
- [ ] All mutations restored and verification scope stated; unresolved restore is a failed run.
- [ ] Private evidence bundle, summary, and verified USB-drive copy ready for the macOS agent.
