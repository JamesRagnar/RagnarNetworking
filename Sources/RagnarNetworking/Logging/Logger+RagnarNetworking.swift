//
//  Logger+RagnarNetworking.swift
//  RagnarNetworking
//

import OSLog

extension Logger {
    static let socket = Logger(subsystem: "RagnarNetworking", category: "Socket")
    static let network = Logger(subsystem: "RagnarNetworking", category: "Network")
    static let responseMap = Logger(subsystem: "RagnarNetworking", category: "ResponseMap")
    static let diagnostics = Logger(subsystem: "RagnarNetworking", category: "Diagnostics")
}

extension RagnarNetworkingLogging {
    /// Runs `log` only when logging is enabled.
    @inline(__always)
    func ifEnabled(_ log: () -> Void) {
        if enabled { log() }
    }
}

/// Runs `log` only in DEBUG builds, independent of runtime logging configuration.
@inline(__always)
func rnDiagnostic(_ log: () -> Void) {
    #if DEBUG
    log()
    #endif
}
