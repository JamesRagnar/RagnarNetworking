//
//  AuthenticationScheme.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-08-02.
//

import Foundation

/// Names the authentication strategy an endpoint uses.
///
/// The scheme is a property of the endpoint; how it is applied is a property of the server. An
/// Interface declares `.bearer`, and `ServerConfiguration.authenticators` decides what
/// `.bearer` means for that server. A request carrying no credential declares `nil`.
///
/// The type is open rather than a closed enum, so a project can name its own schemes:
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
    /// Two schemes with the same name are equal, so a project defining its own should pick a
    /// name unlikely to collide with another module's.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// The credential is applied as an `Authorization` header.
    ///
    /// `HeaderAuthenticator.bearer` is registered for this scheme by default, writing
    /// `Authorization: Bearer <credential>`.
    public static let bearer = AuthenticationScheme("bearer")

    /// The credential is applied to the URL, for a URL handed to something that cannot carry a
    /// header.
    ///
    /// `QueryItemAuthenticator.token` is registered for this scheme by default, writing
    /// `?token=<credential>`. The name reflects placement rather than a wire format: a server
    /// using `?access_token=` registers `.queryItem("access_token")` for this same scheme.
    public static let url = AuthenticationScheme("url")

}

extension AuthenticationScheme: CustomStringConvertible {

    public var description: String { rawValue }

}
