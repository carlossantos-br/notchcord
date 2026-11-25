#if DEBUG
import AppKit
import WebKit

/// File-based debug channel, compiled into DEBUG builds only. Enabled only if
/// ~/Library/Application Support/Notchcord/debug/on exists.
///  - <target>.<n>.js  -> runs JS (target: channel index, "sel" or "picker"), result in <n>.out
///  - <n>.cmd          -> command (expand, collapse, peek, pin, unpin, notch, floating, split, state)
final class DebugBridge {
    static let shared = DebugBridge()
    private var timer: Timer?
    private weak var island: IslandController?
    private weak var picker: PickerController?
    private let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Notchcord/debug")

    func start(island: IslandController, picker: PickerController) {
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("on").path) else { return }
        self.island = island; self.picker = picker
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in self?.poll() }
        NSLog("Notchcord: debug bridge on")
    }

    private func write(_ name: String, _ text: String) {
        try? text.write(to: dir.appendingPathComponent(name + ".out"), atomically: true, encoding: .utf8)
    }

    private func poll() {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        for f in files {
            let url = dir.appendingPathComponent(f)
            if f.hasSuffix(".js") {
                let parts = f.dropLast(3).split(separator: ".", maxSplits: 1).map(String.init)
                guard parts.count == 2, let src = try? String(contentsOf: url, encoding: .utf8) else { continue }
                try? FileManager.default.removeItem(at: url)
                runJS(target: parts[0], name: parts[1], src: src)
            } else if f.hasSuffix(".cmd") {
                guard let src = try? String(contentsOf: url, encoding: .utf8) else { continue }
                try? FileManager.default.removeItem(at: url)
                write(String(f.dropLast(4)), command(src.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
    }

    private func webView(for target: String) -> WKWebView? {
        let m = AppModel.shared
        if target == "picker" { return picker?.web }
        if target == "sel" { return m.selected.flatMap { WebPool.shared.webs[$0.id]?.webView } }
        if let i = Int(target), i < m.channels.count { return WebPool.shared.webs[m.channels[i].id]?.webView }
        return nil
    }

    private func runJS(target: String, name: String, src: String) {
        guard let wv = webView(for: target) else { write(name, "ERR: no web view '\(target)'"); return }
        wv.callAsyncJavaScript(src, arguments: [:], in: nil, in: .page) { [weak self] r in
            switch r {
            case .success(let v):
                if JSONSerialization.isValidJSONObject(v),
                   let d = try? JSONSerialization.data(withJSONObject: v, options: [.prettyPrinted]) {
                    self?.write(name, String(decoding: d, as: UTF8.self))
                } else { self?.write(name, "\(v)") }
            case .failure(let e): self?.write(name, "ERR: \(e)")
            }
        }
    }

    private func command(_ c: String) -> String {
        guard let island else { return "no island" }
        let m = AppModel.shared
        switch c {
        case "expand": island.expand()
        case "focus": island.expand(focus: true)
        case "collapse": island.setPresence(.collapsed)
        case "peek":
            if let id = m.channels.first?.id {
                WebPool.shared.onMessage?(id, "Test", "Test message from the island, with slightly longer text to check line wrapping.", "someone", nil)
            }
        case "pin": m.pinned = true
        case "unpin": m.pinned = false
        case "notch": m.mode = .notch
        case "floating": m.mode = .floating
        case "split": m.split.toggle()
        case "picker": picker?.show(url: nil)
        case "closepicker": picker?.window?.close()
        default: break
        }
        let webs = WebPool.shared.webs.map { "\($0.key): \($0.value.path) | \($0.value.title)" }.joined(separator: "\n")
        return """
        presence=\(m.presence) mode=\(m.mode) pinned=\(m.pinned) split=\(m.isSplit) needsLogin=\(m.needsLogin)
        key=\(island.panel.isKeyWindow) ignoresMouse=\(island.panel.ignoresMouseEvents) frame=\(island.panel.frame)
        notch=\(island.geo.notch) hasNotch=\(island.geo.hasNotch) unread=\(m.unread)
        channels=\(m.channels.map(\.label)) selected=\(m.selectedId ?? "-") visible=\(m.visibleIds)
        picker=\(picker?.state.path ?? "-") | \(picker?.state.title ?? "-")
        \(webs)
        """
    }
}

#endif
