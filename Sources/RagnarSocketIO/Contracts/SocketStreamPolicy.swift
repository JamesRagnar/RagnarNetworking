import Foundation

/// Buffering and loss behavior for one Socket.IO event subscription.
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

    /// The action taken when an occurrence does not reach the consumer.
    ///
    /// An occurrence is lost when a bounded buffer drops it or when it does not satisfy the event's schema. Both are a
    /// gap in what the consumer receives, so both follow this setting.
    public enum Loss: Sendable, Equatable {
        /// Discard the occurrence and keep the subscription active.
        case discard
        /// Finish the subscription with `SocketIOError.bufferOverflow` or `SocketIOError.eventDecodingFailed`.
        case terminate
    }

    /// The policy's buffering behavior.
    public let buffering: Buffering
    /// The policy's action after an occurrence is lost.
    public let loss: Loss

    /// Creates a policy after validating that bounded capacities are positive.
    public init(
        buffering: Buffering,
        loss: Loss
    ) throws {
        try Self.validate(buffering)
        self.buffering = buffering
        self.loss = loss
    }

    /// Retains the oldest 64 pending events and discards any occurrence that is lost.
    public static let bounded = SocketStreamPolicy(
        uncheckedBuffering: .oldest(64),
        loss: .discard
    )

    /// Retains the oldest 64 pending events and terminates on any lost occurrence.
    public static let lossless = SocketStreamPolicy(
        uncheckedBuffering: .oldest(64),
        loss: .terminate
    )

    /// Retains only the newest pending event and discards any occurrence that is lost.
    public static let latest = SocketStreamPolicy(
        uncheckedBuffering: .newest(1),
        loss: .discard
    )

    /// Retains every pending event without a limit and discards any occurrence that is lost.
    public static let unbounded = SocketStreamPolicy(
        uncheckedBuffering: .unbounded,
        loss: .discard
    )

    /// Retains the oldest `capacity` events and discards any occurrence that is lost.
    public static func bounded(capacity: Int) throws -> SocketStreamPolicy {
        try SocketStreamPolicy(buffering: .oldest(capacity), loss: .discard)
    }

    /// Retains the oldest `capacity` events and terminates on any lost occurrence.
    public static func lossless(capacity: Int) throws -> SocketStreamPolicy {
        try SocketStreamPolicy(buffering: .oldest(capacity), loss: .terminate)
    }

    /// Retains the newest `capacity` events and discards any occurrence that is lost.
    public static func latest(capacity: Int) throws -> SocketStreamPolicy {
        try SocketStreamPolicy(buffering: .newest(capacity), loss: .discard)
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
        loss: Loss
    ) {
        self.buffering = buffering
        self.loss = loss
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
