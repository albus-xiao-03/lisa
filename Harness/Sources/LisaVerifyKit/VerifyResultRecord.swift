// One line of `results.jsonl` (plan §10.8 "Results"), in the field order the plan lists, with the X1 additions
// `design`, `pairSession` and `checks` (docs/DECISIONS.md D-54). The X1 proof app writes the same keys, so its
// records import unchanged.

/// One record per case and device: what was expected, what was observed, the status, executor and cause.
public struct VerifyResultRecord: Codable, Sendable, Equatable {
    /// Non-secret configuration: a digest of the whole, plus allowlisted fields.
    public struct Configuration: Codable, Sendable, Equatable {
        public var digest: String
        public var fields: [String: String]

        public init(digest: String, fields: [String: String]) {
            self.digest = digest
            self.fields = fields
        }
    }

    /// Wall-clock times for correlation only; monotonic times for measurement (plan §10.8 "Timing").
    public struct Times: Codable, Sendable, Equatable {
        public var wallClockStart: String
        public var wallClockEnd: String
        public var monotonicStartNanoseconds: UInt64
        public var monotonicEndNanoseconds: UInt64

        public init(
            wallClockStart: String, wallClockEnd: String, monotonicStartNanoseconds: UInt64,
            monotonicEndNanoseconds: UInt64
        ) {
            self.wallClockStart = wallClockStart
            self.wallClockEnd = wallClockEnd
            self.monotonicStartNanoseconds = monotonicStartNanoseconds
            self.monotonicEndNanoseconds = monotonicEndNanoseconds
        }
    }

    /// A paired session's join keys: both devices' records share the base case and the harness nonce.
    public struct PairSession: Codable, Sendable, Equatable {
        public var baseCaseID: String
        public var role: String
        public var devices: String
        public var condition: String
        public var harnessNonce: String
        public var sessionCodes: [String]

        public init(
            baseCaseID: String, role: String, devices: String, condition: String, harnessNonce: String,
            sessionCodes: [String]
        ) {
            self.baseCaseID = baseCaseID
            self.role = role
            self.devices = devices
            self.condition = condition
            self.harnessNonce = harnessNonce
            self.sessionCodes = sessionCodes
        }
    }

    /// One criterion of the case, for example one N-1 check of a nearby cell.
    public struct Check: Codable, Sendable, Equatable {
        public var id: String
        public var status: VerifyStatus
        public var observed: String
        public var evidenceEntries: Int

        public init(id: String, status: VerifyStatus, observed: String, evidenceEntries: Int) {
            self.id = id
            self.status = status
            self.observed = observed
            self.evidenceEntries = evidenceEntries
        }
    }

    public var runID: String
    /// The case ID, or `<case>@<role>` for a paired session's device result.
    public var caseID: String
    public var commit: String
    public var harnessVersion: String
    public var providerInterface: String
    public var configuration: Configuration
    public var platform: String
    public var deviceModel: String
    public var osVersion: String
    public var xcodeVersion: String
    public var apnsEnvironment: String?
    public var profileKind: String?
    public var modelID: String?
    public var assumptions: [String]
    public var requiredEvidence: [String]
    public var expectedResult: String
    public var observedResult: String
    /// Set only when the status is PASS.
    public var resultLevel: VerifyResultLevel?
    public var requiredResultLevel: VerifyResultLevel
    public var status: VerifyStatus
    public var executor: VerifyExecutor
    public var cause: String
    /// `<action ID>=<outcome>` for each logical action the case caused.
    public var actions: [String]
    public var times: Times
    public var evidenceFiles: [String]
    /// The known finding (plan §17.1) a result is recorded against, if any.
    public var knownFinding: String?
    public var design: String?
    public var pairSession: PairSession?
    public var checks: [Check]

    public init(
        runID: String, caseID: String, commit: String, harnessVersion: String, providerInterface: String,
        configuration: Configuration, platform: String, deviceModel: String, osVersion: String, xcodeVersion: String,
        apnsEnvironment: String? = nil, profileKind: String? = nil, modelID: String? = nil, assumptions: [String],
        requiredEvidence: [String], expectedResult: String, observedResult: String, resultLevel: VerifyResultLevel?,
        requiredResultLevel: VerifyResultLevel, status: VerifyStatus, executor: VerifyExecutor, cause: String,
        actions: [String], times: Times, evidenceFiles: [String], knownFinding: String? = nil, design: String? = nil,
        pairSession: PairSession? = nil, checks: [Check] = []
    ) {
        self.runID = runID
        self.caseID = caseID
        self.commit = commit
        self.harnessVersion = harnessVersion
        self.providerInterface = providerInterface
        self.configuration = configuration
        self.platform = platform
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.xcodeVersion = xcodeVersion
        self.apnsEnvironment = apnsEnvironment
        self.profileKind = profileKind
        self.modelID = modelID
        self.assumptions = assumptions
        self.requiredEvidence = requiredEvidence
        self.expectedResult = expectedResult
        self.observedResult = observedResult
        self.resultLevel = resultLevel
        self.requiredResultLevel = requiredResultLevel
        self.status = status
        self.executor = executor
        self.cause = cause
        self.actions = actions
        self.times = times
        self.evidenceFiles = evidenceFiles
        self.knownFinding = knownFinding
        self.design = design
        self.pairSession = pairSession
        self.checks = checks
    }
}
