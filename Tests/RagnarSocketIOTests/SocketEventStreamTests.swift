import Foundation
@testable import RagnarSocketIO
import Testing

private enum StreamEvent: SocketEvent {
    typealias Schema = Int
    static let name = "stream"
}

private func arguments(_ value: Int) throws -> [SocketIOArgument] {
    [try SocketIOArgument(value)]
}

@Suite("Socket Event Stream")
struct SocketEventStreamTests {
    @Test("Multiple subscribers receive independent ordered values")
    func subscribers() async throws {
        let first = SocketEventStream<StreamEvent>.make(
            policy: .lossless,
            decoder: .default,
            onTermination: {}
        )
        let second = SocketEventStream<StreamEvent>.make(
            policy: .lossless,
            decoder: .default,
            onTermination: {}
        )

        #expect(first.continuation.yield(try arguments(1)))
        #expect(first.continuation.yield(try arguments(2)))
        #expect(second.continuation.yield(try arguments(1)))
        #expect(second.continuation.yield(try arguments(2)))
        first.continuation.finish()
        second.continuation.finish()

        #expect(try await collect(first.stream) == [1, 2])
        #expect(try await collect(second.stream) == [1, 2])
    }

    @Test("A decoding failure discards the occurrence and iteration continues")
    func decodingFailure() async throws {
        let stream = SocketEventStream<StreamEvent>.make(
            policy: .bounded,
            decoder: .default,
            onTermination: {}
        )
        #expect(stream.continuation.yield([try SocketIOArgument("wrong")]))
        #expect(stream.continuation.yield(try arguments(1)))
        #expect(stream.continuation.yield([try SocketIOArgument("wrong"), try SocketIOArgument("count")]))
        #expect(stream.continuation.yield(try arguments(2)))
        stream.continuation.finish()

        #expect(try await collect(stream.stream) == [1, 2])
    }

    @Test("Oldest buffering terminates a lossless subscription on overflow")
    func losslessOverflow() async throws {
        let stream = SocketEventStream<StreamEvent>.make(
            policy: try .lossless(capacity: 1),
            decoder: .default,
            onTermination: {}
        )
        #expect(stream.continuation.yield(try arguments(1)))
        #expect(!stream.continuation.yield(try arguments(2)))

        var iterator = stream.stream.makeAsyncIterator()
        #expect(try await iterator.next() == 1)
        await #expect(throws: SocketIOError.bufferOverflow(eventName: "stream")) {
            try await iterator.next()
        }
    }

    @Test("Newest buffering drops old values and continues")
    func latestOverflow() async throws {
        let stream = SocketEventStream<StreamEvent>.make(
            policy: try .latest(capacity: 1),
            decoder: .default,
            onTermination: {}
        )
        #expect(stream.continuation.yield(try arguments(1)))
        #expect(stream.continuation.yield(try arguments(2)))
        stream.continuation.finish()

        #expect(try await collect(stream.stream) == [2])
    }

    @Test("Unbounded buffering is explicit")
    func unbounded() async throws {
        let stream = SocketEventStream<StreamEvent>.make(
            policy: .unbounded,
            decoder: .default,
            onTermination: {}
        )
        for value in 0..<100 {
            #expect(stream.continuation.yield(try arguments(value)))
        }
        stream.continuation.finish()
        #expect(try await collect(stream.stream) == Array(0..<100))
    }

    @Test("Iterator cancellation invokes termination cleanup")
    func cancellation() async throws {
        let terminated = AsyncStream<Void>.makeStream()
        let stream = SocketEventStream<StreamEvent>.make(
            policy: .lossless,
            decoder: .default,
            onTermination: { terminated.continuation.yield() }
        )
        let consumer = Task {
            var iterator = stream.stream.makeAsyncIterator()
            return try await iterator.next()
        }
        await Task.yield()
        consumer.cancel()
        _ = try? await consumer.value

        var terminationIterator = terminated.stream.makeAsyncIterator()
        _ = await terminationIterator.next()
    }

    @Test("Invalidation errors finish the stream")
    func invalidation() async {
        let stream = SocketEventStream<StreamEvent>.make(
            policy: .lossless,
            decoder: .default,
            onTermination: {}
        )
        stream.continuation.finish(throwing: SocketIOError.invalidated)

        var iterator = stream.stream.makeAsyncIterator()
        await #expect(throws: SocketIOError.invalidated) {
            try await iterator.next()
        }
    }
}

private func collect<Event: SocketEvent>(
    _ stream: SocketEventStream<Event>
) async throws -> [Event.Schema] {
    var values: [Event.Schema] = []
    for try await value in stream {
        values.append(value)
    }
    return values
}
