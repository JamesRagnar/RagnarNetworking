//
//  SocketError.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-10.
//

import Foundation

/// Errors that can occur during socket operations.
///
/// Provides detailed error information including the event name, raw data, and underlying
/// errors to aid debugging. Use the helper properties `eventName`, `isRetryable`, and
/// `debugDescription` for error handling and logging.
public enum SocketError: LocalizedError {

    /// Attempted to send an event while not connected to the server
    case notConnected

    /// Connection to the server failed
    case connectionFailed(underlying: Error)

    /// Failed to decode event data received from the server
    case eventDecodingFailed(event: String, data: Any, underlying: Error)

    /// Failed to emit an event to the server
    case emitFailed(event: String, underlying: Error)

    /// Socket configuration is invalid or could not be loaded
    case configurationFailed(underlying: Error)

    /// Server did not acknowledge an event within the timeout period
    case acknowledgmentTimeout(event: String)

    /// Failed to decode acknowledgment data from the server
    case acknowledgmentDecodingFailed(event: String, data: Any, underlying: Error)

    /// Socket disconnected unexpectedly
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

    /// The socket event name associated with this error, if applicable
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

    /// Whether the operation could be retried after this error
    ///
    /// Returns `true` for connection-related errors that might succeed on retry,
    /// `false` for errors that are unlikely to succeed without intervention.
    public var isRetryable: Bool {
        switch self {
        case .notConnected, .connectionFailed, .unexpectedDisconnection:
            return true
        case .eventDecodingFailed, .emitFailed, .configurationFailed,
             .acknowledgmentTimeout, .acknowledgmentDecodingFailed:
            return false
        }
    }

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
