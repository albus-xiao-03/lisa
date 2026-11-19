// The parts of Twilio's JSON responses the call transport reads: a created call's SID and an exception's error code.

import Foundation

/// Reads response bodies defensively: malformed or unexpected JSON yields `nil`, never a crash. Bodies are already
/// bounded by the request's response limit. Exception messages are never read: they can quote phone numbers.
enum TwilioResponseBody {
    /// The `sid` of a call resource, when it has the documented `CA` form.
    static func callSID(in body: Data) -> String? {
        guard let resource = try? JSONDecoder().decode(CallResource.self, from: body), let sid = resource.sid,
            TwilioFormats.isCallSID(sid)
        else { return nil }
        return sid
    }

    /// The numeric Twilio error `code` of an exception (`status`, `message`, `code`, `more_info`).
    static func errorCode(in body: Data) -> Int? {
        guard let exception = try? JSONDecoder().decode(Exception.self, from: body), let code = exception.code,
            (1...999_999).contains(code)
        else { return nil }
        return code
    }

    private struct CallResource: Decodable {
        let sid: String?
    }

    private struct Exception: Decodable {
        let code: Int?
    }
}
