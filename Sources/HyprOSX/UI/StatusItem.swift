import AppKit

struct StatusWorkspace {
    var id: Int
    var name: String
    var active: Bool
}

struct StatusState {
    var title = "HyprOSX"
    var trusted = true
    var paused = false
    var workspaces: [StatusWorkspace] = []
    var errors: [String] = []
}

final class StatusItem: NSObject, NSMenuDelegate {
    private static let shownErrors = 5
    private static let errorWidth = 120

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var state: () -> StatusState = { StatusState() }
    var onWorkspace: (Int) -> Void = { _ in }
    var onReload: () -> Void = {}
    var onOpenConfigFolder: () -> Void = {}
    var onTogglePause: () -> Void = {}
    var onGrantAccessibility: () -> Void = {}

    override init() {
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        update()
    }

    func update() {
        let s = state()
        let font = NSFont.menuBarFont(ofSize: 0)
        let title = NSMutableAttributedString(string: s.trusted ? s.title : "HyprOSX ⚠︎", attributes: [.font: font])
        if !s.errors.isEmpty {
            title.append(NSAttributedString(string: " ●", attributes: [.font: font, .foregroundColor: NSColor.systemRed]))
        }
        item.button?.attributedTitle = title
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let s = state()
        menu.removeAllItems()
        if !s.trusted {
            menu.addItem(entry("Grant Accessibility Access…", #selector(grant)))
            menu.addItem(.separator())
        }
        for ws in s.workspaces {
            let item = entry("Workspace \(ws.name)", #selector(pickWorkspace(_:)))
            item.tag = ws.id
            item.state = ws.active ? .on : .off
            menu.addItem(item)
        }
        if !s.workspaces.isEmpty { menu.addItem(.separator()) }
        for error in s.errors.prefix(Self.shownErrors) {
            menu.addItem(NSMenuItem(title: Self.oneLine(error), action: nil, keyEquivalent: ""))
        }
        if s.errors.count > Self.shownErrors {
            menu.addItem(NSMenuItem(title: "and \(s.errors.count - Self.shownErrors) more: hyprctl configerrors", action: nil, keyEquivalent: ""))
        }
        if !s.errors.isEmpty { menu.addItem(.separator()) }
        menu.addItem(entry("Reload Config", #selector(reload)))
        menu.addItem(entry("Open Config Folder", #selector(openFolder)))
        menu.addItem(entry(s.paused ? "Resume HyprOSX" : "Pause HyprOSX", #selector(togglePause)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit HyprOSX", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private static func oneLine(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        return flat.count > errorWidth ? String(flat.prefix(errorWidth)) + "…" : flat
    }

    private func entry(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func pickWorkspace(_ sender: NSMenuItem) { onWorkspace(sender.tag) }
    @objc private func reload() { onReload() }
    @objc private func openFolder() { onOpenConfigFolder() }
    @objc private func togglePause() { onTogglePause() }
    @objc private func grant() { onGrantAccessibility() }
}
