// Accepting a paged artifact only as a whole (plan §8.1.3): a valid signed header and every page verified in place.

import LisaCrypto
import LisaSyncProtocol

/// Why a paged artifact was refused.
public enum PagedArtifactError: Error, Hashable, Sendable {
    case malformedHeader(OperationEnvelopeError)
    case invalidHeaderSignature
    /// The header names another artifact type, dataset or epoch than expected.
    case unexpectedArtifact
    /// A page index missing, repeated or beyond the page count.
    case incompletePages
    /// A page whose inclusion proof does not verify at its index: altered, substituted or reordered.
    case pageNotIncluded(index: Int64)
}

/// Signs paged-artifact headers and assembles verified artifacts.
public enum PagedArtifactVerification {
    /// The pages, each with its inclusion proof, and the header for them.
    public static func paginate(
        _ pages: [[UInt8]], artifactType: String, dataset: Identifier128, epoch: Identifier128, version: Int64
    ) throws -> (header: PagedArtifactHeader, pages: [PagedArtifactPage]) {
        let header = try PagedArtifactHeader(
            artifactType: artifactType, datasetID: dataset, epochID: epoch, version: version,
            pageCount: Int64(pages.count), merkleRoot: MerkleTree.root(of: pages))
        let wire = try pages.indices.map { index in
            try PagedArtifactPage(
                index: Int64(index), bytes: pages[index], proof: MerkleTree.inclusionProof(index: index, pages: pages))
        }
        return (header, wire)
    }

    /// Core's signature over a header body.
    public static func signHeader(_ header: PagedArtifactHeader, with signer: some MessageSigning) throws
        -> (body: [UInt8], signature: [UInt8])
    {
        let body = try header.canonicalBody()
        return (body, try DomainSignatures.sign(body, domain: .pagedArtifactHeader, with: signer))
    }

    /// The artifact's pages in order, only if the header signature is Core's, the header names the expected type,
    /// dataset and epoch, every index from 0 to the page count is present exactly once, and every page verifies at
    /// its index against the signed root. A dropped, repeated, altered or reordered page refuses the whole artifact.
    public static func assemble(
        headerBody: [UInt8], headerSignature: [UInt8], pages: [PagedArtifactPage], coreKey: P256Verifier,
        expectedType: String, dataset: Identifier128, epoch: Identifier128
    ) throws(PagedArtifactError) -> (header: PagedArtifactHeader, pages: [[UInt8]]) {
        guard DomainSignatures.isValid(headerSignature, over: headerBody, domain: .pagedArtifactHeader, by: coreKey)
        else { throw .invalidHeaderSignature }
        let header: PagedArtifactHeader
        do {
            header = try PagedArtifactHeader.decode(body: headerBody)
        } catch {
            throw .malformedHeader(error)
        }
        guard header.artifactType == expectedType, header.datasetID == dataset, header.epochID == epoch else {
            throw .unexpectedArtifact
        }
        guard Int64(pages.count) == header.pageCount else { throw .incompletePages }
        var ordered = [[UInt8]?](repeating: nil, count: pages.count)
        for page in pages {
            guard page.index < header.pageCount, ordered[Int(page.index)] == nil else { throw .incompletePages }
            guard
                MerkleTree.verifyInclusion(
                    page: page.bytes, index: page.index, treeSize: header.pageCount, proof: page.proof,
                    root: header.merkleRoot)
            else { throw .pageNotIncluded(index: page.index) }
            ordered[Int(page.index)] = page.bytes
        }
        return (header, ordered.compactMap { $0 })
    }
}
