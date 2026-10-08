import SwiftUI

/// Großes Fenster, wenn ein oder mehrere Timer abgelaufen sind.
struct AlarmView: View {
    let window: () -> NSWindow?
    @EnvironmentObject var store: TimerStore

    var body: some View {
        let expired = store.expired
        let now = store.now
        let blinkOn = Int(now.timeIntervalSinceReferenceDate * 2) % 2 == 0
        let accent = expired.first?.color ?? .white

        VStack(spacing: 26) {
            ForEach(expired) { t in
                AlarmRow(timer: t, now: now, blinkOn: blinkOn, showStop: expired.count > 1)
            }

            Button {
                store.removeAllExpired()
            } label: {
                Text(expired.count > 1 ? "Alle stoppen" : "Stopp")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(minWidth: 220)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(accent))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .help("Alarm stoppen (Enter oder Esc)")
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 34)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.black.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(accent.opacity(blinkOn ? 0.9 : 0.25), lineWidth: 3)
        )
        .dragsWindow(window)
    }
}

private struct AlarmRow: View {
    let timer: CountdownTimer
    let now: Date
    let blinkOn: Bool
    let showStop: Bool
    @EnvironmentObject var store: TimerStore

    var body: some View {
        let overdue = Int(now.timeIntervalSince(timer.endDate))

        VStack(spacing: 14) {
            Text(timer.label.isEmpty ? "Timer abgelaufen" : timer.label)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(timer.color)
                .lineLimit(1)

            SegmentClock(seconds: 0, color: timer.color, height: showStop ? 80 : 130, colonOn: true, digitsOn: blinkOn)

            Text("abgelaufen um \(Format.clock(timer.endDate))" + (overdue >= 5 ? " · vor \(Format.compact(overdue))" : ""))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundColor(timer.color.opacity(0.7))

            HStack(spacing: 10) {
                PillButton(title: "+1 min", color: timer.color) { store.snooze(timer.id, minutes: 1) }
                PillButton(title: "+5 min", color: timer.color) { store.snooze(timer.id, minutes: 5) }
                PillButton(title: "↻ \(Format.duration(timer.duration))", color: timer.color) { store.restart(timer.id) }
                if showStop {
                    PillButton(title: "Stopp", color: timer.color, filled: true) { store.remove(timer.id) }
                }
            }
        }
    }
}

private struct PillButton: View {
    let title: String
    let color: Color
    var filled = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(filled ? .black : color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(filled ? color : color.opacity(hovering ? 0.25 : 0.12))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
