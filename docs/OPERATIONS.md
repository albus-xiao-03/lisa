<!-- Running Lisa's host: the single-writer rule, cycles, recovery, dry-run captures, retention, backups, logs and limits. -->
# Lisa — Operations

This document covers ARCH-03, OPS-01, OPS-02, DATA-05 and the operational parts of NOTIFY-07. The command-line interface is described by `lisa --help`, and in `docs/SETUP-LINUX.md` for Linux.

## The authoritative host

- **One host.** A single host owns Lisa's data directory. That host is the Mac app's embedded runtime, or `lisa serve` on a headless machine.
- **Single writer.** Exactly one runtime may write a data directory.
  - The runtime takes an exclusive lock on `<data directory>/lisa.lock`; the operating system releases it if the process ends.
  - A second command that needs to write fails clearly, naming the process that holds the lock. It never starts a competing scheduler.
  - From Phase 7, commands can instead connect to the running host as a client.
- **Commands.** Commands that open the data directory directly, while no host is running: `doctor`, `run-once`, `import`, `capture`, `plan`, `brief`, `status`, `export`, `backup`, `restore`, and `device`.
- **When the host is off.** While the host is stopped, asleep or disconnected:
  - nothing is ingested;
  - no reminder, notification, email or call is decided or sent.

  Notifications Apple has already accepted may still arrive.

## Cycles and schedules

Each cycle:
1. Synchronizes the sources that are due, a few at a time. One source's failure never stops the others.
2. Reviews new email.
3. Re-matches event proposals.
4. Plans today.
5. Syncs and fires reminders.
6. Dispatches the brief at its configured time.
7. Runs the delivery outbox.

Once a day, retention and request-ledger pruning also run.

- **Persisted schedules.** Schedules are kept in `runtime-state.json`, so a restart keeps each source's next run time and failure count.
- **Backoff.** A failing source backs off exponentially, with jitter, from 1 minute to 1 hour. It is never retried before a provider's retry-after time.
- **Shutdown.** `SIGINT` and `SIGTERM` stop the loop after the current cycle.

## Recovery after downtime (REM-04)

When the host opens, it reconciles before doing anything else:
- **Deliveries.** A delivery interrupted while it was being prepared is retried. One interrupted while it was being submitted is recorded as "outcome unknown" and is never resent automatically.
- **Missed reminders.**
  - An obsolete reminder is suppressed.
  - A reminder whose deadline passed is replaced by the single overdue reminder.
  - Missed low-priority reminders of the same kind are coalesced to the latest one.
- **Brief.** At most one catch-up brief is sent, within the configured catch-up window (4 hours by default). A later brief is recorded as skipped.
- **Audit.** Every skipped item is recorded in the audit log with its reason.

## Deliveries and dry runs

- **Dry run by default.** Every channel (email, calls, push) starts in dry-run mode.
  - Intended deliveries are captured, with recipient, subject and content, in `dry-run/captures.jsonl`.
  - Captures are owner-only and bounded to the most recent 2,000.
  - They never contain device tokens.
- **Live mode** is a deliberate, separate step for each channel, in this order (CFG-02):
  1. configure the adapter;
  2. verify access with `lisa doctor`;
  3. enable scheduled operation;
  4. switch that channel's mode to `live`.

  A live mode without an available adapter refuses to start.
- **The outbox.**
  - Every delivery is recorded before anything is sent, and recipients are enforced at send time.
  - Retries are bounded: 5 attempts by default, with exponential backoff, within the delivery's validity window.
  - Health reports pending, failed and uncertain deliveries.

## Network adapters (Phase 6)

- **Check first.** Run `lisa doctor` after configuring an adapter. It reports the network library (libcurl, with whether HTTP/2-only requests work), each source's configuration and secrets, the model endpoint, live delivery, and each APNs environment. It contacts no service and sends nothing.
- **Going live.** Set one channel's mode to `live` only after doctor reports its adapter ready. If a live channel's adapter is missing or unusable, the host refuses to start, naming the reason, rather than pretending to deliver.
- **Outcomes.** A delivery that may have reached a provider is recorded as `outcome unknown` and never resent automatically. Check the provider's own records, such as the mailbox's sent folder or Twilio's call log, before resending by hand.
- **Mail authentication.** libcurl chooses the SASL mechanism the server advertises, preferring GSSAPI, DIGEST-MD5, CRAM-MD5 and NTLM over PLAIN. It always does so inside verified TLS. A server that offers no AUTH receives the message without authentication.
- **Details per integration** are in `docs/INTEGRATIONS.md`.

## Devices and connectivity

- **Pairing codes.** A pairing code lives only in the running host's memory for 10 minutes. Restarting the host invalidates pending codes; create a new one with `lisa device pair-code`.
- **Removing a device.** Removing a device revokes its credential and cancels its pending deliveries.
- **When a device can't reach the host.** The app shows the cached brief and rundown with their age, and queues captures and actions until it reconnects. Push notifications still arrive while the host is running and online, because they travel host → Apple → device.
- **Remote access.** The intended remote arrangement is an owner-configured private VPN route to the host's authenticated HTTPS API (Phase 7 and `docs/SETUP-APPLE.md`).

## Retention (DATA-05)

| Data | Default | Setting |
|---|---|---|
| Raw source content | 90 days | `retention.rawContentDays` |
| Final delivery history | 180 days | `retention.deliveryHistoryDays` |
| Audit records | 365 days | `retention.auditDays` |
| Feed items never shared, rated or saved | 30 days | `retention.feedItemDays` |
| Request ledger (API idempotency) | 30 days | `api.idempotencyRetentionDays` |
| Logs | 3 files × 5 MB | `limits.logMaxBytes`, `limits.logKeepFiles` |

- **Never expire.** Records the owner created (tasks, ideas, captures, preferences) never expire. They are removed only by deleting them.
- **Disabling a source.** Disabling a source states whether imported records are kept. If they are not, they are deleted with their raw content.

## Backups and restore

- **Backup.** `lisa backup --output <directory>` writes a consistent copy of the database with a manifest. The manifest records the format, schema version, application version and record counts.
- **Restore.** `lisa restore <backup file>` restores into a data directory that no host holds. The replaced database is kept beside it.
  - A backup from a newer schema is refused.
  - An older one is migrated forward after a pre-migration backup.
- **Export.** `lisa export` writes versioned JSON of all owner data, without credentials, verifiers or tokens.

## Logs and health

- **Logs.** Logs are structured and redacted (D-09). Private values appear only as short fingerprints; secrets never appear.
- **Health.** `lisa status` and `GET /v1/health` report:
  - the runtime status and the last cycle's outcome;
  - delivery modes and outbox counts;
  - each source's freshness and failure class;
  - devices that cannot receive notifications, with the reason.

## Resource bounds (OPS-02)

Every bound is set in the configuration file's `limits` section, with documented defaults. The bounds cover:
- message and feed sizes;
- items per synchronization pass;
- recurrence expansion;
- concurrent source synchronizations;
- model input, output and daily requests;
- delivery attempts;
- log size;
- raw-content size.

Model repair is limited to one attempt. No polling or expansion loop is unbounded.
