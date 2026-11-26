<!-- X1 setup and session sheet (plan R2 §10.5 N-1, E-1, E-2; §10.6 X1; §10.8). -->
# Apple setup and session X1

X1 runs the proof-only app **Lisa Proof** (scheme `LisaProof`, `Apps/Proof`) on your Mac, iPhone and iPad. It decides three things:
- **N-1:** which nearby design R2 builds. Design A uses pair-specific pre-shared keys over TLS 1.2 with an ECDHE-PSK suite. Design B uses roster-bound mutual TLS 1.3 with Secure Enclave identities. A design is adopted only if its own proof passes on all nine cells (three pairs × three network conditions).
- **E-1:** whether each device can fetch a public URL safely with Core unavailable.
- **E-2:** whether the portable modules build for each Apple platform.

Lisa Proof never ships, uses only synthetic identities, and shows a permanent PROOF ONLY banner. Claude has no Apple SDK: it type-checks the whole target on Linux against stand-ins for the Apple frameworks (`docs/DECISIONS.md` D-70), but has never built or run it. X1 is its first Apple build. Attempt 1 (2026-11-26) stopped at a compiler failure that the fix in `f03cf24` removes.

## 1. Prerequisites

- A Mac with Xcode 26 and XcodeGen 2.46.0, an iPhone and an iPad on iOS/iPadOS 18 or later, and your Apple Developer team (the devices registered for development). See [docs/SETUP-APPLE.md](../../docs/SETUP-APPLE.md) §1–§3 for XcodeGen and signing (`Apps/Config/Signing.local.xcconfig`).
- For the no-access-point cells: Wi-Fi and Bluetooth on, each device joined to no network.
- For E-1: an https URL you control or may fetch; the controlled names, listener, proxy, NAT64 network (macOS Internet Sharing) and split-tunnel VPN each case names (`lisa-verify guide OV-APPLE-X1-FETCH-0N`).
- The harness on the Mac: `swift run lisa-verify quickstart` from the repository's root.

## 2. Build, sign and install

```sh
cd Apps && xcodegen generate --spec project.yml
xcodebuild -scheme LisaProof -destination 'platform=macOS' LISA_PROOF_COMMIT=$(git rev-parse HEAD) build 2>&1 | tee ~/LisaVerify/x1-build-mac.log
xcodebuild -scheme LisaProof -destination 'platform=iOS,id=<iPhone UDID>' LISA_PROOF_COMMIT=$(git rev-parse HEAD) build 2>&1 | tee ~/LisaVerify/x1-build-iphone.log
xcodebuild -scheme LisaProof -destination 'platform=iOS,id=<iPad UDID>' LISA_PROOF_COMMIT=$(git rev-parse HEAD) build 2>&1 | tee ~/LisaVerify/x1-build-ipad.log
```

**If a build fails,** send:
- the output of `xcodebuild -version`;
- every error, with file and line: the `x1-build-*.log` above, or Xcode's Issue navigator (Report navigator › the build › "All Messages"). Every error, not only the first, so one fix covers them all.

Install and launch the app on each device from Xcode (Product › Run), or with `xcrun devicectl device install app`. Then check the signed products:

```sh
swift run lisa-verify preflight apple --app <DerivedData path>/LisaProof.app
```

Expected: the bundle `org.example.lisa.proof` (or your own prefix), one keychain access group, the App Sandbox on the Mac, a development profile listing each device, and no line starting "stops:".

The E-2 cases record each build (`OV-APPLE-X1-01` Mac, `-02` iPhone, `-03` iPad):

```sh
swift run lisa-verify run --mode device --session X1        # prints the run ID; use it below
swift run lisa-verify observe <run-id> OV-APPLE-X1-01 --status pass --observed "LisaProof built for macOS" --evidence ~/LisaVerify/x1-build-mac.log --platform macOS
```

On each device, the Results tab's "Run the portable-module check and write its record" adds the in-app E-2 check.

**Test plan X1** (`xcodebuild test -scheme LisaProof -testPlan X1 -destination …`) runs the UI smoke test of the proof app. The test plan names its two UI test targets by name. If Xcode shows them as missing (XcodeGen assigns its own identifiers), open the test plan in Xcode, remove the missing entries and add `LisaOwnerUITests-iOS` and `LisaOwnerUITests-macOS` once; record that you did.

## 3. The proof roster (once per installation)

1. On each device, Roster tab: enter a label (`mac`, `iphone`, `ipad`).
2. On the Mac press "Generate on this device", turn on "Show setup text", and enter that `lisa-proof-setup:1:` text on the iPhone and iPad.
3. Enter every other device's `lisa-proof-card:1:` text on each device ("Add peer card"). Universal Clipboard or AirDrop is fine; nothing secret is in a card.
4. For Design B: "Provision Design B identity" on each device. The card then carries the TLS key's pin, so re-share the updated cards.

## 4. The nine nearby cells (N-1)

Cells: `OV-NEAR-<pair>-<NN>`, pair `MI` (Mac–iPhone), `MP` (Mac–iPad), `IP` (iPhone–iPad); `01` shared Wi-Fi, `02` Internet disconnected at the router, `03` no access point. For each cell, and for each design in its own pass:

```sh
swift run lisa-verify pair-session OV-NEAR-MI-01 --devices mac,iphone --condition shared-wifi --run <run-id>
swift run lisa-verify guide OV-NEAR-MI-01
```

`pair-session` prints the session nonce and each device's role: the first device in `--devices` is the sender. Enter the run ID, case ID, role, devices, condition and nonce in each device's Results tab. Then follow the guide. Expected observations:
- **Peer identification and the exporter-bound hello:** both screens show the same session code and the peer's label. Design A records an ECDHE-PSK suite, which it needs on every session; Design B records TLS 1.3.
- **Refusals,** each fault from each device in turn: wrong exporter binding, unenrolled identity, unenrolled operation key, oversize frame header. The peer refuses before any data moves. Under Design B the unenrolled identity is a throwaway Secure Enclave certificate, which the peer's verify block refuses during the handshake.
- **Reconnection** after force-quitting the app, and after turning Wi-Fi off and on: a new authenticated session each time.
- **Deduplication:** start both within a second; one session survives.
- **Timing** by the sender: 100 timed frames, one 1 MiB frame and 20 clock exchanges, measured as round trips on one device.
- **Local network permission:** record the prompt and your choice, and once per device a denial that shows the unavailable state without retries.

Press "Finish cell: write the result record" on both devices, export `results.jsonl` and `evidence.jsonl` from each, and import every file:

```sh
swift run lisa-verify import-diagnostics <run-id> <file>
```

## 5. The fetch probe (E-1)

On each device in turn, with Core not configured: `OV-APPLE-X1-FETCH-01`–`09` in the Fetch tab, each with the network and controlled endpoints its guide names. Record what only you can observe, such as the listener or proxy log ("Owner observation"), then "Finish case". The passing outcomes:
- **01, 03, 04 and the public URLs of 05 and 06:** fetched.
- **02 (private destinations):** refused before connect, and your listener records no connection.
- **06, AAAA-only names and global IPv6 literals:** deferred to Core.
- **07 (the translated name):** never dialed by its AAAA.
- **08 (split-tunnel VPN):** one interface or failed closed.
- **09:** the platform facts are recorded. Also check, in Xcode's SDK, whether `nw_nat64_copy_prefixes_async` is declared:

  ```sh
  grep -r nw_nat64_copy_prefixes_async "$(xcrun --sdk iphoneos --show-sdk-path)/System/Library/Frameworks/Network.framework/Headers"
  ```

## 6. What X1 also records

These assumptions are recorded, never relied on silently: an accepted connection survives the listener's replacement every 15 minutes (Design A); the TLS 1.2 PSK exporter is available; unlisted suite values pass through `tls_ciphersuite_t(rawValue:)`; the `dnssd` module name; XcodeGen's `supportedDestinations`. If one fails, record what you saw (`observe … --status fail`); the design or the build needs a change, and the failure is the evidence.

## 7. What to return

```sh
swift run lisa-verify report <run-id>
swift run lisa-verify export <run-id> --redacted ~/Desktop/<run-id>-redacted.json
```

Share the redacted file, and say which design passed on which cells, if any. Selection follows a passed proof only. If both designs fail, nothing is adopted and a redesign comes back to you as a plan revision.
