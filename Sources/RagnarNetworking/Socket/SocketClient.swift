//
//  SocketClient.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2025-02-08.
//

import Foundation
import SocketIO

protocol SocketClientProtocol: Actor {
    var sid: String? { get }
    func setEventHandler(_ handler: @Sendable @escaping (SocketEventSnapshot) -> Void)
    func setStatusHandler(_ handler: @Sendable @escaping (SocketService.SocketStatus) -> Void)
    func emit(_ event: String, _ payload: SocketPayloadValue) throws
    func connect()
    func disconnect()
}

actor SocketIOClientAdapter: SocketClientProtocol {
    private let manager: SocketManager
    private let client: SocketIOClient
    private var eventHandler: (@Sendable (SocketEventSnapshot) -> Void)?
    private var statusHandler: (@Sendable (SocketService.SocketStatus) -> Void)?
    private var callbacksConfigured = false

    init(url: URL, config: SocketServiceConfiguration) {
        manager = SocketManager(socketURL: url, config: config.socketIOConfiguration())
        client = manager.defaultSocket
    }

    var sid: String? {
        client.sid
    }

    func setEventHandler(_ handler: @Sendable @escaping (SocketEventSnapshot) -> Void) {
        configureCallbacksIfNeeded()
        eventHandler = handler
    }

    func setStatusHandler(_ handler: @Sendable @escaping (SocketService.SocketStatus) -> Void) {
        configureCallbacksIfNeeded()
        statusHandler = handler
    }

    func emit(_ event: String, _ payload: SocketPayloadValue) throws {
        let socketData = try SocketIOPayloadConverter.socketData(from: payload)
        client.emit(event, socketData)
    }

    func connect() {
        client.connect()
    }

    func disconnect() {
        manager.disconnect()
    }

    private func configureCallbacksIfNeeded() {
        guard !callbacksConfigured else { return }
        callbacksConfigured = true

        client.onAny { [weak self] event in
            guard let self = self else { return }
            let snapshot = SocketEventSnapshot(event: event.event, items: event.items ?? [])
            Task { await self.handleAnySnapshot(snapshot) }
        }

        client.on(clientEvent: .statusChange) { [weak self] (data, _) in
            guard let self = self else { return }
            guard
                let statusInt = data.last as? Int,
                let status = SocketService.SocketStatus(rawValue: statusInt)
            else {
                return
            }

            Task { await self.handleStatusChange(status) }
        }
    }

    private func handleAnySnapshot(_ snapshot: SocketEventSnapshot) {
        eventHandler?(snapshot)
    }

    private func handleStatusChange(_ status: SocketService.SocketStatus) {
        statusHandler?(status)
    }
}

private enum SocketIOPayloadConverter {
    static func socketData(from payload: SocketPayloadValue) throws -> SocketData {
        switch payload {
        case .string(let value):
            return value
        case .int(let value):
            return value
        case .double(let value):
            return value
        case .bool(let value):
            return value
        case .data(let value):
            return value
        case .array(let values):
            return try values.map { try socketData(from: $0) }
        case .dictionary(let values):
            var mapped: [String: SocketData] = [:]
            mapped.reserveCapacity(values.count)
            for (key, value) in values {
                mapped[key] = try socketData(from: value)
            }
            return mapped
        case .null:
            return NSNull()
        }
    }
}

private extension SocketServiceConfiguration {
    func socketIOConfiguration() -> SocketIOClientConfiguration {
        var config = SocketIOClientConfiguration()
        for option in options {
            config.insert(option.socketIOOption)
        }
        return config
    }
}

private extension SocketServiceOption {
    var socketIOOption: SocketIOClientOption {
        switch self {
        case .compress:
            return .compress
        case .connectParams(let params):
            return .connectParams(params)
        case .extraHeaders(let headers):
            return .extraHeaders(headers)
        case .forceNew(let value):
            return .forceNew(value)
        case .forcePolling(let value):
            return .forcePolling(value)
        case .forceWebsockets(let value):
            return .forceWebsockets(value)
        case .enableSOCKSProxy(let value):
            return .enableSOCKSProxy(value)
        case .log(let value):
            return .log(value)
        case .path(let value):
            return .path(value)
        case .reconnects(let value):
            return .reconnects(value)
        case .reconnectAttempts(let value):
            return .reconnectAttempts(value)
        case .reconnectWait(let value):
            return .reconnectWait(value)
        case .reconnectWaitMax(let value):
            return .reconnectWaitMax(value)
        case .randomizationFactor(let value):
            return .randomizationFactor(value)
        case .secure(let value):
            return .secure(value)
        case .selfSigned(let value):
            return .selfSigned(value)
        case .useCustomEngine(let value):
            return .useCustomEngine(value)
        case .version(let value):
            return .version(value.socketIOVersion)
        }
    }
}

private extension SocketServiceVersion {
    var socketIOVersion: SocketIOVersion {
        switch self {
        case .two:
            return .two
        case .three:
            return .three
        }
    }
}
