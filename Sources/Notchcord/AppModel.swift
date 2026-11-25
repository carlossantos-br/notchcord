import AppKit
import Observation

/// A Discord channel pinned to the island.
struct Channel: Codable, Identifiable, Hashable {
    var guildId: String      // "@me" for DMs
    var channelId: String
    var name: String         // "general", "@someone"
    var guild: String        // server name ("" for DMs)

    var id: String { channelId }
    var url: URL { URL(string: "https://discord.com/channels/\(guildId)/\(channelId)")! }

    /// Short tab label: "# general" or "@someone".
    var label: String {
        if guildId == "@me" { return name.hasPrefix("@") ? name : "@\(name)" }
        return "# \(name)"
    }

    /// Extracts (guildId, channelId) from any Discord link or route.
    static func ids(from text: String) -> (String, String)? {
        guard let r = text.range(of: #"/channels/(@me|\d+)/(\d+)"#, options: .regularExpression) else { return nil }
        let parts = text[r].split(separator: "/")
        guard parts.count >= 3 else { return nil }
        return (String(parts[1]), String(parts[2]))
    }
}

enum Mode: String, Codable { case notch, floating }

enum Presence: Equatable { case collapsed, peek, expanded }

struct Preview: Equatable {
    var channelId: String
    var author: String
    var text: String
    var replyTo: String = ""
    var avatar: URL?
    var stamp = UUID()
}

@Observable
final class AppModel {
    static let shared = AppModel()

    // MARK: Persisted
    var channels: [Channel] = [] { didSet { save() } }
    var selectedId: String? { didSet { save() } }
    var secondaryId: String? { didSet { save() } }
    var split = false { didSet { save() } }
    var pinned = false { didSet { save() } }
    var mode: Mode = .notch { didSet { save() } }
    var paneWidth: CGFloat = 440 { didSet { save() } }
    var bodyHeight: CGFloat = 560 { didSet { save() } }
    var floatingOrigin: CGPoint? { didSet { save() } }
    var zoom: Double = 0.9 { didSet { save() } }

    // MARK: Runtime
    var presence: Presence = .collapsed
    var preview: Preview?
    var unread: [String: Int] = [:]
    var needsLogin = false
    var keyFocused = false

    static let maxChannels = 4
    private var loading = true
    private let defaults = UserDefaults.standard

    init() {
        load()
        loading = false
    }

    // MARK: Derived

    var selected: Channel? { channels.first { $0.id == selectedId } ?? channels.first }

    /// Channels on screen (1, or 2 in split mode), in list order.
    var visibleIds: [String] {
        guard let sel = selected?.id else { return [] }
        guard split, channels.count >= 2 else { return [sel] }
        let other = (secondaryId.flatMap { id in channels.contains { $0.id == id } && id != sel ? id : nil })
            ?? channels.first { $0.id != sel }!.id
        return channels.map(\.id).filter { $0 == sel || $0 == other }
    }

    var isSplit: Bool { split && channels.count >= 2 }

    var totalUnread: Int { unread.values.reduce(0, +) }

    // MARK: Actions

    func select(_ id: String) {
        guard id != selectedId else { return }
        if isSplit, visibleIds.contains(id) {
            // already on screen: just move the focus
            secondaryId = selectedId
            selectedId = id
            return
        }
        secondaryId = selected?.id
        selectedId = id
    }

    func add(_ ch: Channel) {
        if let i = channels.firstIndex(where: { $0.id == ch.id }) {
            channels[i] = ch
        } else {
            if channels.count >= Self.maxChannels { channels.removeLast() }
            channels.append(ch)
        }
        select(ch.id)
    }

    func remove(_ id: String) {
        channels.removeAll { $0.id == id }
        unread[id] = nil
        if selectedId == id { selectedId = channels.first?.id }
        if secondaryId == id { secondaryId = nil }
    }

    func clearUnreadForVisible() {
        guard presence == .expanded else { return }
        for id in visibleIds where unread[id] != nil { unread[id] = nil }
    }

    // MARK: Persistence

    private enum K {
        static let channels = "channels", selected = "selected", secondary = "secondary"
        static let split = "split", pinned = "pinned", mode = "mode"
        static let paneWidth = "paneWidth", bodyHeight = "bodyHeight"
        static let floatX = "floatX", floatY = "floatY", zoom = "zoom"
    }

    private func load() {
        if let data = defaults.data(forKey: K.channels),
           let list = try? JSONDecoder().decode([Channel].self, from: data) { channels = list }
        selectedId = defaults.string(forKey: K.selected)
        secondaryId = defaults.string(forKey: K.secondary)
        split = defaults.bool(forKey: K.split)
        pinned = defaults.bool(forKey: K.pinned)
        mode = Mode(rawValue: defaults.string(forKey: K.mode) ?? "") ?? .notch
        if defaults.object(forKey: K.paneWidth) != nil { paneWidth = defaults.double(forKey: K.paneWidth) }
        if defaults.object(forKey: K.bodyHeight) != nil { bodyHeight = defaults.double(forKey: K.bodyHeight) }
        if defaults.object(forKey: K.floatX) != nil {
            floatingOrigin = CGPoint(x: defaults.double(forKey: K.floatX), y: defaults.double(forKey: K.floatY))
        }
        if defaults.object(forKey: K.zoom) != nil { zoom = defaults.double(forKey: K.zoom) }
    }

    private func save() {
        guard !loading else { return }
        if let data = try? JSONEncoder().encode(channels) { defaults.set(data, forKey: K.channels) }
        defaults.set(selectedId, forKey: K.selected)
        defaults.set(secondaryId, forKey: K.secondary)
        defaults.set(split, forKey: K.split)
        defaults.set(pinned, forKey: K.pinned)
        defaults.set(mode.rawValue, forKey: K.mode)
        defaults.set(paneWidth, forKey: K.paneWidth)
        defaults.set(bodyHeight, forKey: K.bodyHeight)
        if let o = floatingOrigin {
            defaults.set(o.x, forKey: K.floatX); defaults.set(o.y, forKey: K.floatY)
        }
        defaults.set(zoom, forKey: K.zoom)
    }
}
