import SwiftUI

// MARK: - Kleine Bausteine

/// Gezeichnete Tomate (Kreis + grüner Stiel).
struct TomatoIcon: View {
    var size: CGFloat
    var color: Color = TimerPalette.tomato
    var glow = false

    var body: some View {
        ZStack {
            Ellipse()
                .fill(color)
                .frame(width: size, height: size * 0.86)
                .offset(y: size * 0.07)
                .shadow(color: glow ? color.opacity(0.7) : .clear, radius: size * 0.2)
            Capsule()
                .fill(TimerPalette.leaf)
                .frame(width: size * 0.56, height: size * 0.16)
                .offset(y: -size * 0.32)
            Capsule()
                .fill(TimerPalette.leaf)
                .frame(width: size * 0.13, height: size * 0.3)
                .offset(y: -size * 0.42)
        }
        .frame(width: size, height: size)
    }
}

/// Kennzeichen vor dem Countdown: Siebensegment-"P" für eine Tomate, Tasse für die Pause.
struct PomoBadge: View {
    let kind: TimerKind
    let color: Color
    let height: CGFloat
    var dimmed = false

    var body: some View {
        if kind == .pomodoro {
            SevenSegmentDigit(digit: nil, color: color, height: height, pattern: SevenSegmentDigit.letterP)
                .opacity(dimmed ? 0.45 : 1)
        } else {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: height * 0.62, weight: .semibold))
                .foregroundColor(color.opacity(dimmed ? 0.45 : 1))
                .shadow(color: color.opacity(0.6), radius: max(1, height * 0.05))
                .frame(height: height)
        }
    }
}

/// ●●◐○ – Position im Satz von n Tomaten.
struct PomoDots: View {
    let index: Int
    let total: Int
    let kind: TimerKind
    let color: Color
    var size: CGFloat = 4

    var body: some View {
        let position = index
        HStack(spacing: size * 0.7) {
            ForEach(0..<max(1, min(total, 12)), id: \.self) { i in
                let done = i < index - 1 || (i == index - 1 && kind != .pomodoro)
                let current = i == index - 1 && kind == .pomodoro
                Circle()
                    .fill(done ? color : (current ? color.opacity(0.5) : color.opacity(0.18)))
                    .overlay(Circle().strokeBorder(color, lineWidth: current ? max(0.8, size * 0.2) : 0))
                    .frame(width: size, height: size)
            }
        }
        .help("Tomate \(position) von \(total) bis zur langen Pause")
    }
}

// MARK: - Timeline

/// Ein Tag als horizontaler Streifen: Tomaten als rote Blöcke, Pausen dezent.
struct DayTimeline: View {
    let records: [PomodoroRecord]
    let hours: ClosedRange<Double>
    var height: CGFloat = 14
    var nowMarker: Date? = nil
    var onDelete: ((PomodoroRecord) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.05))
                ForEach(Int(hours.lowerBound)...Int(hours.upperBound), id: \.self) { h in
                    Rectangle()
                        .fill(Color.white.opacity(h % 6 == 0 ? 0.16 : 0.07))
                        .frame(width: 1, height: height)
                        .offset(x: x(Double(h), w))
                }
                ForEach(records) { r in
                    ForEach(Array(r.segments.enumerated()), id: \.offset) { _, seg in
                        let x0 = x(Self.hour(of: seg.start), w)
                        let x1 = x(Self.hour(of: seg.end), w)
                        block(r)
                            .frame(width: max(2, x1 - x0), height: r.isWork ? height : height * 0.45)
                            .offset(x: x0, y: r.isWork ? 0 : height * 0.275)
                            .help(Self.tooltip(r, in: records))
                            .contextMenu {
                                if let onDelete { Button("Eintrag löschen") { onDelete(r) } }
                            }
                    }
                }
                if let nowMarker {
                    Rectangle()
                        .fill(Color.white.opacity(0.6))
                        .frame(width: 1, height: height)
                        .offset(x: x(Self.hour(of: nowMarker), w))
                }
            }
        }
        .frame(height: height)
    }

    @ViewBuilder private func block(_ r: PomodoroRecord) -> some View {
        let color = r.isWork ? TimerPalette.tomato : TimerPalette.pause
        RoundedRectangle(cornerRadius: 2)
            .fill(color.opacity(r.isWork ? (r.completed ? 0.95 : 0.4) : 0.45))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(color, lineWidth: r.isWork && !r.completed ? 1 : 0)
            )
    }

    private func x(_ hour: Double, _ width: CGFloat) -> CGFloat {
        let span = hours.upperBound - hours.lowerBound
        let clamped = min(max(hour, hours.lowerBound), hours.upperBound)
        return CGFloat((clamped - hours.lowerBound) / span) * width
    }

    static func hour(of date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
    }

    /// Sichtbarer Stundenbereich: mindestens 8–18 Uhr, erweitert auf alle Einträge.
    static func hourRange(_ records: [PomodoroRecord], including extra: Date? = nil) -> ClosedRange<Double> {
        var lo = 8.0, hi = 18.0
        let dates = records.flatMap { [$0.start, $0.end] } + (extra.map { [$0] } ?? [])
        for d in dates {
            lo = min(lo, floor(hour(of: d)))
            hi = max(hi, ceil(hour(of: d)))
        }
        return max(0, lo)...min(24, max(hi, lo + 1))
    }

    static func tooltip(_ r: PomodoroRecord, in dayRecords: [PomodoroRecord]) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let time = "\(f.string(from: r.start))–\(f.string(from: r.end))"
        let dur = Format.duration(r.activeDuration)
        let label = r.label.isEmpty ? "" : " · \(r.label)"
        switch r.kind {
        case .pomodoro:
            // n-te Tomate dieses Tages
            let number = dayRecords.filter { $0.isWork && $0.start <= r.start }.count
            return "Tomate \(number) · \(time) · \(dur)" + (r.completed ? "" : " (abgebrochen)") + label
        case .longBreak:
            return "Lange Pause · \(time) · \(dur)"
        default:
            return "Pause · \(time) · \(dur)"
        }
    }
}

/// Heutiger Verlauf in der Detailansicht der Tomate – inkl. der gerade laufenden Phase.
struct TodayPomodoroStrip: View {
    let current: CountdownTimer
    @EnvironmentObject var store: TimerStore
    @EnvironmentObject var log: PomodoroLog
    @EnvironmentObject var panels: PanelController

    var body: some View {
        let now = store.now
        var records = log.records(on: now)
        let live = current.liveSegments(at: now)
        if !live.isEmpty {
            records.append(PomodoroRecord(kind: current.kind, label: current.label, index: current.pomoIndex,
                                          planned: current.duration, segments: live, completed: true))
        }
        // Zählen nur, was schon im Protokoll steht; die laufende Tomate erhöht nur die Fokuszeit
        let logged = PomodoroLog.stats(log.records(on: now))
        let focus = logged.focus + (current.kind == .pomodoro ? live.reduce(0) { $0 + $1.duration } : 0)
        let range = DayTimeline.hourRange(records, including: now)

        return VStack(alignment: .leading, spacing: 5) {
            DayTimeline(records: records, hours: range, height: 10, nowMarker: now)
            HStack(spacing: 6) {
                Text("Heute: \(logged.tomatoes) \(logged.tomatoes == 1 ? "Tomate" : "Tomaten") · \(Format.minutes(focus)) Fokus")
                Spacer()
                Button("Verlauf …") { panels.openHistory() }
                    .buttonStyle(.plain)
                    .foregroundColor(current.color.opacity(0.9))
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundColor(current.color.opacity(0.6))
        }
    }
}

// MARK: - Dialog nach Ende einer Tomate / Pause

struct PomodoroPromptView: View {
    let window: () -> NSWindow?
    @EnvironmentObject var store: TimerStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var log: PomodoroLog

    var body: some View {
        if let t = store.pomoDue {
            content(t)
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }

    private func content(_ t: CountdownTimer) -> some View {
        let isWork = t.kind == .pomodoro
        let long = store.isLongBreakDue(after: t)
        let color = t.color
        let today = PomodoroLog.stats(log.records(on: store.now))
        let blinkOn = Int(store.now.timeIntervalSinceReferenceDate * 2) % 2 == 0
        let overdue = Int(store.now.timeIntervalSince(t.endDate))

        return VStack(spacing: 11) {
            HStack(spacing: 8) {
                if isWork {
                    TomatoIcon(size: 18, glow: true)
                } else {
                    Image(systemName: "cup.and.saucer.fill").font(.system(size: 15, weight: .semibold))
                }
                Text(isWork ? "Tomate \(store.tomatoNumberToday(t)) geschafft" : (t.kind == .longBreak ? "Lange Pause vorbei" : "Pause vorbei"))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .foregroundColor(color)

            if !t.label.isEmpty {
                Text(t.label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(color.opacity(0.75))
                    .lineLimit(1)
            }

            VStack(spacing: 5) {
                PomoDots(index: t.pomoIndex, total: settings.longBreakEvery, kind: isWork ? .shortBreak : t.kind,
                         color: TimerPalette.tomato, size: 7)
                Text(setInfo(t, long: long))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(TimerPalette.tomato.opacity(0.65))
            }

            Text("Heute \(today.tomatoes) \(today.tomatoes == 1 ? "Tomate" : "Tomaten") · \(Format.minutes(today.focus))"
                 + (overdue >= 5 ? " · seit \(Format.compact(overdue))" : ""))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundColor(color.opacity(0.6))

            HStack(spacing: 7) {
                if isWork {
                    PillButton(title: long ? "Lange Pause · \(settings.longBreakMinutes) min" : "Pause · \(settings.shortBreakMinutes) min",
                               color: TimerPalette.pause, filled: true, shortcut: .defaultAction) {
                        store.pomoStartBreak()
                    }
                    PillButton(title: "Nächste Tomate", color: TimerPalette.tomato) { store.pomoNextTomato() }
                } else {
                    PillButton(title: "Nächste Tomate", color: TimerPalette.tomato, filled: true, shortcut: .defaultAction) {
                        store.pomoNextTomato()
                    }
                }
                PillButton(title: "Beenden", color: .white.opacity(0.7)) { store.endPomodoroRound() }
            }
            .padding(.top, 3)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.04)))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(color.opacity(blinkOn ? 0.6 : 0.25), lineWidth: 1.5)
        )
        .dragsWindow(window)
    }
}

extension PomodoroPromptView {
    /// Stand im Satz bis zur langen Pause.
    fileprivate func setInfo(_ t: CountdownTimer, long: Bool) -> String {
        if t.kind == .longBreak { return "Neuer Satz – weiter geht's" }
        if long { return t.kind == .pomodoro ? "Zeit für die lange Pause" : "Lange Pause ausgelassen" }
        let left = store.tomatoesUntilLongBreak(after: t)
        return left == 1 ? "noch 1 Tomate bis zur langen Pause" : "noch \(left) Tomaten bis zur langen Pause"
    }
}

// MARK: - Verlaufsfenster

struct PomodoroHistoryView: View {
    @EnvironmentObject var log: PomodoroLog
    @EnvironmentObject var store: TimerStore

    var body: some View {
        let days = log.days
        let range = DayTimeline.hourRange(log.records)
        let cal = Calendar.current
        let today = PomodoroLog.stats(log.records(on: store.now))
        let weekStart = cal.dateInterval(of: .weekOfYear, for: store.now)?.start ?? store.now
        let week = PomodoroLog.stats(log.records.filter { $0.start >= weekStart })

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                HStack(spacing: 7) {
                    TomatoIcon(size: 16, glow: true)
                    Text("Pomodoro-Verlauf")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(TimerPalette.tomato)
                }
                Spacer()
                summary("Heute", today)
                summary("Diese Woche", week)
            }

            // Stundenachse
            HStack(spacing: 10) {
                Color.clear.frame(width: 78, height: 1)
                GeometryReader { geo in
                    ForEach(Int(range.lowerBound)...Int(range.upperBound), id: \.self) { h in
                        Text("\(h)")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.4))
                            .fixedSize()
                            .position(x: CGFloat((Double(h) - range.lowerBound) / (range.upperBound - range.lowerBound)) * geo.size.width,
                                      y: 6)
                    }
                }
                .frame(height: 12)
                Color.clear.frame(width: 96, height: 1)
            }

            ScrollView {
                HistoryDayRows(days: days, hours: range)
                    .padding(.vertical, 4)
            }

            Text("Volle Blöcke = fertige Tomaten · blasse Blöcke = abgebrochen · schmale grüne Balken = Pausen. Rechtsklick auf einen Block löscht ihn.")
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 280)
        .background(Color(white: 0.06))
    }

    private func summary(_ title: String, _ s: (tomatoes: Int, aborted: Int, focus: TimeInterval)) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(title).font(.system(size: 9, weight: .medium, design: .rounded)).foregroundColor(.white.opacity(0.4))
            Text("\(s.tomatoes) · \(Format.minutes(s.focus))")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(TimerPalette.tomato.opacity(0.9))
        }
    }
}

/// Eine Zeile pro Tag mit Timeline und Tagesbilanz.
struct HistoryDayRows: View {
    let days: [Date]
    let hours: ClosedRange<Double>
    @EnvironmentObject var log: PomodoroLog
    @EnvironmentObject var store: TimerStore

    var body: some View {
        let cal = Calendar.current
        LazyVStack(alignment: .leading, spacing: 9) {
            ForEach(days, id: \.self) { day in
                let records = log.records(on: day)
                let s = PomodoroLog.stats(records)
                HStack(spacing: 10) {
                    Text(dayTitle(day))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(cal.isDateInToday(day) ? 0.9 : 0.6))
                        .frame(width: 78, alignment: .leading)
                    DayTimeline(records: records, hours: hours, height: 16,
                                nowMarker: cal.isDateInToday(day) ? store.now : nil,
                                onDelete: { log.remove($0.id) })
                    HStack(spacing: 4) {
                        TomatoIcon(size: 9)
                        Text("\(s.tomatoes)" + (s.aborted > 0 ? " +\(s.aborted)" : ""))
                        Text("· \(Format.minutes(s.focus))").foregroundColor(.white.opacity(0.45))
                    }
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 96, alignment: .leading)
                    .help(s.aborted > 0 ? "\(s.tomatoes) fertig, \(s.aborted) abgebrochen" : "\(s.tomatoes) Tomaten")
                }
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Heute" }
        if cal.isDateInYesterday(day) { return "Gestern" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EE d. MMM"
        return f.string(from: day)
    }
}
