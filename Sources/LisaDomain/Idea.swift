// A captured idea with its preserved original text and planning lifecycle.

import Foundation
import LisaTime

/// An idea's lifecycle (IDEA-01).
public enum IdeaLifecycle: String, Codable, Sendable, CaseIterable {
    case inbox
    case availableForPlanning
    case scheduled
    case explored
    case archived
}

/// A captured idea. `originalCapture` is never rewritten; descriptions and tags are separate.
public struct Idea: Entity {
    public static let collectionName = "ideas"
    public let id: IdeaID
    public var revision: Revision
    public var updatedAt: Date
    public let originalCapture: String
    public var captureID: CaptureID?
    public var summary: String
    public var tags: [String]
    public var notes: String
    public var priority: TaskPriority
    public var estimatedMinutes: Int?
    public var deadline: Deadline?
    public var lifecycle: IdeaLifecycle
    /// Why the planner could not place the idea, kept visible when it repeatedly fails to fit.
    public var unschedulableReason: String?
    public var unschedulableCount: Int
    public var createdAt: Date

    public init(
        id: IdeaID = .random(), originalCapture: String, captureID: CaptureID? = nil, summary: String? = nil,
        tags: [String] = [], priority: TaskPriority = .normal, estimatedMinutes: Int? = nil, now: Date
    ) {
        self.id = id
        self.revision = .initial
        self.updatedAt = now
        self.originalCapture = originalCapture
        self.captureID = captureID
        self.summary = summary ?? originalCapture
        self.tags = tags
        self.notes = ""
        self.priority = priority
        self.estimatedMinutes = estimatedMinutes
        self.deadline = nil
        self.lifecycle = .inbox
        self.unschedulableReason = nil
        self.unschedulableCount = 0
        self.createdAt = now
    }

    /// Moves the idea to `target`, enforcing the lifecycle. A proposed block never marks an idea explored.
    public mutating func transition(to target: IdeaLifecycle, at now: Date) throws {
        let allowed: Set<IdeaLifecycle> =
            switch lifecycle {
            case .inbox: [.availableForPlanning, .archived]
            case .availableForPlanning: [.inbox, .scheduled, .explored, .archived]
            case .scheduled: [.availableForPlanning, .explored, .archived]
            case .explored: [.availableForPlanning, .archived]
            case .archived: [.inbox, .availableForPlanning]
            }
        guard allowed.contains(target) else {
            throw DomainError.invalidTransition(entity: "idea", from: lifecycle.rawValue, to: target.rawValue)
        }
        lifecycle = target
        updatedAt = now
    }
}
