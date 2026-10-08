import SwiftUI

/// Die kleine Leiste am unteren Bildschirmrand.
struct BarView: View {
    @EnvironmentObject var store: TimerStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var panels: PanelController
    @State private var hovering = false

    var body: some View {
        let timers = store.activeSorted
        let alignment: HorizontalAlignment = settings.barOnRight ? .trailing : .leading

        VStack(alignment: alignment, spacing: 8) {
            if panels.inputVisible {
                NewTimerInput()
            }
            HStack(alignment: .center, spacing: 12) {
                ForEach(timers) { t in
                    TimerChip(timer: t, isNext: t.id == timers.first?.id)
                }
                if !panels.inputVisible {
                    // Tomaten-Knopf unter dem "+"; beide etwas kleiner, damit die Leiste nicht höher wird
                    VStack(spacing: 3) {
                        AddButton(enabled: store.canAdd,
                                  color: TimerPalette.color(store.nextFreeColor()),
                                  size: store.canStartPomodoro ? 18 : 22) { panels.showInput() }
                        if store.canStartPomodoro {
                            PomoButton { store.startPomodoro() }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, timers.isEmpty && !panels.inputVisible ? 6 : 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.black.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
        )
        .opacity(timers.isEmpty && !panels.inputVisible && !hovering ? 0.8 : 1)
        .onHover { hovering = $0 }
        .dragsWindow({ panels.barWindow },
                     onChanged: { panels.barDragChanged() },
                     onEnded: { panels.barDragEnded() })
        .contextMenu { BarMenu() }
        .help("Ziehen zum Verschieben · Rechtsklick für Optionen")
    }
}

private struct BarMenu: View {
    @EnvironmentObject var store: TimerStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var panels: PanelController

    var body: some View {
        Button("Neuer Timer …  (⌥⌘T)") { panels.showInput() }
            .disabled(!store.canAdd)
        Button("Tomate starten") { store.startPomodoro() }
            .disabled(!store.canStartPomodoro)
        Button("Pomodoro-Verlauf …") { panels.openHistory() }
        Divider()
        Button("Nach links unten") { settings.corner = .bottomLeft }
        Button("Nach rechts unten") { settings.corner = .bottomRight }
        Button("Einstellungen …") { panels.openSettings() }
        Button("Leiste ausblenden") { settings.showBar = false }
        Divider()
        Button("Segment Timer beenden") { NSApp.terminate(nil) }
    }
}

private struct AddButton: View {
    let enabled: Bool
    /// Farbe, die der nächste Timer bekommt – als blasses Neon
    let color: Color
    var size: CGFloat = 22
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: size * 0.55, weight: .heavy))
                .foregroundColor(enabled ? color.opacity(hovering ? 1 : 0.75) : .white.opacity(0.2))
                .shadow(color: enabled ? color.opacity(hovering ? 0.8 : 0.5) : .clear, radius: 3)
                .frame(width: size, height: size)
                .background(Circle().fill(enabled ? color.opacity(hovering ? 0.22 : 0.12) : Color.white.opacity(0.06)))
                .overlay(Circle().strokeBorder(color.opacity(enabled ? 0.25 : 0), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .help(enabled ? "Neuer Timer (⌥⌘T)" : "Maximal \(TimerStore.maxTimers) Timer")
    }
}

/// Startet die Pomodoro-Runde (nur sichtbar, solange keine läuft).
private struct PomoButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            TomatoIcon(size: 9, glow: hovering)
                .opacity(hovering ? 1 : 0.75)
                .frame(width: 22, height: 13)
                .background(Capsule().fill(TimerPalette.tomato.opacity(hovering ? 0.22 : 0.1)))
                .overlay(Capsule().strokeBorder(TimerPalette.tomato.opacity(0.25), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Tomate starten (oder \"pomo\" eingeben)")
    }
}

/// Ein Timer in der Leiste – Klick öffnet die Details.
struct TimerChip: View {
    let timer: CountdownTimer
    let isNext: Bool
    @EnvironmentObject var store: TimerStore
    @EnvironmentObject var panels: PanelController
    @State private var hovering = false

    var body: some View {
        let now = store.now
        let paused = timer.state == .paused
        let open = panels.openDetails.contains(timer.id)
        let digitHeight: CGFloat = isNext ? 16 : 12

        VStack(spacing: 3) {
            HStack(spacing: digitHeight * 0.3) {
                if timer.kind.isPomodoroPhase {
                    PomoBadge(kind: timer.kind, color: timer.color, height: digitHeight, dimmed: paused)
                }
                SegmentClock(
                    seconds: timer.displaySeconds(at: now),
                    color: timer.color,
                    height: digitHeight,
                    colonOn: timer.colonOn(at: now)
                )
                .opacity(paused ? 0.45 : 1)
            }

            HStack(spacing: 3) {
                if timer.kind.isPomodoroPhase {
                    PomoDots(index: timer.pomoIndex, total: store.settings.longBreakEvery,
                             kind: timer.kind, color: TimerPalette.tomato, size: 4)
                        .padding(.trailing, 2)
                }
                if paused {
                    Image(systemName: "pause.fill").font(.system(size: 7, weight: .bold))
                }
                if !timer.label.isEmpty {
                    Text(timer.label)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 80)
                        .fixedSize()
                    Text("·").opacity(0.6).fixedSize()
                }
                // Ablaufzeit immer sichtbar – das Label wird notfalls gekürzt
                Text(paused ? "Pause" : Format.clock(timer.endDate))
                    .monospacedDigit()
                    .fixedSize()
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundColor(timer.color.opacity(0.85))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(open ? 0.12 : (hovering ? 0.07 : 0)))
        )
        .contentShape(Rectangle())
        .onTapGesture { panels.toggleDetail(timer.id) }
        .onHover { hovering = $0 }
        .help(timer.title)
        .contextMenu { TimerMenu(timer: timer) }
    }
}

struct TimerMenu: View {
    let timer: CountdownTimer
    @EnvironmentObject var store: TimerStore
    @EnvironmentObject var panels: PanelController

    var body: some View {
        if timer.kind.isPomodoroPhase {
            pomodoroMenu
        } else {
            normalMenu
        }
    }

    @ViewBuilder private var pomodoroMenu: some View {
        Button("Details") { panels.openDetail(timer.id) }
        Button("Label ändern …") { panels.editLabel(timer.id) }
        Button(timer.state == .paused ? "Fortsetzen" : "Anhalten") { store.togglePause(timer.id) }
        if timer.kind.isBreak {
            Button("Pause überspringen → nächste Tomate") { store.pomoNextTomato() }
        }
        Button("Pomodoro-Verlauf …") { panels.openHistory() }
        Divider()
        Button(timer.kind == .pomodoro ? "Tomate abbrechen (beendet die Runde)" : "Runde beenden") {
            store.endPomodoroRound()
        }
    }

    @ViewBuilder private var normalMenu: some View {
        Button("Details") { panels.openDetail(timer.id) }
        Button("Label ändern …") { panels.editLabel(timer.id) }
        Button(timer.state == .paused ? "Fortsetzen" : "Pause") { store.togglePause(timer.id) }
        Button("Zurücksetzen") { store.reset(timer.id) }
        Menu("Farbe") {
            ForEach(TimerPalette.names.indices, id: \.self) { i in
                Button((i == timer.colorIndex ? "✓ " : "") + TimerPalette.names[i]) {
                    store.setColor(timer.id, to: i)
                }
            }
        }
        Divider()
        Button("Timer löschen") { store.remove(timer.id) }
    }
}

/// Eingabefeld für einen neuen Timer.
struct NewTimerInput: View {
    @EnvironmentObject var store: TimerStore
    @EnvironmentObject var panels: PanelController
    @State private var text = ""
    @State private var colorIndex: Int?

    var body: some View {
        let parsed = TimeParser.parse(text, now: store.now)
        let color = parsed?.isPomodoro == true ? TimerPalette.tomato : TimerPalette.color(selectedColor)

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .foregroundColor(color)
                InputField(text: $text,
                           placeholder: "9 · 1:30h Pizza · 14:45 · pomo",
                           onSubmit: submit,
                           onCancel: { panels.hideInput() })
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))

            HStack(spacing: 6) {
                ForEach(TimerPalette.colors.indices, id: \.self) { i in
                    let used = store.usedColors.contains(i)
                    Circle()
                        .fill(TimerPalette.color(i).opacity(used ? 0.2 : 1))
                        .frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: i == selectedColor ? 1.5 : 0))
                        .onTapGesture { if !used { colorIndex = i } }
                }
                Spacer(minLength: 10)
                Text(preview(parsed))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(parsed == nil && !text.isEmpty ? .red.opacity(0.85) : .white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .frame(width: 270)
        .onAppear { colorIndex = nil }
    }

    private var selectedColor: Int {
        if let colorIndex, !store.usedColors.contains(colorIndex) { return colorIndex }
        return store.nextFreeColor()
    }

    private func preview(_ p: ParsedTimer?) -> String {
        guard let p else { return text.isEmpty ? "Enter startet · Esc bricht ab" : "Nicht verstanden" }
        if p.isPomodoro {
            if store.pomodoro != nil { return "Es läuft schon eine Tomate" }
            let minutes = TimeInterval(store.settings.pomoMinutes * 60)
            return "Tomate · \(Format.duration(minutes)) → \(Format.clock(store.now.addingTimeInterval(minutes)))"
        }
        if p.isClockTime {
            return "bis \(Format.clock(p.endDate)) · \(Format.duration(p.duration))"
        }
        return "\(Format.duration(p.duration)) → \(Format.clock(p.endDate))"
    }

    private func submit(_ input: String) {
        guard let p = TimeParser.parse(input) else {
            NSSound.beep()
            return
        }
        if p.isPomodoro {
            guard store.startPomodoro(label: p.label) else {
                NSSound.beep()
                return
            }
        } else {
            store.add(p, colorIndex: selectedColor)
        }
        text = ""
        panels.hideInput()
    }
}

/// Natives Textfeld: Enter startet sofort (ohne dass die Textvorhersage
/// den ersten Tastendruck schluckt), Esc bricht ab.
struct InputField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void
    var fontSize: CGFloat = 14
    var textColor: NSColor = .white
    /// Fokus verlassen (z.B. Klick woanders hin) – nicht bei Enter/Esc
    var onEndEditing: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = textColor
        let base = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        field.font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: fontSize) } ?? base
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.35), .font: field.font ?? base]
        )
        field.isAutomaticTextCompletionEnabled = false
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.lineBreakMode = .byClipping
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            Coordinator.configure(field.currentEditor() as? NSTextView)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InputField
        /// Enter oder Esc wurde schon verarbeitet
        private var finished = false
        init(_ parent: InputField) { self.parent = parent }

        func controlTextDidEndEditing(_ note: Notification) {
            guard !finished, let field = note.object as? NSTextField else { return }
            finished = true
            parent.onEndEditing?(field.stringValue)
        }

        /// Vorhersage/Autokorrektur im Feld-Editor aus – sonst übernimmt
        /// der erste Enter-Druck nur den grauen Vorschlag.
        static func configure(_ editor: NSTextView?) {
            guard let editor else { return }
            if #available(macOS 14.0, *) { editor.inlinePredictionType = .no }
            editor.isAutomaticTextCompletionEnabled = false
            editor.isAutomaticTextReplacementEnabled = false
            editor.isAutomaticSpellingCorrectionEnabled = false
            editor.isAutomaticQuoteSubstitutionEnabled = false
            editor.isAutomaticDashSubstitutionEnabled = false
        }

        func controlTextDidBeginEditing(_ note: Notification) {
            Coordinator.configure(note.userInfo?["NSFieldEditor"] as? NSTextView)
        }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            // Laufende Eingabe (z.B. Akzente, Diktat) normal abschließen lassen
            if textView.hasMarkedText() { return false }
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                finished = parent.onEndEditing != nil
                parent.onSubmit(textView.string)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                finished = true
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }
}
