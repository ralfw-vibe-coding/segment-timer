import SwiftUI

/// `SegmentTimer --render-preview <ordner>` schreibt PNGs der Ansichten – zum Prüfen des Designs.
@MainActor
enum DebugRender {
    static func run(into dir: String) {
        let now = Date()
        let settings = AppSettings()
        let cal = Calendar.current

        func t(_ label: String, _ color: Int, _ remaining: TimeInterval, _ state: TimerState = .running) -> CountdownTimer {
            var timer = CountdownTimer(label: label, colorIndex: color, duration: 540, state: state,
                                       endDate: now.addingTimeInterval(remaining))
            if state == .paused { timer.pausedRemaining = remaining }
            return timer
        }
        func pomo(_ kind: TimerKind, index: Int, remaining: TimeInterval, state: TimerState = .running, label: String = "") -> CountdownTimer {
            var p = CountdownTimer(label: label, colorIndex: -1, duration: 1500, state: state,
                                   endDate: now.addingTimeInterval(remaining))
            p.kind = kind
            p.pomoIndex = index
            p.segmentStart = now.addingTimeInterval(-(1500 - remaining))
            return p
        }
        // Beispielverlauf: heute und an zwei Vortagen
        func at(_ dayOffset: Int, _ h: Int, _ m: Int) -> Date {
            let day = cal.date(byAdding: .day, value: -dayOffset, to: now)!
            return cal.date(bySettingHour: h, minute: m, second: 0, of: day)!
        }
        func rec(_ kind: TimerKind, _ d: Int, _ h: Int, _ m: Int, _ minutes: Int, _ index: Int, done: Bool = true) -> PomodoroRecord {
            let s = at(d, h, m)
            return PomodoroRecord(kind: kind, label: "Kapitel 3", index: index, planned: 1500,
                                  segments: [TimeSegment(start: s, end: s.addingTimeInterval(TimeInterval(minutes * 60)))],
                                  completed: done)
        }
        let log = PomodoroLog(inMemory: [
            rec(.pomodoro, 0, 9, 0, 25, 1), rec(.shortBreak, 0, 9, 25, 5, 1),
            rec(.pomodoro, 0, 9, 30, 25, 2), rec(.shortBreak, 0, 9, 55, 5, 2),
            rec(.pomodoro, 0, 10, 0, 12, 3, done: false),
            rec(.pomodoro, 1, 14, 0, 25, 1), rec(.shortBreak, 1, 14, 25, 5, 1),
            rec(.pomodoro, 1, 14, 30, 25, 2), rec(.shortBreak, 1, 14, 55, 5, 2),
            rec(.pomodoro, 1, 15, 0, 25, 3), rec(.shortBreak, 1, 15, 25, 5, 3),
            rec(.pomodoro, 1, 15, 30, 25, 4), rec(.longBreak, 1, 15, 55, 15, 4),
            rec(.pomodoro, 3, 8, 15, 25, 1), rec(.pomodoro, 3, 19, 40, 25, 1),
        ])

        func render<V: View>(_ view: V, _ name: String, store: TimerStore, scale: CGFloat = 2, bg: Color = Color(white: 0.55),
                             editing: UUID? = nil) {
            let panels = PanelController(store: store, settings: settings, alarm: AlarmPlayer(settings: settings))
            panels.editingLabelID = editing
            let renderer = ImageRenderer(content: view.fixedSize()
                .environmentObject(store).environmentObject(settings).environmentObject(log).environmentObject(panels)
                .padding(30).background(bg))
            renderer.scale = scale
            guard let img = renderer.nsImage, let tiff = img.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                print("Fehler: \(name)"); return
            }
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
            print("✓ \(name).png")
        }

        let running = [t("Tee", 0, 599.2), t("", 1, 3725), t("Pizza", 2, 1312, .paused)]
        let store = TimerStore(preview: running, now: now, settings: settings, log: log)
        render(BarView(), "bar", store: store)
        render(DetailView(timerID: running[0].id, window: { nil }), "detail", store: store)
        render(DetailView(timerID: running[1].id, window: { nil }), "detail-hours", store: store)

        render(BarView(), "bar-empty", store: TimerStore(preview: [], now: now, settings: settings, log: log),
               scale: 3, bg: Color(white: 0.3))

        let tomato = pomo(.pomodoro, index: 3, remaining: 1142, label: "Kapitel 3")
        let pomoStore = TimerStore(preview: [tomato, t("Tee", 0, 240)], now: now, settings: settings, log: log)
        render(BarView(), "bar-pomo", store: pomoStore)
        render(DetailView(timerID: tomato.id, window: { nil }), "detail-pomo", store: pomoStore)
        render(DetailView(timerID: tomato.id, window: { nil }), "detail-pomo-edit", store: pomoStore, editing: tomato.id)

        let pause = pomo(.shortBreak, index: 2, remaining: 200)
        render(BarView(), "bar-pause", store: TimerStore(preview: [pause], now: now, settings: settings, log: log))

        render(PomodoroPromptView(window: { nil }), "prompt-tomato",
               store: TimerStore(preview: [pomo(.pomodoro, index: 4, remaining: -3, state: .expired, label: "Kapitel 3")],
                                 now: now, settings: settings, log: log))
        render(PomodoroPromptView(window: { nil }), "prompt-break",
               store: TimerStore(preview: [pomo(.shortBreak, index: 2, remaining: -3, state: .expired)],
                                 now: now, settings: settings, log: log))
        let historyStore = TimerStore(preview: [], now: now, settings: settings, log: log)
        render(PomodoroHistoryView().frame(width: 760, height: 300), "history", store: historyStore)
        // ScrollView-Inhalt rendert ImageRenderer nicht – die Zeilen einzeln
        render(HistoryDayRows(days: log.days, hours: DayTimeline.hourRange(log.records)).frame(width: 700)
                .padding(10).background(Color(white: 0.06)), "history-rows", store: historyStore)

        render(AlarmView(window: { nil }), "alarm",
               store: TimerStore(preview: [t("Backofen", 2, -12, .expired)], now: now, settings: settings, log: log))
    }
}
