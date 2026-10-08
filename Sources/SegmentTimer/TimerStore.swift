import Foundation
import Combine

final class TimerStore: ObservableObject {
    static let maxTimers = 5
    private static let defaultsKey = "timers.v1"

    @Published private(set) var timers: [CountdownTimer] = [] {
        didSet { save() }
    }
    /// Wird ca. 4× pro Sekunde aktualisiert und treibt alle Anzeigen.
    @Published private(set) var now = Date()

    private var ticker: Timer?

    /// Nur für Vorschau-Renderings (--render-preview): feste Timer, kein Speichern.
    private var persist = true
    init(preview: [CountdownTimer], now: Date) {
        persist = false
        timers = preview
        self.now = now
    }

    init() {
        load()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
        tick()
    }

    // MARK: - Abfragen

    /// Laufende (nach Ablaufzeit) und pausierte Timer – ohne abgelaufene.
    var activeSorted: [CountdownTimer] {
        let running = timers.filter { $0.state == .running }.sorted { $0.endDate < $1.endDate }
        let paused = timers.filter { $0.state == .paused }.sorted { $0.pausedRemaining < $1.pausedRemaining }
        return running + paused
    }

    var expired: [CountdownTimer] {
        timers.filter { $0.state == .expired }.sorted { $0.endDate < $1.endDate }
    }

    var nextTimer: CountdownTimer? { activeSorted.first }

    var canAdd: Bool { timers.count < Self.maxTimers }

    var usedColors: Set<Int> { Set(timers.map(\.colorIndex)) }

    func nextFreeColor() -> Int {
        (0..<TimerPalette.colors.count).first { !usedColors.contains($0) } ?? 0
    }

    func timer(_ id: UUID) -> CountdownTimer? {
        timers.first { $0.id == id }
    }

    // MARK: - Aktionen

    @discardableResult
    func add(_ parsed: ParsedTimer, colorIndex: Int? = nil) -> Bool {
        guard canAdd else { return false }
        let color = colorIndex.flatMap { usedColors.contains($0) ? nil : $0 } ?? nextFreeColor()
        timers.append(CountdownTimer(
            label: parsed.label,
            colorIndex: color,
            duration: parsed.duration,
            state: .running,
            endDate: parsed.endDate
        ))
        return true
    }

    func togglePause(_ id: UUID) {
        let now = Date()
        mutate(id) { t in
            switch t.state {
            case .running:
                t.pausedRemaining = t.remaining(at: now)
                t.state = .paused
            case .paused:
                t.endDate = now.addingTimeInterval(t.pausedRemaining)
                t.state = .running
            case .expired:
                break
            }
        }
    }

    /// Zurück auf die ursprüngliche Dauer. Ein pausierter Timer bleibt pausiert.
    func reset(_ id: UUID) {
        let now = Date()
        mutate(id) { t in
            if t.state == .paused {
                t.pausedRemaining = t.duration
            } else {
                t.state = .running
                t.endDate = now.addingTimeInterval(t.duration)
            }
        }
    }

    func restart(_ id: UUID) {
        let now = Date()
        mutate(id) { t in
            t.state = .running
            t.endDate = now.addingTimeInterval(t.duration)
        }
    }

    func snooze(_ id: UUID, minutes: Double) {
        let now = Date()
        mutate(id) { t in
            t.state = .running
            t.endDate = now.addingTimeInterval(minutes * 60)
        }
    }

    func setColor(_ id: UUID, to index: Int) {
        guard let i = timers.firstIndex(where: { $0.id == id }) else { return }
        var copy = timers
        if let other = copy.firstIndex(where: { $0.colorIndex == index && $0.id != id }) {
            copy[other].colorIndex = copy[i].colorIndex   // Farben tauschen
        }
        copy[i].colorIndex = index
        timers = copy
    }

    func remove(_ id: UUID) {
        timers.removeAll { $0.id == id }
    }

    func removeAllExpired() {
        timers.removeAll { $0.state == .expired }
    }

    // MARK: - Intern

    private func mutate(_ id: UUID, _ change: (inout CountdownTimer) -> Void) {
        guard let i = timers.firstIndex(where: { $0.id == id }) else { return }
        var copy = timers[i]
        change(&copy)
        timers[i] = copy
    }

    private func tick() {
        let current = Date()
        now = current
        if timers.contains(where: { $0.state == .running && $0.endDate <= current }) {
            timers = timers.map { t in
                var t = t
                if t.state == .running && t.endDate <= current { t.state = .expired }
                return t
            }
        }
    }

    private func save() {
        guard persist else { return }
        if let data = try? JSONEncoder().encode(timers) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let saved = try? JSONDecoder().decode([CountdownTimer].self, from: data) else { return }
        timers = Array(saved.prefix(Self.maxTimers))
    }
}
