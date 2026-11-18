<!-- The Lisa host API, version 1: transport, authentication, request identities, errors, pagination and routes. -->
# Lisa API, version 1

The Lisa host API is used by the iPhone, iPad and Mac apps, the `lisa` command-line interface and the offline demo (API-01–API-03).

- **One router for every caller.** Calls made in the same process and calls made over the network go through the same router (`LisaAPI`). Validation, request identities, revision checks and permissions are therefore identical for every caller.
- **Network server.** `lisa serve` offers the same contract over HTTP/1.1 (`LisaAPIServer`), on loopback by default. See [Network server](#network-server).

The contract types live in `Sources/LisaAPIContract/`. Clients never see the host's internal records.

## Conventions

| Topic | Rule |
|---|---|
| Paths | Prefixed with `/v1`. Every response carries `Lisa-API-Version: 1.0`; clients refuse an unknown major version. |
| Bodies | JSON, UTF-8, at most 256 KiB per request. Larger requests get `413 payloadTooLarge`. |
| Instants | ISO 8601 UTC with milliseconds, for example `2026-11-16T12:00:00.000Z`. Instants without milliseconds are also accepted. |
| Local dates and times | Local dates are `YYYY-MM-DD`; local times are `HH:MM`. Both are in the owner's configured time zone. |
| Pagination | `limit` is 1–200 (default 50). `cursor` is the `nextCursor` of the previous page. Pages are ordered by record identifier, which is stable across inserts. |
| Revisions | Records carry `revision`. Updates send the revision they saw as `expectedRevision`. A mismatch returns `409 conflict` with `currentRevision`, so the client can reload and decide. A successful change answers with the record as stored after the host's follow-up work (replanning, reminder changes), so its `revision` is the one to send next. A later runtime cycle can still change the record, and the next change then gets the recoverable `409`. |

### Authentication and permissions

- **In-process callers.** The Mac app's embedded host, the CLI and the demo act as the **local owner** through the in-process transport. No credential is involved, because the caller is the host process itself.
- **Command-line clients.** While `lisa serve` owns the data directory, other `lisa` commands act as the local owner by sending that run's **owner credential** to the loopback owner listener. The credential is accepted nowhere else.
- **Paired devices.**
  - Every request sends `Authorization: Bearer <device credential>`. The credential is issued once at pairing.
  - The host stores only its SHA-256 verifier. A removed device's credential returns `401`.
- **Pairing.** `POST /v1/devices/pair` is authenticated by a one-time pairing code that is valid for 10 minutes. After five wrong codes, every pending code is discarded.
- **What paired devices may do.** A paired device may:
  - read the owner's day;
  - capture items;
  - act on tasks, ideas, reminders, plan blocks and event proposals;
  - change non-consequential preferences;
  - manage its own push registration, notification status, notification preferences and pairing.
- **What paired devices may not do.** A paired device may not:
  - create pairing codes;
  - export data;
  - remove other devices;
  - change consequential preferences: approved recipients, the phone number, email and call enablement, model settings, or the Time Sensitive opt-in.
- **Rate limits.** Each caller gets 300 requests per minute by default; unauthenticated pairing attempts get one tenth of that. Excess requests return `429` with `Retry-After`.

### Request identities

- **Required on every mutation.** Every `POST`, `PUT`, `PATCH` and `DELETE` carries `Lisa-Request-ID`: 8–128 characters from letters, digits and `._:-`. A mutation without one is rejected with `400`.
- **Scoped to the caller.** The same ID from two devices names two separate requests, and for captures two separate captures.
- **Retries replay.**
  - Retrying with the same ID returns the recorded response; the replay is marked `Lisa-Replayed: true`. The mutation is never applied twice.
  - Reusing an ID for a different request returns `422 requestIDReused`.
- **Retention.**
  - Definite answers are kept for at least 30 days, the documented maximum offline retry period: `2xx`, `400`, `403`, `404`, `409` and `413`.
  - The answers the network server gives before routing are never kept, including its `413`: the request never reaches the router, and a retry gets the same answer again (see below).
  - Retryable answers are not kept, so a retry runs again: `401`, `429` and `5xx`.
- **Pairing routes.** Pairing and pairing-code responses are never recorded, because they contain a credential or a code. A failed pairing is repeated with a new code.
- **Notification actions.** Devices derive the ID from the installation, the notification and the action (`na:<installation>:<notification>:<action>`). An action the system delivers twice is therefore applied once.

### Errors

Every error response has the body `{"code", "message", "field"?, "retryAfterSeconds"?, "currentRevision"?}`. Messages never contain secrets or raw private content.

| Code | Status | Meaning |
|---|---|---|
| `invalidRequest` | 400 | Malformed input or a failed validation; `field` names the offending field |
| `unauthenticated` | 401 | Missing, unknown or revoked credential, or an invalid pairing code |
| `forbidden` | 403 | The caller may not perform this action |
| `notFound` | 404 | No such route or record |
| `conflict` | 409 | A revision check failed, or the record's state does not allow the change |
| `payloadTooLarge` | 413 | The body exceeds 256 KiB |
| `requestIDReused` | 422 | The request ID belongs to a different request |
| `throttled` | 429 | Too many requests; retry after `retryAfterSeconds` |
| `unavailable` | 503 | A temporary failure; retry later with the same request ID |
| `internalError` | 500 | An unexpected failure; details are only in the host's redacted log |

The network server itself answers a few requests before they reach the router, with the same body shape and code `invalidRequest` (or `payloadTooLarge`), and then closes the connection:

| Status | When |
|---|---|
| 400 | Not valid HTTP/1.1; `Content-Length` together with `Transfer-Encoding`; no or several `Host` fields; a repeated `Authorization`, `Content-Type`, `Expect` or `Lisa-Request-ID`; a badly encoded path or query |
| 405 | A method the API does not use; `Allow` lists `GET, POST, PUT, PATCH, DELETE` |
| 413 | The body exceeds 256 KiB |
| 417 | An expectation other than `100-continue` |
| 431 | The request line and header fields exceed 16 KiB, or there are more than 100 fields |

These answers are not recorded for replay, because the request never reaches the router. The server refuses an oversized body before reading it, so the body is never fingerprinted.

## Network server

- **Listeners.**
  - The **device listener** is at `api.bindAddress` and `api.port`, by default `127.0.0.1:8765`. It accepts device credentials, and pairing codes on `POST /v1/devices/pair`.
  - The **owner listener** is on `127.0.0.1` with a free port. It accepts only the owner credential, and only from this machine.
- **Transport security (API-01).**
  - `api.tls.mode` is `none` (plain HTTP, loopback addresses only), `native` (TLS served by Lisa) or `reverseProxy` (plain HTTP to a trusted proxy on a loopback or private address).
  - Native TLS takes the PEM certificate chain and the unencrypted PEM private key from `api.tls.certificateSecret` and `api.tls.privateKeySecret`. It allows TLS 1.2 with ECDHE and AES-GCM or ChaCha20-Poly1305, and TLS 1.3, with ALPN `http/1.1`. Encrypted keys are refused.
  - Behind a reverse proxy, no request counts as coming from this machine.
- **Request targets.** Paths and query values are percent-encoded with RFC 3986's unreserved characters only (`APIRequest.encodedTarget()`). The server decodes strictly: `+` is a literal plus, and an encoded `/` inside a segment is refused.
- **Responses.**
  - Every response carries `Cache-Control: no-store` and `X-Content-Type-Options: nosniff`.
  - A `401` carries `WWW-Authenticate: Bearer realm="lisa"`.
- **Connections.**
  - Requests on one connection are answered in order, one at a time. `Expect: 100-continue` is answered before the body is sent.
  - A connection must send its first request head within 20 seconds, which includes any TLS handshake, and each body within 30 seconds. An idle kept-alive connection is closed after 30 seconds. At most 64 connections are served at once.
- **Shutdown.** On SIGINT or SIGTERM, `lisa serve` stops accepting connections and lets requests in progress finish, marked `Connection: close`, for up to 5 seconds. It then stops the runtime and releases the data directory.

## Routes

| Operation | Route | Notes |
|---|---|---|
| Runtime health | `GET /v1/health` | Status, delivery modes (`dryRun`/`live`), outbox counts, source freshness, device warnings, and `model`: `{provider: none\|deterministic\|openAICompatible, name?, location?, deterministic, available, dailyRequestLimit?}`. `available` says whether the host could set the provider up, not that an endpoint answers. It never includes an endpoint address, a key reference or a credential; hosts that predate the field omit it (D-47) |
| Rundown | `GET /v1/rundown?date=` | The stored plan, computed on first request for today or a later date |
| Plan-block action | `POST /v1/plans/{planID}/blocks/{blockID}/actions` | `{action: accept\|lock\|reject\|complete\|defer\|move, expectedRevision, start?, end?}`. `move` needs `start` and `end` on the plan's local day; the block becomes locked there. A move that would overlap a busy event or another held block, leave the day, touch a past day or a completed block is a `400` with the reason and field; a calendar event is a `403` (D-52) |
| Brief | `GET /v1/brief?date=` | Generated on first request for today |
| Regenerate brief | `POST /v1/briefs/regenerate` | `{date?}`; creates a new version; no second notification |
| Capture | `POST /v1/captures` | `{kind: idea\|text\|link\|sharedAppleNews, text?, url?, title?, channel}`; `201` when created, `200` when the request ID matched an earlier capture by the same caller |
| Read a captured link | `POST /v1/captures/{id}/retrieve` | No body; local owner and paired devices. `200` `{retrieved, item, characters, truncated, failureClass?, failureSummary?}`, including when the page could not be read for a lasting reason; `404` unknown capture; `409` not an owner-captured link, the item was deleted, or the page was already read; `503` with `retryAfterSeconds` for a temporary failure or a read already in progress (D-46) |
| Tasks | `GET /v1/tasks?status=&limit=&cursor=`, `GET /v1/tasks/{id}`, `POST /v1/tasks`, `PATCH /v1/tasks/{id}` | Patches need `expectedRevision`; corrected fields are kept through later reprocessing |
| Ideas | `GET /v1/ideas?lifecycle=`, `PATCH /v1/ideas/{id}` | The original capture is never changed |
| Event proposals | `GET /v1/event-proposals?state=`, `POST /v1/event-proposals/{id}/actions` | `{action: confirmMatch\|dismiss\|correct\|reportAdded, expectedRevision, …}` |
| Proposal calendar file | `GET /v1/event-proposals/{id}/calendar-file` | `text/calendar`; adding it to a calendar stays the owner's action |
| Reminders | `GET /v1/reminders?state=`, `POST /v1/reminders/{id}/actions` | `{action: acknowledge\|snooze\|dismiss\|complete, expectedRevision?}`; acknowledging never completes the task |
| Notification action | `POST /v1/notifications/{id}/actions` | The action chosen on a delivered notification |
| Preferences | `GET /v1/preferences`, `PATCH /v1/preferences` | `{changes: [{key, value?, confirm?, expectedRevision?}]}`; omit `value` to delete |
| Source status | `GET /v1/sources/status` | Freshness, last success, failure class |
| Pairing code | `POST /v1/devices/pairing-codes` | Local owner only |
| Pair a device | `POST /v1/devices/pair` | Returns the credential once |
| Push registration | `PUT /v1/devices/current/push-registration` | `{token, environment, topic}`; only configured topics and environments are accepted, and the topic must be the app identifier the device paired with; otherwise `403` |
| Notification permission | `PUT /v1/devices/current/notification-status` | `{authorization, settings}` |
| Device notification preferences | `GET`/`PATCH /v1/devices/current/notification-preferences` | `{enabled, categories, showTitles, allowTimeSensitive}`; patches need `expectedRevision` |
| Notification receipts | `POST /v1/devices/current/notification-receipts` | `{notificationIDs}`; the only evidence that a notification was presented; `204` |
| Devices | `GET /v1/devices`, `DELETE /v1/devices/{id}` | Removal revokes the credential and cancels pending deliveries |
| Export | `GET /v1/export` | Local owner only; versioned JSON without credentials or tokens |

## Push payload

Ordinary APNs alert notifications use this payload (`PushPayload` in the contract; D-38):

```json
{
  "aps": {
    "alert": {"title-loc-key": "LISA_REMINDER_TITLE", "loc-key": "LISA_REMINDER_BODY"},
    "category": "LISA_REMINDER",
    "thread-id": "…",
    "sound": "default",
    "interruption-level": "active"
  },
  "lisa": {"v": 1, "kind": "reminder", "notification": "…", "subjectKind": "task", "subject": "…", "revision": 3}
}
```

- **Titled body.** A device that opted in to titles receives `loc-key` `LISA_<CATEGORY>_BODY_TITLED`, with the truncated title as its only `loc-args` value.
- **Interruption level.** `interruption-level` is `time-sensitive` only for urgent confirmed deadlines, when the owner opted in.
- **Categories and actions.**

  | Category | Actions |
  |---|---|
  | `LISA_REMINDER`, `LISA_OVERDUE` | `LISA_ACKNOWLEDGE`, `LISA_SNOOZE`, `LISA_COMPLETE` |
  | `LISA_PLAN_BLOCK` | `LISA_ACKNOWLEDGE`, `LISA_SNOOZE` |
  | `LISA_COMMITMENT_CHANGE` | `LISA_ACKNOWLEDGE` |
  | `LISA_EVENT_PROPOSAL`, `LISA_BRIEF` | Open only |

- **Size.** Payloads stay under 4,096 bytes.
