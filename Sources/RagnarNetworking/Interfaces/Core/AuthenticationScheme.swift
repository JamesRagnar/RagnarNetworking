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
/// A request that carries no credential declares `nil` rather than a scheme, so there is no
/// scheme meaning "no scheme" to register an authenticator against by mistake.
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
///     authenticators: [.apiKey: .header("X-API-Key")]
/// )
/// ```
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

    /// The credential is applied as an `Authorization` header.
    ///
    /// `HeaderAuthenticator.bearer` is registered for this scheme by default, writing
    /// `Authorization: Bearer <credential>`.
    public static let bearer = AuthenticationScheme("bearer")

    /// The credential is applied to the URL.
    ///
    /// `QueryItemAuthenticator.token` is registered for this scheme by default, writing
    /// `?token=<credential>`.
    ///
    /// Use this for a URL handed to something that cannot carry a header, such as an image
    /// loader or `AVPlayer`. The name reflects placement rather than a wire format, which is the
    /// authenticator's business; a server using `?access_token=` registers
    /// `QueryItemAuthenticator(name: "access_token")` for this same scheme.
    public static let url = AuthenticationScheme("url")

}

extension AuthenticationScheme: CustomStringConvertible {

    public var description: String { rawValue }

}
