// Test-only. The kind tags every test carries, so reports can tell unit, integration, recovery, acceptance and adapter
// results apart (CONSTRICTION "Tests"; plan §9, §10). Used by every suite (L01–L33, §16.2, §16.3).

import Testing

extension Tag {
    /// One engine, rule or parser checked on its own: no store, no other process and no network.
    @Tag static var unit: Self
    /// Several components working together, such as services over a real store in a scratch directory.
    @Tag static var integration: Self
    /// Behavior across restarts, crashes and uncertain outcomes.
    @Tag static var recovery: Self
    /// An end-to-end acceptance scenario.
    @Tag static var acceptance: Self
    /// Real adapter code run against a controlled, test-only substitute on loopback.
    @Tag static var adapter: Self
}
