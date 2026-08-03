import Foundation

/// Backoff configuration for automatic transport reconnection.
public struct ReconnectPolicy: Sendable, Equatable {
    /// Whether automatic reconnection is enabled.
    public let enabled: Bool
    /// The delay before the first reconnect attempt.
    public let initialDelay: Duration
    /// The upper bound applied after exponential backoff and jitter.
    public let maximumDelay: Duration
    /// The exponential multiplier applied between attempts.
    public let multiplier: Double
    /// The maximum symmetric random variation, expressed from `0` through `1`.
    public let jitter: Double
    /// The maximum number of reconnect attempts, or `nil` for no attempt limit.
    public let maximumAttempts: Int?

    /// Creates a validated reconnect policy.
    ///
    /// Delays must be nonnegative, `initialDelay` must not exceed `maximumDelay`, `multiplier` must be finite and at
    /// least `1`, `jitter` must be finite and within `0...1`, and `maximumAttempts` must be nonnegative when supplied.
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

    /// Exponential backoff from one to fifteen seconds, with 20 percent jitter and no attempt limit.
    public static let `default` = ReconnectPolicy(
        uncheckedEnabled: true,
        initialDelay: .seconds(1),
        maximumDelay: .seconds(15),
        multiplier: 2,
        jitter: 0.2,
        maximumAttempts: nil
    )

    /// A policy that prevents automatic reconnection.
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

/// Validation errors produced when constructing a `ReconnectPolicy`.
public enum ReconnectPolicyError: Error, Sendable, Equatable {
    /// A delay is negative or the initial delay exceeds the maximum delay.
    case invalidDelay
    /// The multiplier is non-finite or less than one.
    case invalidMultiplier
    /// Jitter is non-finite or outside `0...1`.
    case invalidJitter
    /// The maximum attempt count is negative.
    case invalidMaximumAttempts
}
