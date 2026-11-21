import AppKit
import SwiftUI

enum CopyMode: String, CaseIterable, Identifiable {
    case vector = "Vector"
    case png = "PNG"
    var id: String { rawValue }
}

enum Render {
    /// SVG source with black recolored to `hex` (brand-color logos keep their colors).
    static func svg(_ icon: Icon, hex: String) -> String {
        var s = (try? String(contentsOf: icon.url, encoding: .utf8)) ?? ""
        s = s.replacingOccurrences(of: "currentColor", with: "#000000")
        let h = hex.uppercased()
        guard h != "#000000", !icon.group.hasSuffix("Brand Color") else { return s }
        if s.contains("#000000") {
            s = s.replacingOccurrences(of: "#000000", with: h)
        } else if let r = s.range(of: "<svg") {
            s.replaceSubrange(r, with: "<svg fill=\"\(h)\"")
        }
        return s
    }

    static func image(_ svg: String) -> NSImage? { NSImage(data: Data(svg.utf8)) }

    static func fit(_ img: NSImage, _ side: CGFloat) -> CGSize {
        let w = max(img.size.width, 1), h = max(img.size.height, 1)
        let k = side / max(w, h)
        return CGSize(width: (w * k).rounded(), height: (h * k).rounded())
    }

    /// Vector PDF of the icon. Apps like Affinity turn this into editable curves on paste.
    static func pdf(_ img: NSImage, side: CGFloat) -> Data {
        var box = CGRect(origin: .zero, size: fit(img, side))
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        ctx.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        img.draw(in: box)
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    static func png(_ img: NSImage, side: CGFloat) -> Data? {
        let size = fit(img, side)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width),
                                         pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// A file for dragging or "Copy File": the original, or a recolored temporary copy.
    static func file(_ icon: Icon, hex: String) -> URL {
        if hex.uppercased() == "#000000" { return icon.url }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("IconPicker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appendingPathComponent(icon.name + ".svg")
        try? svg(icon, hex: hex).write(to: out, atomically: true, encoding: .utf8)
        return out
    }
}

enum Clip {
    static let svgType = NSPasteboard.PasteboardType("public.svg-image")

    @discardableResult
    static func copy(_ icon: Icon, mode: CopyMode, hex: String, size: CGFloat) -> Bool {
        let svg = Render.svg(icon, hex: hex)
        guard let img = Render.image(svg) else { return false }
        let item = NSPasteboardItem()
        switch mode {
        case .vector:
            // No PNG on purpose: Affinity prefers a PNG over a PDF and would paste pixels.
            item.setData(Render.pdf(img, side: size), forType: .pdf)
            item.setData(Data(svg.utf8), forType: svgType)
            item.setString(svg, forType: .string)
        case .png:
            guard let data = Render.png(img, side: size) else { return false }
            item.setData(data, forType: .png)
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.writeObjects([item])
    }

    static func copyCode(_ icon: Icon, hex: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(Render.svg(icon, hex: hex), forType: .string)
    }

    static func copyFile(_ icon: Icon, hex: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([Render.file(icon, hex: hex) as NSURL])
    }
}

@MainActor
final class Thumbs {
    static let shared = Thumbs()
    private let cache = NSCache<NSString, NSImage>()

    func get(_ icon: Icon, hex: String) -> NSImage? {
        let key = (icon.id + hex) as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let img = Render.image(Render.svg(icon, hex: hex)) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }
}

extension Color {
    var hex: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#000000" }
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }

    init(hex: String) {
        let v = Int(hex.dropFirst(), radix: 16) ?? 0
        self.init(.sRGB, red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255,
                  blue: Double(v & 255) / 255)
    }
}
