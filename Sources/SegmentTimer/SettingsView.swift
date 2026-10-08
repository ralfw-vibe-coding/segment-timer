import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let alarm: AlarmPlayer
    @EnvironmentObject var settings: AppSettings
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Leiste") {
                Picker("Position", selection: $settings.corner) {
                    ForEach(BarCorner.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text(settings.barAnchor == nil
                         ? "Die Leiste lässt sich mit der Maus frei verschieben."
                         : "Leiste wurde frei verschoben.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if settings.barAnchor != nil {
                        Button("Zurück in die Ecke") { settings.barAnchor = nil }
                    }
                }
                Toggle("Leiste anzeigen", isOn: $settings.showBar)
            }

            Section("Alarmton") {
                Picker("Ton", selection: $settings.soundChoice) {
                    Text("Digitalwecker (eingebaut)").tag(AppSettings.builtinSound)
                    Divider()
                    ForEach(AppSettings.systemSounds, id: \.self) { name in
                        Text(name).tag("system:\(name)")
                    }
                    Divider()
                    Text(customTitle).tag(AppSettings.customSound)
                }
                HStack {
                    Text(settings.customSoundPath.isEmpty
                         ? "Keine eigene Datei gewählt"
                         : (settings.customSoundPath as NSString).lastPathComponent)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("MP3 wählen …", action: chooseFile)
                }
                Slider(value: $settings.volume, in: 0...1) {
                    Text("Lautstärke")
                }
                HStack {
                    Spacer()
                    Button("Probehören") { alarm.preview() }
                    Button("Stopp") { alarm.stop() }
                }
            }

            Section("Allgemein") {
                Toggle("Beim Anmelden starten", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { on in
                        do { try settings.setLaunchAtLogin(on); loginError = nil }
                        catch { loginError = error.localizedDescription }
                    }
                ))
                if let loginError {
                    Text(loginError).font(.caption).foregroundColor(.red)
                }
                LabeledContent("Neuer Timer", value: "⌥⌘T (überall)")
                LabeledContent("Eingabe", value: "9 · 1:30h · 1,5h · 14:45 · 9 Tee")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var customTitle: String {
        settings.customSoundPath.isEmpty ? "Eigene Datei …" : "Eigene Datei: \((settings.customSoundPath as NSString).lastPathComponent)"
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3, .audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Alarmton wählen"
        if panel.runModal() == .OK, let url = panel.url {
            settings.customSoundPath = url.path
            settings.soundChoice = AppSettings.customSound
        }
    }
}
