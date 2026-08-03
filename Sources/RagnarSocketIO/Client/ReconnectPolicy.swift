import Foundation

public struct ReconnectPolicy: Sendable, Equatable {
    public let enabled: Bool
    public let initialDelay: Duration
    public let maximumDelay: Duration
    public let multiplier: Double
    public let jitter: Double
    public let maximumAttempts: Int?

    public init(
        enabled: Bool = true,
        initialDelay: Duration = .seconds(1),
        maximumDelay: Duration = .seconds(15),
        multiplier: Double = 2,
        jitter: Double = 0.2,
        maximumAttempts: Int? = nil
    ) throws {
        guard initialDelay >= .zero, maximumDelay >= .zero, initialDelay <= maximumDelay else {
            throw ReconnectPolicyError.invalidDelay
        }
        guard multiplier >= 1, multiplier.isFinite else {
            throw ReconnectPolicyError.invalidMultiplier
        }
        guard (0...1).contains(jitter), jitter.isFinite else {
            throw ReconnectPolicyError.invalidJitter
        }
        guard maximumAttempts.map({ $0 >= 0 }) ?? true else {
            throw ReconnectPolicyError.invalidMaximumAttempts
        }

        self.enabled = enabled
        self.initialDelay = initialDelay
        self.maximumDelay = maximumDelay
        self.multiplier = multiplier
        self.jitter = jitter
        self.maximumAttempts = maximumAttempts
    }

    public static let `default` = ReconnectPolicy(
        uncheckedEnabled: true,
        initialDelay: .seconds(1),
        maximumDelay: .seconds(15),
        multiplier: 2,
        jitter: 0.2,
        maximumAttempts: nil
    )

    public static let disabled = ReconnectPolicy(
        uncheckedEnabled: false,
        initialDelay: .zero,
        maximumDelay: .zero,
        multiplier: 1,
        jitter: 0,
        maximumAttempts: 0
    )

    private init(
        uncheckedEnabled enabled: Bool,
        initialDelay: Duration,
        maximumDelay: Duration,
        multiplier: Double,
        jitter: Double,
        maximumAttempts: Int?
    ) {
        self.enabled = enabled
        self.initialDelay = initialDelay
        self.maximumDelay = maximumDelay
        self.multiplier = multiplier
        self.jitter = jitter
        self.maximumAttempts = maximumAttempts
    }
}

public enum ReconnectPolicyError: Error, Sendable, Equatable {
    case invalidDelay
    case invalidMultiplier
    case invalidJitter
    case invalidMaximumAttempts
}
