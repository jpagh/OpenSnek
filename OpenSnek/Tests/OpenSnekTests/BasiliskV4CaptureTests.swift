import XCTest
import OpenSnekAppSupport
import OpenSnekCore
import OpenSnekProtocols
@testable import OpenSnek

/// Covers the Windows receiver evidence without opening hardware or importing private captures.
@MainActor final class BasiliskV4CaptureTests: XCTestCase {
    func testExtraControlsAreScopedToReceiver() {
        let receiver = DeviceProfiles.basiliskV4USB
        XCTAssertEqual(receiver.buttonLayout.writableSlots, [1, 2, 3, 4, 5, 9, 10, 14, 52, 53, 57, 128])
        for slot in [14, 57, 128] {
            XCTAssertTrue(receiver.buttonLayout.isEditable(slot))
            XCTAssertTrue(receiver.requiresVerifiedUSBButtonWrite(slot: slot))
            for profile in [DeviceProfiles.basiliskV4WiredUSB, DeviceProfiles.basiliskV4Bluetooth] {
                XCTAssertFalse(profile.buttonLayout.isEditable(slot))
                XCTAssertFalse(profile.requiresVerifiedUSBButtonWrite(slot: slot))
            }
        }
        XCTAssertFalse(receiver.requiresVerifiedUSBButtonWrite(slot: 4))
        XCTAssertTrue(receiver.supportsPollRateControls)
        XCTAssertEqual(receiver.supportedPollRates, [500, 1000])
        XCTAssertFalse(receiver.supportsMappedOnboardProfileCRUD)
    }

    func testCapturedNormalAssignmentsHydrateAndSerializeExactly() throws {
        // Standalone sweep frames 13262/13266; profile 2 mirrors these at 13360/13364.
        let examples: [Int: (block: [UInt8], key: Int)] = [57: ([2, 2, 0, 0xE2, 0, 0, 0], 0xE2), 128: ([2, 2, 0, 0x22, 0, 0, 0], 0x22)]
        for (slot, example) in examples {
            let (block, key) = example
            for target: UInt8 in [1, 2] {
                let raw = response(target: target, slot: UInt8(slot), block: block)
                let extracted = try XCTUnwrap(ButtonBindingSupport.extractUSBFunctionBlock(response: raw, profile: target, slot: UInt8(slot), hypershift: 0, profileID: .basiliskV4Hyperspeed))
                let draft = try XCTUnwrap(ButtonBindingSupport.buttonBindingDraftFromUSBFunctionBlock(slot: slot, functionBlock: extracted, profileID: .basiliskV4Hyperspeed))
                XCTAssertEqual(draft.kind, .keyboardSimple)
                XCTAssertEqual(draft.hidKey, key)
                XCTAssertEqual(ButtonBindingSupport.usbFunctionBlockForWrite(slot: slot, draft: draft, profileID: .basiliskV4Hyperspeed), block)
            }
        }
    }

    func testCapturedRemapToDefaultTransitionsPreserveNativeBlocks() throws {
        let defaults: [(Int, [UInt8])] = [(14, [7, 1, 4, 0, 0, 0, 0]), (57, [12, 1, 1, 0, 0, 0, 0]), (128, [0, 0, 0, 0, 0, 0, 0])]
        for (slot, original) in defaults {
            let changed = ButtonBindingDraft(kind: .rightClick, hidKey: 4, turboEnabled: false, turboRate: 142)
            XCTAssertEqual(ButtonBindingSupport.usbFunctionBlockForWrite(slot: slot, draft: changed, profileID: .basiliskV4Hyperspeed), [1, 1, 2, 0, 0, 0, 0])
            let restored = ButtonBindingSupport.defaultButtonBinding(for: slot, profileID: .basiliskV4Hyperspeed)
            XCTAssertEqual(ButtonBindingSupport.usbFunctionBlockForWrite(slot: slot, draft: restored, profileID: .basiliskV4Hyperspeed), original)
            XCTAssertEqual(ButtonBindingSupport.buttonBindingDraftFromUSBFunctionBlock(slot: slot, functionBlock: original, profileID: .basiliskV4Hyperspeed)?.kind, .default)
        }
        let dpiCycle = ButtonBindingDraft(kind: .dpiCycle, hidKey: 4, turboEnabled: false, turboRate: 142)
        let cycleBlock = ButtonBindingSupport.usbFunctionBlockForWrite(slot: 14, draft: dpiCycle, profileID: .basiliskV4Hyperspeed)
        XCTAssertEqual(cycleBlock, [6, 1, 6, 0, 0, 0, 0])
        XCTAssertEqual(ButtonBindingSupport.buttonBindingDraftFromUSBFunctionBlock(slot: 14, functionBlock: cycleBlock, profileID: .basiliskV4Hyperspeed)?.kind, .dpiCycle)
    }

    func testNewControlReadLayoutRejectsAmbiguity() {
        let raw = response(target: 1, slot: 57, block: [2, 2, 0, 0xE2, 0, 0, 0])
        XCTAssertNil(ButtonBindingSupport.extractUSBFunctionBlock(response: raw, profile: 1, slot: 57, hypershift: 1, profileID: .basiliskV4Hyperspeed))
        let mutations: [(Int, UInt8)] = [(0, 5), (5, 0), (6, 4), (7, 0x0C), (8, 2), (9, 128), (10, 2)]
        for (index, value) in mutations {
            var invalid = raw
            invalid[index] = value
            XCTAssertNil(ButtonBindingSupport.extractUSBFunctionBlock(response: invalid, profile: 1, slot: 57, hypershift: 0, profileID: .basiliskV4Hyperspeed))
        }
        XCTAssertNil(ButtonBindingSupport.extractUSBFunctionBlock(response: Array(raw.prefix(17)), profile: 1, slot: 57, hypershift: 0, profileID: .basiliskV4Hyperspeed))
    }

    func testWriteNeedsOneExactReadbackAndDoesNotRetry() throws {
        let block: [UInt8] = [2, 2, 0, 0x22, 0, 0, 0]
        let request = BridgeClient.USBRawButtonBindingWrite(profile: 1, slot: 128, hypershift: 0, functionBlock: block)
        for matches in [true, false] {
            var commands: [UInt8] = []
            let succeeded = try USBHIDProtocol.performVerifiedButtonWrite(request, profileID: .basiliskV4Hyperspeed) { command, args in
                commands.append(command)
                XCTAssertEqual(Array(args.prefix(3)), [1, 128, 0])
                if command == 0x0C {
                    XCTAssertEqual(Array(args.suffix(7)), block)
                    return [2]
                }
                XCTAssertEqual(Array(args.suffix(7)), Array(repeating: 0, count: 7))
                return self.response(target: 1, slot: 128, block: matches ? block : [0, 0, 0, 0, 0, 0, 0])
            }
            XCTAssertEqual(succeeded, matches)
            XCTAssertEqual(commands, [0x0C, 0x8C])
        }
        var commands: [UInt8] = []
        let rejected = try USBHIDProtocol.performVerifiedButtonWrite(request, profileID: .basiliskV4Hyperspeed) { command, _ in
            commands.append(command)
            return [5]
        }
        XCTAssertFalse(rejected)
        XCTAssertEqual(commands, [0x0C])
    }

    func testMissingOrRejectedReadbackFailsWithoutRetry() throws {
        let request = BridgeClient.USBRawButtonBindingWrite(profile: 0, slot: 128, hypershift: 0, functionBlock: [2, 2, 0, 0x22, 0, 0, 0])
        let readbacks: [[UInt8]?] = [nil, [5], response(target: 1, slot: 128, block: request.functionBlock)]
        for readback in readbacks {
            var count = 0
            let succeeded = try USBHIDProtocol.performVerifiedButtonWrite(request, profileID: .basiliskV4Hyperspeed) { command, _ in
                count += 1
                return command == 0x0C ? [2] : readback
            }
            XCTAssertFalse(succeeded)
            XCTAssertEqual(count, 2)
        }
        let shifted = BridgeClient.USBRawButtonBindingWrite(profile: 1, slot: 57, hypershift: 1, functionBlock: request.functionBlock)
        let succeeded = try USBHIDProtocol.performVerifiedButtonWrite(shifted, profileID: .basiliskV4Hyperspeed) { _, _ in
            XCTFail("Unmapped shifted-layer writes must be rejected before exchange")
            return nil
        }
        XCTAssertFalse(succeeded)
    }

    func testCapturedNormalHypershiftDefaultReadbackMatchesItsWriteForm() throws {
        let request = BridgeClient.USBRawButtonBindingWrite(profile: 1, slot: 57, hypershift: 0, functionBlock: [12, 1, 1, 0, 0, 0, 0])
        let verified = try USBHIDProtocol.performVerifiedButtonWrite(request, profileID: .basiliskV4Hyperspeed) { command, _ in command == 0x0C ? [2] : self.response(target: 1, slot: 57, block: [12, 1, 57, 0, 0, 0, 0]) }
        XCTAssertTrue(verified)
        XCTAssertFalse(ButtonBindingSupport.usbFunctionBlockMatchesReadback(slot: 128, expected: [12, 1, 1, 0, 0, 0, 0], readback: [12, 1, 57, 0, 0, 0, 0], profileID: .basiliskV4Hyperspeed))
        XCTAssertFalse(ButtonBindingSupport.usbFunctionBlockMatchesReadback(slot: 57, expected: [2, 2, 0, 0xE2, 0, 0, 0], readback: [12, 1, 57, 0, 0, 0, 0], profileID: .basiliskV4Hyperspeed))
    }

    func testReceiverEditorHydratesCapturedBindingsAndAppliesTurboRemapAndDefault() async throws {
        let device = MouseDevice(
            id: "v4-capture-editor", vendor_id: 0x1532, product_id: 0x00EA, product_name: "Basilisk V4 HyperSpeed", transport: .usb, path_b64: "", serial: "TEST-\(UUID().uuidString)", firmware: "1.0.16", location_id: 1, profile_id: .basiliskV4Hyperspeed,
            button_layout: DeviceProfiles.basiliskV4USB.buttonLayout)
        defer { clearRefactorPreferences(for: device) }
        let backend = AppStateRefactorStubBackend(devices: [device], stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 80, dpiValues: [1200, 2200], activeStage: 1))])
        for target in [0, 1] {
            await backend.setButtonBindingBlock([2, 2, 0, 0x22, 0, 0, 0], forDeviceID: device.id, slot: 128, profile: target)
            await backend.setButtonBindingBlock([13, 4, 0, 0x4B, 0, 0x53, 0], forDeviceID: device.id, slot: 52, profile: target)
        }
        let appState = AppState(launchRole: .app, backend: backend, autoStart: false)
        await appState.deviceStore.refreshDevices()
        try await waitForRefactorCondition { await MainActor.run { appState.editorStore.buttonBindingHidKey(for: 128) == 0x22 } }
        XCTAssertEqual(appState.editorStore.buttonBindingKind(for: 128), .keyboardSimple)
        XCTAssertEqual(appState.editorStore.buttonBindingTurboRatePressesPerSecond(for: 52), 12)
        XCTAssertEqual(appState.editorStore.buttonTurboPressesPerSecondRange, 4...20)
        appState.editorStore.updateButtonBindingTurboPressesPerSecond(slot: 52, pressesPerSecond: 10)
        try await waitForRefactorCondition { await backend.recordedPatches().contains(where: { $0.buttonBinding?.slot == 52 && $0.buttonBinding?.turboRate == 100 }) }
        appState.editorStore.updateButtonBindingTurboPressesPerSecond(slot: 52, pressesPerSecond: 12)
        try await waitForRefactorCondition { await backend.recordedPatches().contains(where: { $0.buttonBinding?.slot == 52 && $0.buttonBinding?.turboRate == 83 }) }
        appState.editorStore.updateButtonBindingKind(slot: 128, kind: .rightClick)
        try await waitForRefactorCondition { await backend.recordedPatches().contains(where: { $0.buttonBinding?.slot == 128 && $0.buttonBinding?.kind == .rightClick }) }
        appState.editorStore.updateButtonBindingKind(slot: 128, kind: .default)
        try await waitForRefactorCondition { await backend.recordedPatches().contains(where: { $0.buttonBinding?.slot == 128 && $0.buttonBinding?.kind == .default }) }
        let patches = await backend.recordedPatches().compactMap(\.buttonBinding).filter { $0.slot == 128 }
        XCTAssertEqual(patches.last?.kind, .default)
        XCTAssertTrue(patches.allSatisfy { $0.writePersistentLayer && $0.writeDirectLayer && $0.persistentProfile == 1 })
    }

    func testCapturedDefaultVariantsHydrateWithoutLosingCustomBindings() {
        var ai = response(target: 1, slot: 128, block: [0, 0, 0, 0, 0, 0, 0])
        ai[10] = 1  // Reconnect frames 3135/3150: normal request, stored flag one.
        XCTAssertEqual(ButtonBindingSupport.extractUSBFunctionBlock(response: ai, profile: 1, slot: 128, hypershift: 0, profileID: .basiliskV4Hyperspeed), [0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(ButtonBindingSupport.buttonBindingDraftFromUSBFunctionBlock(slot: 57, functionBlock: [12, 1, 57, 0, 0, 0, 0], profileID: .basiliskV4Hyperspeed)?.kind, .default)
        for (slot, buttonID) in [(52, UInt8(0x68)), (53, UInt8(0x69))] {
            let lengths: [UInt8] = [1, 3]
            for length in lengths { XCTAssertEqual(ButtonBindingSupport.buttonBindingDraftFromUSBFunctionBlock(slot: slot, functionBlock: [14, length, buttonID, 0, 20, 0, 0], profileID: .basiliskV4Hyperspeed)?.kind, .default) }
        }
        let tilt = ButtonBindingDraft(kind: .scrollLeft, hidKey: 4, turboEnabled: false, turboRate: 142)
        XCTAssertEqual(ButtonBindingSupport.usbFunctionBlockForWrite(slot: 128, draft: tilt, profileID: .basiliskV4Hyperspeed), [14, 3, 0x68, 0, 20, 0, 0])
    }

    func testReceiverTurboUsesCapturedMillisecondDelayWithoutChangingOtherTransports() {
        let receiver = DeviceProfiles.basiliskV4USB
        XCTAssertEqual(ButtonBindingSupport.turboRawToPressesPerSecond(0x53, profile: receiver), 12)
        XCTAssertEqual(ButtonBindingSupport.turboPressesPerSecondToRaw(12, profile: receiver), 0x53)
        XCTAssertEqual(ButtonBindingSupport.turboPressesPerSecondRange(profile: receiver), 4...20)
        for rate in 4...20 {
            let raw = ButtonBindingSupport.turboPressesPerSecondToRaw(rate, profile: receiver)
            XCTAssertEqual(ButtonBindingSupport.turboRawToPressesPerSecond(raw, profile: receiver), rate)
        }
        for profile in [DeviceProfiles.basiliskV4WiredUSB, DeviceProfiles.basiliskV4Bluetooth] {
            XCTAssertEqual(ButtonBindingSupport.turboPressesPerSecondRange(profile: profile), 1...20)
            XCTAssertEqual(ButtonBindingSupport.turboPressesPerSecondToRaw(12, profile: profile), ButtonBindingSupport.turboPressesPerSecondToRaw(12))
        }
        let draft = ButtonBindingDraft(kind: .keyboardSimple, hidKey: 0x4B, turboEnabled: true, turboRate: 0x53)
        XCTAssertEqual(ButtonBindingSupport.usbFunctionBlockForWrite(slot: 52, draft: draft, profileID: receiver.id), [13, 4, 0, 0x4B, 0, 0x53, 0])
    }

    /// Keeps the exact sanitized USBPcap reports separate from synthetic parser cases.
    private struct CapturedExchange: Decodable {
        let request: String
        let response: String
    }

    func testAllCapturedFeatureExchangesAndNormalButtonReadbacks() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let data = try Data(contentsOf: root.appendingPathComponent("captures/usb/2026-10-20-basilisk-v4-windows/feature-exchanges.json"))
        let exchanges = try JSONDecoder().decode([CapturedExchange].self, from: data)
        XCTAssertEqual(exchanges.count, 177)
        var normalButtonReads = 0
        var pollingReads = 0
        for exchange in exchanges {
            let request = try bytes(exchange.request)
            let response = try bytes(exchange.response)
            XCTAssertEqual(request.count, 90)
            XCTAssertEqual(response.count, 90)
            XCTAssertEqual(response[0], 2)
            XCTAssertEqual(request[1], response[1])
            XCTAssertEqual(Array(request[6...7]), Array(response[6...7]))
            XCTAssertEqual(response[88], response[2..<88].reduce(0, ^))
            if request[6] == 2, request[7] == 0x8C, request[10] == 0 {
                normalButtonReads += 1
                XCTAssertEqual(ButtonBindingSupport.extractUSBFunctionBlock(response: response, profile: request[8], slot: request[9], hypershift: 0, profileID: .basiliskV4Hyperspeed), Array(response[11..<18]))
            }
            if request[6] == 0, request[7] == 0x8E, request[8] == 1 {
                pollingReads += 1
                XCTAssertEqual(USBHIDProtocol.pollRate(from: response, encoding: .profileScoped), response[9] == 1 ? 1000 : 500)
            }
        }
        XCTAssertEqual(normalButtonReads, 36)
        XCTAssertEqual(pollingReads, 19)
    }

    private func bytes(_ hex: String) throws -> [UInt8] {
        let characters = Array(hex)
        XCTAssertEqual(characters.count % 2, 0)
        return try stride(from: 0, to: characters.count, by: 2).map { try XCTUnwrap(UInt8(String(characters[$0..<($0 + 2)]), radix: 16)) }
    }

    private func response(target: UInt8, slot: UInt8, block: [UInt8]) -> [UInt8] {
        var report = USBHIDProtocol.createReport(txn: 0x1F, classID: 2, cmdID: 0x8C, size: 10, args: [target, slot, 0] + block)
        report[0] = 2
        return report
    }
}
