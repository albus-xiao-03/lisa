<!-- Setting up and verifying Lisa's Apple apps: toolchain, project generation, signing, APNs, connecting devices, Siri and the morning alarm, and the A01–A18 checklist. -->
# Lisa — Apple setup

This guide covers the Mac app and the iPhone and iPad companion. None of the steps below has been run yet. Lisa was developed on Linux, where the Apple code is only syntax-checked (`swiftc -parse`) and has never been compiled. Every check in the last section is therefore `NOT_RUN`. Record what you observe there as you go.

## 1. What you need

- **A Mac with Xcode 26 or later.** The package's tools version is Swift 6.2. The apps' deployment targets are macOS 15 and iOS/iPadOS 18. Record the Xcode version you use under A01.
- **XcodeGen 2.46.0**, which generates the Xcode project from `Apps/project.yml` (REC-TOOL-01).
- **An Apple Developer Program membership** for push notifications and device signing (plan §6.9). Push notifications are probably unavailable to free personal teams; check this for your account.
- **An iPhone and an iPad** on iOS/iPadOS 18 or later, for the companion checks.

## 2. Generate and open the project

```sh
cd Apps
xcodegen generate --spec project.yml
open Lisa.xcodeproj
```

The generated project is not tracked by Git. Generate it again after pulling changes to `Apps/`.

| Target | Platform | Sources | Lisa packages it links |
|---|---|---|---|
| LisaCompanion | iPhone and iPad | `Companion/`, `Shared/` | LisaAPIContract, LisaClient, LisaPresentation |
| LisaMac | macOS | `Mac/`, `Shared/` | The same, plus LisaHost, LisaPorts, LisaSecrets, LisaRedaction |

## 3. Signing and identifiers

1. Create `Apps/Config/Signing.local.xcconfig` containing `DEVELOPMENT_TEAM = <your Team ID>`. Git ignores this file, and `Signing.xcconfig` includes it.
2. Replace the placeholder bundle identifiers `org.example.lisa.companion` and `org.example.lisa.mac` in your local copy of `Apps/project.yml` with identifiers registered to your team. Do not commit real identifiers.
3. Create one App ID per app. Enable Push Notifications and Time Sensitive Notifications on each.
4. Choose the configuration:
   - **Debug** uses development signing, so devices get sandbox APNs tokens. Its entitlements use `development`.
   - **Release** needs distribution signing (Ad Hoc or TestFlight), and its tokens are production tokens. An App Store release is out of scope.
5. **The Mac app.** It uses the hardened runtime and is not sandboxed (D-50). Its Keychain items use the data-protection keychain. That needs a build signed with a provisioning profile; without one, Keychain calls fail with `errSecMissingEntitlement`, and there is no fallback.

## 4. Push notifications on the host

1. Create an APNs authentication key (`.p8`) in your developer account, and note its Key ID and your Team ID.
2. Keep the key outside the repository. Refer to it from the host configuration by secret reference: `keychain:` in the Mac app, or `file:` with an owner-only file.
3. Configure `notifications.apns` as `docs/INTEGRATIONS.md` describes:
   - `teamID`, `keyID`, `signingKeySecret`;
   - `topics`, which are the bundle identifiers;
   - `environments`: `development` for Debug builds, `production` for Release builds.
4. Push delivery stays a dry run, which records instead of sending, until you set `delivery.modes.push` to `"live"`. `lisa doctor` and Settings and health show the mode.

## 5. Connecting devices to the host

- **Serving the API.** Use `lisa serve`, or the Mac app's embedded host. The API binds to loopback by default.
  - For devices, bind a local-network or VPN address with native TLS, or put a reverse proxy on a loopback or private address in front of it.
  - `docs/OPERATIONS.md` ("Serving the API") covers addresses, TLS and troubleshooting.
  - Lisa refuses plain HTTP off loopback on both the host and the device side.
- **TLS trust on devices.** Either of these works:
  - The host's certificate comes from an authority the devices already trust.
  - You supply the host's certificate or your own certificate authority in the companion: Connection → Host trust, optionally with the certificate's SHA-256 pin. The app then trusts only that anchor for the configured host name (D-48).

  Either way, the certificate must meet Apple's rules for TLS server certificates:
  - a subject alternative name that matches the host name or IP address you configure;
  - the server-authentication extended key usage;
  - for certificates from your own authority, a validity of at most 825 days.
- **App Transport Security.** Both Info.plists set `NSAllowsLocalNetworking`. It exempts connections to `.local` and unqualified host names from App Transport Security's public-Internet requirements, so a device can reach the Mac by its local name using your own certificate. It does not allow plain HTTP: Lisa's endpoint check accepts only `https` for anything but loopback, and the trust rules above still apply (D-50).
- **Local Network permission.** iOS and iPadOS ask the first time the companion connects to a local-network address. The usage description says why. If you deny it, the companion can reach the host only over another route, such as the VPN.
- **Pairing.**
  1. On the host, create a code with `lisa device pair-code`, or in the Mac app under Settings and health → Paired devices. A code lasts 10 minutes and only until the host restarts.
  2. In the companion, go to Connection, enter the host's address, add trust if needed, and enter the code.
  3. Pairing then offers to turn notifications on. Permission is requested only at that point.
  4. Pair each iPhone and iPad separately. Remove a device from the host with `lisa device revoke` or in the Mac app; its credential stops working immediately.
- **Away from home.** The intended remote arrangement is a private VPN route you configure to the Mac's HTTPS API, with the VPN address as the host address (plan §6.6). Lisa uses no relay, tunnel service or cloud backend.

## 6. Notifications on the devices

- **Categories.** Reminder, overdue, plan block, event proposal, commitment change and brief, with the actions from plan §6.5.
  - "Complete" needs the device unlocked.
  - Acknowledge and snooze also work from the lock screen.
- **Lock-screen privacy.** The text is generic by default. Each device can opt in to "show titles" in its notification settings. The system's Show Previews and Focus settings are respected.
- **Time Sensitive.** Used only for urgent confirmed deadlines when you opt in on the host. Each device's own notification settings still apply (A17).
- **Changed settings.** Changes made in Settings while the app is not running become known at its next launch or return to the foreground, and are reported to the host.
- **The Mac.**
  - With the embedded host, the Mac app posts a local notification at delivery time and handles its actions itself.
  - When a running `lisa serve` owns the data directory, the Mac app connects to it as a client and registers for APNs like a companion.

## 7. Siri, Shortcuts and the morning alarm (SIRI-01, SIRI-02)

- **Lisa's actions.** Six actions appear in the Shortcuts app and to Siri with no setup:
  - get today's brief;
  - get today's rundown;
  - capture an idea;
  - save text or a link for a future brief;
  - mark a task complete;
  - snooze a reminder.

  Replies are truthful. A cached brief states its age, an unreachable host is reported, and changes made offline are queued.
- **Locked devices.** Completing a task asks you to unlock. With Allow Siri When Locked on, Siri can read the brief or rundown, capture, save and snooze on a locked device, and anyone who can speak to the device can then hear the brief (`docs/SECURITY.md`).
- **The alarm automation.** Lisa cannot create personal automations or intercept Clock alarms; you create this one yourself.
  1. Open Shortcuts → Automation → New Automation → Alarm.
  2. Choose the trigger your iOS version offers. Apple documents "is stopped" and "is snoozed"; check whether yours also offers one for when the alarm goes off.
  3. Choose your wake-up alarm, and set the automation to run immediately.
  4. Add Lisa's "Get today's brief" action, then "Speak Text" with its result.
  5. If your device has no trigger for the moment the alarm goes off, use "is stopped", and note under A05 that the brief plays after you stop the alarm, not when it starts.
- **What to check (SIRI-02).** Record each in A05 and A06:
  - a fresh brief with the host reachable;
  - a cached brief with the host unreachable;
  - no brief available;
  - a locked device;
  - how the alarm sound and the speech interact;
  - repeated triggers, such as stopping several alarms or snoozing.

  Do not rely on playback while locked or in the background until you have observed it on your device.

## 8. Acceptance checklist (A01–A18)

Each check is `NOT_RUN_ENVIRONMENT` until it runs on Apple hardware. A12–A14, A17 and A18 also need an Apple Developer account, an APNs key or your VPN route (`NOT_RUN_CREDENTIALS`).

| Check | What to do | Status |
|---|---|---|
| A01 | Build LisaMac (Debug and Release) with the documented Xcode | `NOT_RUN_ENVIRONMENT` |
| A02 | Build LisaCompanion for the simulator and for a physical device | `NOT_RUN_ENVIRONMENT` |
| A03 | In the apps, capture, review a proposal, change a task and edit a preference; confirm each on the host | `NOT_RUN_ENVIRONMENT` |
| A04 | Run each of the six actions from Shortcuts and from Siri | `NOT_RUN_ENVIRONMENT` |
| A05 | The alarm automation in section 7, with the trigger you used | `NOT_RUN_ENVIRONMENT` |
| A06 | Brief while locked, from the cache, and with the host unavailable | `NOT_RUN_ENVIRONMENT` |
| A07 | Capture offline on two devices, reconnect, and confirm there are no duplicates | `NOT_RUN_ENVIRONMENT` |
| A08 | Keychain storage survives relaunch; revoking a device makes it unpaired and hides its data | `NOT_RUN_ENVIRONMENT` |
| A09 | Mac local notifications: permission granted, denied, and a reminder cancelled before delivery | `NOT_RUN_ENVIRONMENT` |
| A10 | Main workflows with the keyboard and with VoiceOver | `NOT_RUN_ENVIRONMENT` |
| A11 | The companion on iPhone (tabs) and iPad (sidebar), including iPad multitasking sizes | `NOT_RUN_ENVIRONMENT` |
| A12 | Each device pairs and registers for APNs separately; token refresh, reinstall and revocation | `NOT_RUN_CREDENTIALS` |
| A13 | Notifications in the foreground, in the background, after termination, while locked, away from home; and on the Mac | `NOT_RUN_CREDENTIALS` |
| A14 | Notification actions open, acknowledge, snooze and complete; offline actions show as pending and reconcile | `NOT_RUN_CREDENTIALS` |
| A15 | Denial, later Settings changes, Focus and preview settings are respected and reported to the host | `NOT_RUN_ENVIRONMENT` |
| A16 | Host asleep, stopped or unreachable behaves as `docs/OPERATIONS.md` describes | `NOT_RUN_ENVIRONMENT` |
| A17 | Time Sensitive for an urgent deadline, with device settings and Focus respected | `NOT_RUN_CREDENTIALS` |
| A18 | Over your VPN route, current data loads and actions synchronize promptly | `NOT_RUN_CREDENTIALS` |
