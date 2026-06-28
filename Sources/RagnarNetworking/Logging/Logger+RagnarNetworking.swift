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

/// Log via OSLog, guarded by `RagnarNetworkingLogging`.
@inline(__always)
func rnLog(
    _ logger: Logger,
    logging: RagnarNetworkingLogging,
    level: OSLogType = .debug,
    _ message: @autoclosure () -> String
) {
    guard logging.enabled else { return }
    let msg = message()
    logger.log(level: level, "\(msg, privacy: .public)")
}

/// Emit a debug-only developer diagnostic that is independent of runtime logging configuration.
@inline(__always)
func rnDiagnostic(_ message: @autoclosure () -> String) {
    #if DEBUG
    let msg = message()
    Logger.diagnostics.warning("\(msg, privacy: .public)")
    #endif
}
