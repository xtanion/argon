import AppKit

let args = CommandLine.arguments
guard args.count == 3, let scale = Double(args[2]) else {
    FileHandle.standardError.write("usage: dmg_background.swift <out.png> <scale>\n".data(using: .utf8)!)
    exit(1)
}

let size = CGSize(width: 600, height: 400)
let pixels = CGSize(width: size.width * scale, height: size.height * scale)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

NSColor.white.setFill()
NSRect(origin: .zero, size: size).fill()

let blue = NSColor(srgbRed: 0.16, green: 0.45, blue: 0.98, alpha: 1)
blue.setStroke()

func bezier(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
    let u = 1 - t
    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
    return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
}

func wobble(_ t: CGFloat, _ seed: CGFloat) -> CGFloat {
    sin(t * 7.3 + seed) * 0.9 + sin(t * 17.1 + seed * 2.1) * 0.45
}

func ink(_ points: [CGPoint], from w0: CGFloat, to w1: CGFloat, seed: CGFloat) {
    let n = points.count
    for i in 1..<n {
        let t = CGFloat(i) / CGFloat(n - 1)
        let pressure = sin(t * .pi) * 0.35 + 0.75
        let segment = NSBezierPath()
        segment.move(to: points[i - 1])
        segment.line(to: points[i])
        segment.lineWidth = (w0 + (w1 - w0) * t) * pressure
        segment.lineCapStyle = .round
        segment.stroke()
    }
}

func sampleCurve(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, seed: CGFloat, jitter: CGFloat) -> [CGPoint] {
    (0...120).map { i in
        let t = CGFloat(i) / 120
        let p = bezier(p0, p1, p2, p3, t)
        let q = bezier(p0, p1, p2, p3, min(t + 0.01, 1))
        let r = bezier(p0, p1, p2, p3, max(t - 0.01, 0))
        let dx = q.x - r.x, dy = q.y - r.y
        let len = max(hypot(dx, dy), 0.001)
        let offset = wobble(t, seed) * jitter * sin(t * .pi)
        return CGPoint(x: p.x - dy / len * offset, y: p.y + dx / len * offset)
    }
}

let start = CGPoint(x: 230, y: 206)
let end = CGPoint(x: 364, y: 210)
let c1 = CGPoint(x: 262, y: 270)
let c2 = CGPoint(x: 330, y: 268)
ink(sampleCurve(start, c1, c2, end, seed: 1.3, jitter: 1.6), from: 2.6, to: 3.6, seed: 0.4)

let angle = atan2(end.y - c2.y, end.x - c2.x)
func barb(_ spread: CGFloat, _ length: CGFloat, _ bend: CGFloat, seed: CGFloat) {
    let a = angle + .pi + spread
    let tip = CGPoint(x: end.x + length * cos(a), y: end.y + length * sin(a))
    let mid = CGPoint(x: (end.x + tip.x) / 2 - sin(a) * bend, y: (end.y + tip.y) / 2 + cos(a) * bend)
    ink(sampleCurve(tip, mid, mid, CGPoint(x: end.x + 0.6, y: end.y - 0.4), seed: seed, jitter: 0), from: 2.2, to: 3.6, seed: seed)
}
barb(-0.72, 26, 2.0, seed: 2.2)
barb(0.62, 22, -1.6, seed: 4.1)

let caption = "Drag Argon to Applications to install"
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
    .foregroundColor: NSColor(white: 0.45, alpha: 1),
]
let textSize = caption.size(withAttributes: attrs)
caption.draw(at: NSPoint(x: (size.width - textSize.width) / 2, y: 70), withAttributes: attrs)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
