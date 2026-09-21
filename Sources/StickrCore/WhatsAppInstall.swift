import Foundation
import AppKit

/// The only way into WhatsApp: the official third-party sticker pack import.
public enum WhatsAppInstall {
    public static let pasteboardType = NSPasteboard.PasteboardType("net.whatsapp.third-party.sticker-pack")

    @discardableResult
    public static func install(packJSON: Data) throws -> Int {
        let pb = NSPasteboard.general
        let previous = pb.pasteboardItems ?? []
        pb.clearContents()
        guard pb.setData(packJSON, forType: pasteboardType) else {
            throw Store.StoreError("Stickr could not place the sticker pack on the pasteboard.")
        }
        defer {
            pb.clearContents()
            for item in previous { pb.writeObjects([item]) }
        }
        let opened = NSWorkspace.shared.open(URL(string: "whatsapp://stickerPack")!)
        if !opened { throw Store.StoreError("WhatsApp did not open. Start WhatsApp and try again.") }
        return packJSON.count
    }
}
