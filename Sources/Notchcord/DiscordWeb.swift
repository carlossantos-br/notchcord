import AppKit
import WebKit

/// Safari user agent: Discord treats a bare WKWebView as an unknown browser.
let safariUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

/// Breaks the WKUserContentController -> handler retain cycle.
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(c, didReceive: m)
    }
}

enum WebFactory {
    /// Every web view shares cookies/localStorage (single login).
    static let processPool = WKProcessPool()

    static func make(compact: Bool, handler: WKScriptMessageHandler?) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.processPool = processPool
        cfg.websiteDataStore = .default()
        cfg.preferences.isElementFullscreenEnabled = false
        cfg.mediaTypesRequiringUserActionForPlayback = .all

        let ucc = WKUserContentController()
        let flag = "window.__ncCompact = \(compact ? "true" : "false"); window.__ncL10n = \(InjectedScripts.l10nJSON);"
        ucc.addUserScript(WKUserScript(source: flag + InjectedScripts.css + InjectedScripts.boot,
                                       injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if let handler { ucc.add(WeakScriptHandler(handler), name: "notchcord") }
        cfg.userContentController = ucc

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.customUserAgent = safariUA
        wv.allowsBackForwardNavigationGestures = false
        wv.allowsMagnification = false
        #if DEBUG
        wv.isInspectable = true
        #endif
        wv.underPageBackgroundColor = .black
        wv.setValue(false, forKey: "drawsBackground")
        return wv
    }
}

/// One Discord web instance bound to a channel.
final class DiscordWeb: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    let channelId: String
    let webView: WKWebView
    var onMessage: ((String, String, String, URL?) -> Void)?
    var onRoute: ((String, String) -> Void)?
    private(set) var path = ""
    private(set) var title = ""

    init(channel: Channel, zoom: Double) {
        channelId = channel.id
        webView = WebFactory.make(compact: true, handler: nil)
        super.init()
        webView.configuration.userContentController.add(WeakScriptHandler(self), name: "notchcord")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.pageZoom = zoom
        webView.load(URLRequest(url: channel.url))
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "notchcord")
    }

    func goHome(_ channel: Channel) {
        webView.load(URLRequest(url: channel.url))
    }

    func focusComposer() {
        webView.evaluateJavaScript("window.__ncFocus && window.__ncFocus()")
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard Self.trusted(m), let body = m.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "route":
            path = body["path"] as? String ?? ""
            title = body["title"] as? String ?? ""
            onRoute?(path, title)
        case "message":
            let author = body["author"] as? String ?? ""
            let text = body["text"] as? String ?? ""
            let reply = body["replyTo"] as? String ?? ""
            let avatar = (body["avatar"] as? String).flatMap(URL.init(string:))
            onMessage?(author, text, reply, avatar)
        default: break
        }
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url, action.targetFrame?.isMainFrame ?? false,
           action.navigationType == .linkActivated, !Self.isDiscord(url) {
            Self.openExternally(url)
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        Self.openExternally(action.request.url)
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { completionHandler($0 == .OK ? panel.urls : nil) }
    }

    /// Hosts allowed to load inside the web view (exact match or real subdomain).
    static let allowedHosts = ["discord.com", "discordapp.com", "discord.gg", "discord.new",
                               "hcaptcha.com", "recaptcha.net"]

    static func hostMatches(_ host: String?, _ list: [String]) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return list.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func isDiscord(_ url: URL) -> Bool {
        if url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" { return true }
        return hostMatches(url.host, allowedHosts)
    }

    /// Only accept bridge messages from the main frame served by Discord itself.
    static func trusted(_ m: WKScriptMessage) -> Bool {
        m.frameInfo.isMainFrame && hostMatches(m.frameInfo.securityOrigin.host, ["discord.com"])
    }

    /// Only http(s) and mailto are handed to the OS; every other scheme is dropped.
    static func openExternally(_ url: URL?) {
        guard let url, let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Keeps one live DiscordWeb per saved channel.
final class WebPool {
    static let shared = WebPool()
    private(set) var webs: [String: DiscordWeb] = [:]
    var onMessage: ((String, String, String, String, URL?) -> Void)?
    var onRoute: ((String, String, String) -> Void)?

    func sync(_ channels: [Channel], zoom: Double) {
        let ids = Set(channels.map(\.id))
        for id in webs.keys where !ids.contains(id) {
            webs[id]?.webView.removeFromSuperview()
            webs[id] = nil
        }
        for ch in channels where webs[ch.id] == nil {
            let w = DiscordWeb(channel: ch, zoom: zoom)
            w.onMessage = { [weak self] a, t, r, av in self?.onMessage?(ch.id, a, t, r, av) }
            w.onRoute = { [weak self] p, t in self?.onRoute?(ch.id, p, t) }
            webs[ch.id] = w
        }
    }

    func setZoom(_ z: Double) { webs.values.forEach { $0.webView.pageZoom = z } }
    func reloadAll() { webs.values.forEach { $0.webView.reload() } }
}
