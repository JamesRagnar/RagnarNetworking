//
//  SocketPayload.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2025-02-08.
//

import Foundation

public protocol SocketPayload: Sendable {
    func socketPayload() throws -> SocketPayloadValue
}

public enum SocketPayloadValue: Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case data(Data)
    case array([SocketPayloadValue])
    case dictionary([String: SocketPayloadValue])
    case null

    static func from(_ value: Any) throws -> SocketPayloadValue {
        if value is NSNull {
            return .null
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            let doubleValue = number.doubleValue
            let intValue = number.intValue
            if Double(intValue) == doubleValue {
                return .int(intValue)
            }
            return .double(doubleValue)
        }
        if let boolValue = value as? Bool {
            return .bool(boolValue)
        }
        if let intValue = value as? Int {
            return .int(intValue)
        }
        if let doubleValue = value as? Double {
            return .double(doubleValue)
        }
        if let stringValue = value as? String {
            return .string(stringValue)
        }
        if let dataValue = value as? Data {
            return .data(dataValue)
        }
        if let arrayValue = value as? [Any] {
            return .array(try arrayValue.map { try SocketPayloadValue.from($0) })
        }
        if let dictValue = value as? [String: Any] {
            var mapped: [String: SocketPayloadValue] = [:]
            mapped.reserveCapacity(dictValue.count)
            for (key, value) in dictValue {
                mapped[key] = try SocketPayloadValue.from(value)
            }
            return .dictionary(mapped)
        }

        throw SocketServiceError.invalidMessageType
    }
}

public extension SocketPayload where Self: Encodable {
    func socketPayload() throws -> SocketPayloadValue {
        let data = try JSONEncoder().encode(self)
        let json = try JSONSerialization.jsonObject(
            with: data,
            options: [.fragmentsAllowed]
        )
        return try SocketPayloadValue.from(json)
    }
}

extension String: SocketPayload {
    public func socketPayload() throws -> SocketPayloadValue {
        .string(self)
    }
}

extension Int: SocketPayload {
    public func socketPayload() throws -> SocketPayloadValue {
        .int(self)
    }
}

extension Double: SocketPayload {
    public func socketPayload() throws -> SocketPayloadValue {
        .double(self)
    }
}

extension Bool: SocketPayload {
    public func socketPayload() throws -> SocketPayloadValue {
        .bool(self)
    }
}

extension Data: SocketPayload {
    public func socketPayload() throws -> SocketPayloadValue {
        .data(self)
    }
}
