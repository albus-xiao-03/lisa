# Lisa demonstration fixtures

**Everything in this directory is synthetic demonstration data.** It was written for the offline scenario that
`lisa demo` runs (requirement DEMO-01 in `specs/R1.md`). No file contains a real person, company, postal address,
phone number, account, credential or message. Every address and link uses a reserved example domain
(`example.com`, `example.org`, `example.net`, `example.invalid`), and the only phone number follows the fictional
`+1 555 …` pattern.

| Synthetic identity | Value |
|---|---|
| Owner | Alex Demo, `owner@example.com` |
| Lisa's mailbox | `lisa@example.invalid` |
| Colleagues | Jordan Example `jordan@example.org`, Priya Sample `priya@example.org` |
| Attacker | "Demo IT Helpdesk" `attacker@example.net`, phone `+1 555 0177` |
| Links | `https://news.example.com/demo/…`, `https://blog.example.org/demo/…`, `https://archive.example.com/demo/…` |

Labels: every message has a `[Demo]` subject prefix and an `X-Lisa-Demo: synthetic` header. Calendar, event and
feed names start with "Demo", and the captured idea starts with `[Demo]`.

## Scenario time

The demo runs at **2026-11-16T13:00:00Z**, which is **Monday 08:00 in America/New_York** (EST, UTC−5). All local
times below are America/New_York. Every date in the fixtures falls between 2026-10-19 and 2026-12-31, after the
daylight-saving change on 2026-11-01, so the offset is always −05:00.

## What each file demonstrates

| DEMO-01 item | File |
|---|---|
| Forwarded email containing a possible event | `mail/01-forwarded-possible-event.eml` |
| Email with a confirmed task and deadline | `mail/02-owner-confirmed-tasks.eml` |
| Duplicate email | `mail/03-owner-confirmed-tasks-duplicate.eml` |
| Attempted third-party recipient injection | `mail/04-third-party-injection.eml` |
| Calendar invitation (additional) | `mail/05-calendar-invitation.eml` |
| Calendar with a recurring event and an exception | `calendar/demo-work.ics` |
| Relevant and irrelevant news | `feeds/demo-tech-news-rss.xml`, `feeds/demo-dev-blog-atom.xml` |
| One failing or stale source | `feeds/stale-demo.xml` |
| Explicit preferences | `demo/preferences.json` |
| Captured idea | `demo/idea.txt` |
| Simulated upcoming reminder | The 08:45 deadline in `mail/02-owner-confirmed-tasks.eml` |

### Mail (`mail/`)

The `.eml` files are RFC 5322 messages with valid MIME and CRLF line endings. They are read in file-name order. Their
deadlines and event times are written as absolute dates ("November 16, 2026 at 8:45 am"), so the results do not depend
on when the files are imported. Weekday names are never combined with a date, because the date reader does not
accept forms such as "Monday, November 16".

- **01-forwarded-possible-event.eml.** Alex forwards a message from Jordan with a Gmail-style
  `---------- Forwarded message ---------` marker. Alex's note above the marker reads
  `Meeting: Demo budget review on November 19, 2026 at 2:00 pm | at Demo Room 4B`.
  Expected result: the message counts as forwarded by the owner, and the original sender and date are recognized.
  Extraction finds one *possible* meeting, which becomes an **event proposal**: "Demo budget review",
  Thursday 2026-11-19 14:00 (19:00Z), at Demo Room 4B, with no end time. The demo calendar has no matching event.
- **02-owner-confirmed-tasks.eml.** A message from Alex (the owner's own words) with two lines of the form
  `Task: … (confirmed)`, each followed by a `Due:` line.
  Expected result: two **confirmed** tasks:
  - "Send the demo slides to Priya", due 2026-11-16 08:45 (13:45Z);
  - "Draft the demo quarterly summary", due Friday 2026-11-20 15:00 (20:00Z).
- **03-owner-confirmed-tasks-duplicate.eml.** A byte-identical copy of 02 under a second file name, with the same
  Message-ID. Expected result: recognized as a duplicate by Message-ID and stored once.
- **04-third-party-injection.eml.** An HTML-only message from `attacker@example.net` to Lisa's mailbox. It tells Lisa
  to send the brief and every reminder to `attacker@example.net` and to call `+1 555 0177`. It also contains hidden
  text and two `Task: … (confirmed)` lines.
  Expected result: the message is direct mail. Both tasks are extracted only as *possible*, with the note
  "confirmation downgraded: the quote is not the owner's own words". They get no reminders and are not planned.
  Recipients and the call number come only from configuration, so nothing is ever sent to or called at the
  attacker's address or number.
- **05-calendar-invitation.eml.** Priya sends a `multipart/alternative` invitation (plain text plus
  `text/calendar; method=REQUEST`, UID `demo-design-review-20261118@example.org`).
  Expected result: an event proposal "Demo design review", Wednesday 2026-11-18 10:00–10:30, at Demo Room 3C. It is
  built from the structured invitation without a model, and the plain-text part yields no extracted items.

### Calendar (`calendar/demo-work.ics`)

"Demo work calendar" uses CRLF line endings and an embedded `America/New_York` VTIMEZONE.

- **Demo weekly planning** repeats every Monday 09:30–10:00 from 2026-11-09, with `UNTIL` 2026-12-28.
  - A `RECURRENCE-ID` moves today's instance to **10:30–11:00**. Its occurrence key, `20261116T143000Z`, keeps the
    original start.
  - An `EXDATE` skips 2026-11-30.
- **Demo customer call** is a one-off event today, 13:00–13:45.
- **Demo vendor sync** is today, 15:00–15:30, with `STATUS:CANCELLED`, so it does not block time.

Expected result for 2026-11-09 to 2026-12-31: 9 occurrences (7 weekly ones, the call and the cancelled sync), each
weekly one lasting 30 minutes, with no expansion warnings. Today's occurrences are 10:30 weekly planning (moved),
13:00 customer call and 15:00 vendor sync (cancelled).

### Feeds (`feeds/`)

| File | Format and title | Items |
|---|---|---|
| `demo-tech-news-rss.xml` | RSS 2.0, "Demo Tech News" | 5, all published 2026-11-14 15:00Z to 2026-11-16 11:30Z |
| `demo-dev-blog-atom.xml` | Atom 1.0, "Demo Developer Blog" | 4, all published 2026-11-14 20:00Z to 2026-11-16 09:20Z |
| `stale-demo.xml` | RSS 2.0, "Demo Archive Weekly" | 2, the newest from 2026-10-26 (three weeks old) |

The interests are `swift` and `productivity`, plus the brief topic `open source`, which Lisa also uses for ranking
news. At the demo time the expected selection is, in order:

1. "Swift concurrency checklist for demo app teams" (RSS, swift)
2. "An open source template for weekly reviews" (Atom, open source)
3. "Five productivity habits for calmer mornings" (RSS, productivity)
4. "Server-side Swift meetup recap: structured concurrency in practice" (swift). It appears in both feeds with the
   same title and link, and is shown once.
5. "Swift on Linux: notes from the demo build farm" (Atom, swift). It has no summary, so it is labeled title-only.

The sports items, the weather item and the archive items match no interest and are left out.

A source's freshness comes from its last successful refresh, not from item dates. The demo therefore marks the
archive source stale or failing itself; the old dates show why. When the whole `feeds/` directory is imported as
one source, all three files belong to that source. To show a stale source on its own, import `stale-demo.xml` as a
separate source.

### Owner data (`demo/`)

- **preferences.json** holds explicit, non-consequential preferences as `{"key": …, "value": {…}}` objects. Each
  value has exactly one of `text`, `number`, `flag` or `list`:
  - `news.interests` = `swift`, `productivity`
  - `brief.topics` = `open source`
  - `planning.windows` = `weekdays 08:00-17:00`. The window opens at 08:00 so that the 08:45 task can be planned
    before its deadline.
  - `planning.bufferMinutes` = 10
  - `ideas.explorationMinutes` = 45

  The file contains no recipient, phone, email, call, model or notification settings. Those come only from the demo
  configuration.
- **idea.txt** holds one captured idea:
  "[Demo] Sketch a weekly review template that turns Friday notes into next week's top three priorities."

## Expected rundown and reminders at 08:00

These figures assume the default 30-minute tasks, a 0.75 maximum allocation, the 60-minute daily idea budget and
reminder offsets of 24 hours and 60 minutes.

- **Free time** after 10-minute buffers: 08:00–10:20, 11:10–12:50 and 13:55–17:00 (425 minutes).
- **Plan:**
  - 08:00–08:30 Send the demo slides to Priya
  - 08:30–09:00 Draft the demo quarterly summary
  - 09:00–09:45 the idea
  - 10:30–11:00 Demo weekly planning (fixed)
  - 13:00–13:45 Demo customer call (fixed)
- **Reminders:**
  - Slides task: both offsets are already past, so one reminder is due immediately at 08:00. This is the simulated
    upcoming reminder. If the task is still open at 09:00, it gets one overdue reminder.
  - Summary task: reminders on Thursday 2026-11-19 at 15:00 and Friday 2026-11-20 at 14:00.
  - Completing a task cancels its pending reminders.
- **Proposals:** both proposals stay unresolved ("not found" in the calendar).

## Assumptions about the demo configuration

These settings are not part of the fixtures:

- The owner's approved address is `owner@example.com`, so messages 01 and 02 count as the owner's own words.
- Lisa's mailbox address is `lisa@example.invalid`, so message 04 counts as direct mail.
- The time zone is America/New_York.
- Extraction uses the deterministic rule-based provider.
- Every delivery is a dry run.

## File format notes

- `.eml` and `.ics` files must keep their CRLF line endings byte for byte. Do not let tools normalize them.
- All fixture data files are plain ASCII. This README is UTF-8.
- Message-IDs use `@example.com` for the owner's mail and `@example.org` for the other messages.
