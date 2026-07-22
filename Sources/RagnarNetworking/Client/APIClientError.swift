//
//  APIClientError.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-07-21.
//

import Foundation

/// Errors that describe an `APIClient` lifecycle failure.
///
/// These are distinct from request-construction (`RequestError`), transport, and
/// decoding (`ResponseError`) failures so callers can react to client lifecycle
/// state without conflating it with a specific authentication or network outcome.
public enum APIClientError: LocalizedError, Sendable {

    /// The client has been permanently invalidated and can no longer send requests.
    ///
    /// A client enters this state after `invalidate()` is called. It never becomes
    /// valid again - create a new client for a new connection generation.
    case invalidated

    public var errorDescription: String? {
        switch self {
        case .invalidated:
            return "The API client has been invalidated and can no longer send requests."
        }
    }

}
