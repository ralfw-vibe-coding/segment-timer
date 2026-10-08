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
                    AddButton(enabled: store.canAdd) { panels.showInput() }
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
        .opacity(timers.isEmpty && !panels.inputVisible && !hovering ? 0.55 : 1)
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
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(enabled ? (hovering ? 0.95 : 0.6) : 0.2))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(hovering && enabled ? 0.16 : 0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .help(enabled ? "Neuer Timer (⌥⌘T)" : "Maximal \(TimerStore.maxTimers) Timer")
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

        VStack(spacing: 3) {
            SegmentClock(
                seconds: timer.displaySeconds(at: now),
                color: timer.color,
                height: isNext ? 16 : 12,
                colonOn: timer.colonOn(at: now)
            )
            .opacity(paused ? 0.45 : 1)

            HStack(spacing: 3) {
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
        .help(timer.label.isEmpty ? "Timer" : timer.label)
        .contextMenu { TimerMenu(timer: timer) }
    }
}

struct TimerMenu: View {
    let timer: CountdownTimer
    @EnvironmentObject var store: TimerStore
    @EnvironmentObject var panels: PanelController

    var body: some View {
        Button("Details") { panels.openDetail(timer.id) }
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
        let color = TimerPalette.color(selectedColor)

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .foregroundColor(color)
                InputField(text: $text,
                           placeholder: "9 · 1:30h Pizza · 14:45 Meeting",
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
        store.add(p, colorIndex: selectedColor)
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

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = .white
        let base = NSFont.systemFont(ofSize: 14, weight: .medium)
        field.font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 14) } ?? base
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
        init(_ parent: InputField) { self.parent = parent }

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
                parent.onSubmit(textView.string)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }
}
