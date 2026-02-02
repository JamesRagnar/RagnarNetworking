//
//  SocketServiceConfiguration.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2025-02-08.
//

public struct SocketServiceConfiguration: Sendable {
    public var options: [SocketServiceOption]
    public var eventBufferSize: Int

    public init(
        _ options: [SocketServiceOption] = [],
        eventBufferSize: Int = 100
    ) {
        self.options = options
        self.eventBufferSize = eventBufferSize
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

}

public enum SocketServiceVersion: Int, Sendable {
    case two = 2
    case three = 3
}
