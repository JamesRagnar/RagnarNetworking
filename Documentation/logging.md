# Logging

Every product logs through OSLog. The package has no logging dependency and no logging switch of its own.

## Subsystem and Categories

| Product | Subsystem | Category |
| --- | --- | --- |
| `RagnarNetworking` | `com.ragnar.networking` | `Interfaces` |
| `RagnarWebSocket` | `com.ragnar.networking` | `WebSocket` |
| `RagnarSocketIO` | `com.ragnar.networking` | `SocketIO` |

One subsystem filter covers the whole package. A category filter narrows it to one product.

## Levels

- `.debug` carries per-connection activity: transport open and close, the Engine.IO handshake, heartbeat responses,
  reconnect attempts and their delays, retryable connection failures, and events dropped by a subscription or buffering
  policy.
- `.warning` carries developer diagnostics for declarations that cannot report misuse through a thrown error. A
  duplicate exact status code in a `ResponseContract` is the only case.
- `.error` carries terminal outcomes: a connection failure that ends the lifecycle, and a reconnect policy that reaches
  its attempt limit.

A failure thrown to the caller is not also logged.

## Verbosity

Verbosity is set outside the package, either on a running system or in an app's `Info.plist`.

```sh
log config --mode "level:debug" --subsystem com.ragnar.networking --category SocketIO
log stream --predicate 'subsystem == "com.ragnar.networking"' --level debug
```

```xml
<key>OSLogPreferences</key>
<dict>
    <key>com.ragnar.networking</key>
    <dict>
        <key>SocketIO</key>
        <dict>
            <key>Level</key>
            <dict>
                <key>Enable</key>
                <string>Debug</string>
            </dict>
        </dict>
    </dict>
</dict>
```

## Privacy

Values are redacted by default. Only package-owned constants are public: status codes, generation and attempt numbers,
close codes, handshake timing, maximum payload size, connection failure case labels, unsupported capability names, and
captured error type names.

Request URLs, event names, server rejection messages, protocol violation descriptions, and raw packet payloads stay
private.
