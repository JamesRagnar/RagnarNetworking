//
//  InterfaceDecodingError.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-02-06.
//

import Foundation

/// Specific errors encountered during response decoding.
public enum InterfaceDecodingError: Error, Sendable {

    /// Expected String response but UTF-8 decoding failed
    case missingString

    /// Expected Data response but type casting failed
    case missingData

    /// JSON decoding failed with structured diagnostics.
    case jsonDecoder(DecodingDiagnostics)

    /// A custom decode closure failed.
    case custom(message: String)

}

/// Sendable diagnostics for decoding failures.
public struct DecodingDiagnostics: Sendable, Equatable {

    public enum Kind: Sendable, Equatable {

        case keyNotFound
        case typeMismatch
        case valueNotFound
        case dataCorrupted
        case other

    }

    public let kind: Kind

    public let codingPath: [String]

    public let debugDescription: String

    public let underlyingDescription: String?

    public init(
        kind: Kind,
        codingPath: [String],
        debugDescription: String,
        underlyingDescription: String? = nil
    ) {
        self.kind = kind
        self.codingPath = codingPath
        self.debugDescription = debugDescription
        self.underlyingDescription = underlyingDescription
    }

}

extension DecodingDiagnostics {

    init(_ error: DecodingError) {
        switch error {
        case .keyNotFound(_, let context):
            self.init(
                kind: .keyNotFound,
                codingPath: context.codingPath.map(\.stringValue),
                debugDescription: context.debugDescription,
                underlyingDescription: context.underlyingError.map(String.init(describing:))
            )

        case .typeMismatch(_, let context):
            self.init(
                kind: .typeMismatch,
                codingPath: context.codingPath.map(\.stringValue),
                debugDescription: context.debugDescription,
                underlyingDescription: context.underlyingError.map(String.init(describing:))
            )

        case .valueNotFound(_, let context):
            self.init(
                kind: .valueNotFound,
                codingPath: context.codingPath.map(\.stringValue),
                debugDescription: context.debugDescription,
                underlyingDescription: context.underlyingError.map(String.init(describing:))
            )

        case .dataCorrupted(let context):
            self.init(
                kind: .dataCorrupted,
                codingPath: context.codingPath.map(\.stringValue),
                debugDescription: context.debugDescription,
                underlyingDescription: context.underlyingError.map(String.init(describing:))
            )

        @unknown default:
            self.init(
                kind: .other,
                codingPath: [],
                debugDescription: String(describing: error),
                underlyingDescription: nil
            )
        }
    }

}
