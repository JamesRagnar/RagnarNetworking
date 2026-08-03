# RagnarWebSocket

`RagnarWebSocket` provides message-level WebSocket transport through an actor-isolated `WebSocketClient` contract.
It does not manage a receive loop, connection status, reconnection, heartbeat, or application protocol.

## Create a Client

`URLSessionWebSocketClient` uses the supplied `URLSession` to create one `URLSessionWebSocketTask` at a time.

```swift
import Foundation
import RagnarWebSocket

let client = URLSessionWebSocketClient(session: .shared)
let request = URLRequest(url: URL(string: "wss://example.com/socket")!)

try await client.open(request)
```

The request URL must use `ws` or `wss` and include a host. `open(_:)` validates the request, creates the task, and
resumes it. It does not wait for the HTTP upgrade to complete. A received message or transport error establishes the
upgrade result for the protocol using the client.

Calling `open(_:)` while a task is active throws `WebSocketError.connectionAlreadyActive`.

## Send and Receive Messages

Messages are represented as `WebSocketMessage.text(_:)` or `WebSocketMessage.binary(_:)`.

```swift
try await client.send(.text("message"))

switch try await client.receive() {
case .text(let text):
    print(text)

case .binary(let data):
    print(data.count)
}
```

Each `receive()` call reads one message. Only one receive operation may be active for a client. A concurrent receive
throws `WebSocketError.concurrentReceive`.

`send(_:)` and `receive()` require an active task. If a suspended operation belongs to a task that has since closed,
the operation throws `WebSocketError.connectionReplacedOrClosed` rather than returning data from an inactive task.

## Close the Connection

```swift
await client.close(code: .normalClosure, reason: nil)
```

`close(code:reason:)` clears the active task before sending the close frame. Repeated calls have no effect. A later
`open(_:)` starts a new connection generation.

## Error Handling

`WebSocketError` distinguishes request validation, client state, concurrent receives, stale operations, and Foundation
transport failures. Transport failures contain a Sendable `WebSocketErrorSnapshot` with the underlying error type and
description.

## Protocol Integration

Higher-level protocols own these operations:

1. Open a validated WebSocket request.
2. Call `receive()` from one protocol-owned receive loop.
3. Interpret messages and apply protocol heartbeat or connection rules.
4. Close the transport when the protocol generation ends.
5. Open a new task when protocol policy requires reconnection.

Tests can inject an actor conforming to `WebSocketClient` without exposing `URLSessionWebSocketTask`.
