//
//  DefaultResponseHandler.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-02-06.
//

import Foundation

/// Default response handler using the Interface response map and decoding rules.
public struct DefaultResponseHandler: ResponseHandler {

    public static func handle<T: Interface>(
        _ response: (data: Data, response: URLResponse),
        for interface: T.Type
    ) throws(ResponseError) -> T.Response {
        switch try handleOutcome(response, for: interface) {
        case .decoded(let value):
            return value

        case .noContent:
            do {
                return try decode(Data(), as: interface)
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

    static func handleOutcome<T: Interface>(
        _ response: (data: Data, response: URLResponse),
        for interface: T.Type
    ) throws(ResponseError) -> ResponseOutcomeResult<T.Response> {
        let responseSnapshot = HTTPResponseSnapshot(response: response.response)
        guard responseSnapshot.statusCode != nil else {
            throw .unknownResponse(
                response.data,
                responseSnapshot
            )
        }

        guard
            let statusCode = responseSnapshot.statusCode,
            let responseCase = interface.responseCases.match(statusCode)
        else {
            throw .unknownResponseCase(
                response.data,
                responseSnapshot
            )
        }

        switch responseCase {
        case .decode:
            do {
                return .decoded(try decode(response.data, as: interface))
            } catch {
                throw .decoding(
                    response.data,
                    responseSnapshot,
                    error
                )
            }

        case .noContent:
            return .noContent

        case .error(let error):
            throw .generic(
                response.data,
                responseSnapshot,
                error
            )

        case .decodeError(body: let decodeBody):
            // Decoding failures from custom closures are surfaced as
            // ResponseError.decoding(.custom).
            let decodedError: any Error & Sendable
            do {
                decodedError = try decodeBody(response.data)
            } catch {
                throw .decoding(
                    response.data,
                    responseSnapshot,
                    .custom(message: String(describing: error))
                )
            }

            throw .decoded(
                response.data,
                responseSnapshot,
                decodedError
            )
        }
    }

    static func decode<T: Interface>(
        _ data: Data,
        as interface: T.Type
    ) throws(InterfaceDecodingError) -> T.Response {
        if T.Response.self == String.self {
            guard let response = String(
                data: data,
                encoding: .utf8
            ) as? T.Response else {
                throw .missingString
            }

            return response
        }

        if T.Response.self == Data.self {
            guard let responseData = data as? T.Response else {
                throw .missingData
            }

            return responseData
        }

        do {
            return try JSONDecoder().decode(
                T.Response.self,
                from: data
            )
        } catch {
            if let decodingError = error as? DecodingError {
                throw .jsonDecoder(.init(decodingError))
            }

            throw .custom(message: String(describing: error))
        }
    }

}
