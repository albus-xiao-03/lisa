<!-- Lisa R1 implementation report (R1 §17): what was delivered, how it was verified, the known limitations and the steps the owner takes next. -->
# Lisa R1 — Implementation report

Status on 2026-11-18, at the commit that adds this file on `main`.

- **Delivered:** the portable Swift package. It holds the domain and its engines, SQLite persistence, the application services, the host runtime, the versioned API with its network server, the command-line interface, the offline demonstration and every production adapter. The iPhone, iPad and Mac apps are written in `Apps/` against the same API.
- **Linux handoff complete.** The persistent suite in `Tests/LisaTests/` (376 tests) passes every Linux acceptance test, L01 to L33, plus R1 §16.2 and §16.3. It passes in debug and release, offline and with synthetic data only.
- **Not release-verified.** The Apple apps were syntax-checked with `swiftc -parse` on Linux; they were not compiled for any Apple platform. No live service was contacted. The Apple acceptance tests A01 to A18 have not run.

## 1. Toolchain and dependency versions

| Item | Version |
|---|---|
| Swift | 6.4.2 (`swift-6.4.2-RELEASE`), Swift 6 language mode, target `aarch64-unknown-linux-gnu` |
| Build machine | Debian GNU/Linux 13 (trixie) in a Docker Hardened Images build, aarch64 |
| System libraries (linked) | SQLite 3.46.1, libxml2 2.9.14, libcurl 8.14.1 (with nghttp2 1.64.0 and OpenSSL 3.5.7). ICU 76.1 is installed as `docs/SETUP-LINUX.md` lists, but Foundation uses the toolchain's own ICU |
| Tools | pkg-config 1.8.1; swift-format 6.4.2 (lint); the `openssl` command 3.5.7, for the certificates, keys and TLS relay of the loopback test servers; `nghttpd` 1.64.0, optional, for the HTTP/2 milestone check M6b |
| Apple toolchain | none: no Xcode or macOS machine was available |

Swift packages pinned in `Package.resolved`, all approved in plan §11 (REC-DEP-01, -03, -04 and -06, with their transitive dependencies):

| Package | Version | Required by | License |
|---|---|---|---|
| swift-argument-parser | 1.8.2 | `LisaCLI` (the `lisa` command) | Apache License 2.0 with the Swift Runtime Library Exception |
| swift-crypto | 5.1.1 | `LisaCrypto` (credentials, provider tokens) | Apache License 2.0; its vendored BoringSSL is under a combination of the ISC and OpenSSL licenses |
| swift-asn1 | 1.7.4 | swift-crypto | Apache License 2.0 |
| swift-nio | 2.105.0 | `LisaAPIServer` | Apache License 2.0 |
| swift-nio-ssl | 2.37.6 | `LisaAPIServer` (TLS listener) | Apache License 2.0; its vendored BoringSSL is under a combination of the ISC and OpenSSL licenses |
| swift-atomics | 1.3.1 | swift-nio | Apache License 2.0 with the Swift Runtime Library Exception |
| swift-collections | 1.7.6 | swift-nio | Apache License 2.0 with the Swift Runtime Library Exception |
| swift-system | 1.9.0 | swift-nio | Apache License 2.0 with the Swift Runtime Library Exception |

swift-certificates, which swift-nio-ssl declares only for its own tests, is not resolved.

The package has 51 products (50 libraries and the `lisa` executable) and 56 targets, the test target included.

## 2. Build and test commands and outcomes

The final verification ran on 2026-11-18 on the code as committed, after `swift package clean`, so every object file was rebuilt:

| Command | Outcome |
|---|---|
| `swift build --build-tests` | Complete in 40.2 s, 0 warnings |
| `.build/out/Products/Debug-linux-aarch64/LisaTests-test-runner --testing-library swift-testing` | 376 tests in 66 suites passed |
| `swift build -c release --build-tests` | Complete in 105.1 s, 0 warnings |
| `.build/out/Products/Release-linux-aarch64/LisaTests-test-runner --testing-library swift-testing` | 376 tests in 66 suites passed |
| `swift format lint --configuration .swift-format -r Sources` (likewise `Apps` and `Tests`) | 0 findings |
| `swiftc -parse` over `Apps/Mac` with `Apps/Shared` (89 files), and over `Apps/Companion` with `Apps/Shared` (71 files) | Exit 0. This is a syntax check on Linux only; nothing was compiled for any Apple platform |

- **Tests by folder:** 188 unit, 127 integration, 24 recovery, 3 acceptance and 34 adapter tests. Each test is also tagged with its kind: the L03 tests carry both the integration and recovery tags, and L32's tests carry one or the other. The 34 adapter tests run 80 cases.
- **Temporary checks.** These are the phase-by-phase verification packages kept outside the repository, in the ignored `.tmp/`. Three of them were re-run unchanged in Phase 9; the other temporary results the matrix cites (for example milestones M6a and M6b, the configuration and doctor checks, the `lisa serve` checks and the URLSession checks) are from Phases 5 to 8.
  - The presentation checks passed 31 of 31, and the Mac presentation checks 89 of 89.
  - The R1 verification package passed 113 of 116. Its 3 failing checks were written for schema version 3, which migration v4, added in Phase T (D-23), changed. Two assert that version. The third numbers its deliberately broken migration 4, so the real v4 now runs in its place and nothing fails.
  - The persistent `Recovery/L23*` suites check the same behaviour against the latest version: migration, backfill, backups, refusal of a newer schema, and a failed migration that leaves the previous data recoverable.

## 3. Requirement coverage and remaining failures

`docs/REQUIREMENTS-MATRIX.md` gives each requirement and acceptance test its implementation, its evidence and the platform that evidence comes from.

- **Linux acceptance (R1 §16.1 to §16.3):** L01 to L33, §16.2 and §16.3 all pass in the persistent suite. Each row names its suites and their kinds.
- **Apple acceptance (R1 §16.4):** A01 to A18 are `NOT_RUN_ENVIRONMENT`. A12 to A14, A17 and A18 also need an Apple Developer account, an APNs key or the owner's VPN route (`NOT_RUN_CREDENTIALS`).
- **Requirements, by the kind of evidence they have:**
  - **Implemented and verified on Linux:** ARCH-01, ARCH-02 and ARCH-04, DATA-01 to DATA-05, INGEST-01, MAIL-02, CAL-02, EVENT-01, MEM-01, PLAN-01 to PLAN-05, REM-01 to REM-04, SEC-02, SEC-03, OPS-01, OPS-02, CLI-01, DEMO-01 and CFG-01 to CFG-03 (CFG-03 is the Linux setup documentation).
    - The macOS build of the package (ARCH-01) has not run.
  - **Implemented; the API side is verified on Linux, and the apps' display is written but not compiled:** BRIEF-01 to BRIEF-04, whose full view of left-out items the apps list under the brief.
  - **Adapter verified on Linux, live service not run:** MAIL-01, CAL-01, NEWS-01 to NEWS-03, MODEL-01 to MODEL-04, EMAIL-01, CALL-01 and NOTIFY-04.
  - **Host side verified on Linux, Apple side written but not compiled:** ARCH-03, IDEA-01, NEWS-04, NOTIFY-01, NOTIFY-02, NOTIFY-05 to NOTIFY-07, UI-01 to UI-03, API-01 to API-03 and SEC-01.
  - **Partial:** NOTIFY-03. The host side is verified on Linux, but devices do not yet reconcile notifications they already show (§7).
  - **Apple only, written but not compiled:** SIRI-01, SIRI-02 and APPLE-01.
- **Remaining failures:** none in the persistent suite. The only failing checks are the 3 temporary checks described in §2.
- **Gaps in the persistent evidence:**
  - The view models in `LisaPresentation` have only temporary checks, the presentation packages above.
  - The TLS device listener: URLSession on Linux cannot be made to trust a certificate authority generated at run time, so the network tests use the plain HTTP that the server allows on loopback.
  - STARTTLS (IMAP in milestone M6a, SMTP in the Phase 6 checks) and APNs over a real HTTP/2 connection (milestone M6b) have only temporary checks. The persistent suite's loopback servers cannot upgrade a connection or speak HTTP/2.
  - X, Discord, Twilio and APNs run on a scripted transport, because their endpoints are fixed public hosts. Their timeouts are therefore reported by the transport rather than really elapsed. Real elapsed timeouts are covered by the IMAP, SMTP, feed, page and model suites.
  - L24 runs the demonstration through `DemoScenario.run`, which `lisa demo` calls. Only temporary checks ran the `lisa` binary itself.
- **Defects found by the persistent suite, all fixed** (recorded in `docs/DECISIONS.md` and the matrix):
  - **Unit tests (5):** a mail header field limit, a multipart part limit, a multipart part without a boundary, an extraction end bound, and the calendar's total occurrence limit.
  - **Integration and recovery tests (9):** a duplicate "soon" reminder; raw content kept for Message-ID duplicates; a missing calendar file read as an empty snapshot; a removal note keeping the day uncertain; failing sources reported as checked; renamed extracted tasks duplicated; crash loops not bounded by the attempt limit; accepted blocks losing their warning; oversized snapshot files skipped.
  - **API and client tests (2):** captures deduplicated across devices instead of per caller (fixed with migration v4), and a 413 not replayed.
  - **Device and notification tests (2):** a push token accepted for another app's topic, and a call placed after reminders that had reached no one.
  - **Close-out review (Phase 9):** the review found that nothing checked a failed migration any more, and that brief length, shared Apple News and the configuration had only temporary checks. Their new suites found two problems, both fixed: the owner's own shares were reported as an unchecked source, and the brief's left-out items, which it says are in the full view, were not available to clients. The API now returns them as `omittedItems`.
  - **Test fix:** one unit test whose random identifier could fail it by chance now uses a fixed one.

## 4. Production adapters and live verification

| Adapter | Requirement | Verified on Linux | Live |
|---|---|---|---|
| IMAP, Lisa's mailbox (`LisaIMAP` over libcurl) | MAIL-01 | L18: real libcurl and implicit TLS against a scripted loopback server. M6a (temporary) also covered STARTTLS | `NOT_RUN_CREDENTIALS` |
| SMTP (`LisaSMTP`) | EMAIL-01 | L18: real libcurl and implicit TLS against a scripted loopback server | `NOT_RUN_CREDENTIALS` |
| HTTPS calendar subscriptions | CAL-01 | L18: real libcurl and TLS against a loopback HTTPS server | `NOT_RUN_CREDENTIALS` |
| News feeds and captured pages | NEWS-01 | L18: real libcurl and TLS against a loopback HTTPS server | `NOT_RUN_ENVIRONMENT` |
| X API v2 | NEWS-02 | L18: scripted transport | `NOT_RUN_CREDENTIALS`; the fields parameter name needs a live check |
| Discord bot | NEWS-03 | L18: scripted transport | `NOT_RUN_CREDENTIALS` |
| Twilio calls (`LisaTwilio`) | CALL-01 | L18: scripted transport | `NOT_RUN_CREDENTIALS` |
| APNs (`LisaAPNs`) | NOTIFY-04 | L27 and L28: scripted transport, and a provider token checked with `openssl`. M6b (temporary) also covered real HTTP/2 against `nghttpd` | `NOT_RUN_CREDENTIALS` |
| OpenAI-compatible model (`LisaOpenAICompatible`) | MODEL-01 | L18: real libcurl and TLS against a loopback HTTPS server | `NOT_RUN_CREDENTIALS` |
| Local files (`LisaLocalSources`, `lisa import`) | INGEST-01 | L07 and the demonstration | Not applicable |
| Dry-run transports for email, calls, push and local notifications | CFG-02, EMAIL-01, CALL-01, NOTIFY-04 | Throughout the suite | Not applicable |

No production adapter has received live verification. Email, calls and push default to dry run (R1 CFG-02); the Mac app's local notifications are always live.

## 5. Apple builds and device checks

- No Apple build and no device check was executed, because no Mac, Xcode or device was available.
- `Apps/` was syntax-checked with `swiftc -parse` on Linux (89 Mac and shared files, 71 companion and shared files). It was not compiled for any Apple platform. The XcodeGen definition `Apps/project.yml` has not been turned into a project.
- The view models the apps display (`LisaPresentation`) build and pass their temporary checks on Linux.
- A01 to A18 are `NOT_RUN_ENVIRONMENT`. The checklist is `docs/SETUP-APPLE.md` §8.

## 6. Known unsupported formats and provider limitations

- **Calendars (D-11):**
  - Only `VEVENT` with `VTIMEZONE` is read. `VTODO`, `VJOURNAL`, `VFREEBUSY` and `VALARM` are ignored.
  - A recurrence rule with parts outside the documented subset shows only the first occurrence, with a warning, and leaves availability uncertain. Examples are `FREQ=HOURLY` or finer, `BYHOUR`, `BYYEARDAY` and `BYWEEKNO`.
  - `RDATE;VALUE=PERIOD` dates are ignored with a warning while the rest of the series is expanded. `RECURRENCE-ID;RANGE=THISANDFUTURE` is applied to one instance only, with a warning that later occurrences may be wrong. Both leave availability uncertain.
  - An unknown `TZID` is read as floating time.
  - Local calendars are files or directories only. Remote calendars are HTTPS subscriptions only.
- **Mail:**
  - IMAP folders with non-ASCII names are not supported.
  - Non-ASCII subjects of sent mail are shortened to about 39 bytes, because LisaMIME does not fold them over several encoded words.
  - libcurl chooses the SASL mechanism the server advertises, always inside verified TLS.
  - Text in a character set that neither Foundation nor the platform's `iconv` decodes becomes a visible marker, never garbled text (D-13). On macOS, linking `libiconv` is not verified.
- **Feeds and pages:**
  - Malformed feeds are read with recovery and labeled "not well-formed".
  - A page that needs signing in or payment, is not text, is too large or cannot be reached stays title-only, with the reason.
  - Apple News items are never fetched: they arrive only as shared links or text.
- **X:** the fields parameter is `tweet.fields` in one place and `post.fields` in another of X's documents; Lisa sends `tweet.fields` and needs a live check. The first synchronization reads only the newest page.
- **Discord:** the bot needs View Channel and Read Message History, and the Message Content privileged intent. Messages that intent withholds are never stored as empty posts: a capability note explains them, or the source fails as `capabilityDenied` when nothing is readable.
- **Twilio:** a 5xx, or a failure after the request was sent, is an unknown outcome, because call creation has no idempotency key. It is never resent automatically.
- **SMTP:** a server that offers no authentication receives the message unauthenticated, still inside verified TLS.
- **APNs:**
  - HTTP/2 is required.
  - Only `ExpiredProviderToken` regenerates the provider token.
  - A 5xx is retried no sooner than 15 minutes later.
  - Apple keeps only one stored notification per app for an offline device.
- **The companions' URLSession transport on Linux:** IPv6 literal hosts are refused, `resourceTimeout` is ignored, and proxy variables apply even on loopback (D-45). Its behaviour on Apple platforms is unverified.
- **Raw content (D-32):** if the same message arrives through another source between preparation and commit, or the commit fails, its raw bytes stay until raw-content retention purges them. With that retention at zero, they are never purged.

## 7. Remaining placeholders and incomplete features

- **TODO markers:** there are no `TODO` or `FIXME` markers in `Sources/` or `Apps/`.
- **Placeholders the owner replaces before an Apple build:**
  - the team ID `TEAMID0000` in `Apps/Config/Signing.xcconfig`, overridden in the ignored `Signing.local.xcconfig`;
  - the placeholder bundle identifiers `org.example.lisa.companion` and `org.example.lisa.mac` in `Apps/project.yml`;
  - the APNs team ID, key ID, signing-key reference and `topics` (the companion's bundle identifier, `org.example.lisa.companion`) in `config.example.json5`.
- **Incomplete:**
  - The Apple apps, the Siri App Intents and the morning-alarm automation are written but have never been compiled or run.
  - Reconciling the other devices when they next connect (NOTIFY-03) is partial. The host suppresses obsolete pending and future deliveries for every device (L29), but plan §6.4's device step is not implemented: on their next activation, devices do not remove notifications already shown for subjects resolved meanwhile. A device removes its delivered notifications only when it is unpaired. R1 does not require that removal to be immediate.
  - In client mode the Mac app shows no notifications at all; only its embedded host posts local notifications (the owner's choice, D-51).
  - Editing a task cannot remove its estimate, because the API has no way to express that.
  - The companion sends its queue when it returns to the foreground and on Send Now; there is no trigger for network changes.
  - Some display logic lives in the SwiftUI views and is untested on Linux: which screen a notification opens, the words for states, and the changed-fields check.

## 8. Steps for the owner

1. **Linux host.**
   - Install the toolchain and libraries in `docs/SETUP-LINUX.md`.
   - Build, run the test suite with the commands in §2, and run `swift run lisa demo --data-dir <empty directory>`.
2. **Configuration.**
   - Start from `config.example.json5`: the zone, approved email addresses and phone number, sources, quiet hours and limits.
   - Give every secret as a reference (`env:`, `file:` or, in the Apple apps, `keychain:`), never as a value.
   - Run `lisa doctor`.
3. **Live integrations, one at a time,** with the setup and verification steps in `docs/INTEGRATIONS.md`.
   - The integrations are Lisa's mailbox, calendar subscriptions, feeds, X, Discord, SMTP, Twilio and the model endpoint.
   - Keep each channel a dry run until its live check passes, then set its `delivery.modes` entry to `live` deliberately.
   - Record each result in `docs/REQUIREMENTS-MATRIX.md`.
4. **Apple apps,** following `docs/SETUP-APPLE.md`.
   - Enroll in the Apple Developer Program.
   - Create the App IDs with Push Notifications and an APNs key, and fill in `Signing.local.xcconfig`.
   - Generate the project with XcodeGen, then build and run the Mac app and the companion.
   - Pair the iPhone and iPad and enable push.
   - Set up Siri and the morning-alarm automation.
5. **Acceptance on devices.** Run A01 to A18 from `docs/SETUP-APPLE.md` §8 on the Mac, iPhone and iPad, including the VPN route for devices away from home (NOTIFY-07). Record the results in the matrix.
