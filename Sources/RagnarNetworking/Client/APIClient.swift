import Foundation

/// App-agnostic actor that owns auth state and handles 401 retry.
///
/// Unauthenticated requests (`.none` auth) never invoke the token closure.
/// 401s coalesce into a single refresh per token generation - only one `refresh` call
/// fires for requests that failed using the same token, whether those failures arrive
/// simultaneously or are staggered over time.
///
/// A client can be permanently invalidated via `invalidate()`. Invalidation is a
/// terminal, one-way boundary: it rejects new `send` calls, cancels any coalesced
/// refresh, and cancels tracked in-flight transport work. A client never becomes
/// valid again - create a new client for a new connection generation.
public actor APIClient {

    private let configuration: ServerConfiguration
    private let pipeline: RequestPipeline
    private let token: @Sendable () async throws -> String?
    private let refresh: @Sendable () async throws -> Void
    private var ongoingRefresh: Task<Void, Error>?

    /// Bumped each time a refresh completes successfully. Lets a request that read its
    /// token before an unrelated refresh completed skip a redundant second refresh.
    private var refreshGeneration: UInt64 = 0

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
    ///   - configuration: Everything about the server - URL, body coding, default headers,
    ///     request builder, default response handler. Stable for the client's lifetime -
    ///     recreate the client if it changes. Credentials are not part of it; the client pairs
    ///     it with the current token per request.
    ///   - transport: The underlying transport. Defaults to `URLSession.shared`.
    ///   - token: Called before each authenticated request. Evaluated lazily to always return the post-refresh value.
    ///   - refresh: Called on 401. Must update whatever state `token` reads from.
    public init(
        configuration: ServerConfiguration,
        transport: any Transport = URLSession.shared,
        token: @escaping @Sendable () async throws -> String?,
        refresh: @escaping @Sendable () async throws -> Void
    ) {
        self.configuration = configuration
        self.pipeline = RequestPipeline(transport: transport)
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
    ///   - configuration: Everything about the server - URL, body coding, default headers,
    ///     request builder, default response handler. Stable for the client's lifetime -
    ///     recreate the client if it changes.
    ///   - transport: The underlying transport. Defaults to `URLSession.shared`.
    public init(
        configuration: ServerConfiguration,
        transport: any Transport = URLSession.shared
    ) {
        self.configuration = configuration
        self.pipeline = RequestPipeline(transport: transport)
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
            let generation = refreshGeneration
            let currentToken = try await token()
            do {
                return try await execute(type, params, token: currentToken)
            } catch let err as ResponseError where err.statusCode == 401 {
                try checkValid()
                // If a refresh has already completed since this request read its token,
                // another request's 401 already refreshed for us - retry directly with
                // the now-current token rather than triggering a second refresh.
                if refreshGeneration == generation {
                    // Run the refresh in its own task so this request's own cancellation
                    // can stop *waiting* for it without cancelling the refresh itself -
                    // other requests may be relying on the same refresh completing.
                    let refreshTask = Task { [self] in try await coalesceRefresh() }
                    do {
                        try await CancellableTaskWait.value(of: refreshTask)
                    } catch {
                        // A refresh cancelled by `invalidate()` surfaces as the terminal
                        // invalidation error rather than a raw cancellation. Caller-initiated
                        // cancellation surfaces as `CancellationError` here without affecting
                        // the refresh, which keeps running for any other waiters.
                        try checkValid()
                        throw error
                    }
                }
                try checkValid()
                try Task.checkCancellation()
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
    ///   underlying transport when the configured `Transport` honors task
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

        let context = RequestContext(
            configuration: configuration,
            authToken: token
        )

        // Run transport inside a tracked child task so `invalidate()` can cancel it
        // from another task. The cancellation handler also forwards cancellation of
        // the caller's own task to the child.
        let task = Task {
            try await pipeline.send(type, params, context: context)
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
            refreshGeneration &+= 1
        } catch {
            ongoingRefresh = nil
            throw error
        }
    }
}

/// Awaits a `Task<Void, Error>`'s value, resolving promptly with `CancellationError`
/// if the calling task is cancelled first - without cancelling the awaited task itself.
///
/// Used so a request that stops waiting on a token refresh does not cancel that
/// refresh for any other requests still relying on it to complete.
private actor CancellableTaskWait {

    private var continuation: CheckedContinuation<Void, Error>?
    private var isResolved = false

    static func value(of task: Task<Void, Error>) async throws {
        try await CancellableTaskWait().wait(for: task)
    }

    private func wait(for task: Task<Void, Error>) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                register(continuation, watching: task)
            }
        } onCancel: {
            Task { await self.resolve(.failure(CancellationError())) }
        }
    }

    private func register(
        _ continuation: CheckedContinuation<Void, Error>,
        watching task: Task<Void, Error>
    ) {
        guard !isResolved else {
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        Task {
            do {
                try await task.value
                resolve(.success(()))
            } catch {
                resolve(.failure(error))
            }
        }
    }

    private func resolve(_ result: Result<Void, Error>) {
        guard !isResolved else { return }
        isResolved = true
        switch result {
        case .success:
            continuation?.resume()

        case .failure(let error):
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}
