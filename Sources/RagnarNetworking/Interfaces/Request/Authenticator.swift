//
//  Authenticator.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-08-02.
//

import Foundation

/// Produces the header fields and query items that carry a credential.
///
/// An Interface declares an `AuthenticationScheme`; `ServerConfiguration.authenticators` maps
/// that scheme to the authenticator that applies it. Authenticators are values, so one may
/// carry its own state - a header name, a signing key, a clock.
///
/// An authenticator returns what to apply rather than mutating the request, so
/// `URLRequestBuilder` sees the names before they land and rejects three cases the
/// authenticator would otherwise have to catch itself:
///
/// - a name the request already carries, as `RequestError.credentialCollision`
/// - a query item outside `redactedQueryItemNames`, as `.undeclaredQueryItemName`
/// - an authenticator that returns nothing anywhere, as `.authenticatorAppliedNothing`
///
/// A credential is therefore a header field or a query item and nothing else. A cookie is the
/// `Cookie` header, a password grant is a `RequestBody`, and a client certificate is
/// `URLSession` configuration.
///
/// Both requirements default to empty. Implement the one the scheme uses.
public protocol Authenticator: Sendable {

    /// Query items carrying the credential, applied before the URL is formed.
    ///
    /// - Parameters:
    ///   - credential: Never `nil`. A scheme with no credential fails with
    ///     `RequestError.missingCredential` before this is called.
    ///   - components: The base URL, path, and the endpoint's own query items, already applied.
    ///     A scheme that signs the URL reads them here.
    /// - Returns: Items to append. Every name must appear in `redactedQueryItemNames`.
    func queryItems(
        for credential: String,
        on components: URLComponents
    ) throws(RequestError) -> [URLQueryItem]

    /// Header fields carrying the credential, applied after the method, headers, and body.
    ///
    /// - Parameters:
    ///   - credential: Never `nil`. See `queryItems(for:on:)`.
    ///   - request: The request awaiting only authentication. A scheme that signs the request
    ///     reads the method, headers, and body here.
    /// - Returns: Fields to set, keyed by name.
    func headers(
        for credential: String,
        on request: URLRequest
    ) throws(RequestError) -> [String: String]

    /// Every query item name `queryItems(for:on:)` may return.
    ///
    /// `ServerConfiguration` unions these across its authenticators, and `HTTPResponseSnapshot`
    /// strips them from the URL it captures, so a URL-carried credential does not reach a
    /// logged error. Returning an undeclared name fails request construction.
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

    /// A token preceding the credential, separated by a space.
    public let prefix: String?

    /// Creates a header authenticator.
    /// - Parameters:
    ///   - name: The header field to write.
    ///   - prefix: A token preceding the credential, such as `Bearer` or `Basic`. `nil` writes
    ///     the credential alone.
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

/// Carries the credential in a query item, for a URL handed to something that cannot carry a
/// header, such as an image loader or `AVPlayer`.
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
