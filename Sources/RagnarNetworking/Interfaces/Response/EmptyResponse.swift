//
//  EmptyResponse.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-02-06.
//

import Foundation

/// A concrete response type for endpoints that succeed with no body.
///
/// Use this as the `Response` for Interfaces that map 204/205/304 to `.noContent`.
public struct EmptyResponse: Decodable, Sendable, Equatable {

    public init() {}

}
