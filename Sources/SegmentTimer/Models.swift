import SwiftUI

enum TimerState: String, Codable {
    case running, paused, expired
}

/// Normaler Countdown oder eine Phase der Pomodoro-Runde.
enum TimerKind: String, Codable {
    case normal, pomodoro, shortBreak, longBreak

    var isPomodoroPhase: Bool { self != .normal }
    var isBreak: Bool { self == .shortBreak || self == .longBreak }
}

/// Zeitraum, in dem eine Tomate (oder Pause) tatsächlich lief.
struct TimeSegment: Codable, Equatable {
    var start: Date
    var end: Date
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct CountdownTimer: Identifiable, Codable, Equatable {
    var id = UUID()
    var label: String
    var colorIndex: Int
    /// Ursprüngliche Dauer – wird bei "Reset" / "Neu starten" verwendet.
    var duration: TimeInterval
    var state: TimerState
    /// Ablaufzeitpunkt (gültig bei .running und .expired).
    var endDate: Date
    /// Restzeit, solange der Timer pausiert ist.
    var pausedRemaining: TimeInterval = 0

    // Pomodoro
    var kind: TimerKind = .normal
    /// Nummer der Tomate im aktuellen Satz (1…n), bei Pausen die der vorangegangenen Tomate.
    var pomoIndex: Int = 1
    /// Bereits abgeschlossene Laufzeiten dieser Phase (unterbrochen durch Pausieren).
    var segments: [TimeSegment] = []
    /// Beginn der aktuell laufenden Strecke.
    var segmentStart: Date?

    func remaining(at now: Date) -> TimeInterval {
        switch state {
        case .running: return max(0, endDate.timeIntervalSince(now))
        case .paused: return pausedRemaining
        case .expired: return 0
        }
    }

    /// Angezeigte Sekunden (aufgerundet, damit 0 erst beim Ablauf erscheint).
    func displaySeconds(at now: Date) -> Int {
        Int(remaining(at: now).rounded(.up))
    }

    /// Doppelpunkt blinkt im Sekundentakt, solange der Timer läuft.
    func colonOn(at now: Date) -> Bool {
        guard state == .running else { return true }
        let r = remaining(at: now)
        return r - r.rounded(.down) >= 0.5
    }

    var color: Color {
        switch kind {
        case .normal: return TimerPalette.color(colorIndex)
        case .pomodoro: return TimerPalette.tomato
        case .shortBreak, .longBreak: return TimerPalette.pause
        }
    }

    /// Anzeigename, z.B. für Menüs.
    var title: String {
        switch kind {
        case .normal: return label.isEmpty ? "Timer" : label
        case .pomodoro: return "Tomate \(pomoIndex)" + (label.isEmpty ? "" : " – \(label)")
        case .shortBreak: return "Pause"
        case .longBreak: return "Lange Pause"
        }
    }

    /// Bisherige Laufzeit dieser Phase inkl. der gerade laufenden Strecke – für die Timeline.
    func liveSegments(at now: Date) -> [TimeSegment] {
        var result = segments
        if let s = segmentStart, now > s { result.append(TimeSegment(start: s, end: now)) }
        return result
    }
}

// Ältere gespeicherte Timer haben noch keine Pomodoro-Felder.
extension CountdownTimer {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        colorIndex = try c.decode(Int.self, forKey: .colorIndex)
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        state = try c.decode(TimerState.self, forKey: .state)
        endDate = try c.decode(Date.self, forKey: .endDate)
        pausedRemaining = try c.decodeIfPresent(TimeInterval.self, forKey: .pausedRemaining) ?? 0
        kind = try c.decodeIfPresent(TimerKind.self, forKey: .kind) ?? .normal
        pomoIndex = try c.decodeIfPresent(Int.self, forKey: .pomoIndex) ?? 1
        segments = try c.decodeIfPresent([TimeSegment].self, forKey: .segments) ?? []
        segmentStart = try c.decodeIfPresent(Date.self, forKey: .segmentStart)
    }
}

enum TimerPalette {
    static let colors: [Color] = [
        Color(red: 1.00, green: 0.20, blue: 0.84), // Magenta
        Color(red: 0.16, green: 0.84, blue: 1.00), // Cyan
        Color(red: 1.00, green: 0.80, blue: 0.18), // Gelb
        Color(red: 0.30, green: 1.00, blue: 0.45), // Grün
        Color(red: 0.68, green: 0.48, blue: 1.00), // Violett
    ]
    static let names = ["Magenta", "Cyan", "Gelb", "Grün", "Violett"]

    /// Feste Farben der Pomodoro-Runde
    static let tomato = Color(red: 1.00, green: 0.27, blue: 0.20)
    static let pause = Color(red: 0.55, green: 0.88, blue: 0.74)
    static let leaf = Color(red: 0.35, green: 0.80, blue: 0.35)

    static func color(_ index: Int) -> Color {
        colors[((index % colors.count) + colors.count) % colors.count]
    }
}

enum Format {
    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static func clock(_ date: Date) -> String {
        let s = clockFormatter.string(from: date)
        if Calendar.current.isDateInTomorrow(date) { return "morgen \(s)" }
        if !Calendar.current.isDateInToday(date) && date > Date() {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0
            return "+\(days) T \(s)"
        }
        return s
    }

    /// "1 h 30 min", "9 min", "45 s"
    static func duration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) h") }
        if m > 0 { parts.append("\(m) min") }
        if s > 0 || parts.isEmpty { parts.append("\(s) s") }
        return parts.joined(separator: " ")
    }

    /// Auf Minuten gerundet: "1 h 8 min", "25 min" – für Fokuszeiten.
    static func minutes(_ interval: TimeInterval) -> String {
        let total = Int((interval / 60).rounded())
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// "9:59" bzw. "1:05:30" – für die Menüleiste.
    static func compact(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
