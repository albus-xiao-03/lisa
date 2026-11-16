<!-- Reproducible Linux setup: the pinned Swift toolchain, system libraries, builds, tests, the offline demo, configuration and headless operation. -->
# Lisa — Linux setup

This guide covers CFG-03. It was written for Debian 13 on aarch64; other distributions need the equivalent packages.

Linux cannot build or validate the Apple apps. SwiftUI, App Intents, UserNotifications, Keychain and Siri exist only on Apple platforms, and the `Apps/` targets are built on a Mac (`docs/SETUP-APPLE.md`).

## 1. Toolchain

- **Version.** Lisa pins Swift **6.4.2**, recorded in `.swift-version`. That matches the owner's Xcode toolchain.
- **Install.** Install the official swift.org toolchain for your platform, following <https://www.swift.org/install/>. Verify the download's signature as the page describes.
- **Check.**

  ```sh
  swift --version      # Swift version 6.4.2 (swift-6.4.2-RELEASE)
  ```

The Swift driver links with `ld.gold`, so install `binutils-gold` if your distribution does not include it.

## 2. System libraries

| Package (Debian) | Version used | Needed for |
|---|---|---|
| `libsqlite3-dev` | 3.46.1 | The data store (DATA-02) |
| `libxml2-dev` | 2.9.14 | XML and HTML reading (feeds, HTML mail) |
| `libcurl4-openssl-dev` | 8.14.1, built with HTTP/2 through nghttp2 1.64.0 and OpenSSL 3.5.7 | Network adapters (Phase 6) |
| `pkg-config` | 1.8.1 | Locating the libraries |
| `libicu-dev` | 76.1 | Foundation's text support |
| `nghttp2-server` (optional) | 1.64.0 | A local HTTP/2 test server for adapter verification |

For example:

```sh
sudo apt-get update
sudo apt-get install --no-install-recommends libsqlite3-dev libxml2-dev libcurl4-openssl-dev pkg-config libicu-dev
```

Cryptography comes from swift-crypto 5.1.1, which vendors BoringSSL, so no system cryptography package is needed for it. Every third-party Swift package is pinned in `Package.resolved`.

## 3. Resolve and build

```sh
swift package resolve          # pinned versions from Package.resolved
swift build                    # debug
swift build -c release         # release
```

The `lisa` executable is at `.build/debug/lisa`, or at `.build/release/lisa` after a release build. `swift run lisa …` builds and runs it in one step.

## 4. Tests

`swift test` runs the persistent package tests in `Tests/`. That suite is added in Phase T; it runs offline and uses synthetic data only (L02). Until then, verification uses temporary checks kept outside the repository.

## 5. The offline demonstration

```sh
swift run lisa demo --data-dir /tmp/lisa-demo
```

- **No setup.** The demo needs no accounts, credentials or network access (DEMO-01, CFG-02). It uses its own data directory, synthetic identities and the bundled `Fixtures/`.
- **What it shows.**
  - It imports mail, a calendar and news, and removes duplicates.
  - It identifies an event proposal, plans the day, and composes the readable and spoken briefs.
  - It captures every intended delivery as a dry run.
  - It shows an acknowledgement from one synthetic device suppressing the other device's pending delivery.
  - It restarts and verifies that nothing was duplicated.
- **Output.** Add `--json` for machine-readable output. The exit code is 0 when every check passes.

## 6. Configuration

1. Copy `config.example.json5` to a private location, for example `~/.config/lisa/config.json5` with mode `0600`.
2. Edit it. Every section is commented. Secrets are references (`env:NAME` or `file:/path`), never values.
3. Validate it:

   ```sh
   lisa doctor --config ~/.config/lisa/config.json5
   ```

   `doctor` reports every invalid setting with its path and a fix. It reports which capabilities are available, and whether every secret reference resolves. It never shows a secret's value, and never sends anything.

Delivery stays dry-run until a channel's mode is deliberately set to `live` (`docs/OPERATIONS.md`).

## 7. Headless operation

```sh
lisa run-once --config ~/.config/lisa/config.json5    # one bounded cycle
lisa serve --config ~/.config/lisa/config.json5       # the host runtime and API (Phase 7)
lisa status --config ~/.config/lisa/config.json5      # runtime and source state
```

- **Single writer.** Only one process may write a data directory at a time (`docs/OPERATIONS.md`).
- **Stopping.** Stop `serve` with `SIGINT` or `SIGTERM`; the current cycle finishes first.

## 8. Backup and restore

```sh
lisa backup --config ~/.config/lisa/config.json5 --output ~/lisa-backups
lisa restore --config ~/.config/lisa/config.json5 ~/lisa-backups/lisa-backup-<timestamp>.sqlite
```

Restore requires that no host is running. It keeps the replaced database beside the restored one.
