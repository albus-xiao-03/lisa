// Unit tests for L26, notification routing at policy level (NOTIFY-01, NOTIFY-03, NOTIFY-05, REM-02; D-26, D-27):
// eligible reminders, important changes and brief availability go to every enabled device by default, the iPhone and
// the iPad alike; per-device enablement and categories, reported permission denial, missing push registrations and
// revoked devices are honored with a recorded reason; quiet hours defer or expire deliveries; validity windows end.

import Foundation
import LisaDomain
import LisaPolicy
import LisaTime
import Testing

@Suite("L26 — Notification routing", .tags(.unit))
struct L26NotificationRoutingTests {
    /// Monday 2026-11-16, 14:00 in New York.
    private let now = TestTime.instant("2026-11-16T14:00", in: TestTime.newYork)

    private func device(
        _ deviceClass: DeviceClass, _ id: String, transport: NotificationTransportKind = .apns,
        authorization: NotificationAuthorization = .authorized,
        preferences: DeviceNotificationPreferences = DeviceNotificationPreferences()
    ) -> DeviceRegistration {
        SyntheticDevice.registration(
            deviceClass, transport: transport, authorization: authorization, preferences: preferences, now: now,
            id: DeviceID(id))
    }

    private func route(
        _ category: NotificationCategory, _ devices: [DeviceRegistration], level: InterruptionLevel = .active
    ) -> [RoutingDecision] {
        NotificationRouting.route(category: category, level: level, devices: devices)
    }

    @Test(
        "Reminders, important changes and brief availability reach every enabled device by default",
        arguments: [NotificationCategory.reminder, .commitmentChange, .brief])
    func everyEnabledDeviceByDefault(category: NotificationCategory) {
        let devices = [
            device(.iPhone, "device-a-iphone"), device(.iPad, "device-b-ipad"),
            device(.mac, "device-c-mac", transport: .local),
        ]
        let decisions = route(category, devices)
        #expect(decisions.map(\.deviceID) == devices.map(\.id))
        #expect(decisions.allSatisfy { $0.deliver && $0.suppressionReason == nil })
        #expect(decisions.allSatisfy { $0.level == .active && !$0.showTitle })
    }

    @Test("Every active device gets exactly one decision, in a stable order, whatever the input order")
    func noDeviceIsSilentlyChosen() {
        let devices = [device(.iPad, "device-2"), device(.iPhone, "device-1"), device(.iPhone, "device-3")]
        let decisions = route(.reminder, devices)
        #expect(decisions.map(\.deviceID) == [DeviceID("device-1"), DeviceID("device-2"), DeviceID("device-3")])
        #expect(route(.reminder, devices.reversed()) == decisions)
    }

    @Test("A device with notifications turned off is skipped with a recorded reason; the others still deliver")
    func perDeviceEnablement() {
        let decisions = route(
            .reminder,
            [
                device(.iPhone, "device-1"),
                device(.iPad, "device-2", preferences: DeviceNotificationPreferences(enabled: false)),
            ])
        #expect(decisions.map(\.deliver) == [true, false])
        #expect(decisions[1].suppressionReason == "notifications are turned off for this device")
    }

    @Test("A category turned off on one device is skipped there only")
    func perDeviceCategories() {
        let noBriefs = DeviceNotificationPreferences(
            categories: Set(NotificationCategory.allCases).subtracting([.brief]))
        let devices = [device(.iPhone, "device-1", preferences: noBriefs), device(.iPad, "device-2")]
        let briefs = route(.brief, devices)
        #expect(briefs.map(\.deliver) == [false, true])
        #expect(briefs[0].suppressionReason == "this category is turned off for this device")
        #expect(route(.reminder, devices).map(\.deliver) == [true, true])
    }

    @Test(
        "Reported permission that does not allow display is honored and recorded",
        arguments: [NotificationAuthorization.denied, .notDetermined, .unknown])
    func reportedPermissionDenial(authorization: NotificationAuthorization) {
        let decisions = route(.reminder, [device(.iPhone, "device-1", authorization: authorization)])
        #expect(decisions.map(\.deliver) == [false])
        #expect(
            decisions.first?.suppressionReason
                == "the device reports notification permission as \(authorization.rawValue)")
    }

    @Test(
        "Permission that allows display delivers",
        arguments: [NotificationAuthorization.authorized, .provisional, .ephemeral])
    func permittedDisplay(authorization: NotificationAuthorization) {
        #expect(route(.reminder, [device(.iPad, "device-1", authorization: authorization)]).map(\.deliver) == [true])
    }

    @Test(
        "A push device without an active token is skipped with a reason; a local-notification device needs none",
        arguments: [PushTokenState.invalid, .unregistered, .replaced])
    func missingPushRegistration(state: PushTokenState) {
        var stale = device(.iPhone, "device-1")
        stale.pushToken?.state = state
        var missing = device(.iPad, "device-2")
        missing.pushToken = nil
        let mac = device(.mac, "device-3", transport: .local)
        let decisions = route(.reminder, [stale, missing, mac])
        #expect(decisions.map(\.deliver) == [false, false, true])
        #expect(decisions.prefix(2).allSatisfy { $0.suppressionReason == "the device has no active push registration" })
    }

    @Test("A revoked device receives nothing and is not routed at all")
    func revokedDevicesAreExcluded() {
        var revoked = device(.iPad, "device-2")
        revoked.state = .revoked
        revoked.revokedAt = now
        let decisions = route(.reminder, [device(.iPhone, "device-1"), revoked])
        #expect(decisions.map(\.deviceID) == [DeviceID("device-1")])
        #expect(!revoked.canReceiveNotifications)
    }

    @Test("Per-device detail and level preferences shape the decision without changing who receives it")
    func perDevicePresentation() {
        let titles = DeviceNotificationPreferences(showTitles: true)
        let noTimeSensitive = DeviceNotificationPreferences(allowTimeSensitive: false)
        let decisions = route(
            .reminder,
            [
                device(.iPhone, "device-1", preferences: titles),
                device(.iPad, "device-2", preferences: noTimeSensitive),
            ],
            level: .timeSensitive)
        #expect(decisions.map(\.deliver) == [true, true])
        #expect(decisions.map(\.showTitle) == [true, false])
        #expect(decisions.map(\.level) == [.timeSensitive, .active])
    }

    @Test("During quiet hours a delivery waits for 07:00 if it is still valid then, and expires otherwise")
    func quietHoursDeferOrExpire() {
        let zone = TestTime.newYork.timeZone
        let late = TestTime.instant("2026-11-16T23:00", in: TestTime.newYork)
        let morning = TestTime.instant("2026-11-17T07:00", in: TestTime.newYork)
        let quiet = QuietHours.defaultValue
        #expect(
            DeliveryTiming.quietHours(
                at: late, quiet: quiet, zone: zone,
                validUntil: TestTime.instant("2026-11-17T09:00", in: TestTime.newYork))
                == .deferUntil(morning))
        #expect(DeliveryTiming.quietHours(at: late, quiet: quiet, zone: zone, validUntil: nil) == .deferUntil(morning))
        #expect(
            DeliveryTiming.quietHours(
                at: late, quiet: quiet, zone: zone,
                validUntil: TestTime.instant("2026-11-17T06:00", in: TestTime.newYork))
                == .expire)
        #expect(DeliveryTiming.quietHours(at: now, quiet: quiet, zone: zone, validUntil: nil) == .sendNow)
        let early = TestTime.instant("2026-11-17T05:30", in: TestTime.newYork)
        #expect(DeliveryTiming.quietHours(at: early, quiet: quiet, zone: zone, validUntil: nil) == .deferUntil(morning))
    }

    @Test("Validity windows: reminders end by their deadline, plan blocks at their end, daily items at midnight")
    func validityWindows() {
        let zone = TestTime.newYork.timeZone
        let settings = NotificationSettings()
        let deadline = Deadline.at(instant: now.addingTimeInterval(30 * 60), zone: TestTime.newYork)
        func valid(_ category: NotificationCategory, deadline: Deadline? = nil, blockEnd: Date? = nil) -> Date {
            DeliveryTiming.validUntil(
                category: category, dueAt: now, deadline: deadline, blockEnd: blockEnd, zone: zone, settings: settings)
        }
        #expect(valid(.reminder, deadline: deadline) == now.addingTimeInterval(30 * 60))
        #expect(valid(.reminder, deadline: .at(instant: now.addingTimeInterval(-60), zone: nil)) == now)
        #expect(valid(.reminder) == now.addingTimeInterval(TimeInterval(settings.defaultValidityMinutes * 60)))
        #expect(valid(.planBlock, blockEnd: now.addingTimeInterval(45 * 60)) == now.addingTimeInterval(45 * 60))
        let midnight = TestTime.instant("2026-11-17T00:00", in: TestTime.newYork)
        for category in [NotificationCategory.overdue, .eventProposal, .brief] {
            #expect(valid(category) == midnight, "\(category)")
        }
        #expect(valid(.commitmentChange) == now.addingTimeInterval(TimeInterval(settings.defaultValidityMinutes * 60)))
    }
}
