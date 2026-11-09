import AppKit

@MainActor
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        main.addSubmenu("Argon") { menu in
            menu.addItem(withTitle: "Settings...", action: #selector(BrowserWindowController.openSettings(_:)), keyEquivalent: ",")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Hide Argon", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
            menu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
                .keyEquivalentModifierMask = [.command, .option]
            menu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Quit Argon") { Application.shared.quit() }.withKey("q"))
        }

        main.addSubmenu("File") { menu in
            menu.addItem(withTitle: "New Tab", action: #selector(BrowserWindowController.newTab(_:)), keyEquivalent: "t")
            menu.addItem(withTitle: "New Space", action: #selector(BrowserWindowController.newSpace(_:)), keyEquivalent: "n")
                .keyEquivalentModifierMask = [.command, .shift]
            menu.addItem(withTitle: "Open File...", action: #selector(BrowserWindowController.openFile(_:)), keyEquivalent: "o")
            menu.addItem(withTitle: "Open Location...", action: #selector(BrowserWindowController.openLocation(_:)), keyEquivalent: "l")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Close Tab", action: #selector(BrowserWindowController.closeTab(_:)), keyEquivalent: "w")
            menu.addItem(withTitle: "Reopen Closed Tab", action: #selector(BrowserWindowController.reopenClosedTab(_:)), keyEquivalent: "t")
                .keyEquivalentModifierMask = [.command, .shift]
            menu.addItem(.separator())
            menu.addItem(withTitle: "Save Page As...", action: #selector(BrowserWindowController.savePage(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Print...", action: #selector(BrowserWindowController.printPage(_:)), keyEquivalent: "p")
            menu.addItem(withTitle: "Print Using System Dialog...", action: #selector(BrowserWindowController.printUsingSystemDialog(_:)), keyEquivalent: "p")
                .keyEquivalentModifierMask = [.command, .option]
            menu.addItem(.separator())
            menu.addItem(withTitle: "Copy URL", action: #selector(BrowserWindowController.copyURL(_:)), keyEquivalent: "c")
                .keyEquivalentModifierMask = [.command, .shift]
            menu.addItem(withTitle: "Copy URL as Markdown", action: #selector(BrowserWindowController.copyURLAsMarkdown(_:)), keyEquivalent: "c")
                .keyEquivalentModifierMask = [.command, .shift, .option]
        }

        main.addSubmenu("Edit") { menu in
            menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
            menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
                .keyEquivalentModifierMask = [.command, .shift]
            menu.addItem(.separator())
            menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
            menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
            menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
            menu.addItem(withTitle: "Paste and Match Style", action: Selector(("pasteAndMatchStyle:")), keyEquivalent: "v")
                .keyEquivalentModifierMask = [.command, .shift, .option]
            menu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
            menu.addItem(.separator())
            menu.addSubmenu("Find") { find in
                find.addItem(withTitle: "Find...", action: #selector(BrowserWindowController.performFind(_:)), keyEquivalent: "f")
                find.addItem(withTitle: "Find Next", action: #selector(BrowserWindowController.findNext(_:)), keyEquivalent: "g")
                find.addItem(withTitle: "Find Previous", action: #selector(BrowserWindowController.findPrevious(_:)), keyEquivalent: "g")
                    .keyEquivalentModifierMask = [.command, .shift]
            }
        }

        main.addSubmenu("View") { menu in
            menu.addItem(withTitle: "Toggle Sidebar", action: #selector(BrowserWindowController.toggleSidebarPanel(_:)), keyEquivalent: "s")
            let alternate = menu.addItem(withTitle: "Toggle Sidebar", action: #selector(BrowserWindowController.toggleSidebarPanel(_:)), keyEquivalent: "s")
            alternate.keyEquivalentModifierMask = [.control]
            alternate.isHidden = true
            alternate.allowsKeyEquivalentWhenHidden = true
            menu.addItem(.separator())
            menu.addItem(withTitle: "Reload Page", action: #selector(BrowserWindowController.reloadPage(_:)), keyEquivalent: "r")
            menu.addItem(withTitle: "Hard Reload", action: #selector(BrowserWindowController.hardReload(_:)), keyEquivalent: "r")
                .keyEquivalentModifierMask = [.command, .shift]
            menu.addItem(withTitle: "Stop", action: #selector(BrowserWindowController.stopLoading(_:)), keyEquivalent: ".")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Zoom In", action: #selector(BrowserWindowController.zoomIn(_:)), keyEquivalent: "+")
            menu.addHiddenAlternate("Zoom In", action: #selector(BrowserWindowController.zoomIn(_:)), key: "=", modifiers: [.command])
            menu.addItem(withTitle: "Zoom Out", action: #selector(BrowserWindowController.zoomOut(_:)), keyEquivalent: "-")
            menu.addItem(withTitle: "Actual Size", action: #selector(BrowserWindowController.actualSize(_:)), keyEquivalent: "0")
            menu.addItem(.separator())
            menu.addSubmenu("Developer") { dev in
                dev.addItem(withTitle: "Developer Tools", action: #selector(BrowserWindowController.toggleDevTools(_:)), keyEquivalent: "i")
                    .keyEquivalentModifierMask = [.command, .option]
                dev.addItem(withTitle: "JavaScript Console", action: #selector(BrowserWindowController.showConsole(_:)), keyEquivalent: "j")
                    .keyEquivalentModifierMask = [.command, .option]
                dev.addItem(withTitle: "Inspect Elements", action: #selector(BrowserWindowController.inspectElement(_:)), keyEquivalent: "c")
                    .keyEquivalentModifierMask = [.command, .option]
                dev.addItem(withTitle: "View Source", action: #selector(BrowserWindowController.viewSource(_:)), keyEquivalent: "u")
                    .keyEquivalentModifierMask = [.command, .option]
            }
            menu.addItem(.separator())
            menu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
                .keyEquivalentModifierMask = [.command, .control]
        }

        main.addSubmenu("History") { menu in
            menu.addItem(withTitle: "Back", action: #selector(BrowserWindowController.goBack(_:)), keyEquivalent: "[")
            menu.addItem(withTitle: "Forward", action: #selector(BrowserWindowController.goForward(_:)), keyEquivalent: "]")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Show All History", action: #selector(BrowserWindowController.showHistory(_:)), keyEquivalent: "y")
        }

        main.addSubmenu("Spaces") { menu in
            menu.addItem(withTitle: "Next Space", action: #selector(BrowserWindowController.nextSpace(_:)), keyEquivalent: String(UnicodeScalar(NSRightArrowFunctionKey)!))
                .keyEquivalentModifierMask = [.command, .option]
            menu.addItem(withTitle: "Previous Space", action: #selector(BrowserWindowController.previousSpace(_:)), keyEquivalent: String(UnicodeScalar(NSLeftArrowFunctionKey)!))
                .keyEquivalentModifierMask = [.command, .option]
            menu.addItem(.separator())
            for index in 0..<9 {
                let item = menu.addItem(withTitle: "Space \(index + 1)", action: #selector(BrowserWindowController.selectSpaceFromMenu(_:)), keyEquivalent: "\(index + 1)")
                item.keyEquivalentModifierMask = [.control]
                item.tag = index
            }
        }

        main.addSubmenu("Tabs") { menu in
            menu.addItem(withTitle: "Next Tab", action: #selector(BrowserWindowController.nextTab(_:)), keyEquivalent: String(UnicodeScalar(NSDownArrowFunctionKey)!))
                .keyEquivalentModifierMask = [.command, .option]
            menu.addItem(withTitle: "Previous Tab", action: #selector(BrowserWindowController.previousTab(_:)), keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!))
                .keyEquivalentModifierMask = [.command, .option]
            menu.addItem(withTitle: "Next Tab", action: #selector(BrowserWindowController.nextTab(_:)), keyEquivalent: "\t")
                .keyEquivalentModifierMask = [.control]
            menu.addItem(withTitle: "Previous Tab", action: #selector(BrowserWindowController.previousTab(_:)), keyEquivalent: "\t")
                .keyEquivalentModifierMask = [.control, .shift]
            menu.addHiddenAlternate("Next Tab", action: #selector(BrowserWindowController.nextTab(_:)), key: "]", modifiers: [.command, .shift])
            menu.addHiddenAlternate("Previous Tab", action: #selector(BrowserWindowController.previousTab(_:)), key: "[", modifiers: [.command, .shift])
            menu.addItem(.separator())
            menu.addItem(withTitle: "Pin/Unpin Tab", action: #selector(BrowserWindowController.togglePin(_:)), keyEquivalent: "d")
            menu.addItem(withTitle: "Clear Unpinned Tabs", action: #selector(BrowserWindowController.clearUnpinnedTabs(_:)), keyEquivalent: "k")
                .keyEquivalentModifierMask = [.command, .shift]
            menu.addItem(.separator())
            for index in 0..<9 {
                let item = menu.addItem(withTitle: index == 8 ? "Last Tab" : "Tab \(index + 1)", action: #selector(BrowserWindowController.selectTabFromMenu(_:)), keyEquivalent: "\(index + 1)")
                item.tag = index
            }
        }

        main.addSubmenu("Window") { menu in
            menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
            menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Downloads", action: #selector(BrowserWindowController.toggleDownloads(_:)), keyEquivalent: "j")
                .keyEquivalentModifierMask = [.command, .shift]
            menu.addItem(withTitle: "Extensions", action: #selector(BrowserWindowController.showExtensions(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Clear Browsing Data...", action: #selector(BrowserWindowController.clearBrowsingData(_:)), keyEquivalent: String(UnicodeScalar(NSBackspaceCharacter)!))
                .keyEquivalentModifierMask = [.command, .shift]
            NSApp.windowsMenu = menu
        }

        return main
    }
}

private extension NSMenu {
    func addSubmenu(_ title: String, build: (NSMenu) -> Void) {
        let menu = NSMenu(title: title)
        build(menu)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        addItem(item)
    }
}

private extension NSMenu {
    func addHiddenAlternate(_ title: String, action: Selector, key: String, modifiers: NSEvent.ModifierFlags) {
        let item = addItem(withTitle: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.isHidden = true
        item.allowsKeyEquivalentWhenHidden = true
    }
}

private extension NSMenuItem {
    func withKey(_ key: String) -> NSMenuItem {
        keyEquivalent = key
        return self
    }
}
