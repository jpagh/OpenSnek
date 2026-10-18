import XCTest
import OpenSnekCore
import OpenSnekHardware
@testable import OpenSnek

/// Exercises USB DPI transitions while preserving raw live and persistent originals.
@MainActor final class BasiliskV4DPITests: XCTestCase {
    func testHardwareUSBStageTransitionsAndExactRestore() async throws {
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
                let steps = [([1000, 2000], 0), ([1000, 2000], 1), ([800, 1600, 3200], 2), ([1200], 0)]
                for (index, step) in steps.enumerated() {
                    let (values, active) = step
                    let patch = index == 1 ? DevicePatch(activeStage: active) : DevicePatch(dpiStagePairs: values.map { DpiPair(x: $0, y: $0) }, activeStage: active)
                    _ = try await client.apply(device: device, patch: patch)
                    let state = try await client.readState(device: device)
                    guard state.dpi_stages.values == values, state.dpi_stages.active_stage == active, state.dpi == DpiPair(x: values[active], y: values[active]) else {
                        let raw = try await self.snapshot(client, device)
                        throw HardwareValidationSession.failure("DPI transition mismatch expected=\(values) active=\(active) observed=\(String(describing: state.dpi_stages.values)) active=\(String(describing: state.dpi_stages.active_stage)) scalar=\(String(describing: state.dpi)) raw=\(raw)")
                    }
                }
            })
    }

    private func requireStopped() throws { guard BLEProbeSession.runningAppProcessIDs().isEmpty else { throw HardwareValidationSession.failure("Stop app/service first") } }

    private func snapshot(_ client: BridgeClient, _ device: MouseDevice) async throws -> [[UInt8]] {
        try requireStopped()
        _ = try await client.readState(device: device)
        guard let session = await client.sessionsFor(device: device).first else { throw HardwareValidationSession.failure("No control session") }
        var originals: [[UInt8]] = []
        let reads: [(UInt8, UInt8)] = [(0x86, 38), (0x85, 7)]
        for target: UInt8 in [0, 1] {
            for (command, size) in reads {
                guard let raw = try await client.perform(session, device, classID: 4, cmdID: command, size: size, args: [target]), raw[0] == 2, raw[8] == target else { throw HardwareValidationSession.failure("Incomplete DPI baseline") }
                let payload = Array(raw[8..<(8 + Int(size))])
                if size == 38 { guard (1...5).contains(payload[2]) else { throw HardwareValidationSession.failure("Invalid DPI stage count") } }
                originals.append(payload)
            }
        }
        return originals
    }

    private func restore(_ originals: [[UInt8]], _ client: BridgeClient, _ device: MouseDevice) async throws {
        try requireStopped()
        guard originals.count == 4, originals.map(\.count) == [38, 7, 38, 7], originals[0][0] == 0, originals[1][0] == 0, originals[2][0] == 1, originals[3][0] == 1 else { throw HardwareValidationSession.failure("Invalid DPI recovery journal") }
        _ = try await client.readState(device: device)
        guard let session = await client.sessionsFor(device: device).first else { throw HardwareValidationSession.failure("No recovery control session") }
        var errors: [String] = []
        for index in [2, 3, 0, 1] {
            let payload = originals[index]
            do { guard try await client.perform(session, device, classID: 4, cmdID: payload.count == 38 ? 6 : 5, size: UInt8(payload.count), args: payload)?.first == 2 else { throw HardwareValidationSession.failure("Raw DPI restore rejected") } } catch { errors.append(error.localizedDescription) }
        }
        guard errors.isEmpty else { throw HardwareValidationSession.failure("Retain recovery journal: \(errors.joined(separator: "; "))") }
    }
}
