# RagnarNetworking Documentation

This directory documents the public surface of `RagnarNetworking`.

## Package Structure

- `APIClient` - authenticated request execution with 401 refresh and retry
- `SocketClient` - actor-based socket transport abstraction for higher-level consumers
- `SocketIOClient` - typed Socket.IO transport built on `URLSessionWebSocketTask`
- `SocketIOURL` - Socket.IO WebSocket URL builder from HTTP(S) server URLs
- `DataTaskProvider` - transport abstraction for interface-driven requests
- `ServerConfiguration` - base URL, auth token, and request encoding configuration
- `RagnarNetworkingLogging` - immutable runtime logging configuration
- `Interfaces/` - request/response modeling, response mapping, and request construction

## Guides

- [APIClient](api_client.md)
- [SocketIOClient](socket_io_client.md)
- [DataTaskProvider](data_task_provider.md)
- [Server Configuration](server_configuration.md)
- [Interfaces Overview](Interfaces/README.md)
