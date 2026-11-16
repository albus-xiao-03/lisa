// The demonstration's fixed time, synthetic identities and host settings: dry-run delivery, no accounts (CFG-02).

import Foundation
import LisaDelivery
import LisaDevices
import LisaDomain
import LisaHost
import LisaInference
import LisaLocalSources
import LisaTime

/// Constants of the demonstration scenario. All identities are synthetic.
public enum DemoConstants {
    /// 2026-11-16T13:00:00Z, which is 08:00 on a Monday in the demo owner's time zone.
    public static let start = Date(timeIntervalSince1970: 1_794_834_000)
    public static let zone = TimeZoneID("America/New_York")!
    public static let ownerAddress = "owner@example.com"
    public static let mailboxAddress = "lisa@example.invalid"
    public static let ownerPhone = "+15550100"
    public static let appTopic = "com.example.lisa.demo"
    public static let label = "Lisa offline demonstration (synthetic data; no account is contacted, nothing is sent)"
}

/// Where the scenario's fixture files are.
public struct DemoFixtures: Sendable {
    public var mail: URL
    public var calendar: URL
    public var feeds: URL
    public var preferences: URL
    public var idea: URL

    public init(root: URL) {
        mail = root.appendingPathComponent("mail")
        calendar = root.appendingPathComponent("calendar")
        feeds = root.appendingPathComponent("feeds")
        preferences = root.appendingPathComponent("demo/preferences.json")
        idea = root.appendingPathComponent("demo/idea.txt")
    }
}

extension DemoConstants {
    /// Host settings for the demonstration: every channel dry-run, the labeled rule-based model, local fixture
    /// sources, and one source that cannot be reached so source health shows a failure.
    public static func hostSettings(dataDirectory: URL, fixtures: DemoFixtures, applicationVersion: String)
        -> HostSettings
    {
        var owner = OwnerSettings(zone: zone)
        owner.delivery = DeliverySettings(
            emailMode: .dryRun, callMode: .dryRun, pushMode: .dryRun, emailEnabled: true,
            approvedEmailAddresses: [ownerAddress])
        owner.calls = CallSettings(enabled: true, approvedNumber: ownerPhone)
        owner.brief.deliveryTime = LocalTime(hour: 7, minute: 30)!
        let unavailable = dataDirectory.appendingPathComponent("demo-unavailable-feed")
        return HostSettings(
            dataDirectory: dataDirectory, applicationVersion: applicationVersion, ownerSettings: owner,
            model: .deterministic,
            dataSharing: .localOnly,
            pushPolicy: PushRegistrationPolicy(allowedTopics: [appTopic], allowedEnvironments: [.development]),
            sources: [
                HostSource(
                    key: "demo-mail", name: "Demo mailbox (local files)", kind: .localImport,
                    access: .localDirectory(fixtures.mail, .mail), mailboxAddress: mailboxAddress),
                HostSource(
                    key: "demo-calendar", name: "Demo work calendar (local file)", kind: .calendarFeed,
                    access: .localDirectory(fixtures.calendar, .calendar)),
                HostSource(
                    key: "demo-news", name: "Demo news feeds (local files)", kind: .newsFeed,
                    access: .localDirectory(fixtures.feeds, .feed)),
                HostSource(
                    key: "demo-unavailable", name: "Demo unavailable feed", kind: .newsFeed,
                    access: .localDirectory(unavailable, .feed)),
            ],
            emailSender: EmailSender(address: mailboxAddress, name: "Lisa (demo)"))
    }
}
