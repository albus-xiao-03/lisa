// Composes the readable and spoken brief from one list of grounded items (BRIEF-01, BRIEF-02, BRIEF-04).

import Foundation
import LisaDomain
import LisaTime

/// A composed brief.
public struct ComposedBrief: Hashable, Sendable {
    public var items: [BriefItem]
    public var omitted: [BriefItem]
    public var text: String
    public var spokenText: String
    public var estimatedSpokenSeconds: Int
}

/// Deterministic brief composition. Both versions are rendered from the same items, so they convey the same
/// commitments, warnings and uncertainty.
public enum BriefComposer {
    public static func compose(_ input: BriefInput) -> ComposedBrief {
        let zone = input.zone.timeZone
        var items: [BriefItem] = []
        items += commitmentItems(input, zone)
        items += deadlineItems(input, zone)
        items += emailItems(input)
        items += proposalItems(input, zone)
        items += ideaItems(input, zone)
        items += newsItems(input)
        items += input.changes.map {
            BriefItem(
                section: .changes, text: $0.text, spokenText: $0.spokenText, references: $0.references,
                isMaterial: true, priority: 0)
        }
        items += sourceItems(input)
        let (kept, omitted) = fit(items, targetWords: input.settings.targetWords)
        let text = renderReadable(kept, omitted: omitted, input: input)
        let spoken = renderSpoken(kept, input: input)
        let seconds = Int(
            (Double(BriefFormatting.wordCount(spoken)) / Double(max(60, input.settings.wordsPerMinute)) * 60).rounded())
        return ComposedBrief(
            items: kept, omitted: omitted, text: text, spokenText: spoken, estimatedSpokenSeconds: seconds)
    }

    /// Whether every material item is present in both renderings.
    public static func hasParity(_ brief: ComposedBrief) -> Bool {
        brief.items.filter(\.isMaterial).allSatisfy {
            brief.text.contains($0.text) && brief.spokenText.contains($0.spokenText)
        }
    }

    private static func commitmentItems(_ input: BriefInput, _ zone: TimeZone) -> [BriefItem] {
        input.commitments.filter { $0.status != .cancelled }.sorted {
            $0.range(in: zone).start < $1.range(in: zone).start
        }.map { occurrence in
            let reference = [SourceReference(recordKind: "occurrence", recordID: occurrence.id.rawValue)]
            let tentative = occurrence.status == .tentative ? " (tentative)" : ""
            let place = occurrence.location.map { " — \($0)" } ?? ""
            switch occurrence.timing {
            case .allDay:
                return BriefItem(
                    section: .commitments, text: "All day: \(occurrence.title)\(tentative)\(place)",
                    spokenText: "All day: \(occurrence.title)\(tentative).", references: reference, isMaterial: true,
                    priority: 0)
            case .timed(let start, let end, _, _):
                return BriefItem(
                    section: .commitments,
                    text:
                        "\(BriefFormatting.time(start, zone))–\(BriefFormatting.time(end, zone)) \(occurrence.title)\(tentative)\(place)",
                    spokenText: "At \(BriefFormatting.spokenTime(start, zone)), \(occurrence.title)\(tentative).",
                    references: reference, isMaterial: true, priority: 0)
            }
        }
    }

    private static func deadlineItems(_ input: BriefInput, _ zone: TimeZone) -> [BriefItem] {
        var result: [BriefItem] = []
        let ordered = input.tasks.sorted {
            ($0.deadline?.latestInstant(in: zone) ?? .distantFuture, $0.id) < (
                $1.deadline?.latestInstant(in: zone) ?? .distantFuture, $1.id
            )
        }
        for task in ordered {
            guard let deadline = task.deadline else { continue }
            let reference = [SourceReference(recordKind: "task", recordID: task.id.rawValue)]
            let overdue = deadline.latestInstant(in: zone) <= input.now
            let when: (String, String) =
                switch deadline {
                case .at(let instant, _):
                    (
                        "\(BriefFormatting.relativeDay(ZoneRules.localDate(for: instant, in: zone), reference: input.date)) at \(BriefFormatting.time(instant, zone))",
                        "\(BriefFormatting.relativeDay(ZoneRules.localDate(for: instant, in: zone), reference: input.date)) at \(BriefFormatting.spokenTime(instant, zone))"
                    )
                case .onDate(let date):
                    (
                        BriefFormatting.relativeDay(date, reference: input.date),
                        BriefFormatting.relativeDay(date, reference: input.date)
                    )
                }
            let text = overdue ? "Overdue: \(task.title) (was due \(when.0))" : "Due \(when.0): \(task.title)"
            let spoken = overdue ? "\(task.title) is overdue; it was due \(when.1)." : "\(task.title) is due \(when.1)."
            result.append(
                BriefItem(
                    section: .deadlines, text: text, spokenText: spoken, references: reference, isMaterial: true,
                    priority: 0))
        }
        for task in input.possibleTasks.sorted(by: { $0.id < $1.id }) {
            result.append(
                BriefItem(
                    section: .deadlines, text: "Possible task, not confirmed: \(task.title)",
                    spokenText: "There is a possible task you have not confirmed: \(task.title).",
                    references: [SourceReference(recordKind: "task", recordID: task.id.rawValue)], isMaterial: false,
                    uncertainty: "not confirmed", priority: 1))
        }
        return result
    }

    private static func emailItems(_ input: BriefInput) -> [BriefItem] {
        input.emails.sorted { ($0.email.receivedAt, $0.email.id) < ($1.email.receivedAt, $1.email.id) }.map {
            attention in
            let sender = attention.email.forwardedOriginal?.from ?? attention.email.from
            let name =
                sender?.displayName ?? sender.map {
                    $0.address.split(separator: "@").first.map(String.init) ?? "someone"
                } ?? "someone"
            return BriefItem(
                section: .email, text: "Email from \(name), \"\(attention.email.subject)\": \(attention.reason)",
                spokenText: "An email from \(name), about \(attention.email.subject), \(attention.reason).",
                references: [SourceReference(recordKind: "email", recordID: attention.email.id.rawValue)],
                isMaterial: false,
                priority: 1)
        }
    }

    private static func proposalItems(_ input: BriefInput, _ zone: TimeZone) -> [BriefItem] {
        input.proposals.filter(\.matchState.isUnresolved).sorted { $0.id < $1.id }.map { proposal in
            let when: (String, String) =
                switch proposal.timing {
                case .timed(let start, _, _):
                    (
                        "\(BriefFormatting.relativeDay(ZoneRules.localDate(for: start, in: zone), reference: input.date)) at \(BriefFormatting.time(start, zone))",
                        "\(BriefFormatting.relativeDay(ZoneRules.localDate(for: start, in: zone), reference: input.date)) at \(BriefFormatting.spokenTime(start, zone))"
                    )
                case .dateOnly(let date):
                    (
                        BriefFormatting.relativeDay(date, reference: input.date),
                        BriefFormatting.relativeDay(date, reference: input.date)
                    )
                case .unknown: ("date not yet known", "with a date that is not yet known")
                }
            let state: (String, String) =
                switch proposal.matchState {
                case .possibleMatch: ("may already be on your calendar", "may already be on your calendar")
                case .needsClarification: ("needs details", "needs more details")
                default: ("is not on your calendar", "is not on your calendar")
                }
            return BriefItem(
                section: .events, text: "\"\(proposal.title)\" (\(when.0)) \(state.0)",
                spokenText: "\(proposal.title), \(when.1), \(state.1).",
                references: proposal.evidenceIDs.map { SourceReference(recordKind: "evidence", recordID: $0.rawValue) }
                    + [SourceReference(recordKind: "proposal", recordID: proposal.id.rawValue)],
                isMaterial: true,
                uncertainty: proposal.uncertainty.isEmpty ? nil : proposal.uncertainty.joined(separator: "; "),
                priority: 1)
        }
    }

    private static func ideaItems(_ input: BriefInput, _ zone: TimeZone) -> [BriefItem] {
        input.ideaBlocks.sorted { $0.range.start < $1.range.start }.map { block in
            BriefItem(
                section: .ideas,
                text:
                    "Idea time \(BriefFormatting.time(block.range.start, zone))–\(BriefFormatting.time(block.range.end, zone)): \(block.title)\(block.provisional ? " (provisional)" : "")",
                spokenText:
                    "At \(BriefFormatting.spokenTime(block.range.start, zone)) there is time set aside to explore \(block.title)\(block.provisional ? ", provisionally" : "").",
                references: [reference(for: block.subject)],
                isMaterial: false, uncertainty: block.provisional ? "provisional" : nil, priority: 2)
        }
    }

    private static func reference(for subject: PlanSubject) -> SourceReference {
        switch subject {
        case .idea(let id): SourceReference(recordKind: "idea", recordID: id.rawValue)
        case .task(let id): SourceReference(recordKind: "task", recordID: id.rawValue)
        case .occurrence(let id): SourceReference(recordKind: "occurrence", recordID: id.rawValue)
        }
    }

    private static func newsItems(_ input: BriefInput) -> [BriefItem] {
        input.news.enumerated().map { index, entry in
            let headlineOnly = entry.item.boundary == .titleOnly ? " (headline only)" : ""
            let shared = entry.item.isSharedContent ? " (shared by you)" : ""
            let link = entry.item.originalURL.map { " <\($0)>" } ?? ""
            return BriefItem(
                section: .news, text: "\(entry.item.title)\(headlineOnly)\(shared) — \(entry.reason)\(link)",
                spokenText:
                    "From \(entry.sourceName): \(entry.item.title)\(entry.item.boundary == .titleOnly ? ", headline only" : "").",
                references: [
                    SourceReference(
                        recordKind: "news", recordID: entry.item.id.rawValue, originalURL: entry.item.originalURL)
                ],
                isMaterial: false, priority: 3 + index)
        }
    }

    private static func sourceItems(_ input: BriefInput) -> [BriefItem] {
        var items: [BriefItem] = []
        for source in input.sources.filter({ !$0.checked }).sorted(by: { $0.name < $1.name }) {
            let detail = source.detail.map { " (\($0))" } ?? ""
            items.append(
                BriefItem(
                    section: .sourceHealth, text: "Could not check \(source.name)\(detail)",
                    spokenText: "I could not check \(source.name).",
                    references: [SourceReference(recordKind: "source", recordID: source.sourceID.rawValue)],
                    isMaterial: true,
                    priority: 0))
        }
        if input.availabilityUncertain {
            items.append(
                BriefItem(
                    section: .sourceHealth, text: "Calendar availability is uncertain; proposed times are provisional",
                    spokenText: "Some calendar information may be out of date, so suggested times are provisional.",
                    references: [], isMaterial: true, uncertainty: "calendar data stale or incomplete", priority: 0))
        }
        let quiet = input.sources.filter { source in
            guard source.checked else { return false }
            switch source.kind {
            case .mailbox: return input.emails.isEmpty
            case .newsFeed, .xAccount, .discordChannel: return input.news.isEmpty
            default: return false
            }
        }
        if !quiet.isEmpty {
            let names = quiet.map(\.name).sorted().joined(separator: ", ")
            items.append(
                BriefItem(
                    section: .sourceHealth, text: "Checked, nothing new to report: \(names)",
                    spokenText: "I checked \(names) and found nothing new to report.", references: [],
                    isMaterial: false,
                    priority: 2))
        }
        return items
    }

    /// Keeps material items and as many optional items (by priority) as fit the target length.
    static func fit(_ items: [BriefItem], targetWords: Int) -> ([BriefItem], [BriefItem]) {
        var kept = items.filter(\.isMaterial)
        var words = kept.reduce(0) { $0 + BriefFormatting.wordCount($1.text) }
        var omitted: [BriefItem] = []
        for item in items.filter({ !$0.isMaterial }).sorted(by: { $0.priority < $1.priority }) {
            let cost = BriefFormatting.wordCount(item.text)
            if words + cost <= targetWords {
                kept.append(item)
                words += cost
            } else {
                omitted.append(item)
            }
        }
        let order = Dictionary(items.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return (kept.sorted { (order[$0] ?? 0) < (order[$1] ?? 0) }, omitted)
    }

    private static let headings: [BriefSection: String] = [
        .commitments: "Today's commitments", .deadlines: "Deadlines and tasks", .email: "Email needing attention",
        .events: "Not yet on your calendar", .ideas: "Idea time", .news: "News", .changes: "Changes",
        .sourceHealth: "Sources",
    ]

    private static func renderReadable(_ items: [BriefItem], omitted: [BriefItem], input: BriefInput) -> String {
        var lines = ["Morning brief for \(BriefFormatting.day(input.date)) (\(input.zone.identifier))"]
        if !items.contains(where: { $0.section == .commitments }) {
            lines.append("")
            lines.append("No calendar commitments today.")
        }
        for section in BriefSection.allCases {
            let sectionItems = items.filter { $0.section == section }
            guard !sectionItems.isEmpty else { continue }
            lines.append("")
            lines.append(headings[section] ?? section.rawValue)
            for item in sectionItems {
                lines.append("- \(item.text)\(item.uncertainty.map { " [\($0)]" } ?? "")")
            }
        }
        if !omitted.isEmpty {
            lines.append("")
            lines.append(
                "\(omitted.count) lower-priority item\(omitted.count == 1 ? " is" : "s are") available in the full view."
            )
        }
        return lines.joined(separator: "\n")
    }

    private static func renderSpoken(_ items: [BriefItem], input: BriefInput) -> String {
        var sentences = ["Good morning. Here is your brief for \(BriefFormatting.day(input.date))."]
        if !items.contains(where: { $0.section == .commitments }) { sentences.append("Your calendar is clear today.") }
        for section in BriefSection.allCases {
            sentences += items.filter { $0.section == section }.map(\.spokenText)
        }
        return sentences.joined(separator: " ")
    }
}
