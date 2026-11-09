import AppKit

LegacySettings.migrate()

let appDelegate = AppDelegate()
exit(ACMain(CommandLine.argc, CommandLine.unsafeArgv, appDelegate))
