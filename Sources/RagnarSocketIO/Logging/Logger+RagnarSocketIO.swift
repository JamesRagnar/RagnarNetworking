import Foundation
import OSLog

let loggingSubsystem = "com.ragnar.networking"

extension Logger {

    static let socketIO = Logger(subsystem: loggingSubsystem, category: "SocketIO")

}

extension SocketConnectionFailure {

    /// A case label built only from package-owned constants, safe to log without redaction.
    var logLabel: String {
        switch self {
        case .protocolViolation:
            "protocolViolation"

        case .unsupportedCapability(let capability):
            "unsupportedCapability(\(capability))"

        case .connectError:
            "connectError"

        case .transport(let typeName):
            "transport(\(typeName))"

        case .heartbeatTimeout:
            "heartbeatTimeout"

        case .namespaceTimeout:
            "namespaceTimeout"

        case .reconnectExhausted(let attempts):
            "reconnectExhausted(\(attempts))"
        }
    }

    /// Peer-supplied detail that must stay redacted, or `nil` when the case carries none.
    var logDetail: String? {
        switch self {
        case .protocolViolation(let description):
            description

        case .connectError(let message):
            message

        case .unsupportedCapability, .transport, .heartbeatTimeout, .namespaceTimeout, .reconnectExhausted:
            nil
        }
    }

}

func logTerminalFailure(_ failure: SocketConnectionFailure) {
    let detail = failure.logDetail.map { " (\($0))" } ?? ""
    Logger.socketIO.error("Connection failed: \(failure.logLabel, privacy: .public)\(detail, privacy: .private)")
}

/// Retries can repeat in bursts, so they stay out of the persisted log store. The terminal outcome that follows is
/// logged at `.error`.
func logRetryableFailure(_ failure: SocketConnectionFailure) {
    let detail = failure.logDetail.map { " (\($0))" } ?? ""
    Logger.socketIO.debug("Connection dropped: \(failure.logLabel, privacy: .public)\(detail, privacy: .private)")
}

extension Duration {

    /// The duration in seconds, for timing values that OSLog cannot interpolate directly.
    var loggableSeconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + (Double(attoseconds) / 1e18)
    }

}
