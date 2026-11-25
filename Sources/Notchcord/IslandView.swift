import SwiftUI
import AppKit
import WebKit

let blurple = Color(red: 0.345, green: 0.396, blue: 0.949)

struct IslandView: View {
    var model: AppModel
    var geo: IslandGeo
    let controller: IslandController

    var body: some View {
        let L = IslandLayout(m: model, g: geo)
        let p = model.presence
        let shape = L.shapeRect(p)
        let expanded = p == .expanded
        let showShape = !(p == .collapsed && model.totalUnread == 0 && !geo.hasNotch)

        ZStack(alignment: .topLeading) {
            // black shape
            Group {
                if L.notchMode {
                    NotchShape(ear: L.ear(p), bottom: L.bottomRadius(p)).fill(Color.black)
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                }
            }
            .shadow(color: .black.opacity(expanded || p == .peek ? 0.45 : 0), radius: 16, y: 6)
            .frame(width: shape.width, height: shape.height)
            .offset(x: shape.minX, y: shape.minY)
            .opacity(showShape ? 1 : 0)

            // web views (always in the window so Discord keeps running)
            WebStageView(stage: controller.stage, model: model, shown: expanded && !model.channels.isEmpty)
                .frame(width: L.stageRect.width, height: L.stageRect.height)
                .offset(x: L.stageRect.minX, y: L.stageRect.minY)
                .allowsHitTesting(expanded)

            if expanded {
                TopBar(model: model, layout: L, controller: controller)
                    .frame(width: L.topBarRect.width, height: L.topBarRect.height)
                    .offset(x: L.topBarRect.minX, y: L.topBarRect.minY)
                    .transition(.opacity.animation(.easeOut(duration: 0.18).delay(0.08)))

                overlays(L)
                    .frame(width: L.stageRect.width, height: L.stageRect.height)
                    .offset(x: L.stageRect.minX, y: L.stageRect.minY)
                    .transition(.opacity.animation(.easeOut(duration: 0.18).delay(0.1)))

                ResizeGrip(controller: controller, model: model, notchMode: L.notchMode)
                    .frame(width: 18, height: 18)
                    .offset(x: L.bodyRect.maxX - 20, y: L.bodyRect.maxY - 20)
                    .transition(.opacity)
            }

            if p == .peek, let pv = model.preview {
                PeekView(preview: pv, channel: model.channels.first { $0.id == pv.channelId })
                    .frame(width: shape.width - 2 * IslandLayout.ear - 24, height: IslandLayout.peekExtra)
                    .offset(x: shape.minX + IslandLayout.ear + 12, y: L.topH - 2)
                    .transition(.opacity.animation(.easeOut(duration: 0.2).delay(0.1)))
            }

            if p == .collapsed && model.totalUnread > 0 {
                CollapsedWings(count: model.totalUnread, notchWidth: geo.notch.width + 8)
                    .frame(width: shape.width - 2 * IslandLayout.ear, height: shape.height)
                    .offset(x: shape.minX + IslandLayout.ear, y: 0)
                    .transition(.opacity.animation(.easeOut(duration: 0.2).delay(0.12)))
            }
        }
        .frame(width: L.windowSize.width, height: L.windowSize.height, alignment: .topLeading)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func overlays(_ lay: IslandLayout) -> some View {
        if model.channels.isEmpty {
            EmptyState(icon: "bubble.left.and.bubble.right.fill",
                       title: L.t("No channels on the island yet", "Nenhum canal na ilha ainda"),
                       subtitle: L.t("Pick up to \(AppModel.maxChannels) channels. They stay live right here in the notch.",
                                   "Escolha até \(AppModel.maxChannels) canais. Eles ficam vivos aqui no notch."),
                       button: L.t("Choose channel", "Escolher canal")) { controller.openPicker?(nil) }
        } else if model.needsLogin {
            EmptyState(icon: "person.crop.circle.badge.questionmark",
                       title: L.t("Log in to Discord", "Entre no Discord"),
                       subtitle: L.t("Your session is stored only on this Mac, inside Notchcord.",
                                   "O login fica salvo só neste Mac, dentro do Notchcord."),
                       button: L.t("Log in", "Entrar")) { controller.openPicker?(URL(string: "https://discord.com/login")) }
        }
    }
}

// MARK: - Top bar

struct TopBar: View {
    var model: AppModel
    let layout: IslandLayout
    let controller: IslandController

    var body: some View {
        HStack(spacing: 0) {
            ChannelTabs(model: model, controller: controller, maxWidth: layout.notchMode ? layout.wingW : layout.bodyW * 0.62)
                .frame(width: layout.notchMode ? layout.wingW : nil, alignment: .leading)
                .padding(.leading, 12)
            Spacer(minLength: layout.notchGap)
            Controls(model: model, controller: controller, notchMode: layout.notchMode)
                .padding(.trailing, 12)
        }
        .frame(maxHeight: .infinity)
        .background(layout.notchMode ? nil : DragArea())
    }
}

struct ChannelTabs: View {
    var model: AppModel
    let controller: IslandController
    let maxWidth: CGFloat

    var body: some View {
        let fits = CGFloat(model.channels.count) * 96 <= maxWidth
        if model.channels.isEmpty {
            Text("Notchcord").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
        } else if fits {
            HStack(spacing: 4) {
                ForEach(model.channels) { ch in
                    TabPill(channel: ch, model: model, controller: controller)
                }
            }
        } else {
            Menu {
                ForEach(model.channels) { ch in
                    Button {
                        model.select(ch.id)
                    } label: {
                        let n = model.unread[ch.id] ?? 0
                        Text(n > 0 ? "\(ch.label)  ·  \(n) \(L.t("new", "nova(s)"))" : ch.label)
                    }
                }
                Divider()
                Button(L.t("Add channel…", "Adicionar canal…")) { controller.openPicker?(nil) }
            } label: {
                HStack(spacing: 5) {
                    Text(model.selected?.label ?? L.t("Channels", "Canais")).lineLimit(1)
                    if model.totalUnread > 0 { Badge(count: model.totalUnread) }
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).opacity(0.6)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

struct TabPill: View {
    let channel: Channel
    var model: AppModel
    let controller: IslandController
    @State private var hover = false

    var body: some View {
        let isSel = model.selected?.id == channel.id
        let onScreen = model.visibleIds.contains(channel.id)
        let n = model.unread[channel.id] ?? 0
        Button {
            withAnimation(.easeOut(duration: 0.15)) { model.select(channel.id) }
            model.clearUnreadForVisible()
        } label: {
            HStack(spacing: 4) {
                Text(channel.label)
                    .lineLimit(1).truncationMode(.tail)
                if n > 0 { Badge(count: n) }
            }
            .font(.system(size: 11.5, weight: isSel ? .semibold : .medium))
            .foregroundStyle(.white.opacity(onScreen ? 1 : 0.6))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .frame(maxWidth: 140)
            .background(Capsule().fill(Color.white.opacity(isSel ? 0.16 : (hover ? 0.08 : 0))))
            .overlay(Capsule().strokeBorder(Color.white.opacity(onScreen && !isSel ? 0.12 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(channel.guild.isEmpty ? channel.label : "\(channel.label) — \(channel.guild)")
        .contextMenu {
            Button(L.t("Back to \(channel.label)", "Voltar para \(channel.label)")) { controller.goHome(channel.id) }
            Button(L.t("Reload", "Recarregar")) { controller.reload(channel.id) }
            Divider()
            Button(L.t("Remove from island", "Remover da ilha"), role: .destructive) { model.remove(channel.id) }
        }
    }
}

struct Badge: View {
    let count: Int
    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 9.5, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 5).frame(minWidth: 16, minHeight: 16)
            .background(Capsule().fill(Color(red: 0.93, green: 0.26, blue: 0.27)))
    }
}

struct Controls: View {
    var model: AppModel
    let controller: IslandController
    let notchMode: Bool

    var body: some View {
        HStack(spacing: 2) {
            if notchMode {
                IconButton(symbol: model.pinned ? "pin.fill" : "pin",
                           help: model.pinned ? L.t("Unpin (open on hover only)", "Desafixar (volta a abrir só no hover)")
                                              : L.t("Keep open", "Fixar aberta"),
                           active: model.pinned) { model.pinned.toggle() }
            }
            if model.channels.count >= 2 {
                IconButton(symbol: model.split ? "rectangle.split.2x1.fill" : "rectangle.split.2x1",
                           help: model.split ? L.t("One channel at a time", "Um canal por vez")
                                             : L.t("Two channels side by side", "Dois canais lado a lado"),
                           active: model.split) { model.split.toggle() }
            }
            IconButton(symbol: notchMode ? "pip.exit" : "menubar.dock.rectangle",
                       help: notchMode ? L.t("Detach as floating window", "Soltar como janela flutuante")
                                       : L.t("Back to the notch", "Voltar para o notch"),
                       active: false) {
                model.mode = notchMode ? .floating : .notch
            }
            IconButton(symbol: "plus", help: L.t("Add channel", "Adicionar canal"), active: false) { controller.openPicker?(nil) }
            Menu {
                Button(L.t("Larger text", "Aumentar texto")) { model.zoom = min(model.zoom + 0.05, 1.4) }
                Button(L.t("Smaller text", "Diminuir texto")) { model.zoom = max(model.zoom - 0.05, 0.6) }
                Button(L.t("Default size", "Tamanho padrão")) { model.zoom = 0.9 }
                Divider()
                if let sel = model.selected {
                    Button(L.t("Back to \(sel.label)", "Voltar para \(sel.label)")) { controller.goHome(sel.id) }
                    Button(L.t("Reload", "Recarregar")) { controller.reload(sel.id) }
                    Button(L.t("Remove \(sel.label) from island", "Remover \(sel.label) da ilha"), role: .destructive) { model.remove(sel.id) }
                    Divider()
                }
                Button(L.t("Quit Notchcord", "Sair do Notchcord")) { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.white.opacity(0.75))
        }
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let active: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(active ? blurple.opacity(1) : .white.opacity(hover ? 1 : 0.72))
                .frame(width: 24, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(hover ? 0.1 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

// MARK: - Peek / wings

struct PeekView: View {
    let preview: Preview
    let channel: Channel?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AsyncImage(url: preview.avatar) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    Circle().fill(blurple)
                    Text(String(preview.author.prefix(1)).uppercased())
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(preview.author.isEmpty ? L.t("New message", "Nova mensagem") : preview.author)
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                        .lineLimit(1)
                    if !preview.replyTo.isEmpty {
                        Label(preview.replyTo, systemImage: "arrowshape.turn.up.left.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                            .labelStyle(.titleAndIcon)
                    }
                    if let ch = channel {
                        Text(ch.label).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                    }
                }
                Text(preview.text)
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }
}

struct CollapsedWings: View {
    let count: Int
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(blurple)
                .frame(maxWidth: .infinity)
            Color.clear.frame(width: notchWidth)
            Badge(count: count)
                .frame(maxWidth: .infinity)
        }
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    let button: String
    let action: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.07))
            VStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 30, weight: .medium)).foregroundStyle(blurple)
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center).frame(maxWidth: 280)
                Button(action: action) {
                    Text(button).font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Capsule().fill(blurple))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - AppKit: web views, dragging, resizing

/// Holds every web view; off-screen ones are stacked behind (still live, never throttled).
final class WebStage: NSView {
    private var visible: [String] = []
    private var shownToken = 0

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        alphaValue = 0
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(visible ids: [String]) {
        let webs = WebPool.shared.webs
        let all = webs.mapValues(\.webView)
        let back = all.filter { !ids.contains($0.key) }.sorted { $0.key < $1.key }.map(\.value)
        let front = ids.compactMap { all[$0] }
        let desired: [NSView] = back + front
        if subviews != desired { subviews = desired }
        visible = ids
        needsLayout = true
    }

    func setShown(_ shown: Bool) {
        shownToken += 1
        let token = shownToken
        if shown {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self, self.shownToken == token else { return }
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    self.animator().alphaValue = 1
                }
            }
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.08
                self.animator().alphaValue = 0
            }
        }
    }

    override func layout() {
        super.layout()
        let n = CGFloat(max(visible.count, 1))
        let gap = IslandLayout.gap
        let w = (bounds.width - gap * (n - 1)) / n
        var frames: [String: CGRect] = [:]
        for (i, id) in visible.enumerated() {
            frames[id] = CGRect(x: CGFloat(i) * (w + gap), y: 0, width: w, height: bounds.height)
        }
        let first = frames[visible.first ?? ""] ?? CGRect(x: 0, y: 0, width: w, height: bounds.height)
        for (id, web) in WebPool.shared.webs where web.webView.superview === self {
            let wv = web.webView
            wv.frame = frames[id] ?? first
            wv.wantsLayer = true
            wv.layer?.cornerRadius = 14
            wv.layer?.cornerCurve = .continuous
            wv.layer?.masksToBounds = true
        }
    }
}

struct WebStageView: NSViewRepresentable {
    let stage: WebStage
    var model: AppModel
    let shown: Bool

    func makeNSView(context: Context) -> WebStage { stage }

    func updateNSView(_ v: WebStage, context: Context) {
        WebPool.shared.sync(model.channels, zoom: model.zoom)
        v.update(visible: model.visibleIds)
        v.setShown(shown)
    }
}

/// Drag area for the floating window.
struct DragArea: NSViewRepresentable {
    final class V: NSView {
        override func mouseDown(with e: NSEvent) { window?.performDrag(with: e) }
        override var mouseDownCanMoveWindow: Bool { true }
    }
    func makeNSView(context: Context) -> V { V() }
    func updateNSView(_ v: V, context: Context) {}
}

/// Resize grip (uses screen coordinates: stable while the window itself is resizing).
struct ResizeGrip: NSViewRepresentable {
    let controller: IslandController
    var model: AppModel
    let notchMode: Bool

    final class V: NSView {
        var onDrag: ((CGFloat, CGFloat, Bool) -> Void)?
        private var start = CGPoint.zero
        override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
        override func mouseDown(with e: NSEvent) { start = NSEvent.mouseLocation; onDrag?(0, 0, true) }
        override func mouseDragged(with e: NSEvent) {
            let p = NSEvent.mouseLocation
            onDrag?(p.x - start.x, start.y - p.y, false)
        }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.white.withAlphaComponent(0.35).setStroke()
            for o in [CGFloat(0), 5] {
                let p = NSBezierPath()
                p.move(to: CGPoint(x: bounds.maxX - 4, y: 6 + o))
                p.line(to: CGPoint(x: 6 + o, y: bounds.maxY - 4))
                p.lineWidth = 1.3
                p.lineCapStyle = .round
                p.stroke()
            }
        }
        override var isFlipped: Bool { true }
    }

    func makeNSView(context: Context) -> V {
        let v = V()
        var w0: CGFloat = 0, h0: CGFloat = 0, origin0 = CGPoint.zero
        v.onDrag = { dx, dy, began in
            if began {
                w0 = model.paneWidth; h0 = model.bodyHeight
                origin0 = controller.panel.frame.origin
                return
            }
            let panes: CGFloat = model.isSplit ? 2 : 1
            if notchMode {
                // grow symmetrically from the notch center
                controller.resize(paneWidth: w0 + 2 * dx / panes, bodyHeight: h0 + dy)
            } else {
                controller.resize(paneWidth: w0 + dx / panes, bodyHeight: h0 + dy)
                // keep the top-left corner in place
                let newH = IslandLayout(m: model, g: controller.geo).windowSize.height
                let top = origin0.y + (h0 + 2 * IslandLayout.fpad)
                model.floatingOrigin = CGPoint(x: origin0.x, y: top - newH)
            }
        }
        return v
    }
    func updateNSView(_ v: V, context: Context) {}
}
