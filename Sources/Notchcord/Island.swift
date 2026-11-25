import AppKit
import SwiftUI
import Observation

// MARK: - Panel

final class IslandPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none
        isReleasedWhenClosed = false
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // let the window sit flush with the top edge, over the menu bar
    override func constrainFrameRect(_ r: NSRect, to s: NSScreen?) -> NSRect { r }
}

// MARK: - Geometry

@Observable
final class IslandGeo {
    var notch = CGSize(width: 185, height: 32)
    var hasNotch = true
    var screenFrame = CGRect.zero
}

struct IslandLayout {
    let m: AppModel
    let g: IslandGeo

    static let ear: CGFloat = 10
    static let pad: CGFloat = 30       // shadow room in notch mode
    static let fpad: CGFloat = 18      // shadow room in floating mode
    static let inset: CGFloat = 8
    static let gap: CGFloat = 6
    static let wing: CGFloat = 40
    static let peekW: CGFloat = 400
    static let peekExtra: CGFloat = 64
    static let floatTop: CGFloat = 38

    var notchMode: Bool { m.mode == .notch }
    var topH: CGFloat { notchMode ? max(g.notch.height, 30) : Self.floatTop }
    var notchGap: CGFloat { notchMode && g.hasNotch ? g.notch.width + 12 : 0 }

    var bodyW: CGFloat {
        let c = m.isSplit ? 2 * m.paneWidth + Self.gap + 2 * Self.inset : m.paneWidth + 2 * Self.inset
        return max(c, notchGap + 2 * 150)
    }
    var bodyH: CGFloat { m.bodyHeight }

    var windowSize: CGSize {
        if notchMode {
            return CGSize(width: max(bodyW, Self.peekW) + 2 * Self.ear + 2 * Self.pad,
                          height: max(bodyH, topH + Self.peekExtra) + Self.pad)
        }
        return CGSize(width: bodyW + 2 * Self.fpad, height: bodyH + 2 * Self.fpad)
    }

    /// Rect of the black shape (window coordinates, y pointing down).
    func shapeRect(_ p: Presence) -> CGRect {
        guard notchMode else { return CGRect(x: Self.fpad, y: Self.fpad, width: bodyW, height: bodyH) }
        let W = windowSize.width
        var w: CGFloat, h: CGFloat
        switch p {
        case .expanded:
            w = bodyW + 2 * Self.ear; h = bodyH
        case .peek:
            w = max(Self.peekW, g.notch.width + 2 * Self.wing) + 2 * Self.ear; h = topH + Self.peekExtra
        case .collapsed:
            if m.totalUnread > 0 {
                w = g.notch.width + 2 * Self.wing + 2 * Self.ear; h = g.notch.height
            } else {
                // slightly smaller than the physical notch: hides inside it
                w = g.notch.width - 4; h = g.notch.height - 2
            }
        }
        return CGRect(x: (W - w) / 2, y: 0, width: w, height: h)
    }

    func ear(_ p: Presence) -> CGFloat {
        guard notchMode else { return 0 }
        if p == .collapsed && m.totalUnread == 0 { return 0 }
        return p == .expanded ? Self.ear : 8
    }

    func bottomRadius(_ p: Presence) -> CGFloat {
        guard notchMode else { return 18 }
        switch p {
        case .expanded: return 26
        case .peek: return 22
        case .collapsed: return m.totalUnread > 0 ? 14 : 9
        }
    }

    var bodyRect: CGRect {
        let s = shapeRect(.expanded)
        return notchMode ? s.insetBy(dx: Self.ear, dy: 0) : s
    }
    var topBarRect: CGRect { CGRect(x: bodyRect.minX, y: bodyRect.minY, width: bodyRect.width, height: topH) }
    var stageRect: CGRect {
        let b = bodyRect
        return CGRect(x: b.minX + Self.inset, y: b.minY + topH,
                      width: b.width - 2 * Self.inset, height: b.height - topH - Self.inset)
    }
    var wingW: CGFloat { (bodyW - notchGap) / 2 - 14 }
}

// MARK: - Controller

final class IslandController: NSObject, NSWindowDelegate {
    let model: AppModel
    let geo = IslandGeo()
    let panel = IslandPanel()
    let stage = WebStage()
    var openPicker: ((URL?) -> Void)?

    private var timer: Timer?
    private var dwell: TimeInterval = 0
    private var outside: TimeInterval = 0
    private var peekWork: DispatchWorkItem?
    private var clickMonitor: Any?
    private var lastMode: Mode?

    var layout: IslandLayout { IslandLayout(m: model, g: geo) }

    init(model: AppModel) {
        self.model = model
        super.init()

        let root = IslandView(model: model, geo: geo, controller: self)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host
        panel.delegate = self

        WebPool.shared.onMessage = { [weak self] id, author, text, reply, avatar in
            self?.handleMessage(channelId: id, author: author, text: text, replyTo: reply, avatar: avatar)
        }
        WebPool.shared.onRoute = { [weak self] id, path, title in
            self?.handleRoute(channelId: id, path: path, title: title)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.clickedOutside()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }

        WebPool.shared.sync(model.channels, zoom: model.zoom)
        relayout()
        observeModel()
        panel.orderFrontRegardless()
    }

    // MARK: Layout

    private func observeModel() {
        withObservationTracking {
            _ = (model.mode, model.isSplit, model.paneWidth, model.bodyHeight, model.channels,
                 model.pinned, model.zoom, model.totalUnread)
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.relayout()
                self?.observeModel()
            }
        }
    }

    static func targetScreen() -> NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    @objc private func screensChanged() { relayout() }

    func relayout() {
        WebPool.shared.sync(model.channels, zoom: model.zoom)
        WebPool.shared.setZoom(model.zoom)

        let screen = Self.targetScreen()
        let f = screen.frame
        geo.screenFrame = f
        if screen.safeAreaInsets.top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            geo.hasNotch = true
            geo.notch = CGSize(width: f.width - l.width - r.width, height: screen.safeAreaInsets.top)
        } else {
            geo.hasNotch = false
            geo.notch = CGSize(width: 180, height: max(NSStatusBar.system.thickness, 24))
        }

        let size = layout.windowSize
        var frame: CGRect
        if model.mode == .notch {
            frame = CGRect(x: f.midX - size.width / 2, y: f.maxY - size.height, width: size.width, height: size.height)
            panel.isMovable = false
        } else {
            let vf = (NSScreen.main ?? screen).visibleFrame
            var o = model.floatingOrigin ?? CGPoint(x: vf.maxX - size.width - 12, y: vf.maxY - size.height - 12)
            // keep it on some screen
            let probe = CGRect(origin: o, size: size)
            if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(probe.insetBy(dx: 60, dy: 60)) }) {
                o = CGPoint(x: vf.maxX - size.width - 12, y: vf.maxY - size.height - 12)
            }
            frame = CGRect(origin: o, size: size)
            panel.isMovable = true
        }
        if panel.frame != frame { panel.setFrame(frame, display: true) }

        if model.mode == .floating || model.pinned { setPresence(.expanded) }
        else if lastMode == .floating { setPresence(.collapsed) }
        lastMode = model.mode
        updateMouse()
    }

    private func updateMouse() {
        panel.ignoresMouseEvents = (model.mode == .notch && model.presence != .expanded)
    }

    // MARK: Presence

    func setPresence(_ p: Presence) {
        guard model.presence != p else { updateMouse(); return }
        if p != .peek { peekWork?.cancel() }
        withAnimation(.spring(response: p == .expanded ? 0.42 : 0.36, dampingFraction: p == .collapsed ? 0.9 : 0.78)) {
            model.presence = p
        }
        if p == .expanded { model.clearUnreadForVisible() }
        if p != .expanded { giveBackFocus() }
        updateMouse()
    }

    func expand(focus: Bool = false) {
        setPresence(.expanded)
        if focus { focusComposer() }
    }

    func collapse() {
        guard model.mode == .notch, !model.pinned else { giveBackFocus(); return }
        setPresence(.collapsed)
    }

    func toggleFromHotkey() {
        if model.presence != .expanded { expand(focus: true); return }
        if !panel.isKeyWindow { focusComposer(); return }
        if model.mode == .notch && !model.pinned { collapse() } else { giveBackFocus() }
    }

    func focusComposer() {
        panel.makeKeyAndOrderFront(nil)
        guard let id = model.selected?.id, let web = WebPool.shared.webs[id] else { return }
        panel.makeFirstResponder(web.webView)
        web.focusComposer()
    }

    private func giveBackFocus() {
        guard panel.isKeyWindow else { return }
        if NSApp.isActive { NSApp.deactivate() }
        else { NSWorkspace.shared.frontmostApplication?.activate() }
    }

    private func clickedOutside() {
        guard model.mode == .notch, !model.pinned, model.presence == .expanded else { return }
        collapse()
    }

    // MARK: Hover

    private func screenRect(_ r: CGRect) -> CGRect {
        let wf = panel.frame
        return CGRect(x: wf.minX + r.minX, y: wf.maxY - r.maxY, width: r.width, height: r.height)
    }

    private func tick() {
        guard model.mode == .notch, !model.pinned else { return }
        let p = NSEvent.mouseLocation
        let dt = 0.05
        switch model.presence {
        case .collapsed, .peek:
            var hot = screenRect(layout.shapeRect(model.presence))
            if model.presence == .collapsed {
                // the whole notch plus a little margin
                let n = geo.notch
                hot = CGRect(x: geo.screenFrame.midX - n.width / 2, y: geo.screenFrame.maxY - n.height,
                             width: n.width, height: n.height + 1).union(hot)
            }
            if hot.insetBy(dx: -4, dy: -1).contains(p) {
                dwell += dt
                if dwell >= 0.15 {
                    dwell = 0
                    if model.presence == .peek, let pv = model.preview { model.select(pv.channelId) }
                    expand()
                }
            } else { dwell = 0 }
        case .expanded:
            if panel.isKeyWindow { outside = 0; return }   // user is interacting: close on outside click instead
            if screenRect(layout.shapeRect(.expanded)).insetBy(dx: -8, dy: -8).contains(p) {
                outside = 0
            } else {
                outside += dt
                if outside >= 0.45 { outside = 0; collapse() }
            }
        }
    }

    // MARK: Discord events

    private func handleMessage(channelId: String, author: String, text: String, replyTo: String, avatar: URL?) {
        let visibleNow = model.presence == .expanded && model.visibleIds.contains(channelId)
        if visibleNow { return }
        model.unread[channelId, default: 0] += 1
        guard model.mode == .notch, model.presence != .expanded, !author.isEmpty || !text.isEmpty else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
            model.preview = Preview(channelId: channelId, author: author, text: text, replyTo: replyTo, avatar: avatar)
        }
        setPresence(.peek)
        peekWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.model.presence == .peek else { return }
            self.setPresence(.collapsed)
        }
        peekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private func handleRoute(channelId: String, path: String, title: String) {
        let anyLogin = WebPool.shared.webs.values.contains { $0.path.hasPrefix("/login") || $0.path == "/" }
        if model.needsLogin != anyLogin { model.needsLogin = anyLogin }
    }

    // MARK: NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard model.mode == .floating else { return }
        let o = panel.frame.origin
        if model.floatingOrigin != o { model.floatingOrigin = o }
    }

    func windowDidBecomeKey(_ notification: Notification) { model.keyFocused = true }
    func windowDidResignKey(_ notification: Notification) { model.keyFocused = false }

    // MARK: UI actions

    func goHome(_ id: String) {
        guard let ch = model.channels.first(where: { $0.id == id }) else { return }
        WebPool.shared.webs[id]?.goHome(ch)
    }

    func reload(_ id: String) { WebPool.shared.webs[id]?.webView.reload() }

    func resize(paneWidth: CGFloat, bodyHeight: CGFloat) {
        let maxH = geo.screenFrame.height - 60
        let maxW = (geo.screenFrame.width - 80) / (model.isSplit ? 2 : 1)
        model.paneWidth = min(max(paneWidth, 340), maxW)
        model.bodyHeight = min(max(bodyHeight, 260), maxH)
    }
}
