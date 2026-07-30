# SocketIOClient

`SocketIOClient` implements the Socket.IO 4.x wire protocol over `URLSessionWebSocketTask`. The entire public API is typed via `SocketEvent` - event names and raw payloads are never exposed to callers.

`SocketIOClient` also conforms to `SocketClient`, the transport abstraction intended for higher-level consumers.

## Setup

```swift
let socketURL = SocketIOURL.webSocketURL(for: serverURL)!
let socket = SocketIOClient(
    url: socketURL,
    logging: .disabled
)
await socket.connect()
```

`SocketIOURL.webSocketURL(for:)` converts an HTTP/HTTPS server URL to the correct Socket.IO WebSocket URL (`wss://host/socket.io/?EIO=4&transport=websocket`).

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

## Reconnection

By default, the client reconnects with exponential backoff (1s initial, 15s max, 2× multiplier) after an unexpected disconnection. Disconnections triggered by `disconnect()` or `invalidate()` do not reconnect.

The client also watches for silence: if no inbound frame of any kind arrives within `pingInterval + pingTimeout` (taken from the server's handshake, defaulting to 25s/20s if unavailable), the connection is treated as half-open and torn down, triggering the same reconnection behavior as a network failure.

If the server rejects the connection (Socket.IO `CONNECT_ERROR`, for example due to invalid or expired credentials), `statusUpdates()` emits `.failed(reason:)` instead of `.disconnected`, and automatic reconnection is not attempted - the same credentials would only be rejected again. Call `connect()` or `reconnect(to:)` explicitly once the underlying cause has been addressed.

```swift
// Disable reconnection
let socket = SocketIOClient(url: url, reconnect: .disabled)

// Custom policy
let socket = SocketIOClient(url: url, reconnect: ReconnectPolicy(
    initialDelay: .seconds(2),
    maxDelay: .seconds(30),
    multiplier: 1.5
))
```

## Authentication

`auth` resolves the Socket.IO CONNECT `auth` payload. It is called fresh at the start of every connection attempt, so a refreshed token is used across reconnects rather than the value captured at init time.

```swift
let socket = SocketIOClient(
    url: socketURL,
    auth: { ["token": await tokenProvider.currentToken()] }
)
```

When `auth` is `nil` or resolves to an empty dictionary, a bare CONNECT frame is sent with no payload. This is the correct place to send credentials - unlike `SocketIOURL.webSocketURL(for:)`, which never carries credentials in its query string, the CONNECT payload is not logged by intermediate proxies, servers, or CDNs the way a URL query is.

`auth` is resolved while no further frames are read from the socket, so a slow closure delays the CONNECT frame and eats into the heartbeat window armed at the start of that connection attempt. Keep it fast - a local token read, not a network round trip.

## Logging

Runtime socket logs are controlled per instance through `RagnarNetworkingLogging`.

```swift
let socket = SocketIOClient(
    url: url,
    logging: RagnarNetworkingLogging(enabled: false)
)
```
