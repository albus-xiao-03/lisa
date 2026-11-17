<!-- Lisa's security and data-routing model: secrets, authorization, untrusted content, network boundaries, and what each provider receives. -->
# Lisa — Security and data routing

This document covers SEC-01 to SEC-03 and the security parts of API-01, CFG-02 and NOTIFY-06. Design decisions are cited as D-*n* from `docs/DECISIONS.md`.

## What is stored, and where

All owner data stays on the authoritative host, inside its data directory. The directory is created with owner-only permissions (`0700`).

| Data | Location | Protection |
|---|---|---|
| Records: tasks, ideas, captures, events, proposals, plans, briefs, reminders, deliveries, devices, audit | `lisa.sqlite` (WAL mode) | File mode `0600` (D-22) |
| Raw source content: messages, feed documents | The `raw_content` table in the same database | Purged by age (D-24, D-31) |
| Logs | `logs/`: rotating files of at most 5 MB each, three files | Redacted metadata only (D-09) |
| Dry-run captures: intended email, calls and notifications | `dry-run/captures.jsonl`, bounded | `0600`. They contain the intended content, but never device tokens. |
| Runtime schedules | `runtime-state.json` | `0600` |
| Backups | Where the owner chooses | Consistent copies with a manifest (D-23) |

- **No encryption claim.** The database is **not encrypted by Lisa**. Lisa relies on file permissions and on the operating system's storage protection, such as FileVault on the Mac or disk encryption on Linux. No database encryption is claimed.
- **Paired devices.** A device keeps only its credential, in Keychain. Cached briefs and rundowns, and its queue of pending actions, use data protection that is available after first unlock.

## Secrets (SEC-01, D-08)

- **References only.** Secrets are never stored in configuration, the database, fixtures, logs or Git. Configuration holds references, which are resolved only through the `SecretStore` interface:
  - `env:NAME`, an environment variable;
  - `file:/path`, an owner-only file of at most 64 KiB;
  - `keychain:item`, available only in the Apple apps.
- **Device credentials.**
  - A device credential is 256 random bits, shown to the device once.
  - The host stores only its SHA-256 verifier and compares in constant time (D-29).
  - Push tokens and verifiers never appear in API responses, exports or logs.
- **Logs.** Logs record only classified values. Private content (addresses, subjects, URLs, tokens) appears only as a short fingerprint. Secrets never appear in any form.

## Authorization (API-01, D-35)

- **Principals.** Every action is attributed to a principal:
  - the **local owner**: the host process itself, or the owner on the host;
  - a **paired device**;
  - the **runtime**;
  - a **model** suggestion;
  - the **demonstration**.
- **Consequential settings.** The following can be changed only by the owner on the host:
  - approved email addresses and phone number;
  - email and call enablement;
  - model endpoint and data sharing;
  - the Time Sensitive opt-in.

  A paired device, inference and source content can never change them. Inferred preferences take effect only after the owner confirms them (D-30).
- **Mutations.** Every mutation has a stable request identity, and revision checks wherever concurrent edits matter.
- **The local owner over the network.** A `lisa` command connected to a running `lisa serve` acts as the local owner only through the owner credential on the loopback owner listener (D-44). Paired devices never receive it.

## Untrusted content (SEC-02)

- **Inputs are data.** Email, feeds, calendars, posts and model output are untrusted data, never instructions.
- **XML.**
  - XML is read by libxml2 with network access, external entities and entity declarations disabled.
  - An external DTD is never loaded (D-12).
- **HTML.** HTML becomes plain text with active content removed. Links are never fetched (D-14).
- **Model output.**
  - The model sees source text inside an explicit untrusted-content envelope.
  - Its output is validated before anything is stored: evidence quotes must match the source, and dates are checked.
  - A commitment becomes "confirmed" only from the owner's own text (D-19, D-33).
- **No side effects from content.** Source content cannot add a recipient, change a number, change a preference or start a call. Recipients are enforced by the outbox at send time, independently of any content (D-26).
- **Limits.** Every imported item is bounded, using limits from the configuration: message, feed and document sizes, recurrence expansion, items per synchronization, model input and output, and retry attempts.

## Network boundaries

- **Explicit connectors only.** Lisa connects only to configured endpoints, plus a link the owner explicitly asks it to read (NEWS-01, D-46): only the local owner or a paired device can ask, only for a link the owner captured, once per item, to public https addresses, with one bounded GET and nothing the page refers to. Each attempt is audited with its outcome and failure class only, never the address or content. All host-side traffic goes through libcurl (D-41).
- **Address policy.** Every resolved address is checked when a connection opens, and again before any request byte is sent. That defeats DNS rebinding and covers reused connections. The policy refuses:
  - loopback, private and shared addresses, except an endpoint the owner configured with such a literal (a local model server or mail server);
  - link-local addresses, including cloud metadata, and reserved, documentation and multicast addresses, always.
- **URL policy.**
  - https only; plain http only to a loopback model server.
  - No credentials in URLs.
  - No redirects for authenticated APIs. Feed redirects are re-validated at every hop and never carry credentials to another origin.
- **TLS.** TLS 1.2 or later, with peer and host verification against the system trust store. There is no option to disable verification. Proxy environment variables are ignored, so the destination's address is the one checked.
- **No duplicate actions.** A POST is sent at most once per attempt. libcurl's automatic resend is refused, and the attempt is recorded as an unknown outcome.
- **API exposure (API-01, D-44).**
  - The API binds to loopback by default. Any other address requires TLS, either native or through a trusted reverse proxy on a loopback or private address. The configuration validator and the server both refuse plain HTTP off loopback, and certificate validation is never disabled.
  - Native TLS allows only TLS 1.2 with ECDHE and AES-GCM or ChaCha20-Poly1305, and TLS 1.3. Encrypted private keys are refused rather than prompting for a passphrase.
  - Every request on the device listener needs a device credential; only pairing uses a one-time code instead. Possessing a push token authenticates nothing.
  - The owner listener exists only for command-line clients on the host. It is bound to 127.0.0.1, accepts only loopback peers (checked on the address bytes, including IPv4-mapped IPv6), and accepts only the owner credential. That credential is issued per `lisa serve` run, kept in memory only as a digest, written to an owner-only file, refused by the device listener, and revoked at shutdown.
  - Behind a reverse proxy, no request counts as coming from this machine.
  - The server bounds header size, body size, connection count and every wait for the client, and refuses ambiguous framing (request smuggling) and repeated credential headers. Responses forbid caching and content sniffing.

## What each provider receives (SEC-03)

| Provider | Receives | When |
|---|---|---|
| Configured model endpoint | Only the minimized text of the item being interpreted, inside the untrusted envelope. Remote endpoints are refused unless data sharing allows them. | Extraction, when a model is configured. The default is the rule-based provider, which sends nothing. |
| Apple Push Notification service | The device token, the app topic, timing headers, and a minimal payload: generic localized text, category, opaque identifiers, and a truncated title only if the device opted in (D-38) | Notification delivery in live mode |
| Mail server (IMAP) | Lisa's own mailbox login; read-only commands | Synchronization of Lisa's own mailbox |
| Mail server (SMTP) | Lisa's sending identity, the approved recipients, and the brief or reminder text | Email delivery in live mode |
| Twilio | The approved phone number and a short spoken message | Call escalation in live mode, after every CALL-01 condition |
| X, Discord, calendar and news hosts | Requests for the configured account, channel or feed; X and Discord also receive their tokens | Synchronization of that source |
| The host of a link the owner captured | One GET for that page, with no cookies or credentials | Only when the owner asks Lisa to read the link |

- **Disabling a provider.** Disabling a provider, or removing its configuration, stops new requests to it.
- **Dry run by default.** Delivery stays dry-run until the owner deliberately enables live mode for a channel (CFG-02). Live mode on a channel without an adapter refuses to start rather than pretending (D-36).
