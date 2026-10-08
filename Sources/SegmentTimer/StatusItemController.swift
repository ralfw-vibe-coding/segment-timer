import AppKit
import SwiftUI

/// Symbol in der Menüleiste mit einem Menü (Neuer Timer, Timer-Liste, Einstellungen, Beenden).
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store: TimerStore
    private let settings: AppSettings
    private let panels: PanelController

    init(store: TimerStore, settings: AppSettings, panels: PanelController) {
        self.store = store
        self.settings = settings
        self.panels = panels
        super.init()

        if let button = item.button {
            let image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Segment Timer")
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let add = NSMenuItem(title: "Neuer Timer …", action: #selector(newTimer), keyEquivalent: "t")
        add.keyEquivalentModifierMask = [.command, .option]
        add.target = self
        add.isEnabled = store.canAdd
        menu.addItem(add)

        let timers = store.expired + store.activeSorted
        if !timers.isEmpty {
            menu.addItem(.separator())
            for t in timers {
                let time = t.state == .expired ? "abgelaufen" : Format.compact(t.displaySeconds(at: store.now))
                let name = t.label.isEmpty ? "Timer" : t.label
                let entry = NSMenuItem(title: "\(name) – \(time)\(t.state == .paused ? " (Pause)" : "")",
                                       action: #selector(openTimer(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = t.id
                entry.image = Self.dot(NSColor(t.color))
                menu.addItem(entry)
            }
        }

        menu.addItem(.separator())
        let bar = NSMenuItem(title: "Leiste anzeigen", action: #selector(toggleBar), keyEquivalent: "")
        bar.target = self
        bar.state = settings.showBar ? .on : .off
        menu.addItem(bar)

        let prefs = NSMenuItem(title: "Einstellungen …", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Segment Timer beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private static func dot(_ color: NSColor) -> NSImage {
        let img = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        return img
    }

    @objc private func newTimer() {
        // Menü erst schließen lassen, dann Eingabe öffnen
        DispatchQueue.main.async { self.panels.showInput() }
    }

    @objc private func openTimer(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        if store.timer(id)?.state != .expired { panels.openDetail(id) }
    }

    @objc private func toggleBar() { panels.toggleBar() }

    @objc private func openSettings() { panels.openSettings() }
}
