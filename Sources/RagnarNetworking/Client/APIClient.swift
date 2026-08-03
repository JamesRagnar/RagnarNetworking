import Foundation

/// App-agnostic actor that coordinates one credential lifecycle and handles challenge retry.
///
/// A request declaring no `AuthenticationScheme` never reads the credential source, and one whose
/// `InterfaceRequest.allowsRefreshOnChallenge` is `false` is never retried.
/// `ServerConfiguration.challengePolicy` decides which failures are challenges, so no status
/// code is hardcoded here.
///
/// Challenges coalesce into a single refresh per credential generation: one refresh call fires
/// for all requests that failed in the same generation, whether those failures arrive
/// simultaneously or are staggered over time.
///
/// A client can be permanently invalidated via `invalidate()`. Invalidation is a
/// terminal, one-way boundary: it rejects new `send` calls, cancels any coalesced
/// refresh, and cancels tracked in-flight transport work. A client never becomes
/// valid again - create a new client for a new connection generation.
public actor APIClient {

    private let configuration: ServerConfiguration
    private let pipeline: RequestPipeline
    private let credentialSource: CredentialSource?
    private var ongoingRefresh: Task<Void, Error>?

    /// Bumped each time a refresh completes successfully. Lets a request that read its
    /// credential before an unrelated refresh completed skip a redundant second refresh.
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
    ///   - configuration: The server contract: URL, body coding, default headers, request
    ///     builder, default response handler. Held for the client's lifetime; recreate the
    ///     client if it changes.
    ///   - transport: The underlying transport. Defaults to `URLSession.shared`.
    ///   - credentialSource: The one read-only or refreshing credential lifecycle coordinated by
    ///     this client. Evaluated lazily for each authenticated request.
    public init(
        configuration: ServerConfiguration,
        transport: any Transport = URLSession.shared,
        credentialSource: CredentialSource
    ) {
        self.configuration = configuration
        self.pipeline = RequestPipeline(transport: transport)
        self.credentialSource = credentialSource
    }

    /// Creates an `APIClient` for requests that declare no `AuthenticationScheme`.
    ///
    /// No credential is available, so a request declaring a registered scheme fails with
    /// `RequestError.missingCredential`. An unregistered scheme still fails with
    /// `RequestError.unregisteredScheme`.
    ///
    /// - Parameters:
    ///   - configuration: The server contract: URL, body coding, default headers, request
    ///     builder, default response handler. Held for the client's lifetime.
    ///   - transport: The underlying transport. Defaults to `URLSession.shared`.
    public init(
        configuration: ServerConfiguration,
        transport: any Transport = URLSession.shared
    ) {
        self.configuration = configuration
        self.pipeline = RequestPipeline(transport: transport)
        self.credentialSource = nil
    }

    /// Sends a typed request.
    ///
    /// A request whose `InterfaceRequest.allowsRefreshOnChallenge` is `true` is retried once after
    /// a challenge when the client has a refreshing source. The source refreshes, then its
    /// credential is re-read for the retry. A read-only source instead surfaces the challenge's
    /// original `ResponseError` without another read or request.
    /// `ServerConfiguration.challengePolicy` decides what counts as a challenge and receives the
    /// Interface's response statuses, so an endpoint that models the challenge status code
    /// surfaces its own error instead.
    ///
    /// - Throws: `APIClientError.invalidated` if the client has been invalidated. The
    ///   check is applied before credential resolution, before and after transport, before
    ///   refresh, and before retry.
    public func send<T: Interface>(
        _ type: T.Type,
        _ params: T.Request
    ) async throws -> T.Response {
        try checkValid()

        guard params.allowsRefreshOnChallenge else {
            return try await execute(type, params, credential: try await credential(for: params))
        }

        let generation = refreshGeneration
        let currentCredential = try await credential(for: params)
        do {
            return try await execute(type, params, credential: currentCredential)
        } catch let err as ResponseError where configuration.challengePolicy.isChallenge(
            err,
            T.responses.statuses
        ) {
            try checkValid()
            guard let credentialSource else {
                throw APIClientError.noCredentialSource
            }
            guard credentialSource.refresh != nil else {
                throw err
            }
            // If a refresh has already completed since this request read its token,
            // another request's challenge already refreshed for us - retry directly with
                // the now-current credential rather than triggering a second refresh.
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
            return try await execute(type, params, credential: try await credential(for: params))
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

    /// Resolves the credential for a request, or `nil` when it declares no scheme.
    ///
    /// Keyed on `authentication` rather than `allowsRefreshOnChallenge`, so an endpoint that opts
    /// out of refresh still sends its credential.
    private func credential(for params: some InterfaceRequest) async throws -> String? {
        guard params.authentication != nil else { return nil }
        return try await credentialSource?.read()
    }

    /// Throws `APIClientError.invalidated` if the client has been invalidated.
    private func checkValid() throws {
        if isInvalidated {
            throw APIClientError.invalidated
        }
    }

    private func execute<T: Interface>(
        _ type: T.Type,
        _ params: T.Request,
        credential: String?
    ) async throws -> T.Response {
        try checkValid()

        let context = RequestContext(
            configuration: configuration,
            credential: credential
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
        guard let refresh = credentialSource?.refresh else {
            throw APIClientError.noCredentialSource
        }
        let task = Task<Void, Error> { try await refresh() }
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
/// Used so a request that stops waiting on a credential refresh does not cancel that
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
