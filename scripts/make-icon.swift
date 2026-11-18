// Etodo uygulama simgesi (logo B · Damla). Kullanım: swift scripts/make-icon.swift <çıktı klasörü>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // y aşağı; 100 birimlik taslak, macOS simge gövdesine (1024'te 824, kenar 100) oturur.
    ctx.translateBy(x: 0, y: s); ctx.scaleBy(x: 1, y: -1)
    let inset = s * 100 / 1024, body = s * 824 / 1024
    let bodyRect = CGRect(x: inset, y: inset, width: body, height: body)
    let shape = CGPath(roundedRect: bodyRect, cornerWidth: body * 0.225, cornerHeight: body * 0.225, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: s * 10 / 1024), blur: s * 24 / 1024, color: color(0x000000, 0.28))
    ctx.addPath(shape); ctx.setFillColor(color(0x0A84FF)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let bg = CGGradient(colorsSpace: nil, colors: [color(0x48A4FF), color(0x0A6FE8)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: inset), end: CGPoint(x: 0, y: inset + body), options: [])
    ctx.restoreGState()

    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: inset + x * body / 100, y: inset + y * body / 100) }
    let k: CGFloat = 25 * 0.5523
    let drop = CGMutablePath()
    drop.move(to: p(50, 16))
    drop.addCurve(to: p(75, 60), control1: p(50, 16), control2: p(75, 45))
    drop.addCurve(to: p(50, 85), control1: p(75, 60 + k), control2: p(50 + k, 85))
    drop.addCurve(to: p(25, 60), control1: p(50 - k, 85), control2: p(25, 60 + k))
    drop.addCurve(to: p(50, 16), control1: p(25, 45), control2: p(50, 16))
    drop.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: s * 8 / 1024), blur: s * 20 / 1024, color: color(0x003A80, 0.30))
    ctx.addPath(drop); ctx.setFillColor(.white); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(drop); ctx.clip()
    let shine = CGGradient(colorsSpace: nil, colors: [color(0xFFFFFF), color(0xE3F0FF)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(shine, start: p(50, 16), end: p(50, 85), options: [])
    ctx.restoreGState()

    let arrow = CGMutablePath()
    arrow.move(to: p(50, 44)); arrow.addLine(to: p(50, 70))
    arrow.move(to: p(41, 61)); arrow.addLine(to: p(50, 70)); arrow.addLine(to: p(59, 61))
    ctx.addPath(arrow)
    ctx.setStrokeColor(color(0x0A78F5))
    ctx.setLineWidth(body * (px <= 32 ? 0.085 : 0.065))
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.strokePath()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

var images: [String] = []
for (size, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
    try render(size * scale).write(to: out.appendingPathComponent(name))
    images.append(#"{"idiom":"mac","size":"\#(size)x\#(size)","scale":"\#(scale)x","filename":"\#(name)"}"#)
}
try Data(#"{"images":[\#(images.joined(separator: ","))],"info":{"author":"xcode","version":1}}"#.utf8)
    .write(to: out.appendingPathComponent("Contents.json"))
