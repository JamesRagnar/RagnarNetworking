//
//  ResponseHandler.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-02-06.
//

import Foundation

/// Handles decoding and mapping of responses for an Interface.
public protocol ResponseHandler {

    /// Handle a response for a given Interface type.
    static func handle<T: Interface>(
        _ response: (data: Data, response: URLResponse),
        for interface: T.Type
    ) throws(ResponseError) -> T.Response

}

/// Default response handler using the Interface response map and decoding rules.
public struct DefaultResponseHandler: ResponseHandler {

    public static func handle<T: Interface>(
        _ response: (data: Data, response: URLResponse),
        for interface: T.Type
    ) throws(ResponseError) -> T.Response {
        switch try T.handleOutcome(response) {
        case .decoded(let value):
            return value
        case .noContent:
            do {
                return try T.decode(response: Data())
            } catch {
                let responseSnapshot = HTTPResponseSnapshot(response: response.response)
                guard responseSnapshot.statusCode != nil else {
                    throw .unknownResponse(
                        response.data,
                        responseSnapshot
                    )
                }

                throw .decoding(
                    response.data,
                    responseSnapshot,
                    error
                )
            }
        }
    }

}
