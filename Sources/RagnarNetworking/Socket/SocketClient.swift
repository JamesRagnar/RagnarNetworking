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
    func emit(_ event: String, _ item: SocketData)
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

    func emit(_ event: String, _ item: SocketData) {
        client.emit(event, item)
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
