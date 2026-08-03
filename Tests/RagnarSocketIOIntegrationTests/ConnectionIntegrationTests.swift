import Foundation
import RagnarSocketIO
import Testing

@Suite(
    "Socket.IO Reference Connection",
    .enabled(if: socketIOIntegrationEnabled),
    .serialized
)
struct ConnectionIntegrationTests {
    @Test("Default path connects, survives heartbeats, and disconnects explicitly")
    func defaultPath() async throws {
        try await withIntegrationServer { server in
            let client = try makeIntegrationClient()
            try await client.connect(to: .server(server.endpoint))
            try await waitForStatus(.connected, from: client)

            try await Task.sleep(for: .seconds(1))
            try await waitForStatus(.connected, from: client)

            await client.disconnect()
            try await waitForStatus(.disconnected, from: client)
            try await Task.sleep(for: .milliseconds(250))
            try await waitForStatus(.disconnected, from: client)
            await client.invalidate()
        }
    }

    @Test("Custom path preserves unrelated query items")
    func customPath() async throws {
        try await withIntegrationServer(path: "/custom/socket.io/") { server in
            var components = try #require(URLComponents(url: server.endpoint, resolvingAgainstBaseURL: false))
            components.queryItems = [URLQueryItem(name: "fixture", value: "value")]
            let endpoint = try #require(components.url)
            let client = try makeIntegrationClient()

            try await client.connect(to: .server(endpoint, path: "/custom/socket.io/"))
            try await waitForStatus(.connected, from: client)
            await client.invalidate()
        }
    }
}
