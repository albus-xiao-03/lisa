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
| `lisa-r2-archive-v1\n` | A protected archive's header and ciphertext digests (§8.6.6) |
| `lisa-r2-change-page-v1\n` | Core's change page over its canonical body (§8.4.2; §8a) |
| `lisa-r2-custody-v1\n` | A peer's custody acknowledgement over its canonical body (§8.6.1, §8.7; §8c) |
| `lisa-r2-receipt-v1\n` | Core's receipt for one operation over its canonical body (§8.2.1; §8d) |
| `lisa-r2-device-authorization-v1\n` | Core's authorization record for one device, returned at enrollment (§8.1.2 step 5.7; §8f) |
| `lisa-r2-credential-reset-v1\n` | A device's credential-reset request, signed by its existing operation key (§8.1.4; §8g) |
| `lisa-r2-key-transition-v1\n` | A transition in Core's signing-key history, signed by both its keys (§8.1.4; §8h) |
| `lisa-r2-device-key-update-v1\n` | A device's operation-key update, signed by both its keys (§8.1.4; §8i) |

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

- **Hello** (`NearbyHello`): protocol version 1, device ID, roster epoch and version, confirmed head (a `Digest256`), and a 32-byte nonce. **Wire form:** canonical JSON of at most 4 KiB, `{"deviceID", "head", "nonce" (base64url), "protocolVersion": 1, "rosterEpoch", "rosterVersion"}`, decoded strictly (another protocol version, an unknown or missing member, a wrong length or a non-canonical form is refused). **Vector** (reproduced with Python's `json` and `base64`): device ID `00 01 … 0f`, epoch `10 11 … 1f`, version 7, head `20 21 … 3f`, nonce `40 41 … 5f` → `{"deviceID":"000102030405060708090a0b0c0d0e0f","head":"202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f","nonce":"QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl8","protocolVersion":1,"rosterEpoch":"101112131415161718191a1b1c1d1e1f","rosterVersion":7}` (262 bytes).
- **Authentication:** each side signs, under `lisa-nearby-auth-v1\n`, the canonical object
  `{"exporter": <32 bytes, base64url>, "head": <signer's head>, "initiator": {"deviceID", "nonce"}, "protocolVersion": 1, "responder": {"deviceID", "nonce"}, "rosterEpoch": <signer's>, "rosterVersion": <signer's>, "signer": "initiator" | "responder"}`.
  The exporter is the TLS exporter value with label `EXPORTER-lisa-nearby-v1`, 32 bytes, so a relay that terminates two sessions presents a different value on each and both signatures fail. Each side verifies the other's signature with the operation key from its newest roster; an unknown or revoked device has none. The two hellos must name different devices.
- **Design A derivations** (`NearbyPairKeys`):
  - pair key `K_ij = HKDF-SHA256(ECDH(i, j), salt = dataset ID bytes, info = "lisa-nearby-psk-v1" ‖ lower device ID ‖ higher device ID)`, 32 bytes, with the IDs' 16 raw bytes ordered bytewise, so both devices derive the same key;
  - window = Unix seconds ÷ 900, as 8 bytes big-endian;
  - discovery tag = the first 16 bytes of `HMAC-SHA256(discovery secret, "lisa-disc-v1" ‖ window ‖ device ID)`;
  - rejoin identity = the first 16 bytes of `HMAC-SHA256(K_ij, "lisa-rejoin-v1" ‖ window)`.

  **Vectors** (reproduced with Python's `hmac`): discovery secret `00 01 … 1f`, window 2,000,000 (Unix second 1,800,000,000), device ID `00 01 … 0f` → tag `218c28976c2415b1d21ea358c0878b45`; pair key `20 21 … 3f`, window 2,000,000 → rejoin identity `c4267b18478e985a535b7512bbf4758b`.
- **Frames** (`NearbyFrameHeader`): an 8-byte header, then the payload; the whole frame is at most 1 MiB (§3). Header bytes 0–3: the total length including the header, unsigned big-endian, 8 to 1,048,576; byte 4: the kind (the session layer's registry, M6); byte 5: header version 1; bytes 6–7: zero. A receiver reads exactly 8 bytes and refuses a total outside the budget, another version or non-zero reserved bytes before reading or allocating the payload. Example: kind 3 with a 5-byte payload → `00 00 00 0d 03 01 00 00`; the largest frame's header → `00 10 00 00 <kind> 01 00 00`.

## 8. Operation envelope (plan §8.2.1–§8.2.3, §8.3.2, §8.3.3)

An operation's signed body is one canonical JSON object (`OperationEnvelope`) of at most 65,536 bytes:

| Field | Content |
|---|---|
| `protocolVersion` | `2` |
| `schemaVersion`, `policyVersion` | Integers ≥ 1 |
| `datasetID`, `operationID` | Identifiers. A device's operation ID is random and stable for the logical action; a legacy child's is derived (below) |
| `origin` | `{"kind": "device", "deviceID", "incarnationID", "sequence" (≥ 1), "previous"?: {"incarnationID", "lastSequence"}}`, where `previous` may appear only on sequence 1; or `{"kind": "coreLegacyTranslation", "incarnationID", "sequence" (≥ 1)}`, the incarnation derived from the request and the sequence the child's index plus one (§8j) |
| `entity` | `{"type", "id"}`, the type from the catalog (`OperationCatalog`) |
| `type` | The operation type, `<entity>.<action>` from the catalog (§8.2.3) |
| `payload` | The type's payload. The schemas implemented so far are below ("Item payloads"); other types' payloads stay opaque to the envelope codec until theirs are |
| `dependencies` | At most 32 operation IDs, strictly ascending, never the operation's own ID |
| `observed` | Optional: `{"pieces": [≤ 256 IDs, strictly ascending], "horizon"?: {"epochID", "partition", "position"}, "reviewedSetDigest"?, "group"?: {"groupID", "index", "count", "listDigest"}}`. On a legacy child only: `{"pieces": [], "projectionRevision": N}`, R1's `expectedRevision` ("observed at projection revision N", ≥ 1), alone (§8j) |
| `legacyParent` | Only on Core legacy children: `{"scope", "requestID" (R1's 8–128-character alphabet), "discriminator", "index" (in 0..<count), "count", "setDigest"}` |
| `createdAt` | Unix milliseconds, display and audit only; required on device operations, absent on legacy children |

- **Malformed, refused before any payload is read:** a device operation carrying `legacyParent` or lacking `createdAt`, a legacy child lacking `legacyParent` or carrying `createdAt`, too many, unsorted or self dependencies, too many or unsorted observed pieces, a `previous` link after sequence 1, an unknown type, an unknown field, another protocol version, a non-canonical or oversized body.
- **Digest:** SHA-256 over the complete canonical signed body (`OperationDigest`). **Signature:** raw 64 bytes over `lisa-r2-op\n` ‖ body, not part of the digest (`OperationSigning`). Verification refuses a malformed body, another dataset, an origin without a key in the holder's roster (unknown or revoked), a forged signature, and a legacy child not signed by Core's key.
- **Duplicates,** everywhere (`OperationIdentityCheck`): the same ID and digest is `duplicate`; the same ID with another digest is `identity_reuse`; the same `(device, incarnation, sequence)` under another ID is `sequence_reuse`. On a replica the rules hold against every operation it knows: its journal, and canonical state from pages and full snapshots (canonical operations keep their origin triple for this). An operation known only canonically is a `duplicate` in Core's state, never a new journal entry.
- **Legacy child identity** (`LegacyChildIdentity`, plan §8.12.2): the child ID is the first 16 bytes of `SHA-256("lisa-v1-child-v1" ‖ 0x00 ‖ len32(dataset) ‖ dataset ‖ len32(scope) ‖ scope ‖ len32(requestID) ‖ requestID ‖ len32(discriminator) ‖ discriminator)`, with `len32` a 32-bit big-endian length, the dataset as its 16 raw bytes and the strings as UTF-8; `setDigest` is SHA-256 of the ordered child IDs' raw bytes. **Vectors** (reproduced with Python's `hashlib`), dataset `00112233445566778899aabbccddeeff`, scope `device:0123`, request ID `req-00000001`: discriminator `change:0` → `80d40d4a935c024d740fdc1f05dbbeb7`; `change:1` → `8fe937c75d3c10b783f520badee69ace`; set digest of the two → `eb8d5c08cc6253fb04b7d28287d5fede7f305878525c0212ea3c7526a11778d1`.
- **Value budget** (`OperationValueBudget.maximumValueBytes(type)`): 65,536 − the encoded size of the type's largest envelope whose payload is `{"value":""}`, taking the larger of the device and legacy variants with every optional field at its maximum. The legacy variant is the larger. Results: `note.add` 53,982 bytes, `task.edit` 53,981, `capture.create` 53,976, `conflict.resolve` 53,974 (each type's name length is the only difference). A value of exactly that many encoded bytes, built from worst-case `\u00xx` escapes, fills the body to 65,536 bytes; one byte more is refused. Payload schemas with more fields subtract their own encoded overhead when they are defined.

### Item payloads: the task family, notes, tags and deletion (plan §8.2.3, §8.3.2, §8.3.3)

`ItemOperationPayload` decodes each of these strictly. The rules:
- only the type's own fields are accepted;
- each value is checked by its rules;
- what an operation replaces, removes or reopens by observation is stated in its observed set (§8 above), never in its payload.

| Type | Payload | Rules |
|---|---|---|
| `task.create` | `{"confirmation","deadline","estimate","priority","splittable","title"}`, all six present | As `task.edit` per field; R1's defaults are the caller's (normal priority, not splittable) |
| `task.edit` | `{"field": <field>, "value": <value>}` | `title` 1–200 characters; `priority` `low`, `normal`, `high` or `urgent`; `deadline` a deadline or `null` to clear; `estimate` minutes ≥ 1 or `null`; `splittable` a boolean; `confirmation` `confirmed`, `possible` or `informational` |
| `task.complete`, `task.cancel`, `item.delete` | `{}` | The operation ID is the terminal action's or the deletion's identity |
| `task.reopen` | `{"reopens": [IDs]}` | 0–32 terminal-action operation IDs, strictly ascending; an unnamed one stays in effect. An empty list reopens the terminal actions its observed set covers, by ID or by commit position under its horizon; a v1 reopen observed at a projection revision is one (D-72) |
| `note.add`, `note.replaceObserved` | `{"text": <text>}` | Within the text budget below; an addition is non-empty. A replacement removes exactly the note pieces its observed set covers; an empty one adds nothing, so it clears them (R1's `notes: ""`, D-72) |
| `tags.change` | `{"change": "add" \| "remove", "tag": <tag>}` | One tag of 1–64 characters; a removal covers only additions of its own tag that its observed set covers |
| `conflict.resolve` | `{"field": <task field>, "value"?: <its value>}` | The value is read under the declared field. A single resolution carries its value; in a paged group (`observed.group`, pages numbered 1…count, each depending on the previous one) only the last page does. The candidates it resolves are its observed set |

- **A deadline** is `{"kind":"instant","at": <UTC milliseconds>, "zone"?: <IANA name>}` or `{"kind":"date","date":"YYYY-MM-DD"}`.
  - The date must exist in the Gregorian calendar, for example `2028-02-29` but not `2026-02-29`.
  - The zone is 1–64 bytes of `A–Z a–z 0–9 / _ + -`.
  - A date-only deadline never becomes an invented time (R1's `Deadline`).
- **A paged resolution group** (plan §8.3.2) applies atomically, as its last page observing every page's explicit candidates together with the last page's horizon.
  - It applies once all `count` pages are present: one group ID, one count, one field and one list digest.
  - The list digest must equal SHA-256 of the sorted, concatenated 16-byte IDs of every page.
  - Until then, or with a mismatch, it changes nothing. A missing page leaves the later pages waiting under the dependency rules, and a candidate outside the list stays as a new conflict.
- **A task operation must name a task:** `task.*` with another entity type is malformed. The replica store applies these checks both to its own saves and to arriving operations, refusing the latter as `malformed`.
- **The note text budget:** a note's text may take `ItemOperationPayload.maximumTextBytes(type)` encoded bytes, measured after canonical escaping and excluding the quotes. That is the type's value budget plus one, because `{"text":…}` is one byte shorter than the budget's reference `{"value":…}`.
  - For `note.add` it is 53,983 bytes.
  - It is checked on the encoded length before anything larger is built.
  - A text that doesn't fit becomes a blob (§8.3.3), when blobs are implemented.
- **Vectors** (canonical payload bytes; harness v15 round-trips each through the decoder):
  - `task.create`, title "Call the dentist", priority high, due 2026-12-01, 30 minutes: `{"confirmation":"confirmed","deadline":{"date":"2026-12-01","kind":"date"},"estimate":30,"priority":"high","splittable":false,"title":"Call the dentist"}`
  - `task.edit` deadline: `{"field":"deadline","value":{"at":1795550000000,"kind":"instant","zone":"Europe/Berlin"}}`
  - `task.edit` clearing the estimate: `{"field":"estimate","value":null}`
  - `task.reopen`: `{"reopens":["00000000000000000000000000000001","00000000000000000000000000000002"]}`
  - `note.add`: `{"text":"Bring the referral"}`
  - `tags.change`: `{"change":"remove","tag":"health"}`
  - `task.complete`, `task.cancel`, `item.delete`: `{}`
- **Merged state** (`LisaMerge.TaskMergeState`, `docs/CONFLICTS.md`): one register per field, note pieces, one observed-remove set per tag, terminal actions and the tombstone.

### Preference payloads (plan §8.2.3; `docs/DECISIONS.md` D-73)

A preference is a register per key: entity type `preference`, partition `preferences`. The entity ID is the first 16 bytes of `SHA-256("lisa-preference-key-v1" ‖ 0x00 ‖ key)`. Vectors from Python's hashlib:
- `brief.time` → `9a1618a9b65b1a60368ae340a3ed4727`;
- `model.endpoint` → `2a70184edc7d5c8486c4b5d12a20daf8`;
- `planning.windows` → `3c042116161cfd01f1c7cbcf443132c5`.

| Type | Payload | Rules |
|---|---|---|
| `preference.set` | `{"key": <key>, "value": <value>}` | `<value>` is `{"kind":"text","text"}`, `{"kind":"number","number"}`, `{"kind":"flag","flag"}` or `{"kind":"list","list":[strings]}`. A number is the shortest decimal text that reads back as the same finite value, in that one form (`0.8` → `"0.8"`, `15` → `"15.0"`). A list holds at most 256 strings |
| `preference.delete`, `preference.confirm` | `{"key": <key>}` | — |

- **A key** is 1–256 UTF-8 bytes without control characters. Whether a key and its value are supported is R1's rule, checked at Core.
- **The size:** the payload fits the type's value budget (§8.3.3).
- **The merge:** a set and a delete each replace the versions they observed, a delete writing no value. So a delete clears what it saw, and a later set re-creates the key. A confirmation confirms the model-authority values it observed.

## 8a. Change pages (plan §8.4.2)

A change page is one canonical JSON object of at most 512 KiB: `{"datasetID", "entries", "epochID", "fromPosition", "partitions", "toPosition"}` (`ChangePage`). Core signs it raw, over `lisa-r2-change-page-v1\n` ‖ body (`ChangePageSigning`), and relays forward the exact bytes (`SignedChangePage`).
- **The page:**
  - `partitions` is 1–256 names (1–128 bytes each), strictly ascending in Unicode scalar order.
  - `fromPosition` is ≥ 0 and `toPosition` is greater than it.
  - `entries` is strictly ascending by position. Every entry lies in `(from, to]` and touches at least one listed partition.
- **What a page proves:** for every partition it lists, the page's entries are all the entries in `(from, to]` touching that partition. A listed partition without entries is proved unchanged over the interval. A page is self-contained.
- **An operation entry** (`ChangeEntry`) is `{"decision", "operation": {"body", "signature"}, "partitions", "position"}`:
  - `decision` is `accepted`, `accepted_with_conflict` or `rejected` (every decision is an entry, §8.2.1);
  - the operation's exact signed bytes are base64url;
  - `partitions` is the 1–256 partitions it touches, strictly ascending;
  - `position` is ≥ 1.
  - `observedHorizon`, optional: `{"epochID", "partition", "position"}`, only on an `accepted` or `accepted_with_conflict` entry whose operation is a legacy child carrying a projection revision. It is the horizon Core resolved the revision to when it decided the child (§8j). An entry without one has exactly the bytes it had before the field existed.
  - The unwindowed collections' partitions are `tasks`, `ideas`, `captures`, `preferences`, `proposals`, `reminders` and `suggestions` (`CollectionPartition`).
- **A derived-record entry** is `{"partitions", "position", "record": {"id", "row": <row> | null, "type": "occurrence"}}`: a row Core computed, or its deletion (`DerivedRecord`, plan §8.3.5). It has no signature of its own; the Core-signed page or snapshot vouches for it.
  - **An occurrence row** (`OccurrenceRow`) is `{"civil"?, "expandedZone"?, "sourceID", "timing", "title"}`. The timing is either:
    - `{"kind":"timed","start","end","zone"}`, in UTC milliseconds with `end ≥ start`. The zone is `utc`, an IANA name, `floating`, or `unknown` (a TZID R1 didn't know, resolved like floating);
    - or `{"kind":"allDay","firstDate","endDate"}`, with the end exclusive.
  - **A floating or unknown-zone row moves with the zone.**
    - `expandedZone` names the zone its instants were expanded in.
    - `civil` holds its original civil times, `{"start","end"}` as `YYYY-MM-DDTHH:MM`, when retained. A migrated row may lack them.
  - **A zone proof** (`ZoneProof`, type `zoneProof`) is `{"firstBucket","generation","lastBucket","sourceID","zone"}`: Core holds the source's every occurrence expanded for that zone and generation over those buckets.
  - **Calendar partitions are UTC days, named `occurrences/<n>`** (`CalendarBuckets`). Bucket n covers `[n × 86,400,000, (n + 1) × 86,400,000)`.
  - **An occurrence belongs to every bucket its interval overlaps:**
    - a timed `[start, end)` covers each bucket it overlaps;
    - a zero-length event, its start's bucket;
    - all-day dates are widened by a day on each side, `day(first) − 1` through `day(end)`.
  - **Which buckets an entry names:** the buckets of the row's old and new ranges, so a move reaches the buckets it left. A deletion names the range the row last occupied.
- **On a replica** (`ReplicaStore.applyChangePage`):
  - **Verified whole first:** Core's signature, the page's form, the dataset, and every entry's operation by the roster (the replica's own device included). Anything invalid refuses the page, and nothing changes.
  - **Then, per listed partition with cursor `c`:**
    - under repair → deferred, and applied after the repair publishes;
    - `to ≤ c` → ignored;
    - `from ≤ c < to` → the entries in `(c, to]` are applied, and `c` becomes `to`;
    - `c < from` → a gap, and the cursor stays;
    - another epoch → refused for that partition;
    - no cursor → applied only if the page starts at 0.
  - **A derived record** changes its row only above the row's version. For each bucket it touches, it records whether that bucket's proof delivered the row, and at which version (a membership record).
  - **The absence rule:** a bucket lists a row whose range overlaps it when its own proof delivered the row at its current version, or when the row's version is above the bucket's cursor (delivered through another bucket, until this one catches up). Otherwise the row is absent from that bucket.
  - **A bucket repair** (§8.4.3) starts from a Core-signed paged artifact of type `bucket-snapshot`, whose version is the cut.
    - Its chunks name only that bucket and list its members as record entries, at most 512 per chunk.
    - A cut older than the bucket's cursor is refused, and another epoch abandons the repair.
    - The chunks are staged in the repair's own generation, invisible to readers. While the bucket is repairing, pages listing it are deferred for it.
    - **Publication** is one transaction of constant size. It re-checks the epoch, the cursor and the overlay watermark, then flips the bucket's published generation. Its membership is then exactly the snapshot's members, and its cursor is the cut.
    - Readers resolve each row to its newest version among published generations, so they see one view or the other.
    - The deferred pages then apply, each in its own transaction. Superseded generations are cleaned up in bounded chunks.
  - **A window roll** drops a bucket's cursor and memberships, and drops a row only when no covered bucket overlaps it.
  - **A local planning-zone change** (`setPlanningZone`) advances the coverage generation and marks every source with rows that move with the zone unverified, at once, even with Core offline. A source's mark clears for a bucket only with a zone proof of that source and zone covering it.
  - **A planning day** (`planningDay`) is read from its own UTC bounds:
    - all-day rows follow the date;
    - zoned and UTC rows keep their instants;
    - a floating row expanded in another zone, or from an unverified source, is shown unverified.
    - No free time is offered from an unverified, stale or repairing day.
  - **Each operation entry applies once,** and only when its position is above its row's version:
    - a committed entry joins canonical state, and the journal's copy, if any, records the commit and stops being an overlay;
    - a rejected entry leaves the view;
    - either way, its causal decision releases its dependents.
  - Nothing missing from a page is read as deleted.

## 8b. Full snapshots (plan §8.4.3, §8.6.3)

A full snapshot is a paged artifact (§9) of type `snapshot`, signed by Core. Its header's `version` is the cut, and its `epochID` is the snapshot's epoch.
- **Each page is a chunk** (`SnapshotChunk`): `{"entries", "partitions"}`.
  - `partitions` is the snapshot's coverage, the same on every chunk.
  - `entries` holds the committed operations of those partitions as change-log entries (§8a), with no rejections, strictly ascending by position, each at or below the cut.
- **On a replica** (`beginSnapshotInstallation`, `stageSnapshotChunk`, `buildStagedIndexStep`, `catchUpPass`, `installSnapshot`):
  - Each chunk is verified against the signed root at its index, and every operation by the roster, before it is staged in its own transaction.
  - At the installation point the backlog is evaluated first. Over 2,048 local changes, a cursor beyond the cut, another epoch, or a covered partition the snapshot doesn't cover each invalidate the staging, applying nothing.
  - Otherwise the staged canonical tables and index are swapped in together, with the cursors at the cut.
  - A chunk that isn't included under the root is refused, and an incomplete set of chunks doesn't install.

## 8c. Revocations and peer custody on a replica (plan §8.1.3, §8.6.1; R2-L17, R2-L15)

### Revocations

The sync engine verifies a roster and hands each revocation to the replica as `(device, epoch, position)` (`recordRevocation`). The roster's own format is specified at M3.
- **Permanent:** the replica keeps every revocation it learned, as a union. Recording one again changes nothing, and no later roster, epoch or restore removes one.
- **Pending effects leave the view at once.** In the same transaction:
  - Every relayed operation of the device that Core hasn't decided, and that canonical state doesn't hold, moves to `revoked`. It leaves the effective view and the index, in one local change of kind `revocation`.
  - Its exact signed bytes stay in the journal for inspection ("rejected (revoked), kept for inspection").
  - Its submit follow-up is dropped, so it is never forwarded.
  - One still waiting is decided rejected, so the operations waiting for it are released with it ignored (§8.2.2).
- **What stays:** operations Core accepted (a final receipt or a page), canonical state, and other devices' operations, including ones that depend on a revoked operation.
- **Later arrivals** from a revoked device are verified and checked against the duplicate rules as usual. A new one is stored `revoked` (`storedRevoked`): never applied, never waiting, never forwarded.
- **Core still decides:**
  - A provisional receipt for a revoked operation changes nothing.
  - Core's final acceptance authorizes it. If it had entered the view it returns as an overlay. If it was decided while waiting, it appears with the canonical state that contains it.
  - A page carrying it applies as committed.
  - A Core rejection makes it `rejected`.
- **This replica's own device:** only the record is kept, and its saved local work stays pending. What a revoked device does with its own work is specified at M3.

### Peer custody (R2-SYNC-04)

A receiver acknowledges that it durably holds an operation's exact bytes ("Also held by <device>"). The acknowledgement is signed with its operation key under `lisa-r2-custody-v1\n`, over the canonical body (`CustodyAcknowledgement`):
- **Fields:** `{"acknowledgedAt", "datasetID", "digest", "holderDeviceID", "operationID"}`, at most 1 KiB. `digest` is SHA-256 of the operation's complete canonical signed body, and `acknowledgedAt` (Unix milliseconds, not negative) is for display and audit only.
- **Vector:** dataset `0123456789abcdef0123456789abcdef`, holder `1111…` (32 hex digits), operation `2222…`, digest `3333…` (64) and time 1795560100000 encode as `{"acknowledgedAt":1795560100000,"datasetID":"0123456789abcdef0123456789abcdef","digest":"3333…","holderDeviceID":"1111…","operationID":"2222…"}`.
- **On a replica** (`recordCustody`, `custody(of:)`, `safety(of:)`): the acknowledgement must verify by the holder's key in the newest roster, for the replica's dataset. It must name a journal entry by its exact digest and come from a device that is neither this one nor revoked; anything else is refused and changes nothing.
- **Kept apart:** a custody record never changes the entry's Core state, receipt, overlay or follow-ups. The origin never discards an operation because of it.
- **The three kinds of safety** are reported separately: saved on this device, held by peers, and synced with Core. Only a final Core acceptance, from a receipt or a page, gives the last (R2-L15). A peer receipt never becomes a Core-committed status.
- **Not yet on the replica:** the store records receipts the sync engine verified. Core's receipt format and its signature check are specified with Core at M3, and the relay of receipts and acknowledgements over the nearby link at M6.

## 8d. Core receipts and the ledger's intake (plan §8.2.1, §8.4.1; R2-SYNC-03, R2-L14, R2-L15)

- **Receipt** (`CoreReceipt`): Core signs it under `lisa-r2-receipt-v1\n` over the canonical body, at most 16 KiB.
  - **Fields:** `{"datasetID", "digest", "epochID", "operationID", "outcome"}`, plus as the outcome requires: `position` on final receipts; `missing`, ascending and never empty, on the provisional `waiting_for_dependencies`; `reason` (lowercase letters and `_`, at most 64 bytes) and an optional `recoveryHint` (at most 1 KiB) on `rejected`.
  - **Outcomes:** `accepted`, `accepted_with_conflict`, `rejected`, `waiting_for_dependencies`.
  - **Rejection reasons so far:** `malformed`, `unknown_item`, `dependency_rejected`, `dependency_cycle`, `unsupported_operation`.
  - **On a replica:** a receipt counts as Core commitment only when it verifies by Core's key from the verified key history. `recordReceipt(_:coreKey:)` verifies it (`ReceiptSigning.verify`), refuses a forged, foreign or other-digest receipt without change, and keeps the body and signature as the receipt's bytes.
  - **Vector:** dataset `0123456789abcdef0123456789abcdef`, epoch `fedcba9876543210fedcba9876543210`, operation `1111…` (32 hex digits), digest `2222…` (64), `accepted` at position 7 encode as `{"datasetID":"0123456789abcdef0123456789abcdef","digest":"2222…","epochID":"fedcba9876543210fedcba9876543210","operationID":"1111…","outcome":"accepted","position":7}`. A provisional receipt lists `missing` between `epochID` and `operationID`, and has no `position`.
- **Intake at Core** (`CoreLedger.intake`):
  - **Before the transaction:** each operation is verified (dataset, the origin's roster key, the signature). An unverified one gets no receipt.
  - **Then one write transaction, with a savepoint per operation:**
    1. The duplicate rules: a `duplicate` returns its current receipt; `identity_reuse` and `sequence_reuse` are refused with a security event.
    2. Support and payload checks: a failure is rejected with a receipt.
    3. Causal readiness: a waiting operation gets a provisional receipt naming what it misses. A ready one is merged, projected into R1's records, and logged with its final receipt.
  - **Release:** waiting operations are released in bounded steps (`releaseStep`): at most 256 edges and 256 operations each, round-robin across origins.
  - **Lookup:** `receipt(for:)` returns an operation's current receipt, provisional or final.
  - **Positions:** every decision, a rejection included, takes the next commit position and is a change-log entry of its item's partition.
- **Full snapshots from Core** (`CoreLedger.snapshot`): one consistent cut, at the newest position, of the named partitions (§8b). Every accepted operation at or below the cut goes into chunks in position order, with rejections left out. A chunk that would pass 512 KiB carries fewer entries, and the header Core signs has the cut as its version.
- **Pages from Core** (`CoreLedger.changePage`): a signed page per partition (§8a) carries every decision in `(after, to]`. When entries remain, `to` is the last entry's position; otherwise it is the newest position. A page that would pass 512 KiB carries fewer entries.

## 8e. The v2 sync routes (plan §8.12.1, §8.6.5)

- **Common rules:**
  - Every request carries the device's bearer credential and `Lisa-API-Version: 2.0`.
  - Bodies are canonical JSON (`SyncWire`); exact signed bytes travel as strict base64url in `{"body", "signature"}` objects.
  - Any answer but 200 carries `{"code", "message"}`: 401 `unauthenticated`, 400 `invalid_request`, 404 `not_found`, 503 `unavailable`.
- **`GET /v2/capabilities`:** answers `{"apiVersion": "2.0", "datasetID", "epochID", "head", "features"}`. `head` is the newest commit position, and `features` lists Core's capabilities as strictly ascending tokens: `challenges`, `changes`, `credential-reset`, `enrollment`, `operations`, `receipts`, `trust`.
- **Negotiation,** before any route, an enrollment included:
  - a `Lisa-API-Version` with another major version gets 426 `upgrade_required`, while another minor version is answered;
  - a `Lisa-Required-Features` list (comma-separated) naming a feature Core lacks gets 426 `upgrade_required`;
  - a request without a version header is taken as 2.x.
  - The client's `CoreSession` refuses a Core whose capabilities name another major version (`incompatibleCore`).
- **`POST /v2/operations`:** takes `{"operations": [signed, …]}` (1–100). It answers `{"outcomes": [...]}`, one per operation in order:
  - `{"outcome": "receipted" | "duplicate", "receipt": signed}`;
  - `{"outcome": "identity_reuse" | "sequence_reuse"}`;
  - `{"outcome": "unverified", "reason"}`.
- **`POST /v2/receipts/lookup`:** takes `{"operationIDs": [hex, …]}` (1–100). It answers `{"receipts": [{"operationID", "receipt"?}]}`, each with the current receipt, provisional or final, or none.
- **`GET /v2/changes?partition=&after=&limit=`:** answers `{"page": signed}` with Core's signed page from `after` (§8a, §8d), or `{}` when nothing was committed after it. `limit` is 1–512, 256 by default.
- **The client** (`LisaSyncEngine.CoreSession` over `LisaSyncHTTP.HTTPCoreTransport`):
  1. Checks the dataset.
  2. Pulls pages per partition from each cursor until Core has nothing newer.
  3. Signs held drafts.
  4. Submits pending local operations in saved order, in batches of 100, and records each receipt only after verifying it by Core's key. What Core refuses without a receipt stays in the journal.
  5. Pulls again.

## 8f. Enrollment, the roster and device authentication (plan §8.1.2, §8.1.3, §8.12.1)

- **Roster** (`TrustRoster`, artifact type `roster`, §9), identified by (epoch, version):
  - **Page 0, the summary:** `{"kind": "summary", "datasetID", "epochID", "version", "issuedAt", "policyVersion", "maximumNearbyTrustAgeDays", "tlsPins": [{"pin", "validFrom", "validUntil"?}], "anchorsDigest"? (ca mode), "exportKey", "deviceCount", "revocationCount"}`. One or two distinct pins, current first.
  - **Then the device pages,** 64 entries each: `{"kind": "devices", "devices": [{"deviceID", "name", "deviceClass", "status", "operationKey", "exportKey", "enrolledAt", "capabilities"}]}`.
  - **Then the revocation pages,** 256 each: `{"kind": "revocations", "revocations": [{"deviceID", "epochID", "position", "revokedAt"}]}`.
  - **Order and status:** both lists are strictly ascending by device ID. A listed device is `revoked` exactly when a revocation names it; a revocation can outlive its device's entry.
  - **Decoding** requires this page order and the counts, and the summary must agree with the signed header.
  - **On a device:** accepted only as a whole by the trusted Core key, and only if newer than the held version within its epoch (`RosterSigning.verifyNewer`). Its revocations are recorded before the roster (union rule).
- **Request** (`EnrollmentRequest`), signed by the new operation key under `lisa-r2-enroll-request-v1\n`. It carries `{"enrollmentID", "token", "datasetID", "trustMode", "leafPin", "caDigest"? (ca mode), "issuerFingerprint", "deviceName", "deviceClass", "operationKey", "exportKey", "credentialVerifier", "incarnationID", "createdAt"}`, at most 16 KiB.
  - Its body contains the token, so it is secret-bearing: kept only in the device's pending item, never stored by Core.
  - **Request digest:** SHA-256 of the exact signed body.
- **Result** (`EnrollmentResult`), signed by Core under `lisa-r2-enroll-result-v1\n`: `{"datasetID", "enrollmentID", "issuerFingerprint", "requestDigest", "deviceID", "operationKey", "exportKey", "rosterDigest", "authorizationDigest", "issuedAt"}`.
  - `rosterDigest` is SHA-256 of the roster's signed header body, which binds every page.
  - `authorizationDigest` is SHA-256 of the authorization record's body.
- **Authorization record** (`DeviceAuthorization`), signed by Core under `lisa-r2-device-authorization-v1\n`: `{"datasetID", "epochID", "deviceID", "rosterVersion", "operationKey", "capabilities", "issuedAt"}`.
- **Response** (`EnrollmentResponse`): `{"result": signed, "roster": {"header": signed, "pages": [{"index", "bytes", "proof"}]}, "authorization": signed}`. It holds nothing of the request. Core stores these exact bytes for 7 days and returns them to an exact retry.
- **Anchors bundle** (`TLSAnchorsBundle`), signed by Core under `lisa-r2-tls-anchors-v1\n`: `{"datasetID", "caCertificate", "intermediates"}` (DER, base64url). It depends only on the dataset and the configured certificates, so its digest, which the roster carries as `anchorsDigest`, is stable across restarts.
- **Credential** (`CoreCredential`): 32 random bytes from the device. It travels as unpadded base64url in `Authorization: Bearer`, and Core keeps only its SHA-256 (`credentialVerifier`).
- **Routes:**
  - `POST /v2/enrollments` takes `{"request": signed}` and answers the response body, or `{"code", "message"}`. Codes:
    - `invalid_request` 400, uncounted;
    - `enrollment_unknown` 404;
    - `enrollment_consumed` 409, with a security event;
    - `enrollment_response_purged` 409, naming the device;
    - `enrollment_device_limit` 409, counted;
    - `enrollment_expired` 410;
    - `enrollment_invalidated` 410;
    - `enrollment_rejected` 403, counted: a wrong token, signature, key or field.
  - `GET /v2/trust/tls-anchors` answers `{"bundle": signed}` in `ca` mode and 404 in `pin` mode.
  - These two need no credential.
  - `GET /v2/trust` answers `{"roster": …}` to an active device's credential.
- **Core's order in one write transaction** (`CoreTrust.enroll`):
  1. A consumed enrollment answers first, whatever the expiry: the stored bytes for the same digest, 409 for another, `enrollment_response_purged` after 7 days.
  2. Then: invalidated or cancelled; expired; a changed signer, which invalidates the open record.
  3. The token's hash, in constant time.
  4. The request's signature by its own operation key, its keys, dataset, issuer, trust mode, pin, CA digest and class.
  5. The device limit, 10 by default.
  6. Consume: the device; the terminal record (state, digest, device, time); a new roster; the authorization; the result; the stored response.
  - A failed attempt is committed with the refusal, and the fifth invalidates.
- **Device completion** (`CoreEnrollment`, `ReplicaStore.completeEnrollment`): in one transaction, the dataset and device ID, the trust state (Core URL and signing key from the owner text, TLS mode, host, CA and intermediates, enrollment ID, request digest) and the roster. Repeating it with the same digest changes nothing. The pending item is removed only afterwards.
  - The item goes on `enrollment_consumed`, `_expired` and `_invalidated`, and at the owner text's expiry plus 24 hours. Other refusals and unverifiable results keep it for an exact replay.
- **Revocation** (`CoreTrust.revoke`): the device's status, a permanent revocation at the current epoch and commit position, its open resets cancelled, and a new roster version. Its credential is then refused (401), and its operations, from any submitter, are `unverified`. A challenge it answers afterwards is refused as `revokedDevice` (§8g), so its upload can be quarantined.

## 8g. Credential reset and challenges (plan §8.1.4, §8.1.5)

- **Reset token** (`CredentialResetToken`):
  - 32 random bytes, shown once to the owner as unpadded base64url, and usable for 10 minutes.
  - Core keeps only `SHA-256(ASCII "lisa-reset-token-v1" ‖ 0x00 ‖ token)`. A device that isn't active gets none.
- **Reset request** (`CredentialResetRequest`): `{"datasetID", "deviceID", "token", "newVerifier", "createdAt"}`, signed by the device's existing operation key under `lisa-r2-credential-reset-v1\n`. It carries the token, so it is secret-bearing.
- **`POST /v2/devices/current/credential-reset`** takes `{"request": signed}` and needs no credential.
  - **Core, in one write transaction:** the device must be active; its registry key must verify the signature; and an open token for that device must match in constant time and be unexpired.
  - **Then** the verifier is replaced, the token used, and the device's other open tokens cancelled. The old credential is then refused (401).
  - **The answer** is `{"deviceID", "resetAt"}`, or:
    - `credential_reset_unknown` 404;
    - `device_revoked` 403;
    - `credential_reset_invalid` 403: a wrong key, token, dataset or verifier, or a cancelled token;
    - `credential_reset_expired` 410;
    - `credential_reset_used` 410.
- **Challenge** (`Challenge`): `POST /v2/challenges` takes `{"deviceID", "purpose"}`, needs no credential, and answers `{"challengeID", "nonce", "purpose", "datasetID", "epochID", "deviceID", "expiresInSeconds": 120}`.
  - **Purposes:** `recovery-evidence`, `trust-evidence`, `credential-refresh`, `owner-import`, `legacy-link-lookup`.
  - **Storage:** Core keeps each challenge with its run generation (a random 128-bit value per Core process) and a deadline on its monotonic clock.
- **Response** (`ChallengeSigning`): the device signs, with its operation key, the exact bytes `"lisa-challenge-v1" ‖ 0x00 ‖ purpose ‖ datasetID ‖ epochID ‖ challengeID ‖ nonce ‖ deviceID ‖ keyID ‖ SHA-256(body)`.
  - The purpose is its ASCII token, identifiers are their 16 raw bytes, the nonce is 32 bytes, and `keyID` is SHA-256 of the operation key's SubjectPublicKeyInfo DER.
  - The proof travels with the body it authorizes as `{"challengeID", "keyID", "signature"}`.
- **Verification** (`CoreTrust.verifyChallenge`, one write transaction), in this order:
  1. `unknown`.
  2. `used`.
  3. `otherRun`: issued before a Core restart.
  4. `otherEpoch`.
  5. `purposeMismatch`.
  6. `expired`, by the monotonic deadline. A wall-clock step has no effect.
  7. `unknownKey` when the registry has no such device. The device's trust records then reach Core only as an owner-mediated trust bundle (§8.5.3).
  8. `revokedDevice` when it is revoked: the challenge is spent, and the caller keeps the upload as quarantined evidence.
  9. `unknownKey` when the key ID isn't the active device's key.
  10. `invalidSignature`: this covers a body changed after signing, and a response signed for another epoch.

  Only `verified` and `revokedDevice` spend the challenge. Revoking a device leaves its open challenges to this verdict.
- **Consumers:** the routes that take a proof (recovery evidence, credential refresh, owner import, legacy-link lookups) arrive with M3-7 and the migration spans.

## 8h. Core's signing-key history (plan §8.1.1, §8.1.4, §8.5.3; `docs/DECISIONS.md` D-65)

- **Transition** (`SigningKeyTransition`):
  - **Fields:** `{"datasetID", "sequence", "previousKey", "nextKey", "activationPosition", "issuedAt"}`, the keys as base64url SubjectPublicKeyInfo DER, at most 4 KiB.
  - **Signatures:** both keys sign the exact body under `lisa-r2-key-transition-v1\n`. It travels as `{"body", "previousSignature", "nextSignature"}`.
  - **Activation:** the activation position is the first commit position the next key signs.
- **History** (`CoreKeyHistory`): entries `{key, sequence, validFrom, retiredAt}`, starting at an anchor.
  - **A new link must** be signed by both keys, for this dataset, from the current key, the next in sequence when the current key's sequence is known, activating after the current key's start, and with a key never used before.
  - **A device's anchor** is the owner text's key, of unknown sequence until the transition that activated it arrives. Transitions from before the anchor are skipped while the anchor is all the history holds.
- **Verification:**
  - a final receipt by the key valid at its position;
  - pages, snapshots, rosters, anchors bundles and enrollment results by the current key;
  - a provisional receipt by any key of the history.
- **`GET /v2/trust`:** `{"roster": …, "keyTransitions": [signed, …]}` once Core has rotated, in sequence order; before that, `{"roster": …}` alone.
- **Core** (`CoreLedger.rotateSigningKey`, `importKeyTransition`):
  - **Rotation:** activation is the last position plus one; a rotation with nothing committed since the last one is refused; the rotating ledger stops signing.
  - **Opening:** only with the history's current key (`signerRetired`, `signerMismatch`).
  - **Import:** a transition that continues the store's history, once the store has reached its activation.

## 8i. Device key rotation (plan §8.1.4; `docs/DECISIONS.md` D-66)

- **Update** (`DeviceKeyUpdate`): `{"datasetID", "deviceID", "previousKey", "nextKey", "createdAt"}`, signed by both keys under `lisa-r2-device-key-update-v1\n`. It travels as `{"update": {"body", "previousSignature", "nextSignature"}}`.
- **`POST /v2/devices/current/key-update`,** under the device's bearer credential, answers `{"roster": …}`, the new roster. Its refusals:
  - `key_update_invalid` 403: a bad signature, another device or dataset, or a previous key that isn't the registry's;
  - `device_revoked` 403;
  - `key_update_key_in_use` 409;
  - `key_update_operations_waiting` 409.
- **Roster:** each device entry carries `"previousKeys": [base64url SPKI, …]`, oldest first.
- **Verification on replicas:**
  - Core's pages, repairs and snapshots verify a device's committed operations with its current key, its `previousKeys`, or its last key once it is revoked (`ReplicaStore.rosterHistoricalKeys`).
  - Operations received from peers verify only with the current key.
- **The device after an update:** it re-signs its pending and submitted operations with the next key; IDs and digests are unchanged.

## 8j. Legacy children and parents (plan §8.12.2; `docs/DECISIONS.md` D-67)

- **Children are a pure function of the request** (`LisaLegacyRequests.LegacyChildSet`):
  - **ID:** the first 16 bytes of `SHA-256("lisa-v1-child-v1" ‖ 0x00 ‖ len32(dataset) ‖ dataset ‖ len32(scope) ‖ scope ‖ len32(requestID) ‖ requestID ‖ len32(discriminator) ‖ discriminator)`.
  - **Origin:** `coreLegacyTranslation` with incarnation `SHA-256("lisa-v1-incarnation-v1" ‖ len32(dataset) ‖ dataset ‖ len32(scope) ‖ scope ‖ len32(requestID) ‖ requestID)` (first 16 bytes; no 0x00 after this label) and sequence index + 1.
  - **Versions:** schema and policy versions 1, the derivation scheme's; no `createdAt`.
  - **Observed set:** none, except on a PATCH child made against R1's `expectedRevision` N, a field edit, a notes replacement or a reopen: `{"pieces": [], "projectionRevision": N}` (`LegacyChange.observedRevision`, D-69, D-72). It stays a pure function of the request.
  - **`legacyParent`:** `{scope, requestID, discriminator, index, count, setDigest}`, the set digest being SHA-256 of the ordered child IDs.
  - **Dependencies:** at most one, the immediate predecessor among the request's children in the same chain (the same entity, or for preferences the same key).
  - **Created entities:** an entity the request creates gets the child-ID derivation of `entity:<discriminator>`.
  - Only Core's signature, which the digest leaves out, differs between conversions.
- **Vectors** (dataset bytes `00…0f`, scope `device:0123456789abcdef0123456789abcdef`, request ID `queue-2026-11-25-0001`; reproduced with Python's hashlib):
  - incarnation `e1f2790dce9f30d247e55dd97a508704`;
  - `field:title` → `e7b59fbce39fe1aa9ff9a26d3531afc0`, `field:notes` → `5e634746fd0cb2e0dbcc9ca31e3e937d`, `status` → `6fa66a242b90a415efe5442d24e6676c`;
  - their set digest `e5bbe52476f4abf64d2d262b1954e690ea65fc94d9449448c1cf94fa06b5d7ee`;
  - `entity:create:task` → `1ac3159244ac03e49f884a399bf4707f`.
- **"Observed at projection revision N"** (D-69; schema v10 and v11):
  - **At decision:** when Core accepts such a child, it resolves N through its projection-revision map to the horizon `(epoch, "tasks", P(N))`, the state R1's revision N of the entity reflected. It keeps the horizon with the operation (`core_operations.observed_epoch`, `observed_position`).
  - **Folding:** Core's fold uses that horizon in place of the observed set. A revision the map doesn't hold resolves to nothing, so the child observes nothing and conflicts.
  - **On replicas:** they don't hold the map. Core serves the horizon in its signed change entries and snapshot chunks (`observedHorizon`, §8a). A replica keeps it with the canonical operation and folds with it the same way, so its view equals Core's.
- **Parents** (`CoreLedger.legacyConvert`, schema v9): one per `(scope, requestID)`, Core-only.
  - **The transaction:** the lookup again (`replay`, `bodyExpired`, `mismatch`, `awaitingReview`, or `unknown`), the route's conversion with the children taken in through the ledger, and, for an answer R1 records (2xx, 400, 403, 404, 409, 413), the parent with its children's dispositions and the answer, the body kept for 30 days by default.
  - **Nothing is kept** of a conversion that throws or answers otherwise.

## 9. Paged artifacts (plan §8.1.3, §8.4.3)

Rosters with key history, causal summaries, snapshot manifests and reviewed-set artifacts can span several pages:
- **Header** (`PagedArtifactHeader`), signed by Core under `lisa-r2-paged-artifact-v1\n`: `{"artifactType", "datasetID", "epochID", "version", "pageCount" (≥ 1), "merkleRoot"}`.
- **Pages** (`PagedArtifactPage`): `{index, bytes (at most 524,288), proof}`, the proof being the inclusion path, leaf side first.
- **Tree** (`MerkleTree`): RFC 6962. Leaf `SHA-256(0x00 ‖ page)`, node `SHA-256(0x01 ‖ left ‖ right)`; for n > 1 pages the left subtree holds the largest power of two below n. Proofs are RFC 6962's audit path, verified by RFC 9162 §2.1.3.2.
- **Acceptance** (`PagedArtifactVerification.assemble`): Core's header signature, the expected type, dataset and epoch, exactly `pageCount` pages with every index once, and every page verified at its index against the signed root. A dropped, repeated, swapped or altered page, a forged header or another dataset refuses the whole artifact. The proof does not authenticate the tree size (RFC 9162's algorithm accepts some size-n proofs under size n + 1), so the size is always taken from the signed header.
- **Vectors** (pages are the ASCII strings `page-0`, `page-1`, …; reproduced with an independent Python implementation): roots for 1, 2, 3, 5, 7 and 8 pages: `db4a76ac8c461b45ae3bff430d7cac5c8f7ca6a24ed61f00c2cc3ac7d9cea390`, `9f986a9a86251bd8ca7582421873166e5bb6baaa0d5846f767b70c6d91127db2`, `e8cf1716052692337c090ad09676ed22f277f56547aa42a8d566439a0a42adbe`, `4b51c34223a04defb1dee194c7a543843ff28d4886c008c09f7506ce38a93f7a`, `87f45200cc7e94818a4341e9f82fdd3d333be87069a21fdb36b28c41152e2709`, `5de10b435c206d44950064dc0ac4d84cad4e608bbff864ebc3dddd62f296bf77`. The proof of page 5 in 7 pages is `dc4e1dfabb0f278819e31d357612c989b62f153a51f4e707c7f4aaedb23f838b`, `1afc45a4da64f47b7f7be075c1e01de71ee14aaabb9adf448674dc790c60cf91`, `ecfaf8a423d8a78f097fdaa35167814e8abbeef186835e034e8057ebe98ecc47`; of page 4 in 5 pages, the last of those alone.

## 10. Protected archive `lisa-archive` v1 (plan §8.6.6)

- **File layout** (`ArchiveContainer`): the 16 ASCII bytes `LISA-ARCHIVE-V1\n`; the header length as 4 bytes big-endian and the canonical header; the ciphertext length as 8 bytes big-endian (equal to the header's `payloadLength`) and the AES-256-GCM ciphertext with its 16-byte tag; one byte, 0 or 1; then the 64-byte signature exactly when that byte is 1, which must agree with the header naming a signer. Nothing may follow.
- **Header** (`ArchiveHeader`, canonical JSON): `format` `lisa-archive`, `formatVersion` 1, `archiveID`, `datasetID`, `originDeviceID`, `incarnations` (strictly ascending), `createdAt`, `rosterVersion`, `head` (known at export), `recipients` (at least one, strictly ascending by `keyID`: `{"kind": "core-roster" | "owner-supplied-core-key" | "installation-only", "keyID", "encapsulatedKey", "sealedKey"}`), `signerKeyID` (absent when unsigned), `payloadNonce` (12 bytes), `payloadLength`. A key ID is SHA-256 of the public key's canonical DER.
- **Sealing:** a random 256-bit key encrypts the payload with AES-256-GCM, with SHA-256 of the canonical header as authenticated data. The key is sealed to each recipient with HPKE base mode (DHKEM(P-256, HKDF-SHA256), HKDF-SHA256, AES-256-GCM), with info `lisa-archive-v1 payload key\n` ‖ archive ID and authenticated data `kind` ‖ 0x00 ‖ key ID. The exporting device signs `lisa-r2-archive-v1\n` ‖ SHA-256(header) ‖ SHA-256(ciphertext), or the archive stays unsigned when its key is unavailable.
- **Payload:** entries, each one kind byte, a 4-byte big-endian length and the exact bytes (at most 16 MiB): 1 signed operation, 2 blob, 3 draft, 4 conflict, 5 quarantined legacy bytes, 6 rollback acknowledgement, 7 reviewed-set artifact. Each kind's schema is specified when it is produced (M5 and later).
- **Opening** (`ArchiveReader`): only for the expected dataset and only with a recipient's key; opening only decrypts. Authenticity is a separate check against the exporting device's key in the trusted roster, and an unsigned archive is never authentic. Eligibility against trusted revocation evidence is the importer's rule (M5).

## 11. Not yet specified here

The payloads of the other operation types (captures, ideas, reminders, occurrences, proposals, preferences, plans, suggestions, conflicts, devices, authority writes, restores), receipts, dependency release, windowed partitions' bucket ranges and interval coverage, membership records, snapshots and chunks, manifests, blobs, rosters and their revocation evidence (§8c covers a replica's handling), lineage and confirmations, enrollment request and result bodies, challenges, assignments and reports, legacy import items, the archive entries' schemas and nearby frames. Each is added with its vectors when its milestone implements it.
