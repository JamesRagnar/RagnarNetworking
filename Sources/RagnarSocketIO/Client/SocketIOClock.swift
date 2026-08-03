import Foundation

protocol SocketIOClock: Sendable {
    func sleep(for duration: Duration) async throws
}

struct ContinuousSocketIOClock: SocketIOClock {
    func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}
