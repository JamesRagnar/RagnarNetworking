# SocketIOClient

`SocketIOClient` implements the Socket.IO 4.x wire protocol over `URLSessionWebSocketTask`. The entire public API is typed via `SocketEvent` - event names and raw payloads are never exposed to callers.

`SocketIOClient` also conforms to `SocketClient`, the transport abstraction intended for higher-level consumers.

## Setup

```swift
let socketURL = SocketIOClient.webSocketURL(for: serverURL)!
let socket = SocketIOClient(url: socketURL)
await socket.connect()
```

`SocketIOClient.webSocketURL(for:)` converts an HTTP/HTTPS server URL to the corresponding Socket.IO WebSocket URL, joining the default `socket.io` path onto the server URL's existing path and preserving any existing query items alongside `EIO` and `transport`. For a server with no path (`https://example.com`), this produces `wss://example.com/socket.io/?EIO=4&transport=websocket`. For a server hosted under a prefix (`https://example.com/api/v2`), this produces `wss://example.com/api/v2/socket.io/?EIO=4&transport=websocket`. Pass `path:` to override the Socket.IO endpoint path.

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
| `reconnect(to:)` | Switches to a new URL and reconnects, preserving all registered streams. |
| `invalidate()` | Closes the connection and finishes all streams. Use for teardown. |

## Protocol Coverage

Handled Socket.IO packet types: `CONNECT` (marks the connection `.connected`), `CONNECT_ERROR` (marks the connection `.failed(reason:)`), and `EVENT` (dispatched to `events(for:)` streams by event name).

Not handled: `DISCONNECT`, `ACK`, `BINARY_EVENT`, and `BINARY_ACK` packets are received and logged, but otherwise ignored - `emit` never requests an acknowledgement, and there is no API to send or receive binary (non-JSON) event payloads. Only the default Socket.IO namespace (`/`) is supported; events sent by a server on any other namespace are not parsed and are dropped as malformed frames.

`SocketIOClient` opens the WebSocket with `URLSessionWebSocketTask`'s URL-only initializer - it does not send custom headers (such as `Authorization`) on the handshake request. The only way to pass credentials is as a query item on the URL passed to `webSocketURL(for:)` or the client's initializer (for example `?token=...`, subject to the same interception/logging risk as any other URL query parameter), or via cookies already present in the `URLSession`'s cookie storage.

## Reconnection

By default, the client reconnects with exponential backoff (1s initial, 15s max, 2× multiplier) after an unexpected disconnection. Disconnections triggered by `disconnect()` or `invalidate()` do not reconnect.

The client also watches for silence: if no inbound frame of any kind arrives within `pingInterval + pingTimeout` (taken from the server's handshake, defaulting to 25s/20s if unavailable), the connection is treated as half-open and torn down, triggering the same reconnection behavior as a network failure.

If the server rejects the connection (Socket.IO `CONNECT_ERROR`, for example due to invalid or expired credentials), `statusUpdates()` emits `.failed(reason:)` instead of `.disconnected`, and automatic reconnection is not attempted - the same credentials would only be rejected again. Call `connect()` or `reconnect(to:)` explicitly once the underlying cause has been addressed.

```swift
// Disable reconnection
let socket = SocketIOClient(url: url, reconnect: .disabled)

// Custom policy
let socket = SocketIOClient(url: url, reconnect: SocketIOClient.ReconnectPolicy(
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
