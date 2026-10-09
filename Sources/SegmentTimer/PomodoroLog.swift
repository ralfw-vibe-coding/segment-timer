import Foundation

/// Eine abgeschlossene (oder abgebrochene) Tomate bzw. Pause.
struct PomodoroRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: TimerKind
    var label: String
    var index: Int
    var planned: TimeInterval
    var segments: [TimeSegment]
    /// false = abgebrochen bzw. übersprungen
    var completed: Bool

    var start: Date { segments.first?.start ?? .distantPast }
    var end: Date { segments.last?.end ?? .distantPast }
    var activeDuration: TimeInterval { segments.reduce(0) { $0 + $1.duration } }
    var isWork: Bool { kind == .pomodoro }

    /// Abgebrochene Tomaten zählen erst ab 5 Minuten – kürzere waren meist versehentlich gestartet.
    static let minAbortedDuration: TimeInterval = 5 * 60

    var counts: Bool {
        !(isWork && !completed && activeDuration < Self.minAbortedDuration)
    }
}

/// Verlauf aller Tomaten, gespeichert als JSON in Application Support.
final class PomodoroLog: ObservableObject {
    @Published private(set) var records: [PomodoroRecord] = []
    private let fileURL: URL?

    init(inMemory: [PomodoroRecord]? = nil) {
        if let inMemory {
            fileURL = nil
            records = inMemory
            return
        }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Segment Timer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("pomodoro-log.json")
        load()
    }

    func append(_ record: PomodoroRecord) {
        guard record.counts else { return }
        records.append(record)
        save()
    }

    func remove(_ id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    func records(on day: Date) -> [PomodoroRecord] {
        let cal = Calendar.current
        return records.filter { cal.isDate($0.start, inSameDayAs: day) }
    }

    /// Tage mit Einträgen (plus heute), neueste zuerst.
    var days: [Date] {
        let cal = Calendar.current
        var set = Set(records.map { cal.startOfDay(for: $0.start) })
        set.insert(cal.startOfDay(for: Date()))
        return set.sorted(by: >)
    }

    static func stats(_ records: [PomodoroRecord]) -> (tomatoes: Int, aborted: Int, focus: TimeInterval) {
        let work = records.filter(\.isWork)
        return (work.filter(\.completed).count,
                work.filter { !$0.completed }.count,
                work.reduce(0) { $0 + $1.activeDuration })
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = (try? decoder.decode([PomodoroRecord].self, from: data)) ?? []
        // Regel gilt auch für ältere Einträge
        records = loaded.filter(\.counts)
        if records.count != loaded.count { save() }
    }

    private func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
