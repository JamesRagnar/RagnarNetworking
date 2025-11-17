//
//  Interface+Response.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-11-18.
//

import Foundation

/// The known possible response error scenarios
public enum ResponseError: LocalizedError {
    
    /// The response type or code could not be determined
    case unknownResponse(Data, URLResponse)
    
    /// The provided Interface does not accept the returned response case
    case unknownResponseCase(Data, HTTPURLResponse)
    
    /// The expected result type could not be decoded for the expected response type
    case decoding(Data, HTTPURLResponse, InterfaceDecodingError)
    
    /// An unhandled error occurred
    case generic(Data, HTTPURLResponse, Error)
    
}

/// Cases where the response type could not be read
public enum InterfaceDecodingError: Error {
    
    /// The response expected a String, but was unable to decode one
    case missingString
    
    /// The response expected raw Data, but was unable to map
    case missingData
    
    /// There was an issue decoding the data to the expected type
    case jsonDecoder(Error)
    
}

public extension Interface {
    
    static func handle(
        _ response: (data: Data, response: URLResponse)
    ) throws(ResponseError) -> Response {
        guard let httpResponse = response.response as? HTTPURLResponse else {
            throw .unknownResponse(
                response.data,
                response.response
            )
        }
        
        guard let responseCase = responseCases[httpResponse.statusCode] else {
            throw .unknownResponseCase(
                response.data,
                httpResponse
            )
        }
        
        switch responseCase {
        case .success:
            do {
                return try decode(response: response.data)
            } catch {
                throw .decoding(
                    response.data,
                    httpResponse,
                    error
                )
            }
        case .failure(let error):
            throw .generic(
                response.data,
                httpResponse,
                error
            )
        }
    }
    
    static func decode(response data: Data) throws(InterfaceDecodingError) -> Response {
        if Response.self == String.self {
            guard let response = String(
                data: data,
                encoding: .utf8
            ) as? Response else {
                throw .missingString
            }

            return response
        }

        if Response.self == Data.self {
            guard let responseData = data as? Response else {
                throw .missingData
            }

            return responseData
        }

        do {
            return try JSONDecoder().decode(
                Response.self,
                from: data
            )
        } catch {
            throw .jsonDecoder(error)
        }
    }

}

// MARK: - ResponseError Helpers

public extension ResponseError {

    /// The HTTP status code from the response, if available
    var statusCode: Int? {
        switch self {
        case .unknownResponse:
            return nil
        case .unknownResponseCase(_, let httpResponse),
             .decoding(_, let httpResponse, _),
             .generic(_, let httpResponse, _):
            return httpResponse.statusCode
        }
    }

    /// The response body as a UTF-8 string, useful for logging
    var responseBodyString: String? {
        let data: Data
        switch self {
        case .unknownResponse(let responseData, _),
             .unknownResponseCase(let responseData, _),
             .decoding(let responseData, _, _),
             .generic(let responseData, _, _):
            data = responseData
        }

        return String(data: data, encoding: .utf8)
    }

    /// Attempts to decode the error response body as a specific type
    /// - Parameter type: The Decodable type to decode the response as
    /// - Returns: The decoded instance, or nil if decoding fails
    func decodeError<T: Decodable>(as type: T.Type) -> T? {
        let data: Data
        switch self {
        case .unknownResponse(let responseData, _),
             .unknownResponseCase(let responseData, _),
             .decoding(let responseData, _, _),
             .generic(let responseData, _, _):
            data = responseData
        }

        return try? JSONDecoder().decode(type, from: data)
    }

    /// All HTTP headers from the response, if available
    var headers: [String: String]? {
        let httpResponse: HTTPURLResponse?
        switch self {
        case .unknownResponse:
            httpResponse = nil
        case .unknownResponseCase(_, let response),
             .decoding(_, let response, _),
             .generic(_, let response, _):
            httpResponse = response
        }

        return httpResponse?.allHeaderFields as? [String: String]
    }

    /// Returns the value of a specific header field
    /// - Parameter key: The header field name
    /// - Returns: The header value, or nil if not found
    func header(_ key: String) -> String? {
        return headers?[key]
    }

    /// Indicates whether this error represents a retryable failure
    /// Returns true for 5xx server errors and 429 (Too Many Requests)
    var isRetryable: Bool {
        guard let code = statusCode else {
            return false
        }

        return (500...599).contains(code) || code == 429
    }

    /// A detailed description useful for debugging, including status code, headers, and body preview
    var debugDescription: String {
        var components: [String] = []

        // Error type
        switch self {
        case .unknownResponse:
            components.append("ResponseError.unknownResponse")
        case .unknownResponseCase:
            components.append("ResponseError.unknownResponseCase")
        case .decoding(_, _, let decodingError):
            components.append("ResponseError.decoding(\(decodingError))")
        case .generic(_, _, let error):
            components.append("ResponseError.generic(\(error))")
        }

        // Status code
        if let code = statusCode {
            components.append("Status: \(code)")
        }

        // Headers
        if let headers = headers, !headers.isEmpty {
            let headerStrings = headers.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            components.append("Headers: [\(headerStrings)]")
        }

        // Body preview (first 200 characters)
        if let body = responseBodyString {
            let preview = body.prefix(200)
            let suffix = body.count > 200 ? "..." : ""
            components.append("Body: \(preview)\(suffix)")
        }

        return components.joined(separator: " | ")
    }

}

