import SwiftUI

/// Großansicht eines Timers: Countdown, Ablaufzeit, Reset / Pause / Löschen.
struct DetailView: View {
    let timerID: UUID
    let window: () -> NSWindow?
    @EnvironmentObject var store: TimerStore
    @EnvironmentObject var panels: PanelController

    var body: some View {
        if let t = store.timer(timerID) {
            content(t)
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }

    private func content(_ t: CountdownTimer) -> some View {
        let now = store.now
        let paused = t.state == .paused

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(t.label.isEmpty ? "Timer" : t.label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(t.color.opacity(0.9))
                    .lineLimit(1)
                Spacer(minLength: 20)
                Button { panels.closeDetail(timerID) } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.45))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Verkleinern (Esc)")
            }

            SegmentClock(
                seconds: t.displaySeconds(at: now),
                color: t.color,
                height: 96,
                colonOn: t.colonOn(at: now)
            )
            .opacity(paused ? 0.5 : 1)
            .padding(.horizontal, 4)

            HStack(alignment: .center) {
                Text(paused ? "Pause" : Format.clock(t.endDate))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(t.color)
                    .help(paused ? "Pausiert" : "Ablaufzeit")
                Spacer(minLength: 24)
                HStack(spacing: 10) {
                    SquareButton(symbol: "arrow.counterclockwise", color: t.color, help: "Zurücksetzen auf \(Format.duration(t.duration))") {
                        store.reset(timerID)
                    }
                    SquareButton(symbol: paused ? "play.fill" : "pause.fill", color: t.color, help: paused ? "Fortsetzen" : "Pause") {
                        store.togglePause(timerID)
                    }
                    SquareButton(symbol: "xmark", color: t.color, help: "Timer stoppen und löschen") {
                        store.remove(timerID)
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(t.color.opacity(0.18), lineWidth: 1)
        )
        .dragsWindow(window)
        .contextMenu { TimerMenu(timer: t) }
    }
}

struct SquareButton: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 26
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.48, weight: .heavy))
                .foregroundColor(.black)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.24).fill(color.opacity(hovering ? 1 : 0.85)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
