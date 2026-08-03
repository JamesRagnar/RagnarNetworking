import Foundation

/// Buffering and overflow behavior for one Socket.IO event subscription.
public struct SocketStreamPolicy: Sendable, Equatable {
    /// The values retained while the consumer is not requesting the next element.
    public enum Buffering: Sendable, Equatable {
        /// Retain every pending value without a limit.
        case unbounded
        /// Retain the oldest values up to the supplied capacity.
        case oldest(Int)
        /// Retain the newest values up to the supplied capacity.
        case newest(Int)
    }

    /// The action taken when a bounded buffer drops a value.
    public enum Overflow: Sendable, Equatable {
        /// Keep the subscription active after the buffering policy drops a value.
        case dropAndContinue
        /// Finish the subscription with `SocketIOError.bufferOverflow`.
        case terminate
    }

    /// The policy's buffering behavior.
    public let buffering: Buffering
    /// The policy's action after a bounded buffer drops a value.
    public let overflow: Overflow

    /// Creates a policy after validating that bounded capacities are positive.
    public init(
        buffering: Buffering,
        overflow: Overflow
    ) throws {
        try Self.validate(buffering)
        self.buffering = buffering
        self.overflow = overflow
    }

    /// Retains the oldest 64 pending events and terminates on overflow.
    public static let lossless = SocketStreamPolicy(
        uncheckedBuffering: .oldest(64),
        overflow: .terminate
    )

    /// Retains only the newest pending event and continues after dropping an older value.
    public static let latest = SocketStreamPolicy(
        uncheckedBuffering: .newest(1),
        overflow: .dropAndContinue
    )

    /// Retains every pending event without a limit.
    public static let unbounded = SocketStreamPolicy(
        uncheckedBuffering: .unbounded,
        overflow: .dropAndContinue
    )

    /// Retains the oldest `capacity` events and terminates on overflow.
    public static func lossless(capacity: Int) throws -> SocketStreamPolicy {
        try SocketStreamPolicy(buffering: .oldest(capacity), overflow: .terminate)
    }

    /// Retains the newest `capacity` events and continues after dropping older values.
    public static func latest(capacity: Int) throws -> SocketStreamPolicy {
        try SocketStreamPolicy(buffering: .newest(capacity), overflow: .dropAndContinue)
    }

    var bufferingPolicy: AsyncThrowingStream<[SocketIOArgument], Error>.Continuation.BufferingPolicy {
        switch buffering {
        case .unbounded:
            .unbounded

        case .oldest(let capacity):
            .bufferingOldest(capacity)

        case .newest(let capacity):
            .bufferingNewest(capacity)
        }
    }

    private init(
        uncheckedBuffering buffering: Buffering,
        overflow: Overflow
    ) {
        self.buffering = buffering
        self.overflow = overflow
    }

    private static func validate(_ buffering: Buffering) throws {
        switch buffering {
        case .unbounded:
            return

        case .oldest(let capacity), .newest(let capacity):
            guard capacity > 0 else {
                throw SocketIOError.invalidStreamCapacity(capacity)
            }
        }
    }
}
