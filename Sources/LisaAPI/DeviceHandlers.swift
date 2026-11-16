// Handlers for pairing, push registration, permission status, per-device preferences, receipts and device removal.

import Foundation
import LisaAPIContract
import LisaApplication
import LisaDevices
import LisaDomain

extension APIRouter {
    func createPairingCode(_ caller: Caller) throws -> APIResponse {
        let code = try application.createPairingCode(by: try principal(caller))
        return try json(PairingCodeDTO(code: code.code, expiresAt: code.expiresAt), status: 201)
    }

    func pairDevice(_ request: APIRequest) throws -> APIResponse {
        let body = try decode(PairDeviceRequest.self, request)
        guard !body.installationID.isEmpty, body.installationID.count <= 128 else {
            throw APIFailure.invalid("installationID must be 1 to 128 characters", field: "installationID")
        }
        guard let deviceClass = DeviceClass(rawValue: body.deviceClass.rawValue),
            let environment = APNsEnvironment(rawValue: body.environment.rawValue)
        else { throw APIFailure.invalid("unknown device class or environment") }
        let issued = try application.pairDevice(
            code: body.code, installationID: body.installationID, name: body.name, deviceClass: deviceClass,
            appBundleID: body.appBundleID, environment: environment)
        return try json(
            PairDeviceResponse(
                device: DTOMapping.device(issued.registration, current: issued.registration.id),
                credential: issued.credential),
            status: 201)
    }

    func pushRegistration(_ request: APIRequest, _ caller: Caller) throws -> APIResponse {
        let deviceID = try requireDevice(caller)
        let body = try decode(PushRegistrationRequest.self, request)
        guard let environment = APNsEnvironment(rawValue: body.environment.rawValue) else {
            throw APIFailure.invalid("unknown environment", field: "environment")
        }
        let device = try application.registerPushToken(
            deviceID: deviceID, token: body.token, environment: environment, topic: body.topic)
        return try json(DTOMapping.device(device, current: deviceID))
    }

    func notificationStatus(_ request: APIRequest, _ caller: Caller) throws -> APIResponse {
        let deviceID = try requireDevice(caller)
        let body = try decode(NotificationStatusRequest.self, request)
        guard let authorization = NotificationAuthorization(rawValue: body.authorization.rawValue) else {
            throw APIFailure.invalid("unknown authorization", field: "authorization")
        }
        guard body.settings.count <= 20 else { throw APIFailure.invalid("at most 20 settings", field: "settings") }
        let device = try application.reportNotificationStatus(
            deviceID: deviceID, authorization: authorization, settings: body.settings)
        return try json(DTOMapping.device(device, current: deviceID))
    }

    func deviceNotificationPreferences(_ caller: Caller) throws -> APIResponse {
        let deviceID = try requireDevice(caller)
        guard let device = try application.record(DeviceRegistration.self, id: deviceID) else {
            throw APIFailure.notFound("the device")
        }
        return try json(DTOMapping.devicePreferences(device))
    }

    func updateDeviceNotificationPreferences(_ request: APIRequest, _ caller: Caller) throws -> APIResponse {
        let deviceID = try requireDevice(caller)
        let body = try decode(DeviceNotificationPreferencesPatch.self, request)
        guard let device = try application.record(DeviceRegistration.self, id: deviceID) else {
            throw APIFailure.notFound("the device")
        }
        var preferences = device.preferences
        if let enabled = body.enabled { preferences.enabled = enabled }
        if let names = body.categories {
            preferences.categories = Set(
                try names.map { name in
                    guard let category = NotificationCategory(rawValue: name) else {
                        throw APIFailure.invalid("unknown notification category \(name)", field: "categories")
                    }
                    return category
                })
        }
        if let showTitles = body.showTitles { preferences.showTitles = showTitles }
        if let allow = body.allowTimeSensitive { preferences.allowTimeSensitive = allow }
        let updated = try application.updateDevicePreferences(
            deviceID: deviceID, preferences: preferences, expectedRevision: Revision(body.expectedRevision))
        return try json(DTOMapping.devicePreferences(updated))
    }

    func notificationReceipts(_ request: APIRequest, _ caller: Caller) throws -> APIResponse {
        let deviceID = try requireDevice(caller)
        let body = try decode(NotificationReceiptsRequest.self, request)
        guard body.notificationIDs.count <= NotificationReceiptsRequest.maxNotificationIDs else {
            throw APIFailure.invalid(
                "at most \(NotificationReceiptsRequest.maxNotificationIDs) notification IDs per request",
                field: "notificationIDs")
        }
        _ = try application.recordReceipts(
            notificationIDs: body.notificationIDs.map(NotificationID.init), deviceID: deviceID)
        return APIResponse(status: 204, headers: Self.headers(contentType: "application/json"))
    }

    func listDevices(_ caller: Caller) throws -> APIResponse {
        _ = try principal(caller)
        let devices = try application.all(DeviceRegistration.self).sorted { $0.pairedAt < $1.pairedAt }
        return try json(devices.map { DTOMapping.device($0, current: caller.deviceID) })
    }

    func removeDevice(_ id: String, _ caller: Caller) throws -> APIResponse {
        let device = try application.revokeDevice(DeviceID(id), by: try principal(caller))
        return try json(DTOMapping.device(device, current: caller.deviceID))
    }
}
