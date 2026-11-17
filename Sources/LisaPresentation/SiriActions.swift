// The work behind the App Intents (SIRI-01): the brief and the rundown to read, captures, and completing a chosen task
// or snoozing a chosen reminder through the app's shared client services, with truthful results.

import Foundation
import LisaAPIContract
import LisaClient

/// What the App Intents do (SIRI-01). The Apple apps define the intents in the app targets, so they run in the app's
/// own process over its single `ClientServices`: one queue and one cache per storage.
///
/// - Reading: the brief and the rundown come from the host or, while it is unreachable, from the cache with a spoken
///   notice of their day and age. With nothing to read, the reply says why.
/// - Capturing: an idea, or text or a link for a future brief, is queued durably first and then sent. Offline it stays
///   queued, and the reply says so.
/// - Choosing: tasks and reminders are offered under the host's stable identifiers. A spoken name keeps every match
///   (`TitleMatcher`), so Siri asks which one was meant when several match.
/// - Acting: completing a task and snoozing a reminder expect the revision last read and go through the durable
///   queue. The reply is done, queued, unavailable, a conflict to review in the app, or a failure, never "done" for an
///   action that is only queued.
@MainActor
public struct SiriActions {
    /// The app's client services.
    public let context: ClientContext
    /// Where connectivity is reported, normally the app's `ConnectivityModel`.
    public let contacts: (any HostContactReporting)?
    /// The device's time format.
    public let locale: Locale

    /// Actions over `context`, reporting connectivity to `contacts`.
    public init(context: ClientContext, contacts: (any HostContactReporting)? = nil, locale: Locale = .current) {
        self.context = context
        self.contacts = contacts
        self.locale = locale
    }

    // MARK: - Reading

    /// The brief of `date` (`YYYY-MM-DD`), or of the host's current date, to be spoken.
    public func brief(date: String? = nil) async -> SiriReply {
        let model = BriefModel(context: context, contacts: contacts)
        await model.load(date: date)
        return .brief(speech: model.speechText(at: context.now()), failure: model.state.failure, date: date)
    }

    /// The rundown of `date` (`YYYY-MM-DD`), or of the host's current date, to be spoken.
    public func rundown(date: String? = nil) async -> SiriReply {
        let model = RundownModel(context: context, contacts: contacts)
        await model.load(date: date)
        guard let result = model.state.result else { return .rundownFailure(model.state.failure, date: date) }
        return SiriReply(
            dialog: RundownSpeech.text(
                for: result, at: context.now(), isEarlierDay: model.showsEarlierDay, timeZone: context.timeZone,
                locale: locale))
    }

    // MARK: - Capturing

    /// Captures `text` as an idea, from Siri.
    public func captureIdea(_ text: String) async -> SiriReply {
        let model = CaptureModel(context: context, contacts: contacts, channel: .siri)
        return .captured(await model.capture(CaptureDraft(kind: .idea, text: text)), isIdea: true)
    }

    /// Saves text or one web address for a future brief, from Siri (`CaptureDraft.textOrLink(_:)`).
    public func saveForBrief(_ textOrLink: String) async -> SiriReply {
        let model = CaptureModel(context: context, contacts: contacts, channel: .siri)
        return .captured(await model.capture(.textOrLink(textOrLink)), isIdea: false)
    }

    // MARK: - Choosing

    /// The tasks that can be completed: open, started or blocked. They come from the host, or while it is unreachable
    /// from the task lists cached on this device.
    public func completableTasks() async throws(SiriLookupError) -> [SiriItem] {
        let client = context.client
        do throws(ClientError) {
            var tasks: [TaskDTO] = []
            for status in SiriItem.completableStatuses {
                tasks += try await PageCollector.collect {
                    (cursor: String?) async throws(ClientError) -> Page<TaskDTO> in
                    try await client.tasks(status: status, limit: Pagination.maxLimit, cursor: cursor)
                }.items
            }
            await contacts?.record(.reached)
            return items(of: tasks)
        } catch {
            if let contact = HostContact(error) { await contacts?.record(contact) }
            guard error.isHostUnavailable else { throw SiriLookupError(LoadFailure(error), listing: .tasks) }
            let cached = items(of: await cachedTasks()).filter(\.isActionable)
            guard !cached.isEmpty else { throw SiriLookupError(LoadFailure(error), listing: .tasks) }
            return cached
        }
    }

    /// The completable tasks whose title matches `query`, every match kept so Siri can ask which one was meant.
    public func tasks(matching query: String) async throws(SiriLookupError) -> [SiriItem] {
        TitleMatcher.matches(query, in: try await completableTasks(), title: \.title)
    }

    /// The tasks with these identifiers, in the order given, whatever their status. Unknown identifiers are skipped.
    /// While the host is unreachable they come from the cached task lists.
    public func tasks(withIDs ids: [String]) async throws(SiriLookupError) -> [SiriItem] {
        var found: [SiriItem] = []
        var cached: [SiriItem]?
        for id in ids {
            if let cached {
                if let item = cached.first(where: { $0.id == id }) { found.append(item) }
                continue
            }
            do throws(ClientError) {
                let task = try await context.client.task(id: id)
                await contacts?.record(.reached)
                found.append(.task(task, timeZone: context.timeZone, locale: locale))
            } catch {
                if let contact = HostContact(error) { await contacts?.record(contact) }
                if error.status == 404 { continue }
                guard error.isHostUnavailable else { throw SiriLookupError(LoadFailure(error), listing: .tasks) }
                let saved = items(of: await cachedTasks())
                cached = saved
                if let item = saved.first(where: { $0.id == id }) { found.append(item) }
            }
        }
        return found
    }

    /// The reminders that can be snoozed: scheduled, delivered or snoozed. Reminders are not cached, so they need the
    /// host.
    public func snoozableReminders() async throws(SiriLookupError) -> [SiriItem] {
        let client = context.client
        do throws(ClientError) {
            let reminders = try await PageCollector.collect {
                (cursor: String?) async throws(ClientError) -> Page<ReminderDTO> in
                try await client.reminders(limit: Pagination.maxLimit, cursor: cursor)
            }.items
            await contacts?.record(.reached)
            return reminders.map { SiriItem.reminder($0, timeZone: context.timeZone, locale: locale) }
                .filter(\.isActionable)
        } catch {
            if let contact = HostContact(error) { await contacts?.record(contact) }
            throw SiriLookupError(LoadFailure(error), listing: .reminders)
        }
    }

    /// The snoozable reminders whose title matches `query`, every match kept so Siri can ask which one was meant.
    public func reminders(matching query: String) async throws(SiriLookupError) -> [SiriItem] {
        TitleMatcher.matches(query, in: try await snoozableReminders(), title: \.title)
    }

    /// The snoozable reminders with these identifiers, in the order given. Unknown or inactive ones are skipped.
    public func reminders(withIDs ids: [String]) async throws(SiriLookupError) -> [SiriItem] {
        let active = try await snoozableReminders()
        return ids.compactMap { id in active.first { $0.id == id } }
    }

    // MARK: - Acting

    /// Marks `task` complete, expecting the revision last read. It is queued first and sent within the context's time
    /// limit; offline it stays queued.
    public func complete(_ task: SiriItem) async -> SiriReply {
        guard task.isActionable else { return .notCompletable(task) }
        let patch = TaskPatchRequest(expectedRevision: task.revision, status: .completed)
        let submission = await ActionSubmitter(context: context).submit(
            .updateTask(id: task.id, patch), coalescing: true)
        if let contact = submission.contact { await contacts?.record(contact) }
        return .completed(task.title, submission.outcome)
    }

    /// Snoozes `reminder` for the host's configured snooze duration, expecting the revision last read. It is queued
    /// first and sent within the context's time limit; offline it stays queued.
    public func snooze(_ reminder: SiriItem) async -> SiriReply {
        guard reminder.isActionable else { return .notSnoozable(reminder) }
        let request = ReminderActionRequest(action: .snooze, expectedRevision: reminder.revision)
        let submission = await ActionSubmitter(context: context).submit(.reminderAction(id: reminder.id, request))
        if let contact = submission.contact { await contacts?.record(contact) }
        let until = submission.decoded(ReminderDTO.self)?.snoozedUntil.map(spokenTime)
        return .snoozed(reminder.title, until: until, submission.outcome)
    }

    // MARK: - Internals

    /// The tasks as items, each once: the highest revision read wins.
    private func items(of tasks: [TaskDTO]) -> [SiriItem] {
        var newest: [String: TaskDTO] = [:]
        var order: [String] = []
        for task in tasks {
            if let known = newest[task.id] {
                if task.revision > known.revision { newest[task.id] = task }
            } else {
                newest[task.id] = task
                order.append(task.id)
            }
        }
        return order.compactMap { newest[$0] }.map { .task($0, timeZone: context.timeZone, locale: locale) }
    }

    /// Every task in the task lists cached on this device: all tasks and the completable statuses.
    private func cachedTasks() async -> [TaskDTO] {
        let cache = context.cache
        var tasks: [TaskDTO] = []
        for status in [nil] + SiriItem.completableStatuses.map(Optional.some) {
            if let page = try? await cache.tasks(status: status) { tasks += page.value.items }
        }
        return tasks
    }

    /// The time of `instant`, with its day when it is not today.
    private func spokenTime(_ instant: Date) -> String {
        let zone = context.timeZone
        if LocalDay.string(for: instant, in: zone) == LocalDay.string(for: context.now(), in: zone) {
            return SpokenMoment.time(instant, in: zone, locale: locale)
        }
        return SpokenMoment.dayAndTime(instant, in: zone, locale: locale)
    }
}
