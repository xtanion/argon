import AppKit

NSFont.registerBundledFonts()
LegacySettings.migrate()

let appDelegate = AppDelegate()
exit(ACMain(CommandLine.argc, CommandLine.unsafeArgv, appDelegate))
