# RagnarNetworking Documentation

This directory documents the public surface of `RagnarNetworking`.

## Package Structure

- `APIClient` - authenticated request execution with challenge refresh, retry, and terminal invalidation
- `SocketClient` - actor-based socket transport abstraction for higher-level consumers
- `SocketIOClient` - typed Socket.IO transport built on `URLSessionWebSocketTask`
- `SocketIOURL` - Socket.IO WebSocket URL builder from HTTP(S) server URLs
- `Transport` - single-requirement abstraction for executing a `URLRequest`; decorate it for middleware
- `RequestPipeline` - composes `RequestBuilder`, `Transport`, and `ResponseHandler` into one request
- `ServerConfiguration` - base URL, body coding, and default headers; `RequestContext` pairs one with a per-request token
- `Interfaces/` - request/response modeling, response mapping, and request construction

## Guides

- [APIClient](api_client.md)
- [SocketIOClient](socket_io_client.md)
- [RequestPipeline and Transport](request_pipeline.md)
- [Server Configuration](server_configuration.md)
- [Interfaces Overview](Interfaces/README.md)
- [Authentication](Interfaces/authentication.md)
- [Error Handling](error_handling.md)
- [Concurrency](concurrency.md)
