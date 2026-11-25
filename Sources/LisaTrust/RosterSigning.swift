// Signing the roster and accepting it only as a whole (plan §8.1.3): Core pages the roster, signs the header that
// binds the ordered pages, and a device accepts it only with a valid header signature by Core's key and every page
// verified in place. A device keeps the newest verified roster and refuses an older version within an epoch.

import Foundation
import LisaCrypto
import LisaSyncProtocol

/// Why a roster was refused.
public enum RosterVerificationError: Error, Hashable, Sendable {
    case artifact(PagedArtifactError)
    case malformed(OperationEnvelopeError)
    case wrongDataset
    /// Not newer than the roster the device already holds for this epoch.
    case notNewer(held: Int64, offered: Int64)
}

/// Signs and verifies rosters.
public enum RosterSigning {
    /// The roster as it travels, signed by Core.
    public static func sign(_ roster: TrustRoster, with core: some MessageSigning) throws -> SignedRoster {
        let (header, pages) = try PagedArtifactVerification.paginate(
            try roster.pages(), artifactType: TrustRoster.artifactType, dataset: roster.datasetID,
            epoch: roster.epochID, version: roster.version)
        let (body, signature) = try PagedArtifactVerification.signHeader(header, with: core)
        return try SignedRoster(headerBody: body, headerSignature: signature, pages: pages)
    }

    /// The roster, only if Core's key signed its header, it names `dataset`, and every page verifies. The epoch is
    /// the one the header names; callers that hold an epoch compare it.
    public static func verify(_ signed: SignedRoster, dataset: Identifier128, coreKey: P256Verifier)
        throws(RosterVerificationError) -> TrustRoster
    {
        let header: PagedArtifactHeader
        do {
            header = try PagedArtifactHeader.decode(body: signed.headerBody)
        } catch {
            throw .malformed(error)
        }
        guard header.datasetID == dataset else { throw .wrongDataset }
        let assembled: (header: PagedArtifactHeader, pages: [[UInt8]])
        do {
            assembled = try PagedArtifactVerification.assemble(
                headerBody: signed.headerBody, headerSignature: signed.headerSignature, pages: signed.pages,
                coreKey: coreKey, expectedType: TrustRoster.artifactType, dataset: dataset, epoch: header.epochID)
        } catch {
            throw .artifact(error)
        }
        do {
            return try TrustRoster.decode(pages: assembled.pages, header: assembled.header)
        } catch {
            throw .malformed(error)
        }
    }

    /// Verifies `offered` and accepts it only if it is newer than `held` within the same epoch (a new epoch's roster
    /// replaces any older epoch's).
    public static func verifyNewer(
        _ offered: SignedRoster, than held: TrustRoster?, dataset: Identifier128, coreKey: P256Verifier
    ) throws(RosterVerificationError) -> TrustRoster {
        let roster = try verify(offered, dataset: dataset, coreKey: coreKey)
        if let held, held.epochID == roster.epochID, roster.version <= held.version {
            throw .notNewer(held: held.version, offered: roster.version)
        }
        return roster
    }

    /// The digest an enrollment result binds for the roster: SHA-256 of the signed header body, which binds every
    /// page through the Merkle root.
    public static func digest(_ signed: SignedRoster) -> Digest256 {
        // A SHA-256 value is always 32 bytes.
        try! Digest256(bytes: [UInt8](Digests.sha256(Data(signed.headerBody))))
    }
}
