# RagnarWebSocket

`RagnarWebSocket` is a thin actor facade over one `URLSessionWebSocketTask`. It isolates Foundation transport details
without adding protocol or lifecycle policy.

```swift
import RagnarWebSocket

let client = URLSessionWebSocketClient()
try await client.open(URLRequest(url: URL(string: "wss://example.com/socket")!))
try await client.send(.text("message"))
let response = try await client.receive()
await client.close(code: .normalClosure, reason: nil)
```

## Contract

`WebSocketClient` provides:

- `open(_:)` to validate and start one `ws` or `wss` request.
- `send(_:)` for one text or binary message.
- `receive()` for one text or binary message.
- `close(code:reason:)` for idempotent explicit closure.

Only one receive may be active. Closing and opening a later generation prevents a suspended operation from returning a
message from the replaced connection.

`open(_:)` starts the HTTP upgrade but does not report a completed handshake. The first received message or transport
error establishes the outcome for a higher protocol.

## Deliberate Omissions

`RagnarWebSocket` does not provide:

- Receive loops or asynchronous streams.
- Connection status.
- Reconnection.
- Heartbeats.
- JSON coding.
- Engine.IO or Socket.IO framing.
- Application suspension behavior.

Higher protocols own those decisions. Tests can inject an actor conforming to `WebSocketClient` without importing
Foundation's task type or using `@testable import`.
