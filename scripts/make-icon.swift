// Renders the SkyRay app icon (1024x1024 PNG) with CoreGraphics. No dependencies.
// Usage: swift scripts/make-icon.swift <out.png> [--rounded]
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "icon.png"
let rounded = args.contains("--rounded")
let size: CGFloat = 1024

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 0xff) / 255, CGFloat((hex >> 8) & 0xff) / 255, CGFloat(hex & 0xff) / 255, a])!
}

// Optional iOS-style rounded mask for previews (the App Store applies its own mask).
if rounded {
    let r = size * 0.2237
    let path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size), cornerWidth: r, cornerHeight: r, transform: nil)
    ctx.addPath(path); ctx.clip()
}

// 1. Sky gradient: deep navy (top-left) -> azure -> cyan (bottom-right).
let bg = CGGradient(colorsSpace: cs, colors: [rgb(0x081C44), rgb(0x0E4DC4), rgb(0x18B6F5)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// 2. Soft glow at the bottom right (sun below the horizon).
let glow = CGGradient(colorsSpace: cs, colors: [rgb(0x7FF0FF, 0.55), rgb(0x7FF0FF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 860, y: 120), startRadius: 0, endCenter: CGPoint(x: 860, y: 120), endRadius: 620, options: [])

// 3. A few faint stars in the dark corner.
ctx.setFillColor(rgb(0xFFFFFF, 0.55))
for (x, y, r) in [(150, 850, 7), (260, 930, 4), (95, 700, 4), (330, 800, 5), (210, 760, 3), (420, 900, 3)] as [(CGFloat, CGFloat, CGFloat)] {
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

// 4. The comet: a bright head at the top right with a tail that tapers away
// towards the bottom left. Upper and lower edges are quadratic curves that
// meet at the tail tip and open up to the head's diameter.
let head = CGPoint(x: 745, y: 745)
let headR: CGFloat = 96
let tail = CGPoint(x: 165, y: 250)
// Direction from tail to head and its perpendicular, for the head's shoulders.
let dx = head.x - tail.x, dy = head.y - tail.y
let len = (dx * dx + dy * dy).squareRoot()
let ux = dx / len, uy = dy / len
let px = -uy, py = ux
// Shoulders sit slightly behind the head centre so the tail tucks under the disc.
let back = CGPoint(x: head.x - ux * headR * 0.35, y: head.y - uy * headR * 0.35)
let upperShoulder = CGPoint(x: back.x + px * headR * 0.80, y: back.y + py * headR * 0.80)
let lowerShoulder = CGPoint(x: back.x - px * headR * 0.80, y: back.y - py * headR * 0.80)
// Control points close to the tail axis: a slim, gently curved streak.
let mid = CGPoint(x: (tail.x + head.x) / 2, y: (tail.y + head.y) / 2)
let ctrlUpper = CGPoint(x: mid.x + px * 150, y: mid.y + py * 150)
let ctrlLower = CGPoint(x: mid.x + px * 20, y: mid.y + py * 20)
let comet = CGMutablePath()
comet.move(to: tail)
comet.addQuadCurve(to: upperShoulder, control: ctrlUpper)
comet.addLine(to: lowerShoulder)
comet.addQuadCurve(to: tail, control: ctrlLower)
comet.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 60, color: rgb(0xBFF6FF, 0.8))
ctx.setFillColor(rgb(0xFFFFFF, 0.0))
ctx.addPath(comet); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(comet); ctx.clip()
let tailGrad = CGGradient(colorsSpace: cs, colors: [rgb(0xFFFFFF, 0.0), rgb(0xFFFFFF, 0.85), rgb(0xFFFFFF, 1)] as CFArray, locations: [0, 0.45, 1])!
ctx.drawLinearGradient(tailGrad, start: tail, end: head, options: [])
ctx.restoreGState()

// 5. The head: solid white disc with a strong glow.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 90, color: rgb(0xFFFFFF, 1))
ctx.setFillColor(rgb(0xFFFFFF))
ctx.fillEllipse(in: CGRect(x: head.x - headR, y: head.y - headR, width: headR * 2, height: headR * 2))
ctx.restoreGState()

// 6. Two small sparkles so the sky feels alive.
ctx.setStrokeColor(rgb(0xFFFFFF, 0.9)); ctx.setLineCap(.round)
for (cx, cy, arm, w) in [(900.0, 520.0, 22.0, 6.0), (300.0, 880.0, 16.0, 5.0)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
    ctx.setLineWidth(w)
    ctx.move(to: CGPoint(x: cx - arm, y: cy)); ctx.addLine(to: CGPoint(x: cx + arm, y: cy)); ctx.strokePath()
    ctx.move(to: CGPoint(x: cx, y: cy - arm)); ctx.addLine(to: CGPoint(x: cx, y: cy + arm)); ctx.strokePath()
}

let image = ctx.makeImage()!
let url = URL(fileURLWithPath: outPath) as CFURL
let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outPath)")
