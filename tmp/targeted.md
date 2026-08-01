1. InterfaceResponse and the Sendable workaround

**The design is right. The stated reason is wrong, and it understates the guarantee.**

The cited restriction is real, but only for the formulation nobody proposed:

```
extension Array: InterfaceResponse where Element: Decodable & Sendable {}
error: conditional conformance to non-marker protocol 'InterfaceResponse'
       cannot depend on conformance of 'Element' to marker protocol 'Sendable'
```

But the actual alternative, `protocol InterfaceResponse: Sendable` with the conformance left as `where Element: Decodable`, **compiles clean** under `-swift-version 6`. So "would make the `Array`/`Dictionary` conformances inexpressible" (`InterfaceResponse.swift:31-34`) is false as written.

It is worse than inexpressible. It is unsound. This compiles with zero diagnostics in Swift 6 mode:

```swift
public protocol InterfaceResponse: Sendable { /* ... */ }
extension Array: InterfaceResponse where Element: Decodable {}

final class Box: Decodable { var v = 0 }        // not Sendable
actor Sink { func take<T>(_ v: T) {} }

func ship<T: InterfaceResponse>(_ value: T, to sink: Sink) async {
    await sink.take(value)                      // T: Sendable "for free"
}

func caller(sink: Sink) async {
    let boxes = [Box()]
    await ship(boxes, to: sink)
    boxes[0].v = 2                              // genuine race, accepted
}
```

The conditional conformance is checked against `Element: Decodable` only, so `[Box]` satisfies `InterfaceResponse` and therefore inherits `Sendable` without `Array`'s own conditional `Sendable` ever being verified.

The shipped form closes that. `Response: InterfaceResponse & Sendable` (`Interface.swift:25`) forces a separate `Array<Box>: Sendable` check, which fails:

```
s1.swift:7:6: error: type 'Box' does not conform to the 'Sendable' protocol
enum BadInterface: Interface {   // typealias Response = [Box]
```

Other formulations, all rejected:
- `protocol SendableInterfaceResponse: InterfaceResponse, Sendable` + `extension Array: SendableInterfaceResponse where Element: Decodable & Sendable` → same marker-protocol error, now on `SendableInterfaceResponse`.
- `@retroactive` → `error: 'retroactive' attribute does not apply; 'InterfaceResponse' is declared in this module`, plus the marker error. Not applicable at all here.

**Non-Sendable reaching a concurrency boundary: no path.** Every generic entry point is constrained on `T: Interface`, not on `InterfaceResponse` alone (`ResponseHandler.swift:24`, `DefaultResponseHandler.swift:54/80/157`, `RequestPipeline.swift:47`), and `ResponseOutcomeResult<Response: Sendable>` (`ResponseHandler.swift:38`) re-states it. `APIClient.execute` crosses a `Task` boundary at `APIClient.swift:179-188` with `T.Response`, which is Sendable by the `Interface` constraint. Grep confirms `InterfaceResponse` appears unconstrained nowhere in `Sources/`.

**Verdict: non-issue in code, real doc defect.** `InterfaceResponse.swift:30-34` and the matching PR paragraph should say the refinement compiles but silently grants `Sendable` to non-Sendable element types, and that the current split is *stronger*, not "unchanged."

---

## 2. Array and Dictionary conditional conformances

**Default is selected.** Verified at runtime: `[Int].decode(from: "[1,2,3]")` → `[1, 2, 3]`, `[[Int]]` and `[String: [Int]]` both work.

**Your Dictionary suspicion is right, but not for the reason you gave.** `[Int: T]` is fine; the stdlib's `Dictionary.init(from:)` special-cases `Key.self == Int.self` and uses a keyed container with `intValue`:

| Response type | `{"a":1}` / `{"1":"x"}` | `["a",1]` |
|---|---|---|
| `[String: Int]` | ✅ `["a": 1]` | ✗ |
| `[Int: String]` | ✅ `[1: "x"]` | ✗ `DecodingError` |
| `[Kind: Int]` (enum, `RawValue == String`) | ✗ `typeMismatch: Expected to decode Array<Any> but found a dictionary` | ✅ `[Kind.a: 1]` |
| `[Kind: Int]` + `CodingKeyRepresentable` | ✅ `[Kind.a: 1]` | ✗ |

So the failing input for the doc claim at `InterfaceResponse.swift:105` ("Decodes a top-level JSON object as a dictionary") is `Response = [Kind: Int]` against body `{"a":1}`, which throws. The unkeyed-array fallback bites any key type that is not `String`, not `Int`, and not `CodingKeyRepresentable`.

**Do not constrain to `Key == String`.** That would break `[Int: T]`, which works correctly. The honest fix is the doc: the conformance inherits stdlib `Dictionary: Decodable` semantics verbatim, which means an object for `String`/`Int`/`CodingKeyRepresentable` keys and an alternating unkeyed array otherwise. Verified that adding `CodingKeyRepresentable` to the enum makes `{"a":1}` decode.

**Verdict: doc defect, plus a test gap.** `grep -rn Dictionary Tests/` returns only unrelated header-dictionary tests. The `Dictionary` conformance ships with zero coverage, and it is the one with the sharpest semantics. `Array` has exactly one test (`InterfaceResponseTests.swift:1132-1160`).

**Missing conformances (real regression).** These were all legal `Response` types under `Response: Decodable, Sendable` and now fail to compile:

```
s2.swift:13:6: error: type 'IntResponse' does not conform to protocol 'Interface'   // Response = Int
s2.swift:21:6: error: type 'OptResponse' does not conform to protocol 'Interface'   // Response = User?
s2.swift:27:6: error: type 'SetResponse' does not conform to protocol 'Interface'   // Response = Set<String>
```

Loud, so not a defect. But the workaround is not cheap: `Int` is stdlib and `InterfaceResponse` is yours, so a consumer conforming it in their own module needs `@retroactive`, with the ODR hazard that implies. `Int`, `Double`, `Bool`, `Set` (where `Element: Decodable & Hashable`), and `Optional` (where `Wrapped: InterfaceResponse`) are all one-line conditional conformances that belong in the package. The `Optional` one also gives you a clean `null`-body story. None of them are listed as breaking changes in the PR body.

---

## 3. Behavior parity with the removed decode ladder

Ran each case against the actual conformances. Parity holds.

| Case | Old (`HEAD~1:DefaultResponseHandler.swift:157-190`) | New (`InterfaceResponse.swift`, `DefaultResponseHandler.swift:157-174`) |
|---|---|---|
| `String`, invalid UTF-8 (`[0xFF,0xFE,0xFD]`) | `.missingString` | `.missingString` ✅ |
| `Data`, empty | returns `Data()` | returns `Data()` ✅ |
| `Data`, non-empty | returns bytes | returns bytes ✅ |
| `EmptyResponse`, body `"junk"` | `EmptyResponse()` | `EmptyResponse()` ✅ (`EmptyResponse.swift:19-31`) |
| JSON `Decodable`, empty `Data` | `.jsonDecoder(dataCorrupted)` | `.jsonDecoder(dataCorrupted)` ✅ |

**Error normalization order: correct, and the first arm is load-bearing.** `InterfaceDecodingError` and `DecodingError` are disjoint types, so the two `catch` clauses can never both match and their relative order is semantically irrelevant. But the `InterfaceDecodingError` arm itself is not optional: without it, `String.decode` throwing `.missingString` (`InterfaceResponse.swift:82`) would fall to the final `catch` and become `.custom(message: "missingString")`, losing the case. Covered by `InterfaceResponseTests.swift:1009-1028`.

No diagnostic detail is lost relative to the old code. The new arm is strictly additive; the `DecodingError → .jsonDecoder(DecodingDiagnostics)` mapping and the `String(describing:)` fallback are both unchanged.

**`missingData` was genuinely unreachable.** `git grep missingData HEAD~1` returns exactly three source hits: the case declaration, its `errorDescription`, and the single throw site at `HEAD~1:DefaultResponseHandler.swift:181`. That throw was guarded by `if T.Response.self == Data.self`, so `data as? T.Response` reduced to `data as? Data`, which cannot fail. No other path. (`HEAD~1` there is the pre-change tip, `4efa8e5`.) Removing a public enum case is source-breaking for exhaustive switches, but loudly.

**Verdict: PR claim is accurate.**

---

## 4. The `defaultHandler` parameter

**Real defect, and it is the exact shape the PR argued against.**

`Interface+ResponseHandler.swift:36` defaults `defaultHandler` to `DefaultResponseHandler()`. The PR body states the rule it violates: *"A defaulted parameter meant `T.handle(response)` compiled and silently used a plain `JSONDecoder`, losing the client's rules with no diagnostic."* Substituting handler for decoder gives the identical sentence.

**Silent-loss path.** Not inside the package: `RequestPipeline.swift:56-60` is the only in-package caller and passes `context.responseHandler`. But this compiles, and silently discards a configured `EnvelopeUnwrappingHandler`:

```swift
// custom cache / replay / transport layer, holding a configuration
let (data, response) = try await myCache.fetch(request)
return try GetUser.handle((data, response), responseDecoder: config.responseDecoder)
// config.responseHandler is gone. No warning.
```

The caller who has `config.responseDecoder` in hand is precisely the caller who also has `config.responseHandler`, and the parameter shape invites them to forget it.

The pull is already visible in this branch: roughly thirty call sites in `InterfaceResponseTests.swift` (427, 444, 460, 476, 541, 611, 629, …) take the default. Those tests are deliberately exercising `DefaultResponseHandler`, so they are not wrong, but they are the demonstration that the default gets taken.

**Recommendation: make it required.** One-line change, mechanical test churn, and it restores the symmetry the PR claims. The two-argument public `handle` is still worth having as a three-argument one, for the same reason `URLRequest.init(_:_:context:)` is worth having on the request side: someone not using `RequestPipeline` needs the seam. It is the *default value*, not the entry point, that should go.

---

## 5. The silent `responseHandler` migration break

**Confirmed exactly as described, with runtime proof.** Unchanged pre-migration source:

```swift
enum Legacy: Interface {
    typealias Response = EmptyResponse
    static var responseCases: ResponseMap { [.success(.noContent)] }
    static var responseHandler: any ResponseHandler { MyHandler() }   // old signature
}
```

Compiles clean (also under `-warnings-as-errors`). At runtime:

```
concrete Legacy.responseHandler   : MyHandler()
protocol witness (generic context): nil
```

`MyHandler` is dead. The endpoint takes the configured handler.

**What I tried, and what the compiler said:**

| Attempt | Result |
|---|---|
| Rename requirement to `overrideHandler`, add `@available(*, unavailable, renamed: "overrideHandler")` shadow in the protocol extension | Compiles silently. A concrete declaration shadows an extension member with no diagnostic. **Does not work.** |
| Deprecated same-name member with the old non-optional type in the same extension | `error: invalid redeclaration of 'responseHandler'`. **Cannot be written.** |
| `-warnings-as-errors` on the unmodified repro | No diagnostic. |

So "Swift cannot be made to flag this" is correct **for the optional signature**. But the break is avoidable by not changing the signature:

```swift
public struct UnsetResponseHandler: ResponseHandler { /* never invoked */ }

public protocol Interface {
    static var responseHandler: any ResponseHandler { get }
}
extension Interface {
    static var responseHandler: any ResponseHandler { UnsetResponseHandler() }
}
// resolve: T.responseHandler is UnsetResponseHandler ? context.responseHandler : T.responseHandler
```

Verified end to end: old source unchanged resolves to `MyH`, a non-overriding Interface resolves to the configured handler. Cost is a public sentinel type and one runtime `is` check; benefit is that the silent break disappears entirely. `Optional` is the cleaner model and I would not insist on the swap, but the PR body's *"It must be `(any ResponseHandler)?`"* is not true, and the sentinel should be weighed rather than implied away.

**If you keep the optional, the documentation is not sufficient.** The warning lives only in the PR body. Neither `Interface.swift:30-45` (the doc comment on the requirement, which is where an upgrader looks) nor `Documentation/Interfaces/response_handling.md:51-58` mentions the invariance trap. A PR body is not reachable from the source tree after merge. Put it in the doc comment and in the docs file.

---

## 6. Ownership move fallout

**Grep is clean.** `URLRequestBuilder()` and `DefaultResponseHandler()` appear at exactly three sites in `Sources/`:
- `ServerConfiguration.swift:70` and `:71` — correct, these are the configuration's own defaults.
- `Interface+ResponseHandler.swift:36` — the section 4 issue. Nothing else.

**Nothing reads from two sources.** `RequestPipeline` holds only `transport` (`RequestPipeline.swift:26`) and reads `context.builder` / `context.responseHandler` (`:52`, `:59`). `URLRequest.init(requestParameters:context:)` reads `context.builder` (`URLRequest+RequestBuilder.swift:49`). No precedence rule survives anywhere.

**RequestContext forwarding pulls its weight, mostly.** All six are used:
- `url`, `requestEncoder`, `resolvedHeaders(for:)` — consumed by the default `RequestBuilder` pipeline (`RequestBuilder.swift:146`, `:154`, `:165`). These justify the facade: `RequestBuilder`'s protocol methods receive a `RequestContext`, so without forwarding every custom builder would spell `context.configuration.url`.
- `responseDecoder`, `builder`, `responseHandler` — used only by `RequestPipeline` and `URLRequest.init`, both of which could say `context.configuration.x`. These three are the ones that are arguably indirection, though they are cheap and consistent with the other three.

Since `configuration` is public, `context.builder` and `context.configuration.builder` are both spellings of one value. One source of truth, two names. Not a defect.

**One footgun worth a doc line:** `context.builder` is visible inside a `RequestBuilder.buildRequest` implementation, where it *is* the builder currently running. A custom builder that "delegates to the configured builder" via `context.builder.buildRequest(...)` recurses infinitely. The invariants list at `RequestBuilder.swift:28-35` tells people to "compose with `URLRequestBuilder`" but does not say that composing through the context is the wrong way to do it.

---

## Interactions with out-of-scope work

`#67` (typed error bodies) will want `ResponseOutcome.decodeError`'s closure to return the same `InterfaceResponse`-shaped thing; the `Optional` conformance gap from section 2 becomes more visible there. `#69` is untouched by this branch. No conflict with `#70`.

## Ranked

1. **`defaultHandler` default value** (`Interface+ResponseHandler.swift:36`) — remove it. Contradicts the branch's own stated rule and has a real silent-loss path.
2. **`Sendable` rationale is factually wrong** (`InterfaceResponse.swift:30-34`, PR body) — the refinement compiles and is unsound; the current design is stronger than "unchanged."
3. **Dictionary doc claim is false for non-`String`/`Int`/`CodingKeyRepresentable` keys** (`InterfaceResponse.swift:105`) — fix the doc, do not constrain to `Key == String`, and add coverage (currently zero).
4. **Migration trap is documented only in the PR body** — move it into `Interface.swift:30-45` and `response_handling.md`; note that the sentinel formulation avoids the break outright.
5. **Missing `Int`/`Bool`/`Double`/`Set`/`Optional` conformances** — loud regression, but `@retroactive` makes the user-side workaround unpleasant.
6. **`context.builder` recursion footgun** — one line in the `RequestBuilder` invariants.

Sections 3 and 6 are otherwise clean; the parity claim and the ownership move both hold up under inspection.
