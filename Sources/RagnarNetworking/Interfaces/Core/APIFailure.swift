//
//  APIFailure.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-08-02.
//

import Foundation

/// Everything a `send` can fail with, named by the layer that failed.
///
/// Both `APIClient.send` and `RequestPipeline.send` declare `throws(APIFailure)`, so the caught
/// error is an `APIFailure` and a caller can switch on it exhaustively, with no `default` and
/// no cast:
///
/// ```swift
/// do {
///     let user = try await client.send(GetUser.self, .init(id: 1))
///     show(user)
/// } catch {
///     switch error {
///     case .transport(let failure): show(failure.isOffline ? "Offline" : "Network error")
///     case .response(let error): show(error.errorDescription)
///     case .request, .credential, .noCredentialSource: assertionFailure("\(error)")
///     case .cancelled: break
///     case .invalidated: replaceClient()
///     }
/// }
/// ```
///
/// A `catch` clause matching one case still needs an unconditional `catch` after it: Swift
/// treats a `do` as exhaustive only when it ends in a catch-all, however many cases the
/// preceding clauses cover.
///
/// Which cases each entry point can produce:
/// - `RequestPipeline.send`: `.request`, `.transport`, `.response`, `.cancelled`.
/// - `APIClient.send`: all of the above, plus `.credential`, `.invalidated`, and
///   `.noCredentialSource`.
public enum APIFailure: LocalizedError, Sendable {

    /// The request could not be built, or a credential could not be applied to it.
    ///
    /// Includes the authentication cases `RequestError` models: a scheme with no registered
    /// authenticator, a missing credential, a collision with a header the request already
    /// carried. Failing to *obtain* a credential is `.credential` instead.
    case request(RequestError)

    /// The transport could not reach the server or complete the exchange.
    case transport(TransportError)

    /// A response arrived but could not be interpreted as the Interface's `Response`.
    case response(ResponseError)

    /// The client's `token` or `refresh` closure threw, carrying that error unchanged.
    ///
    /// Failing to *obtain* a credential. Failing to *apply* one is `.request`.
    case credential(any Error)

    /// The call was cancelled, either by cancelling the calling `Task` or by the transport
    /// reporting `URLError.cancelled`.
    case cancelled

    /// The client was invalidated via `invalidate()` and can no longer send requests.
    ///
    /// Terminal: a client never becomes valid again. Create a new one.
    case invalidated

    /// A request was challenged on a client created without credential closures.
    ///
    /// Reached only by a request that declares no scheme but overrides
    /// `RequestParameters.refreshesOnChallenge` to `true`; any declared scheme fails at
    /// construction with `.request(.missingCredential)` first.
    case noCredentialSource

    /// Maps an untyped error from an untyped boundary - `Transport.data(for:)`, a `Task` whose
    /// failure type is erased - onto a case.
    ///
    /// Passes an `APIFailure` through unchanged, lifts cancellation out of the transport
    /// classification so it lands on `.cancelled` from either source, and classifies the rest.
    static func classifying(_ error: any Error) -> APIFailure {
        if let failure = error as? APIFailure {
            return failure
        }

        if error is CancellationError {
            return .cancelled
        }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            return .cancelled
        }

        return .transport(TransportError.classifying(error))
    }

    /// Maps an error thrown by a consumer's `token` or `refresh` closure onto a case.
    ///
    /// Those closures are untyped `throws`, so cancellation escaping one has to be recognized
    /// rather than reported as a credential problem.
    static func credential(from error: any Error) -> APIFailure {
        if let failure = error as? APIFailure {
            return failure
        }

        if error is CancellationError {
            return .cancelled
        }

        return .credential(error)
    }

    public var errorDescription: String? {
        switch self {
        case .request(let error):
            return error.errorDescription

        case .transport(let error):
            return error.errorDescription

        case .response(let error):
            return error.errorDescription

        case .credential(let error):
            // Bridges through `NSError`, which consults `LocalizedError.errorDescription`
            // for a Swift error type that provides one.
            return error.localizedDescription

        case .cancelled:
            return "The request was cancelled."

        case .invalidated:
            return "The API client has been invalidated and can no longer send requests."

        case .noCredentialSource:
            return """
            An authenticated request was challenged, but this client was created without \
            token and refresh closures.
            """
        }
    }

}
