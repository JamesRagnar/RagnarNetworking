# Concurrency

## Actor Isolation

`APIClient` in `RagnarNetworking` and `SocketIOClient` in `RagnarSocketIO` are actors. Calls into either from multiple tasks are serialized at each isolated method's entry, and safe to make concurrently.

Both actors are reentrant at `await` points, per standard Swift actor semantics. While one call to `APIClient.send` is suspended reading or refreshing its `CredentialSource`, or awaiting transport, another call can run on the same actor. For example, `APIClient` reads `isInvalidated` and `refreshGeneration` fresh after each `await` rather than caching them across a suspension. See [Socket.IO Client](SocketIO.md) for the separate socket product's lifecycle guarantees.

## APIClient Cancellation

Cancelling the `Task` that called `send` cancels that call's in-flight transport task (`withTaskCancellationHandler` forwards cancellation to the child `Task` running `RequestPipeline.send`). It does not cancel a credential refresh that call triggered if other calls are also waiting on that refresh. Only the cancelled call stops waiting for it (`CancellableTaskWait`), and it still throws `CancellationError` promptly rather than waiting for the refresh to finish. Cancellation always surfaces as `CancellationError`, including when `URLSession` reports it as `URLError.cancelled`, so one check covers both sources. If `invalidate()` was the cause, the caller instead receives `APIClientError.invalidated`, since invalidation is checked immediately after a caught error.

`invalidate()` cancels every tracked in-flight transport task and any in-progress refresh across all outstanding `send` calls. A custom `Transport` conformance that does not observe `Task` cancellation continues to run to completion, but its result is discarded at the post-transport check.

## SocketIOClient Cancellation

Each call to `events(for:)` returns an independent `SocketEventStream`, and each call to `statusUpdates()` returns an independent `AsyncStream`. Cancelling a task that iterates either stream deregisters only that subscription. It does not affect other subscriptions or the underlying connection. `invalidate()` finishes all remaining streams.

`connect(to:)`, `disconnect()`, and `invalidate()` are not tied to caller task cancellation. They run to completion once called.

## Transport Thread Safety

`APIClient.send` can have multiple calls in flight concurrently, each running its own transport `Task` against the configured `Transport`. A `Transport` conformance must support concurrent invocations of `data(for:)` from multiple tasks at once. `URLSession` satisfies this.
