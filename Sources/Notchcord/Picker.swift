import AppKit
import SwiftUI
import WebKit
import Observation

@Observable
final class PickerState {
    var path = ""
    var title = ""
    var link = ""
    var message: String?
    var ids: (String, String)? { Channel.ids(from: path) }
    var canUse: Bool { ids != nil }
}

/// Regular window with the full Discord UI: log in and pick a channel by browsing.
final class PickerController: NSObject, NSWindowDelegate, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    let model: AppModel
    let state = PickerState()
    var onAdded: ((Channel) -> Void)?
    private(set) var window: NSWindow?
    private(set) var web: WKWebView?
    private var autoAddChannel: String?

    init(model: AppModel) { self.model = model }

    func show(url: URL?) {
        if window == nil { build() }
        if let url { web?.load(URLRequest(url: url)) }
        else if web?.url == nil {
            web?.load(URLRequest(url: model.selected?.url ?? URL(string: "https://discord.com/channels/@me")!))
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let wv = WebFactory.make(compact: false, handler: self)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        web = wv

        let view = PickerView(state: state, web: wv,
                              use: { [weak self] in self?.useCurrent() },
                              submitLink: { [weak self] in self?.useLink() })
        let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1180, height: 780),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = L.t("Choose channel — Notchcord", "Escolher canal — Notchcord")
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: view)
        w.setFrameAutosaveName("NotchcordPicker")
        if !w.setFrameUsingName("NotchcordPicker") { w.center() }
        w.delegate = self
        w.appearance = NSAppearance(named: .darkAqua)
        window = w
    }

    // MARK: Actions

    func useCurrent() {
        guard let (g, c) = state.ids, let web else { return }
        web.evaluateJavaScript(Self.nameScript) { [weak self] result, _ in
            guard let self else { return }
            let (name, guild) = Self.parseNames(json: result as? String, guildId: g, channelId: c)
            let ch = Channel(guildId: g, channelId: c, name: name, guild: guild)
            self.model.add(ch)
            self.state.message = L.t("\(ch.label) is on the island.", "\(ch.label) foi pra ilha.")
            self.onAdded?(ch)
        }
    }

    func useLink() {
        let text = state.link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let (g, c) = Channel.ids(from: text) else {
            state.message = L.t("That doesn't look like a channel link. Right-click the channel → Copy Link.",
                                "Esse link não parece de um canal. Use botão direito no canal → Copiar link.")
            return
        }
        autoAddChannel = c
        state.link = ""
        web?.load(URLRequest(url: URL(string: "https://discord.com/channels/\(g)/\(c)")!))
    }

    // MARK: Names

    /// Reads the page title plus the channel header.
    static let nameScript = #"""
    (() => {
      const pick = (s) => { const e = document.querySelector(s); return e ? e.textContent.trim() : ''; };
      const header = pick('section[class*="title_"] h1') || pick('[class*="titleWrapper_"] h1') || pick('h1[class*="title_"]');
      const guild = pick('nav[class*="container_"] header h2') || pick('[class*="sidebar_"] header [class*="name_"]') || pick('[class*="sidebar_"] header');
      return JSON.stringify({ title: document.title, header, guild });
    })()
    """#

    static func parseNames(json: String?, guildId: String, channelId: String) -> (String, String) {
        var title = "", header = "", guildDom = ""
        if let json, let d = json.data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: String] {
            title = o["title"] ?? ""; header = o["header"] ?? ""; guildDom = o["guild"] ?? ""
        }
        // "(3) Discord | #general | Server"  /  "• Discord | @someone"
        var t = title.replacingOccurrences(of: #"^(\(\d+\)\s*|•\s*)"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: " - Discord", with: "")
        let parts = t.components(separatedBy: " | ").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "Discord" }
        var name = parts.first { $0.hasPrefix("#") }.map { String($0.dropFirst()) } ?? ""
        if name.isEmpty { name = header.isEmpty ? (parts.first ?? "channel") : header }
        if name.hasPrefix("#") { name.removeFirst() }
        var guild = guildDom
        if guild.isEmpty { guild = parts.first { !$0.hasPrefix("#") && !$0.hasPrefix("@") && $0 != name } ?? "" }
        if guildId == "@me" { guild = "" }
        return (name.trimmingCharacters(in: .whitespaces), guild)
    }

    // MARK: WK

    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard DiscordWeb.trusted(m), let body = m.body as? [String: Any], body["type"] as? String == "route" else { return }
        state.path = body["path"] as? String ?? ""
        state.title = body["title"] as? String ?? ""
        if let auto = autoAddChannel, state.ids?.1 == auto, !state.title.isEmpty, state.title != "Discord" {
            autoAddChannel = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.useCurrent() }
        }
        // logged in: island web views that were stuck on the login page go back to their channel
        if state.path.hasPrefix("/channels/") {
            for ch in model.channels {
                if let w = WebPool.shared.webs[ch.id], !w.path.hasPrefix("/channels/") { w.goHome(ch) }
            }
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        DiscordWeb.openExternally(action.request.url)
        return nil
    }

    func windowWillClose(_ notification: Notification) {
        state.message = nil
        NSApp.deactivate()
    }
}

struct PickerView: View {
    var state: PickerState
    let web: WKWebView
    let use: () -> Void
    let submitLink: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            WebViewRep(web: web)
            HStack(spacing: 12) {
                Image(systemName: state.canUse ? "checkmark.circle.fill" : "hand.point.up.left.fill")
                    .foregroundStyle(state.canUse ? Color.green : blurple)
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.message ?? (state.canUse ? L.t("Ready. Is this the channel for the island?", "Pronto. Esse é o canal que vai pra ilha?")
                                                          : L.t("Browse to the channel you want on the island", "Navegue até o canal que você quer na ilha")))
                        .font(.system(size: 13, weight: .semibold))
                    Text(state.canUse ? cleanTitle(state.title) : L.t("Log in if asked, then open the channel as usual.",
                                                                    "Faça login se pedir, depois abra o canal normalmente."))
                        .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                TextField(L.t("or paste the channel link", "ou cole o link do canal"), text: Binding(get: { state.link }, set: { state.link = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 230)
                    .onSubmit(submitLink)
                Button(action: use) {
                    Text(L.t("Use this channel", "Usar este canal")).font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 6)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(blurple)
                .keyboardShortcut(.defaultAction)
                .disabled(!state.canUse)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(.bar)
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    private func cleanTitle(_ t: String) -> String {
        t.replacingOccurrences(of: #"^(\(\d+\)\s*|•\s*)"#, with: "", options: .regularExpression)
    }
}

struct WebViewRep: NSViewRepresentable {
    let web: WKWebView
    func makeNSView(context: Context) -> WKWebView { web }
    func updateNSView(_ v: WKWebView, context: Context) {}
}
