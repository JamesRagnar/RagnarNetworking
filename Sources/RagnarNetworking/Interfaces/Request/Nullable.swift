//
//  Nullable.swift
//  RagnarNetworking
//

import Foundation

/// Encodes either a value or an explicit JSON `null`.
///
/// Use this for request body fields where the API distinguishes between a field being
/// absent (`nil` Swift optional) and being explicitly set to `null`.
///
/// - `nil` on the property - field is omitted from the JSON body
/// - `.null` - field encodes as `null`
/// - `.value(x)` - field encodes as the wrapped value
///
/// The `nil`-omits-the-field behavior relies on the encoding container using
/// `encodeIfPresent`, which Swift's synthesized `Encodable` conformance emits for
/// `Optional`-typed properties. It does not hold if a type hand-writes `encode(to:)` and
/// calls `container.encode(_:forKey:)` on a `Nullable<Value>?` property directly - that
/// encodes `nil` as JSON `null`, indistinguishable from `.null`.
///
/// `Nullable` conforms to `Encodable` only. It cannot represent a tri-state response body,
/// since there is no corresponding `Decodable` conformance.
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
