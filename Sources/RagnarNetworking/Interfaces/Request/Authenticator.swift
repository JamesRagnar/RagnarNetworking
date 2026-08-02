//
//  Authenticator.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-08-02.
//

import Foundation
import OSLog

/// Applies a credential to a request on a server's behalf.
///
/// An Interface declares which `AuthenticationScheme` it uses;
/// `ServerConfiguration.authenticators` maps that scheme to the authenticator that gives it
/// meaning. Changing how a server carries credentials is a configuration change rather than a
/// `RequestBuilder` fork.
///
/// Authenticators are values, so one may carry its own state - a header name, a signing key,
/// a clock - without reaching for globals.
///
/// ## Two application points
///
/// A credential lands either in the URL, before it is formed, or on the request, after it is
/// fully built. The pipeline never holds a live `URLComponents` and `URLRequest` at the same
/// time, so both are separate requirements. **Implement the one your scheme uses and leave the
/// other empty.** Neither has a default implementation: an authenticator author should read
/// both signatures and pick deliberately rather than inherit a no-op without noticing there
/// was a choice.
///
/// `apply(_:to:request:)` runs after the method, headers, and body are all on the request, so a
/// scheme that signs the request - HMAC over the body, for instance - can see everything it
/// needs to sign.
///
/// ## Collision handling
///
/// Only an authenticator knows the header and query names it writes, so it owns what happens
/// when the caller already supplied one. The built-in authenticators follow the package's
/// established precedence, and a custom authenticator should document its own:
///
/// - **Headers: the caller wins.** `BearerAuthenticator` finds an existing `Authorization`,
///   logs a diagnostic, and leaves it alone.
/// - **Query items: the authenticator wins.** `QueryTokenAuthenticator` strips matching items
///   from the base URL and from the endpoint's own `queryItems`, logs a diagnostic for each,
///   then appends the credential.
///
/// The asymmetry is deliberate. A stale `?token=` baked into a base URL must not beat the live
/// credential, while a caller who explicitly writes an `Authorization` header is overriding on
/// purpose.
public protocol Authenticator: Sendable {

    /// Applies the credential to URL components, before the URL is formed.
    ///
    /// Leave this empty for a scheme that does not carry its credential in the URL.
    ///
    /// - Parameters:
    ///   - credential: The credential for this request. Never `nil`; a scheme with a registered
    ///     authenticator and no credential fails with `RequestError.authentication` before this
    ///     is called.
    ///   - components: The components built so far, with the path and the endpoint's own query
    ///     items already applied.
    func apply(_ credential: String, to components: inout URLComponents) throws(RequestError)

    /// Applies the credential to the request, after the method, headers, and body are applied.
    ///
    /// Leave this empty for a scheme that does not carry its credential on the request.
    ///
    /// - Parameters:
    ///   - credential: The credential for this request. Never `nil`; see the components variant.
    ///   - request: The fully built request, awaiting only authentication.
    func apply(_ credential: String, to request: inout URLRequest) throws(RequestError)

    /// Query item names this authenticator may write.
    ///
    /// `ServerConfiguration` unions these across its registered authenticators, and
    /// `HTTPResponseSnapshot` strips them from the URL it captures, so a credential carried in
    /// a URL does not survive into an error a consumer logs or attaches to a bug report.
    ///
    /// Defaults to empty, which is correct for any authenticator that does not touch the URL.
    var redactedQueryItemNames: Set<String> { get }

}

public extension Authenticator {

    var redactedQueryItemNames: Set<String> { [] }

}

// MARK: - Bearer

/// Writes `Authorization: Bearer <credential>`. Registered for `.bearer` by default.
///
/// A caller-supplied `Authorization` header wins: this authenticator logs a diagnostic and
/// leaves the caller's value in place.
public struct BearerAuthenticator: Authenticator {

    /// The header field written. Defaults to `Authorization`.
    public let headerName: String

    /// The scheme token preceding the credential. Defaults to `Bearer`.
    public let headerScheme: String

    /// Creates a bearer authenticator.
    /// - Parameters:
    ///   - headerName: The header field to write. Defaults to `Authorization`.
    ///   - headerScheme: The scheme token preceding the credential. Defaults to `Bearer`.
    ///     Pass `"Basic"` for basic auth over a pre-encoded credential, or `""` for a bare
    ///     header value.
    public init(
        headerName: String = "Authorization",
        headerScheme: String = "Bearer"
    ) {
        self.headerName = headerName
        self.headerScheme = headerScheme
    }

    public func apply(_ credential: String, to components: inout URLComponents) throws(RequestError) {}

    public func apply(_ credential: String, to request: inout URLRequest) throws(RequestError) {
        if request.value(forHTTPHeaderField: headerName) != nil {
            Logger.diagnostics.warning(
                """
                RagnarNetworking: a custom \(self.headerName, privacy: .public) header \
                overrides authentication for this request.
                """
            )
            return
        }

        let value = headerScheme.isEmpty ? credential : "\(headerScheme) \(credential)"
        request.setValue(value, forHTTPHeaderField: headerName)
    }

}

// MARK: - Query Token

/// Writes the credential as a query item. Registered for `.url` by default, under the name
/// `token`.
///
/// Use this for a URL handed to something that cannot carry a header. Existing query items with
/// the same name, whether from the configuration's base URL or the endpoint's own `queryItems`,
/// are stripped with a diagnostic so a stale value cannot beat the live credential.
public struct QueryTokenAuthenticator: Authenticator {

    /// The query item name written. Defaults to `token`.
    public let name: String

    /// Creates a query-token authenticator.
    /// - Parameter name: The query item name to write. Defaults to `token`. A server using
    ///   `?access_token=` passes `"access_token"`.
    public init(name: String = "token") {
        self.name = name
    }

    public var redactedQueryItemNames: Set<String> { [name] }

    public func apply(_ credential: String, to components: inout URLComponents) throws(RequestError) {
        var queryItems = components.queryItems ?? []

        let conflicts = queryItems.filter {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
        if !conflicts.isEmpty {
            Logger.diagnostics.warning(
                """
                RagnarNetworking: URL authentication overrides \(conflicts.count, privacy: .public) \
                existing '\(self.name, privacy: .public)' query item(s).
                """
            )
            queryItems.removeAll {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            }
        }

        queryItems.append(URLQueryItem(name: name, value: credential))
        components.queryItems = queryItems
    }

    public func apply(_ credential: String, to request: inout URLRequest) throws(RequestError) {}

}
