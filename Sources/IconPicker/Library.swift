import AppKit
import Observation

struct Icon: Identifiable, Hashable, Sendable {
    let id: String   // path relative to the icons folder
    let name: String
    let group: String
    let url: URL
}

/// The icons folder on disk and everything found in it.
@MainActor @Observable
final class Library {
    static let defaultFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/Vector Icons", isDirectory: true)
    private static let folderKey = "iconsFolder"

    var root: URL?
    var icons: [Icon] = []
    var groups: [String] = []
    var counts: [String: Int] = [:]
    var isLoading = false
    var showDownloader = false
    let downloader = IconDownloader()

    init() { load() }

    /// Folder to use: the one the user picked, the folder holding the app, or Documents › Vector Icons.
    private func resolveRoot() -> URL {
        let fm = FileManager.default
        if let saved = UserDefaults.standard.string(forKey: Self.folderKey),
           fm.fileExists(atPath: saved) {
            return URL(fileURLWithPath: saved, isDirectory: true)
        }
        let beside = Bundle.main.bundleURL.deletingLastPathComponent()
        if IconDownloader.sets.contains(where: { fm.fileExists(atPath: beside.appendingPathComponent($0).path) }) {
            return beside
        }
        return Self.defaultFolder
    }

    func load() {
        let folder = resolveRoot()
        root = folder
        isLoading = true
        Task {
            let found = await Task.detached(priority: .userInitiated) { Self.scan(folder) }.value
            icons = found
            counts = found.reduce(into: [:]) { $0[$1.group, default: 0] += 1 }
            groups = counts.keys.sorted { a, b in
                Self.rank(a) == Self.rank(b) ? a < b : Self.rank(a) < Self.rank(b)
            }
            isLoading = false
        }
    }

    func use(folder: URL) {
        UserDefaults.standard.set(folder.path, forKey: Self.folderKey)
        load()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.message = "Choose a folder that contains SVG icons (subfolders become sets)."
        if let root { panel.directoryURL = root }
        if panel.runModal() == .OK, let url = panel.url { use(folder: url) }
    }

    nonisolated static func scan(_ root: URL) -> [Icon] {
        let fm = FileManager.default
        let base = root.standardizedFileURL.path + "/"
        var list: [Icon] = []
        let walker = fm.enumerator(at: root, includingPropertiesForKeys: nil,
                                   options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension.lowercased() == "svg" else { continue }
            let rel = url.standardizedFileURL.path.replacingOccurrences(of: base, with: "")
            let group = (rel as NSString).deletingLastPathComponent
            list.append(Icon(id: rel, name: url.deletingPathExtension().lastPathComponent,
                             group: group.isEmpty ? "Ungrouped" : group, url: url))
        }
        list.sort { a, b in
            let ra = rank(a.group), rb = rank(b.group)
            if ra != rb { return ra < rb }
            return a.group == b.group ? a.name < b.name : a.group < b.group
        }
        return list
    }

    /// General-purpose sets first, brand logos last, anything else after.
    nonisolated static func rank(_ group: String) -> Int {
        let order = IconDownloader.sets
        return order.firstIndex(of: group.components(separatedBy: "/")[0]) ?? order.count
    }
}
