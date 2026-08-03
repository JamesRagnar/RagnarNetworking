import Foundation

public struct SocketEventDecoder: Sendable {
    private let makeValue: @Sendable () -> JSONDecoder

    public init(_ makeDecoder: @escaping @Sendable () -> JSONDecoder) {
        makeValue = makeDecoder
    }

    public static let `default` = SocketEventDecoder { JSONDecoder() }

    func makeDecoder() -> JSONDecoder {
        makeValue()
    }
}

public struct SocketEventEncoder: Sendable {
    private let makeValue: @Sendable () -> JSONEncoder

    public init(_ makeEncoder: @escaping @Sendable () -> JSONEncoder) {
        makeValue = makeEncoder
    }

    public static let `default` = SocketEventEncoder { JSONEncoder() }

    func makeEncoder() -> JSONEncoder {
        makeValue()
    }
}
