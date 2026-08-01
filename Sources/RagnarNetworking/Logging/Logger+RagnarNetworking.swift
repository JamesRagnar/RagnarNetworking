//
//  Logger+RagnarNetworking.swift
//  RagnarNetworking
//

import OSLog

extension Logger {
    static let socket = Logger(subsystem: "RagnarNetworking", category: "Socket")
    static let diagnostics = Logger(subsystem: "RagnarNetworking", category: "Diagnostics")
}
