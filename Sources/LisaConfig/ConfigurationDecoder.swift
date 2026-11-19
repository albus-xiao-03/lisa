// Decoding a parsed document into a validated configuration: the version, the top level and every section.

import LisaTime

/// Turns a parsed JSON5 document into a `LisaConfiguration`, collecting every issue before failing.
struct ConfigurationDecoder {
    let sourceName: String
    let homeDirectory: String

    func decode(_ root: JSON5Node) throws(ConfigurationError) -> LisaConfiguration {
        guard case .object(let object) = root.value else {
            throw ConfigurationError.invalid([
                ConfigurationIssue(
                    path: ConfigurationPath.root.description, problem: "must be an object in braces { }",
                    fix: "start the file with { version: 1, …", line: root.position.line, column: root.position.column)
            ])
        }
        try checkVersion(object)
        let context = DecodingContext(homeDirectory: homeDirectory)
        let top = ConfigSection(object, path: .root, position: root.position, context: context)
        _ = top.value("version")
        let dataDirectory = top.requiredValidated(
            "dataDirectory", maxLength: 1024,
            fix: "the directory where Lisa keeps her data, such as ~/.local/share/lisa"
        ) { FilePathRules.absolutePath($0, homeDirectory: homeDirectory) }
        let timeZone: TimeZoneID?
        if let value = top.value("timeZone") {
            timeZone = value.timeZone()
        } else {
            top.reportMissing("timeZone", fix: "the IANA zone for planning and reminders, such as \"America/New_York\"")
            timeZone = nil
        }
        // Placeholders below stand in for values already reported; the configuration is then rejected.
        let zone = timeZone ?? .utc
        let configuration = LisaConfiguration(
            version: ConfigurationLoader.supportedVersion,
            sourceName: sourceName,
            dataDirectory: dataDirectory ?? "/",
            timeZone: zone,
            planning: PlanningSection.decode(top.section("planning")),
            dateReading: DateReadingSection.decode(top.section("dateReading")),
            brief: BriefSection.decode(top.section("brief")),
            reminders: ReminderSection.decode(top.section("reminders")),
            news: NewsConfiguration.decode(top.section("news")),
            delivery: DeliveryConfiguration.decode(top.section("delivery")),
            email: top.section("email").flatMap(EmailAdapterConfiguration.decode),
            calls: top.section("calls").flatMap(CallAdapterConfiguration.decode),
            notifications: NotificationConfiguration.decode(top.section("notifications")),
            model: ModelConfiguration.decode(top.section("model")),
            sources: SourceConfiguration.decodeList(top.list("sources", maxCount: 100), defaultZone: zone),
            api: APIConfiguration.decode(top.section("api")),
            retention: RetentionConfiguration.decode(top.section("retention")),
            limits: ResourceLimits.decode(top.section("limits")))
        top.finish()
        ConfigurationValidator(context: context).validate(configuration)
        guard !context.hasIssues else {
            throw ConfigurationError.invalid(context.listedIssues())
        }
        return configuration
    }

    /// The version comes first: without a supported version, nothing else in the file can be interpreted.
    private func checkVersion(_ object: JSON5Object) throws(ConfigurationError) {
        let supported = ConfigurationLoader.supportedVersion
        guard let member = object.member("version") else {
            throw ConfigurationError.unsupportedVersion(found: nil, supported: supported)
        }
        if case .null = member.value.value {
            throw ConfigurationError.unsupportedVersion(found: nil, supported: supported)
        }
        guard case .number(let number) = member.value.value, let version = number.exactInteger else {
            throw ConfigurationError.invalid([
                ConfigurationIssue(
                    path: "version", problem: "must be the whole number \(supported), without quotes",
                    line: member.value.position.line, column: member.value.position.column)
            ])
        }
        guard version == supported else {
            throw ConfigurationError.unsupportedVersion(found: version, supported: supported)
        }
    }
}
