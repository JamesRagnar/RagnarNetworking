//
//  SocketEventSnapshot.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2025-02-08.
//

import Foundation

public struct SocketEventSnapshot: Sendable {
    public let event: String
    public let items: [SocketItem]

    public init(event: String, items: [Any]) {
        self.event = event
        self.items = items.map { SocketItem.from($0) }
    }

    public var firstUnsupportedDescription: String? {
        for item in items {
            if case .unsupported(let description) = item {
                return description
            }
        }
        return nil
    }
}

public enum SocketItem: Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case data(Data)
    case array([SocketItem])
    case dictionary([String: SocketItem])
    case null
    case unsupported(String)

    static func from(_ value: Any) -> SocketItem {
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
            return .array(arrayValue.map { SocketItem.from($0) })
        }
        if let dictValue = value as? [String: Any] {
            return .dictionary(dictValue.mapValues { SocketItem.from($0) })
        }

        return .unsupported(String(describing: value))
    }

    func asAny() -> Any {
        switch self {
        case .string(let value): value
        case .int(let value): value
        case .double(let value): value
        case .bool(let value): value
        case .data(let value): value
        case .array(let values): values.map { $0.asAny() }
        case .dictionary(let values): values.mapValues { $0.asAny() }
        case .null: NSNull()
        case .unsupported: NSNull()
        }
    }

}
