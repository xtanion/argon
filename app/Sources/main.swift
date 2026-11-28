import AppKit

NSFont.registerBundledFonts()
LegacySettings.migrate()

let appDelegate = AppDelegate()
exit(STMain(CommandLine.argc, CommandLine.unsafeArgv, appDelegate))
