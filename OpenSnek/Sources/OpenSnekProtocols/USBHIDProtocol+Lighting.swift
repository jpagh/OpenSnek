import OpenSnekCore

/// Decodes only effect bodies validated on the standard USB extended-lighting surface.
public extension USBHIDProtocol {
    static func lightingEffect(from response: [UInt8], expectedLEDID: UInt8) -> LightingEffectPatch? {
        guard let state = profileLightingEffectState(from: response, expectedLEDID: expectedLEDID) else { return nil }
        let body = state.payload
        switch state.effectID {
        case 0: return LightingEffectPatch(kind: .off)
        case 3: return LightingEffectPatch(kind: .spectrum)
        case 4:
            guard body.count >= 6, let direction = LightingWaveDirection(rawValue: Int(body[3])) else { return nil }
            return LightingEffectPatch(kind: .wave, waveDirection: direction)
        case 1, 5:
            guard body.count >= 9, body[5] == 1 else { return nil }
            if state.effectID == 5, !(1...4).contains(body[4]) { return nil }
            return LightingEffectPatch(kind: state.effectID == 1 ? .staticColor : .reactive, primary: RGBPatch(r: Int(body[6]), g: Int(body[7]), b: Int(body[8])), reactiveSpeed: state.effectID == 5 ? Int(body[4]) : 2)
        case 2: return pulseEffect(from: body)
        default: return nil
        }
    }

    private static func pulseEffect(from body: [UInt8]) -> LightingEffectPatch? {
        guard body.count >= 6 else { return nil }
        switch body[3] {
        case 0: return LightingEffectPatch(kind: .pulseRandom)
        case 1:
            guard body.count >= 9, body[5] == 1 else { return nil }
            return LightingEffectPatch(kind: .pulseSingle, primary: RGBPatch(r: Int(body[6]), g: Int(body[7]), b: Int(body[8])))
        case 2:
            guard body.count >= 12, body[5] == 2 else { return nil }
            return LightingEffectPatch(kind: .pulseDual, primary: RGBPatch(r: Int(body[6]), g: Int(body[7]), b: Int(body[8])), secondary: RGBPatch(r: Int(body[9]), g: Int(body[10]), b: Int(body[11])))
        default: return nil
        }
    }

    static func lightingEffect(_ observed: LightingEffectPatch, matches requested: LightingEffectPatch) -> Bool {
        guard observed.kind == requested.kind else { return false }
        if requested.kind.usesPrimaryColor, observed.primary != requested.primary { return false }
        if requested.kind.usesSecondaryColor, observed.secondary != requested.secondary { return false }
        if requested.kind == .wave, observed.waveDirection != requested.waveDirection { return false }
        return requested.kind != .reactive || observed.reactiveSpeed == requested.reactiveSpeed
    }
}
