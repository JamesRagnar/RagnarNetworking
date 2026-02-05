//
//  RequestBody.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-02-03.
//

import Foundation

/// Represents an encoded request body with its content type.
public struct EncodedBody: Sendable {

    public let data: Data

    /// Optional content type. Nil when no Content-Type should be set (e.g., EmptyBody).
    /// - Warning: Must be non-nil when data is non-empty.
    public let contentType: String?

    public init(data: Data, contentType: String?) {
        self.data = data
        self.contentType = contentType
    }
}

/// Protocol that all request bodies must conform to.
/// Couples encoding strategy with content-type to prevent mismatches.
public protocol RequestBody: Sendable {

    /// Encodes the body and returns both data and content-type.
    /// - Parameter encoder: The JSON encoder to use (with configured strategies)
    func encodeBody(using encoder: JSONEncoder) throws -> EncodedBody

}

/// Default implementation: JSON encoding with application/json content type
public extension RequestBody where Self: Encodable {

    func encodeBody(using encoder: JSONEncoder) throws -> EncodedBody {
        let data = try encoder.encode(self)
        return EncodedBody(data: data, contentType: "application/json")
    }

}

/// Sentinel type for endpoints with no request body.
/// Cannot be instantiated - used only as a type marker in typealias.
/// This type represents the absence of a request body; callers should pass `nil`
/// for the `body` parameter rather than instantiating EmptyBody.
public struct EmptyBody: RequestBody {

    private init() {}

    public func encodeBody(using encoder: JSONEncoder) throws -> EncodedBody {
        EncodedBody(data: Data(), contentType: nil)
    }

}

/// Binary body for raw data uploads (images, files, etc.)
public struct BinaryBody: RequestBody {

    public let data: Data
    public let contentType: String

    public init(
        data: Data,
        contentType: String
    ) {
        self.data = data
        self.contentType = contentType
    }

    public func encodeBody(using encoder: JSONEncoder) throws -> EncodedBody {
        EncodedBody(data: data, contentType: contentType)
    }

}

/// Encodes a top-level array body as JSON.
public struct ArrayBody<Element: Encodable & Sendable>: RequestBody {

    public let items: [Element]

    public init(_ items: [Element]) {
        self.items = items
    }

    public func encodeBody(using encoder: JSONEncoder) throws -> EncodedBody {
        let data = try encoder.encode(items)
        return EncodedBody(data: data, contentType: "application/json")
    }

}

/// Wraps any Encodable payload as a request body.
public struct EncodableBody<Value: Encodable & Sendable>: RequestBody {

    public let value: Value

    public init(_ value: Value) {
        self.value = value
    }

    public func encodeBody(using encoder: JSONEncoder) throws -> EncodedBody {
        let data = try encoder.encode(value)
        return EncodedBody(data: data, contentType: "application/json")
    }

}

/// Encodes either a value or an explicit JSON null. Use `nil` on the property to omit.
public enum Nullable<Value: Encodable & Sendable>: Encodable, Sendable {

    case value(Value)
    case null

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .value(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

}

extension Nullable: Equatable where Value: Equatable {}
