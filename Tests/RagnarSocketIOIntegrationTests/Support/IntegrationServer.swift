import Foundation
import Testing

actor IntegrationServer {
    let endpoint: URL
    private let process: Process
    private let standardOutput: Pipe
    private let standardError: Pipe

    private init(
        endpoint: URL,
        process: Process,
        standardOutput: Pipe,
        standardError: Pipe
    ) {
        self.endpoint = endpoint
        self.process = process
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    static func start(
        path: String = "/socket.io/",
        pingInterval: Int = 250,
        pingTimeout: Int = 250
    ) async throws -> IntegrationServer {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", fixtureDirectory.appendingPathComponent("server.mjs").path]
        process.currentDirectoryURL = fixtureDirectory
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.environment = ProcessInfo.processInfo.environment.merging([
            "SOCKET_IO_PATH": path,
            "PING_INTERVAL": String(pingInterval),
            "PING_TIMEOUT": String(pingTimeout)
        ]) { _, fixtureValue in fixtureValue }

        try process.run()

        do {
            let line = try await firstLine(from: standardOutput.fileHandleForReading, timeout: .seconds(5))
            let readiness = try parseReadiness(line)
            let endpoint = try #require(URL(string: "http://127.0.0.1:\(readiness.port)"))
            return IntegrationServer(
                endpoint: endpoint,
                process: process,
                standardOutput: standardOutput,
                standardError: standardError
            )
        } catch {
            process.terminate()
            throw error
        }
    }

    func stop() async {
        guard process.isRunning else { return }
        process.terminate()
        for _ in 0..<500 where process.isRunning {
            try? await Task.sleep(for: .milliseconds(10))
        }
        if process.isRunning {
            process.interrupt()
        }
    }

    func diagnostics() -> String {
        guard !process.isRunning else { return "Reference server is still running." }
        let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errors = standardError.fileHandleForReading.readDataToEndOfFile()
        return [output, errors]
            .compactMap { String(data: $0, encoding: .utf8) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private struct Readiness: Decodable {
        let port: Int
        let path: String
    }

    private static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("IntegrationTests/SocketIOReferenceServer")
    }()

    private static func parseReadiness(_ line: String) throws -> Readiness {
        let prefix = "RAGNAR_SOCKET_IO_READY "
        guard line.hasPrefix(prefix) else {
            throw IntegrationServerError.invalidReadiness(line)
        }
        return try JSONDecoder().decode(Readiness.self, from: Data(line.dropFirst(prefix.count).utf8))
    }

    private static func firstLine(
        from fileHandle: FileHandle,
        timeout: Duration
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                var data = Data()
                for try await byte in fileHandle.bytes {
                    if byte == 10 { break }
                    data.append(byte)
                }
                guard let line = String(data: data, encoding: .utf8) else {
                    throw IntegrationServerError.invalidUTF8
                }
                return line
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw IntegrationServerError.startupTimeout
            }

            guard let first = try await group.next() else {
                throw IntegrationServerError.startupTimeout
            }
            group.cancelAll()
            return first
        }
    }
}

enum IntegrationServerError: Error {
    case startupTimeout
    case invalidReadiness(String)
    case invalidUTF8
}
