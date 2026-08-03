import Foundation

protocol SocketIORandomSource: Sendable {
    func unitInterval() -> Double
}

struct SystemSocketIORandomSource: SocketIORandomSource {
    func unitInterval() -> Double {
        Double.random(in: 0...1)
    }
}
