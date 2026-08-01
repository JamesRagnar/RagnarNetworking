Verdict up front

The response half of this package is well carved. The request half is not, and the single worst joint is `AuthenticationType`. Goal 1 is substantially met for *response shape* and substantially missed for *request shape*, because the most error-prone parts of a request (path, query, method/body pairing, auth) are either stringly typed or modeled as independent members with no compiler-visible relationship.

---

# 1. Are the core abstractions the right ones?

**Earning their place, keep as-is:**

- **`Transport`** (`Transport.swift:17`). One method, `URLRequest` in, bytes out. This is the correct boundary and the reasoning in the doc comment is right: a conformer cannot bypass building or handling. It is also composable as a decorator, which is where retry/backoff/logging belong. Do not widen this.
- **`InterfaceResponse`** (`InterfaceResponse.swift:35`). Putting decoding on the response type instead of switching on `Response.self` inside the handler is the correct call and is what makes envelope unwrapping and non-JSON responses expressible without forking. This is the best structural decision in the package.
- **`RequestBody` / `EncodedBody`** (`RequestBody.swift:12`, `:31`). Returning bytes and Content-Type as one value makes the classic desync structurally hard. Right shape.
- **`ResponseMap`** (`ResponseMap.swift:21`). Exact-beats-range with declaration-ordered ranges, deterministic and documented. Status semantics genuinely are per-endpoint, so this belongs on `Interface`. Right.
- **`ResponseHandler`** (`ResponseHandler.swift:14`). One method, plus `handleOutcome`/`decode` on `DefaultResponseHandler` for composition by delegation. This is the correctly-sized extension point in the package. See §5 for why `RequestBuilder` should have been built this way and wasn't.
- **`RequestPipeline`** (`RequestPipeline.swift:23`). Three named roles, one injected piece of machinery, no state. Clean.

**Earning it, with a caveat:**

- **`RequestContext`** (`RequestContext.swift:15`). The split of volatile credential from stable policy is correct. The five forwarding properties (`:37-54`) are pure delegation and give two spellings for every field, which is a taste call either way. The real caveat is that `authToken: String?` (`:22`) hardcodes "a credential is a string," which §4 argues is wrong.
- **`ServerConfiguration`** (`ServerConfiguration.swift:24`). Defensible today, but the stated rule is the problem, not the contents. The doc says "Everything else that describes the server belongs here. That is the rule for deciding where a new knob goes" (`:22-23`). That is a residual category, not a joint. `resolvedHeaders` living here rather than in the builder (`:90`) so an override cannot drop defaults is genuinely good defensive carving, and I'd keep it. But when someone next needs a per-request timeout, a cache policy, or a retry policy, the stated rule points them at `ServerConfiguration`, and none of those are server facts. I would restate the rule as "server *contract*" rather than "everything else."

**Carved at the wrong joint:**

- **`AuthenticationType`** (`Interface.swift:104`). This is the load-bearing mistake. It is a closed three-case enum answering two unrelated questions at once:
  1. *Does this request need a credential?* Asked by `APIClient.send` at `APIClient.swift:94` to decide whether to invoke the `token` closure. This is per-endpoint and is genuinely a boolean.
  2. *Where does the credential go on the wire?* Asked by `RequestBuilder.applyHeaders`/`applyQueryItems` (`RequestBuilder.swift:277`, `:237`). This is per-*server* and is open policy.

  Two consequences. First, every Interface in a codebase restates `.bearer`, which is a fact about the server, on every single endpoint. That is server convention duplicated across hundreds of declarations. Second, because the enum is closed and `APIClient` switches on it, a server using `X-API-Key`, Basic, `Token <t>` instead of `Bearer <t>`, cookie auth, or HMAC signing cannot be supported by replacing the `RequestBuilder` alone: a custom scheme has no case to declare, so `APIClient` never calls `token()` and the 401 refresh machinery is unreachable. The enum is the fork trigger.

  What I'd build: `RequestParameters.requiresAuthentication: Bool` (or a two-case `.none`/`.required`), and a separate `Authenticator` on `ServerConfiguration` that applies an opaque credential to a `URLRequest`. `APIClient` then asks the boolean; the configuration answers the placement.

- **`method` and `body` as independent members** (`Interface.swift:59` and `:77`). HTTP couples them; the type system here does not. Probe 4 confirms `method = .get` with a JSON body compiles and produces a GET carrying 7 body bytes. The commoner direction (declare `.post`, leave `body: EmptyBody = .init()` from the copied template) is equally uncaught. A single sum type (`.get`, `.delete`, `.head` carrying nothing; `.post(Body)`, `.put(Body)`, `.patch(Body)` carrying one) makes the wrong pairing unrepresentable and *removes* one of the six mandatory restatements rather than adding verbosity. This is the highest-value change available for goal 1.

**Missing:**

- **A response-metadata seam.** `InterfaceResponse.decode(from:using:)` (`InterfaceResponse.swift:45`) receives only `Data` and a `ResponseDecoder`. No status code, no headers. A `Response` that needs the `ETag`, a `Link` pagination header, `X-Total-Count`, or `Content-Range` cannot be built through `InterfaceResponse` at all. The only escape is writing a whole `ResponseHandler`, which then has to re-implement status matching or compose through `handleOutcome`. Header-driven pagination is not exotic. This is the response side's too-narrow point and it is asymmetric with `RequestBody`, which genuinely has everything it needs.
- **`URLRequest`-level policy.** `makeRequest(url:)` returns a bare `URLRequest(url:)` (`RequestBuilder.swift:261`). There is nowhere to set `timeoutInterval`, `cachePolicy`, `httpShouldHandleCookies`, or `allowsCellularAccess` short of overriding a builder step. Common need, only a wide escape hatch.
- **Streaming.** `Transport` is `(Data, URLResponse)` only. Large-file upload from disk and streamed download are structurally excluded; you buffer or you leave the package. Acceptable if deliberate, but say so.

**Redundant / suspect:**

- **`Interface.responseHandler`** (`Interface.swift:45`) is not redundant (it is the only place that sees status code and headers together), but its **replacement** semantics are wrong. The doc has to warn twice that an override in an envelope-unwrapping API must re-unwrap the envelope (`Interface.swift:37-39`, `response_handling.md:58-60`). Needing to warn about it twice is the tell. The common case for a per-endpoint hook is "the default plus one thing," and replacement is the wrong composition operator. A decorator shape (`static var responseHandler: ((any ResponseHandler) -> any ResponseHandler)?`) makes the default case additive.
- **`ResponseError.isRetryable`** (`ResponseError.swift:195`) bakes 5xx-plus-429 into the core, is consumed by nothing in the package, and implies a retry the package does not perform. It is advice wearing a policy's clothes. *(Overlaps issue #42.)*

---

# 2. Where the compiler stops helping

Ranked by likelihood in real use. All confirmed by compiling against the built module.

**1. `path` is a `String`, `queryItems` is `[URLQueryItem]?`, `headers` is `[String: String]?`.** Nothing about the most error-prone third of a request is checked. Probe 6:

```swift
init(page: Int) {
    self.path = "/x"   // `page` dropped entirely; compiles clean
}
```

This matters because the docs claim more than the code delivers. `request_parameters.md:20-28` says a `queryItems` you meant to populate "compiles clean and produces a wrong request at runtime, the exact class of error this package exists to move to compile time." Forcing the member to be *named* does not move that error to compile time. It moves it to *visible in the diff*, which is a real and worthwhile benefit, but it is a review aid, not a compiler guarantee. I'd argue goal 3's rationale should be restated honestly, because as written it invites trusting a guarantee that isn't there. Probe 7 sharpens this: a `let timeout: TimeInterval = 30` added to a `Parameters` conformance compiles and is silently ignored, so the "restate every member" discipline does not even catch a member that doesn't exist.

**2. `.noContent` and `Response` are unrelated.** Probe 1: `Response = User` with `[.code(204, .noContent)]` compiles. At runtime, `DefaultResponseHandler.handle` (`DefaultResponseHandler.swift:63-72`) calls `decode(Data(), ...)` and you get:

```
ResponseError.decoding(jsonDecoder(... dataCorrupted, "The given data was not valid JSON." ...)) | Status: 204
```

The inverse is worse. Probe 5: `Response = EmptyResponse` with `[.code(200, .decode)]` compiles and *silently succeeds*, discarding a real body, because `EmptyResponse.decode` accepts any bytes (`EmptyResponse.swift:24-29`). No error, no log. 204 handling is routine work; both directions are likely.

**3. An Interface can declare a `Response` and never decode it.** Probe 2 (`[.code(404, .error(...))]`) and Probe 3 (`[]`) both compile with `Response = User`. Every response then throws `unknownResponseCase`. An Interface with a response type and no success case is unambiguously a bug and is exactly the kind of omission the "no defaults" philosophy is aimed at, yet `responseCases` is the one member with no such protection.

Fixes for 2 and 3 are the same shape: make `ResponseMap` generic over `Response` and constrain the outcomes. `.noContent` becomes available only where `Response` is a no-body type; `.decode` becomes unavailable where it isn't. Splitting success cases from failure cases (`successCases` typed to only admit `.decode`/`.noContent`) additionally forces the author to write the success mapping. That is more surface, and it is genuinely the tradeoff goal 3 says the package accepts. *(Overlaps issue #67, which by its title proposes a generic `ResponseMap`.)*

**4. `method` / `body` mismatch.** Probe 4, covered above.

**5. `.decode` on an error range, `.error` on 200.** Probe 10: `.serverError(.decode)` and `.code(200, .error(...))` both compile. Less likely than the above, but free to catch with the same generic-`ResponseMap` change.

**6. Auth declared but unreachable.** `authentication = .bearer` on a client built with the unauthenticated `APIClient.init(configuration:transport:)` (`APIClient.swift:70-78`) compiles and fails at runtime with `RequestError.authentication`, via a `refresh` closure that exists only to throw (`:77`). Two initializers on one type cannot be connected by the compiler. Login-adjacent flows make this plausible.

**7. `Authorization` in `headers` while `authentication = .bearer`.** Silently overrides the generated header with only a `Logger.warning` (`RequestBuilder.swift:286-294`).

**8. Duplicate exact codes in `ResponseMap`.** Runtime log only (`ResponseMap.swift:38-43`). Deterministic first-wins, so low stakes. Two notes: there is no `#if DEBUG` anywhere in `Sources/`, so the "In DEBUG builds" claim in the docs is not what the code does; and because `responseCases` is a `static var` re-evaluated per response (`DefaultResponseHandler.swift:95`), the map is reconstructed and the warning re-emitted on every single response rather than once per type. `Logger.responseMap` is declared and never used.

Good news from the probes: path percent-encoding is well-behaved (`/users/a b` to `%20`, `#` to `%23`, `100%` to `100%25`) and base-URL query items survive path joining (`https://x.test/v1?api_key=k` plus `/x` plus `page=2` yields `https://x.test/v1/x?api_key=k&page=2`). Those are easy to get wrong and are right here.

---

# 3. What I'd have built differently

Load-bearing only.

**a. Split `AuthenticationType` into a per-endpoint boolean and a per-server `Authenticator`.** Argued in §1. Buys: an open set of auth schemes without forking; removes a per-server fact from every endpoint declaration; makes `APIClient`'s "do I need a token" question honest. *(Overlaps issues #69 and #34.)*

**b. Fold `method` and `body` into one sum type.** Argued in §1. Buys: the wrong pairing becomes unrepresentable, and the declaration gets *shorter*.

**c. Make `ResponseMap` generic over `Response`.** Argued in §2. Buys: kills failure modes 2, 3, and 5, including the silent one.

**d. Give `InterfaceResponse.decode` the response metadata, not just bytes.** Signature becomes something like `decode(from: Data, metadata: HTTPResponseSnapshot, using: ResponseDecoder)`. `HTTPResponseSnapshot` already exists and is already `Sendable` and already redacted. Buys: header-driven response types (pagination, ETag, `Content-Range`) stop requiring a full `ResponseHandler`. This is a small change that closes the response side's only genuinely narrow point.

**e. Give `RequestError` the context `ResponseError` already has.** `RequestError.componentsURL` (`RequestError.swift:19`) tells you nothing about which Interface, which path, or which parameters failed. Every `ResponseError` case carries a body and a snapshot. Buys: symmetry, and debuggability of the half that currently has none.

**f. Make `RequestBuilder` composition-by-delegation rather than override-by-protocol-extension.** See §5.

Things I would *not* change: `Transport`, `InterfaceResponse` as a concept, `EncodedBody`, `ResponseBody`, `ResponseMap` matching order, `resolvedHeaders` living on the configuration, and the `APIClient` refresh machinery.

---

# 4. Symmetry

Real asymmetries, and whether they're justified:

| | Request | Response | Verdict |
|---|---|---|---|
| Type owns conversion | `RequestBody` | `InterfaceResponse` | Symmetric. Good. |
| Empty case | `EmptyBody` | `EmptyResponse` | Symmetric. Good. |
| Codec argument | `encodeBody(using: JSONEncoder)` (`RequestBody.swift:16`) | `decode(from:using: ResponseDecoder)` (`InterfaceResponse.swift:45`) | **Accident.** The request side hands the body a concrete `JSONEncoder`; the response side hands the type the configuration value. An XML or protobuf body gets a `JSONEncoder` it cannot use and has no access to any configured non-JSON policy. The `XmlBody` example in `request_parameters.md:126` literally accepts and ignores the parameter. Should be `encodeBody(using: RequestEncoder)`. |
| Metadata available | body has everything it needs | `decode` gets bytes only | **Accident.** §3d. |
| Extension point size | `RequestBuilder`, 12 overridable requirements (`RequestBuilder.swift:37-119`) | `ResponseHandler`, 1 requirement plus composition helpers | **Accident of history.** The response side is right. §5. |
| Error context | `RequestError`, flat, no context | `ResponseError`, body plus snapshot on all five cases | **Accident.** §3e. |
| Declaration validated | builder throws on Content-Type conflict, missing token (`RequestBuilder.swift:320`, `:279`) | nothing validates that `responseCases` is coherent with `Response` | **Accident.** §2, items 2/3/5. |
| Tri-state null | `Nullable` | none | **Real difference**, and documented as such at `Nullable.swift:23-24`. Fine. |
| Status mapping | none | `ResponseMap` | **Real difference.** Fine. |

The pattern: the response half was designed later and better. The request half carries the older shape.

---

# 5. Extension points

**Right size:** `Transport` (one method), `ResponseHandler` (one method, composition via `DefaultResponseHandler.handleOutcome`/`decode`), `InterfaceResponse` (one static, per-type not per-client).

**Too wide: `RequestBuilder`.** Twelve public requirements, every one with a default implementation, documented as "stable customization points" (`RequestBuilder.swift:14`). That is a large frozen public surface for a rare need, and every default implementation is now an ABI-and-behavior commitment. Worse, the invariants that make an override safe are prose the compiler cannot enforce: "Respect the request's declared `AuthenticationType`," "Keep body bytes and `Content-Type` in sync," "ensure `.url` authentication still has a single final `token` query item" (`:28-32`, `:64-65`). An override of `applyQueryItems` that forgets to append the token produces silently unauthenticated requests, which is precisely the failure class the package exists to prevent, introduced by the package's own extension mechanism.

The `ResponseHandler` shape is the answer: one required method on the protocol, with `URLRequestBuilder` exposing its steps as public *callable* methods on the concrete struct rather than as overridable protocol requirements. Composition then happens by delegation, which is what the `ClientTaggingBuilder` example in `request_pipeline.md:47` is already doing by hand. Same capability, a fraction of the frozen surface, and no way to accidentally omit a step. *(Issue #70's title suggests a `RequestModifier` alongside `RequestBuilder`, which by name is additive rather than a narrowing; I'd argue for narrowing.)*

**Too narrow: `AuthenticationType`** (§1) and **the 401 trigger.** `APIClient.send` hardcodes `err.statusCode == 401` (`APIClient.swift:103`). A server signaling expiry with 403 plus a body code, or 419, or a `WWW-Authenticate` challenge, cannot use the refresh machinery at all, and the machinery is the most valuable and hardest-to-rewrite thing in the package. This wants a `shouldRefresh: @Sendable (ResponseError) -> Bool` predicate on the client. Common need, currently nowhere to go except reimplementing `APIClient`. *(Overlaps #34, and #69's "challenge policy.")*

**Too narrow: `RequestEncoder`/`ResponseDecoder`** are `JSONEncoder`/`JSONDecoder` factories wearing format-neutral names (`RequestEncoder.swift:16`, `ResponseDecoder.swift:16`). The response side has an escape via `InterfaceResponse`, and `response_handling.md:288` names this tradeoff explicitly, which is fair. The request side's escape is broken by the `JSONEncoder` parameter (§4).

---

# 6. Reuse ceiling: what is secretly one server's convention

1. **`AuthenticationType`'s three cases.** The dominant fork trigger. §1.
2. **The literal string `"token"`** for `.url` auth, in `RequestBuilder.swift:207, 213, 221, 228, 244`. A server using `?access_token=` or `?api_key=` needs a builder override, and separately loses the redaction in `HTTPResponseSnapshot.redactingTokenQueryItem` (`ResponseError.swift:89, 94`), which also hardcodes `"token"`. The token then survives into every captured error snapshot URL. The redaction and the injection are coupled by a string literal in two files.
3. **The literal `"Bearer "`** at `RequestBuilder.swift:282`. Servers using `Token <t>` or `JWT <t>` fork.
4. **`401` as the refresh trigger**, `APIClient.swift:103`.
5. **`isRetryable`'s 5xx-plus-429**, `ResponseError.swift:200`.
6. **`application/json` as the implicit default content type** in the `Encodable` default (`RequestBody.swift:25`), `ArrayBody` (`:89`), and `EncodableBody` (`:105`). Correct for most servers, but three separate hardcodings rather than one policy.

Items 2, 3, and 6 all become configuration rather than literals once the `Authenticator` split in §3a exists.

---

# 7. What is genuinely good, and why

Say these out loud so a future refactor doesn't trade them away:

- **`Transport` as a single method.** It makes the test seam impossible to misuse: a mock cannot accidentally skip request construction or response handling, so tests exercise the real paths. The 284 passing tests, including the concurrency ones, are downstream of this decision.
- **`InterfaceResponse`.** Moving decoding onto the response type is what converts "the package supports N formats" into "the package supports whatever you can write." It is also what makes an envelope-unwrapping `ResponseHandler` writable at all, since such a handler can call `T.Response.decode(from: innerData, using:)` on the inner payload. That's a real capability, not a documentation claim.
- **`ResponseBody` carrying its decoder** (`ResponseBody.swift:16`). This kills an entire quiet bug class: a catch site re-decoding an error body with a fresh `JSONDecoder()` and silently losing `.convertFromSnakeCase`. The doc comment at `:12-15` names exactly the bug it prevents. Most packages get this wrong by omission. Same reasoning drives `.decodeError(body:)` receiving the decoder at handling time (`ResponseMap.swift:90`) rather than capturing at declaration time, which is the right resolution of a genuinely awkward constraint (`responseCases` is static and has no live configuration).
- **`ResponseError` context and redaction.** Every case carries body and snapshot. `description` aliases `debugDescription` (`ResponseError.swift:266`) specifically so plain `"\(error)"` interpolation cannot fall through to the synthesized enum description and leak the unredacted snapshot. `Set-Cookie` / `Authorization` / `Proxy-Authorization` redacted from the string form while remaining available on `headers` for callers who deliberately want them (`:206-210`, `:48-49`). That is a considered privacy boundary, not a checkbox.
- **`APIClient`'s refresh generation counter and `CancellableTaskWait`** (`APIClient.swift:24`, `:226-276`). The distinction between "my task was cancelled, stop waiting" and "the shared refresh should be cancelled" is subtle, and getting it wrong means one user's cancelled request breaks refresh for every concurrent request. This is the hardest code in the package and it is correct, with the generation check (`:108`) additionally avoiding a redundant second refresh for a staggered 401. Do not simplify this.
- **`resolvedHeaders` on `ServerConfiguration`** (`:90`), placed there so no `RequestBuilder` override can drop `defaultHeaders`. Correct instinct: put the invariant where it cannot be overridden, not where it's convenient. It is the one place the `RequestBuilder` surface was correctly defended against itself.
- **`EncodedBody` returning bytes and Content-Type together**, plus the explicit conflict check at `RequestBuilder.swift:316-324`.
- **Zero dependencies**, and `Interfaces/README.md:129-141` documenting the existential limitation of `any Interface` with the closure-erasure workaround rather than pretending it doesn't exist.

---

# 8. Overlap with open issues

Checked titles only, after forming the above. Overlaps, so you can discount these as independent signal:

- **#69** "Make authentication a strategy: open `AuthenticationScheme`, `Authenticator`, and a challenge policy" and **#34** "401 retry and refresh are unreachable for auth schemes other than `.bearer` and `.url`" cover my §1 `AuthenticationType` finding and the §5 401-trigger finding. My additional angle: the enum conflates a per-endpoint boolean with a per-server placement policy, which is *why* it forces the fork, and splitting on that line also removes the `"token"` and `"Bearer"` literals in §6.
- **#67** "Type the error body: `Interface.Failure`, generic `ResponseMap`, and typed throws from `send`" overlaps my §2 items 2, 3, and 5 by proposing a generic `ResponseMap`. My angle is different: I want genericity over `Response` to constrain `.noContent`/`.decode`, which is a distinct axis from typing the *failure* side.
- **#70** "Add `RequestModifier` as a composable seam alongside `RequestBuilder`" touches my §5 `RequestBuilder` finding, but by title proposes adding a seam. I'm arguing the opposite direction: narrow the existing one to a single requirement plus callable helpers.
- **#42** "isRetryable implies a retry the package does not perform" is my §1 `isRetryable` note, already known.
- **#23** "Transport failures are unmodelled and undocumented" is adjacent to my §3e `RequestError` context point but not the same thing.

**Not represented in any issue title:** the `method`/`body` independence (§2.4, §3b), `InterfaceResponse.decode` having no response metadata (§3d), the `encodeBody(using: JSONEncoder)` vs `decode(using: ResponseDecoder)` asymmetry (§4), `Interface.responseHandler`'s replace-instead-of-decorate semantics (§1), and the gap between what `request_parameters.md:20-28` claims the no-defaults rule buys and what it actually buys (§2.1). Those five are where I'd spend attention first, and §3b is the cheapest of them by a wide margin.
