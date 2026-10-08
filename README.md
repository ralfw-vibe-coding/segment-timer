# Segment Timer

Countdown-Timer für macOS im Siebensegment-Look. Bis zu 5 Timer, jeder mit eigener Farbe und Label.
Liegt als kleine Leiste unten links oder rechts am Bildschirmrand. Läuft ein Timer ab, öffnet sich
groß das Alarmfenster.

Gebaut nur mit Swift Package Manager, ohne Xcode-Projekt.

## Bauen & installieren

```bash
./build.sh            # → build/Segment Timer.app
./build.sh install    # → /Applications/Segment Timer.app und starten
```

## Bedienung

| Was | Wie |
|---|---|
| Leiste verschieben | Einfach mit der Maus ziehen; zurück in die Ecke per Rechtsklick |
| Neuer Timer | `+` in der Leiste, **⌥⌘T** (global) oder Menüleisten-Symbol |
| Details (Countdown, Ablaufzeit, Reset/Pause/Stopp) | Klick auf einen Timer in der Leiste, Fenster ist verschiebbar, Esc schließt |
| Pause, Reset, Farbe, Löschen | Rechtsklick auf einen Timer |
| Alarm stoppen | Enter oder Esc bzw. „Stopp“; außerdem +1 min, +5 min, Neustart |
| Position, Ton, MP3, Lautstärke | Rechtsklick auf die Leiste → Einstellungen |

### Pomodoro

- Start mit dem Tomaten-Knopf unter dem `+` oder durch Eingabe von `pomo` (`p`, `pomodoro`, auch mit Label: `pomo Kapitel 3`)
- Es läuft immer höchstens eine Tomate, sie zählt zu den 5 Timern
- In der Leiste: Siebensegment-„P“ vor dem Countdown, Punkte ●●◐○ zeigen die Position im Satz; in der Pause eine Tasse
- Nach einer Tomate: Dialog mit Pause (jede 4. eine lange) · Nächste Tomate · Beenden; nach der Pause: Nächste Tomate · Beenden
- Tomaten lassen sich anhalten und fortsetzen. Abbrechen zählt die bisherige Zeit und beendet die Runde (die nächste beginnt wieder bei 1)
- Verlauf: Detailansicht der Tomate (heutiger Tag) und Fenster „Pomodoro-Verlauf“ (Rechtsklick auf die Leiste), eine Zeile pro Tag
- Längen in den Einstellungen; Protokoll in `~/Library/Application Support/Segment Timer/pomodoro-log.json`

### Eingabe

Zahlen ohne Einheit sind Minuten. Text vor oder nach der Zeit wird zum Label.

| Eingabe | Bedeutung |
|---|---|
| `9`, `9min`, `90s` | Dauer |
| `1:30h`, `1,5h`, `1h 30`, `2:30min`, `1:30:00` | Dauer |
| `12:30`, `14:45`, `um 9`, `18 Uhr`, `12.30` | Ablaufzeit (liegt sie in der Vergangenheit, dann morgen) |
| `9 Tee`, `Meeting 14:45` | mit Label |
| `pomo`, `pomo Kapitel 3` | Tomate starten |

## Code

- `Sources/SegmentTimer/` – App (SwiftUI in randlosen `NSPanel`s, AppKit für Fenster und Menüleiste)
- `TimeParser.swift` – Eingabe-Interpretation
- `SevenSegment.swift` – Ziffern-Rendering
- `SegmentTimer --render-preview <ordner>` schreibt PNGs der Ansichten (zum Design-Check)
