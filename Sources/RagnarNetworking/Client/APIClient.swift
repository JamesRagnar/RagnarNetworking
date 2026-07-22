import Foundation

/// App-agnostic actor that owns auth state and handles 401 retry.
///
/// Unauthenticated requests (`.none` auth) never invoke the token closure.
/// Concurrent 401s coalesce into a single refresh - only one `refresh` call fires
/// regardless of how many requests fail simultaneously.
///
/// A client can be permanently invalidated via `invalidate()`. Invalidation is a
/// terminal, one-way boundary: it rejects new `send` calls, cancels any coalesced
/// refresh, and cancels tracked in-flight transport work. A client never becomes
/// valid again - create a new client for a new connection generation.
public actor APIClient {

    private let baseURL: URL
    private let session: any DataTaskProvider
    private let token: @Sendable () async throws -> String?
    private let refresh: @Sendable () async throws -> Void
    private var ongoingRefresh: Task<Void, Error>?

    /// Whether `invalidate()` has been called. Once `true`, it never returns to `false`.
    private var isInvalidated = false

    /// Cancellation handles for tracked in-flight transport tasks, keyed by request identity.
    ///
    /// Type-erased to `() -> Void` because each transport `Task` is generic over its
    /// `Interface.Response` and cannot be stored in a homogeneous collection directly.
    private var inFlightCancellers: [UUID: @Sendable () -> Void] = [:]

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
    ///
    /// - Throws: `APIClientError.invalidated` if the client has been invalidated. The
    ///   check is applied before token resolution, before and after transport, before
    ///   refresh, and before retry.
    public func send<T: Interface>(
        _ type: T.Type,
        _ params: T.Parameters
    ) async throws -> T.Response {
        try checkValid()

        switch params.authentication {
        case .none:
            return try await execute(type, params, token: nil)

        case .bearer, .url:
            let currentToken = try await token()
            do {
                return try await execute(type, params, token: currentToken)
            } catch let err as ResponseError where err.statusCode == 401 {
                try checkValid()
                do {
                    try await coalesceRefresh()
                } catch {
                    // A refresh cancelled by `invalidate()` surfaces as the terminal
                    // invalidation error rather than a raw cancellation.
                    try checkValid()
                    throw error
                }
                try checkValid()
                let freshToken = try await token()
                return try await execute(type, params, token: freshToken)
            }
        }
    }

    /// Permanently invalidates the client.
    ///
    /// After this call:
    /// - New `send` calls fail with `APIClientError.invalidated`.
    /// - Any coalesced refresh owned by the client is cancelled.
    /// - Tracked in-flight transport tasks are cancelled. Cancellation reaches the
    ///   underlying transport when the configured `DataTaskProvider` honors task
    ///   cancellation (as `URLSession` does); otherwise the in-flight result is
    ///   suppressed at the post-transport checkpoint.
    ///
    /// Invalidation is terminal and idempotent - a client never becomes valid again.
    public func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true

        ongoingRefresh?.cancel()

        for cancel in inFlightCancellers.values {
            cancel()
        }
        inFlightCancellers.removeAll()
    }

    // MARK: - Private

    /// Throws `APIClientError.invalidated` if the client has been invalidated.
    private func checkValid() throws {
        if isInvalidated {
            throw APIClientError.invalidated
        }
    }

    private func execute<T: Interface>(
        _ type: T.Type,
        _ params: T.Parameters,
        token: String?
    ) async throws -> T.Response {
        try checkValid()

        let config = ServerConfiguration(
            url: baseURL,
            authToken: token
        )

        // Run transport inside a tracked child task so `invalidate()` can cancel it
        // from another task. The cancellation handler also forwards cancellation of
        // the caller's own task to the child.
        let task = Task {
            try await session.dataTask(type, params, config)
        }
        let id = UUID()
        inFlightCancellers[id] = { task.cancel() }
        defer { inFlightCancellers[id] = nil }

        do {
            let response = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try checkValid()
            return response
        } catch {
            // Transport cancelled by `invalidate()` surfaces as the terminal
            // invalidation error rather than a raw cancellation. Caller-initiated
            // cancellation (without invalidation) still propagates unchanged.
            try checkValid()
            throw error
        }
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
