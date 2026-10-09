import AVFoundation

/// Spielt den Alarmton in Schleife, bis er gestoppt wird.
final class AlarmPlayer: NSObject, AVAudioPlayerDelegate {
    private let settings: AppSettings
    private var player: AVAudioPlayer?
    private var shortPlayer: AVAudioPlayer?
    private(set) var isRinging = false
    /// Solange Ton läuft, schläft der Mac nicht ein – darum klingelt der Alarm nicht endlos.
    static let maxRingSeconds: TimeInterval = 120
    private var ringGeneration = 0

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        guard !isRinging else { return }
        isRinging = true
        play()
        // Nach spätestens 2 Minuten verstummen (das Alarmfenster bleibt stehen)
        ringGeneration += 1
        let generation = ringGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.maxRingSeconds) { [weak self] in
            guard let self, self.isRinging, self.ringGeneration == generation else { return }
            self.stop()
        }
    }

    func stop() {
        isRinging = false
        ringGeneration += 1
        player?.stop()
        player = nil
    }

    /// Kurzer Hinweiston (Ende einer Tomate/Pause): einmal, höchstens ein paar Sekunden.
    func playShort(maxSeconds: TimeInterval = 4) {
        guard !isRinging else { return }      // ein laufender Alarm ist ohnehin zu hören
        shortPlayer?.stop()
        let p = makePlayer()
        p?.volume = Float(settings.volume)
        p?.play()
        shortPlayer = p
        DispatchQueue.main.asyncAfter(deadline: .now() + maxSeconds) { [weak self] in
            guard let self, self.shortPlayer === p else { return }
            p?.stop()
            self.shortPlayer = nil
        }
    }

    /// Einmal abspielen (Einstellungen → Probehören).
    func preview() {
        stop()
        play()
    }

    private func play() {
        player = makePlayer()
        player?.volume = Float(settings.volume)
        player?.delegate = self
        player?.prepareToPlay()
        player?.play()
    }

    private func makePlayer() -> AVAudioPlayer? {
        let choice = settings.soundChoice
        if choice == AppSettings.customSound, !settings.customSoundPath.isEmpty,
           let p = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: settings.customSoundPath)) {
            return p
        }
        if choice.hasPrefix("system:"),
           let p = try? AVAudioPlayer(contentsOf: AppSettings.systemSoundURL(String(choice.dropFirst(7)))) {
            return p
        }
        return try? AVAudioPlayer(data: DigitalBeep.wav)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard isRinging else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.isRinging, let p = self.player else { return }
            p.currentTime = 0
            p.play()
        }
    }
}

/// Erzeugt den klassischen "Piep-Piep-Piep-Piep" eines Digitalweckers als WAV.
enum DigitalBeep {
    static let wav: Data = {
        let sampleRate = 44_100.0
        var samples: [Int16] = []

        func tone(_ seconds: Double, frequency: Double) {
            let n = Int(seconds * sampleRate)
            let fade = 0.004 * sampleRate
            for i in 0..<n {
                let t = Double(i) / sampleRate
                let x = 2 * Double.pi * frequency * t
                let env = min(1, Double(i) / fade, Double(n - i) / fade)
                let v = (sin(x) + 0.25 * sin(3 * x)) / 1.25 * env * 0.55
                samples.append(Int16(v * Double(Int16.max)))
            }
        }
        func silence(_ seconds: Double) {
            samples.append(contentsOf: repeatElement(0, count: Int(seconds * sampleRate)))
        }

        for _ in 0..<4 {
            tone(0.075, frequency: 2600)
            silence(0.06)
        }
        silence(0.35)

        var data = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let byteCount = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); u32(36 + byteCount)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); u32(16)
        u16(1); u16(1)                                  // PCM, mono
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate) * 2)
        u16(2); u16(16)                                 // block align, bits
        data.append(contentsOf: Array("data".utf8)); u32(byteCount)
        samples.forEach { u16(UInt16(bitPattern: $0)) }
        return data
    }()
}
