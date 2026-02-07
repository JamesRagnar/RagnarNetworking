//
//  ErrorSnapshot.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-02-06.
//

import Foundation

/// A Sendable snapshot of an Error for safe propagation.
public struct ErrorSnapshot: Sendable, Equatable, CustomStringConvertible {

    public let typeName: String
    public let description: String
    public let localizedDescription: String

    public init(typeName: String, description: String, localizedDescription: String) {
        self.typeName = typeName
        self.description = description
        self.localizedDescription = localizedDescription
    }

    public init(_ error: Error) {
        self.typeName = String(describing: type(of: error))
        self.description = String(describing: error)
        self.localizedDescription = (error as NSError).localizedDescription
    }

}
