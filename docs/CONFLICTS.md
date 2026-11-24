<!-- How Lisa R2 merges concurrent changes and how the owner resolves conflicts (plan R2 §8.3, §8.2.2). -->
# Conflicts and merging

Every device works offline and Lisa Core orders what arrives, yet **no clock decides between devices and no change silently overwrites another**. Each owner field has a merge class, and each operation that replaces or resolves something names exactly what it observed. Devices holding the same operations reach the same state, in any order they received them.

## The rules

| Situation | What happens | Where (`LisaMerge`) |
|---|---|---|
| The same operation twice | Applied once | Operation IDs (§8.2.1) |
| Edits to different fields | Both apply: each field is its own register | `MultiValueRegister` per field |
| Concurrent edits to one field | Each edit replaces only the versions it observed. Every candidate nobody observed survives, and two survivors are a **conflict** | `MultiValueRegister` |
| Your correction versus a model or source value | A model or source write never replaces your value, whether concurrent or later; it is kept as a **suggestion**. Your write replaces what you saw, whatever wrote it. A value whose authority a migration couldn't establish is protected like yours | `MergeAuthority`, `MultiValueRegister.suggestions` |
| Concurrent notes | Both kept, as separate note pieces | Pieces keyed `(item, piece)` |
| Tags added and removed at once | A removal removes only the additions it saw; a concurrent addition stays | `ObservedRemoveSet` |
| Completion or cancellation versus another edit | The edit applies; the item stays completed or cancelled | `TerminalActions` |
| Completed on one device, cancelled on another | Both kept: "completed and cancelled", shown for review; its reminders and deliveries stop | `TerminalActions.Status.completedAndCancelled` |
| Reopening | Reopens exactly the completions and cancellations it names; one it didn't see stays in effect | `TerminalActions.reopen(naming:)` |
| Acknowledged or dismissed on one device, snoozed on another | That reminder firing stops; the snooze stays in history and makes no new firing | `FiringResponses` |
| Two snoozes of one firing | The later snooze time wins, capped at the policy maximum; one new firing | `FiringResponses.nextFiring(cappedAt:)` |
| Deleted on one device, edited on another | The deletion wins in any order; the edit is kept as superseded while retention allows; restoring creates a new item | `ItemTombstone` |
| Two plans or briefs | Both kept as separate results, never merged | — |
| A conflict in a planning field | Planned conservatively, marked uncertain, escalation held | §8.3.4 (M5) |

## What "observed" means

An operation names what it observed in two parts (`ObservedSet`, `ObservedCoverage`):
- **A horizon** `(epoch, partition, position)`. It covers every committed version of that field at or before that position, in that epoch and partition. A device can state it only after installing the partition that far.
- **Explicit version IDs** for versions the device saw that Core hadn't committed by then: its own, a peer's or a relayed one. There are at most 256 per operation; beyond that they come in pages that apply together (§8.3.2).

Anything outside both parts is a later arrival and stays, so a resolution never removes a version you didn't see. A version committed after your horizon, or in another epoch, isn't covered by it. Lisa keeps each operation's observed set, so a version that arrives or commits later is judged the same way on every device.

## Order and dependencies

An operation waits until every operation it depends on has been decided, and is never applied out of order or skipped (`CausalRelease`, §8.2.2):
- At most 32 dependencies per operation.
- A cycle, which only forged or corrupt input can produce, rejects every member.
- One decision can release thousands of waiting operations, so release happens in bounded, restartable steps: at most 256 dependency edges or 256 operations per step, oldest first and fairly across devices. A capture never waits behind a large release for more than one step.

## Resolving a conflict

You resolve a conflict by choosing a value, or a new one, from the candidates you saw. Your resolution names exactly that set, as a horizon, explicit IDs and a digest of the reviewed list:
- A candidate that arrives later stays as a new conflict, never silently overwritten.
- If a resolution is replayed after a restore into a new epoch, it applies only with the list you reviewed (§8.3.2). Until then it waits, showing "Resolution waiting for the list you reviewed (until <date>)".
- If the list never arrives, you can apply the resolution to the explicitly listed candidates only, or discard it. With neither by the deadline, the conflict stays for a new resolution.
- Core alone decides each waiting resolution's single final outcome.

The resolution screens on the Mac, iPhone and iPad arrive with the apps (M5); this page will then describe them step by step.
