import AppKit
import WebKit

final class StickrWindowController: NSWindowController, WKNavigationDelegate, WKUIDelegate {
    private let webView: WKWebView
    private let bridge: AppBridge
    private var pendingRoute: String?

    init(store: Store, kind: String) {
        let config = WKWebViewConfiguration()
        bridge = AppBridge(store: store)
        config.userContentController.addScriptMessageHandler(bridge, contentWorld: .page, name: "stickr")
        if kind == "search" {
            config.userContentController.addUserScript(WKUserScript(source: "window.__stickrInitialRoute='search'", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        config.setURLSchemeHandler(StickerScheme(store: store), forURLScheme: "stickr")
        webView = WKWebView(frame: .zero, configuration: config)
        let size = kind == "search" ? NSSize(width: 660, height: 520) : NSSize(width: 720, height: 620)
        let style: NSWindow.StyleMask = kind == "search" ? [.titled, .fullSizeContentView] : [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = "Stickr"; window.minSize = NSSize(width: 620, height: 480)
        window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false; window.contentView = webView
        if kind == "search" { window.level = .floating; window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary] }
        super.init(window: window)
        bridge.window = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        if let fileURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web") {
            var parts = URLComponents(url: fileURL, resolvingAgainstBaseURL: false)
            if kind == "search" { parts?.fragment = "search" }
            webView.loadFileURL(parts?.url ?? fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        }
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(route: String) {
        pendingRoute = route
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
        window?.level = route == "onboarding" ? .floating : .normal
        window?.makeKeyAndOrderFront(nil)
        if webView.url != nil {
            webView.evaluateJavaScript("window.stickrNavigate && window.stickrNavigate(\(jsonString(route)))")
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let route = pendingRoute else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak webView] in
            webView?.evaluateJavaScript("window.stickrNavigate && window.stickrNavigate(\(jsonString(route)))")
        }
    }

    func bringForward(aboveSettings: Bool = false) {
        if aboveSettings { window?.level = .floating }
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func closeWindow() { window?.orderOut(nil) }

    func reportProgress(stickerID: String, state: String) {
        webView.evaluateJavaScript("window.stickrProgress && window.stickrProgress(\(jsonString(stickerID)), \(jsonString(state)))")
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert(); alert.messageText = prompt; alert.addButton(withTitle: "Create"); alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: defaultText ?? ""); field.placeholderString = "Pack name"; field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        guard let window else { completionHandler(nil); return }
        alert.beginSheetModal(for: window) { response in completionHandler(response == .alertFirstButtonReturn ? field.stringValue : nil) }
    }
}

private func jsonString(_ value: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [value])
    return String(data: data, encoding: .utf8)!.dropFirst().dropLast().description
}

final class StickerScheme: NSObject, WKURLSchemeHandler {
    let store: Store
    init(store: Store) { self.store = store }
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let id = urlSchemeTask.request.url?.lastPathComponent.removingPercentEncoding,
              let sticker = try? store.sticker(id: id),
              let data = try? Data(contentsOf: URL(fileURLWithPath: sticker.path)),
              let url = urlSchemeTask.request.url,
              let response = URLResponse(url: url, mimeType: "image/webp", expectedContentLength: data.count, textEncodingName: nil) as URLResponse? else {
            urlSchemeTask.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist)); return
        }
        urlSchemeTask.didReceive(response); urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
