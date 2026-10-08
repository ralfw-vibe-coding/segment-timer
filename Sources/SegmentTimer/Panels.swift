import AppKit
import SwiftUI
import Combine

/// Randloses, schwebendes Fenster, das auf allen Spaces sichtbar ist
/// und Tastatureingaben annehmen kann, ohne die App zu aktivieren.
final class FloatingPanel: NSPanel {
    var onCancel: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    /// Ohne sichtbares Menü fehlen Cmd-C/V/X/A/Z – hier nachgerüstet.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.shift) == .command,
           let key = event.charactersIgnoringModifiers?.lowercased() {
            let action: Selector?
            switch key {
            case "x": action = #selector(NSText.cut(_:))
            case "c": action = #selector(NSText.copy(_:))
            case "v": action = #selector(NSText.paste(_:))
            case "a": action = #selector(NSText.selectAll(_:))
            case "z": action = event.modifierFlags.contains(.shift) ? Selector(("redo:")) : Selector(("undo:"))
            default: action = nil
            }
            if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Größe ändern und dabei die untere linke bzw. rechte Ecke festhalten.
    func resize(to size: CGSize, anchorRight: Bool) {
        let size = CGSize(width: ceil(size.width), height: ceil(size.height))
        guard size.width > 0, size.height > 0, frame.size != size else { return }
        let x = anchorRight ? frame.maxX - size.width : frame.minX
        setFrame(NSRect(x: x, y: frame.minY, width: size.width, height: size.height), display: true)
        invalidateShadow()
    }
}

/// Hosting-View, der meldet, wenn sich die natürliche Größe des SwiftUI-Inhalts ändert.
final class PanelHostingView: NSHostingView<AnyView> {
    var onSizeChange: ((CGSize) -> Void)?
    private var lastSize: CGSize = .zero
    private var pending = false

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async { [weak self] in
            self?.pending = false
            self?.checkSize()
        }
    }

    func checkSize() {
        let size = intrinsicContentSize
        guard size.width >= 1, size.height >= 1, size.width < 5000, size != lastSize else { return }
        lastSize = size
        onSizeChange?(size)
    }
}

extension View {
    /// Fenster per Ziehen verschieben.
    func dragsWindow(_ window: @escaping () -> NSWindow?,
                     onChanged: (() -> Void)? = nil,
                     onEnded: (() -> Void)? = nil) -> some View {
        modifier(WindowDragModifier(window: window, changed: onChanged, ended: onEnded))
    }
}

private struct WindowDragModifier: ViewModifier {
    let window: () -> NSWindow?
    var changed: (() -> Void)?
    var ended: (() -> Void)?
    @State private var start: (mouse: NSPoint, origin: NSPoint)?

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { _ in
                    guard let w = window() else { return }
                    let mouse = NSEvent.mouseLocation
                    if start == nil { start = (mouse, w.frame.origin) }
                    guard let s = start else { return }
                    changed?()
                    w.setFrameOrigin(NSPoint(x: s.origin.x + mouse.x - s.mouse.x,
                                             y: s.origin.y + mouse.y - s.mouse.y))
                }
                .onEnded { _ in
                    let wasDragging = start != nil
                    start = nil
                    if wasDragging { ended?() }
                }
        )
    }
}

/// Verwaltet Leiste, Detailfenster, Alarmfenster und Einstellungen.
final class PanelController: ObservableObject {
    @Published private(set) var inputVisible = false
    @Published private(set) var openDetails: Set<UUID> = []

    let store: TimerStore
    let settings: AppSettings
    let alarm: AlarmPlayer

    private let barPanel = FloatingPanel()
    private var barSize = CGSize(width: 40, height: 40)
    private var barDragging = false
    private var detailPanels: [UUID: FloatingPanel] = [:]
    private var alarmPanel: FloatingPanel?
    private var pomoPanel: FloatingPanel?
    private var historyWindow: NSWindow?
    /// Ende der Pomodoro-Phase, für die zuletzt der Hinweiston kam
    private var lastPomoSignal: Date?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    init(store: TimerStore, settings: AppSettings, alarm: AlarmPlayer) {
        self.store = store
        self.settings = settings
        self.alarm = alarm
    }

    func start() {
        // Über dem Dock, damit die Leiste auch ganz unten am Rand sichtbar bleibt
        barPanel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        barPanel.contentView = makeHost(BarView()) { [weak self] size in
            self?.barSize = size
            self?.layoutBar()
        }
        barPanel.onCancel = { [weak self] in self?.hideInput() }

        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: barPanel, queue: .main) { [weak self] _ in
            self?.hideInput(restoreFocus: false)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.layoutBar()
        }

        // Sicherheitsnetz: Größen regelmäßig prüfen
        store.$now
            .sink { [weak self] _ in self?.hosts.forEach { $0.checkSize() } }
            .store(in: &cancellables)

        store.$timers
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncPanels() }
            .store(in: &cancellables)
        settings.$corner.combineLatest(settings.$showBar, settings.$barAnchor)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.layoutBar() }
            .store(in: &cancellables)

        layoutBar()
        syncPanels()
    }

    private var hosts: [PanelHostingView] = []

    private func makeHost<V: View>(_ view: V, onSizeChange: @escaping (CGSize) -> Void) -> PanelHostingView {
        let host = PanelHostingView(rootView: AnyView(
            view
                .fixedSize()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(store.log)
                .environmentObject(self)
        ))
        host.sizingOptions = [.intrinsicContentSize]
        host.onSizeChange = onSizeChange
        hosts.removeAll { $0.window == nil && $0 !== host }
        hosts.append(host)
        DispatchQueue.main.async { host.checkSize() }
        return host
    }

    private var screen: NSScreen? { NSScreen.screens.first }

    /// Bildschirm, auf dem die Leiste gerade liegt.
    private var barScreen: NSScreen? {
        let center = NSPoint(x: barPanel.frame.midX, y: barPanel.frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? screen
    }

    // MARK: - Leiste

    func layoutBar() {
        guard settings.showBar || inputVisible else {
            barPanel.orderOut(nil)
            return
        }
        guard !barDragging else { return }
        let margin: CGFloat = 8
        let w = ceil(barSize.width), h = ceil(barSize.height)
        var frame: NSRect
        let target: NSScreen?

        if let a = settings.barAnchor {
            frame = NSRect(x: a.right ? a.x - w : a.x, y: a.y, width: w, height: h)
            let probe = NSPoint(x: a.right ? a.x - 1 : a.x + 1, y: a.y + 1)
            target = NSScreen.screens.first { $0.frame.contains(probe) } ?? screen
        } else {
            target = screen
            let vf = target?.visibleFrame ?? .zero
            frame = NSRect(x: settings.corner == .bottomLeft ? vf.minX + margin : vf.maxX - margin - w,
                           y: vf.minY + margin, width: w, height: h)
        }
        // Immer vollständig auf dem Bildschirm halten (z.B. wenn die Eingabe aufklappt).
        // Frei verschoben darf die Leiste bis an den Rand – auch über das Dock.
        let bounds = settings.barAnchor != nil ? target?.frame : target?.visibleFrame
        if let vf = bounds {
            frame.origin.x = min(max(frame.minX, vf.minX), vf.maxX - w)
            frame.origin.y = min(max(frame.minY, vf.minY), vf.maxY - h)
        }
        barPanel.setFrame(frame, display: true)
        barPanel.invalidateShadow()
        barPanel.orderFrontRegardless()
    }

    var barWindow: NSWindow { barPanel }

    func barDragChanged() {
        barDragging = true
    }

    /// Nach dem Verschieben die Position merken. Verankert wird an der Kante,
    /// die näher am Bildschirmrand liegt – dorthin wächst die Leiste nicht.
    func barDragEnded() {
        barDragging = false
        let f = barPanel.frame
        let right = f.midX > (barScreen?.frame.midX ?? 0)
        settings.barAnchor = BarAnchor(x: Double(right ? f.maxX : f.minX), y: Double(f.minY), right: right)
    }

    func showInput() {
        guard store.canAdd else {
            NSSound.beep()
            return
        }
        inputVisible = true
        layoutBar()
        barPanel.makeKeyAndOrderFront(nil)
    }

    func hideInput(restoreFocus: Bool = true) {
        guard inputVisible else { return }
        inputVisible = false
        if restoreFocus && barPanel.isKeyWindow {
            // Fokus an die vorher aktive App zurückgeben
            barPanel.orderOut(nil)
        }
        layoutBar()
    }

    func toggleBar() {
        settings.showBar.toggle()
    }

    // MARK: - Detailfenster

    func toggleDetail(_ id: UUID) {
        if detailPanels[id] != nil { closeDetail(id) } else { openDetail(id) }
    }

    func openDetail(_ id: UUID) {
        if let existing = detailPanels[id] {
            existing.orderFrontRegardless()
            return
        }
        guard store.timer(id) != nil, let screen = barScreen else { return }
        let panel = FloatingPanel()
        let anchorRight = settings.barOnRight
        panel.onCancel = { [weak self] in self?.closeDetail(id) }

        panel.contentView = makeHost(DetailView(timerID: id, window: { [weak panel] in panel })) { [weak panel] size in
            panel?.resize(to: size, anchorRight: anchorRight)
        }

        // Über der Leiste bzw. über bereits offenen Detailfenstern stapeln
        let vf = screen.visibleFrame
        let bar = barPanel.isVisible ? barPanel.frame : NSRect(x: anchorRight ? vf.maxX - 8 : vf.minX + 8, y: vf.minY, width: 0, height: 0)
        let base = max(bar.maxY, detailPanels.values.map(\.frame.maxY).max() ?? 0)
        let w: CGFloat = 400, h: CGFloat = 200
        let y = min(base + 10, vf.maxY - h)
        let x = min(max(anchorRight ? bar.maxX - w : bar.minX, vf.minX), vf.maxX - w)
        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: false)
        panel.orderFrontRegardless()

        detailPanels[id] = panel
        openDetails.insert(id)
    }

    func closeDetail(_ id: UUID) {
        detailPanels.removeValue(forKey: id)?.orderOut(nil)
        openDetails.remove(id)
    }

    // MARK: - Alarm

    func syncPanels() {
        for id in detailPanels.keys {
            if let t = store.timer(id), t.state != .expired { continue }
            closeDetail(id)
        }

        if store.expired.isEmpty {
            alarm.stop()
            alarmPanel?.orderOut(nil)
            alarmPanel = nil
        } else {
            showAlarm()
            alarm.start()
        }

        if let due = store.pomoDue {
            showPomoPrompt()
            if lastPomoSignal != due.endDate {
                lastPomoSignal = due.endDate
                alarm.playShort()
            }
        } else {
            pomoPanel?.orderOut(nil)
            pomoPanel = nil
        }
    }

    /// Dialog nach Ende einer Tomate bzw. Pause – kleiner als der Alarm, ebenfalls mittig.
    private func showPomoPrompt() {
        if let pomoPanel {
            pomoPanel.orderFrontRegardless()
            return
        }
        let panel = FloatingPanel()
        panel.level = .statusBar
        panel.contentView = makeHost(PomodoroPromptView(window: { [weak panel] in panel })) { [weak self, weak panel] size in
            guard let self, let panel, let screen = self.screen else { return }
            let vf = screen.visibleFrame
            let w = ceil(size.width), h = ceil(size.height)
            var y = vf.midY - h / 2 + vf.height * 0.08
            if let alarm = self.alarmPanel { y = alarm.frame.minY - 12 - h }   // nicht überdecken
            panel.setFrame(NSRect(x: vf.midX - w / 2, y: max(vf.minY, y), width: w, height: h), display: true)
            panel.invalidateShadow()
        }
        if let screen {
            panel.setFrame(NSRect(x: screen.visibleFrame.midX - 170, y: screen.visibleFrame.midY - 80, width: 340, height: 160), display: false)
        }
        pomoPanel = panel
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    // MARK: - Pomodoro-Verlauf

    func openHistory() {
        if historyWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 420),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            w.title = "Pomodoro-Verlauf"
            w.isReleasedWhenClosed = false
            w.appearance = NSAppearance(named: .darkAqua)
            w.contentView = NSHostingView(rootView: PomodoroHistoryView()
                .environmentObject(store.log)
                .environmentObject(store))
            w.setContentSize(NSSize(width: 760, height: 420))
            w.center()
            historyWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        historyWindow?.makeKeyAndOrderFront(nil)
    }

    private func showAlarm() {
        if let alarmPanel {
            alarmPanel.orderFrontRegardless()
            return
        }
        let panel = FloatingPanel()
        panel.level = .statusBar
        panel.onCancel = { [weak self] in self?.store.removeAllExpired() }
        panel.contentView = makeHost(AlarmView(window: { [weak panel] in panel })) { [weak self, weak panel] size in
                guard let panel, let screen = self?.screen else { return }
                let vf = screen.visibleFrame
                let w = ceil(size.width), h = ceil(size.height)
                panel.setFrame(NSRect(x: vf.midX - w / 2, y: vf.midY - h / 2 + vf.height * 0.08, width: w, height: h), display: true)
                panel.invalidateShadow()
        }
        if let screen {
            panel.setFrame(NSRect(x: screen.visibleFrame.midX - 200, y: screen.visibleFrame.midY - 150, width: 400, height: 300), display: false)
        }
        alarmPanel = panel
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    // MARK: - Einstellungen

    func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "Segment Timer – Einstellungen"
            w.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: SettingsView(alarm: alarm).environmentObject(settings))
            w.contentView = host
            w.setContentSize(host.fittingSize)
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
