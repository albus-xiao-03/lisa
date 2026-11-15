<!-- Traceability from every R1 requirement and acceptance test to implementation, automated evidence and manual checks. -->
# Lisa — Requirements Matrix

Required by R1 §16. Columns:
- **Implementation:** modules or files.
- **Automated evidence:** temporary implementation checks (in `.tmp/`, not committed) until the persistent Phase T suite exists in `Tests/`.
- **Manual / Apple:** checks that need a Mac, iPhone, iPad or live credentials.

Statuses follow R1 §1: `PASS`, `FAIL`, `NOT_RUN_ENVIRONMENT`, `NOT_RUN_CREDENTIALS`, `OUT_OF_SCOPE`. "Planned (Pn)" marks work not yet done.

## Requirements

| ID | Implementation | Automated evidence | Manual / Apple | Status |
|---|---|---|---|---|
| ARCH-01 | `Package.swift` (Swift 6 mode, no Apple frameworks); Linux networking differences (Phase 6) | Linux debug/release builds | macOS build | Partial: package and foundations (P1) |
| ARCH-02 | Module split, plan §5.1 | — | — | Partial (P1) |
| ARCH-03 | `LisaRuntime` lock, `LisaHost` | — | — | Planned (P5, P7) |
| ARCH-04 | Approved dependencies only, plan §11 | — | — | Ongoing |
| DATA-01 | `Sources/LisaDomain/*` | Temporary checks: lifecycles, identities | — | Implemented (P1); persistence in P3 |
| DATA-02 | `LisaStore` | — | — | Planned (P3) |
| DATA-03 | `Sources/LisaTime/*` | Temporary checks: DST gap/overlap, day lengths, date-only, ambiguous dates — PASS | — | Implemented (P1) |
| DATA-04 | `LisaReview`, `LisaStore` | — | — | Planned (P3, P4) |
| DATA-05 | `LisaStore`, `LisaOwnerData` | — | — | Planned (P3, P4) |
| INGEST-01 | `LisaIngestion` | — | — | Planned (P4) |
| MAIL-01 | `LisaMIME` (MIME, charsets, forwards, attachments), `LisaHTMLText`; IMAP in P6 | Temporary checks PASS (Linux): plain, HTML-only, forwarded (inline and attached), multipart, malformed, charsets | Live mailbox | Partial: parsing implemented (P2); IMAP P6 |
| MAIL-02 | `LisaMIME` (Message-ID, references), `LisaInference` (addressing, confirmation) | Temporary checks PASS (Linux): identity headers; CC never confirms | — | Partial (P2); dedup and storage P3/P4 |
| CAL-01 | `LisaICalendar` (subset in D-11); HTTPS feeds in P6 | Temporary checks PASS (Linux): recurrence across DST, EXDATE, overrides, cancellation, transparency, all-day, VTIMEZONE, floating, unsupported warnings, bounds | — | Partial: engine implemented (P2) |
| CAL-02 | `LisaIngestion` | — | — | Planned (P4) |
| EVENT-01 | `LisaMatching`, `LisaICalendar` export, `LisaDomain/EventProposal.swift` | Temporary checks PASS (Linux): matched, possible, not found, dismissed, awaiting refresh; export round trip | — | Partial: engine (P2); review service P4 |
| NEWS-01 | `LisaFeeds`, `LisaXML`, `LisaRanking`; ingestion P4/P6 | Temporary checks PASS (Linux): RSS/Atom, mutes, duplicates, reasons, title-only label | — | Partial: engines (P2) |
| NEWS-02 | `LisaXSource` | — | Live X API | Planned (P6) |
| NEWS-03 | `LisaDiscordSource` | — | Live Discord bot | Planned (P6) |
| NEWS-04 | Capture workflow, publisher feeds | — | Apple share sheet | Planned (P4, P8) |
| MEM-01 | `LisaDomain/Preference.swift`, `LisaOwnerData` | Temporary checks: consequential keys | — | Partial (P1) |
| IDEA-01 | `LisaDomain/Idea.swift`, `Capture.swift`, `LisaOwnerData` | Temporary checks: lifecycle | — | Partial (P1) |
| MODEL-01 to MODEL-04 | `LisaInference` (provider boundary, validator, bounded repair, deterministic provider, data-sharing policy); HTTP adapter P6 | Temporary checks PASS (Linux): quotes, confirmation authority, dates, one repair, remote refused by policy, minimization | Live endpoint | Partial: core implemented (P2) |
| PLAN-01 to PLAN-05 | `LisaPlanning` (algorithm in D-15); service P4 | Temporary checks PASS (Linux): §16.2 fixture exact, no overlaps, determinism, locks preserved, allocation cap, provisional, rejections | — | Partial: engine implemented (P2) |
| BRIEF-01 to BRIEF-04 | `LisaBriefComposer` (D-18); versions and scheduling P4 | Temporary checks PASS (Linux): parity, no URLs or IDs in speech, could-not-check vs nothing-new, trimming keeps material | — | Partial: composer implemented (P2) |
| REM-01 to REM-04 | `LisaPolicy` (ReminderPlanner, RecoveryPolicy, DeliveryTiming); services P4 | Temporary checks PASS (Linux): no bursts, date-only needs a time, quiet-hour deferral, recovery coalescing, catch-up limit | — | Partial: rules implemented (P2) |
| EMAIL-01 | `LisaDelivery`, `LisaSMTP`, `LisaMIME` | — | Live SMTP | Planned (P4, P6) |
| CALL-01 | `LisaPolicy/CallEligibility.swift`, `UrgencyRule.swift`; Twilio P6 | Temporary checks PASS (Linux): every condition enforced and reported | Live Twilio | Partial: rules implemented (P2) |
| NOTIFY-01 | `LisaPolicy/NotificationRouting.swift`; intents P4 | Temporary checks PASS (Linux): both devices by default, per-device reasons | Devices | Partial: routing implemented (P2) |
| NOTIFY-02 | `LisaDomain/DeviceRegistration.swift`, `LisaDevices`, `LisaAPI` | Temporary checks: token redaction | Devices | Partial (P1 model) |
| NOTIFY-03 | `LisaDomain/NotificationIntent.swift`, `Delivery.swift`, `LisaDelivery` | Temporary checks: change identities | — | Partial (P1 model) |
| NOTIFY-04 | `LisaAPNs`, `LisaCurl`, `LisaCrypto` | — | Live APNs | Planned (P6); Apple-specific details need documentation access |
| NOTIFY-05 | `LisaClient`, `Apps/` | — | Devices | Planned (P5, P8) |
| NOTIFY-06 | `LisaPolicy/NotificationContentPolicy.swift`, `UrgencyRule.swift`; APNs P6; Apple P8 | Temporary checks PASS (Linux): generic content, opt-in titles truncated, Time Sensitive only for urgent confirmed deadlines | Devices | Partial: policy implemented (P2) |
| NOTIFY-07 | `LisaRuntime`, `docs/OPERATIONS.md`, `docs/SETUP-APPLE.md` | — | VPN route, devices | Planned (P4–P8) |
| UI-01 to UI-03 | `LisaPresentation`, `LisaClient`, `Apps/` | — | Mac, iPhone, iPad | Planned (P5, P8) |
| SIRI-01, SIRI-02 | `Apps/Shared` App Intents, `docs/SETUP-APPLE.md` | — | Devices | Planned (P8) |
| APPLE-01 | `Apps/project.yml` (XcodeGen), entitlements | — | Mac | Planned (P8) |
| API-01 to API-03 | `LisaAPIContract`, `LisaAPI`, `LisaAPIServer` | — | — | Planned (P5, P7) |
| SEC-01 | `LisaSecrets`, `LisaRedaction`, Keychain (P8) | Temporary checks: references, protected files, redaction — PASS | Keychain on devices | Partial (P1) |
| SEC-02 | `LisaXML` (D-12), `LisaHTMLText` (D-14); network boundaries P6 | Temporary checks PASS (Linux): XXE, entity expansion, external DTD not loaded, malformed recovery, script removal | — | Partial: content boundaries implemented (P2) |
| SEC-03 | `docs/SECURITY.md`, `LisaInference` minimization | — | — | Planned (P4, P5) |
| OPS-01 | `LisaRuntime`, `LisaLogging` | Temporary checks: redacted logs, rotation — PASS | — | Partial (P1 logging) |
| OPS-02 | Limits in every engine (`ICalendarLimits`, `MIMELimits`, `XMLReadLimits`, `ModelUsageLimits`, planner caps) | Temporary checks PASS (Linux): recurrence and size limits, log growth | — | Partial (P1–P2) |
| CLI-01 | `lisa` executable | — | — | Planned (P5, P7) |
| DEMO-01 | `LisaDemo`, `Fixtures/` | — | — | Planned (P5) |
| CFG-01 to CFG-03 | `LisaConfig`, `config.example.json5`, `docs/SETUP-LINUX.md` | — | — | Planned (P5) |

## Linux acceptance (R1 §16.1)

L01–L33 are verified first by temporary checks in the phases shown in plan §9.1. They are then verified by the persistent Phase T suite in `Tests/`. The status of each test is recorded here as those runs complete.

| Test | Status |
|---|---|
| L01 | Partial: Phase 1–2 modules build in debug and release on Linux (aarch64, Swift 6.4.2) |
| L04, L06, L11, L14 | Temporary checks PASS (engine level); persistent tests in Phase T |
| L22 | Partial: recurrence, message, document and model-output limits checked (temporary) |
| L02, L03, L05, L07–L10, L12, L13, L15–L21, L23–L33 | Planned |

## Apple acceptance (R1 §16.4)

| Test | Status |
|---|---|
| A01–A18 | `NOT_RUN_ENVIRONMENT`. A12–A14, A17 and A18 also need an Apple Developer account, an APNs key or the owner's VPN route (`NOT_RUN_CREDENTIALS`). |
