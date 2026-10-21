import OpenSnekCore

/// Shares the exact button-write/readback transaction between app and probe.
public extension USBHIDProtocol {
    /// Selects a device bank, control, layer, and exact seven-byte function.
    struct ButtonBindingWrite {
        public let profile: UInt8
        public let slot: UInt8
        public let hypershift: UInt8
        public let functionBlock: [UInt8]

        public init(profile: UInt8, slot: UInt8, hypershift: UInt8, functionBlock: [UInt8]) {
            self.profile = profile
            self.slot = slot
            self.hypershift = hypershift
            self.functionBlock = functionBlock
        }
    }

    /// Call under exclusive device access. ACK is followed by one exact normal-layer read.
    static func performVerifiedButtonWrite(_ request: ButtonBindingWrite, profileID: DeviceProfileID, exchange: (UInt8, [UInt8]) throws -> [UInt8]?) throws -> Bool {
        guard request.hypershift == 0, request.functionBlock.count == 7 else { return false }
        let selector = [request.profile, request.slot, request.hypershift]
        guard try exchange(0x0C, selector + request.functionBlock)?.first == 0x02 else { return false }
        guard let response = try exchange(0x8C, selector + Array(repeating: 0, count: 7)) else { return false }
        let readback = ButtonBindingSupport.extractUSBFunctionBlock(response: response, profile: request.profile, slot: request.slot, hypershift: request.hypershift, profileID: profileID)
        guard let readback else { return false }
        return ButtonBindingSupport.usbFunctionBlockMatchesReadback(slot: Int(request.slot), expected: request.functionBlock, readback: readback, profileID: profileID)
    }
}
