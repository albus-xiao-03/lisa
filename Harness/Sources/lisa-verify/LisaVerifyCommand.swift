// `lisa-verify` (plan §10.8): the owner-verification harness's command line. It runs from a clean clone with
// `swift run lisa-verify <command>`; its run store is `~/LisaVerify` (or `--home`).

import ArgumentParser

@main
struct LisaVerifyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lisa-verify",
        abstract: "Lisa's owner-verification harness: cases, paired sessions, observations, imports, reports, exports.",
        version: HarnessInfo.version,
        subcommands: [
            QuickstartCommand.self, CasesCommand.self, GuideCommand.self, PairSessionCommand.self, ObserveCommand.self,
            ImportDiagnosticsCommand.self, ReportCommand.self, ExportCommand.self, ActionsCommand.self,
            AuthorizeRetryCommand.self, CleanupCommand.self, RunCommand.self, ResumeCommand.self, RetryCommand.self,
            PreflightCommand.self, FixtureActionCommand.self,
        ])
}
