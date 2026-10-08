import Foundation

struct ParsedTimer: Equatable {
    let duration: TimeInterval
    let endDate: Date
    let isClockTime: Bool
    let label: String
    /// "pomo" / "pomodoro" / "p" – Dauer kommt dann aus den Einstellungen.
    var isPomodoro = false
}

/// Versteht Eingaben wie:
///   9 · 9min · 90s · 1h 30 · 1:30h · 1,5h · 2:30min · 1:30:00   → Dauer
///   12:30 · 14:45 · um 9 · 18 Uhr · 12.30                        → Ablaufzeit
/// Zahlen ohne Einheit sind Minuten. Text vor oder nach der Zeitangabe wird zum Label:
///   "9 Tee", "1:30h Backofen", "Meeting 14:45"
enum TimeParser {
    static let maxDuration: TimeInterval = 100 * 3600

    static func parse(_ input: String, now: Date = Date()) -> ParsedTimer? {
        let tokens = input.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return nil }

        // Tomate: "pomo", "pomo Kapitel 3", "Kapitel 3 pomo"
        let pomoWords: Set<String> = ["p", "pomo", "pomodoro", "tomate"]
        if pomoWords.contains(tokens[0].lowercased()) {
            return ParsedTimer(duration: 0, endDate: now, isClockTime: false,
                               label: tokens.dropFirst().joined(separator: " "), isPomodoro: true)
        }
        if tokens.count > 1, pomoWords.contains(tokens[tokens.count - 1].lowercased()) {
            return ParsedTimer(duration: 0, endDate: now, isClockTime: false,
                               label: tokens.dropLast().joined(separator: " "), isPomodoro: true)
        }

        // Zeitangabe vorne, Rest ist Label (längster passender Präfix gewinnt)
        for k in stride(from: tokens.count, through: 1, by: -1) {
            let spec = tokens[0..<k].joined(separator: " ")
            if let result = parseSpec(spec, now: now) {
                return make(result, label: tokens[k...].joined(separator: " "), now: now)
            }
        }
        // Label vorne, Zeitangabe hinten
        for k in 1..<tokens.count {
            let spec = tokens[k...].joined(separator: " ")
            if let result = parseSpec(spec, now: now) {
                return make(result, label: tokens[0..<k].joined(separator: " "), now: now)
            }
        }
        return nil
    }

    private enum Spec {
        case duration(TimeInterval)
        case clock(hour: Int, minute: Int)
    }

    private static func make(_ spec: Spec, label: String, now: Date) -> ParsedTimer? {
        switch spec {
        case .duration(let d):
            guard d > 0, d <= maxDuration else { return nil }
            return ParsedTimer(duration: d, endDate: now.addingTimeInterval(d), isClockTime: false, label: label)
        case .clock(let hour, let minute):
            let cal = Calendar.current
            guard var end = cal.date(bySettingHour: hour % 24, minute: minute, second: 0, of: now) else { return nil }
            if end <= now { end = cal.date(byAdding: .day, value: 1, to: end) ?? end.addingTimeInterval(86400) }
            return ParsedTimer(duration: end.timeIntervalSince(now), endDate: end, isClockTime: true, label: label)
        }
    }

    private static func parseSpec(_ raw: String, now: Date) -> Spec? {
        var s = raw.lowercased().trimmingCharacters(in: .whitespaces)

        // --- Uhrzeit ---
        var forcedClock = false
        for prefix in ["um ", "bis ", "@"] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            forcedClock = true
        }
        if s.hasSuffix("uhr") {
            s = String(s.dropLast(3)).trimmingCharacters(in: .whitespaces)
            forcedClock = true
        }
        // 14:45 / 12.30 (Punkt = Uhrzeit, Komma = Dezimalzahl)
        if let m = match(#"^(\d{1,2})[:.](\d{2})$"#, s),
           let h = Int(m[0]), let min = Int(m[1]), h <= 24, min < 60, !(h == 24 && min > 0) {
            return .clock(hour: h, minute: min)
        }
        if forcedClock {
            if let m = match(#"^(\d{1,2})$"#, s), let h = Int(m[0]), h <= 24 {
                return .clock(hour: h, minute: 0)
            }
            return nil
        }

        // --- Dauer ---
        s = s.replacingOccurrences(of: ",", with: ".")
        // 1:30:00 → h:m:s
        if let m = match(#"^(\d+):(\d{1,2}):(\d{2})$"#, s),
           let h = Double(m[0]), let min = Double(m[1]), let sec = Double(m[2]) {
            return .duration(h * 3600 + min * 60 + sec)
        }
        // 1:30h → h:m
        if let m = match(#"^(\d+):(\d{2})\s*([a-z]+)$"#, s), let a = Double(m[0]), let b = Double(m[1]) {
            switch unitFactor(m[2]) {
            case 3600: return .duration(a * 3600 + b * 60)
            case 60: return .duration(a * 60 + b)
            default: return nil
            }
        }
        return parseUnits(s).map(Spec.duration)
    }

    /// "1h 30m", "1h30", "90 s", "1.5h", "9", "2 std 15 min"
    private static func parseUnits(_ s: String) -> TimeInterval? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*([a-zäöü]*)"#) else { return nil }
        let ns = s as NSString
        let matches = regex.matches(in: s, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return nil }

        var total: TimeInterval = 0
        var lastFactor: Double?
        var cursor = 0
        for match in matches {
            // zwischen den Teilen darf nur Leerraum stehen
            let gap = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            guard gap.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            cursor = match.range.location + match.range.length

            guard let value = Double(ns.substring(with: match.range(at: 1))) else { return nil }
            let unit = ns.substring(with: match.range(at: 2))
            let factor: Double
            if unit.isEmpty {
                switch lastFactor {
                case nil: factor = 60          // Standard: Minuten
                case 3600: factor = 60         // "1h 30" → 30 min
                case 60: factor = 1            // "5m 30" → 30 s
                default: return nil
                }
            } else if let f = unitFactor(unit) {
                factor = f
            } else {
                return nil
            }
            total += value * factor
            lastFactor = factor
        }
        guard ns.substring(from: cursor).trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return total > 0 ? total : nil
    }

    private static func unitFactor(_ unit: String) -> Double? {
        switch unit {
        case "h", "hr", "hrs", "std", "stdn", "stunde", "stunden", "hour", "hours": return 3600
        case "m", "min", "mins", "minute", "minuten", "minutes": return 60
        case "s", "sek", "sec", "secs", "sekunde", "sekunden", "second", "seconds": return 1
        default: return nil
        }
    }

    private static func match(_ pattern: String, _ s: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }
}
