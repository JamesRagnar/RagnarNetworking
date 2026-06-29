import Foundation

/// App-agnostic actor that owns auth state and handles 401 retry.
///
/// Unauthenticated requests (`.none` auth) never invoke the token closure.
/// Concurrent 401s coalesce into a single refresh - only one `refresh` call fires
/// regardless of how many requests fail simultaneously.
public actor APIClient {

    private let baseURL: URL
    private let session: any DataTaskProvider
    private let token: @Sendable () async throws -> String?
    private let refresh: @Sendable () async throws -> Void
    private var ongoingRefresh: Task<Void, Error>?

    /// Creates an `APIClient`.
    ///
    /// - Parameters:
    ///   - baseURL: Base URL for all requests. Stable for the client's lifetime - recreate if the server URL changes.
    ///   - session: The underlying transport. Defaults to `URLSession.shared`.
    ///   - token: Called before each authenticated request. Evaluated lazily to always return the post-refresh value.
    ///   - refresh: Called on 401. Must update whatever state `token` reads from.
    public init(
        baseURL: URL,
        session: any DataTaskProvider = URLSession.shared,
        token: @escaping @Sendable () async throws -> String?,
        refresh: @escaping @Sendable () async throws -> Void
    ) {
        self.baseURL = baseURL
        self.session = session
        self.token = token
        self.refresh = refresh
    }

    /// Creates an `APIClient` for unauthenticated request flows.
    ///
    /// Use this initializer when the client will only send requests whose
    /// `AuthenticationType` is `.none`.
    ///
    /// Requests using `.bearer` or `.url` authentication through this initializer
    /// will fail with authentication-related errors.
    ///
    /// - Parameters:
    ///   - baseURL: Base URL for all requests. Stable for the client's lifetime - recreate if the server URL changes.
    ///   - session: The underlying transport. Defaults to `URLSession.shared`.
    public init(
        baseURL: URL,
        session: any DataTaskProvider = URLSession.shared
    ) {
        self.baseURL = baseURL
        self.session = session
        self.token = { nil }
        self.refresh = { throw RequestError.authentication }
    }

    /// Sends a typed request.
    ///
    /// Authenticated requests (`.bearer` or `.url`) are retried once after a 401 -
    /// the `refresh` closure fires first, then `token` is re-evaluated for the retry.
    public func send<T: Interface>(
        _ type: T.Type,
        _ params: T.Parameters
    ) async throws -> T.Response {
        switch params.authentication {
        case .none:
            return try await execute(type, params, token: nil)

        case .bearer, .url:
            let currentToken = try await token()
            do {
                return try await execute(type, params, token: currentToken)
            } catch let err as ResponseError where err.statusCode == 401 {
                try await coalesceRefresh()
                let freshToken = try await token()
                return try await execute(type, params, token: freshToken)
            }
        }
    }

    // MARK: - Private

    private func execute<T: Interface>(
        _ type: T.Type,
        _ params: T.Parameters,
        token: String?
    ) async throws -> T.Response {
        let config = ServerConfiguration(
            url: baseURL,
            authToken: token
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
