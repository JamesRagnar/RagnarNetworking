import Foundation
import RagnarWebSocket
import Testing

private actor PublicWebSocketClientFake: WebSocketClient {
    func open(_ request: URLRequest) throws {}
    func send(_ message: WebSocketMessage) async throws {}
    func receive() async throws -> WebSocketMessage { .text("message") }
    func close(code: WebSocketCloseCode, reason: Data?) {}
}

@Test("WebSocketClient supports public actor conformances")
func publicConformance() async throws {
    let client: any WebSocketClient = PublicWebSocketClientFake()
    try await client.open(URLRequest(url: URL(string: "wss://example.com")!))
    #expect(try await client.receive() == .text("message"))
}
