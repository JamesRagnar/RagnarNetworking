//
//  DecodingDiagnosticsTests.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-02-06.
//

import Foundation
@testable import RagnarNetworking
import Testing

@Suite("DecodingDiagnostics Tests")
struct DecodingDiagnosticsTests {

    struct AnyCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init(_ string: String) {
            self.stringValue = string
            self.intValue = nil
        }

        init?(stringValue: String) {
            self.init(stringValue)
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    func makeContext(debugDescription: String, underlying: NSError) -> DecodingError.Context {
        let path = [AnyCodingKey("root"), AnyCodingKey("child")]
        return DecodingError.Context(
            codingPath: path,
            debugDescription: debugDescription,
            underlyingError: underlying
        )
    }

    @Test("Captures keyNotFound diagnostics")
    func testKeyNotFoundDiagnostics() {
        let underlying = NSError(domain: "KeyNotFound", code: 1)
        let context = makeContext(debugDescription: "Missing key", underlying: underlying)
        let error = DecodingError.keyNotFound(AnyCodingKey("missing"), context)
        let diagnostics = DecodingDiagnostics(error)

        #expect(diagnostics.kind == .keyNotFound)
        #expect(diagnostics.codingPath == ["root", "child"])
        #expect(diagnostics.debugDescription == "Missing key")
        #expect(diagnostics.underlyingDescription == String(describing: underlying))
    }

    @Test("Captures typeMismatch diagnostics")
    func testTypeMismatchDiagnostics() {
        let underlying = NSError(domain: "TypeMismatch", code: 2)
        let context = makeContext(debugDescription: "Wrong type", underlying: underlying)
        let error = DecodingError.typeMismatch(String.self, context)
        let diagnostics = DecodingDiagnostics(error)

        #expect(diagnostics.kind == .typeMismatch)
        #expect(diagnostics.codingPath == ["root", "child"])
        #expect(diagnostics.debugDescription == "Wrong type")
        #expect(diagnostics.underlyingDescription == String(describing: underlying))
    }

    @Test("Captures valueNotFound diagnostics")
    func testValueNotFoundDiagnostics() {
        let underlying = NSError(domain: "ValueNotFound", code: 3)
        let context = makeContext(debugDescription: "Missing value", underlying: underlying)
        let error = DecodingError.valueNotFound(Int.self, context)
        let diagnostics = DecodingDiagnostics(error)

        #expect(diagnostics.kind == .valueNotFound)
        #expect(diagnostics.codingPath == ["root", "child"])
        #expect(diagnostics.debugDescription == "Missing value")
        #expect(diagnostics.underlyingDescription == String(describing: underlying))
    }

    @Test("Captures dataCorrupted diagnostics")
    func testDataCorruptedDiagnostics() {
        let underlying = NSError(domain: "DataCorrupted", code: 4)
        let context = makeContext(debugDescription: "Corrupted data", underlying: underlying)
        let error = DecodingError.dataCorrupted(context)
        let diagnostics = DecodingDiagnostics(error)

        #expect(diagnostics.kind == .dataCorrupted)
        #expect(diagnostics.codingPath == ["root", "child"])
        #expect(diagnostics.debugDescription == "Corrupted data")
        #expect(diagnostics.underlyingDescription == String(describing: underlying))
    }

}
