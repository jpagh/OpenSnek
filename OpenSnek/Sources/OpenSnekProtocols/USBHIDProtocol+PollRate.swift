import OpenSnekCore

/// Describes one polling-register exchange without transport ownership.
public struct USBPollRateCommand: Sendable {
    public let commandID: UInt8
    public let size: UInt8
    public let args: [UInt8]
}

/// Keeps legacy divisors separate from the newer 8 kHz-base polling register.
public extension USBHIDProtocol {
    static func pollRateReadCommand(encoding: USBPollRateProtocol) -> USBPollRateCommand {
        switch encoding {
        case .standard: return USBPollRateCommand(commandID: 0x85, size: 1, args: [])
        case .extended: return USBPollRateCommand(commandID: 0xC0, size: 2, args: [0, 0])
        }
    }

    static func pollRateWriteCommand(hz: Int, encoding: USBPollRateProtocol) -> USBPollRateCommand? {
        switch encoding {
        case .standard:
            guard let raw = [1000: UInt8(1), 500: 2, 125: 8][hz] else { return nil }
            return USBPollRateCommand(commandID: 5, size: 1, args: [raw])
        case .extended:
            guard let raw = [8000: UInt8(1), 4000: 2, 2000: 4, 1000: 8, 500: 16, 250: 32, 125: 64][hz] else { return nil }
            return USBPollRateCommand(commandID: 0x40, size: 2, args: [0, raw])
        }
    }

    static func pollRate(from response: [UInt8], encoding: USBPollRateProtocol) -> Int? {
        let command = pollRateReadCommand(encoding: encoding)
        guard response.count > 8, response[0] == 2, response[6] == 0, response[7] == command.commandID else { return nil }
        switch encoding {
        case .standard: return [UInt8(1): 1000, 2: 500, 8: 125][response[8]]
        case .extended:
            // Some firmware declares size 1 but places the rate in args[1].
            guard response.count > 9, response[8] == 0 else { return nil }
            return [UInt8(1): 8000, 2: 4000, 4: 2000, 8: 1000, 16: 500, 32: 250, 64: 125][response[9]]
        }
    }
}
