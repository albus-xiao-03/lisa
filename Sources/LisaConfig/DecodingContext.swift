// Issue collection for one decoding pass: problems with positions, setting positions and already-invalid paths.

/// Collects the issues and setting positions of one decoding pass. It belongs to a single synchronous decode and is
/// never shared between tasks or threads.
final class DecodingContext {
    /// The most issues listed in one error; any further issues are counted in a final summary issue.
    static let maxListedIssues = 200

    private struct Entry {
        let issue: ConfigurationIssue
        let position: SourcePosition?
        let order: Int
    }

    /// The home directory that a leading `~` in a path expands to.
    let homeDirectory: String
    private var entries: [Entry] = []
    private var issuePaths: [ConfigurationPath] = []
    private var omittedIssueCount = 0
    private var positions: [ConfigurationPath: SourcePosition] = [:]

    init(homeDirectory: String) {
        self.homeDirectory = homeDirectory
    }

    /// Remembers where the value at `path` starts, so later issues about it can name a line and column.
    func record(_ path: ConfigurationPath, at position: SourcePosition) {
        positions[path] = position
    }

    /// The position of the value at `path`, or of its nearest enclosing value that appears in the document.
    func position(of path: ConfigurationPath) -> SourcePosition? {
        var candidate: ConfigurationPath? = path
        while let current = candidate {
            if let position = positions[current] { return position }
            candidate = current.parent
        }
        return nil
    }

    /// Records a problem with the setting at `path`. The message must not quote the setting's value.
    func report(_ path: ConfigurationPath, at position: SourcePosition?, _ problem: String, fix: String? = nil) {
        issuePaths.append(path)
        guard entries.count < Self.maxListedIssues else {
            omittedIssueCount += 1
            return
        }
        let issue = ConfigurationIssue(
            path: path.description, problem: problem, fix: fix, line: position?.line, column: position?.column)
        entries.append(Entry(issue: issue, position: position, order: entries.count))
    }

    var hasIssues: Bool { !issuePaths.isEmpty }

    /// Whether an issue concerns `path`, a setting inside it, or a setting that encloses it. Cross-setting rules skip
    /// settings already reported, so one mistake produces one issue.
    func hasIssue(affecting path: ConfigurationPath) -> Bool {
        issuePaths.contains { path.contains($0) || $0.contains(path) }
    }

    /// The issues in document order: positioned issues by line and column, then the others in the order found.
    func listedIssues() -> [ConfigurationIssue] {
        let ordered = entries.sorted { lhs, rhs in
            switch (lhs.position, rhs.position) {
            case (let lhsPosition?, let rhsPosition?) where lhsPosition != rhsPosition:
                return lhsPosition < rhsPosition
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return lhs.order < rhs.order
            }
        }
        var issues = ordered.map(\.issue)
        if omittedIssueCount > 0 {
            issues.append(
                ConfigurationIssue(
                    path: ConfigurationPath.root.description,
                    problem: "\(omittedIssueCount) more issues were found and are not listed",
                    fix: "fix the issues above, then check the file again"))
        }
        return issues
    }
}
