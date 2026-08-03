import Foundation

public struct SocketStreamPolicy: Sendable, Equatable {
    public enum Buffering: Sendable, Equatable {
        case unbounded
        case oldest(Int)
        case newest(Int)
    }

    public enum Overflow: Sendable, Equatable {
        case dropAndContinue
        case terminate
    }

    public let buffering: Buffering
    public let overflow: Overflow

    public init(
        buffering: Buffering,
        overflow: Overflow
    ) throws {
        try Self.validate(buffering)
        self.buffering = buffering
        self.overflow = overflow
    }

    public static let lossless = SocketStreamPolicy(
        uncheckedBuffering: .oldest(64),
        overflow: .terminate
    )

    public static let latest = SocketStreamPolicy(
        uncheckedBuffering: .newest(1),
        overflow: .dropAndContinue
    )

    public static let unbounded = SocketStreamPolicy(
        uncheckedBuffering: .unbounded,
        overflow: .dropAndContinue
    )

    public static func lossless(capacity: Int) throws -> SocketStreamPolicy {
        try SocketStreamPolicy(buffering: .oldest(capacity), overflow: .terminate)
    }

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
