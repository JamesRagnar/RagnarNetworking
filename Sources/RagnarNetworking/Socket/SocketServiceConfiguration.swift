//
//  SocketServiceConfiguration.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2025-02-08.
//

import SocketIO

public struct SocketServiceConfiguration: Sendable {
    public var options: [SocketServiceOption]

    public init(_ options: [SocketServiceOption] = []) {
        self.options = options
    }

    func socketIOConfiguration() -> SocketIOClientConfiguration {
        var config = SocketIOClientConfiguration()
        for option in options {
            config.insert(option.socketIOOption)
        }
        return config
    }
}

public enum SocketServiceOption: Sendable {
    case compress
    case connectParams([String: String])
    case extraHeaders([String: String])
    case forceNew(Bool)
    case forcePolling(Bool)
    case forceWebsockets(Bool)
    case enableSOCKSProxy(Bool)
    case log(Bool)
    case path(String)
    case reconnects(Bool)
    case reconnectAttempts(Int)
    case reconnectWait(Int)
    case reconnectWaitMax(Int)
    case randomizationFactor(Double)
    case secure(Bool)
    case selfSigned(Bool)
    case useCustomEngine(Bool)
    case version(SocketServiceVersion)

    fileprivate var socketIOOption: SocketIOClientOption {
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

public enum SocketServiceVersion: Int, Sendable {
    case two = 2
    case three = 3

    fileprivate var socketIOVersion: SocketIOVersion {
        switch self {
        case .two:
            return .two
        case .three:
            return .three
        }
    }
}
