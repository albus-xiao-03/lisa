<!-- Lisa's network integrations: what each adapter reads or sends, how to set it up, how failures are classified, and what has been verified where. -->
# Lisa — Integrations

This document covers the Phase 6 adapters: MAIL-01, CAL-01 (HTTPS), NEWS-01 to NEWS-03, EMAIL-01, CALL-01, MODEL-01 and NOTIFY-04. Design decisions are cited as D-*n* from `docs/DECISIONS.md`.

**Verification status.**
- Every adapter was built and checked on Linux only, against scripted test doubles and local loopback servers with a synthetic certificate authority.
- No real account, mailbox, feed, phone number, device or provider was contacted. Live checks are `NOT_RUN_CREDENTIALS`.
- The Mac's own libcurl is `NOT_RUN_ENVIRONMENT`.
- The persistent suite repeats these checks for every adapter (`Tests/LisaTests/Adapters/`, L18 and L27): success, authentication failure, timeout and throttling. IMAP, SMTP, the feeds, captured pages and the model run through the real libcurl over loopback TLS. X, Discord, Twilio and APNs run on a scripted transport, because their endpoints are fixed public hosts.
- STARTTLS (IMAP in milestone M6a, SMTP in the Phase 6 checks) and APNs over real HTTP/2 (milestone M6b) were verified only by temporary checks: the persistent suite's loopback servers cannot upgrade a connection or speak HTTP/2.

## Rules every adapter follows

- **One network stack.** All host-side traffic goes through libcurl 8.14.1 (`LisaCurl`). TLS 1.2 or later is required, with peer and host verification always on against the system trust store. Proxy environment variables are ignored (D-41).
- **Addresses.**
  - Every resolved address is checked before connecting, and again before any request byte is sent.
  - Public addresses only, except for an endpoint the owner configured with a loopback or private IP literal, or `localhost`.
  - Plain http is allowed only to a model server on the same machine. Cloud metadata and link-local addresses are always refused.
- **Redirects** are followed only by feed connectors, at most three, each re-validated. Authenticated APIs never follow them.
- **Limits.** Every response has a size limit and a time limit. Every pass is bounded by its configured items, bytes and timeout (OPS-02).
- **Secrets** are references (`env:`, `file:`, `keychain:`), resolved each time they are used and never logged. Private calendar or feed addresses appear in messages only as their origin.
- **Deliveries.** Every attempt has one of these outcomes:
  - not sent (retried);
  - temporarily unavailable or throttled (retried after the provider's time);
  - rejected (not retried);
  - accepted by the provider;
  - unknown: the request may have reached the provider, so it is never resent automatically.

  A POST is sent at most once per attempt (D-41).
- **Dry run by default.** A channel delivers for real only when its mode is `live`. A live channel whose adapter is missing or unusable stops the host from starting.

`lisa doctor` checks every configured adapter without contacting any service: the network library, configuration and secrets, the model endpoint, live delivery, and APNs HTTP/2 capability.

## Lisa's mailbox (IMAP, MAIL-01)

- **What it does.**
  - Reads Lisa's own dedicated mailbox only, never the owner's.
  - Uses only `EXAMINE` (which must report `READ-ONLY`), `UID SEARCH`, `UID FETCH` with `BODY.PEEK[]` and `LOGOUT`. No message is marked read, moved, deleted or flagged.
  - libcurl establishes TLS and logs in before Lisa sends anything (D-41, D-42).
- **Setup.** In `sources`:
  - `kind: "mailbox"`, `host`;
  - `security` (`implicitTLS`, port 993, or `startTLS`, port 143);
  - `username`, `passwordSecret`, `folder` (default `INBOX`), and `mailboxAddress`, Lisa's own address, which the owner forwards to.

  Use an app-specific password where the provider offers one.
- **Behavior.**
  - The cursor is (UIDVALIDITY, last UID). If UIDVALIDITY changes, everything is read again and duplicates are removed by Message-ID.
  - Messages over the size limit are listed, not downloaded.
  - A dropped connection never advances the cursor.
  - Folders with non-ASCII names are not supported.
- **Verified.** Milestone M6a, all seven checks against a synthetic loopback server:
  - only read-only commands are sent, and flags stay unchanged;
  - implicit TLS and required STARTTLS work, untrusted certificates are refused, and no credential is ever sent in plaintext;
  - LOGIN and AUTHENTICATE PLAIN both work;
  - recovery after a dropped connection;
  - malformed input gives a classified error;
  - limits and memory stay bounded.

## HTTPS calendars (CAL-01)

- **What it does.**
  - Downloads an iCalendar subscription with conditional requests.
  - Every full download is a complete snapshot, so removed events are reconciled.
  - A "not modified" answer changes nothing.
- **Setup.** In `sources`: `kind: "calendarFeed"` with exactly one of:
  - `url` (public https);
  - `urlSecret` (a private subscription address, kept as a secret);
  - `file` (a local `.ics`). A missing or unreadable file fails the refresh with class `configuration`, and a file over the size limit fails it as partial. Neither cancels any event.

  `floatingTimeZone` sets the zone used for times written without one.
- **Verified.** Loopback TLS with the real libcurl client, scripted responses, and the host's runtime with a scripted network.

## News feeds and captured links (NEWS-01)

- **Feeds.** `kind: "newsFeed"` with `url` or `urlSecret`. RSS and Atom documents are fetched conditionally (full refresh daily) and checked before ingestion.
- **Captured links.** A link the owner captures can be read once, on request:
  - https and public addresses only;
  - text only, with no scripts and no subresources.

  Links found inside content are never fetched. Apple News items are kept as shared content and never fetched (NEWS-04).
- **Reading a captured link (D-46).**
  - The owner asks with `lisa capture --kind link --retrieve <url>`, or a device calls `POST /v1/captures/{id}/retrieve`. Only the local owner and paired devices may ask, and only for a link the owner captured. Each item is read once.
  - The item then holds the page's text, bounded like a feed item's and labeled `pageText` (what an anonymous reader sees, which for a paywall may be only a teaser), plus the retrieval time, the final address and the page's title when it had only the link. The raw page is kept under raw-content retention.
  - A page that needs signing in or payment, is not text, is too large or cannot be reached leaves the item title-only and reports why. Temporary failures can be retried with the same request ID.
- **Verified.** Through the host and API with a scripted network (success, replay, second read refused, each failure class, refused addresses, permissions, no subresource requests), and the CLI in process and in client mode with links Lisa refuses before sending. A successful read through the real libcurl over loopback TLS is verified by the persistent suite (L18); a read from a public site is not, because the sandbox has no Internet access.

## X (NEWS-02)

- **Setup.** `kind: "xAccount"` with the account's numeric `userID` and `bearerTokenSecret` (an app-only bearer token from the X developer console).
- **Behavior.**
  - Reads that account's posts through API v2: newest first, then only newer ones.
  - Rate limits and usage caps are honored.
  - Withheld or long posts are handled as documented.
- **Open question (needs a live check).** X's own documents disagree on the name of the fields parameter (`tweet.fields` or `post.fields`). Lisa uses `tweet.fields` from one place, so a rename is a one-line change.

## Discord (NEWS-03)

- **Setup.**
  - `kind: "discordChannel"` with the numeric `channelID` and `botTokenSecret`, the bot's token, never the owner's.
  - Give the bot View Channel and Read Message History in that channel, and enable the Message Content privileged intent in the developer portal.
- **Behavior.**
  - Reads the channel's messages with the REST API, newest first, then only newer ones.
  - Rate limits are honored before Discord's invalid-request limit is reached.
  - Messages whose content is withheld (no Message Content intent) are reported, not stored as empty.

## Email (SMTP, EMAIL-01)

- **Setup.** The `email` section:
  - `host`;
  - `security` (`implicitTLS`, port 465, or `startTLS`, port 587);
  - `username`, `passwordSecret`, `fromAddress` (Lisa's own address), `fromName`.

  Then set `delivery.emailEnabled`, an approved address, and `delivery.modes.email: "live"`.
- **Behavior.**
  - Sends a UTF-8 text message only to approved addresses. The outbox enforces this, not the content.
  - EHLO uses the sender's domain.
  - The classification of failures is in D-42.
  - Non-ASCII subjects are shortened to about 39 bytes; folding them over several encoded words is a known limitation of LisaMIME.

## Calls (Twilio, CALL-01)

- **Setup.** The `calls` section: `accountSID`, `authTokenSecret`, `fromNumber` (a Twilio number). Then set `delivery.callsEnabled`, `delivery.approvedPhoneNumber` and `delivery.modes.call: "live"`.
- **Behavior.**
  - Every call must first pass the call gate (CALL-01).
  - Lisa creates one call with inline TwiML that speaks the message, and never fetches TwiML from a URL.
  - A server error, or a failure after the request was sent, is `unknown`, because Twilio's call creation takes no idempotency key. The call is never placed twice automatically.

## Push notifications (APNs, NOTIFY-04)

- **Setup.** `notifications.apns`: `teamID`, `keyID`, `signingKeySecret` (the `.p8` key) and `topics` (the app bundle IDs). Then set `environments` (`development`, `production`) and `delivery.modes.push: "live"`.
  - The Apple account steps are in `docs/SETUP-APPLE.md` (Phase 8). The owner has not enrolled yet, so live pushes are `NOT_RUN_CREDENTIALS`.
- **Behavior.**
  - Fixed endpoints: `api.sandbox.push.apple.com` and `api.push.apple.com`, port 443.
  - HTTP/2 only, and the HTTP version actually used is checked.
  - ES256 provider tokens are refreshed every 50 minutes.
  - Payloads are minimal by default; the item title is sent only when the device opted in.
  - Every documented response reason is classified (D-42). A 5xx is retried no sooner than 15 minutes later. 400 and 410 token errors deactivate the device's token.
- **Verified (M6b).** Against nghttpd on loopback: TLS with ALPN h2 and a full HTTP/2 exchange, plus the adapter's exact headers and payload. The provider token signature was checked with openssl.

## Model endpoint (OpenAI-compatible, MODEL-01)

- **Setup.** In `model`:
  - `provider: "openAICompatible"`, `endpoint` (for example `http://127.0.0.1:8080/v1` for a local server), `modelIdentifier` and the optional `apiKeySecret`;
  - `dataSharing` (`localOnly` for loopback or private endpoints, `remoteMinimized` to allow a remote one);
  - `requestTimeoutSeconds`.
- **Behavior.**
  - Chat Completions with JSON output.
  - Content is minimized and validated by the extraction pipeline before and after the call.
  - Model outages make items wait; nothing is invented.
  - A daily request budget (`maxRequestsPerDay`) is configured but not yet enforced.
