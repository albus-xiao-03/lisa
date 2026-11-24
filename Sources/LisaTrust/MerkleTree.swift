// The Merkle tree binding a paged artifact's ordered pages (plan §8.1.3): RFC 6962 hashing and tree shape, with
// inclusion proofs verified by the algorithm of RFC 9162 §2.1.3.2.

import Foundation
import LisaCrypto
import LisaSyncProtocol

/// RFC 6962 Merkle trees over ordered pages: leaf `SHA-256(0x00 ‖ page)`, node `SHA-256(0x01 ‖ left ‖ right)`, and
/// for n > 1 pages the left subtree holds the largest power of two smaller than n.
public enum MerkleTree {
    public static func leafHash(_ page: [UInt8]) -> [UInt8] { sha256([0x00] + page) }

    static func nodeHash(_ left: [UInt8], _ right: [UInt8]) -> [UInt8] { sha256([0x01] + left + right) }

    static func sha256(_ bytes: [UInt8]) -> [UInt8] { [UInt8](Digests.sha256(Data(bytes))) }

    /// The largest power of two smaller than `n` (for n ≥ 2).
    static func split(_ n: Int) -> Int {
        var k = 1
        while k * 2 < n { k *= 2 }
        return k
    }

    /// The root over leaf hashes `leaves[range]`.
    static func root(leaves: ArraySlice<[UInt8]>) -> [UInt8] {
        if leaves.count == 1 { return leaves[leaves.startIndex] }
        let k = split(leaves.count)
        let middle = leaves.startIndex + k
        return nodeHash(root(leaves: leaves[leaves.startIndex..<middle]), root(leaves: leaves[middle...]))
    }

    /// The root of one or more pages.
    /// - Precondition: `pages` is not empty.
    public static func root(of pages: [[UInt8]]) -> Digest256 {
        precondition(!pages.isEmpty, "a paged artifact has at least one page")
        // A SHA-256 value is always 32 bytes.
        return try! Digest256(bytes: root(leaves: ArraySlice(pages.map(leafHash))))
    }

    /// The inclusion proof of page `index`, leaf side first (RFC 6962 `PATH`).
    public static func inclusionProof(index: Int, pages: [[UInt8]]) -> [Digest256] {
        precondition(pages.indices.contains(index))
        return path(index, ArraySlice(pages.map(leafHash))).map { try! Digest256(bytes: $0) }
    }

    static func path(_ m: Int, _ leaves: ArraySlice<[UInt8]>) -> [[UInt8]] {
        if leaves.count == 1 { return [] }
        let k = split(leaves.count)
        let middle = leaves.startIndex + k
        if m < k {
            return path(m, leaves[leaves.startIndex..<middle]) + [root(leaves: leaves[middle...])]
        }
        return path(m - k, leaves[middle...]) + [root(leaves: leaves[leaves.startIndex..<middle])]
    }

    /// Whether `page` is the page at `index` of a tree of `treeSize` pages with root `root`, given its proof
    /// (RFC 9162 §2.1.3.2).
    public static func verifyInclusion(
        page: [UInt8], index: Int64, treeSize: Int64, proof: [Digest256], root: Digest256
    ) -> Bool {
        guard index >= 0, index < treeSize else { return false }
        var fn = UInt64(index)
        var sn = UInt64(treeSize - 1)
        var r = leafHash(page)
        for p in proof {
            if sn == 0 { return false }
            if fn & 1 == 1 || fn == sn {
                r = nodeHash(p.bytes, r)
                if fn & 1 == 0 {
                    while fn & 1 == 0 && fn != 0 {
                        fn >>= 1
                        sn >>= 1
                    }
                }
            } else {
                r = nodeHash(r, p.bytes)
            }
            fn >>= 1
            sn >>= 1
        }
        return sn == 0 && r == root.bytes
    }
}
