import XCTest
import OpenSnekCore
import OpenSnekHardware
@testable import OpenSnek

/// Covers independently scoped USB surfaces and opt-in journaled hardware checks.
@MainActor final class BasiliskV4OnboardingTests: XCTestCase {
    private struct ButtonSnapshot: Codable, Equatable, Sendable {
        let slot: Int
        let persistent: [UInt8]
        let live: [UInt8]
    }

    /// Journals every target changed by the USB hardware check.
    private struct Snapshot: Codable, Equatable, Sendable {
        let sleep: Int
        let threshold: Int
        let brightness: Int?
        let buttons: [ButtonSnapshot]
    }

    func testReceiverProfileDoesNotInheritUnprovenV3Controls() throws {
        let profile = try XCTUnwrap(DeviceProfiles.resolve(vendorID: 0x1532, productID: 0x00EA, transport: .usb))
        XCTAssertEqual(profile.id, .basiliskV4Hyperspeed)
        XCTAssertEqual(DeviceProfiles.maximumDPI(for: profile.id), 33_000)
        XCTAssertEqual(DeviceProfiles.clampDPI(35_000, profileID: profile.id), 33_000)
        XCTAssertEqual(ButtonBindingSupport.defaultUSBFunctionBlock(for: 52, profileID: profile.id), [0x0E, 1, 0x68, 0, 0x14, 0, 0])
        XCTAssertEqual(ButtonBindingSupport.defaultUSBFunctionBlock(for: 53, profileID: profile.id), [0x0E, 1, 0x69, 0, 0x14, 0, 0])
        XCTAssertTrue(profile.supportsDPIControls)
        XCTAssertFalse(profile.supportsPollRateControls)
        XCTAssertFalse(profile.supportsScrollModeControls)
        XCTAssertTrue(profile.supportsLightingBrightnessControls)
        XCTAssertEqual(profile.supportedLightingEffects, LightingEffectKind.allCases.filter { $0 != .reactive })
        XCTAssertEqual(profile.usbLightingEffectReadLEDID, 0x0A)
        XCTAssertFalse(profile.supportsMappedOnboardProfileCRUD)
        XCTAssertNil(DeviceProfiles.resolve(vendorID: 0x1532, productID: 0x00EA, transport: .bluetooth))
        XCTAssertEqual(profile.buttonLayout.writableSlots, [1, 2, 3, 4, 5, 9, 10, 52, 53])
    }

    // Legacy test name is retained for journal recovery; exact device scope selects receiver or wired.
    func testHardwareReceiverButtonsAndPowerRestoreExactly() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OPEN_SNEK_HW"] == "1" else { throw XCTSkip("Opt-in scoped hardware check") }
        let scope = try HardwareValidationScope(environment: environment)
        let client = BridgeClient()
        let device = try scope.select(from: await client.listDevices(), transport: .usb)
        guard device.profile_id == .basiliskV4Hyperspeed || device.profile_id == .basiliskV4HyperspeedWired else { throw HardwareValidationSession.failure("Select an explicitly scoped Basilisk V4 USB identity") }
        if scope.isRecovery {
            try await HardwareValidationSession.recover(deviceID: device.id, journalURL: scope.journalURL, read: { try await self.snapshot(client, device) }, restore: { try await self.restore($0, client, device) })
            return
        }
        try await HardwareValidationSession.run(
            deviceID: device.id, journalURL: scope.journalURL, read: { try await self.snapshot(client, device) }, restore: { try await self.restore($0, client, device) },
            operation: {
                let baseline = try await self.snapshot(client, device)
                for button in baseline.buttons {
                    _ = try await client.apply(device: device, patch: DevicePatch(buttonBinding: ButtonBindingPatch(slot: button.slot, kind: .rightClick, hidKey: nil)))
                    let changed = try await self.readButton(button.slot, client, device)
                    let expected: [UInt8] = [1, 1, 2, 0, 0, 0, 0]
                    guard changed.persistent == expected, changed.live == expected else { throw HardwareValidationSession.failure("Changed button readback mismatch at \(button.slot)") }
                    _ = try await client.apply(device: device, patch: DevicePatch(buttonBinding: ButtonBindingPatch(slot: button.slot, kind: .default, hidKey: nil)))
                    let restoredDefault = try await self.readButton(button.slot, client, device)
                    let factory = ButtonBindingSupport.defaultUSBFunctionBlock(for: button.slot, profileID: device.profile_id)
                    guard restoredDefault.persistent == factory, restoredDefault.live == factory else { throw HardwareValidationSession.failure("Default readback mismatch at \(button.slot)") }
                }
                let sleep = baseline.sleep == 300 ? 360 : 300
                let threshold = baseline.threshold == 51 ? 38 : 51
                let brightness = baseline.brightness == 128 ? 96 : 128
                _ = try await client.apply(device: device, patch: DevicePatch(sleepTimeout: sleep, lowBatteryThresholdRaw: threshold, ledBrightness: brightness))
                let changed = try await self.snapshot(client, device)
                guard changed.sleep == sleep, changed.threshold == threshold, changed.brightness == brightness else { throw HardwareValidationSession.failure("Changed power readback mismatch") }
            })
    }

    private func requireStopped() throws { guard BLEProbeSession.runningAppProcessIDs().isEmpty else { throw HardwareValidationSession.failure("Stop OpenSnek app and service first") } }

    private func readButton(_ slot: Int, _ client: BridgeClient, _ device: MouseDevice) async throws -> ButtonSnapshot {
        try requireStopped()
        guard let persistent = try await client.debugUSBReadButtonBinding(device: device, slot: slot, profile: 1), let live = try await client.debugUSBReadButtonBinding(device: device, slot: slot, profile: 0), persistent.count == 7, live.count == 7 else {
            throw HardwareValidationSession.failure("Incomplete button baseline")
        }
        return ButtonSnapshot(slot: slot, persistent: persistent, live: live)
    }

    private func snapshot(_ client: BridgeClient, _ device: MouseDevice) async throws -> Snapshot {
        try requireStopped()
        let state = try await client.readState(device: device)
        guard let sleep = state.sleep_timeout, let threshold = state.low_battery_threshold_raw else { throw HardwareValidationSession.failure("Incomplete power baseline") }
        var buttons: [ButtonSnapshot] = []
        for slot in [1, 2, 3, 4, 5, 9, 10, 52, 53] { buttons.append(try await readButton(slot, client, device)) }
        guard let brightness = state.led_value else { throw HardwareValidationSession.failure("Incomplete brightness baseline") }
        return Snapshot(sleep: sleep, threshold: threshold, brightness: brightness, buttons: buttons)
    }

    // Original raw settings can exceed the editor's write clamps; recovery must not clamp them.
    private func restorePower(_ snapshot: Snapshot, _ client: BridgeClient, _ device: MouseDevice) async throws {
        guard (0...65535).contains(snapshot.sleep), (0...255).contains(snapshot.threshold), let session = await client.sessionsFor(device: device).first else { throw HardwareValidationSession.failure("Invalid power recovery payload") }
        let sleep = try await client.perform(session, device, classID: 7, cmdID: 3, size: 2, args: [UInt8(snapshot.sleep >> 8), UInt8(snapshot.sleep & 255)])
        let threshold = try await client.perform(session, device, classID: 7, cmdID: 1, size: 1, args: [UInt8(snapshot.threshold)])
        if let brightness = snapshot.brightness { guard (0...255).contains(brightness), try await client.perform(session, device, classID: 0x0F, cmdID: 4, size: 3, args: [1, 0x0A, UInt8(brightness)])?.first == 2 else { throw HardwareValidationSession.failure("Brightness restore rejected") } }
        guard sleep?.first == 2, threshold?.first == 2 else { throw HardwareValidationSession.failure("Raw power restore rejected") }
    }

    private func restore(_ snapshot: Snapshot, _ client: BridgeClient, _ device: MouseDevice) async throws {
        try requireStopped()
        // Resolve the responding control interface on a fresh recovery process before writing.
        _ = try await client.readState(device: device)
        guard [[1, 2, 3, 4, 5, 9, 10], [1, 2, 3, 4, 5, 9, 10, 52, 53]].contains(snapshot.buttons.map(\.slot)), snapshot.buttons.allSatisfy({ $0.persistent.count == 7 && $0.live.count == 7 }) else { throw HardwareValidationSession.failure("Invalid recovery snapshot") }
        var failures: [String] = []
        for target in [1, 0] {
            for button in snapshot.buttons {
                do { guard try await client.debugUSBSetButtonBindingRaw(device: device, slot: button.slot, profile: target, functionBlock: target == 1 ? button.persistent : button.live) else { throw HardwareValidationSession.failure("Button restore rejected") } } catch {
                    failures.append(error.localizedDescription)
                }
            }
        }
        do { try await restorePower(snapshot, client, device) } catch { failures.append(error.localizedDescription) }
        guard failures.isEmpty else { throw HardwareValidationSession.failure("Retain recovery journal: \(failures.joined(separator: "; "))") }
    }
}
