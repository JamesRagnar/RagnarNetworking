# RagnarSocketIO

`RagnarSocketIO` implements Engine.IO protocol 4 and Socket.IO protocol 5 over the `RagnarWebSocket` transport. It
provides typed event contracts, asynchronous event streams, connection status, heartbeat handling, and reconnection.

## Protocol Scope

The client supports:

- Direct WebSocket transport.
- The default `/` namespace.
- Engine.IO `OPEN`, `CLOSE`, `PING`, `PONG`, and `MESSAGE` packets.
- Socket.IO `CONNECT`, `DISCONNECT`, `EVENT`, and `CONNECT_ERROR` packets.
- JSON text events with zero, one, or multiple arguments.
- Server-driven heartbeat.
- Automatic reconnect after transport loss or heartbeat timeout.

The client rejects polling, transport upgrades, non-default namespaces, acknowledgements, binary events, binary
attachments, connection-state recovery, and replay. A recognized unsupported capability ends the active connection
with `.failed(.unsupportedCapability(_))`.

## Define Events

An incoming event conforms to `SocketEvent` and declares its wire name and decoded schema.

```swift
import Foundation
import RagnarSocketIO

enum LibraryItemUpdated: SocketEvent {
    struct Schema: Decodable, Sendable {
        let identifier: String
    }

    static let name = "library_item_updated"
}
```

The default implementation decodes exactly one JSON argument as `Schema`. An event with no arguments uses
`SocketEmptyBody`; it accepts either zero arguments or one JSON `null`.

```swift
enum LibraryScanStarted: SocketEvent {
    typealias Schema = SocketEmptyBody
    static let name = "library_scan_started"
}
```

An event that the client may send also conforms to `EmittableSocketEvent`. Its schema must be `Encodable` to use the
default one-argument encoder.

```swift
enum PlaybackProgressUpdated: EmittableSocketEvent {
    struct Schema: Codable, Sendable {
        let itemID: String
        let currentTime: Double
    }

    static let name = "playback_progress_updated"
}
```

Override `decode(arguments:using:)` or `encode(_:using:)` when a server event has multiple arguments. Each argument is
a `SocketIOArgument` containing one JSON value. Preserve argument order when decoding or encoding these events.

## Create a Client

```swift
let client = SocketIOClient()
```

The initializer accepts a `WebSocketClient`, coder factories, a reconnect policy, and a namespace connection timeout.
`SocketEventDecoder` and `SocketEventEncoder` create a new Foundation coder for each decode or emission. Supply a
factory when event schemas require custom date, data, or key strategies.

The default initializer creates `URLSessionWebSocketClient`. A target that supplies another transport must also depend
on and import `RagnarWebSocket` to declare its `WebSocketClient` conformance.

```swift
let client = SocketIOClient(
    decoder: .init {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    },
    encoder: .init {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
)
```

## Configure an Endpoint

Use `.server` with an HTTP or HTTPS server URL. Resolution converts the scheme to WS or WSS, joins the Socket.IO path
onto the server path, preserves unrelated query items, applies headers, and sets `EIO=4&transport=websocket`.

```swift
let endpoint = SocketIOEndpoint.server(
    URL(string: "https://example.com/api")!,
    path: "/socket.io/",
    headers: ["Authorization": "Bearer token"]
)
```

Use `.request` when the caller already has a complete WS or WSS `URLRequest`. The request must contain exactly one
`EIO=4` query item and one `transport=websocket` query item.

```swift
let endpoint = SocketIOEndpoint.request(request)
```

Endpoint validation occurs before an active connection is replaced. An invalid endpoint does not close the current
connection.

## Observe Status and Connect

Subscribe to status before connecting when every transition is required.

```swift
let statuses = await client.statusUpdates()
let statusTask = Task {
    for await status in statuses {
        print(status)
    }
}

try await client.connect(to: endpoint)
```

`connect(to:)` validates the endpoint, changes the status to `.connecting`, and starts the connection task. It returns
without waiting for the handshake. `.connected` is emitted only after the server sends the Socket.IO `CONNECT` packet
for the default namespace.

Calling `connect(to:)` with the active endpoint while the client is connecting, connected, or reconnecting has no
effect. A different valid endpoint starts a new connection generation.

## Receive Events

Create a stream before or after connecting. Subscriptions remain registered across automatic reconnects and explicit
disconnects.

```swift
let updates = await client.events(for: LibraryItemUpdated.self)

do {
    for try await update in updates {
        print(update.identifier)
    }
} catch {
    // Handle schema failure, overflow, or invalidation.
}
```

Each call to `events(for:policy:)` creates an independent subscription. Event decoding occurs when the iterator requests
the next value. A decoding failure terminates only that subscription.

## Select a Stream Policy

The event type's `defaultStreamPolicy` applies when `events(for:)` does not receive an explicit policy. The default is
`.lossless`, which retains the oldest 64 pending events and terminates with `SocketIOError.bufferOverflow` if the buffer
fills.

Available policies are:

- `.lossless` or `try .lossless(capacity:)` for ordered events that require resynchronization after overflow.
- `.latest` or `try .latest(capacity:)` for state or telemetry where newer values replace pending older values.
- `.unbounded` when the consumer explicitly accepts an unbounded queue.
- `try SocketStreamPolicy(buffering:overflow:)` for a custom buffering and overflow combination.

Bounded capacities must be greater than zero.

## Emit Events

Emission requires `.connected` status and an `EmittableSocketEvent` contract.

```swift
try await client.emit(
    PlaybackProgressUpdated.self,
    .init(itemID: "item-id", currentTime: 42)
)
```

An emitted message is checked against the Engine.IO `maxPayload` value from the active handshake. Emission while not
connected throws `SocketIOError.notConnected`; an oversized message throws `SocketIOError.messageTooLarge`.

## Disconnect and Invalidate

```swift
await client.disconnect()
await client.invalidate()
```

`disconnect()` closes the current transport and publishes `.disconnected`. Event and status subscriptions remain open,
and a later `connect(to:)` may reuse the client.

`invalidate()` closes the transport, publishes `.invalidated`, finishes every subscription, and permanently rejects
future connections and emissions.

## Heartbeat and Reconnection

The client reads `pingInterval`, `pingTimeout`, and `maxPayload` from the Engine.IO `OPEN` packet. The heartbeat deadline
resets on `OPEN` and server `PING`. Each `PING` receives a `PONG` with the same payload.

Automatic reconnect applies after transport failure, Engine.IO close, heartbeat timeout, or send failure. It does not
apply after explicit disconnect, invalidation, server namespace disconnect, `CONNECT_ERROR`, namespace timeout, invalid
endpoint configuration, or an unsupported protocol capability.

`ReconnectPolicy` controls the initial delay, maximum delay, multiplier, symmetric jitter, and optional attempt limit.
Use `.disabled` when the application owns reconnection.

```swift
let policy = try ReconnectPolicy(
    initialDelay: .seconds(1),
    maximumDelay: .seconds(30),
    multiplier: 2,
    jitter: 0.2,
    maximumAttempts: 5
)
```

A successful namespace connection resets the reconnect attempt count.

## Application Authentication and Recovery

`RagnarSocketIO` manages transport and namespace state only. If the server requires an application authentication event,
send it after every `.connected` transition before treating application events as usable.

The client does not replay events missed during disconnection and does not recover application state after stream
overflow. Use the server's HTTP API or another application-specific mechanism to resynchronize.

## Reference Tests

The integration fixture uses Socket.IO server 4.7.4. Run it with Node 20 or 22 and npm:

```sh
Scripts/run-socketio-integration-tests.sh
```

The script installs the fixture with `npm ci` and runs `RagnarSocketIOIntegrationTests`.
