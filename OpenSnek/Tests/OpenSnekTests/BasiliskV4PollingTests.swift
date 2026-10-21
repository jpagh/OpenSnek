import XCTest
import OpenSnekCore
import OpenSnekHardware
import OpenSnekProtocols
@testable import OpenSnek

/// Verifies wired-specific polling without enabling unsupported receiver commands.
@MainActor final class BasiliskV4PollingTests: XCTestCase {
    func testWiredProfileRetainsIndependentPollingAndValidatedControls() throws {
        let wired = try XCTUnwrap(DeviceProfiles.resolve(vendorID: 0x1532, productID: 0x00EB, transport: .usb))
        let receiver = try XCTUnwrap(DeviceProfiles.resolve(vendorID: 0x1532, productID: 0x00EA, transport: .usb))
        XCTAssertEqual(wired.id, .basiliskV4HyperspeedWired)
        XCTAssertEqual(wired.usbPollRateProtocol, .extended)
        XCTAssertEqual(wired.supportedPollRates, [125, 250, 500, 1000])
        XCTAssertTrue(wired.supportsPollRateControls)
        XCTAssertTrue(receiver.supportsPollRateControls)
        XCTAssertEqual(receiver.usbPollRateProtocol, .profileScoped)
        XCTAssertEqual(receiver.supportedPollRates, [500, 1000])
        XCTAssertTrue(wired.supportsDPIControls)
        XCTAssertTrue(wired.supportsButtonRemapControls)
        XCTAssertTrue(wired.supportsPowerManagementControls)
        XCTAssertTrue(wired.supportsLightingBrightnessControls)
        XCTAssertEqual(wired.supportedLightingEffects, receiver.supportedLightingEffects)
        XCTAssertFalse(wired.supportedLightingEffects.contains(.reactive))
        XCTAssertFalse(wired.supportsScrollModeControls)
        XCTAssertFalse(wired.supportsMappedOnboardProfileCRUD)
        XCTAssertEqual(wired.buttonLayout.writableSlots, [1, 2, 3, 4, 5, 9, 10, 52, 53])
        XCTAssertEqual(ButtonBindingSupport.defaultUSBFunctionBlock(for: 52, profileID: wired.id), [14, 1, 104, 0, 20, 0, 0])
        XCTAssertEqual(ButtonBindingSupport.defaultUSBFunctionBlock(for: 53, profileID: wired.id), [14, 1, 105, 0, 20, 0, 0])
    }

    func testExtendedRateByteIsNotLegacyDivisorAndValidatesCommandEcho() {
        var extended = USBHIDProtocol.createReport(txn: 31, classID: 0, cmdID: 0xC0, size: 1, args: [0, 8])
        extended[0] = 2
        XCTAssertEqual(USBHIDProtocol.pollRate(from: extended, encoding: .extended), 1000)
        XCTAssertNil(USBHIDProtocol.pollRate(from: extended, encoding: .standard))
        var legacy = USBHIDProtocol.createReport(txn: 31, classID: 0, cmdID: 0x85, size: 1, args: [8])
        legacy[0] = 2
        XCTAssertEqual(USBHIDProtocol.pollRate(from: legacy, encoding: .standard), 125)
        extended[0] = 5
        XCTAssertNil(USBHIDProtocol.pollRate(from: extended, encoding: .extended))
        extended[0] = 2
        extended[9] = 3
        XCTAssertNil(USBHIDProtocol.pollRate(from: extended, encoding: .extended))
        XCTAssertNil(USBHIDProtocol.pollRate(from: [], encoding: .extended))
    }

    func testExtendedWritesUseCorrectCommandTargetAndRateBytes() throws {
        let rates: [(Int, UInt8)] = [(125, 64), (250, 32), (500, 16), (1000, 8)]
        for (hz, raw) in rates {
            let command = try XCTUnwrap(USBHIDProtocol.pollRateWriteCommand(hz: hz, encoding: .extended))
            XCTAssertEqual(command.commandID, 0x40)
            XCTAssertEqual(command.size, 2)
            XCTAssertEqual(command.args, [0, raw])
        }
        XCTAssertNil(USBHIDProtocol.pollRateWriteCommand(hz: 333, encoding: .extended))
        XCTAssertNil(USBHIDProtocol.pollRateWriteCommand(hz: 250, encoding: .standard))
        XCTAssertEqual(USBHIDProtocol.pollRateWriteCommand(hz: 1000, encoding: .standard)?.args, [1])
    }

    func testReceiverPollingUsesCapturedBankOneCommandsOnly() throws {
        let read = USBHIDProtocol.pollRateReadCommand(encoding: .profileScoped)
        XCTAssertEqual(read.commandID, 0x8E)
        XCTAssertEqual(read.size, 2)
        XCTAssertEqual(read.args, [1, 0])
        let rates: [(Int, UInt8)] = [(500, 2), (1000, 1)]
        for (hz, raw) in rates {
            let write = try XCTUnwrap(USBHIDProtocol.pollRateWriteCommand(hz: hz, encoding: .profileScoped))
            XCTAssertEqual(write.commandID, 0x0E)
            XCTAssertEqual(write.args, [1, raw])
            XCTAssertEqual(write.size, 2)
            XCTAssertEqual(USBHIDProtocol.pollRate(from: receiverPollResponse(raw: raw), encoding: .profileScoped), hz)
        }
        for hz in [125, 250, 2000, 4000, 8000] { XCTAssertNil(USBHIDProtocol.pollRateWriteCommand(hz: hz, encoding: .profileScoped)) }
        XCTAssertFalse(DeviceProfiles.basiliskV4Bluetooth.supportsPollRateControls)
    }

    func testReceiverPollingRejectsWrongCommandTargetAndUnknownCodes() {
        let valid = receiverPollResponse(raw: 2)
        let mutations: [(Int, UInt8)] = [(0, 5), (5, 1), (6, 2), (7, 0xC0), (8, 0), (8, 2), (9, 8), (9, 0)]
        for (index, value) in mutations {
            var invalid = valid
            invalid[index] = value
            XCTAssertNil(USBHIDProtocol.pollRate(from: invalid, encoding: .profileScoped))
        }
        XCTAssertNil(USBHIDProtocol.pollRate(from: Array(valid.prefix(9)), encoding: .profileScoped))
        XCTAssertNil(USBHIDProtocol.pollRate(from: valid, encoding: .extended))
        XCTAssertNil(USBHIDProtocol.pollRate(from: valid, encoding: .standard))
    }

    func testReceiverPollingWriteRequiresChangedReadbackWithoutRetries() throws {
        for matches in [true, false] {
            var commands: [UInt8] = []
            let result = try USBHIDProtocol.performVerifiedPollRateWrite(hz: 500, encoding: .profileScoped) { command in
                commands.append(command.commandID)
                if command.commandID == 0x0E {
                    XCTAssertEqual(command.args, [1, 2])
                    return [2]
                }
                XCTAssertEqual(command.args, [1, 0])
                return self.receiverPollResponse(raw: matches ? 2 : 1)
            }
            XCTAssertEqual(result, matches)
            XCTAssertEqual(commands, [0x0E, 0x8E])
        }
        let result = try USBHIDProtocol.performVerifiedPollRateWrite(hz: 125, encoding: .profileScoped) { _ in
            XCTFail("Uncaptured rate must not be written")
            return nil
        }
        XCTAssertFalse(result)
    }

    private func receiverPollResponse(raw: UInt8) -> [UInt8] {
        var response = USBHIDProtocol.createReport(txn: 20, classID: 0, cmdID: 0x8E, size: 2, args: [1, raw])
        response[0] = 2
        return response
    }

    func testHardwareWiredPollApplyReadbackAndExactRestore() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OPEN_SNEK_HW"] == "1" else { throw XCTSkip("Opt-in scoped hardware check") }
        let scope = try HardwareValidationScope(environment: environment)
        let client = BridgeClient()
        let device = try scope.select(from: await client.listDevices(), transport: .usb)
        guard device.profile_id == .basiliskV4HyperspeedWired else { throw HardwareValidationSession.failure("Select the wired Basilisk V4, not its receiver") }
        if scope.isRecovery {
            try await HardwareValidationSession.recover(deviceID: device.id, journalURL: scope.journalURL, read: { try await self.snapshot(client, device) }, restore: { try await self.restore($0, client, device) })
            return
        }
        try await HardwareValidationSession.run(
            deviceID: device.id, journalURL: scope.journalURL, read: { try await self.snapshot(client, device) }, restore: { try await self.restore($0, client, device) },
            operation: {
                for hz in DeviceProfiles.basiliskV4WiredUSB.supportedPollRates {
                    _ = try await client.apply(device: device, patch: DevicePatch(pollRate: hz))
                    let state = try await client.readState(device: device)
                    guard state.poll_rate == hz else { throw HardwareValidationSession.failure("App polling readback mismatch") }
                }
            })
    }

    private func requireStopped() throws { guard BLEProbeSession.runningAppProcessIDs().isEmpty else { throw HardwareValidationSession.failure("Stop app/service first") } }

    private func snapshot(_ client: BridgeClient, _ device: MouseDevice) async throws -> [UInt8] {
        try requireStopped()
        _ = try await client.readState(device: device)
        guard let session = await client.sessionsFor(device: device).first else { throw HardwareValidationSession.failure("No control session") }
        var values: [UInt8] = []
        for target: UInt8 in [0, 1] {
            guard let raw = try await client.perform(session, device, classID: 0, cmdID: 0xC0, size: 2, args: [target, 0]), raw[0] == 2, raw[8] == target, [1, 2, 4, 8, 16, 32, 64].contains(raw[9]) else { throw HardwareValidationSession.failure("Incomplete polling baseline") }
            values.append(raw[9])
        }
        return values
    }

    private func restore(_ originals: [UInt8], _ client: BridgeClient, _ device: MouseDevice) async throws {
        try requireStopped()
        guard originals.count == 2, originals.allSatisfy({ [1, 2, 4, 8, 16, 32, 64].contains($0) }) else { throw HardwareValidationSession.failure("Invalid polling journal") }
        _ = try await client.readState(device: device)
        guard let session = await client.sessionsFor(device: device).first else { throw HardwareValidationSession.failure("No recovery control session") }
        var errors: [String] = []
        for target in [1, 0] {
            do { guard try await client.perform(session, device, classID: 0, cmdID: 0x40, size: 2, args: [UInt8(target), originals[target]])?.first == 2 else { throw HardwareValidationSession.failure("Polling restore rejected") } } catch { errors.append(error.localizedDescription) }
        }
        guard errors.isEmpty else { throw HardwareValidationSession.failure("Retain journal: \(errors.joined(separator: "; "))") }
    }
}
