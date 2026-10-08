import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private lazy var store = TimerStore()
    private lazy var alarm = AlarmPlayer(settings: settings)
    private var panels: PanelController!
    private var statusItem: StatusItemController!
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panels = PanelController(store: store, settings: settings, alarm: alarm)
        panels.start()
        statusItem = StatusItemController(store: store, settings: settings, panels: panels)
        hotKey = HotKey(keyCode: kVK_ANSI_T, modifiers: cmdKey | optionKey) { [weak self] in
            self?.panels.showInput()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Erneutes Öffnen der App (z.B. Doppelklick im Finder) → Leiste zeigen
        settings.showBar = true
        return false
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--render-preview") {
    let dir = CommandLine.arguments.dropFirst(i + 1).first ?? "."
    MainActor.assumeIsolated { DebugRender.run(into: dir) }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
