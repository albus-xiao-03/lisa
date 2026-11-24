<!-- The R2 synchronization protocol as implemented (plan §8.2, §8.16, §8.1, §8.7): canonical encoding, identifiers, budgets, signing domains, owner texts and the nearby session layer, with test vectors. Grows with each milestone; sections not yet implemented say so. -->
# Lisa R2 — Synchronization protocol

This document specifies Lisa R2's wire formats as `LisaSyncProtocol` and `LisaTrust` implement them, with the test vectors the temporary harnesses check (`docs/VERIFICATION-SCENARIOS.md`). The design is `plans/R2.md` revision 13; where the plan fixes a byte, this document repeats it, and where it leaves an encoding open, this document defines it. **Status:** M1, in progress. Receipts, change pages, rosters, lineage, enrollment messages, challenges and frames are added as they are implemented.

## 1. Canonical JSON (plan §8.16.1)

Every signed body is one canonical JSON value (`CanonicalEncoder`, `CanonicalDecoder`):
- **UTF-8.** Invalid UTF-8 is refused: overlong forms, encoded surrogates, values above U+10FFFF, truncated and stray bytes.
- **Objects:** keys sorted by Unicode scalar value (not UTF-16 code unit, unlike RFC 8785), each key unique. Keys that are canonically equivalent but spelled differently (for example U+00E9 and U+0065 U+0301) are refused as duplicates, because consumers that compare strings by canonical equivalence would merge them.
- **No whitespace** anywhere, including around the top-level value.
- **Integers only,** in the signed 64-bit range: no fraction, exponent, leading zero, `+` or `-0`. Instants are Unix milliseconds; decimals travel as strings.
- **Minimal escaping:** `\"`, `\\`, `\b`, `\f`, `\n`, `\r`, `\t`; `\u00xx` with lowercase hexadecimal for the other characters below U+0020; every other character, U+007F, U+2028 and astral characters included, as its raw UTF-8 bytes. `\/`, `A`, uppercase hexadecimal and escaped surrogate pairs are not canonical.
- **Nesting:** at most 16 arrays and objects deep; a top-level container is at depth 1.
- **Strictness:** the decoder refuses anything that does not re-encode to the identical bytes, so every value has exactly one accepted encoding. Signed bodies are never re-encoded: signatures and digests cover the received bytes.
- **Equality** of decoded values is byte-exact: two strings are equal only when their UTF-8 bytes are.

**Vectors**
- Key order: an object with keys `😀` (U+1F600), U+E000, `é`, `z`, `a`, `Z` encodes as `{"Z":…,"a":…,"z":…,"é":…,"\u{E000}":…,"😀":…}`. Under UTF-16 order U+1F600 would come before U+E000.
- Escapes: the string `q"b\` + U+0008 U+000C U+000A U+000D U+0009 U+0001 U+001F + U+007F `é日😀` U+2028 `/` encodes as `"q\"b\\\b\f\n\r\t\u0001\u001f` followed by the raw bytes `7f c3a9 e697a5 f09f9880 e280a8 2f` and `"`.
- Integers: `[0,-1,9223372036854775807,-9223372036854775808]` is canonical; `9223372036854775808`, `-9223372036854775809`, `01`, `-0`, `1.0`, `1e3` and `+1` are refused.
- Size: an operation body of exactly 65,536 bytes is accepted; 65,537 is refused before parsing.

## 2. Binary values and identifiers

- **Bytes** travel inside JSON as unpadded base64url (RFC 4648 §5, `StrictBase64URL`). Decoding refuses padding, characters outside the alphabet, a length ≡ 1 (mod 4) and non-zero unused trailing bits. Vectors: RFC 4648's `f`→`Zg`, `fo`→`Zm8`, `foo`→`Zm9v`, `foob`→`Zm9vYg`, `fooba`→`Zm9vYmE`, `foobar`→`Zm9vYmFy`; bytes `00 01 … 1f` → `AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8`.
- **Identifiers** (`Identifier128`): datasets, epochs, devices, enrollments, incarnations and operations are random 128-bit values, written as exactly 32 lowercase hexadecimal digits. Key derivations use their 16 raw bytes.
- **Digests** (`Digest256`): SHA-256 values, fingerprints and pins, written as exactly 64 lowercase hexadecimal digits.
- **Public keys:** P-256 keys travel as canonical DER SubjectPublicKeyInfo (`id-ecPublicKey`, named curve secp256r1, uncompressed point), 91 bytes, which must re-encode byte for byte; a compressed point, an extra byte, another curve or a point off the curve is refused. A key's fingerprint is SHA-256 of those 91 bytes.

## 3. Transfer budgets (plan §8.16.2)

Checked separately, each on encoded bytes (`TransferBudgets`):

| Unit | Limit |
|---|---|
| One canonical operation body, metadata included | 65,536 bytes |
| One batch | at most 100 operations and 524,288 bytes of bodies plus one 64-byte signature each |
| One HTTP request body (JSON envelope with base64url bodies) | 786,432 bytes |
| One nearby frame, its 8-byte header included | 1,048,576 bytes, checked from the header before allocation |
| Declared dependencies of one operation | 32 |

Vectors: each limit is accepted exactly and refused one unit over; eight 65,472-byte bodies with their signatures fill a batch exactly.

## 4. Signatures (plan §8.16.1)

A signature is a raw 64-byte P-256 ECDSA value (`r ‖ s`) over a signing domain's ASCII prefix followed by the exact body. Domains in use:

| Domain prefix | Signs |
|---|---|
| `lisa-r2-op\n` | A device operation (plan §8.2.1, fixed by the plan) |
| `lisa-r2-enroll-request-v1\n` | A device's enrollment request (§8.1.2 step 4) |
| `lisa-r2-enroll-result-v1\n` | Core's enrollment result (§8.1.2 step 5.7) |
| `lisa-r2-tls-anchors-v1\n` | Core's token-free TLS anchors bundle (§8.1.2 step 3) |
| `lisa-nearby-auth-v1\n` | Each side's nearby authentication transcript (§8.7) |
| `lisa-r2-paged-artifact-v1\n` | The header of a paged artifact (§8.1.3) |

A signature under one domain never verifies under another, and a body differing by one byte never verifies.

## 5. Enrollment token (plan §8.1.2 step 1)

The token is 32 random bytes, carried as unpadded base64url; any other length is refused. Core stores only `tokenHash = SHA-256(ASCII "lisa-enroll-token-v1" ‖ 0x00 ‖ token)`. **Vector:** token `00 01 … 1f`; hash `e74f49bf65f5c648421c64994582a9b22ef0f1ab253fefaceb1241f83fe313db`; text `AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8`. Python's `hashlib` reproduces the hash.

## 6. Owner texts (plan §8.1.2 step 2)

`lisa-pair:4:` (pairing) and `lisa-reanchor:2:` (re-anchoring after loss of Core's signer) share one rule (`OwnerTextCodec`):
1. The whole text is at most 4,096 bytes of ASCII, checked before decoding.
2. An earlier format (`lisa-pair:1:`–`3:`, `lisa-reanchor:1:`) is refused as outdated, so the device asks the owner for current text before sending any token or changing trust. Any other prefix is refused.
3. After the prefix comes unpadded base64url of a canonical JSON object with `version` equal to the prefix's version and `checksum`.
4. `checksum` is unpadded base64url of the first four bytes of SHA-256 over the ASCII prefix (through its final colon) followed by the canonical object without `checksum`.
5. Missing, unknown or mistyped fields are refused, as is a wrong checksum.
6. `coreSigningSPKI` is the canonical DER of Core's signing key (§2) and `coreSigningFingerprint` its SHA-256 in 64 lowercase hexadecimal digits; the key must parse, re-encode identically and hash to that fingerprint. Only this key verifies Core's application signatures during enrollment and re-anchoring.

**`lisa-pair:4:` fields:** `caDigest` (`ca` mode only; SHA-256 of the owner CA certificate's DER), `coreSigningFingerprint`, `coreSigningSPKI`, `coreURL` (`https`, a host, optionally a port and `/`; no credentials, path, query or fragment), `datasetID`, `enrollmentID`, `expiresAt` (Unix milliseconds), `leafPin` (SHA-256 of the TLS leaf's SubjectPublicKeyInfo), `token`, `trustMode` (`ca` or `pin`), `version` (4), `checksum`.

**`lisa-reanchor:2:` fields:** `confirmationDigest` (SHA-256 of the exact signed confirmation), `confirmationSequence` (≥ 0), `coreSigningFingerprint`, `coreSigningSPKI`, `datasetID`, `deviceID` (the target device), `epochID`, `proofDigest` and `proofLength` (> 0) of the public proof transferred beside the text, `version` (2), `checksum`.

**Shared fixture** for the Core CLI and every device parser. Synthetic values: the signing key is the P-256 scalar `01 02 … 20`, the token is the vector above.
- `coreSigningSPKI`: `MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEUVw9brnjlrkE0_7Kf1T9zQzB6Ze_N13KUVrQpsO0A19FNr46UPMY-_mlR1kCoiFQK-8NV-CMU7LMClbxfZ-TVA`
- `coreSigningFingerprint`: `f1d59449b727165de732bf283338122b99628a615918fedc67d878fffcf47da7`
- Other fields: `coreURL` `https://lisa-core.example.invalid:8443`, `trustMode` `pin`, `leafPin` `abab…ab` (32 bytes of `ab`), `datasetID` `00112233445566778899aabbccddeeff`, `enrollmentID` `ffeeddccbbaa99887766554433221100`, `expiresAt` `1795510000000`.
- The text:

```
lisa-pair:4:eyJjaGVja3N1bSI6Ik9yaWNoQSIsImNvcmVTaWduaW5nRmluZ2VycHJpbnQiOiJmMWQ1OTQ0OWI3MjcxNjVkZTczMmJmMjgzMzM4MTIyYjk5NjI4YTYxNTkxOGZlZGM2N2Q4NzhmZmZjZjQ3ZGE3IiwiY29yZVNpZ25pbmdTUEtJIjoiTUZrd0V3WUhLb1pJemowQ0FRWUlLb1pJemowREFRY0RRZ0FFVVZ3OWJybmpscmtFMF83S2YxVDl6UXpCNlplX04xM0tVVnJRcHNPMEExOUZOcjQ2VVBNWS1fbWxSMWtDb2lGUUstOE5WLUNNVTdMTUNsYnhmWi1UVkEiLCJjb3JlVVJMIjoiaHR0cHM6Ly9saXNhLWNvcmUuZXhhbXBsZS5pbnZhbGlkOjg0NDMiLCJkYXRhc2V0SUQiOiIwMDExMjIzMzQ0NTU2Njc3ODg5OWFhYmJjY2RkZWVmZiIsImVucm9sbG1lbnRJRCI6ImZmZWVkZGNjYmJhYTk5ODg3NzY2NTU0NDMzMjIxMTAwIiwiZXhwaXJlc0F0IjoxNzk1NTEwMDAwMDAwLCJsZWFmUGluIjoiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYiIsInRva2VuIjoiQUFFQ0F3UUZCZ2NJQ1FvTERBME9EeEFSRWhNVUZSWVhHQmthR3h3ZEhoOCIsInRydXN0TW9kZSI6InBpbiIsInZlcnNpb24iOjR9
```

Its checksum is `OrichA`. Checked independently of Lisa's code: OpenSSL parses the SPKI as a P-256 key, and Python reproduces the fingerprint, the canonical payload and the checksum.

**Refusal vectors** (each built through the public codec, so only the stated rule differs): a 4,097-byte text, non-ASCII, `lisa-pair:3:`, a `lisa-reanchor:2:` prefix on pairing content, inner version 3 under `lisa-pair:4:`, a trailing `=`, whitespace in the JSON, a checksum computed under another prefix, an extra field `note`, a missing `token`, another key's fingerprint, an SPKI with an extra byte, a point moved off the curve, an uppercase fingerprint, `ca` mode without `caDigest` or `pin` mode with one, and an `http`, credentialed, pathed or query-bearing URL.

## 7. Nearby session layer (plan §8.7)

- **Hello** (`NearbyHello`): protocol version 1, device ID, roster epoch and version, confirmed head (a `Digest256`), and a 32-byte nonce.
- **Authentication:** each side signs, under `lisa-nearby-auth-v1\n`, the canonical object
  `{"exporter": <32 bytes, base64url>, "head": <signer's head>, "initiator": {"deviceID", "nonce"}, "protocolVersion": 1, "responder": {"deviceID", "nonce"}, "rosterEpoch": <signer's>, "rosterVersion": <signer's>, "signer": "initiator" | "responder"}`.
  The exporter is the TLS exporter value with label `EXPORTER-lisa-nearby-v1`, 32 bytes, so a relay that terminates two sessions presents a different value on each and both signatures fail. Each side verifies the other's signature with the operation key from its newest roster; an unknown or revoked device has none. The two hellos must name different devices.
- **Design A derivations** (`NearbyPairKeys`):
  - pair key `K_ij = HKDF-SHA256(ECDH(i, j), salt = dataset ID bytes, info = "lisa-nearby-psk-v1" ‖ lower device ID ‖ higher device ID)`, 32 bytes, with the IDs' 16 raw bytes ordered bytewise, so both devices derive the same key;
  - window = Unix seconds ÷ 900, as 8 bytes big-endian;
  - discovery tag = the first 16 bytes of `HMAC-SHA256(discovery secret, "lisa-disc-v1" ‖ window ‖ device ID)`;
  - rejoin identity = the first 16 bytes of `HMAC-SHA256(K_ij, "lisa-rejoin-v1" ‖ window)`.

  **Vectors** (reproduced with Python's `hmac`): discovery secret `00 01 … 1f`, window 2,000,000 (Unix second 1,800,000,000), device ID `00 01 … 0f` → tag `218c28976c2415b1d21ea358c0878b45`; pair key `20 21 … 3f`, window 2,000,000 → rejoin identity `c4267b18478e985a535b7512bbf4758b`.
- **Frames:** 8-byte header and payload within the frame budget (§3); the header layout is specified when M6 implements the frames.

## 8. Operation envelope (plan §8.2.1–§8.2.3, §8.3.2, §8.3.3)

An operation's signed body is one canonical JSON object (`OperationEnvelope`) of at most 65,536 bytes:

| Field | Content |
|---|---|
| `protocolVersion` | `2` |
| `schemaVersion`, `policyVersion` | Integers ≥ 1 |
| `datasetID`, `operationID` | Identifiers. A device's operation ID is random and stable for the logical action; a legacy child's is derived (below) |
| `origin` | `{"kind": "device", "deviceID", "incarnationID", "sequence" (≥ 1), "previous"?: {"incarnationID", "lastSequence"}}`, where `previous` may appear only on sequence 1; or `{"kind": "coreLegacyTranslation"}` |
| `entity` | `{"type", "id"}`, the type from the catalog (`OperationCatalog`) |
| `type` | The operation type, `<entity>.<action>` from the catalog (§8.2.3) |
| `payload` | The type's payload; opaque to the envelope codec until each type's schema is implemented |
| `dependencies` | At most 32 operation IDs, strictly ascending, never the operation's own ID |
| `observed` | Optional: `{"pieces": [≤ 256 IDs, strictly ascending], "horizon"?: {"epochID", "partition", "position"}, "reviewedSetDigest"?, "group"?: {"groupID", "index", "count", "listDigest"}}` |
| `legacyParent` | Only on Core legacy children: `{"scope", "requestID" (R1's 8–128-character alphabet), "discriminator", "index" (in 0..<count), "count", "setDigest"}` |
| `createdAt` | Unix milliseconds, display and audit only; required on device operations, absent on legacy children |

- **Malformed, refused before any payload is read:** a device operation carrying `legacyParent` or lacking `createdAt`, a legacy child lacking `legacyParent` or carrying `createdAt`, too many, unsorted or self dependencies, too many or unsorted observed pieces, a `previous` link after sequence 1, an unknown type, an unknown field, another protocol version, a non-canonical or oversized body.
- **Digest:** SHA-256 over the complete canonical signed body (`OperationDigest`). **Signature:** raw 64 bytes over `lisa-r2-op\n` ‖ body, not part of the digest (`OperationSigning`). Verification refuses a malformed body, another dataset, an origin without a key in the holder's roster (unknown or revoked), a forged signature, and a legacy child not signed by Core's key.
- **Duplicates,** everywhere (`OperationIdentityCheck`): the same ID and digest is `duplicate`; the same ID with another digest is `identity_reuse`; the same `(device, incarnation, sequence)` under another ID is `sequence_reuse`.
- **Legacy child identity** (`LegacyChildIdentity`, plan §8.12.2): the child ID is the first 16 bytes of `SHA-256("lisa-v1-child-v1" ‖ 0x00 ‖ len32(dataset) ‖ dataset ‖ len32(scope) ‖ scope ‖ len32(requestID) ‖ requestID ‖ len32(discriminator) ‖ discriminator)`, with `len32` a 32-bit big-endian length, the dataset as its 16 raw bytes and the strings as UTF-8; `setDigest` is SHA-256 of the ordered child IDs' raw bytes. **Vectors** (reproduced with Python's `hashlib`), dataset `00112233445566778899aabbccddeeff`, scope `device:0123`, request ID `req-00000001`: discriminator `change:0` → `80d40d4a935c024d740fdc1f05dbbeb7`; `change:1` → `8fe937c75d3c10b783f520badee69ace`; set digest of the two → `eb8d5c08cc6253fb04b7d28287d5fede7f305878525c0212ea3c7526a11778d1`.
- **Value budget** (`OperationValueBudget.maximumValueBytes(type)`): 65,536 − the encoded size of the type's largest envelope whose payload is `{"value":""}`, taking the larger of the device and legacy variants with every optional field at its maximum. The legacy variant is the larger. Results: `note.add` 53,982 bytes, `task.edit` 53,981, `capture.create` 53,976, `conflict.resolve` 53,974 (each type's name length is the only difference). A value of exactly that many encoded bytes, built from worst-case `\u00xx` escapes, fills the body to 65,536 bytes; one byte more is refused. Payload schemas with more fields subtract their own encoded overhead when they are defined.

## 9. Paged artifacts (plan §8.1.3, §8.4.3)

Rosters with key history, causal summaries, snapshot manifests and reviewed-set artifacts can span several pages:
- **Header** (`PagedArtifactHeader`), signed by Core under `lisa-r2-paged-artifact-v1\n`: `{"artifactType", "datasetID", "epochID", "version", "pageCount" (≥ 1), "merkleRoot"}`.
- **Pages** (`PagedArtifactPage`): `{index, bytes (at most 524,288), proof}`, the proof being the inclusion path, leaf side first.
- **Tree** (`MerkleTree`): RFC 6962. Leaf `SHA-256(0x00 ‖ page)`, node `SHA-256(0x01 ‖ left ‖ right)`; for n > 1 pages the left subtree holds the largest power of two below n. Proofs are RFC 6962's audit path, verified by RFC 9162 §2.1.3.2.
- **Acceptance** (`PagedArtifactVerification.assemble`): Core's header signature, the expected type, dataset and epoch, exactly `pageCount` pages with every index once, and every page verified at its index against the signed root. A dropped, repeated, swapped or altered page, a forged header or another dataset refuses the whole artifact. The proof does not authenticate the tree size (RFC 9162's algorithm accepts some size-n proofs under size n + 1), so the size is always taken from the signed header.
- **Vectors** (pages are the ASCII strings `page-0`, `page-1`, …; reproduced with an independent Python implementation): roots for 1, 2, 3, 5, 7 and 8 pages: `db4a76ac8c461b45ae3bff430d7cac5c8f7ca6a24ed61f00c2cc3ac7d9cea390`, `9f986a9a86251bd8ca7582421873166e5bb6baaa0d5846f767b70c6d91127db2`, `e8cf1716052692337c090ad09676ed22f277f56547aa42a8d566439a0a42adbe`, `4b51c34223a04defb1dee194c7a543843ff28d4886c008c09f7506ce38a93f7a`, `87f45200cc7e94818a4341e9f82fdd3d333be87069a21fdb36b28c41152e2709`, `5de10b435c206d44950064dc0ac4d84cad4e608bbff864ebc3dddd62f296bf77`. The proof of page 5 in 7 pages is `dc4e1dfabb0f278819e31d357612c989b62f153a51f4e707c7f4aaedb23f838b`, `1afc45a4da64f47b7f7be075c1e01de71ee14aaabb9adf448674dc790c60cf91`, `ecfaf8a423d8a78f097fdaa35167814e8abbeef186835e034e8057ebe98ecc47`; of page 4 in 5 pages, the last of those alone.

## 10. Not yet specified here

Receipts, dependency release, change pages and interval coverage, snapshots and chunks, manifests, blobs, rosters and revocation, lineage and confirmations, enrollment request and result bodies, challenges, assignments and reports, legacy import items, the protected archive format and nearby frames. Each is added with its vectors when its milestone implements it.
