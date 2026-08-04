import OSLog

let loggingSubsystem = "com.ragnar.networking"

extension Logger {

    static let webSocket = Logger(subsystem: loggingSubsystem, category: "WebSocket")

}
