import SwiftUI

/// Eine Siebensegment-Ziffer. Nicht leuchtende Segmente werden schwach angedeutet.
struct SevenSegmentDigit: View {
    let digit: Int?
    let color: Color
    let height: CGFloat
    var glow: Bool = true

    //                         a      b      c      d      e      f      g
    private static let map: [[Bool]] = [
        [true, true, true, true, true, true, false],      // 0
        [false, true, true, false, false, false, false],  // 1
        [true, true, false, true, true, false, true],     // 2
        [true, true, true, true, false, false, true],     // 3
        [false, true, true, false, false, true, true],    // 4
        [true, false, true, true, false, true, true],     // 5
        [true, false, true, true, true, true, true],      // 6
        [true, true, true, false, false, false, false],   // 7
        [true, true, true, true, true, true, true],       // 8
        [true, true, true, true, false, true, true],      // 9
    ]

    static func width(for height: CGFloat) -> CGFloat { height * 0.56 }

    var body: some View {
        let w = Self.width(for: height)
        let pad = height * 0.08
        Canvas { ctx, _ in
            let segments = Self.segments(w: w, h: height, offset: pad)
            let lit = digit.map { Self.map[$0 % 10] } ?? Array(repeating: false, count: 7)
            for i in 0..<7 where !lit[i] {
                ctx.fill(segments[i], with: .color(color.opacity(0.13)))
            }
            ctx.drawLayer { layer in
                if glow { layer.addFilter(.shadow(color: color.opacity(0.75), radius: max(1, height * 0.045))) }
                for i in 0..<7 where lit[i] {
                    layer.fill(segments[i], with: .color(color))
                }
            }
        }
        .frame(width: w + 2 * pad, height: height + 2 * pad)
        .padding(-pad)
    }

    private static func segments(w: CGFloat, h: CGFloat, offset o: CGFloat) -> [Path] {
        let t = h * 0.15            // Strichstärke
        let gap = max(0.4, t * 0.14)
        let half = t / 2

        func horizontal(_ y: CGFloat) -> Path {
            let x0 = half, x1 = w - half
            var p = Path()
            p.move(to: CGPoint(x: o + x0 + gap, y: o + y))
            p.addLine(to: CGPoint(x: o + x0 + gap + half, y: o + y - half))
            p.addLine(to: CGPoint(x: o + x1 - gap - half, y: o + y - half))
            p.addLine(to: CGPoint(x: o + x1 - gap, y: o + y))
            p.addLine(to: CGPoint(x: o + x1 - gap - half, y: o + y + half))
            p.addLine(to: CGPoint(x: o + x0 + gap + half, y: o + y + half))
            p.closeSubpath()
            return p
        }
        func vertical(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: o + x, y: o + y0 + gap))
            p.addLine(to: CGPoint(x: o + x + half, y: o + y0 + gap + half))
            p.addLine(to: CGPoint(x: o + x + half, y: o + y1 - gap - half))
            p.addLine(to: CGPoint(x: o + x, y: o + y1 - gap))
            p.addLine(to: CGPoint(x: o + x - half, y: o + y1 - gap - half))
            p.addLine(to: CGPoint(x: o + x - half, y: o + y0 + gap + half))
            p.closeSubpath()
            return p
        }

        let mid = h / 2
        return [
            horizontal(half),                       // a
            vertical(w - half, half, mid),          // b
            vertical(w - half, mid, h - half),      // c
            horizontal(h - half),                   // d
            vertical(half, mid, h - half),          // e
            vertical(half, half, mid),              // f
            horizontal(mid),                        // g
        ]
    }
}

struct SegmentColon: View {
    let color: Color
    let height: CGFloat
    let on: Bool

    var body: some View {
        let d = height * 0.13
        VStack(spacing: height * 0.24) {
            Circle().frame(width: d, height: d)
            Circle().frame(width: d, height: d)
        }
        .foregroundColor(on ? color : color.opacity(0.18))
        .shadow(color: on ? color.opacity(0.7) : .clear, radius: max(1, height * 0.04))
        .frame(width: height * 0.2, height: height)
    }
}

/// Zeigt Sekunden als MM:SS bzw. H:MM:SS in Siebensegment-Ziffern.
struct SegmentClock: View {
    let seconds: Int
    let color: Color
    let height: CGFloat
    var colonOn: Bool = true
    var digitsOn: Bool = true
    var glow: Bool = true

    static func text(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    var body: some View {
        let chars = Array(Self.text(seconds))
        HStack(spacing: height * 0.13) {
            ForEach(chars.indices, id: \.self) { i in
                if chars[i] == ":" {
                    SegmentColon(color: color, height: height, on: colonOn && digitsOn)
                } else {
                    SevenSegmentDigit(
                        digit: digitsOn ? chars[i].wholeNumberValue : nil,
                        color: color,
                        height: height,
                        glow: glow
                    )
                }
            }
        }
    }
}
