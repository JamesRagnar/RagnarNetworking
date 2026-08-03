import Foundation

/// Supplies the one credential lifecycle coordinated by an `APIClient`.
///
/// A source is either read-only or refreshing. Both modes resolve the current credential lazily
/// once for each authenticated request attempt. A refreshing source additionally gives the
/// client one lifecycle transition to coalesce when requests are challenged.
///
/// One source may support multiple `AuthenticationScheme` values on the same client. Schemes
/// describe how the credential is applied, not which credential lifecycle owns it.
public struct CredentialSource: Sendable {

    let read: @Sendable () async throws -> String?
    let refresh: (@Sendable () async throws -> Void)?

    private init(
        read: @escaping @Sendable () async throws -> String?,
        refresh: (@Sendable () async throws -> Void)?
    ) {
        self.read = read
        self.refresh = refresh
    }

    /// Creates a source that can resolve credentials but cannot recover from a challenge.
    ///
    /// A recognized authentication challenge is surfaced as its original `ResponseError`.
    /// The source is not read again and the request is not retried.
    public static func readOnly(
        _ read: @escaping @Sendable () async throws -> String?
    ) -> CredentialSource {
        CredentialSource(read: read, refresh: nil)
    }

    /// Creates a source that can resolve and refresh one credential lifecycle.
    ///
    /// `refresh` must finish only after the state read by `read` reflects the completed
    /// lifecycle transition. The credential string may remain unchanged when the transition
    /// renews server-side validity without rotating the value.
    public static func refreshing(
        read: @escaping @Sendable () async throws -> String?,
        refresh: @escaping @Sendable () async throws -> Void
    ) -> CredentialSource {
        CredentialSource(read: read, refresh: refresh)
    }
}
