// Serializes the requests of one APNs environment, so a single HTTP/2 connection carries every push and a new
// provider token is never raced by a second stream (plan §6.2; S10).

/// A first-in, first-out gate that admits one request at a time. With one request in flight, the libcurl client
/// keeps reusing its one idle connection instead of opening and closing extra ones, which APNs may treat as a
/// denial-of-service attack (Apple, "Establishing a connection to APNs"). It also fits APNs allowing only one stream
/// on a connection until a request with a valid provider token has been posted (S10).
actor APNsRequestGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Runs `body` after every earlier caller has finished.
    func run<T: Sendable>(_ body: @Sendable () async -> T) async -> T {
        if busy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            busy = true
        }
        let result = await body()
        if waiters.isEmpty {
            busy = false
        } else {
            // The gate passes straight to the next caller, which then runs without re-checking `busy`.
            waiters.removeFirst().resume()
        }
        return result
    }
}
