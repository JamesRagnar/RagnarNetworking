# RagnarNetworking Documentation

This directory documents the package's three independent products.

## Package Structure

- `RagnarNetworking` - typed HTTP interfaces and authenticated request execution
- `RagnarWebSocket` - one-message-at-a-time WebSocket transport over `URLSessionWebSocketTask`
- `RagnarSocketIO` - typed Engine.IO 4 and Socket.IO protocol 5 subset over `RagnarWebSocket`
- `Transport` - single-requirement abstraction for executing a `URLRequest`; decorate it for middleware
- `RequestPipeline` - composes `RequestBuilder`, `Transport`, and `ResponseHandler` into one request
- `ServerConfiguration` - base URL, body coding, and default headers; `RequestContext` pairs one with a per-request token
- `Interfaces/` - request/response modeling, response contracts, and request construction

## Guides

- [APIClient](api_client.md)
- [WebSocket Transport](WebSocket.md)
- [Socket.IO Client](SocketIO.md)
- [RequestPipeline and Transport](request_pipeline.md)
- [Server Configuration](server_configuration.md)
- [Interfaces Overview](Interfaces/README.md)
- [Authentication](Interfaces/authentication.md)
- [Error Handling](error_handling.md)
- [Concurrency](concurrency.md)
