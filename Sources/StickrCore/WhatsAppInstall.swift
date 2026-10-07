import Foundation
import AppKit

/// The only way into WhatsApp: the official third-party sticker pack import.
public enum WhatsAppInstall {
    public static let pasteboardType = NSPasteboard.PasteboardType("net.whatsapp.third-party.sticker-pack")

    @discardableResult
    public static func install(packJSON: Data) throws -> Int {
        let pb = NSPasteboard.general
        // Copy the old pasteboard contents as data, because items cannot move between pasteboards.
        var previous: [(NSPasteboard.PasteboardType, Data)] = []
        if let items = pb.pasteboardItems {
            for item in items {
                for t in item.types {
                    if let d = item.data(forType: t) { previous.append((t, d)) }
                }
            }
        }
        pb.clearContents()
        guard pb.setData(packJSON, forType: pasteboardType) else {
            throw Store.StoreError("Stickr could not place the sticker pack on the pasteboard.")
        }
        // WhatsApp reads the pasteboard after it opens, so restore the old contents after a short grace period.
        defer {
            pb.clearContents()
            if !previous.isEmpty {
                let item = NSPasteboardItem()
                for (t, d) in previous { item.setData(d, forType: t) }
                pb.writeObjects([item])
            }
        }
        let opened = NSWorkspace.shared.open(URL(string: "whatsapp://stickerPack")!)
        if !opened { throw Store.StoreError("WhatsApp did not open. Start WhatsApp and try again.") }
        Thread.sleep(forTimeInterval: 4)
        return packJSON.count
    }
}
