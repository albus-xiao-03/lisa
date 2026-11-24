<!-- Development environment report (2026-11-24): the current platform for Lisa R2 development, how it differs from the platform recorded in plans/R2.md revision 13 and from R1's build environment, the version of every toolchain, library, tool, image and package, what was installed, and the checks showing the environment can build the implementation. -->
# Lisa — Development environment report

**Date:** 2026-11-24. **Prepared by:** Claude, at the owner's request. **Branch:** `feature/distributive` at `05b856e`.

**Scope.** The development environment was built on a new, unconfigured platform and checked with the project's existing build, test, lint, syntax and demo commands. **No R2 implementation has started.** M0 waits for the owner's instruction, and nothing here is milestone evidence. `plans/R2.md` was not changed. The only repository change is this file, committed on its own.

**The platform changed after the plan was approved, and the plan doesn't record it.** Revision 13 (approved 2026-11-23) describes a Fedora 45 host (§1.2, §3, §10.1). Development now happens on a Debian 13 sandbox. On 2026-11-24 the owner confirmed the change and asked that it be recorded only in reports and Claude's memory, not in the plan. Section 8 lists every plan statement the change affects.

## 1. Summary

- **Toolchain.** The default is Swift 6.4.2: the version `.swift-version` pins, R1 used, and the plan's production images carry (O-3). Swift 6.4.3, the latest release (2026-11-19), is installed beside it. Both are the official swift.org Debian 13 builds, and their signatures were verified. The plan host's Swift 6.3.2 has no Debian 13 build, so it isn't installed.
- **Libraries.** Debian 13 supplies SQLite 3.46.1, libxml2 2.9.14, libcurl 8.14.1 and OpenSSL 3.5.9. These are the same as R1's build environment and the plan's production runtime image (§8.11.1). They are older than the Fedora versions the plan recorded (SQLite 3.53.4, libxml2 2.15.4, libcurl 8.21.0, OpenSSL 4.0.3).
- **Containers.** Docker Engine 29.10.0, Buildx 0.39.1 and Compose 5.8.0 match the plan host almost exactly. The engine, however, is **rootful** and runs inside the sandbox. P-02, P-03 and O-10 name the owner's rootless engine on the previous host.
- **Swift packages.** Unchanged. All eight pins resolve at their recorded revisions, and `Package.resolved` keeps its SHA-256 `9608e8e0…a37494`. Four packages have newer patch releases upstream; none was applied.
- **Readiness.** With both toolchains:
  - debug and release builds complete with 0 warnings;
  - the unmodified R1 suite passes 376 tests in 66 suites in both configurations;
  - `swift format lint` reports no findings, and `swiftc -parse` accepts the Apple sources.

  With Swift 6.4.2, the offline demo also passes 30 of 30 checks, and a hardened container smoke run succeeds.
- **Not established here.** Apple builds and device behavior, live services, arm64, SELinux confinement and rootless-engine behavior.

## 2. Platforms compared

| Item | Plan revision 13 host (§1.2; observed 2026-11-20, rechecked 2026-11-21) | R1 build environment (`IMPLEMENTATION-REPORT.md` §1; 2026-11-18) | Current platform (observed 2026-11-24) |
|---|---|---|---|
| Operating system | Fedora 45 | Debian 13 (trixie), a Docker Hardened Images build | Debian 13 (trixie), Docker Hardened Images, in a Docker Sandboxes VM (`lisa.lab`) |
| Architecture | x86_64 | aarch64 | x86_64; kernel 7.0.14 |
| Capacity | Not recorded | Not recorded | 24 CPUs; 23.5 GiB memory, no swap. Root file system 20 GB, 11 GB free after installation. Project volume 49 GB |
| Account | `claude` (uid 1001), member of its own group only | Not recorded | `agent` (uid 1000), groups `sudo` and `docker` |
| Administration | No `sudo`. The owner installed every package (P-01, P-04, P-06) | Not recorded | Passwordless `sudo`. Claude installed the packages and toolchains under the owner's instructions of 2026-11-24 (§7) |
| Git workspace | The owner's working tree, used directly | Not recorded | Clone mode: a standalone clone. The host repository is mounted read-only at `/run/sandbox/source`. Commits stay in the sandbox until the owner fetches them. Ignored files, such as the earlier `.tmp/r2/` drafts (§1.1), aren't in the clone |
| Network | Not recorded | Not recorded; the suite ran offline | Outbound HTTP and HTTPS go through the sandbox proxy under a firewall policy; loopback is exempt (`NO_PROXY`). Reachable: swift.org, GitHub, Debian, Docker Hub, snapshot.debian.org, proton.me. snapshot.ubuntu.com answered, but a sample snapshot request returned HTTP 500 from the service |
| SELinux | Enforcing on the host; the engine doesn't label containers | Not recorded | Not active (an empty `selinuxfs`, no tools). The engine reports no SELinux option |
| arm64 | Unavailable (no binfmt or qemu) | Native | Unavailable: `binfmt_misc` is empty, and the builder offers amd64, v2 and v3 |
| Apple toolchain | None; the owner provides a Mac, iPhone and iPad for X1–X7 | None | None |

## 3. Toolchain

| Component | Plan host | R1 | Current: default | Current: also installed |
|---|---|---|---|---|
| Swift | 6.3.2 (`swift-6.3.2-RELEASE`), Fedora's package | 6.4.2 | **6.4.2** (`swift-6.4.2-RELEASE`, released 2026-10-29), at `/opt/swift/swift-6.4.2-RELEASE-debian13` | **6.4.3** (`swift-6.4.3-RELEASE`, released 2026-11-19, the latest), at `/opt/swift/swift-6.4.3-RELEASE-debian13` |
| Origin and verification | Fedora repository | swift.org, as `docs/SETUP-LINUX.md` directs | swift.org `debian13` tarball, 1,122,816,308 bytes, SHA-256 `8b6fde77…646c64`. Good GPG signature, made 2026-10-28 by the Swift 6.x Release Signing Key `52BB 7E3D E28A 71BE 22EC 05FF EF80 A866 B47A 981F`; that fingerprint matches swift.org's `all-keys.asc` and the official swift-docker Debian 13 Dockerfile | Same origin; 1,124,063,362 bytes, SHA-256 `a0b8191b…01fdd1`; signature made 2026-11-20 by the same key |
| swift-format | 6.3.2 | 6.4.2 | 6.4.2, bundled | 6.4.3, bundled |
| Clang, LLD, LLDB | ld.lld 23.1.5 installed | Not recorded | 21.0.0 each, bundled | Bundled; versions not recorded |
| Linker the driver uses | Not recorded | `ld.gold` (`docs/SETUP-LINUX.md`) | GNU gold 1.16 (`binutils-gold` 2.44-2), as in the official `swift` images | The same |
| C toolchain | Not recorded | Not recorded | GCC 14.2.0, libstdc++ 14, glibc 2.41 | The same |
| Build products | Not recorded | `.build/out/Products/<config>-linux-aarch64/` | `.build/out/Products/<config>-linux-x86_64/` | Its own scratch path, `.build/toolchain-6.4.3/` |

Swift 6.3 was never published for Debian 13. swift.org's release index lists only Debian 12 for 6.3.2 and 6.3.3; Debian 13 builds start at 6.4.0.

## 4. System libraries and tools

| Library or tool | Plan host (Fedora 45) | R1 (Debian 13, aarch64) | Current (Debian 13, x86_64): version and Debian package | Used for |
|---|---|---|---|---|
| SQLite | 3.53.4 | 3.46.1 | 3.46.1 (`libsqlite3-dev` 3.46.1-7+deb13u2+dhi4) | `CSQLite`, the data store |
| libxml2 | 2.15.4 | 2.9.14 | 2.9.14 (`libxml2-dev` 2.12.7+dfsg+really2.9.14-2.1+deb13u3+dhi3) | `CLibXML2`: feeds and HTML |
| libcurl | 8.21.0, with OpenSSL 4.0.3, nghttp2 1.69.0 and HTTP/3 | 8.14.1, with nghttp2 1.64.0 and OpenSSL 3.5.7 | 8.14.1 (`libcurl4-openssl-dev` 8.14.1-2+deb13u7+dhi1): OpenSSL 3 backend, HTTP/2 (nghttp2 1.64.0) and HTTP/3 (nghttp3 1.8.0) | `CCurl`: network adapters and APNs |
| OpenSSL | 4.0.3, library, headers and command | Command 3.5.7 | 3.5.9, library and command (`openssl` 3.5.9-1~deb13u1+dhi1); no headers needed | The R1 suite's run-time certificates, keys and `s_server` relay |
| nghttp2 tools | 1.69.0 | `nghttpd` 1.64.0, optional | `nghttpd` 1.64.0 (`nghttp2-server`) | An optional local HTTP/2 test server |
| ICU | Not recorded | 76.1 | 76.1 (`libicu-dev`) | Listed by `docs/SETUP-LINUX.md`; Foundation uses the toolchain's own ICU |
| pkg-config | Not recorded | 1.8.1 | 1.8.1 (`pkgconf`) | Locating `sqlite3` and `libxml-2.0` |
| tzdata | Not recorded | Not recorded | 2026f | Time-zone tests |
| Other tools | Podman 6.2.0 (unused) | Not recorded | git 2.47.3, GnuPG 2.4.7, curl 8.14.1, iproute2 6.15.0 (`ip`, `ss`), Python 3.14.10 (shipped with the image, not a Debian package) | General development; `ip` and `ss` for the M4 publish checks |

- **Toolchain prerequisites.** Installed from the official swift-docker `6.4/debian/13` list: `binutils-gold`, `gcc`, `libstdc++-14-dev`, `libedit-dev`, `libncurses-dev`, `libpython3-dev` (3.13.5, for LLDB) and `uuid-dev`. `git` and `tzdata` were already present.
- **Not needed, so not installed.**
  - `libssl-dev` and `libnghttp2-dev`. The plan host had their Fedora equivalents only as dependencies of `libcurl-devel`; the package includes just `curl/curl.h`.
  - Podman and the `sqlite3` command.

## 5. Container engine and images

| Item | Plan host | Current |
|---|---|---|
| Engine | Rootless Docker 29.10.0 (`dockerd-rootless.sh`), a user service with lingering | Rootful Docker CE 29.10.0 inside the sandbox; containerd 2.4.2, runc 1.4.4 |
| Context and socket | `rootless`, `unix:///run/user/1001/docker.sock` | `default`, `unix:///var/run/docker.sock`; the account is in the `docker` group |
| Storage and cgroups | overlayfs; cgroup v2 with systemd; data root in the account's home | overlayfs (containerd snapshotter); cgroup v2 with cgroupfs; data root `/var/lib/docker` |
| Security options | seccomp (builtin), rootless, cgroupns; no SELinux labelling | seccomp (builtin), cgroupns; not rootless, no user-namespace remapping, no SELinux |
| UID mapping | `claude:589824:65536`, so container UID 10001 is host UID 599824 (§8.11.2) | No `/etc/subuid`, so container UID 10001 is host UID 10001 |
| Buildx and BuildKit | 0.39.0; builder `rootless` with BuildKit 0.35.0; amd64, v2, v3 | 0.39.1; builder `default` (docker driver) with BuildKit 0.35.0; amd64, v2, v3 |
| Compose | v5.8.0 | v5.8.0 |
| Podman | 6.2.0, unused | Not installed |
| Registry access | Direct | Through the proxy at `gateway.docker.internal:3128` |
| Images present | `alpine:latest`, `hello-world:latest` | `hello-world:latest` (`sha256:1e4c05b8…9b2bfa`), pulled for the smoke run |

**Production base images (O-3).** Checked on 2026-11-24 from registry metadata, without pulling:
- `swift:6.4.2-trixie` still resolves to the plan's `sha256:9733821c…430097`, and `swift:6.4.2-trixie-slim` to `sha256:42571ee8…cccea0d`. Both indexes carry amd64 and arm64.
- For comparison, `swift:6.4.3-trixie` is `sha256:c19ad401…8130f1` and `swift:6.4.3-trixie-slim` is `sha256:61a6bc8d…f79d161`.
- The registry also answered for the images later milestones use: `ollama/ollama`, `ubuntu:24.04`, `ubuntu:26.04` and `debian:13`.

## 6. Swift package dependencies

These are the approved pins, unchanged. `swift package --force-resolved-versions resolve` checked out each package at its recorded revision. `Package.resolved` kept its SHA-256, `9608e8e024c6cbe0ea3fc269c5d80dcba8235c585f852de0e0c046a1dab37494`, which is the value the plan records (§1.1).

| Package | Required by | Pinned version | Revision | Newest upstream tag (2026-11-24) |
|---|---|---|---|---|
| swift-argument-parser | `LisaCLI`; `exact:` in `Package.swift` | 1.8.2 | `6a52f325…` | 1.8.2 |
| swift-crypto | `LisaCrypto`; `exact:` | 5.1.1 | `f8fad2f9…` | **5.1.2** |
| swift-nio | `LisaAPIServer`; `exact:` | 2.105.0 | `2f58d8ef…` | **2.105.1** |
| swift-nio-ssl | `LisaAPIServer`; `exact:` | 2.37.6 | `15e0b9e4…` | **2.37.7** |
| swift-asn1 | swift-crypto | 1.7.4 | `917b472d…` | **1.7.5** |
| swift-atomics | swift-nio | 1.3.1 | `0442cb5a…` | 1.3.1 |
| swift-collections | swift-nio | 1.7.6 | `88754449…` | 1.7.6 |
| swift-system | swift-nio | 1.9.0 | `640e5755…` | 1.9.0 |

The newer patch releases were not applied. Taking any of them changes `Package.swift` (the exact pins) or `Package.resolved`, which needs the owner's explicit permission (`CONSTRICTION.md`; plan §3 and §15). swift-certificates (P-08, conditional on N-1) is not resolved.

## 7. What was installed and configured

All of this was done under the owner's instructions of 2026-11-24, which authorize this task only:
- build and test the development environment;
- build it for the current platform;
- the latest releases of required development dependencies are allowed;
- configure the environment for performance;
- write this report at the project root and commit it.

1. **Debian packages**, installed with `sudo apt-get install --no-install-recommends`: `binutils-gold gcc libstdc++-14-dev libedit-dev libncurses-dev libpython3-dev uuid-dev libicu-dev libcurl4-openssl-dev libsqlite3-dev libxml2-dev pkg-config nghttp2-server`. With their dependencies, that set up 91 packages. Afterwards no installed package had a pending update, so every package is the current Debian 13 build.
2. **Swift toolchains.** Downloaded from download.swift.org, verified with GnuPG against swift.org's `all-keys.asc` in a throwaway keyring, and extracted root-owned into `/opt/swift/`.
3. **PATH.** An idempotent entry in `/etc/sandbox-persistent.sh` puts Swift 6.4.2 first. To use 6.4.3, put `/opt/swift/swift-6.4.3-RELEASE-debian13/usr/bin` first instead.
4. **Images.** `hello-world:latest` was pulled for the smoke run.
5. **Performance.** Nothing needed tuning:
   - with 24 cores, a clean debug build takes 31 s and a clean release build 111 s;
   - build products live on the 49 GB project volume;
   - the open-file limit is 1,048,576.

   The default `ld.gold` linker was kept, so host links match the official images.

**Not changed:** `plans/R2.md`, the specifications, `Sources/`, `Tests/`, `Apps/`, `Package.swift`, `Package.resolved`, `.swift-version`, and the Git configuration. No branch was created or switched, and nothing was pushed or fetched.

## 8. Where the approved plan no longer matches the platform

The plan is unchanged, at the owner's direction. Each row is for the owner to settle. Rows marked **M0** affect the first milestone as written.

| Plan statement | What it assumes | What the current platform offers | Consequence |
|---|---|---|---|
| §1.2; §3 "Environment"; §4 C1 | Fedora 45; the installed Swift 6.3.2; no `sudo`; owner-installed headers | Debian 13; Swift 6.4.2 and 6.4.3 installed by Claude; `sudo` available | The plan's environment rows describe the previous host |
| **M0:** §4 C8; §8.18 step 2; §15 P-08 ("Swift 6.3.2 on Fedora") | Code builds with 6.3.2 and 6.4.2; M0 builds the frozen R1 artifacts with 6.3.2 | No 6.3 release exists for Debian 13 | The frozen R1 build and the second host toolchain need a toolchain choice. 6.4.2 matches the images and R1 |
| **M0:** §9 "Fedora debug and release builds"; §10.1 "Fedora host" evidence class; §16 portable gate ("Fedora builds") | Evidence from Fedora 45 with Swift 6.3.2 | Debian 13, x86_64, Swift 6.4.2 | Host evidence would carry this platform's identity, not "Fedora" |
| §10.5 E-5; §17 "Fedora drift" | libxml2 2.15 and OpenSSL 4.0 compatibility checked at M0 | libxml2 2.9.14, OpenSSL 3.5.9 | E-5 can't run here. The host now uses the production image's distribution, so library drift between host and image shrinks |
| §15 P-02, P-03; §16 O-10; §10.7; §8.11.2 | The owner-configured rootless engine on the previous host; first use at M2 | A rootful engine in the sandbox | §15 says approved permissions keep their original scope, so P-02 and P-03 name the previous engine. Container work from M2 needs the owner to confirm their scope here. The rootless-specific checks (container UID 10001 as host UID 599824, secrets owned by that UID) don't apply as written |
| §8.11.2 SELinux | `NOT_RUN_ENVIRONMENT` on the rootless engine | No SELinux at all | Unchanged: `NOT_RUN_ENVIRONMENT` (Claude; environment configuration). The target-host evidence stays the owner's |
| §8.11.3 positive publish case | A private address actually assigned to the host | `eth0` holds `172.17.0.1/31` (RFC 1918) and `fd29:74ca:32f5::1/127` (ULA) | Candidates exist; the choice is still made at M4 |
| §1.4; §10.1 arm64 | Unavailable | Unavailable | Unchanged: `NOT_RUN_ENVIRONMENT` |
| §1.1 `.tmp/r2/` drafts; §10.2 evidence in `.tmp/r2/<run-id>/` | Files in the owner's working tree | Ignored files aren't part of the clone, and fetched commits don't carry `.tmp/` | The earlier drafts remain on the owner's host. Run directories made here exist only in this sandbox unless the owner copies them |
| §1.5 SQLite note | SQLite's WAL-reset bug is fixed from 3.51.3 | Debian 13 ships 3.46.1, as does the production image's Debian 13 base. Whether Debian backported the fix wasn't established | Worth confirming before relying on concurrent checkpoints. The single-writer design is the existing guard |
| §8.19.5 Proton Mail Bridge, amd64 only | An amd64 Core host | x86_64 | Unaffected |

## 9. Readiness checks

Claude ran these checks on 2026-11-24 on the current platform (Debian 13, x86_64), against the unmodified tree at `05b856e`. They are environment checks run with the project's existing commands. They are **not M0 evidence**: M0 reruns the suite under its own recorded procedure (§8.18, §10.3).

| Check | Command | Swift 6.4.2 (default) | Swift 6.4.3 |
|---|---|---|---|
| Dependency resolution | `swift package --force-resolved-versions resolve` | All 8 pins at their recorded revisions; `Package.resolved` unchanged | The same, in a separate scratch path |
| Debug build with tests | `swift build --build-tests` | **PASS**: 31.4 s, 0 warnings, 0 errors | **PASS**: 32.4 s, 0 warnings, 0 errors |
| R1 suite, debug | `.build/out/Products/Debug-linux-x86_64/LisaTests-test-runner --testing-library swift-testing` | **PASS**: 376 tests in 66 suites, 2.8 s | **PASS**: 376 tests in 66 suites |
| Release build with tests | `swift build -c release --build-tests` | **PASS**: 111.0 s, 0 warnings, 0 errors | **PASS**: 111.3 s, 0 warnings, 0 errors |
| R1 suite, release | The same runner under `Release-linux-x86_64` | **PASS**: 376 tests in 66 suites | **PASS**: 376 tests in 66 suites |
| Format | `swift format lint --configuration .swift-format -r` over `Sources`, `Apps` and `Tests` | **PASS**: 0 findings | **PASS**: 0 findings |
| Apple sources, syntax only | `swiftc -parse` over `Apps/Mac` with `Apps/Shared` (89 files), and over `Apps/Companion` with `Apps/Shared` (71 files) | Exit 0 | Exit 0 |
| Offline demo | `lisa demo --data-dir <run directory>/demo-release --json`, release build | **PASS**: 8 steps, 30 of 30 checks | Not run |
| Container engine | `docker run --rm --read-only --cap-drop ALL --security-opt no-new-privileges --user 10001:10001 --tmpfs /tmp:size=1m --network none hello-world` | **PASS**: exit 0; the container was removed | Not applicable |
| Base images | `docker buildx imagetools inspect` | The plan's digests confirmed (§5) | Not applicable |

- **What the suite covers.** 188 unit, 127 integration, 24 recovery, 3 acceptance and 34 adapter tests, the same split R1 recorded. The integration and adapter tests run against loopback servers with run-time certificates and against scripted IMAP, SMTP, APNs and HTTP peers. These are controlled substitutes: no live service, account or Apple platform was involved, and passing them validates none of those.
- **Not verified here** (`NOT_RUN_ENVIRONMENT`, Claude):
  - building or running the Apple apps (there is no Apple SDK, and the parse check is syntax only);
  - arm64;
  - SELinux confinement;
  - rootless-engine behavior.

  Live provider checks belong to the owner (§10.8).

## 10. Open decisions for the owner

1. **The plan's environment.** Amend `plans/R2.md` for the new platform (§1.2, §3, §9, §10.1, §15–§17), or keep it and treat this report as the record. Claude made no change.
2. **The host toolchain.**
   - Keep Swift 6.4.2 as the default, or move to 6.4.3. 6.4.2 matches `.swift-version`, the O-3 images and R1. Moving would also mean updating `.swift-version`, the O-3 digests and the setup documents.
   - Decide what replaces Swift 6.3.2 in C8, in the frozen R1 build (§8.18) and in P-08's toolchain list.
3. **Container scope.** Whether P-02 and P-03 cover this rootful engine, and whether rootless parity is wanted before M2–M4.
4. **Package updates.** swift-crypto 5.1.2, swift-nio 2.105.1, swift-nio-ssl 2.37.7 and swift-asn1 1.7.5 are available. Each needs the owner's explicit permission; none was taken.
5. **Disk space.** The two toolchain tarballs (2.1 GB) stay in `.tmp/r2/20261124-devenv/downloads/`, because `CONSTRICTION.md` doesn't allow Claude to remove temporary files. The owner may delete them.

## 11. Reproducing the environment

```sh
sudo apt-get update
sudo apt-get install -y --no-install-recommends binutils-gold gcc libstdc++-14-dev libedit-dev libncurses-dev \
  libpython3-dev uuid-dev libicu-dev libcurl4-openssl-dev libsqlite3-dev libxml2-dev pkg-config nghttp2-server

# In a new directory under .tmp/ (CONSTRICTION.md). For 6.4.3, set V=6.4.3.
set -eu
V=6.4.2
T=swift-$V-RELEASE-debian13.tar.gz
B=https://download.swift.org/swift-$V-release/debian13/swift-$V-RELEASE/$T
FPR=52BB7E3DE28A71BE22EC05FFEF80A866B47A981F   # Swift 6.x Release Signing Key, pinned here, never read from a download
curl -fsSLO "$B" && curl -fsSLO "$B.sig"
curl -fsSL -o all-keys.asc https://www.swift.org/keys/all-keys.asc
mkdir -m 700 gnupg && export GNUPGHOME="$PWD/gnupg"
gpg --batch --quiet --import all-keys.asc
gpg --batch --export "$FPR" > pinned-key.gpg   # gpgv trusts only the pinned signer, not every key in the file
ok=1
[ -s pinned-key.gpg ] || ok=0
gpgv --status-fd 3 --keyring ./pinned-key.gpg "$T.sig" "$T" 3>verify.status || ok=0
grep -q '^\[GNUPG:\] GOODSIG ' verify.status || ok=0
awk '$1=="[GNUPG:]" && $2=="VALIDSIG" {print $NF}' verify.status | grep -qx "$FPR" || ok=0   # primary-key fingerprint
if grep -Eq '^\[GNUPG:\] (BADSIG|ERRSIG|EXPSIG|EXPKEYSIG|REVKEYSIG|NO_PUBKEY)' verify.status; then ok=0; fi
if [ "$ok" -ne 1 ]; then echo "no valid signature from $FPR: not extracting" >&2; exit 1; fi
# The privileged extraction is reached only after every check above passed.
sudo mkdir -p /opt/swift && sudo tar -xzf "$T" -C /opt/swift
export PATH=/opt/swift/swift-$V-RELEASE-debian13/usr/bin:$PATH   # made persistent in /etc/sandbox-persistent.sh

# At the project root:
swift --version                                   # Swift version 6.4.2 (swift-6.4.2-RELEASE)
swift package --force-resolved-versions resolve   # Package.resolved must stay unchanged
```

## 12. Evidence and temporary files

The evidence is in `.tmp/r2/20261124-devenv/`. That directory is ignored by Git and exists only in this sandbox:
- `downloads/`: both toolchains, their signatures and `all-keys.asc`;
- `gnupg/`: the throwaway keyring;
- `logs/`:
  - the install and resolution logs (`apt-install.log`, `resolve.log`);
  - the build, test, lint and parse logs for each toolchain (`*-6.4.2*`, `*-6.4.3*`);
  - `demo-release-6.4.2.json`, `docker-smoke.txt` and `registry-swift-images.txt`;
  - `gpg-verify-*.log`, `linker-probe-6.4.2.log` and `tool-inventory*.txt`;
- `demo-release/`: the demo's data directory;
- `probe/`: the linker probe.

Three temporary files are kept from failed or partial first attempts, because `CONSTRICTION.md` forbids removing or overwriting temporary files:
- `build-debug-6.4.2.log` and `build-debug-6.4.2.time` are from a first build attempt that failed because `/usr/bin/time` isn't installed;
- `tool-inventory.txt` is a partial inventory.

**One temporary file was created outside `.tmp/` by mistake.** It is `snap-body.txt` in Claude's session scratch directory under `/tmp/claude-1000/`. It holds the response bodies of three public snapshot.ubuntu.com probes; the last one remains, a 186-byte error page. It contains no private data. It was left in place, as the no-removal rule requires.
