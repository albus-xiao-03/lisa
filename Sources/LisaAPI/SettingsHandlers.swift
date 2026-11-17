// Handlers for preferences, source status, health and export.

import Foundation
import LisaAPIContract
import LisaApplication
import LisaDomain
import LisaOwnerData
import LisaPorts

extension APIRouter {
    func preferences() throws -> APIResponse {
        let preferences = try application.services.preferences.list()
        return try json(preferences.map(DTOMapping.preference))
    }

    /// Applies changes in order. The first refused change stops the request; earlier changes stay applied and are
    /// visible in the next read, so a client always re-reads after an error.
    func updatePreferences(_ request: APIRequest, _ caller: Caller) throws -> APIResponse {
        let body = try decode(PreferencesPatchRequest.self, request)
        guard !body.changes.isEmpty, body.changes.count <= 50 else {
            throw APIFailure.invalid("send between 1 and 50 changes", field: "changes")
        }
        let principal = try principal(caller)
        for change in body.changes {
            let key = PreferenceKey(change.key)
            if let value = change.value {
                _ = try application.setPreference(
                    key, DTOMapping.preferenceValue(value),
                    expectedRevision: change.expectedRevision.map(Revision.init),
                    by: principal)
            } else if change.confirm == true {
                _ = try application.confirmPreference(key, by: principal)
            } else {
                _ = try application.delete(.preference(key), by: principal)
            }
        }
        return try preferences()
    }

    func sourcesStatus() throws -> APIResponse {
        let now = application.services.clock.now()
        let sources = try application.all(Source.self).sorted { $0.name < $1.name }
        return try json(sources.map { DTOMapping.source($0, now: now) })
    }

    func health() throws -> APIResponse {
        let runtime = status.runtimeStatus()
        let now = application.services.clock.now()
        let owner = try application.services.settings.currentSettings()
        let counts = try application.outboxCounts()
        let sources = try application.all(Source.self).sorted { $0.name < $1.name }.map {
            DTOMapping.source($0, now: now)
        }
        let devices = try application.all(
            DeviceRegistration.self, RecordQuery.all.filter("state", equals: DeviceState.active.rawValue))
        let deviceWarnings = devices.compactMap { device -> String? in
            guard !device.canReceiveNotifications else { return nil }
            if !device.preferences.enabled { return "\(device.name): notifications are turned off for this device" }
            if !device.authorization.allowsDisplay {
                return "\(device.name): notification permission is \(device.authorization.rawValue)"
            }
            return "\(device.name): no active push registration"
        }
        let outbox = OutboxSummaryDTO(
            pending: counts[.pending] ?? 0, inProgress: counts[.inProgress] ?? 0,
            outcomeUnknown: counts[.outcomeUnknown] ?? 0, failed: counts[.failed] ?? 0,
            capturedDryRun: counts[.capturedDryRun] ?? 0)
        let degraded =
            sources.contains { $0.enabled && ($0.failing || $0.freshness == "stale") } || outbox.outcomeUnknown > 0
            || !deviceWarnings.isEmpty || !runtime.warnings.isEmpty
        let overall = runtime.lastCycleProblem != nil ? "failing" : (degraded ? "degraded" : "ok")
        return try json(
            HealthDTO(
                status: overall, apiVersion: APIVersioning.version,
                applicationVersion: configuration.applicationVersion,
                schemaVersion: configuration.schemaVersion, startedAt: runtime.startedAt,
                lastCycleAt: runtime.lastCycleAt,
                lastCycleProblem: runtime.lastCycleProblem,
                deliveryModes: [
                    "email": owner.delivery.emailMode.rawValue, "call": owner.delivery.callMode.rawValue,
                    "push": owner.delivery.pushMode.rawValue,
                    "localNotification": configuration.localNotificationsLive ? "live" : "dryRun",
                ],
                outbox: outbox, sources: sources, deviceWarnings: deviceWarnings, warnings: runtime.warnings,
                model: configuration.model))
    }

    func export(_ caller: Caller) throws -> APIResponse {
        let data = try application.services.export.export(
            schemaVersion: configuration.schemaVersion, applicationVersion: configuration.applicationVersion,
            by: try principal(caller))
        return APIResponse(status: 200, headers: Self.headers(contentType: "application/json"), body: data)
    }
}
