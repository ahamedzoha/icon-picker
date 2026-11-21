// Renders the app icon: a white glyph on a rounded gradient square, 1024 px.
// usage: swift scripts/make-icon.swift <glyph.svg> <out.png>   (then build an .icns with iconutil)
import AppKit

let a = CommandLine.arguments
var svg = try! String(contentsOfFile: a[1], encoding: .utf8)
svg = svg.replacingOccurrences(of: "#000000", with: "#FFFFFF")
let glyph = NSImage(data: Data(svg.utf8))!
let S = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
// macOS icon grid: 824x824 rounded square centered in 1024
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(srgbRed: 0.98, green: 0.45, blue: 0.30, alpha: 1),
           ending: NSColor(srgbRed: 0.85, green: 0.20, blue: 0.55, alpha: 1))!.draw(in: path, angle: -60)
glyph.draw(in: body.insetBy(dx: 190, dy: 190))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
