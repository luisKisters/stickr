import Foundation
import AppKit

/// The only way into WhatsApp: the official third-party sticker pack import.
public enum WhatsAppInstall {
    public static let pasteboardType = NSPasteboard.PasteboardType("net.whatsapp.third-party.sticker-pack")
    static let bundleID = "net.whatsapp.WhatsApp"

    @discardableResult
    public static func install(packJSON: Data) async throws -> Int {
        let pb = NSPasteboard.general
        // Copy the old pasteboard items as data, because items cannot move between pasteboards.
        let previous: [NSPasteboardItem] = (pb.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for t in item.types { if let d = item.data(forType: t) { copy.setData(d, forType: t) } }
            return copy
        }
        pb.clearContents()
        guard pb.setData(packJSON, forType: pasteboardType) else {
            throw Store.StoreError("Stickr could not place the sticker pack on the pasteboard.")
        }
        defer {
            pb.clearContents()
            if !previous.isEmpty { pb.writeObjects(previous) }
        }
        let opened = NSWorkspace.shared.open(URL(string: "whatsapp://stickerPack")!)
        if !opened { throw Store.StoreError("WhatsApp did not open. Start WhatsApp and try again.") }
        // WhatsApp reads the pasteboard after it has launched. Wait for the launch, then give it a grace period.
        for _ in 0..<60 {
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: \.isFinishedLaunching) { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        try await Task.sleep(for: .seconds(4))
        return packJSON.count
    }
}
