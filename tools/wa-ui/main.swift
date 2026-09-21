// wa-ui: the small set of actions a computer-use agent needs to test Stickr inside the real WhatsApp app.
// Safety rule: every action that clicks, types or sends first checks that the open chat is "Message yourself".
// If it is not, the command fails with exit code 3 and does nothing.
import AppKit

let bundleID = "net.whatsapp.WhatsApp"
let container = NSString(string: "~/Library/Group Containers/group.net.whatsapp.WhatsApp.shared").expandingTildeInPath

func fail(_ msg: String, _ code: Int32 = 1) -> Never { FileHandle.standardError.write((msg + "\n").data(using: .utf8)!); exit(code) }
func whatsapp() -> NSRunningApplication {
  guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { fail("WhatsApp is not running. Run: wa-ui open-self") }
  return app
}
func attr(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(e, a as CFString, &v); return v }
func label(_ e: AXUIElement) -> String { ["AXDescription", "AXTitle", "AXValue", "AXIdentifier"].compactMap { attr(e, $0) as? String }.joined(separator: " | ") }
func frame(_ e: AXUIElement) -> CGRect {
  var p = CGPoint.zero, s = CGSize.zero
  if let v = attr(e, "AXPosition") { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
  if let v = attr(e, "AXSize") { AXValueGetValue(v as! AXValue, .cgSize, &s) }
  return CGRect(origin: p, size: s)
}
func walk(_ e: AXUIElement, depth: Int = 0, visit: (AXUIElement, Int) -> Bool) {   // visit returns false to stop
  var count = 0
  func go(_ e: AXUIElement, _ d: Int) -> Bool {
    count += 1; if count > 8000 || d > 50 { return true }
    if !visit(e, d) { return false }
    for c in (attr(e, "AXChildren") as? [AXUIElement] ?? []) { if !go(c, d + 1) { return false } }
    return true
  }
  _ = go(e, depth)
}
func mainWindow() -> (AXUIElement, CGRect) {
  let ax = AXUIElementCreateApplication(whatsapp().processIdentifier)
  guard let w = (attr(ax, "AXWindows") as? [AXUIElement])?.max(by: { frame($0).width < frame($1).width }) else { fail("WhatsApp has no window. Is Accessibility allowed for this terminal?") }
  return (w, frame(w))
}
func find(_ text: String) -> AXUIElement? {
  let want = text.lowercased(); var hit: AXUIElement?
  walk(mainWindow().0) { e, _ in if (attr(e, "AXRole") as? String) != "AXGroup", label(e).lowercased().contains(want) { hit = e; return false }; return true }
  return hit
}
func selfChatIsOpen() -> Bool { find("Message yourself") != nil }
func requireSelfChat() { if !selfChatIsOpen() { fail("REFUSED: the open chat is not 'Message yourself'. Run: wa-ui open-self", 3) } }
func bringToFront() {
  let app = whatsapp(); app.activate(options: [.activateAllWindows])
  for _ in 0..<30 { usleep(100_000); if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID { usleep(300_000); return } }
  fail("Could not bring WhatsApp to the front.", 2)
}
func stillFront() { if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != bundleID { fail("REFUSED: WhatsApp lost focus. Nothing was sent.", 2) } }
func windowID() -> CGWindowID {
  let pid = whatsapp().processIdentifier
  let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
  let mine = list.filter { ($0["kCGWindowOwnerPID"] as? Int32) == pid && (($0["kCGWindowBounds"] as! [String: Any])["Height"] as! Double) > 300 && ($0["kCGWindowIsOnscreen"] as? Bool) == true }
  guard let id = mine.first?["kCGWindowNumber"] as? UInt32 else { fail("No visible WhatsApp window.") }
  return id
}
func run(_ tool: String, _ args: [String]) -> String {
  let p = Process(), pipe = Pipe(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args; p.standardOutput = pipe; try? p.run(); p.waitUntilExit()
  return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}
let keyCodes: [String: CGKeyCode] = ["return": 36, "escape": 53, "tab": 48, "down": 125, "up": 126, "left": 123, "right": 124, "delete": 51]

let args = Array(CommandLine.arguments.dropFirst())
switch args.first ?? "help" {
case "guard":
  print(selfChatIsOpen() ? "OK: the open chat is 'Message yourself'." : "NO: another chat is open."); exit(selfChatIsOpen() ? 0 : 3)

case "open-self":   // opens the chat with yourself. This is the only chat the agent may use.
  let plist = NSDictionary(contentsOfFile: container + "/Library/Preferences/group.net.whatsapp.WhatsApp.shared.plist")
  guard let jid = plist?["OwnJabberID"] as? String, let number = jid.split(separator: "@").first else { fail("Own number not found in the WhatsApp preferences.") }
  NSWorkspace.shared.open(URL(string: "whatsapp://send?phone=\(number)")!); sleep(3)
  print(selfChatIsOpen() ? "OK" : "The self chat did not open."); exit(selfChatIsOpen() ? 0 : 3)

case "shot":        // wa-ui shot out.png   -> image in window points, so image x,y = click x,y
  guard args.count == 2 else { fail("usage: wa-ui shot <out.png>") }
  let size = mainWindow().1.size
  _ = run("/usr/sbin/screencapture", ["-x", "-o", "-l", String(windowID()), args[1]])
  _ = run("/usr/bin/sips", ["-z", String(Int(size.height)), String(Int(size.width)), args[1]])
  print("saved \(args[1]) \(Int(size.width))x\(Int(size.height))")

case "ax":          // wa-ui ax [filter]   -> labelled elements with their centre point in window coordinates
  let filter = args.count > 1 ? args[1].lowercased() : ""; let origin = mainWindow().1.origin
  walk(mainWindow().0) { e, _ in
    let l = label(e); if !l.isEmpty, filter.isEmpty || l.lowercased().contains(filter) { let f = frame(e); print("\(attr(e, "AXRole") as? String ?? "") | \(l) | centre \(Int(f.midX - origin.x)),\(Int(f.midY - origin.y))") }
    return true }

case "press":       // wa-ui press "Add to my stickers"
  guard args.count == 2 else { fail("usage: wa-ui press <label text>") }
  requireSelfChat()
  guard let e = find(args[1]) else { fail("No element with label: \(args[1])") }
  let r = AXUIElementPerformAction(e, "AXPress" as CFString); print(r == .success ? "pressed" : "press failed: \(r.rawValue)"); exit(r == .success ? 0 : 1)

case "click":       // wa-ui click x y   (window coordinates, same as the screenshot)
  guard args.count == 3, let x = Double(args[1]), let y = Double(args[2]) else { fail("usage: wa-ui click <x> <y>") }
  requireSelfChat(); bringToFront(); let o = mainWindow().1.origin; stillFront()
  for t in [CGEventType.leftMouseDown, .leftMouseUp] { CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: CGPoint(x: o.x + x, y: o.y + y), mouseButton: .left)!.post(tap: .cghidEventTap); usleep(60_000) }
  print("clicked")

case "key":         // wa-ui key return | escape | tab | up | down | left | right | delete | cmd+v
  guard args.count == 2 else { fail("usage: wa-ui key <name>") }
  let cmdV = args[1] == "cmd+v"; guard cmdV || keyCodes[args[1]] != nil else { fail("unknown key") }
  requireSelfChat(); bringToFront(); stillFront()
  for down in [true, false] { let e = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: cmdV ? 9 : keyCodes[args[1]]!, keyDown: down)!; if cmdV { e.flags = .maskCommand }; e.post(tap: .cghidEventTap); usleep(40_000) }
  print("sent key")

case "type":        // wa-ui type "text"   (into the focused field of the self chat)
  guard args.count == 2 else { fail("usage: wa-ui type <text>") }
  requireSelfChat(); bringToFront(); stillFront()
  for ch in args[1].utf16 { for down in [true, false] { let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)!; var c = ch; e.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c); e.post(tap: .cghidEventTap); usleep(15_000) } }
  print("typed")

case "import-pack": // wa-ui import-pack pack.json   -> WhatsApp shows its "Add to my stickers" dialog
  guard args.count == 2, let data = FileManager.default.contents(atPath: args[1]) else { fail("usage: wa-ui import-pack <pack.json>") }
  let pb = NSPasteboard.general; pb.clearContents()
  guard pb.setData(data, forType: NSPasteboard.PasteboardType("net.whatsapp.third-party.sticker-pack")) else { fail("pasteboard write failed") }
  NSWorkspace.shared.open(URL(string: "whatsapp://stickerPack")!); sleep(3); print("handed \(data.count) bytes to WhatsApp")

case "packs":       // wa-ui packs   -> installed packs as WhatsApp stores them (read from a copy)
  let tmp = NSTemporaryDirectory() + "stickr-sticker-\(getpid()).sqlite"
  for ext in ["", "-wal", "-shm"] { try? FileManager.default.copyItem(atPath: container + "/Sticker.sqlite" + ext, toPath: tmp + ext) }
  print(run("/usr/bin/sqlite3", [tmp, "select ZNAME || ' | ' || ZSTICKERPACKID || ' | ' || ZSTICKERCOUNT from ZWACDABSTRACTSTICKERPACK where Z_ENT=2 order by Z_PK"]))

case "last-message": // wa-ui last-message -> type of the newest message you sent in the self chat. 15 = sticker, 1 = image.
  let tmp = NSTemporaryDirectory() + "stickr-chat-\(getpid()).sqlite"
  for ext in ["", "-wal", "-shm"] { try? FileManager.default.copyItem(atPath: container + "/ChatStorage.sqlite" + ext, toPath: tmp + ext) }
  let plist = NSDictionary(contentsOfFile: container + "/Library/Preferences/group.net.whatsapp.WhatsApp.shared.plist"); let jid = plist?["OwnJabberID"] as? String ?? ""
  print(run("/usr/bin/sqlite3", [tmp, "select 'type=' || m.ZMESSAGETYPE || ' seconds_ago=' || cast(strftime('%s','now') - (m.ZMESSAGEDATE + 978307200) as int) from ZWAMESSAGE m join ZWACHATSESSION c on m.ZCHATSESSION=c.Z_PK where c.ZCONTACTJID='\(jid)' order by m.ZMESSAGEDATE desc limit 1"]))

default:
  print("""
  wa-ui guard | open-self | shot <out.png> | ax [filter] | press <label> | click <x> <y> | key <name> | type <text>
        import-pack <pack.json> | packs | last-message
  Actions only work while the chat 'Message yourself' is open. Coordinates are window points and match the screenshot.
  """)
}
