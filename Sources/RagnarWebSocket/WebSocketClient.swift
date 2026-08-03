import Foundation

public protocol WebSocketClient: Actor {
    func open(_ request: URLRequest) throws
    func send(_ message: WebSocketMessage) async throws
    func receive() async throws -> WebSocketMessage
    func close(code: WebSocketCloseCode, reason: Data?)
}
