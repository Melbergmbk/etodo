// .dmg penceresinin arka planı: iki simge arasında ok ve tek satır açıklama.
// Kullanım: swift scripts/make-dmg-background.swift <çıktı.png> <ölçek 1|2>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let scale = CGFloat(Double(CommandLine.arguments[2])!)
let size = NSSize(width: 600, height: 380)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

NSColor(srgbRed: 0.965, green: 0.969, blue: 0.976, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

// Finder koordinatları üstten; burada alttan. Simge merkezleri y=170 (üstten) → 210 (alttan).
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 248, y: 210)); arrow.line(to: NSPoint(x: 348, y: 210))
arrow.move(to: NSPoint(x: 334, y: 222)); arrow.line(to: NSPoint(x: 350, y: 210)); arrow.line(to: NSPoint(x: 334, y: 198))
arrow.lineWidth = 5; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
NSColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 0.85).setStroke()
arrow.stroke()

let style = NSMutableParagraphStyle(); style.alignment = .center
let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 17, weight: .semibold),
                                            .foregroundColor: NSColor(white: 0.12, alpha: 1), .paragraphStyle: style]
let sub: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13),
                                          .foregroundColor: NSColor(white: 0.45, alpha: 1), .paragraphStyle: style]
NSAttributedString(string: "Etodo’yu Uygulamalar klasörüne sürükle", attributes: title)
    .draw(in: NSRect(x: 0, y: 64, width: 600, height: 24))
NSAttributedString(string: "Sonra Uygulamalar’dan aç. İlk açılışta kurulum sayfasındaki 3. adıma bak.", attributes: sub)
    .draw(in: NSRect(x: 0, y: 40, width: 600, height: 20))

NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: out)
