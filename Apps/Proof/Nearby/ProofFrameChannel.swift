// PROOF ONLY — Apps/Proof never ships. The boundary between the proof's session layer and its transport: framed
// sends and receives. The session layer (hello, transcript signatures, timing) is written against this protocol;
// `NWConnectionFrameChannel` is the Network framework implementation.

protocol ProofFrameChannel: Sendable {
    /// Sends one frame and returns once the transport has taken it (backpressure by awaiting each send).
    func send(_ frame: ProofFrame) async throws
    /// Receives one whole frame; the header is checked against the 1 MiB budget before the payload is read.
    func receive() async throws -> ProofFrame
    /// Writes bytes exactly as given: only the oversize-header refusal case uses it.
    func sendRaw(_ bytes: [UInt8]) async throws
    func close()
}

enum ProofChannelError: Error, Equatable, Sendable {
    case closedByPeer
    case sendTimedOut
    case idleTimedOut
}
