// R1's `PATCH /v1/preferences` request and answers in R1's bytes (plan §8.12.2; docs/DECISIONS.md D-74, D-75). The
// router's conversion reads the request and renders the answer here, and so will the administrative terminal's
// `resolve`, so a request decided after a hold gets the bytes it would have got at once. The texts are R1's
// (`APIRouter.decode`, `SettingsHandlers.updatePreferences`, `DTOMapping.preference`), checked against R1's own path.

import Foundation
import LisaAPIContract
import LisaDomain

extension LegacyPreferenceRoutes {
    /// The changes a request body names, or R1's refusal of it: a body that is missing or doesn't decode, or one with
    /// fewer than 1 or more than 50 changes. A value sets its key, `confirm: true` confirms it, and anything else
    /// deletes it.
    public static func requested(_ body: Data?) -> Result<[Change], APIErrorBody> {
        guard let body, !body.isEmpty else {
            return .failure(APIErrorBody(code: .invalidRequest, message: "a JSON request body is required"))
        }
        guard let patch = try? APIJSON.decoder().decode(PreferencesPatchRequest.self, from: body) else {
            return .failure(
                APIErrorBody(
                    code: .invalidRequest,
                    message: "the request body does not match the documented schema for this route"))
        }
        guard !patch.changes.isEmpty, patch.changes.count <= 50 else {
            return .failure(
                APIErrorBody(code: .invalidRequest, message: "send between 1 and 50 changes", field: "changes"))
        }
        return .success(
            patch.changes.map { change in
                let action: Action
                if let value = change.value {
                    action = .set(value.r1Value, expectedRevision: change.expectedRevision)
                } else if change.confirm == true {
                    action = .confirm
                } else {
                    action = .delete
                }
                return Change(key: change.key, action: action)
            })
    }

    /// §8.12.2's answer while a request waits for an administrative decision: R1's 503, never recorded.
    public static let awaitingReview = APIErrorBody(
        code: .unavailable, message: "This change is waiting for review on the administrative terminal.",
        retryAfterSeconds: 300)

    /// R1's answer to a converted request: 200 with every preference, the refusal's template, or the 503 while it
    /// waits for an administrative decision.
    public static func answer(_ effect: Effect) throws -> (status: Int, body: [UInt8]) {
        let error: APIErrorBody
        if effect.heldIndex != nil {
            error = awaitingReview
        } else if let refused = effect.refusal {
            error = template(refused)
        } else {
            return (200, [UInt8](try APIJSON.encoder().encode(effect.preferences.map(dto))))
        }
        return (error.code.httpStatus, [UInt8](try APIJSON.encoder().encode(error)))
    }

    /// R1's refusal of a change, with R1's code, from a fixed template that names the change's position and never the
    /// caller's key or value (§8.12.2 "Error bodies never echo caller input").
    public static func template(_ refused: Refused) -> APIErrorBody {
        let change = "changes[\(refused.index)]"
        switch refused.refusal {
        case .unsupportedKey:
            return APIErrorBody(
                code: .invalidRequest, message: "\(change).key is not a supported preference", field: "\(change).key")
        case .invalidValue(let reason):
            // R1's reasons are its own text; only an unknown weekday's names the caller's token.
            let shown = reason.hasPrefix("unknown weekday") ? "has an unknown weekday" : reason
            return APIErrorBody(code: .invalidRequest, message: "\(change).value \(shown)", field: "\(change).value")
        case .ownerOnly:
            return APIErrorBody(code: .forbidden, message: "\(change) can be changed only by the owner on the host")
        case .deletedByOwnerOnly:
            return APIErrorBody(code: .forbidden, message: "\(change) can be deleted only by the owner on the host")
        case .notPermitted:
            return APIErrorBody(code: .forbidden, message: "\(change) can't be changed by this caller")
        case .notFound:
            return APIErrorBody(code: .notFound, message: "\(change) names a preference that does not exist")
        case .changed(let currentRevision):
            return APIErrorBody(
                code: .conflict, message: "\(change) changed since it was read; reload it and try again",
                currentRevision: currentRevision)
        }
    }

    /// R1's DTO of a record, as `DTOMapping.preference` writes it.
    static func dto(_ preference: Preference) -> PreferenceDTO {
        PreferenceDTO(
            key: preference.key.rawValue, value: PreferenceValueDTO(preference.value),
            origin: preference.origin.rawValue, confirmed: preference.confirmed, effective: preference.isEffective,
            consequential: preference.key.isConsequential, revision: preference.revision.value,
            updatedAt: preference.updatedAt)
    }
}

extension PreferenceValueDTO {
    /// R1's value of the DTO, as `DTOMapping.preferenceValue` reads it.
    var r1Value: PreferenceValue {
        switch self {
        case .text(let text): .text(text)
        case .number(let number): .number(number)
        case .flag(let flag): .flag(flag)
        case .list(let list): .list(list)
        }
    }

    /// The DTO of R1's value, as `DTOMapping.preferenceValue` writes it.
    init(_ value: PreferenceValue) {
        switch value {
        case .text(let text): self = .text(text)
        case .number(let number): self = .number(number)
        case .flag(let flag): self = .flag(flag)
        case .list(let list): self = .list(list)
        }
    }
}
