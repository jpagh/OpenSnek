/// Keeps saved/backend patches within the mapped Bluetooth feature surface.
public extension DevicePatch {
    func supportedBluetoothControls(for device: MouseDevice) -> DevicePatch {
        guard device.transport == .bluetooth, let profile = DeviceProfiles.resolve(vendorID: device.vendor_id, productID: device.product_id, transport: device.transport) else { return self }
        var supported = self
        if profile.supportedLightingEffects.isEmpty { supported.ledRGB = nil }
        if let effect = supported.lightingEffect, !profile.supportedLightingEffects.contains(effect.kind) { supported.lightingEffect = nil }
        if !profile.supportsBluetoothLowBatteryThresholdControls { supported.lowBatteryThresholdRaw = nil }
        return supported
    }
}
