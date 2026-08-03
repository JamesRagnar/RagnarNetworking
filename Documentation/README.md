# RagnarNetworking Documentation

This directory documents the package's three independent products.

## Products

- `RagnarNetworking` provides typed HTTP interfaces and authenticated request execution.
- `RagnarWebSocket` provides one-message-at-a-time WebSocket transport over `URLSessionWebSocketTask`.
- `RagnarSocketIO` provides the supported Engine.IO 4 and Socket.IO protocol 5 subset over `RagnarWebSocket`.

`RagnarSocketIO` depends on `RagnarWebSocket`. `RagnarNetworking` does not depend on either socket product.

## RagnarNetworking

- [APIClient](api_client.md)
- [RequestPipeline and Transport](request_pipeline.md)
- [Server Configuration](server_configuration.md)
- [Interfaces Overview](Interfaces/README.md)
- [Authentication](Interfaces/authentication.md)
- [Error Handling](error_handling.md)
- [Concurrency](concurrency.md)

## RagnarWebSocket

- [WebSocket Transport](WebSocket.md)

## RagnarSocketIO

- [Socket.IO Client](SocketIO.md)
