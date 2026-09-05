// Composes an App Store marketing screenshot: gradient background, headline,
// sub-headline, and the raw simulator screenshot framed with rounded corners.
// Usage: swift scripts/make-store-shot.swift <in.png> <out.png> <W> <H> "<title>" "<subtitle>" [rtl]
import Foundation
import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
guard a.count >= 7 else { print("usage: in out W H title subtitle [rtl]"); exit(1) }
let inPath = a[1], outPath = a[2]
let W = CGFloat(Double(a[3])!), H = CGFloat(Double(a[4])!)
let title = a[5], subtitle = a[6]
let rtl = a.count > 7 && a[7] == "rtl"

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ hex: UInt32, _ al: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 0xff) / 255, CGFloat((hex >> 8) & 0xff) / 255, CGFloat(hex & 0xff) / 255, al])!
}
let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// Background: the icon's sky gradient plus a soft glow.
let bg = CGGradient(colorsSpace: cs, colors: [rgb(0x081C44), rgb(0x0E4DC4), rgb(0x18B6F5)] as CFArray, locations: [0, 0.6, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])
let glow = CGGradient(colorsSpace: cs, colors: [rgb(0x7FF0FF, 0.35), rgb(0x7FF0FF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: W * 0.85, y: H * 0.1), startRadius: 0, endCenter: CGPoint(x: W * 0.85, y: H * 0.1), endRadius: W * 0.9, options: [])

// Text block at the top.
let scale = W / 1320.0
func draw(_ text: String, size: CGFloat, weight: String, y: CGFloat, color: CGColor) -> CGFloat {
    let font = CTFontCreateWithName(weight as CFString, size * scale, nil)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let str = NSAttributedString(string: text, attributes: attrs)
    let framesetter = CTFramesetterCreateWithAttributedString(str)
    let maxWidth = W * 0.86
    let fit = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: 0), nil, CGSize(width: maxWidth, height: 10_000), nil)
    let para = NSMutableParagraphStyle(); para.alignment = .center
    para.baseWritingDirection = rtl ? .rightToLeft : .leftToRight
    let str2 = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
    let fs2 = CTFramesetterCreateWithAttributedString(str2)
    let rect = CGRect(x: (W - maxWidth) / 2, y: y - fit.height, width: maxWidth, height: fit.height + 4)
    let path = CGPath(rect: rect, transform: nil)
    let frame = CTFramesetterCreateFrame(fs2, CFRange(location: 0, length: 0), path, nil)
    CTFrameDraw(frame, ctx)
    return fit.height
}
var cursor = H - 150 * scale
let th = draw(title, size: 96, weight: rtl ? "GeezaPro-Bold" : "HelveticaNeue-Bold", y: cursor, color: rgb(0xFFFFFF))
cursor -= th + 26 * scale
_ = draw(subtitle, size: 46, weight: rtl ? "GeezaPro" : "HelveticaNeue", y: cursor, color: rgb(0xD8F3FF))

// Device screenshot: scaled to ~76% width, rounded corners, shadow, anchored at the bottom.
guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: inPath) as CFURL, nil),
      let shot = CGImageSourceCreateImageAtIndex(src, 0, nil) else { print("cannot read \(inPath)"); exit(1) }
let shotW = W * 0.76
let shotH = shotW * CGFloat(shot.height) / CGFloat(shot.width)
let shotRect = CGRect(x: (W - shotW) / 2, y: -shotH * 0.04, width: shotW, height: shotH)
let corner = shotW * 0.11
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -30 * scale), blur: 90 * scale, color: rgb(0x000000, 0.45))
ctx.setFillColor(rgb(0x000000, 0.001))
ctx.addPath(CGPath(roundedRect: shotRect, cornerWidth: corner, cornerHeight: corner, transform: nil)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: shotRect, cornerWidth: corner, cornerHeight: corner, transform: nil)); ctx.clip()
ctx.draw(shot, in: shotRect)
ctx.restoreGState()
// Thin bezel line.
ctx.setStrokeColor(rgb(0xFFFFFF, 0.25)); ctx.setLineWidth(4 * scale)
ctx.addPath(CGPath(roundedRect: shotRect, cornerWidth: corner, cornerHeight: corner, transform: nil)); ctx.strokePath()

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outPath)")
