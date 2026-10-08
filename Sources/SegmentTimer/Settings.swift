import Foundation
import ServiceManagement

enum BarCorner: String, CaseIterable, Identifiable {
    case bottomLeft, bottomRight
    var id: String { rawValue }
    var title: String { self == .bottomLeft ? "Links unten" : "Rechts unten" }
}

/// Frei gewählte Position der Leiste: untere Kante und linke bzw. rechte Kante.
struct BarAnchor: Equatable {
    var x: Double
    var y: Double
    var right: Bool
}

final class AppSettings: ObservableObject {
    static let builtinSound = "builtin"
    static let customSound = "file"

    private let defaults = UserDefaults.standard

    @Published var corner: BarCorner {
        didSet {
            defaults.set(corner.rawValue, forKey: "corner")
            barAnchor = nil   // Ecke gewählt → frei verschobene Position verwerfen
        }
    }
    /// nil = Leiste sitzt in der gewählten Ecke
    @Published var barAnchor: BarAnchor? {
        didSet {
            if let a = barAnchor {
                defaults.set(["x": a.x, "y": a.y, "right": a.right], forKey: "barAnchor")
            } else {
                defaults.removeObject(forKey: "barAnchor")
            }
        }
    }

    /// Wächst die Leiste nach links (rechts verankert)?
    var barOnRight: Bool { barAnchor?.right ?? (corner == .bottomRight) }
    @Published var showBar: Bool {
        didSet { defaults.set(showBar, forKey: "showBar") }
    }
    /// "builtin", "system:<Name>" oder "file"
    @Published var soundChoice: String {
        didSet { defaults.set(soundChoice, forKey: "soundChoice") }
    }
    @Published var customSoundPath: String {
        didSet { defaults.set(customSoundPath, forKey: "customSoundPath") }
    }
    @Published var volume: Double {
        didSet { defaults.set(volume, forKey: "volume") }
    }

    // Pomodoro (alle Werte in Minuten)
    @Published var pomoMinutes: Int {
        didSet { defaults.set(pomoMinutes, forKey: "pomoMinutes") }
    }
    @Published var shortBreakMinutes: Int {
        didSet { defaults.set(shortBreakMinutes, forKey: "shortBreakMinutes") }
    }
    @Published var longBreakMinutes: Int {
        didSet { defaults.set(longBreakMinutes, forKey: "longBreakMinutes") }
    }
    /// Lange Pause nach so vielen Tomaten
    @Published var longBreakEvery: Int {
        didSet { defaults.set(longBreakEvery, forKey: "longBreakEvery") }
    }

    init() {
        defaults.register(defaults: [
            "corner": BarCorner.bottomRight.rawValue,
            "showBar": true,
            "soundChoice": Self.builtinSound,
            "customSoundPath": "",
            "volume": 0.8,
            "pomoMinutes": 25,
            "shortBreakMinutes": 5,
            "longBreakMinutes": 15,
            "longBreakEvery": 4,
        ])
        corner = BarCorner(rawValue: defaults.string(forKey: "corner") ?? "") ?? .bottomRight
        showBar = defaults.bool(forKey: "showBar")
        soundChoice = defaults.string(forKey: "soundChoice") ?? Self.builtinSound
        customSoundPath = defaults.string(forKey: "customSoundPath") ?? ""
        volume = defaults.double(forKey: "volume")
        pomoMinutes = defaults.integer(forKey: "pomoMinutes")
        shortBreakMinutes = defaults.integer(forKey: "shortBreakMinutes")
        longBreakMinutes = defaults.integer(forKey: "longBreakMinutes")
        longBreakEvery = max(1, defaults.integer(forKey: "longBreakEvery"))
        if let d = defaults.dictionary(forKey: "barAnchor"),
           let x = d["x"] as? Double, let y = d["y"] as? Double, let right = d["right"] as? Bool {
            barAnchor = BarAnchor(x: x, y: y, right: right)
        }
    }

    static var systemSounds: [String] {
        let dir = "/System/Library/Sounds"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return files
            .filter { $0.hasSuffix(".aiff") }
            .map { ($0 as NSString).deletingPathExtension }
            .sorted()
    }

    static func systemSoundURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
    }

    // MARK: Beim Anmelden starten

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        objectWillChange.send()
    }
}
