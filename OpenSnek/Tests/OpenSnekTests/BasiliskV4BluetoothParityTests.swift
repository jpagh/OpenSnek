import XCTest
import OpenSnekCore
import OpenSnekHardware
import OpenSnekProtocols
@testable import OpenSnek

/// Covers the V4 BLE editor/backend boundary and reversible threshold hardware gate.
@MainActor final class BasiliskV4BluetoothParityTests: XCTestCase {
    func testThresholdVisibilityIsTransportAndProfileScoped() {
        XCTAssertTrue(device().supportsLowBatteryThresholdControls)
        let wired = MouseDevice(id: "wired", vendor_id: 0x1532, product_id: 0x00EB, product_name: "Basilisk V4", transport: .usb, path_b64: "", serial: nil, firmware: nil)
        XCTAssertTrue(wired.supportsLowBatteryThresholdControls)
        let v3 = MouseDevice(id: "v3", vendor_id: 0x068E, product_id: 0x00AC, product_name: "Basilisk V3 Pro", transport: .bluetooth, path_b64: "", serial: nil, firmware: nil)
        XCTAssertFalse(v3.supportsLowBatteryThresholdControls)
        XCTAssertNil(DevicePatch(lowBatteryThresholdRaw: 51).supportedBluetoothControls(for: v3).lowBatteryThresholdRaw)
        XCTAssertNotNil(DevicePatch(ledRGB: RGBPatch(r: 0, g: 255, b: 64)).supportedBluetoothControls(for: v3).ledRGB)
    }

    func testSavedUnsupportedLightingCannotEscapeBrightnessOnlyBLEProfile() {
        let original = DevicePatch(lowBatteryThresholdRaw: 51, ledBrightness: 96, ledRGB: RGBPatch(r: 0, g: 255, b: 64), lightingEffect: LightingEffectPatch(kind: .wave))
        let filtered = original.supportedBluetoothControls(for: device())
        XCTAssertEqual(filtered.lowBatteryThresholdRaw, 51)
        XCTAssertEqual(filtered.ledBrightness, 96)
        XCTAssertNil(filtered.ledRGB)
        XCTAssertNil(filtered.lightingEffect)
    }

    func testHardwareThresholdApplyReadbackAndExactRestore() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OPEN_SNEK_HW"] == "1" else { throw XCTSkip("Opt-in scoped V4 BLE check") }
        let scope = try HardwareValidationScope(environment: environment)
        let isolation = try BLEProbeSession()
        let client = BridgeClient()
        let selected = try scope.select(from: await client.listDevices(), transport: .bluetooth)
        guard selected.supportsLowBatteryThresholdControls else { throw HardwareValidationSession.failure("Select the validated V4 Bluetooth profile") }
        guard await client.prepareBluetoothControlConnection(preferredPeripheralName: selected.product_name) else { throw HardwareValidationSession.failure("Cannot prepare selected V4") }
        let peripherals = await client.btVendorClient.connectedPeripheralSummaries() ?? []
        guard peripherals.filter({ BluetoothNameMatcher.looselyMatches($0.name, selected.product_name) }).count == 1 else { throw HardwareValidationSession.failure("Disconnect other matching models first") }
        let read: () async throws -> Int = { try await self.readRaw(client, selected, isolation) }
        let restore: (Int) async throws -> Void = { raw in
            try isolation.checkAppIsStopped()
            guard (0...255).contains(raw), try await client.btSetScalar(device: selected, key: .lowBatteryThresholdSet, value: raw, size: 1, payloadLength: 1) else { throw HardwareValidationSession.failure("Raw threshold restore failed; retain journal") }
        }
        if scope.isRecovery {
            try await HardwareValidationSession.recover(deviceID: selected.id, journalURL: scope.journalURL, read: read, restore: restore)
            return
        }
        try await HardwareValidationSession.run(
            deviceID: selected.id, journalURL: scope.journalURL, read: read, restore: restore,
            operation: {
                for requested in [0x33, 0x30, 0, 255] {
                    let raw = max(0x0C, min(0x3F, requested))
                    try isolation.checkAppIsStopped()
                    let result = try await client.apply(device: selected, patch: DevicePatch(lowBatteryThresholdRaw: requested))
                    guard result.low_battery_threshold_raw == raw, try await read() == raw else { throw HardwareValidationSession.failure("App threshold apply/readback mismatch") }
                }
                let state = try await client.readState(device: selected)
                guard state.low_battery_threshold_raw == 0x3F else { throw HardwareValidationSession.failure("Full BLE telemetry omitted the threshold") }
            })
    }

    private func readRaw(_ client: BridgeClient, _ selected: MouseDevice, _ isolation: BLEProbeSession) async throws -> Int {
        try isolation.checkAppIsStopped()
        guard let raw = try await client.btGetScalar(device: selected, key: .lowBatteryThresholdGet, size: 1) else { throw HardwareValidationSession.failure("Missing complete threshold read; no mutation is safe") }
        return raw
    }

    private func device() -> MouseDevice { MouseDevice(id: "v4-ble", vendor_id: 0x068E, product_id: 0x00EC, product_name: "BSK V4 HS", transport: .bluetooth, path_b64: "", serial: nil, firmware: nil, profile_id: .basiliskV4Hyperspeed) }
}
