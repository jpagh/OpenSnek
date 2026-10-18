import XCTest
import OpenSnekCore
import OpenSnekHardware
import OpenSnekProtocols
@testable import OpenSnek

/// Locks down observed effect decoding, live presentation, and scoped hardware restoration.
@MainActor final class BasiliskV4LightingTests: XCTestCase {
    func testCapturedEffectsDecodeAndUnknownBodiesAreRejected() {
        let bodies: [([UInt8], LightingEffectKind)] = [
            ([0, 10, 3, 1, 40, 1, 0, 255, 0, 0, 255, 0], .spectrum), ([0, 10, 0, 0, 0, 0], .off), ([0, 10, 1, 0, 0, 1, 0, 255, 64], .staticColor), ([0, 10, 4, 2, 40, 0], .wave), ([0, 10, 5, 0, 2, 1, 255, 64, 0], .reactive), ([0, 10, 2, 0, 0, 0], .pulseRandom),
            ([0, 10, 2, 1, 0, 1, 0, 64, 255], .pulseSingle), ([0, 10, 2, 2, 0, 2, 0, 255, 64, 255, 64, 0], .pulseDual)
        ]
        for (body, kind) in bodies { XCTAssertEqual(USBHIDProtocol.lightingEffect(from: response(body), expectedLEDID: 10)?.kind, kind) }
        XCTAssertNil(USBHIDProtocol.lightingEffect(from: response([0, 10, 99]), expectedLEDID: 10))
        XCTAssertNil(USBHIDProtocol.lightingEffect(from: response([0, 10, 1, 0, 0, 1, 255]), expectedLEDID: 10))
        XCTAssertNil(USBHIDProtocol.lightingEffect(from: response([0, 10, 4, 7, 40, 0]), expectedLEDID: 10))
        XCTAssertNil(USBHIDProtocol.lightingEffect(from: response([0, 10, 3]), expectedLEDID: 4))
    }

    func testLiveEffectSurvivesStateMergeAndHydratesEditorInsteadOfStaticFallback() throws {
        let device = makeDevice()
        let effect = LightingEffectPatch(kind: .spectrum)
        let state = makeState(effect)
        XCTAssertEqual(state.merged(with: makeState(nil)).lighting_effect, effect)
        XCTAssertEqual(makeState(nil).mergedWithStableReadTelemetry(from: state).lighting_effect, effect)
        XCTAssertFalse(state.differsOnlyInDynamicDpiState(from: makeState(nil)))
        XCTAssertEqual(try JSONDecoder().decode(MouseState.self, from: JSONEncoder().encode(state)).lighting_effect, effect)
        let backend = AppStateRefactorStubBackend(devices: [], stateByDeviceID: [:])
        let app = AppState(launchRole: .app, backend: backend, autoStart: false)
        _ = app.deviceController.applyDeviceList([device], source: "refresh")
        app.deviceStore.state = state
        app.editorController.hydrateEditable(from: state)
        XCTAssertEqual(app.editorStore.editableLightingEffect, .spectrum)
        XCTAssertEqual(app.editorStore.visibleLightingEffects, LightingEffectKind.allCases.filter { $0 != .reactive })
        XCTAssertNil(DevicePatch(lightingEffect: LightingEffectPatch(kind: .reactive)).supportedUSBControls(for: device).lightingEffect)
    }

    func testHardwareEffectApplyReadbackAndExactRestore() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OPEN_SNEK_HW"] == "1" else { throw XCTSkip("Opt-in scoped hardware check") }
        let scope = try HardwareValidationScope(environment: environment)
        let client = BridgeClient()
        let device = try scope.select(from: await client.listDevices(), transport: .usb)
        guard device.profile_id == .basiliskV4Hyperspeed || device.profile_id == .basiliskV4HyperspeedWired else { throw HardwareValidationSession.failure("Select an explicitly scoped Basilisk V4 USB identity") }
        if scope.isRecovery {
            try await HardwareValidationSession.recover(deviceID: device.id, journalURL: scope.journalURL, read: { try await self.rawSnapshot(client, device) }, restore: { try await self.restore($0, client, device) })
            return
        }
        try await HardwareValidationSession.run(
            deviceID: device.id, journalURL: scope.journalURL, read: { try await self.rawSnapshot(client, device) }, restore: { try await self.restore($0, client, device) },
            operation: {
                for kind in DeviceProfiles.basiliskV4USB.supportedLightingEffects {
                    let effect = LightingEffectPatch(kind: kind, primary: RGBPatch(r: 0, g: 255, b: 64), secondary: RGBPatch(r: 255, g: 64, b: 0), waveDirection: .right)
                    _ = try await client.apply(device: device, patch: DevicePatch(lightingEffect: effect))
                    let state = try await client.readState(device: device)
                    guard let observed = state.lighting_effect, USBHIDProtocol.lightingEffect(observed, matches: effect) else { throw HardwareValidationSession.failure("Effect readback mismatch for \(kind)") }
                }
            })
    }

    private func requireStopped() throws { guard BLEProbeSession.runningAppProcessIDs().isEmpty else { throw HardwareValidationSession.failure("Stop app/service first") } }

    private func rawSnapshot(_ client: BridgeClient, _ device: MouseDevice) async throws -> [[UInt8]] {
        try requireStopped()
        _ = try await client.readState(device: device)
        guard let session = await client.sessionsFor(device: device).first else { throw HardwareValidationSession.failure("No control session") }
        var payloads: [[UInt8]] = []
        for target: UInt8 in [0, 1] {
            guard let raw = try await client.perform(session, device, classID: 15, cmdID: 0x82, size: 12, args: USBHIDProtocol.profileLightingEffectReadArgs(profile: target, ledID: 10)), let state = USBHIDProtocol.profileLightingEffectState(from: raw, expectedLEDID: 10), state.payload.count == 12
            else { throw HardwareValidationSession.failure("Incomplete raw effect baseline") }
            payloads.append(state.payload)
        }
        return payloads
    }

    private func restore(_ originals: [[UInt8]], _ client: BridgeClient, _ device: MouseDevice) async throws {
        try requireStopped()
        guard originals.count == 2, originals.allSatisfy({ $0.count == 12 && $0[1] == 10 }) else { throw HardwareValidationSession.failure("Invalid lighting journal") }
        _ = try await client.readState(device: device)
        guard let session = await client.sessionsFor(device: device).first else { throw HardwareValidationSession.failure("No recovery control session") }
        var errors: [String] = []
        for target in [1, 0] {
            var args = originals[target]
            args[0] = UInt8(target)
            do { guard try await client.perform(session, device, classID: 15, cmdID: 2, size: 12, args: args)?.first == 2 else { throw HardwareValidationSession.failure("Effect restore rejected") } } catch { errors.append(error.localizedDescription) }
        }
        guard errors.isEmpty else { throw HardwareValidationSession.failure("Retain journal: \(errors.joined(separator: "; "))") }
    }

    private func response(_ body: [UInt8]) -> [UInt8] {
        var report = USBHIDProtocol.createReport(txn: 31, classID: 15, cmdID: 0x82, size: UInt8(body.count), args: body)
        report[0] = 2
        return report
    }

    private func makeDevice() -> MouseDevice { MouseDevice(id: "v4-lighting-test", vendor_id: 0x1532, product_id: 0x00EA, product_name: "Basilisk V4 HyperSpeed", transport: .usb, path_b64: "", serial: nil, firmware: nil, profile_id: .basiliskV4Hyperspeed, supports_advanced_lighting_effects: true) }

    private func makeState(_ effect: LightingEffectPatch?) -> MouseState {
        MouseState(
            device: DeviceSummary(id: "v4-lighting-test", product_name: nil, serial: nil, transport: .usb, firmware: nil), connection: "USB", battery_percent: nil, charging: nil, dpi: nil, dpi_stages: DpiStages(active_stage: 0, values: [1600]), poll_rate: nil, device_mode: nil, led_value: 85,
            capabilities: Capabilities(dpi_stages: true, poll_rate: false, button_remap: true, lighting: true), lighting_effect: effect)
    }
}
