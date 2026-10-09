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

    let settings: AppSettings
    let log: PomodoroLog
    private var ticker: Timer?

    /// Nur für Vorschau-Renderings (--render-preview): feste Timer, kein Speichern.
    private var persist = true
    init(preview: [CountdownTimer], now: Date, settings: AppSettings, log: PomodoroLog) {
        self.settings = settings
        self.log = log
        persist = false
        timers = preview
        self.now = now
    }

    init(settings: AppSettings, log: PomodoroLog) {
        self.settings = settings
        self.log = log
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

    /// Abgelaufene normale Timer (→ Alarmfenster). Tomaten haben ihren eigenen Dialog.
    var expired: [CountdownTimer] {
        timers.filter { $0.state == .expired && $0.kind == .normal }.sorted { $0.endDate < $1.endDate }
    }

    /// Die (einzige) Tomate bzw. Pause der laufenden Pomodoro-Runde.
    var pomodoro: CountdownTimer? { timers.first { $0.kind.isPomodoroPhase } }

    /// Tomate oder Pause ist abgelaufen und wartet auf die Entscheidung, wie es weitergeht.
    var pomoDue: CountdownTimer? { pomodoro.flatMap { $0.state == .expired ? $0 : nil } }

    var canStartPomodoro: Bool { pomodoro == nil && canAdd }

    var nextTimer: CountdownTimer? { activeSorted.first }

    var canAdd: Bool { timers.count < Self.maxTimers }

    var usedColors: Set<Int> { Set(timers.filter { $0.kind == .normal }.map(\.colorIndex)) }

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
                if let s = t.segmentStart {
                    t.segments.append(TimeSegment(start: s, end: now))
                    t.segmentStart = nil
                }
            case .paused:
                t.endDate = now.addingTimeInterval(t.pausedRemaining)
                t.state = .running
                if t.kind.isPomodoroPhase { t.segmentStart = now }
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

    /// Label ändern. Bei einer Tomate gilt es für die laufende und alle weiteren Tomaten der Runde.
    func setLabel(_ id: UUID, _ label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        mutate(id) { $0.label = trimmed }
    }

    func remove(_ id: UUID) {
        timers.removeAll { $0.id == id }
    }

    func removeAllExpired() {
        timers.removeAll { $0.state == .expired && $0.kind == .normal }
    }

    // MARK: - Pomodoro

    @discardableResult
    func startPomodoro(label: String = "") -> Bool {
        guard canStartPomodoro else { return false }
        var t = CountdownTimer(label: label, colorIndex: -1, duration: 0, state: .running, endDate: Date())
        t.kind = .pomodoro
        beginPhase(&t, kind: .pomodoro, index: 1)
        timers.append(t)
        return true
    }

    /// Nach einer Tomate: kurze bzw. (jede n-te) lange Pause.
    func pomoStartBreak() {
        guard let id = pomodoro?.id else { return }
        mutate(id) { t in
            let long = t.pomoIndex % self.settings.longBreakEvery == 0
            self.beginPhase(&t, kind: long ? .longBreak : .shortBreak, index: t.pomoIndex)
        }
    }

    /// Nächste Tomate – nach einer Tomate, nach einer Pause oder als "Pause überspringen".
    func pomoNextTomato() {
        guard let id = pomodoro?.id else { return }
        let now = Date()
        mutate(id) { t in
            if t.kind.isBreak && t.state != .expired {
                self.logPhase(&t, end: now, completed: false)   // Pause übersprungen
            }
            let next = t.pomoIndex % self.settings.longBreakEvery + 1
            self.beginPhase(&t, kind: .pomodoro, index: next)
        }
    }

    /// Runde beenden. Eine laufende Tomate zählt mit ihrer bisherigen Zeit als abgebrochen;
    /// die nächste Runde beginnt wieder mit Tomate 1.
    func endPomodoroRound() {
        guard var t = pomodoro else { return }
        if t.state != .expired { logPhase(&t, end: Date(), completed: false) }
        remove(t.id)
    }

    /// Laufende Nummer der Tomate am heutigen Tag (fertige Tomaten heute + die laufende).
    /// Unabhängig vom Satz bis zur langen Pause – es gibt keine Obergrenze.
    func tomatoNumberToday(_ t: CountdownTimer) -> Int {
        let done = PomodoroLog.stats(log.records(on: now)).tomatoes
        return done + (t.kind == .pomodoro && t.state != .expired ? 1 : 0)
    }

    /// Wie viele Tomaten noch bis zur langen Pause – nach der Tomate mit Satzposition `t.pomoIndex`.
    func tomatoesUntilLongBreak(after t: CountdownTimer) -> Int {
        settings.longBreakEvery - t.pomoIndex
    }

    /// Deckel zu = wie manuelles Abbrechen: eine laufende Tomate zählt bis jetzt und beendet
    /// die Runde, alle Timer werden gestoppt (auch klingelnde).
    func stopAllForLidClose() {
        if pomodoro != nil { endPomodoroRound() }
        if !timers.isEmpty { timers.removeAll() }
    }

    /// Wird die lange Pause nach dieser Tomate fällig?
    func isLongBreakDue(after t: CountdownTimer) -> Bool {
        t.pomoIndex % settings.longBreakEvery == 0
    }

    private func beginPhase(_ t: inout CountdownTimer, kind: TimerKind, index: Int) {
        let now = Date()
        let minutes: Int
        switch kind {
        case .pomodoro: minutes = settings.pomoMinutes
        case .longBreak: minutes = settings.longBreakMinutes
        default: minutes = settings.shortBreakMinutes
        }
        t.kind = kind
        t.pomoIndex = index
        t.duration = TimeInterval(max(1, minutes) * 60)
        t.state = .running
        t.endDate = now.addingTimeInterval(t.duration)
        t.pausedRemaining = 0
        t.segments = []
        t.segmentStart = now
    }

    /// Phase ins Protokoll schreiben (bis `end`) und Laufzeiten zurücksetzen.
    private func logPhase(_ t: inout CountdownTimer, end: Date, completed: Bool) {
        var segs = t.segments
        if let s = t.segmentStart, end > s { segs.append(TimeSegment(start: s, end: end)) }
        t.segments = []
        t.segmentStart = nil
        guard !segs.isEmpty else { return }
        log.append(PomodoroRecord(kind: t.kind, label: t.label, index: t.pomoIndex,
                                  planned: t.duration, segments: segs, completed: completed))
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
        guard timers.contains(where: { $0.state == .running && $0.endDate <= current }) else { return }
        var copy = timers
        for i in copy.indices where copy[i].state == .running && copy[i].endDate <= current {
            copy[i].state = .expired
            if copy[i].kind.isPomodoroPhase {
                logPhase(&copy[i], end: copy[i].endDate, completed: true)
            }
        }
        timers = copy
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
