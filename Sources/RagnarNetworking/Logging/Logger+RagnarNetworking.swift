//
//  Logger+RagnarNetworking.swift
//  RagnarNetworking
//

import OSLog

let loggingSubsystem = "com.ragnar.networking"

extension Logger {

    static let interfaces = Logger(subsystem: loggingSubsystem, category: "Interfaces")

}
