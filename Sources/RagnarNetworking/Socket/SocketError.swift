//
//  SocketError.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-10.
//

import Foundation

/// Errors that can occur during socket operations
public enum SocketError: LocalizedError {

    /// Socket is not connected
    case notConnected

    /// Connection failed with underlying error
    case connectionFailed(underlying: Error)

    /// Failed to decode event data
    case eventDecodingFailed(event: String, data: Any, underlying: Error)

    /// Failed to emit event
    case emitFailed(event: String, underlying: Error)

    /// Configuration is invalid or failed to load
    case configurationFailed(underlying: Error)

    /// Acknowledgment timeout
    case acknowledgmentTimeout(event: String)

    /// Acknowledgment received invalid data
    case acknowledgmentDecodingFailed(event: String, data: Any, underlying: Error)

    /// Socket was disconnected unexpectedly
    case unexpectedDisconnection(reason: String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Socket is not connected"
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .eventDecodingFailed(let event, _, let error):
            return "Failed to decode event '\(event)': \(error.localizedDescription)"
        case .emitFailed(let event, let error):
            return "Failed to emit event '\(event)': \(error.localizedDescription)"
        case .configurationFailed(let error):
            return "Configuration failed: \(error.localizedDescription)"
        case .acknowledgmentTimeout(let event):
            return "Acknowledgment timeout for event '\(event)'"
        case .acknowledgmentDecodingFailed(let event, _, let error):
            return "Failed to decode acknowledgment for event '\(event)': \(error.localizedDescription)"
        case .unexpectedDisconnection(let reason):
            return "Unexpected disconnection: \(reason)"
        }
    }

    /// The event name associated with this error, if applicable
    public var eventName: String? {
        switch self {
        case .eventDecodingFailed(let event, _, _),
             .emitFailed(let event, _),
             .acknowledgmentTimeout(let event),
             .acknowledgmentDecodingFailed(let event, _, _):
            return event
        case .notConnected, .connectionFailed, .configurationFailed, .unexpectedDisconnection:
            return nil
        }
    }

    /// Whether this error is potentially retryable
    public var isRetryable: Bool {
        switch self {
        case .notConnected, .connectionFailed, .unexpectedDisconnection:
            return true
        case .eventDecodingFailed, .emitFailed, .configurationFailed,
             .acknowledgmentTimeout, .acknowledgmentDecodingFailed:
            return false
        }
    }

    /// Debug description with detailed context
    public var debugDescription: String {
        switch self {
        case .notConnected:
            return "SocketError.notConnected: Socket is not in connected state"
        case .connectionFailed(let error):
            return "SocketError.connectionFailed: \(error)"
        case .eventDecodingFailed(let event, let data, let error):
            return """
            SocketError.eventDecodingFailed:
              Event: \(event)
              Data: \(data)
              Error: \(error)
            """
        case .emitFailed(let event, let error):
            return "SocketError.emitFailed: Event '\(event)' - \(error)"
        case .configurationFailed(let error):
            return "SocketError.configurationFailed: \(error)"
        case .acknowledgmentTimeout(let event):
            return "SocketError.acknowledgmentTimeout: Event '\(event)' did not receive ack in time"
        case .acknowledgmentDecodingFailed(let event, let data, let error):
            return """
            SocketError.acknowledgmentDecodingFailed:
              Event: \(event)
              Data: \(data)
              Error: \(error)
            """
        case .unexpectedDisconnection(let reason):
            return "SocketError.unexpectedDisconnection: \(reason)"
        }
    }
}
