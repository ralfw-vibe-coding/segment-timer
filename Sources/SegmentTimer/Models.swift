import SwiftUI

enum TimerState: String, Codable {
    case running, paused, expired
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

    var color: Color { TimerPalette.color(colorIndex) }
}

enum TimerPalette {
    static let colors: [Color] = [
        Color(red: 1.00, green: 0.20, blue: 0.84), // Magenta
        Color(red: 0.16, green: 0.84, blue: 1.00), // Cyan
        Color(red: 1.00, green: 0.80, blue: 0.18), // Gelb
        Color(red: 0.30, green: 1.00, blue: 0.45), // Grün
        Color(red: 1.00, green: 0.42, blue: 0.20), // Orange
    ]
    static let names = ["Magenta", "Cyan", "Gelb", "Grün", "Orange"]

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

    /// "9:59" bzw. "1:05:30" – für die Menüleiste.
    static func compact(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
