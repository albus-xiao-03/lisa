<!-- The result schema and the redacted export (plan R2 §10.8 "Results"; docs/DECISIONS.md D-54). -->
# Results

## `results.jsonl`

One JSON object per line, one per case (per device for a paired case), with sorted keys:

| Key | Meaning |
|---|---|
| `runID` | `run-YYYYMMDDTHHMMSSZ-<6 lowercase base32 characters>` |
| `caseID` | The case, or `<case>@sender` / `<case>@receiver` for one device of a paired case |
| `commit`, `harnessVersion` | The commit built and the harness or app version that recorded it |
| `providerInterface` | For example "Gmail API", "IMAP via Bridge", "Network framework TLS 1.2 PSK" |
| `configuration` | `digest` of the whole non-secret configuration and allowlisted `fields` |
| `platform`, `deviceModel`, `osVersion`, `xcodeVersion` | Where it ran |
| `apnsEnvironment`, `profileKind`, `modelID` | When the case involves them (omitted otherwise) |
| `assumptions`, `requiredEvidence` | What the case assumed and what it must show |
| `expectedResult`, `observedResult` | What should happen and what did |
| `resultLevel` | Set only on `PASS`: `harness-ready`, `fixture-pass`, `provider-accepted` or `owner-verified` |
| `requiredResultLevel` | The level the case needs |
| `status` | `PASS`, `FAIL`, `NOT_RUN_ENVIRONMENT`, `NOT_RUN_CREDENTIALS`, `BLOCKED_PERMISSION` or `OUT_OF_SCOPE` |
| `executor`, `cause` | `claude` or `owner`, and the exact cause |
| `actions` | `<action ID>=<state>` for each logical action the case caused |
| `times` | Wall-clock start and end (correlation only) and monotonic start and end in nanoseconds |
| `evidenceFiles` | Evidence names, with `sha256:` digests where the harness computed them |
| `knownFinding` | The known finding (plan §17.1) the result is recorded against, if any |
| `design` | `A` or `B` for a nearby proof (X1 runs both designs under one case ID) |
| `pairSession` | `baseCaseID`, `role`, `devices`, `condition`, `harnessNonce`, `sessionCodes` |
| `checks` | Each criterion: `id`, `status`, `observed`, `evidenceEntries` |

The nearby cells' checks are:
- `peer-identification`, `unenrolled-identity-refused`, `exporter-bound-hello`, `wrong-binding-refused`;
- `reconnect-after-kill`, `reconnect-after-wifi-toggle`, `deduplication`, `100-frames-timed`;
- `tls-version-and-suite-recorded`, `local-network-prompt-recorded`, `local-network-denial-recorded`;
- for Design A, also `forward-secret-ecdhe-psk-suite`.

The proof app also records `frames-within-1-mib-budget` and `rejoin-without-discovery-secret` as information. Lisa Proof writes these same keys, so its exports import unchanged.

## The action ledger

Each logical action is recorded in the run's `actions.sqlite` under `OVA-<run-id>-<case>-<n>`. A logical action is anything that can reach a person, a device, an account or a provider. Its states:
- `intent`: committed before any I/O;
- `submitting`: committed before the first byte;
- `accepted` or `refused`;
- `ambiguous`: submitted with no answer and no evidence found;
- `superseded`: replaced by the single retry `<id>.r2` you authorized by typing `may duplicate <id>`.

## The redacted export

`lisa-verify export <run-id> --redacted <file>` writes allowlisted fields only:
- Free text is scrubbed: URLs, e-mail addresses, telephone numbers, IP addresses and token-like strings become per-run aliases such as `<address-1>`.
- Configuration keeps its digest and the keys `design`, `suitePolicy`, `fault`, `harnessRole`, `condition`, `devices`, `mode`, `platform` and `rejoin`.
- Provider references become `sha256:` digests.

With `--canaries <file>` (one value per line), nothing is written if any of the values survives.
