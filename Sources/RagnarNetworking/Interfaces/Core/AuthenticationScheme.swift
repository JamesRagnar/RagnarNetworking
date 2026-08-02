//
//  AuthenticationScheme.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-08-02.
//

import Foundation

/// Names the authentication strategy an endpoint uses.
///
/// The scheme is a property of the endpoint; how that scheme is applied to a request is a
/// property of the server. An Interface declares `.bearer`, and
/// `ServerConfiguration.authenticators` decides what `.bearer` means for that server.
///
/// The type is open rather than a closed enum, so a project can name schemes the package does
/// not ship:
///
/// ```swift
/// extension AuthenticationScheme {
///     static let apiKey = AuthenticationScheme("apiKey")
/// }
///
/// let configuration = ServerConfiguration(
///     url: url,
///     authenticators: [.apiKey: APIKeyAuthenticator(header: "X-API-Key")]
/// )
/// ```
///
/// - Warning: In a context where the expected type is `AuthenticationScheme?`, the leading-dot
///   spelling `.none` resolves to `Optional.none` rather than to `AuthenticationScheme.none`.
///   No API in this package takes an optional scheme, so this only arises in code that
///   introduces one. Write `AuthenticationScheme.none` in full there.
public struct AuthenticationScheme: Hashable, Sendable {

    /// The scheme's name. Used as the key into `ServerConfiguration.authenticators`.
    public let rawValue: String

    /// Creates a scheme with the given name.
    ///
    /// Two schemes with the same name are the same scheme, so a project defining its own should
    /// pick a name unlikely to collide with another module's.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// The request carries no credential.
    ///
    /// Short-circuits before any authenticator lookup: no authenticator is consulted and no
    /// credential is required. Registering an authenticator under this scheme has no effect.
    ///
    /// A request whose credential arrives by some route the package does not model - a cookie
    /// jar, a custom `Transport`, a signing proxy - declares `.none` and overrides
    /// `RequestParameters.isAuthenticated` to `true` to keep challenge retry and coalesced
    /// refresh.
    public static let none = AuthenticationScheme("none")

    /// The credential is applied as an `Authorization` header.
    ///
    /// `BearerAuthenticator` is registered for this scheme by default, writing
    /// `Authorization: Bearer <credential>`.
    public static let bearer = AuthenticationScheme("bearer")

    /// The credential is applied to the URL.
    ///
    /// `QueryTokenAuthenticator` is registered for this scheme by default, writing
    /// `?token=<credential>`.
    ///
    /// Use this for a URL handed to something that cannot carry a header, such as an image
    /// loader or `AVPlayer`. The name reflects placement rather than a wire format, which is
    /// now the authenticator's business; a server using `?access_token=` registers
    /// `QueryTokenAuthenticator(name: "access_token")` for this same scheme.
    public static let url = AuthenticationScheme("url")

}
