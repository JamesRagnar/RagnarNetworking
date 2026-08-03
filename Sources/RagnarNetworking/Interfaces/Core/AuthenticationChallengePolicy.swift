//
//  AuthenticationChallengePolicy.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-08-02.
//

import Foundation

/// Decides whether a failed response is the server rejecting a stale credential.
///
/// `APIClient` consults this before refreshing and retrying. Which status code or header
/// signals staleness varies by server, so the policy lives on `ServerConfiguration`.
///
/// ```swift
/// let policy = AuthenticationChallengePolicy { error, _ in
///     error.statusCode == 419 || error.header("WWW-Authenticate") != nil
/// }
/// ```
///
/// Only requests whose `InterfaceRequest.refreshesOnChallenge` is `true` reach the policy.
public struct AuthenticationChallengePolicy: Sendable {

    /// Whether the error is a credential challenge.
    ///
    /// Receives the Interface's `responseCases` so a policy can ask what the endpoint declared.
    /// Inferring that from the thrown `ResponseError` case instead would tie the policy to
    /// `DefaultResponseHandler`'s error mapping, which a custom `ResponseHandler` may change.
    public let isChallenge: @Sendable (ResponseError, ResponseMap) -> Bool

    /// Creates a challenge policy.
    /// - Parameter isChallenge: Whether the error is the server rejecting a stale credential.
    public init(isChallenge: @escaping @Sendable (ResponseError, ResponseMap) -> Bool) {
        self.isChallenge = isChallenge
    }

    /// Challenges on 401, unless the Interface declared an exact `.code(401, ...)` case.
    ///
    /// The default. An endpoint that models 401 surfaces its own error rather than refreshing,
    /// which also stops a throwing `refresh` from replacing that error at the catch site.
    ///
    /// A range match does not count: `.clientError(...)` is a catch-all for status codes the
    /// endpoint did not consider, 401 included, so it keeps refresh.
    public static let unmodelled401 = AuthenticationChallengePolicy { error, responseCases in
        error.statusCode == 401 && responseCases.exactOutcome(401) == nil
    }

    /// Challenges on any 401, whatever the Interface declared.
    ///
    /// Use this when an endpoint both models 401 and relies on refresh firing.
    public static let any401 = AuthenticationChallengePolicy { error, _ in
        error.statusCode == 401
    }

}
