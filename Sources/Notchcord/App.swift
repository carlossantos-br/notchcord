import AppKit
import Carbon.HIToolbox
import ServiceManagement

// MARK: - Global hotkey (Carbon: no Accessibility permission needed)

final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, user in
            guard let user else { return noErr }
            let hk = Unmanaged<HotKey>.fromOpaque(user).takeUnretainedValue()
            DispatchQueue.main.async { hk.action() }
            return noErr
        }, 1, &spec, me, &handler)
        let id = EventHotKeyID(signature: OSType(0x4E544344), id: 1) // 'NTCD'
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}

// MARK: - Menu bar icon

enum MenuIcon {
    static func make() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 14), flipped: true) { r in
            NSColor.black.setStroke()
            let body = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1.5), xRadius: 3, yRadius: 3)
            body.lineWidth = 1.4
            body.stroke()
            NSColor.black.setFill()
            NSBezierPath(roundedRect: CGRect(x: r.midX - 4.5, y: 1.5, width: 9, height: 4.5), xRadius: 2.25, yRadius: 2.25).fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}

// MARK: - Menu bar menu

final class StatusController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: AppModel
    private let island: IslandController
    private let picker: PickerController

    init(model: AppModel, island: IslandController, picker: PickerController) {
        self.model = model; self.island = island; self.picker = picker
        super.init()
        item.button?.image = MenuIcon.make()
        item.button?.toolTip = "Notchcord"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let showTitle = model.presence == .expanded && model.mode == .notch && !model.pinned
            ? L.t("Collapse island", "Recolher ilha") : L.t("Open island", "Abrir ilha")
        add(menu, showTitle, key: "d", mods: [.control, .option]) { [weak self] in self?.island.toggleFromHotkey() }
        if model.mode == .notch {
            add(menu, L.t("Keep open", "Fixar aberta"), state: model.pinned) { [weak self] in self?.model.pinned.toggle() }
        }
        add(menu, model.mode == .notch ? L.t("Detach as floating window", "Soltar como janela flutuante")
                                        : L.t("Back to the notch", "Voltar para o notch")) { [weak self] in
            guard let self else { return }
            self.model.mode = self.model.mode == .notch ? .floating : .notch
        }
        if model.channels.count >= 2 {
            add(menu, L.t("Two channels side by side", "Dois canais lado a lado"), state: model.split) { [weak self] in self?.model.split.toggle() }
        }
        menu.addItem(.separator())

        if !model.channels.isEmpty {
            let header = NSMenuItem(title: L.t("Channels", "Canais"), action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for ch in model.channels {
                let n = model.unread[ch.id] ?? 0
                let title = ch.label + (ch.guild.isEmpty ? "" : "  —  \(ch.guild)") + (n > 0 ? "  (\(n))" : "")
                let mi = add(menu, title, state: model.visibleIds.contains(ch.id)) { [weak self] in
                    self?.model.select(ch.id); self?.island.expand()
                }
                let sub = NSMenu()
                addTo(sub, L.t("Show", "Mostrar")) { [weak self] in self?.model.select(ch.id); self?.island.expand() }
                addTo(sub, L.t("Back to the channel", "Voltar para o canal")) { [weak self] in self?.island.goHome(ch.id) }
                addTo(sub, L.t("Reload", "Recarregar")) { [weak self] in self?.island.reload(ch.id) }
                sub.addItem(.separator())
                addTo(sub, L.t("Remove from island", "Remover da ilha")) { [weak self] in self?.model.remove(ch.id) }
                mi.submenu = sub
            }
        }
        add(menu, model.channels.count >= AppModel.maxChannels
                 ? L.t("Add channel… (replaces the last one)", "Adicionar canal… (substitui o último)")
                 : L.t("Add channel…", "Adicionar canal…")) { [weak self] in
            self?.picker.show(url: nil)
        }
        add(menu, L.t("Open full Discord (login, servers)…", "Abrir Discord completo (login, servidores)…")) { [weak self] in
            self?.picker.show(url: URL(string: "https://discord.com/channels/@me"))
        }
        menu.addItem(.separator())
        let login = SMAppService.mainApp.status == .enabled
        add(menu, L.t("Open at login", "Abrir ao iniciar o Mac"), state: login) {
            do {
                if login { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
            } catch { NSLog("Notchcord login item: \(error)") }
        }
        menu.addItem(.separator())
        add(menu, L.t("Quit Notchcord", "Sair do Notchcord"), key: "q") { NSApp.terminate(nil) }
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, key: String = "", mods: NSEvent.ModifierFlags = [.command],
                     state: Bool? = nil, _ action: @escaping () -> Void) -> NSMenuItem {
        let mi = addTo(menu, title, key: key, action)
        mi.keyEquivalentModifierMask = mods
        if let state { mi.state = state ? .on : .off }
        return mi
    }

    @discardableResult
    private func addTo(_ menu: NSMenu, _ title: String, key: String = "", _ action: @escaping () -> Void) -> NSMenuItem {
        let mi = ClosureMenuItem(title: title, keyEquivalent: key, action: action)
        menu.addItem(mi)
        return mi
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, keyEquivalent: String, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel.shared
    var island: IslandController!
    var picker: PickerController!
    var status: StatusController!
    var hotKey: HotKey?

    func applicationDidFinishLaunching(_ n: Notification) {
        island = IslandController(model: model)
        picker = PickerController(model: model)
        island.openPicker = { [weak self] url in self?.picker.show(url: url) }
        picker.onAdded = { [weak self] _ in
            self?.island.expand()
        }
        status = StatusController(model: model, island: island, picker: picker)
        hotKey = HotKey(keyCode: kVK_ANSI_D, modifiers: controlKey | optionKey) { [weak self] in
            self?.island.toggleFromHotkey()
        }
        #if DEBUG
        DebugBridge.shared.start(island: island, picker: picker)
        #endif

        if model.channels.isEmpty {
            picker.show(url: nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        island.expand(focus: true)
        return false
    }
}
