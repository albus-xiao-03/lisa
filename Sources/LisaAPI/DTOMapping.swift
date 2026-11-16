// Maps domain records to API DTOs. Clients never see domain types, credentials, verifiers or push tokens.

import Foundation
import LisaAPIContract
import LisaDomain
import LisaTime

enum DTOMapping {
    static func deadline(_ deadline: Deadline?) -> DeadlineDTO? {
        switch deadline {
        case .at(let instant, let zone): DeadlineDTO(instant: instant, zone: zone?.identifier)
        case .onDate(let date): DeadlineDTO(date: date.iso)
        case nil: nil
        }
    }

    static func task(_ task: LisaTask) -> TaskDTO {
        TaskDTO(
            id: task.id.rawValue, revision: task.revision.value, title: task.title, notes: task.notes,
            status: TaskStatusValue(rawValue: task.status.rawValue) ?? .open,
            priority: TaskPriorityValue(rawValue: task.priority.rawValue) ?? .normal, deadline: deadline(task.deadline),
            unresolvedDeadlineText: task.unresolvedDeadlineText, estimatedMinutes: task.estimatedMinutes,
            splittable: task.splittable,
            confirmation: ConfirmationValue(rawValue: task.confirmation.rawValue) ?? .possible,
            origin: task.origin.rawValue, evidenceCount: task.evidenceIDs.count,
            ownerCorrected: task.ownerCorrected.map(\.rawValue).sorted(), createdAt: task.createdAt,
            completedAt: task.completedAt)
    }

    static func idea(_ idea: Idea) -> IdeaDTO {
        IdeaDTO(
            id: idea.id.rawValue, revision: idea.revision.value, originalCapture: idea.originalCapture,
            summary: idea.summary, tags: idea.tags, notes: idea.notes,
            priority: TaskPriorityValue(rawValue: idea.priority.rawValue) ?? .normal,
            estimatedMinutes: idea.estimatedMinutes, deadline: deadline(idea.deadline),
            lifecycle: IdeaLifecycleValue(rawValue: idea.lifecycle.rawValue) ?? .inbox,
            unschedulableReason: idea.unschedulableReason, unschedulableCount: idea.unschedulableCount,
            createdAt: idea.createdAt)
    }

    static func capture(_ capture: Capture, created: Bool) -> CaptureDTO {
        CaptureDTO(
            id: capture.id.rawValue, kind: CaptureKindValue(rawValue: capture.kind.rawValue) ?? .text,
            capturedAt: capture.capturedAt, processing: capture.processing.rawValue,
            ideaID: capture.resultingIdeaID?.rawValue, newsID: capture.resultingNewsID?.rawValue, created: created)
    }

    static func timing(_ timing: ProposedTiming) -> ProposedTimingDTO {
        switch timing {
        case .timed(let start, let end, let zone): ProposedTimingDTO(start: start, end: end, zone: zone?.identifier)
        case .dateOnly(let date): ProposedTimingDTO(date: date.iso)
        case .unknown: ProposedTimingDTO()
        }
    }

    static func proposal(_ proposal: EventProposal) -> EventProposalDTO {
        let match: MatchStateDTO =
            switch proposal.matchState {
            case .needsClarification(let detail): MatchStateDTO(state: "needsClarification", detail: detail)
            case .notFound: MatchStateDTO(state: "notFound")
            case .possibleMatch(let id, let reasons):
                MatchStateDTO(state: "possibleMatch", occurrenceID: id.rawValue, reasons: reasons)
            case .matched(let id): MatchStateDTO(state: "matched", occurrenceID: id.rawValue)
            case .dismissed: MatchStateDTO(state: "dismissed")
            case .ownerReportsAdded(let at):
                MatchStateDTO(state: "ownerReportsAdded", detail: APIDates.string(from: at))
            }
        return EventProposalDTO(
            id: proposal.id.rawValue, revision: proposal.revision.value, title: proposal.title,
            timing: timing(proposal.timing), location: proposal.location, participants: proposal.participants,
            uncertainty: proposal.uncertainty, match: match, evidenceCount: proposal.evidenceIDs.count,
            createdAt: proposal.createdAt)
    }

    static func reminder(_ reminder: Reminder) -> ReminderDTO {
        let subject: (String, String) =
            switch reminder.subject {
            case .task(let id): ("task", id.rawValue)
            case .planBlock(let plan, let block): ("planBlock", "\(plan.rawValue)/\(block)")
            case .proposal(let id): ("proposal", id.rawValue)
            case .occurrenceChange(let id): ("occurrence", id.rawValue)
            }
        var detail: String?
        var snoozedUntil: Date?
        switch reminder.state {
        case .delivered(let at), .acknowledged(let at), .dismissed(let at), .completed(let at):
            detail = APIDates.string(from: at)
        case .snoozed(let until):
            snoozedUntil = until
        case .cancelled(let reason), .suppressed(let reason):
            detail = reason
        case .scheduled:
            break
        }
        return ReminderDTO(
            id: reminder.id.rawValue, revision: reminder.revision.value, subjectKind: subject.0, subjectID: subject.1,
            rule: reminder.rule.rawValue, dueAt: reminder.dueAt, title: reminder.title, state: reminder.state.name,
            stateDetail: detail, snoozedUntil: snoozedUntil, urgentDeadline: reminder.urgentDeadline)
    }

    static func subject(_ subject: PlanSubject) -> (String, String) {
        switch subject {
        case .occurrence(let id): ("occurrence", id.rawValue)
        case .task(let id): ("task", id.rawValue)
        case .idea(let id): ("idea", id.rawValue)
        }
    }

    static func rundown(_ plan: Plan) -> RundownDTO {
        RundownDTO(
            planID: plan.id.rawValue, revision: plan.revision.value, date: plan.localDate.iso,
            zone: plan.zone.identifier,
            blocks: plan.blocks.map { block in
                let (kind, id) = subject(block.subject)
                return PlanBlockDTO(
                    blockID: block.blockID, kind: block.kind.rawValue, subjectKind: kind, subjectID: id,
                    title: block.title, start: block.range.start, end: block.range.end, state: block.state.rawValue,
                    provisional: block.provisional, explanation: block.explanation)
            },
            unscheduled: plan.unscheduled.map { item in
                let (kind, id) = subject(item.subject)
                return UnscheduledItemDTO(subjectKind: kind, subjectID: id, title: item.title, reason: item.reason)
            },
            warnings: plan.warnings, changes: plan.changes, availabilityUncertain: plan.basis.availabilityUncertain,
            computedAt: plan.basis.computedAt)
    }

    static func brief(_ brief: Brief) -> BriefDTO {
        BriefDTO(
            briefID: brief.id.rawValue, revision: brief.revision.value, date: brief.localDate.iso,
            zone: brief.zone.identifier, version: brief.version, state: brief.state.rawValue, text: brief.text,
            spokenText: brief.spokenText,
            items: brief.items.map { item in
                BriefItemDTO(
                    section: item.section.rawValue, text: item.text, spokenText: item.spokenText,
                    references: item.references.map {
                        SourceReferenceDTO(
                            recordKind: $0.recordKind, recordID: $0.recordID, originalURL: $0.originalURL)
                    },
                    material: item.isMaterial, uncertainty: item.uncertainty)
            },
            omittedCount: brief.omitted.count, generatedAt: brief.generatedAt,
            estimatedSpokenSeconds: brief.estimatedSpokenSeconds, templateOnly: brief.templateOnly,
            lastFailure: brief.lastFailure)
    }

    static func preferenceValue(_ value: PreferenceValue) -> PreferenceValueDTO {
        switch value {
        case .text(let text): .text(text)
        case .number(let number): .number(number)
        case .flag(let flag): .flag(flag)
        case .list(let list): .list(list)
        }
    }

    static func preferenceValue(_ value: PreferenceValueDTO) -> PreferenceValue {
        switch value {
        case .text(let text): .text(text)
        case .number(let number): .number(number)
        case .flag(let flag): .flag(flag)
        case .list(let list): .list(list)
        }
    }

    static func preference(_ preference: Preference) -> PreferenceDTO {
        PreferenceDTO(
            key: preference.key.rawValue, value: preferenceValue(preference.value), origin: preference.origin.rawValue,
            confirmed: preference.confirmed, effective: preference.isEffective,
            consequential: preference.key.isConsequential, revision: preference.revision.value,
            updatedAt: preference.updatedAt)
    }

    static func source(_ source: Source, now: Date) -> SourceStatusDTO {
        SourceStatusDTO(
            id: source.id.rawValue, name: source.name, kind: source.kind.rawValue, enabled: source.enabled,
            freshness: source.freshness(at: now).rawValue, lastAttemptAt: source.lastAttemptAt,
            lastSuccessAt: source.lastSuccessAt, failing: source.isFailing,
            failureClass: source.isFailing ? source.lastFailure?.errorClass.rawValue : nil,
            failureSummary: source.isFailing ? source.lastFailure?.summary : nil,
            retryAfter: source.isFailing ? source.lastFailure?.retryAfter : nil, notes: source.capabilityNotes)
    }

    static func devicePreferences(_ device: DeviceRegistration) -> DeviceNotificationPreferencesDTO {
        DeviceNotificationPreferencesDTO(
            enabled: device.preferences.enabled, categories: device.preferences.categories.map(\.rawValue).sorted(),
            showTitles: device.preferences.showTitles, allowTimeSensitive: device.preferences.allowTimeSensitive,
            revision: device.revision.value)
    }

    static func device(_ device: DeviceRegistration, current: DeviceID?) -> DeviceDTO {
        DeviceDTO(
            id: device.id.rawValue, name: device.name,
            deviceClass: DeviceClassValue(rawValue: device.deviceClass.rawValue) ?? .iPhone,
            state: device.state.rawValue, transport: device.transport.rawValue, pairedAt: device.pairedAt,
            lastSeenAt: device.lastSeenAt,
            authorization: NotificationAuthorizationValue(rawValue: device.authorization.rawValue) ?? .unknown,
            pushTokenState: device.pushToken?.state.rawValue, canReceiveNotifications: device.canReceiveNotifications,
            preferences: devicePreferences(device), isCurrent: device.id == current)
    }
}
