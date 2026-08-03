# RagnarSocketIO

`RagnarSocketIO` provides a deliberately bounded Socket.IO client built on the separate `RagnarWebSocket` product. It is
not a complete replacement for every feature in the JavaScript Socket.IO client.

## Supported Protocol

The tested baseline is Socket.IO server 4.7.4 with:

- Engine.IO protocol 4.
- Socket.IO protocol revision 5.
- Direct WebSocket transport only.
- The default `/` namespace only.
- JSON text events with zero, one, or multiple arguments.
- Engine.IO `OPEN`, `CLOSE`, `PING`, `PONG`, and `MESSAGE` packets.
- Socket.IO `CONNECT`, `DISCONNECT`, `EVENT`, and `CONNECT_ERROR` packets.
- Server-driven heartbeat and automatic reconnect after transport loss or heartbeat timeout.

The reference suite verifies the default and custom Socket.IO paths, heartbeat survival, JSON event shapes, typed
emission, transport reconnect, persistent subscriptions, server namespace disconnect, and acknowledgement rejection.

## Client

```swift
import RagnarSocketIO

enum ItemUpdated: SocketEvent {
    struct Schema: Decodable, Sendable {
        let identifier: String
    }

    static let name = "item_updated"
}

let client = SocketIOClient()
let updates = await client.events(for: ItemUpdated.self)
try await client.connect(to: .server(URL(string: "https://example.com")!))

for try await update in updates {
    print(update.identifier)
}
```

`connect(to:)` validates an endpoint before replacing a current generation. A server endpoint converts `http` and
`https` to `ws` and `wss`, joins the Socket.IO path, preserves unrelated query items, and sets `EIO=4` and
`transport=websocket`.

Connection success is observed through `statusUpdates()`. `.connected` is published only after the server's Socket.IO
`CONNECT` packet, not after the WebSocket starts or Engine.IO sends `OPEN`.

## Typed Events

`SocketEvent` defines an incoming event name, `Decodable & Sendable` schema, stream policy, and argument decoder.
`EmittableSocketEvent` adds an argument encoder. This prevents an incoming-only contract from being emitted by mistake.

The default contract decodes exactly one JSON argument. `SocketEmptyBody` accepts zero arguments or one JSON `null`.
Events with multiple arguments override `decode(arguments:using:)`; emittable multi-argument events also override
`encode(_:using:)`.

`SocketEventDecoder` and `SocketEventEncoder` are Sendable factories. Each iteration or emission creates a fresh
Foundation coder, so custom date and key strategies do not require sharing mutable coders across tasks.

## Stream Policy

Each `events(for:)` call creates one raw argument buffer and returns `SocketEventStream<Event>`. JSON decoding runs in
the consumer task when its iterator requests the next element. There is no second typed buffer.

Available policies include:

- `.lossless`: retain the oldest 64 events and terminate on overflow.
- `try .lossless(capacity:)`: choose another bounded lossless capacity.
- `.latest`: retain the newest event and continue after dropping older values.
- `try .latest(capacity:)`: choose another newest-value capacity.
- `.unbounded`: explicit unbounded buffering.

Cancellation, schema failure, overflow termination, and client invalidation remove the affected subscription. A schema
failure in one subscription does not terminate other subscriptions to the same event name.

## Lifecycle and Reconnect

One `SocketIOClient` actor owns one transport generation, receive loop, heartbeat watchdog, reconnect schedule, event
subscription registry, and status registry.

Automatic reconnect applies to:

- WebSocket or transport failure.
- Server Engine.IO transport close.
- Heartbeat timeout.
- Send failure on an active generation.

Automatic reconnect does not apply to:

- Explicit disconnect or invalidation.
- Server Socket.IO `DISCONNECT`.
- Socket.IO `CONNECT_ERROR`.
- Namespace connection timeout.
- Invalid endpoints.
- Recognized unsupported protocol capabilities.

`ReconnectPolicy` controls the initial and maximum delay, multiplier, symmetric jitter, and optional attempt limit.
Successful namespace connection resets the attempt count. Event subscriptions survive reconnect; application
authentication does not run automatically.

## Unsupported Capabilities

The client recognizes and fails explicitly for:

- HTTP polling and transport upgrades.
- Non-default namespaces.
- Acknowledgement packets and acknowledgement-bearing events.
- Binary events, binary acknowledgements, and attachments.
- Connection-state recovery and replay.

Do not rely on the client to restore application state after a reconnect or lossless-stream overflow. A consumer package
must reauthenticate after each `.connected` transition when its server requires application authentication, and must use
its HTTP APIs to resynchronize state that could have changed while disconnected.

## Reference Tests

Run the pinned Socket.IO 4.7.4 reference suite with:

```sh
Scripts/run-socketio-integration-tests.sh
```

The script requires Node 20 or 22 and npm. It installs the fixture with `npm ci` and runs only
`RagnarSocketIOIntegrationTests`. The Node fixture is test infrastructure and is not a production package dependency.

## Migration from RagnarNetworking

The legacy combined client was removed from the `RagnarNetworking` module. Add the `RagnarSocketIO` library product to
the consuming target and import it directly. No compatibility aliases or umbrella re-exports are provided.

Before:

```swift
import RagnarNetworking

let client: any SocketClient = try SocketIOClient(endpoint: .server(serverURL))
let updates = await client.events(for: LibraryItemUpdated.self)
await client.connect()
```

After:

```swift
import Foundation
import RagnarSocketIO

let client: any SocketClient = SocketIOClient(
    decoder: .init { JSONDecoder() },
    encoder: .init { JSONEncoder() },
    reconnectPolicy: .default
)

let updates = await client.events(for: LibraryItemUpdated.self)
try await client.connect(to: .server(serverURL))
```

Migration changes include:

- Endpoint configuration moves to `SocketIOEndpoint` and is supplied to `connect(to:)`.
- Incoming contracts conform to `SocketEvent`; client-emitted contracts also conform to `EmittableSocketEvent`.
- Each subscription is a throwing `SocketEventStream<Event>` with an explicit bounded or unbounded policy.
- `.connected` means the server's Socket.IO `CONNECT` packet was received for the default namespace.
- Reconnect restores transport and namespace state, but does not restore application authentication or missed events.
- Lossless stream overflow terminates that subscription, so the application must resynchronize through another API.

The new client intentionally excludes polling, transport upgrades, non-default namespaces, acknowledgements, binary
events, and connection-state recovery. Consumers requiring any excluded behavior must extend the bounded implementation
or select a complete Socket.IO client rather than depending on unspecified fallback behavior.

### Legacy Test Disposition

The removed combined-client tests are covered by the replacement suites according to responsibility:

- URL resolution and request validation move to `SocketIOEndpointTests`.
- Engine.IO and Socket.IO frame parsing move to `EngineIOCodecTests` and `SocketIOCodecTests`.
- Typed event decoding, emission, fanout, cancellation, and overflow move to the contract and stream suites.
- Connection state, heartbeat, reconnect, endpoint replacement, and invalidation move to the lifecycle suite.
- Real handshake, event, heartbeat, and reconnect behavior move to the pinned reference-server suite.

Tests coupled to the combined module, permissive malformed-frame handling, non-throwing event streams, and its exact
logging output are intentionally obsolete. Those behaviors conflict with the independent targets and explicit failure
semantics of the replacement.
