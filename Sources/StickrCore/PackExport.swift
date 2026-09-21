import Foundation
import AppKit

public enum PackExport {
    /// The pack JSON for the WhatsApp pasteboard type net.whatsapp.third-party.sticker-pack.
    /// Still and animated stickers never share a pack, so the caller splits first.
    public static func packJSON(name: String, members: [Sticker], animated: Bool) throws -> Data {
        guard members.count >= 3, members.count <= 30 else {
            throw Store.StoreError("A sticker pack needs 3 to 30 stickers. This one has \(members.count).")
        }
        let tray = trayPNG(first: members[0])
        var stickers: [[String: Any]] = []
        for s in members {
            let data = try Data(contentsOf: URL(fileURLWithPath: s.path))
            var entry: [String: Any] = [
                "image_data": data.base64EncodedString(),
                "emojis": s.emojis.isEmpty ? ["🙂"] : Array(s.emojis.prefix(3)),
            ]
            if !s.caption.isEmpty { entry["accessibility_text"] = s.caption }
            stickers.append(entry)
        }
        var dict: [String: Any] = [
            "identifier": "stickr-\(slug(name))",
            "name": name,
            "publisher": "Stickr",
            "tray_image": tray.base64EncodedString(),
            "stickers": stickers,
        ]
        if animated { dict["animated_sticker_pack"] = true }
        return try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
    }

    public static func slug(_ name: String) -> String {
        let ok = name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        return ok.isEmpty ? "pack" : String(ok.prefix(40))
    }

    /// 96 x 96 PNG for the tray icon, from the first member sticker.
    static func trayPNG(first sticker: Sticker) -> Data {
        guard let img = NSImage(contentsOfFile: sticker.path) else { return Data() }
        let size = CGSize(width: 96, height: 96)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 96, pixelsHigh: 96, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0) ?? (NSBitmapImageRep() as NSBitmapImageRep)
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(origin: .zero, size: size), from: img.alignmentRect ?? NSRect(origin: .zero, size: size), operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }

    /// Stickers that break the limits WhatsApp enforces on iOS (still 100 KB, animated 500 KB) stay out of packs.
    public static func limitProblems(_ s: Sticker) -> String? {
        if s.animated && s.byteSize > 500_000 { return "animated sticker of \(s.byteSize / 1000) KB, above the 500 KB limit" }
        if !s.animated && s.byteSize > 100_000 { return "still sticker of \(s.byteSize / 1000) KB, above the 100 KB limit" }
        if s.width != 512 || s.height != 512 { return "\(s.width) x \(s.height) px, not 512 x 512" }
        return nil
    }
}
