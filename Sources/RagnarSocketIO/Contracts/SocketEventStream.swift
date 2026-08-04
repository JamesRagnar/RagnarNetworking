import Foundation
import OSLog

/// An asynchronous sequence that decodes one typed value for each received event occurrence.
///
/// Each stream represents one independent subscription. Decoding occurs in `AsyncIterator.next()` rather than in the
/// client actor.
public struct SocketEventStream<Event: SocketEvent>: AsyncSequence, Sendable {
    /// The event schema produced by the sequence.
    public typealias Element = Event.Schema

    private let arguments: AsyncThrowingStream<[SocketIOArgument], Error>
    private let decoder: SocketEventDecoder
    private let loss: SocketStreamPolicy.Loss
    private let finishArguments: @Sendable (any Error) -> Void

    init(
        arguments: AsyncThrowingStream<[SocketIOArgument], Error>,
        decoder: SocketEventDecoder,
        loss: SocketStreamPolicy.Loss,
        finishArguments: @escaping @Sendable (any Error) -> Void
    ) {
        self.arguments = arguments
        self.decoder = decoder
        self.loss = loss
        self.finishArguments = finishArguments
    }

    /// Creates an iterator over this subscription.
    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            iterator: arguments.makeAsyncIterator(),
            decoder: decoder,
            loss: loss,
            finishArguments: finishArguments
        )
    }

    /// An iterator that decodes buffered Socket.IO arguments as the event schema.
    public struct AsyncIterator: AsyncIteratorProtocol {
        private var iterator: AsyncThrowingStream<[SocketIOArgument], Error>.AsyncIterator
        private let decoder: SocketEventDecoder
        private let loss: SocketStreamPolicy.Loss
        private let finishArguments: @Sendable (any Error) -> Void

        init(
            iterator: AsyncThrowingStream<[SocketIOArgument], Error>.AsyncIterator,
            decoder: SocketEventDecoder,
            loss: SocketStreamPolicy.Loss,
            finishArguments: @escaping @Sendable (any Error) -> Void
        ) {
            self.iterator = iterator
            self.decoder = decoder
            self.loss = loss
            self.finishArguments = finishArguments
        }

        /// Waits for and decodes the next event occurrence.
        ///
        /// An occurrence that does not satisfy the event's schema is lost. Under `.discard` it is dropped and iteration
        /// continues; under `.terminate` this subscription finishes with `SocketIOError.eventDecodingFailed`.
        public mutating func next() async throws -> Event.Schema? {
            while let arguments = try await iterator.next() {
                do {
                    return try Event.decode(
                        arguments: arguments,
                        using: decoder.makeDecoder()
                    )
                } catch {
                    let snapshot = SocketIODecodingErrorSnapshot(error)
                    guard loss == .discard else {
                        let streamError = SocketIOError.eventDecodingFailed(
                            eventName: Event.name,
                            snapshot: snapshot
                        )
                        finishArguments(streamError)
                        throw streamError
                    }
                    Logger.socketIO.error(
                        """
                        Discarded event \(Event.name, privacy: .private): \
                        schema failure \(snapshot.category, privacy: .public)
                        """
                    )
                }
            }
            return nil
        }
    }
}

/// A producer handle for a typed Socket.IO event stream.
///
/// Custom `SocketClient` implementations use a source to feed received arguments into the same decoding, buffering, and
/// loss behavior as `SocketIOClient`.
public struct SocketEventStreamSource<Event: SocketEvent>: Sendable {
    /// The typed stream returned to the event consumer.
    public let stream: SocketEventStream<Event>

    let continuation: SocketEventContinuation

    init(
        stream: SocketEventStream<Event>,
        continuation: SocketEventContinuation
    ) {
        self.stream = stream
        self.continuation = continuation
    }

    /// Feeds one ordered argument list into the stream.
    ///
    /// Returns `false` when the stream has terminated, including termination caused by a lost occurrence under
    /// `SocketStreamPolicy.Loss.terminate`.
    @discardableResult
    public func yield(arguments: [SocketIOArgument]) -> Bool {
        continuation.yield(arguments)
    }

    /// Finishes the stream normally.
    public func finish() {
        continuation.finish()
    }

    /// Finishes the stream with `error`.
    public func finish(throwing error: any Error) {
        continuation.finish(throwing: error)
    }
}

struct SocketEventContinuation: Sendable {
    private let eventName: String
    private let loss: SocketStreamPolicy.Loss
    private let continuation: AsyncThrowingStream<[SocketIOArgument], Error>.Continuation

    init(
        eventName: String,
        loss: SocketStreamPolicy.Loss,
        continuation: AsyncThrowingStream<[SocketIOArgument], Error>.Continuation
    ) {
        self.eventName = eventName
        self.loss = loss
        self.continuation = continuation
    }

    func yield(_ arguments: [SocketIOArgument]) -> Bool {
        switch continuation.yield(arguments) {
        case .enqueued:
            return true

        case .dropped:
            guard loss == .terminate else {
                Logger.socketIO.debug("Dropped event \(self.eventName, privacy: .private): stream buffer full")
                return true
            }
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
    /// Creates a typed stream and its producer source.
    ///
    /// Use this factory when implementing `SocketClient`. Values fed through the source retain the selected buffering,
    /// loss, and event decoding behavior.
    public static func makeStream(
        policy: SocketStreamPolicy = Event.defaultStreamPolicy,
        decoder: SocketEventDecoder = .default,
        onTermination: @escaping @Sendable () -> Void = {}
    ) -> SocketEventStreamSource<Event> {
        let subscription = make(
            policy: policy,
            decoder: decoder,
            onTermination: onTermination
        )
        return SocketEventStreamSource(
            stream: subscription.stream,
            continuation: subscription.continuation
        )
    }

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
                loss: policy.loss,
                finishArguments: { error in continuation.finish(throwing: error) }
            ),
            SocketEventContinuation(
                eventName: Event.name,
                loss: policy.loss,
                continuation: continuation
            )
        )
    }
}
