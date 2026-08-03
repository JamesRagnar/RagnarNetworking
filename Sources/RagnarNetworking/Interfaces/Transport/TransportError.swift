//
//  TransportError.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-08-02.
//

import Foundation

/// A failure moving bytes, before any response could be interpreted.
///
/// `Transport.data(for:)` is untyped `throws`, so `RequestPipeline` classifies whatever it
/// throws into one of these cases rather than letting a raw `URLError` escape:
///
/// ```swift
/// do {
///     let user = try await client.send(GetUser.self, .init(id: 1))
/// } catch let failure as TransportError {
///     show(failure.isOffline ? "You are offline." : failure.errorDescription)
/// } catch let error as ResponseError {
///     show(error.errorDescription)
/// } catch {
///     report(error)
/// }
/// ```
///
/// Cancellation is not among these cases. It stays `CancellationError` whether the package
/// raised it or `URLSession` reported `URLError.cancelled`, so `catch is CancellationError`
/// is the single check for it.
public enum TransportError: LocalizedError, Sendable {

    /// The device has no usable network path to the server.
    ///
    /// Covers `notConnectedToInternet`, `networkConnectionLost`, `dataNotAllowed`, and
    /// `internationalRoamingOff`.
    case offline(URLError)

    /// The request exceeded the transport's timeout.
    case timedOut(URLError)

    /// A `URLError` that is neither an offline condition nor a timeout, such as
    /// `cannotFindHost` or `secureConnectionFailed`.
    case url(URLError)

    /// A failure from a custom `Transport` that was not a `URLError`, carried unchanged.
    case other(any Error)

    /// The underlying `URLError`, or `nil` for a custom transport's own error type.
    public var urlError: URLError? {
        switch self {
        case .offline(let error), .timedOut(let error), .url(let error):
            return error

        case .other:
            return nil
        }
    }

    /// Whether the failure was a lack of network connectivity.
    public var isOffline: Bool {
        if case .offline = self {
            return true
        }
        return false
    }

    /// Whether the failure was a timeout.
    public var isTimeout: Bool {
        if case .timedOut = self {
            return true
        }
        return false
    }

    /// Classifies an error thrown by `Transport.data(for:)`.
    ///
    /// - Important: Cancellation is not classified here. `RequestPipeline.send` lifts it out
    ///   first, so a cancelled call throws `CancellationError` rather than a `TransportError`.
    static func classifying(_ error: any Error) -> TransportError {
        guard let urlError = error as? URLError else {
            return .other(error)
        }

        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .dataNotAllowed,
             .internationalRoamingOff:
            return .offline(urlError)

        case .timedOut:
            return .timedOut(urlError)

        default:
            return .url(urlError)
        }
    }

    public var errorDescription: String? {
        switch self {
        case .offline:
            return "The Internet connection appears to be offline."

        case .timedOut:
            return "The request timed out."

        case .url(let error):
            return error.localizedDescription

        case .other(let error):
            return error.localizedDescription
        }
    }

}
