// The `lisa` command-line interface (CLI-01): the headless host's commands, with --help, explicit data and
// configuration paths, exit codes and machine-readable output.

import ArgumentParser

/// The release identifier reported by `lisa --version`, health and backups.
enum LisaVersion {
    static let current = "0.9.0-r1"
}

@main
struct LisaCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lisa",
        abstract: "Lisa, a single-owner personal secretary: headless host commands.",
        discussion: """
            Commands open the data directory directly and take its single-writer lock, so they fail clearly (exit 4) \
            while another Lisa runtime owns it. Delivery is a dry run until a channel is deliberately set to live.

            Exit codes: 0 success, 1 failure, 3 invalid configuration, 4 data directory in use, 5 checks failed, \
            6 host refused to start, 64 usage error.
            """,
        version: LisaVersion.current,
        subcommands: [
            DoctorCommand.self, DemoCommand.self, RunOnceCommand.self, ImportCommand.self, CaptureCommand.self,
            PlanCommand.self, BriefCommand.self, StatusCommand.self, ExportCommand.self, BackupCommand.self,
            RestoreCommand.self, DeviceCommand.self, TaskCommand.self, ReminderCommand.self, ProposalCommand.self,
            PreferenceCommand.self,
        ])
}
