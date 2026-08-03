import Foundation

public struct SocketEventStream<Event: SocketEvent>: AsyncSequence, Sendable {
    public typealias Element = Event.Schema

    private let arguments: AsyncThrowingStream<[SocketIOArgument], Error>
    private let decoder: SocketEventDecoder
    private let finishArguments: @Sendable (any Error) -> Void

    init(
        arguments: AsyncThrowingStream<[SocketIOArgument], Error>,
        decoder: SocketEventDecoder,
        finishArguments: @escaping @Sendable (any Error) -> Void
    ) {
        self.arguments = arguments
        self.decoder = decoder
        self.finishArguments = finishArguments
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            iterator: arguments.makeAsyncIterator(),
            decoder: decoder,
            finishArguments: finishArguments
        )
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private var iterator: AsyncThrowingStream<[SocketIOArgument], Error>.AsyncIterator
        private let decoder: SocketEventDecoder
        private let finishArguments: @Sendable (any Error) -> Void

        init(
            iterator: AsyncThrowingStream<[SocketIOArgument], Error>.AsyncIterator,
            decoder: SocketEventDecoder,
            finishArguments: @escaping @Sendable (any Error) -> Void
        ) {
            self.iterator = iterator
            self.decoder = decoder
            self.finishArguments = finishArguments
        }

        public mutating func next() async throws -> Event.Schema? {
            guard let arguments = try await iterator.next() else { return nil }

            do {
                return try Event.decode(
                    arguments: arguments,
                    using: decoder.makeDecoder()
                )
            } catch {
                let streamError = if let socketError = error as? SocketIOError {
                    socketError
                } else {
                    SocketIOError.eventDecodingFailed(
                        eventName: Event.name,
                        snapshot: SocketIODecodingErrorSnapshot(error)
                    )
                }
                finishArguments(streamError)
                throw streamError
            }
        }
    }
}

struct SocketEventContinuation: Sendable {
    private let eventName: String
    private let overflow: SocketStreamPolicy.Overflow
    private let continuation: AsyncThrowingStream<[SocketIOArgument], Error>.Continuation

    init(
        eventName: String,
        overflow: SocketStreamPolicy.Overflow,
        continuation: AsyncThrowingStream<[SocketIOArgument], Error>.Continuation
    ) {
        self.eventName = eventName
        self.overflow = overflow
        self.continuation = continuation
    }

    func yield(_ arguments: [SocketIOArgument]) -> Bool {
        switch continuation.yield(arguments) {
        case .enqueued:
            return true

        case .dropped:
            guard overflow == .terminate else { return true }
            continuation.finish(throwing: SocketIOError.bufferOverflow(eventName: eventName))
            return false

        case .terminated:
            return false

        @unknown default:
            return false
        }
    }

    func finish(throwing error: (any Error)? = nil) {
        continuation.finish(throwing: error)
    }
}

extension SocketEventStream {
    static func make(
        policy: SocketStreamPolicy,
        decoder: SocketEventDecoder,
        onTermination: @escaping @Sendable () -> Void
    ) -> (stream: SocketEventStream<Event>, continuation: SocketEventContinuation) {
        let (arguments, continuation) = AsyncThrowingStream<[SocketIOArgument], Error>.makeStream(
            bufferingPolicy: policy.bufferingPolicy
        )
        continuation.onTermination = { _ in onTermination() }
        return (
            SocketEventStream(
                arguments: arguments,
                decoder: decoder,
                finishArguments: { error in continuation.finish(throwing: error) }
            ),
            SocketEventContinuation(
                eventName: Event.name,
                overflow: policy.overflow,
                continuation: continuation
            )
        )
    }
}
