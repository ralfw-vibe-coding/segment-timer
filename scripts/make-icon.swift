// Zeichnet das App-Icon (Siebensegment "9" auf schwarzem Grund) als 1024px-PNG.
// Aufruf: swift scripts/make-icon.swift <ausgabe.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let inset: CGFloat = 100
let bg = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset),
                      xRadius: 185, yRadius: 185)
NSColor(white: 0.05, alpha: 1).setFill()
bg.fill()

let magenta = NSColor(red: 1, green: 0.2, blue: 0.84, alpha: 1)
let h: CGFloat = 560, w = h * 0.56, t = h * 0.15, gap = t * 0.14, half = t / 2
let ox = (size - w) / 2, oy = (size - h) / 2
// y nach oben (AppKit) – Segmente wie in der App, nur gespiegelt
func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: ox + x, y: oy + h - y) }
func horizontal(_ y: CGFloat) -> NSBezierPath {
    let p = NSBezierPath(); let x0 = half, x1 = w - half
    p.move(to: pt(x0 + gap, y)); p.line(to: pt(x0 + gap + half, y - half)); p.line(to: pt(x1 - gap - half, y - half))
    p.line(to: pt(x1 - gap, y)); p.line(to: pt(x1 - gap - half, y + half)); p.line(to: pt(x0 + gap + half, y + half)); p.close()
    return p
}
func vertical(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: pt(x, y0 + gap)); p.line(to: pt(x + half, y0 + gap + half)); p.line(to: pt(x + half, y1 - gap - half))
    p.line(to: pt(x, y1 - gap)); p.line(to: pt(x - half, y1 - gap - half)); p.line(to: pt(x - half, y0 + gap + half)); p.close()
    return p
}
let mid = h / 2
let segs = [horizontal(half), vertical(w - half, half, mid), vertical(w - half, mid, h - half),
            horizontal(h - half), vertical(half, mid, h - half), vertical(half, half, mid), horizontal(mid)]
let lit = [true, true, true, true, false, true, true] // "9"
for (i, s) in segs.enumerated() where !lit[i] { magenta.withAlphaComponent(0.14).setFill(); s.fill() }
let shadow = NSShadow(); shadow.shadowColor = magenta.withAlphaComponent(0.8); shadow.shadowBlurRadius = 30
shadow.set()
magenta.setFill()
for (i, s) in segs.enumerated() where lit[i] { s.fill() }

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
