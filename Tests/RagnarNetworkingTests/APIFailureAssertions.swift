//
//  APIFailureAssertions.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-08-02.
//

import Foundation
@testable import RagnarNetworking

// MARK: - Assertion Helpers

/// `APIFailure` cannot be `Equatable` - `.credential`, `.transport`, and `.response` carry
/// values that are not - so assertions match on the case rather than comparing values.
extension APIFailure {

    var isInvalidated: Bool {
        if case .invalidated = self {
            return true
        }
        return false
    }

    var isCancelled: Bool {
        if case .cancelled = self {
            return true
        }
        return false
    }

    var isNoCredentialSource: Bool {
        if case .noCredentialSource = self {
            return true
        }
        return false
    }

    var credentialError: (any Error)? {
        if case .credential(let error) = self {
            return error
        }
        return nil
    }

    var transportError: TransportError? {
        if case .transport(let error) = self {
            return error
        }
        return nil
    }

    var responseError: ResponseError? {
        if case .response(let error) = self {
            return error
        }
        return nil
    }

    var requestError: RequestError? {
        if case .request(let error) = self {
            return error
        }
        return nil
    }

}
