// Core's signing-key history (plan §8.1.1, §8.1.4, §8.5.3): `{key, validFromPosition, retiredAtPosition}` from an
// anchor (the key in the owner text, or an independent anchor after a restore) through verified transitions, each
// signed by both its keys and chaining from the key before. Records are verified with the key their position names:
// a final receipt by the key valid at its commit position, so a retired key verifies only records from before its
// retirement. Records signed when served (change pages, snapshots, rosters, anchors bundles) are always signed by the
// current key and are verified with it; a provisional receipt, which has no position and never counts as commitment,
// verifies with any key of the history.

import LisaCrypto
import LisaSyncProtocol

/// Why a transition or a history was refused.
public enum KeyHistoryError: Error, Hashable, Sendable {
    case malformed(OperationEnvelopeError)
    case invalidKey
    case wrongDataset
    /// Not signed by both of its keys.
    case invalidSignature
    /// Its previous key isn't the history's current key, or its sequence isn't the next one.
    case notTheNextTransition
    /// Its activation position isn't after the current key's.
    case activationNotAfter(Int64)
    /// Its next key is already in the history.
    case keyAlreadyUsed
}

/// One key and the commit positions it signs.
public struct CoreKeyEntry: Hashable, Sendable {
    public let key: P256Verifier
    /// The sequence of the transition that activated it: 0 for Core's first key, nil for an anchor whose transition
    /// this holder hasn't seen.
    public let sequence: Int64?
    /// The first position this key signs.
    public let validFrom: Int64
    /// The first position the next key signs; none for the current key.
    public let retiredAt: Int64?

    public func isValid(at position: Int64) -> Bool { position >= validFrom && retiredAt.map { position < $0 } ?? true }
}

/// Signs and verifies key transitions.
public enum KeyTransitionSigning {
    /// The transition, signed by the current key and by the next key over the same body.
    public static func sign(
        _ transition: SigningKeyTransition, previous: some MessageSigning, next: some MessageSigning
    ) throws -> SignedKeyTransition {
        guard previous.verifier.spkiDER == transition.previousKey, next.verifier.spkiDER == transition.nextKey else {
            throw KeyHistoryError.invalidKey
        }
        let body = try transition.canonicalBody()
        return try SignedKeyTransition(
            body: body, previousSignature: try DomainSignatures.sign(body, domain: .keyTransition, with: previous),
            nextSignature: try DomainSignatures.sign(body, domain: .keyTransition, with: next))
    }

    /// The transition and its next key, only if both of its keys signed these exact bytes.
    public static func verify(_ signed: SignedKeyTransition) throws(KeyHistoryError)
        -> (transition: SigningKeyTransition, next: P256Verifier)
    {
        let transition: SigningKeyTransition
        do {
            transition = try signed.transition()
        } catch {
            throw .malformed(error)
        }
        guard let previous = try? P256Verifier(canonicalSPKI: transition.previousKey),
            let next = try? P256Verifier(canonicalSPKI: transition.nextKey)
        else { throw .invalidKey }
        guard
            DomainSignatures.isValid(signed.previousSignature, over: signed.body, domain: .keyTransition, by: previous),
            DomainSignatures.isValid(signed.nextSignature, over: signed.body, domain: .keyTransition, by: next)
        else { throw .invalidSignature }
        return (transition, next)
    }
}

/// The key history one holder trusts.
public struct CoreKeyHistory: Hashable, Sendable {
    public let datasetID: Identifier128
    /// Oldest first; the last is current.
    public let entries: [CoreKeyEntry]

    /// A history that starts at `anchor`, valid from position 0. `sequence` is 0 for Core's first key; a device
    /// anchored by an owner text leaves it nil and learns it from the transition that activated the anchor.
    public init(datasetID: Identifier128, anchor: P256Verifier, sequence: Int64? = nil) {
        self.datasetID = datasetID
        entries = [CoreKeyEntry(key: anchor, sequence: sequence, validFrom: 0, retiredAt: nil)]
    }

    init(datasetID: Identifier128, entries: [CoreKeyEntry]) {
        self.datasetID = datasetID
        self.entries = entries
    }

    /// The key that signs new records.
    public var current: P256Verifier { entries[entries.count - 1].key }

    /// The sequence of the current key's transition, when known.
    public var currentSequence: Int64? { entries[entries.count - 1].sequence }

    /// How many transitions this history has applied since its anchor.
    public var transitionCount: Int64 { Int64(entries.count - 1) }

    /// The history with `signed` applied as the next link: signed by both keys, for this dataset, from the current
    /// key, the next in sequence when that is known, activating after the current key's start, with a key never used
    /// before.
    public func applying(_ signed: SignedKeyTransition) throws(KeyHistoryError) -> CoreKeyHistory {
        let (transition, next) = try KeyTransitionSigning.verify(signed)
        guard transition.datasetID == datasetID else { throw .wrongDataset }
        guard transition.previousKey == current.spkiDER else { throw .notTheNextTransition }
        if let currentSequence, transition.sequence != currentSequence + 1 { throw .notTheNextTransition }
        let last = entries[entries.count - 1]
        guard transition.activationPosition > last.validFrom else {
            throw .activationNotAfter(transition.activationPosition)
        }
        guard !entries.contains(where: { $0.key == next }) else { throw .keyAlreadyUsed }
        var updated = entries
        updated[updated.count - 1] = CoreKeyEntry(
            key: last.key, sequence: last.sequence ?? transition.sequence - 1, validFrom: last.validFrom,
            retiredAt: transition.activationPosition)
        updated.append(
            CoreKeyEntry(
                key: next, sequence: transition.sequence, validFrom: transition.activationPosition, retiredAt: nil))
        return CoreKeyHistory(datasetID: datasetID, entries: updated)
    }

    /// The history with Core's transitions applied in sequence order. A transition whose next key the history
    /// already holds is checked and skipped; the one that activated an anchor of unknown sequence names it. A
    /// transition from before the anchor is skipped only while the anchor is all the history holds; any other one
    /// must be the next link.
    public func applying(all transitions: [SignedKeyTransition]) throws(KeyHistoryError) -> CoreKeyHistory {
        var history = self
        for signed in transitions {
            let transition: SigningKeyTransition
            do {
                transition = try signed.transition()
            } catch {
                throw .malformed(error)
            }
            guard transition.datasetID == datasetID else { throw .wrongDataset }
            if let index = history.entries.firstIndex(where: { $0.key.spkiDER == transition.nextKey }) {
                let entry = history.entries[index]
                if let sequence = entry.sequence {
                    guard sequence == transition.sequence else { throw .notTheNextTransition }
                } else {
                    _ = try KeyTransitionSigning.verify(signed)
                    var entries = history.entries
                    entries[index] = CoreKeyEntry(
                        key: entry.key, sequence: transition.sequence, validFrom: entry.validFrom,
                        retiredAt: entry.retiredAt)
                    history = CoreKeyHistory(datasetID: datasetID, entries: entries)
                }
                continue
            }
            if transition.previousKey == history.current.spkiDER {
                history = try history.applying(signed)
            } else if history.entries.count == 1, history.currentSequence == nil {
                continue
            } else {
                throw .notTheNextTransition
            }
        }
        return history
    }

    /// The key that signs records at `position`.
    public func key(at position: Int64) -> P256Verifier? { entries.first { $0.isValid(at: position) }?.key }

    /// Whether `key` is in the history.
    public func contains(_ key: P256Verifier) -> Bool { entries.contains { $0.key == key } }

    /// Verifies a Core receipt by the key its position names, or, for a provisional receipt, by any key of the
    /// history.
    public func verifyReceipt(_ signed: SignedCoreReceipt) throws(ReceiptVerificationError) -> CoreReceipt {
        let claimed: CoreReceipt
        do {
            claimed = try signed.receipt()
        } catch {
            throw .malformed(error)
        }
        let candidates: [P256Verifier]
        if let position = claimed.position {
            candidates = key(at: position).map { [$0] } ?? []
        } else {
            candidates = entries.map(\.key).reversed()
        }
        for key in candidates {
            if let receipt = try? ReceiptSigning.verify(signed, dataset: datasetID, coreKey: key) { return receipt }
        }
        if claimed.datasetID != datasetID { throw .wrongDataset }
        throw .invalidSignature
    }
}
