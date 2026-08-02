//
//  AuthenticationChallengePolicy.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-08-02.
//

import Foundation

/// Decides whether a failed response is the server saying the credential is stale.
///
/// `APIClient` consults this before refreshing and retrying. Which status code or header
/// signals staleness is a property of the server, so the policy lives on
/// `ServerConfiguration`. A server that answers with 419, or with a `WWW-Authenticate` header
/// alongside some other status, needs a policy rather than a fork of `APIClient`.
///
/// ```swift
/// let policy = AuthenticationChallengePolicy { error, _ in
///     error.statusCode == 419 || error.header("WWW-Authenticate") != nil
/// }
/// ```
///
/// Only requests whose `RequestParameters.isAuthenticated` is `true` reach the policy at all.
/// An unauthenticated request is never refreshed or retried regardless of what it returns.
public struct AuthenticationChallengePolicy: Sendable {

    /// Whether the error is a credential challenge.
    ///
    /// The Interface's `responseCases` is passed alongside the error so a policy can ask what
    /// the endpoint declared, rather than inferring it from which `ResponseError` case was
    /// thrown. Inferring would tie the policy to `DefaultResponseHandler`'s error mapping,
    /// which a custom `ResponseHandler` is free to change.
    public let isChallenge: @Sendable (ResponseError, ResponseMap) -> Bool

    /// Creates a challenge policy.
    /// - Parameter isChallenge: Whether the error is the server rejecting a stale credential.
    public init(isChallenge: @escaping @Sendable (ResponseError, ResponseMap) -> Bool) {
        self.isChallenge = isChallenge
    }

    /// Challenges on 401, unless the Interface declared an exact `.code(401, ...)` case.
    ///
    /// The default. An endpoint that deliberately models 401 - a login route returning typed
    /// validation errors, say - surfaces its own error to the caller instead of triggering a
    /// refresh it did not ask for. That matters beyond a wasted round trip: a refresh that
    /// throws replaces the modelled error at the catch site, so an endpoint's ordinary 401
    /// could otherwise sign a user out.
    ///
    /// A *range* match does not count as modelling it. `.clientError(.decodeError(...))` is a
    /// catch-all for everything the endpoint did not think about, 401 included, so it keeps
    /// refresh. Only `.code(401, ...)` is a statement about 401 specifically.
    public static let unmodelled401 = AuthenticationChallengePolicy { error, responseCases in
        error.statusCode == 401 && responseCases.exactOutcome(401) == nil
    }

    /// Challenges on any 401, whatever the Interface declared.
    ///
    /// Restores the behavior from before challenge policies existed. Use this if an endpoint
    /// both models 401 and relies on refresh firing.
    public static let any401 = AuthenticationChallengePolicy { error, _ in
        error.statusCode == 401
    }

}
