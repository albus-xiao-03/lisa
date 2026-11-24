// Signing change pages and checking them on arrival (plan §8.4.2): Core signs a page's exact canonical body under the
// change-page domain; a holder accepts only Core's valid signature over a well-formed page of its own dataset, before
// any entry is looked at. Each entry's operation is still verified on its own when it is applied.

import LisaCrypto
import LisaSyncProtocol

/// Why a change page was refused before any entry was applied.
public enum ChangePageVerificationError: Error, Hashable, Sendable {
    case malformed(OperationEnvelopeError)
    case wrongDataset
    case invalidSignature
}

/// Signs and verifies change pages.
public enum ChangePageSigning {
    public static func sign(_ page: ChangePage, with core: some MessageSigning) throws -> SignedChangePage {
        let body = try page.canonicalBody()
        return try SignedChangePage(
            body: body, signature: try DomainSignatures.sign(body, domain: .changePage, with: core))
    }

    /// Decodes and verifies an arriving page against Core's signing key from the verified key history.
    public static func verify(_ signed: SignedChangePage, dataset: Identifier128, coreKey: P256Verifier)
        throws(ChangePageVerificationError) -> ChangePage
    {
        guard DomainSignatures.isValid(signed.signature, over: signed.body, domain: .changePage, by: coreKey) else {
            throw .invalidSignature
        }
        let page: ChangePage
        do {
            page = try signed.page()
        } catch {
            throw .malformed(error)
        }
        guard page.datasetID == dataset else { throw .wrongDataset }
        return page
    }
}
