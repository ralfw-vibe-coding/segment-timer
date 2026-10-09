import AppKit
import IOKit

/// Meldet das Zuklappen des Deckels – auch wenn der Mac dabei nicht einschläft
/// (z.B. mit externem Monitor). Hält den Rechner selbst nie wach.
final class LidWatcher {
    private let onClose: () -> Void
    private var wasClosed = LidWatcher.isLidClosed
    private var timer: Timer?

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose

        // Zuklappen löst meist sofort den Ruhezustand aus – vorher noch reagieren
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.check() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.wasClosed = LidWatcher.isLidClosed }

        // Zuklappen ohne Ruhezustand
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.check() }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func check() {
        let closed = LidWatcher.isLidClosed
        if closed && !wasClosed { onClose() }
        wasClosed = closed
    }

    static var isLidClosed: Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return (value as? Bool) ?? false
    }
}
