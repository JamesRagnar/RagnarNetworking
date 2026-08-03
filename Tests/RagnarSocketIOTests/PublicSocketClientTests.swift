import Foundation
import RagnarSocketIO
import Testing

private enum PublicIncomingEvent: SocketEvent {
    typealias Schema = Int
    static let name = "incoming"
}

private enum PublicOutgoingEvent: EmittableSocketEvent {
    typealias Schema = Int
    static let name = "outgoing"
}

@Test("SocketClient exposes typed public contracts")
func publicSocketClientSurface() async {
    let client: any SocketClient = SocketIOClient(reconnectPolicy: .disabled)
    _ = await client.events(for: PublicIncomingEvent.self)
    await #expect(throws: SocketIOError.notConnected) {
        try await client.emit(PublicOutgoingEvent.self, 1)
    }
    await client.invalidate()
}
