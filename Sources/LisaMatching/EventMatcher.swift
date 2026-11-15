// EVENT-01: compares an event proposal with subscribed occurrences; a loose similarity is never treated as proof.

import Foundation
import LisaDomain
import LisaTime

/// Matches proposals against calendar occurrences.
public enum EventMatcher {
    /// Returns the proposal's new match state. Owner decisions (matched, dismissed, reported added) are kept.
    ///
    /// - `matched`: a strong title match starting within five minutes of the proposal, or the same iCalendar UID.
    /// - `possibleMatch`: a partial title match on the same day, or the same start with a weak title match.
    /// - `notFound`: nothing comparable; `needsClarification` when the proposal has no date.
    public static func match(
        _ proposal: EventProposal, against occurrences: [CalendarOccurrence], zone: TimeZone, proposalUID: String? = nil
    ) -> ProposalMatchState {
        switch proposal.matchState {
        case .matched, .dismissed: return proposal.matchState
        case .ownerReportsAdded:
            // Awaiting refresh: once the event appears, it becomes a match; until then the owner's report stands.
            break
        default: break
        }
        if let proposalUID, let exact = occurrences.first(where: { $0.uid == proposalUID && $0.status != .cancelled }) {
            return .matched(exact.id)
        }
        let proposalTokens = TitleTokens.tokens(proposal.title)
        var best: (OccurrenceID, Double, [String], Bool)?
        for occurrence in occurrences where occurrence.status != .cancelled {
            let similarity = TitleTokens.similarity(proposalTokens, TitleTokens.tokens(occurrence.title))
            var reasons = ["title similarity \(Int((similarity * 100).rounded()))%"]
            let range = occurrence.range(in: zone)
            var sameStart = false
            var sameDay = false
            switch proposal.timing {
            case .timed(let start, _, _):
                sameStart = abs(range.start.timeIntervalSince(start)) <= 300
                sameDay = ZoneRules.localDate(for: range.start, in: zone) == ZoneRules.localDate(for: start, in: zone)
            case .dateOnly(let date):
                sameDay = ZoneRules.localDate(for: range.start, in: zone) == date
            case .unknown:
                return proposal.matchState.isUnresolved
                    ? .needsClarification("the date or time is missing") : proposal.matchState
            }
            if sameStart { reasons.append("same start time") } else if sameDay { reasons.append("same day") }
            if let location = proposal.location, let other = occurrence.location,
                TitleTokens.similarity(TitleTokens.tokens(location), TitleTokens.tokens(other)) >= 0.5
            {
                reasons.append("similar location")
            }
            let strong = similarity >= 0.8 && sameStart
            let possible = (similarity >= 0.5 && sameDay) || (sameStart && similarity >= 0.3)
            guard strong || possible else { continue }
            let score = similarity + (sameStart ? 1 : 0) + (sameDay ? 0.5 : 0)
            if best == nil || score > best!.1 { best = (occurrence.id, score, reasons, strong) }
        }
        if let best {
            return best.3 ? .matched(best.0) : .possibleMatch(best.0, reasons: best.2)
        }
        if case .ownerReportsAdded = proposal.matchState { return proposal.matchState }
        return .notFound
    }
}
