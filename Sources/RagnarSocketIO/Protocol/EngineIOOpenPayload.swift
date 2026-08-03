import Foundation

struct EngineIOOpenPayload: Decodable, Sendable, Equatable {
    let sessionID: String
    let upgrades: [String]
    let pingInterval: Duration
    let pingTimeout: Duration
    let maxPayload: Int

    private enum CodingKeys: String, CodingKey {
        case sessionID = "sid"
        case upgrades
        case pingInterval
        case pingTimeout
        case maxPayload
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        upgrades = try container.decode([String].self, forKey: .upgrades)

        let pingIntervalMilliseconds = try container.decode(Int64.self, forKey: .pingInterval)
        let pingTimeoutMilliseconds = try container.decode(Int64.self, forKey: .pingTimeout)
        guard
            Self.validHeartbeatMilliseconds(pingIntervalMilliseconds),
            Self.validHeartbeatMilliseconds(pingTimeoutMilliseconds)
        else {
            throw SocketIOProtocolError.invalidHeartbeatTiming
        }
        pingInterval = .milliseconds(pingIntervalMilliseconds)
        pingTimeout = .milliseconds(pingTimeoutMilliseconds)

        maxPayload = try container.decode(Int.self, forKey: .maxPayload)
        guard maxPayload > 0 else {
            throw SocketIOProtocolError.invalidMaximumPayload
        }
    }

    var wireValue: WireValue {
        get throws {
            WireValue(
                sessionID: sessionID,
                upgrades: upgrades,
                pingInterval: try pingInterval.milliseconds,
                pingTimeout: try pingTimeout.milliseconds,
                maxPayload: maxPayload
            )
        }
    }

    private static func validHeartbeatMilliseconds(_ value: Int64) -> Bool {
        value > 0 && value <= 86_400_000
    }

    struct WireValue: Encodable {
        let sessionID: String
        let upgrades: [String]
        let pingInterval: Int64
        let pingTimeout: Int64
        let maxPayload: Int

        private enum CodingKeys: String, CodingKey {
            case sessionID = "sid"
            case upgrades
            case pingInterval
            case pingTimeout
            case maxPayload
        }
    }
}

private extension Duration {
    var milliseconds: Int64 {
        get throws {
            let components = self.components
            let (secondsAsMilliseconds, overflow) = components.seconds.multipliedReportingOverflow(by: 1_000)
            guard !overflow, components.attoseconds % 1_000_000_000_000_000 == 0 else {
                throw SocketIOProtocolError.invalidHeartbeatTiming
            }
            let subsecondMilliseconds = components.attoseconds / 1_000_000_000_000_000
            let (milliseconds, additionOverflow) = secondsAsMilliseconds.addingReportingOverflow(subsecondMilliseconds)
            guard !additionOverflow, milliseconds > 0, milliseconds <= 86_400_000 else {
                throw SocketIOProtocolError.invalidHeartbeatTiming
            }
            return milliseconds
        }
    }
}
