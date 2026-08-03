# SocketIOClient

`SocketIOClient` implements the Socket.IO 4.x wire protocol over `URLSessionWebSocketTask`. The entire public API is typed via `SocketEvent` - event names and raw payloads are never exposed to callers.

`SocketIOClient` also conforms to `SocketClient`, the transport abstraction intended for higher-level consumers.

## Setup

```swift
let socket = try SocketIOClient(endpoint: .server(serverURL))
await socket.connect()
```

`SocketEndpoint.server` accepts only HTTP/HTTPS URLs. The client converts the scheme to WS/WSS, joins the default `socket.io` path onto the server URL's existing path, preserves unrelated query items, and owns the `EIO=4` and `transport=websocket` query items. Pass `path:` to override the Socket.IO endpoint path.

Use `SocketEndpoint.webSocket` when discovery, a gateway, or a test fixture already supplies the complete WS/WSS Socket.IO URL. The client validates its scheme and host, then uses it verbatim:

```swift
let socket = try SocketIOClient(endpoint: .webSocket(discoveredURL))
```

Initialization throws `SocketEndpointError` before creating the client when the endpoint has an unsupported scheme, lacks a host, or cannot be resolved.

## Defining Events

```swift
struct ItemUpdatedEvent: SocketEvent {
    static let name = "item_updated"
    struct Schema: Decodable, Sendable {
        let libraryItemId: String
    }
}
```

For events with no payload, use `SocketEmptyBody` as the `Schema`:

```swift
struct ConnectEvent: SocketEvent {
    static let name = "connect"
    typealias Schema = SocketEmptyBody
}
```

## Receiving Events

```swift
for await event in await socket.events(for: ItemUpdatedEvent.self) {
    print(event.libraryItemId)
}
```

Each call to `events(for:)` returns an independent stream. Multiple consumers of the same event type each get their own stream. Streams persist across reconnection cycles - consumers never need to re-subscribe.

## Emitting Events

```swift
// With payload
try await socket.emit(SomeEvent.self, SomeEvent.Schema(value: 42))

// No payload
try await socket.emit(ConnectEvent.self)
```

## Status Updates

```swift
for await status in await socket.statusUpdates() {
    // .disconnected, .connecting, .connected
}
```

`statusUpdates()` emits the current status immediately on subscription, then streams all subsequent changes.

## Connection Lifecycle

| Method | Behavior |
|---|---|
| `connect()` | Opens the connection. No-ops if already connecting or connected. |
| `disconnect()` | Closes the connection. Event and status streams are preserved for reconnect. |
| `reconnect(to:)` | Validates and switches to a new endpoint, preserving all registered streams. Throws without changing the current connection when validation fails. |
| `invalidate()` | Closes the connection and finishes all streams. Use for teardown. |

## Protocol Coverage

Handled Socket.IO packet types: `CONNECT` (marks the connection `.connected`), `CONNECT_ERROR` (marks the connection `.failed(reason:)`), and `EVENT` (dispatched to `events(for:)` streams by event name).

Not handled: `DISCONNECT`, `ACK`, `BINARY_EVENT`, and `BINARY_ACK` packets are received and logged, but otherwise ignored - `emit` never requests an acknowledgement, and there is no API to send or receive binary (non-JSON) event payloads. Only the default Socket.IO namespace (`/`) is supported; events sent by a server on any other namespace are not parsed and are dropped as malformed frames.

`SocketIOClient` opens the WebSocket with `URLSessionWebSocketTask`'s URL-only initializer - it does not send custom headers such as `Authorization` on the handshake request. Credentials can be passed as query items in either endpoint URL, subject to the same interception and logging risks as any URL query parameter, or through cookies already present in the `URLSession`'s cookie storage.

## Reconnection

By default, the client reconnects with exponential backoff (1s initial, 15s max, 2× multiplier) after an unexpected disconnection. Disconnections triggered by `disconnect()` or `invalidate()` do not reconnect.

The client also watches for silence: if no inbound frame of any kind arrives within `pingInterval + pingTimeout` (taken from the server's handshake, defaulting to 25s/20s if unavailable), the connection is treated as half-open and torn down, triggering the same reconnection behavior as a network failure.

If the server rejects the connection (Socket.IO `CONNECT_ERROR`, for example due to invalid or expired credentials), `statusUpdates()` emits `.failed(reason:)` instead of `.disconnected`, and automatic reconnection is not attempted - the same credentials would only be rejected again. Call `connect()` or `try await reconnect(to:)` explicitly once the underlying cause has been addressed.

```swift
// Disable reconnection
let socket = try SocketIOClient(endpoint: .server(url), reconnect: .disabled)

// Custom policy
let socket = try SocketIOClient(endpoint: .server(url), reconnect: SocketIOClient.ReconnectPolicy(
    initialDelay: .seconds(2),
    maxDelay: .seconds(30),
    multiplier: 1.5
))
```

## Logging

`SocketIOClient` logs unconditionally via `os.Logger` under the `RagnarNetworking` subsystem,
category `Socket`. Control verbosity from outside the package with the standard OSLog tools -
Console.app, `log stream --predicate 'subsystem == "RagnarNetworking"'`, or
`log config --subsystem RagnarNetworking --mode level:off`.
