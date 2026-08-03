import Foundation

/// A Sendable factory that creates an independent decoder for each event decode.
public struct SocketEventDecoder: Sendable {
    private let makeValue: @Sendable () -> JSONDecoder

    /// Creates a decoder factory.
    public init(_ makeDecoder: @escaping @Sendable () -> JSONDecoder) {
        makeValue = makeDecoder
    }

    /// A factory that creates an unconfigured `JSONDecoder`.
    public static let `default` = SocketEventDecoder { JSONDecoder() }

    func makeDecoder() -> JSONDecoder {
        makeValue()
    }
}

/// A Sendable factory that creates an independent encoder for each event emission.
public struct SocketEventEncoder: Sendable {
    private let makeValue: @Sendable () -> JSONEncoder

    /// Creates an encoder factory.
    public init(_ makeEncoder: @escaping @Sendable () -> JSONEncoder) {
        makeValue = makeEncoder
    }

    /// A factory that creates an unconfigured `JSONEncoder`.
    public static let `default` = SocketEventEncoder { JSONEncoder() }

    func makeEncoder() -> JSONEncoder {
        makeValue()
    }
}
