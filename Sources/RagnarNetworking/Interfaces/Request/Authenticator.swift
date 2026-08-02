//
//  Authenticator.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-08-02.
//

import Foundation

/// Produces the header fields and query items that carry a credential.
///
/// An Interface declares which `AuthenticationScheme` it uses;
/// `ServerConfiguration.authenticators` maps that scheme to the authenticator that gives it
/// meaning. Changing how a server carries credentials is a configuration change rather than a
/// `RequestBuilder` fork.
///
/// Authenticators are values, so one may carry its own state - a header name, a signing key,
/// a clock - without reaching for globals.
///
/// ## Why this returns values rather than mutating the request
///
/// An authenticator describes what it wants applied; `URLRequestBuilder` applies it. That is
/// what lets the builder see the names being written *before* they land, which is where three
/// guarantees come from that an authenticator cannot be trusted to reproduce individually:
///
/// - **A collision fails the request.** If a returned name is already present - a caller's own
///   `Authorization` header, a stale `?token=` baked into the base URL - construction throws
///   `RequestError.credentialCollision` rather than silently picking a winner.
/// - **Redaction cannot drift.** Every name returned from `queryItems(for:on:)` must be listed
///   in `redactedQueryItemNames`, or construction throws
///   `RequestError.undeclaredQueryItemName`. A credential cannot reach a captured error
///   snapshot because someone renamed a parameter and forgot the other declaration.
/// - **A silent no-op fails the request.** An authenticator that contributes neither a header
///   nor a query item throws `RequestError.authenticatorAppliedNothing`, so a conformance that
///   implements the wrong half cannot produce an unauthenticated request that looks fine.
///
/// The cost is that an authenticator cannot reach other parts of the request. In HTTP a
/// credential is a header or a query item: cookies are the `Cookie` header, a password grant is
/// a request *body* rather than an authenticator's business, and client certificates are
/// `URLSession` configuration. The restriction is what buys the guarantees above.
///
/// ## Both requirements have empty defaults
///
/// Implement the one your scheme uses. Returning nothing visibly adds nothing, and an
/// authenticator that adds nothing at all fails loudly at request construction, so an empty
/// default cannot become a silently unauthenticated request.
public protocol Authenticator: Sendable {

    /// Query items carrying the credential, applied before the URL is formed.
    ///
    /// - Parameters:
    ///   - credential: The credential for this request. Never `nil`; a scheme with a registered
    ///     authenticator and no credential fails with `RequestError.missingCredential` before
    ///     this is called.
    ///   - components: The components built so far, with the base URL, path, and the endpoint's
    ///     own query items already applied. A scheme that signs the URL reads them here.
    /// - Returns: Items to append. Every name must appear in `redactedQueryItemNames`.
    func queryItems(
        for credential: String,
        on components: URLComponents
    ) throws(RequestError) -> [URLQueryItem]

    /// Header fields carrying the credential, applied after the method, headers, and body.
    ///
    /// - Parameters:
    ///   - credential: The credential for this request. Never `nil`; see `queryItems(for:on:)`.
    ///   - request: The request built so far, awaiting only authentication. A scheme that signs
    ///     the request - HMAC over the body, for instance - reads everything it signs here.
    /// - Returns: Fields to set, keyed by name.
    func headers(
        for credential: String,
        on request: URLRequest
    ) throws(RequestError) -> [String: String]

    /// Every query item name `queryItems(for:on:)` may return.
    ///
    /// `ServerConfiguration` unions these across its registered authenticators, and
    /// `HTTPResponseSnapshot` strips them from the URL it captures, so a credential carried in
    /// a URL does not survive into an error a consumer logs or attaches to a bug report.
    ///
    /// Returning a name that is not listed here fails request construction, so this cannot fall
    /// out of step with what the authenticator actually writes.
    var redactedQueryItemNames: Set<String> { get }

}

public extension Authenticator {

    func queryItems(
        for credential: String,
        on components: URLComponents
    ) throws(RequestError) -> [URLQueryItem] {
        []
    }

    func headers(
        for credential: String,
        on request: URLRequest
    ) throws(RequestError) -> [String: String] {
        [:]
    }

    var redactedQueryItemNames: Set<String> { [] }

}

// MARK: - Header

/// Carries the credential in a header field.
///
/// ```swift
/// .header("Authorization", prefix: "Bearer")   // Authorization: Bearer <credential>
/// .header("X-API-Key")                         // X-API-Key: <credential>
/// ```
public struct HeaderAuthenticator: Authenticator {

    /// The header field written.
    public let name: String

    /// A token preceding the credential, separated by a space. `nil` writes the credential
    /// alone.
    public let prefix: String?

    /// Creates a header authenticator.
    /// - Parameters:
    ///   - name: The header field to write.
    ///   - prefix: A token preceding the credential, such as `Bearer` or `Basic`. `nil`, the
    ///     default, writes the credential alone.
    public init(name: String, prefix: String? = nil) {
        self.name = name
        self.prefix = prefix
    }

    public func headers(
        for credential: String,
        on request: URLRequest
    ) throws(RequestError) -> [String: String] {
        guard let prefix else { return [name: credential] }
        return [name: "\(prefix) \(credential)"]
    }

}

public extension Authenticator where Self == HeaderAuthenticator {

    /// `Authorization: Bearer <credential>`. Registered for `.bearer` by default.
    static var bearer: HeaderAuthenticator {
        HeaderAuthenticator(name: "Authorization", prefix: "Bearer")
    }

    /// `Authorization: Basic <credential>`, over a credential the caller has already encoded.
    static var basic: HeaderAuthenticator {
        HeaderAuthenticator(name: "Authorization", prefix: "Basic")
    }

    /// A header carrying the credential alone, with no scheme token.
    static func header(_ name: String, prefix: String? = nil) -> HeaderAuthenticator {
        HeaderAuthenticator(name: name, prefix: prefix)
    }

}

// MARK: - Query Item

/// Carries the credential in a query item.
///
/// Use this for a URL handed to something that cannot carry a header, such as an image loader
/// or `AVPlayer`.
///
/// ```swift
/// .token                          // ?token=<credential>
/// .queryItem("access_token")      // ?access_token=<credential>
/// ```
public struct QueryItemAuthenticator: Authenticator {

    /// The query item name written.
    public let name: String

    /// Creates a query item authenticator.
    /// - Parameter name: The query item name to write.
    public init(name: String) {
        self.name = name
    }

    public var redactedQueryItemNames: Set<String> { [name] }

    public func queryItems(
        for credential: String,
        on components: URLComponents
    ) throws(RequestError) -> [URLQueryItem] {
        [URLQueryItem(name: name, value: credential)]
    }

}

public extension Authenticator where Self == QueryItemAuthenticator {

    /// `?token=<credential>`. Registered for `.url` by default.
    static var token: QueryItemAuthenticator {
        QueryItemAuthenticator(name: "token")
    }

    /// A query item carrying the credential under the given name.
    static func queryItem(_ name: String) -> QueryItemAuthenticator {
        QueryItemAuthenticator(name: name)
    }

}
