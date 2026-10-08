import SwiftUI

/// `SegmentTimer --render-preview <ordner>` schreibt PNGs der Ansichten – zum Prüfen des Designs.
@MainActor
enum DebugRender {
    static func run(into dir: String) {
        let now = Date()
        func t(_ label: String, _ color: Int, _ remaining: TimeInterval, _ state: TimerState = .running) -> CountdownTimer {
            var timer = CountdownTimer(label: label, colorIndex: color, duration: 540, state: state,
                                       endDate: now.addingTimeInterval(remaining))
            if state == .paused { timer.pausedRemaining = remaining }
            return timer
        }
        let running = [t("Tee", 0, 599.2), t("", 1, 3725), t("Pizza", 2, 1312, .paused)]
        let settings = AppSettings()
        let store = TimerStore(preview: running, now: now)
        let panels = PanelController(store: store, settings: settings, alarm: AlarmPlayer(settings: settings))

        func save<V: View>(_ view: V, _ name: String) {
            let renderer = ImageRenderer(content: view
                .environmentObject(store).environmentObject(settings).environmentObject(panels)
                .padding(30).background(Color(white: 0.55)))
            renderer.scale = 2
            guard let img = renderer.nsImage, let tiff = img.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                print("Fehler: \(name)"); return
            }
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
            print("✓ \(name).png")
        }

        save(BarView().fixedSize(), "bar")
        save(DetailView(timerID: running[0].id, window: { nil }).fixedSize(), "detail")
        save(DetailView(timerID: running[1].id, window: { nil }).fixedSize(), "detail-hours")

        let expiredStore = TimerStore(preview: [t("Backofen", 2, -12, .expired)], now: now)
        let r = ImageRenderer(content: AlarmView(window: { nil }).fixedSize().environmentObject(expiredStore).padding(30).background(Color(white: 0.55)))
        r.scale = 2
        if let tiff = r.nsImage?.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("alarm.png")); print("✓ alarm.png")
        }
    }
}
