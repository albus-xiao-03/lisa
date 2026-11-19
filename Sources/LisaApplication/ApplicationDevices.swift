// Device commands on the facade: pairing, push registration, permission status, preferences and receipts.

import Foundation
import LisaDelivery
import LisaDevices
import LisaDomain
import LisaPorts

extension LisaApplication {
    /// Pairs a device with a one-time code; the credential is returned once.
    public func pairDevice(
        code: String, installationID: String, name: String, deviceClass: DeviceClass, appBundleID: String,
        environment: APNsEnvironment
    ) throws -> IssuedCredential {
        try services.devices.pair(
            code: code, installationID: installationID, name: name, deviceClass: deviceClass, appBundleID: appBundleID,
            environment: environment)
    }

    /// The paired device behind a credential, or `nil`.
    public func authenticateDevice(credential: String) throws -> DeviceRegistration? {
        try services.devices.authenticate(credential: credential)
    }

    /// Binds an APNs token to the calling device for a configured topic and environment.
    public func registerPushToken(deviceID: DeviceID, token: String, environment: APNsEnvironment, topic: String) throws
        -> DeviceRegistration
    {
        try services.devices.registerPushToken(
            deviceID: deviceID, token: token, environment: environment, topic: topic, policy: pushPolicy)
    }

    public func reportNotificationStatus(
        deviceID: DeviceID, authorization: NotificationAuthorization, settings: [String: String]
    )
        throws -> DeviceRegistration
    {
        try services.devices.reportNotificationStatus(
            deviceID: deviceID, authorization: authorization, settings: settings)
    }

    public func updateDevicePreferences(
        deviceID: DeviceID, preferences: DeviceNotificationPreferences, expectedRevision: Revision
    )
        throws -> DeviceRegistration
    {
        try services.devices.updatePreferences(
            deviceID: deviceID, preferences: preferences, expectedRevision: expectedRevision)
    }

    /// Records notifications a device reports as presented, the only evidence of display.
    public func recordReceipts(notificationIDs: [NotificationID], deviceID: DeviceID) throws -> Int {
        var recorded = 0
        for id in notificationIDs.prefix(200) {
            try recordReceipt(notificationID: id, deviceID: deviceID)
            recorded += 1
        }
        return recorded
    }
}
