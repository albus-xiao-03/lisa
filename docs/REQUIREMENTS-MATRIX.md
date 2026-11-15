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
| MAIL-01 | `LisaMIME`, `LisaIMAP` | — | Live mailbox | Planned (P2, P6) |
| MAIL-02 | `LisaMIME`, `LisaReview` | — | — | Planned (P2, P4) |
| CAL-01 | `LisaICalendar`, `LisaCalendarFeeds` | — | — | Planned (P2, P6) |
| CAL-02 | `LisaIngestion` | — | — | Planned (P4) |
| EVENT-01 | `LisaMatching`, `LisaReview`, `.ics` export | — | — | Planned (P2, P4) |
| NEWS-01 | `LisaFeeds`, `LisaRanking`, `LisaNewsFeeds` | — | — | Planned (P2, P6) |
| NEWS-02 | `LisaXSource` | — | Live X API | Planned (P6) |
| NEWS-03 | `LisaDiscordSource` | — | Live Discord bot | Planned (P6) |
| NEWS-04 | Capture workflow, publisher feeds | — | Apple share sheet | Planned (P4, P8) |
| MEM-01 | `LisaDomain/Preference.swift`, `LisaOwnerData` | Temporary checks: consequential keys | — | Partial (P1) |
| IDEA-01 | `LisaDomain/Idea.swift`, `Capture.swift`, `LisaOwnerData` | Temporary checks: lifecycle | — | Partial (P1) |
| MODEL-01 to MODEL-04 | `LisaInference`, `LisaOpenAICompatible` | — | Live endpoint | Planned (P2, P6) |
| PLAN-01 to PLAN-05 | `LisaPlanning`, `LisaAgenda` | — | — | Planned (P2, P4) |
| BRIEF-01 to BRIEF-04 | `LisaBriefComposer`, `LisaAgenda` | — | — | Planned (P2, P4) |
| REM-01 to REM-04 | `LisaPolicy`, `LisaAgenda`, `LisaDelivery` | Temporary checks: reminder actions | — | Partial (P1 model) |
| EMAIL-01 | `LisaDelivery`, `LisaSMTP`, `LisaMIME` | — | Live SMTP | Planned (P4, P6) |
| CALL-01 | `LisaPolicy`, `LisaDelivery`, `LisaTwilio` | — | Live Twilio | Planned (P2, P4, P6) |
| NOTIFY-01 | `LisaPolicy`, `LisaAgenda`, `LisaDelivery` | — | Devices | Planned (P2, P4) |
| NOTIFY-02 | `LisaDomain/DeviceRegistration.swift`, `LisaDevices`, `LisaAPI` | Temporary checks: token redaction | Devices | Partial (P1 model) |
| NOTIFY-03 | `LisaDomain/NotificationIntent.swift`, `Delivery.swift`, `LisaDelivery` | Temporary checks: change identities | — | Partial (P1 model) |
| NOTIFY-04 | `LisaAPNs`, `LisaCurl`, `LisaCrypto` | — | Live APNs | Planned (P6); Apple-specific details need documentation access |
| NOTIFY-05 | `LisaClient`, `Apps/` | — | Devices | Planned (P5, P8) |
| NOTIFY-06 | `LisaPolicy`, `LisaAPNs`, `Apps/` | — | Devices | Planned (P2, P6, P8) |
| NOTIFY-07 | `LisaRuntime`, `docs/OPERATIONS.md`, `docs/SETUP-APPLE.md` | — | VPN route, devices | Planned (P4–P8) |
| UI-01 to UI-03 | `LisaPresentation`, `LisaClient`, `Apps/` | — | Mac, iPhone, iPad | Planned (P5, P8) |
| SIRI-01, SIRI-02 | `Apps/Shared` App Intents, `docs/SETUP-APPLE.md` | — | Devices | Planned (P8) |
| APPLE-01 | `Apps/project.yml` (XcodeGen), entitlements | — | Mac | Planned (P8) |
| API-01 to API-03 | `LisaAPIContract`, `LisaAPI`, `LisaAPIServer` | — | — | Planned (P5, P7) |
| SEC-01 | `LisaSecrets`, `LisaRedaction`, Keychain (P8) | Temporary checks: references, protected files, redaction — PASS | Keychain on devices | Partial (P1) |
| SEC-02 | `LisaHTTP`, `LisaCurl`, `LisaXML`, `LisaHTMLText` | — | — | Planned (P2, P6) |
| SEC-03 | `docs/SECURITY.md`, `LisaInference` minimization | — | — | Planned (P4, P5) |
| OPS-01 | `LisaRuntime`, `LisaLogging` | Temporary checks: redacted logs, rotation — PASS | — | Partial (P1 logging) |
| OPS-02 | Configuration bounds across modules | Temporary checks: log growth — PASS | — | Partial (P1) |
| CLI-01 | `lisa` executable | — | — | Planned (P5, P7) |
| DEMO-01 | `LisaDemo`, `Fixtures/` | — | — | Planned (P5) |
| CFG-01 to CFG-03 | `LisaConfig`, `config.example.json5`, `docs/SETUP-LINUX.md` | — | — | Planned (P5) |

## Linux acceptance (R1 §16.1)

L01–L33 are verified first by temporary checks in the phases shown in plan §9.1. They are then verified by the persistent Phase T suite in `Tests/`. The status of each test is recorded here as those runs complete.

| Test | Status |
|---|---|
| L01 | Partial: Phase 1 modules build in debug and release on Linux (aarch64, Swift 6.4.2) |
| L02–L33 | Planned |

## Apple acceptance (R1 §16.4)

| Test | Status |
|---|---|
| A01–A18 | `NOT_RUN_ENVIRONMENT`. A12–A14, A17 and A18 also need an Apple Developer account, an APNs key or the owner's VPN route (`NOT_RUN_CREDENTIALS`). |
