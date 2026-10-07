import AppKit
import Carbon
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var windows: [String: StickrWindowController] = [:]
    private var timer: Timer?
    private var store: Store!
    private var hotKeyRefs: [EventHotKeyRef?] = [nil, nil]
    private var localKeyMonitor: Any?
    private var searchHotKey = "option+command+s"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        do { store = try Store(url: AppPaths.storeURL) }
        catch { NSAlert(error: error).runModal(); NSApp.terminate(nil); return }
        configureStatusItem()
        searchHotKey = (try? store.setting("hotkey")) ?? "option+command+s"
        registerHotKeys()
        HotKeyController.delegate = self
        if (try? store.setting("start_at_login")) == nil {
            try? store.setSetting("start_at_login", "true")
            try? SMAppService.mainApp.register()
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape), self?.windows["search"]?.window?.isVisible == true {
                self?.windows["search"]?.closeWindow(); return nil
            }
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "," {
                self?.show("settings"); return nil
            }
            return event
        }
        scheduleQuietRefresh()
        NotificationCenter.default.addObserver(self, selector: #selector(rescheduleRefresh), name: .stickrScheduleChanged, object: nil)
        if (try? store.setting("onboarding_complete")) != "true" { show("onboarding") }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "face.smiling.inverse", accessibilityDescription: "Stickr")
        statusItem.menu = menu()
    }

    private func menu() -> NSMenu {
        let menu = NSMenu(); menu.delegate = self
        let count = (try? store.allStickers().count) ?? 0
        let changed = (try? AppRefresh.statuses(store: store).filter { !$0.current }.count) ?? 0
        let suffix = changed > 0 ? " · \(changed) pack\(changed == 1 ? "" : "s") to update" : ""
        let state = NSMenuItem(title: "\(count) stickers\(suffix)", action: nil, keyEquivalent: "")
        state.isEnabled = false; menu.addItem(state); menu.addItem(.separator())
        menu.addItem(item("Find a sticker", #selector(openSearch), "s", [.option, .command]))
        menu.addItem(item("Check for new stickers", #selector(checkNow)))
        menu.addItem(item("Packs…", #selector(openPacks)))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), ",", [.command]))
        menu.addItem(item("Quit Stickr", #selector(NSApplication.terminate(_:)), "q", [.command]))
        return menu
    }

    private func item(_ title: String, _ action: Selector, _ key: String = "", _ mask: NSEvent.ModifierFlags = []) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self; item.keyEquivalentModifierMask = mask
        return item
    }

    func menuWillOpen(_ menu: NSMenu) { statusItem.menu = self.menu() }

    @objc private func openSearch() { show("search") }
    @objc private func openPacks() { show("packs") }
    @objc private func openSettings() { show("settings") }
    @objc private func checkNow() { show("updates") }

    private func show(_ route: String) {
        let kind = route == "search" ? "search" : "main"
        if windows[kind] == nil { windows[kind] = StickrWindowController(store: store, kind: kind) }
        windows[kind]?.show(route: route)
    }

    private func scheduleQuietRefresh() {
        timer?.invalidate(); timer = nil
        let setting = (try? store.setting("schedule")) ?? "Every 6 hours"
        let intervals = ["Every 6 hours": 21_600.0, "Every day": 86_400.0, "Every week": 604_800.0]
        guard let interval = intervals[setting] else { return }
        timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runBackgroundScan() }
        }
        timer?.tolerance = 900
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    @objc private func rescheduleRefresh() { scheduleQuietRefresh() }

    private func runBackgroundScan() {
        let currentStore = store!
        Task.detached(priority: .utility) {
            _ = try? await AppRefresh.run(store: currentStore)
        }
    }

    private func registerHotKeys() {
        var searchID = EventHotKeyID(signature: OSType(0x53544B52), id: 1)
        var settingsID = EventHotKeyID(signature: OSType(0x53544B52), id: 2)
        var searchRef: EventHotKeyRef?
        var settingsRef: EventHotKeyRef?
        let parsed = Self.parseHotKey(searchHotKey) ?? (UInt32(kVK_ANSI_S), UInt32(optionKey | cmdKey))
        RegisterEventHotKey(parsed.0, parsed.1, searchID, GetApplicationEventTarget(), 0, &searchRef)
        RegisterEventHotKey(UInt32(kVK_ANSI_Comma), UInt32(cmdKey), settingsID, GetApplicationEventTarget(), 0, &settingsRef)
        hotKeyRefs = [searchRef, settingsRef]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer in
            var eventID = EventHotKeyID(); GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &eventID)
            if let pointer {
                let app = Unmanaged<AppDelegate>.fromOpaque(pointer).takeUnretainedValue()
                if eventID.id == 1 { app.openSearch() }
                if eventID.id == 2 { app.openSettings() }
            }
            return noErr
        }, 1, [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))], Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    func applySearchHotKey(_ value: String) throws {
        guard let parsed = Self.parseHotKey(value) else { throw Store.StoreError("Use a letter with Command, Option, or Control.") }
        if let old = hotKeyRefs[0] { UnregisterEventHotKey(old) }
        var ref: EventHotKeyRef?
        var eventID = EventHotKeyID(signature: OSType(0x53544B52), id: 1)
        let status = RegisterEventHotKey(parsed.0, parsed.1, eventID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else {
            searchHotKey = (try? store.setting("hotkey")) ?? "option+command+s"
            let fallback = Self.parseHotKey(searchHotKey)!
            _ = RegisterEventHotKey(fallback.0, fallback.1, eventID, GetApplicationEventTarget(), 0, &hotKeyRefs[0])
            throw Store.StoreError("That shortcut is already used by another app.")
        }
        hotKeyRefs[0] = ref; searchHotKey = value
    }

    private static func parseHotKey(_ value: String) -> (UInt32, UInt32)? {
        let parts = value.lowercased().split(separator: "+").map(String.init)
        guard let letter = parts.last, letter.count == 1 else { return nil }
        let codes: [String: UInt32] = ["a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"o":31,"u":32,"i":34,"p":35,"l":37,"j":38,"k":40,"n":45,"m":46]
        guard let code = codes[letter] else { return nil }
        var modifiers: UInt32 = 0
        if parts.contains("command") { modifiers |= UInt32(cmdKey) }
        if parts.contains("option") { modifiers |= UInt32(optionKey) }
        if parts.contains("control") { modifiers |= UInt32(controlKey) }
        if parts.contains("shift") { modifiers |= UInt32(shiftKey) }
        guard modifiers != 0 else { return nil }
        return (code, modifiers)
    }
}

@MainActor
enum HotKeyController { static weak var delegate: AppDelegate? }

extension Notification.Name { static let stickrScheduleChanged = Notification.Name("StickrScheduleChanged") }

@main @MainActor
enum StickrMain {
    private static let delegate = AppDelegate()
    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}

enum AppPaths {
    static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Stickr", isDirectory: true)
    static let storeURL = support.appendingPathComponent("stickr.sqlite")
}
