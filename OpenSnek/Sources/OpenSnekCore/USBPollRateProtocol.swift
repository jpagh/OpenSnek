/// Selects the transport-specific polling register encoding without raw-PID checks.
public enum USBPollRateProtocol: String, Codable, Sendable {
    case standard
    case extended
    case profileScoped
}
