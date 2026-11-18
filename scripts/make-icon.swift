// Etodo uygulama simgesi (logo C · Mıknatıs ve üçlü: video, fotoğraf, müzik). Kullanım: swift scripts/make-icon.swift <çıktı klasörü>
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
    ctx.setShadow(offset: CGSize(width: 0, height: s * 10 / 1024), blur: s * 24 / 1024, color: color(0x000000, 0.25))
    ctx.addPath(shape); ctx.setFillColor(color(0xF5F1E8)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let bg = CGGradient(colorsSpace: nil, colors: [color(0xFDFBF6), color(0xEAE3D2)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: inset), end: CGPoint(x: 0, y: inset + body), options: [])
    ctx.restoreGState()

    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: inset + x * body / 100, y: inset + y * body / 100) }
    func u(_ v: CGFloat) -> CGFloat { v * body / 100 }
    let small = px <= 32

    // Çekim çizgileri: içerik mıknatısa doğru akıyor (küçük boyutta çizilmez).
    if !small {
        let lines = CGMutablePath()
        for (x, y0) in [(30.0, 34.0), (50.0, 31.0), (68.0, 36.0)] {
            lines.move(to: p(x, y0)); lines.addLine(to: p(x, y0 + 4))
        }
        ctx.addPath(lines)
        ctx.setStrokeColor(color(0x1E2B4A, 0.22)); ctx.setLineWidth(u(2)); ctx.setLineCap(.round)
        ctx.strokePath()
    }

    // Mıknatıs gövdesi
    let k: CGFloat = 20 * 0.5523
    let magnet = CGMutablePath()
    magnet.move(to: p(30, 52)); magnet.addLine(to: p(30, 64))
    magnet.addCurve(to: p(50, 84), control1: p(30, 64 + k), control2: p(50 - k, 84))
    magnet.addCurve(to: p(70, 64), control1: p(50 + k, 84), control2: p(70, 64 + k))
    magnet.addLine(to: p(70, 52))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: u(1.2)), blur: u(2.4), color: color(0x000000, 0.22))
    ctx.addPath(magnet)
    ctx.setStrokeColor(color(0x1E2B4A)); ctx.setLineWidth(u(small ? 16 : 14)); ctx.setLineCap(.butt)
    ctx.strokePath()
    ctx.restoreGState()
    // üstte ince parlama
    ctx.addPath(magnet)
    ctx.setStrokeColor(color(0xFFFFFF, 0.10)); ctx.setLineWidth(u(3))
    ctx.strokePath()

    // Kırmızı uçlar
    for x: CGFloat in [23, 63] {
        let tip = CGPath(roundedRect: CGRect(origin: p(x - (small ? 0.5 : 0), 44), size: CGSize(width: u(small ? 15 : 14), height: u(11))),
                         cornerWidth: u(1.5), cornerHeight: u(1.5), transform: nil)
        ctx.addPath(tip); ctx.setFillColor(color(0xFF453A)); ctx.fillPath()
        ctx.addRect(CGRect(origin: p(x, 44), size: CGSize(width: u(14), height: u(2.5))))
        ctx.setFillColor(color(0xFFFFFF, 0.28)); ctx.fillPath()
    }

    // Video (oynat)
    let play = CGMutablePath()
    play.move(to: p(24, 16)); play.addLine(to: p(24, 30)); play.addLine(to: p(36, 23)); play.closeSubpath()
    ctx.addPath(play); ctx.setFillColor(color(0x0A84FF)); ctx.setStrokeColor(color(0x0A84FF))
    ctx.setLineWidth(u(2.5)); ctx.setLineJoin(.round)
    ctx.drawPath(using: .fillStroke)

    // Fotoğraf
    let photo = CGPath(roundedRect: CGRect(origin: p(42, 14), size: CGSize(width: u(16), height: u(13))),
                       cornerWidth: u(2.5), cornerHeight: u(2.5), transform: nil)
    ctx.addPath(photo); ctx.setFillColor(color(0xFFB020)); ctx.fillPath()
    if !small {
        let mountain = CGMutablePath()
        mountain.move(to: p(45, 24)); mountain.addLine(to: p(49, 19)); mountain.addLine(to: p(52, 22))
        mountain.addLine(to: p(53.5, 21)); mountain.addLine(to: p(56, 24)); mountain.closeSubpath()
        ctx.addPath(mountain); ctx.setFillColor(.white); ctx.fillPath()
    }

    // Müzik notası
    ctx.addEllipse(in: CGRect(origin: p(64, 25), size: CGSize(width: u(8), height: u(8))))
    ctx.setFillColor(color(0xBF5AF2)); ctx.fillPath()
    let stem = CGMutablePath()
    stem.move(to: p(71.5, 29)); stem.addLine(to: p(71.5, 16)); stem.addLine(to: p(77, 18.5))
    ctx.addPath(stem); ctx.setStrokeColor(color(0xBF5AF2)); ctx.setLineWidth(u(3))
    ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.strokePath()

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
