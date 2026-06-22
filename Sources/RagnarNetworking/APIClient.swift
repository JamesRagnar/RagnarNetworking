import Foundation

/// App-agnostic actor that owns auth state and handles 401 retry using Swift Concurrency primitives.
///
/// Takes two closures and nothing else — no knowledge of any app-specific auth type.
/// Concurrent 401s coalesce into a single refresh via Task value reuse.
public actor APIClient {

    public struct Credentials: Sendable {
        public let baseURL: URL
        public let accessToken: String?

        public init(baseURL: URL, accessToken: String? = nil) {
            self.baseURL = baseURL
            self.accessToken = accessToken
        }
    }

    private let session: any DataTaskProvider
    private let credentials: @Sendable () async throws -> Credentials
    private let refresh: @Sendable () async throws -> Void
    private var ongoingRefresh: Task<Void, Error>?

    public init(
        session: any DataTaskProvider = URLSession.shared,
        credentials: @escaping @Sendable () async throws -> Credentials,
        refresh: @escaping @Sendable () async throws -> Void
    ) {
        self.session = session
        self.credentials = credentials
        self.refresh = refresh
    }

    public func send<T: Interface>(
        _ type: T.Type,
        _ params: T.Parameters
    ) async throws -> T.Response {
        switch params.authentication {
        case .none:
            let creds = try await credentials()
            return try await execute(type, params, creds: creds)

        case .bearer, .url:
            let creds = try await credentials()
            do {
                return try await execute(type, params, creds: creds)
            } catch let e as ResponseError where e.statusCode == 401 {
                try await coalesceRefresh()
                let fresh = try await credentials()
                return try await execute(type, params, creds: fresh)
            }
        }
    }

    // MARK: - Private

    private func execute<T: Interface>(
        _ type: T.Type,
        _ params: T.Parameters,
        creds: Credentials
    ) async throws -> T.Response {
        let config = ServerConfiguration(
            url: creds.baseURL,
            authToken: creds.accessToken
        )
        return try await session.dataTask(type, params, config)
    }

    private func coalesceRefresh() async throws {
        if let task = ongoingRefresh {
            try await task.value
            return
        }
        let task = Task<Void, Error> { [self] in try await refresh() }
        ongoingRefresh = task
        do {
            try await task.value
            ongoingRefresh = nil
        } catch {
            ongoingRefresh = nil
            throw error
        }
    }
}
