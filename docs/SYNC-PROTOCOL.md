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
| `origin` | `{"kind": "device", "deviceID", "incarnationID", "sequence" (≥ 1), "previous"?: {"incarnationID", "lastSequence"}}`, where `previous` may appear only on sequence 1; or `{"kind": "coreLegacyTranslation"}` |
| `entity` | `{"type", "id"}`, the type from the catalog (`OperationCatalog`) |
| `type` | The operation type, `<entity>.<action>` from the catalog (§8.2.3) |
| `payload` | The type's payload. The schemas implemented so far are below ("Item payloads"); other types' payloads stay opaque to the envelope codec until theirs are |
| `dependencies` | At most 32 operation IDs, strictly ascending, never the operation's own ID |
| `observed` | Optional: `{"pieces": [≤ 256 IDs, strictly ascending], "horizon"?: {"epochID", "partition", "position"}, "reviewedSetDigest"?, "group"?: {"groupID", "index", "count", "listDigest"}}` |
| `legacyParent` | Only on Core legacy children: `{"scope", "requestID" (R1's 8–128-character alphabet), "discriminator", "index" (in 0..<count), "count", "setDigest"}` |
| `createdAt` | Unix milliseconds, display and audit only; required on device operations, absent on legacy children |

- **Malformed, refused before any payload is read:** a device operation carrying `legacyParent` or lacking `createdAt`, a legacy child lacking `legacyParent` or carrying `createdAt`, too many, unsorted or self dependencies, too many or unsorted observed pieces, a `previous` link after sequence 1, an unknown type, an unknown field, another protocol version, a non-canonical or oversized body.
- **Digest:** SHA-256 over the complete canonical signed body (`OperationDigest`). **Signature:** raw 64 bytes over `lisa-r2-op\n` ‖ body, not part of the digest (`OperationSigning`). Verification refuses a malformed body, another dataset, an origin without a key in the holder's roster (unknown or revoked), a forged signature, and a legacy child not signed by Core's key.
- **Duplicates,** everywhere (`OperationIdentityCheck`): the same ID and digest is `duplicate`; the same ID with another digest is `identity_reuse`; the same `(device, incarnation, sequence)` under another ID is `sequence_reuse`.
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
| `task.reopen` | `{"reopens": [IDs]}` | 1–32 terminal-action operation IDs, strictly ascending; an unnamed one stays in effect |
| `note.add`, `note.replaceObserved` | `{"text": <text>}` | Non-empty, within the text budget below; a replacement removes exactly the note pieces its observed set covers |
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

The payloads of the other operation types (captures, ideas, reminders, occurrences, proposals, preferences, plans, suggestions, conflicts, devices, authority writes, restores), receipts, dependency release, windowed partitions' bucket ranges and interval coverage, membership records, snapshots and chunks, manifests, blobs, rosters and revocation, lineage and confirmations, enrollment request and result bodies, challenges, assignments and reports, legacy import items, the archive entries' schemas and nearby frames. Each is added with its vectors when its milestone implements it.
