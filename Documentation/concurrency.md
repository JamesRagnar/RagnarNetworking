# Concurrency

## Actor Isolation

`APIClient` and `SocketIOClient` are actors. Calls into either from multiple tasks are serialized at each isolated method's entry, and safe to make concurrently.

Both actors are reentrant at `await` points, per standard Swift actor semantics: while one call to `APIClient.send` is suspended awaiting `token()`, `refresh()`, or transport, another call to `send` (or any other isolated method) can run on the same actor. `APIClient.send` and `SocketIOClient`'s connection-management methods (`connect`, `disconnect`, `reconnect(to:)`, `invalidate`) are written to tolerate this interleaving - for example, `APIClient` reads `isInvalidated` and `refreshGeneration` fresh after each `await` rather than caching them across a suspension.

## APIClient Cancellation

Cancelling the `Task` that called `send` cancels that call's in-flight transport task (`withTaskCancellationHandler` forwards cancellation to the child `Task` running `RequestPipeline.send`). It does not cancel a token refresh that call triggered, if other calls are also waiting on that refresh - only the cancelled call stops waiting for it (`CancellableTaskWait`), and it still throws `APIFailure.cancelled` promptly rather than waiting for the refresh to finish. `.cancelled` covers both sources of cancellation: a `CancellationError` raised inside the package, and a `URLError.cancelled` raised by the transport. If invalidate() was the cause, the caller instead receives `APIFailure.invalidated`, since invalidation is checked immediately after a caught error.

`invalidate()` cancels every tracked in-flight transport task and any in-progress refresh across all outstanding `send` calls. A custom `Transport` conformance that does not observe `Task` cancellation continues to run to completion, but its result is discarded at the post-transport check.

## SocketIOClient Cancellation

Each call to `events(for:)` or `statusUpdates()` returns an independent `AsyncStream`. Cancelling the `Task` iterating one consumer's stream ends that consumer's `for await` loop and deregisters only that consumer (via the stream's `onTermination`); it does not affect other consumers of the same event, the underlying connection, or other registered streams. Streams are only finished for all consumers by `invalidate()`.

`connect()`, `disconnect()`, `reconnect(to:)`, and `invalidate()` are not tied to caller task cancellation - they run to completion once called.

## Transport Thread Safety

`APIClient.send` can have multiple calls in flight concurrently, each running its own transport `Task` against the configured `Transport`. A `Transport` conformance must support concurrent invocations of `data(for:)` from multiple tasks at once. `URLSession` satisfies this.
