import Foundation
import Observation

/// Downloads the free icon sets from the npm registry and sorts them into folders.
@MainActor @Observable
final class IconDownloader {
    /// Top-level folder names, in sidebar order.
    nonisolated static let sets = ["Lucide", "Phosphor", "Tabler", "Heroicons", "Remix", "Brand Logos"]

    struct Package: Sendable {
        let npm: String
        let set: String
    }

    nonisolated static let packages = [
        Package(npm: "lucide-static", set: "Lucide"),
        Package(npm: "@phosphor-icons/core", set: "Phosphor"),
        Package(npm: "@tabler/icons", set: "Tabler"),
        Package(npm: "heroicons", set: "Heroicons"),
        Package(npm: "remixicon", set: "Remix"),
        Package(npm: "simple-icons", set: "Brand Logos"),
    ]

    var isRunning = false
    var status = ""
    var progress = 0.0
    var error: String?

    func run(into root: URL, completion: @escaping @MainActor () -> Void) {
        guard !isRunning else { return }
        isRunning = true
        error = nil
        progress = 0
        Task {
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                for (i, pkg) in Self.packages.enumerated() {
                    status = "Downloading \(pkg.set)…"
                    let version = try await Self.install(pkg, into: root)
                    status = "\(pkg.set) \(version) ready"
                    progress = Double(i + 1) / Double(Self.packages.count)
                }
                status = "All sets downloaded."
            } catch {
                self.error = error.localizedDescription
            }
            isRunning = false
            completion()
        }
    }

    // MARK: - Work (off the main actor)

    enum Failure: LocalizedError {
        case badResponse(String), extract(String), layout(String)
        var errorDescription: String? {
            switch self {
            case .badResponse(let s): "Couldn't download \(s). Check your internet connection."
            case .extract(let s): "Couldn't unpack \(s)."
            case .layout(let s): "\(s) changed its file layout; this set was skipped."
            }
        }
    }

    /// Downloads one package, organizes it into `root/<set>`, and returns the version installed.
    nonisolated static func install(_ pkg: Package, into root: URL) async throws -> String {
        let fm = FileManager.default
        let encoded = pkg.npm.replacingOccurrences(of: "/", with: "%2F")
        let metaURL = URL(string: "https://registry.npmjs.org/\(encoded)/latest")!
        let (metaData, metaResponse) = try await URLSession.shared.data(from: metaURL)
        guard (metaResponse as? HTTPURLResponse)?.statusCode == 200,
              let meta = try JSONSerialization.jsonObject(with: metaData) as? [String: Any],
              let version = meta["version"] as? String,
              let dist = meta["dist"] as? [String: Any],
              let tarball = (dist["tarball"] as? String).flatMap(URL.init(string:)),
              tarball.host == "registry.npmjs.org"
        else { throw Failure.badResponse(pkg.npm) }

        let (tgz, response) = try await URLSession.shared.download(from: tarball)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.badResponse(pkg.npm) }

        let work = fm.temporaryDirectory.appendingPathComponent("IconPicker-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        try untar(tgz, into: work, name: pkg.npm)
        try? fm.removeItem(at: tgz)

        let src = work.appendingPathComponent("package", isDirectory: true)
        let staged = work.appendingPathComponent("out", isDirectory: true)
        try organize(pkg.set, from: src, into: staged)

        let dest = root.appendingPathComponent(pkg.set, isDirectory: true)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: staged, to: dest)
        copyLicenses(from: src, set: pkg.set, into: root.appendingPathComponent("Licenses", isDirectory: true))
        return version
    }

    nonisolated static func untar(_ file: URL, into dir: URL, name: String) throws {
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xzf", file.path, "-C", dir.path]
        try tar.run()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0 else { throw Failure.extract(name) }
    }

    nonisolated static func organize(_ set: String, from src: URL, into out: URL) throws {
        func dir(_ path: String) -> URL { src.appendingPathComponent(path, isDirectory: true) }
        var copied = 0
        func copy(_ from: URL, _ to: String, keep: (String) -> Bool = { _ in true },
                  rename: (String) -> String = { $0 }, edit: (String, String) -> String = { s, _ in s }) {
            let dest = out.appendingPathComponent(to, isDirectory: true)
            try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            let files = (try? FileManager.default.contentsOfDirectory(at: from, includingPropertiesForKeys: nil)) ?? []
            for f in files where f.pathExtension == "svg" {
                let stem = f.deletingPathExtension().lastPathComponent
                guard keep(stem), var s = try? String(contentsOf: f, encoding: .utf8) else { continue }
                s = edit(s.replacingOccurrences(of: "currentColor", with: "#000000"), stem)
                let target = dest.appendingPathComponent(rename(stem) + ".svg")
                if (try? s.write(to: target, atomically: false, encoding: .utf8)) != nil { copied += 1 }
            }
        }

        switch set {
        case "Lucide":
            // lucide-static also ships alias files; keep only the canonical names listed in tags.json.
            let tags = (try? Data(contentsOf: src.appendingPathComponent("tags.json")))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let names = Set(tags?.keys.map { $0 } ?? [])
            copy(dir("icons"), "", keep: { names.isEmpty || names.contains($0) })
        case "Phosphor":
            for w in ["thin", "light", "regular", "bold", "fill", "duotone"] {
                copy(dir("assets/\(w)"), w.capitalized, rename: { $0.hasSuffix("-\(w)") ? String($0.dropLast(w.count + 1)) : $0 })
            }
        case "Tabler":
            copy(dir("icons/outline"), "Outline")
            copy(dir("icons/filled"), "Filled")
        case "Heroicons":
            copy(dir("24/outline"), "Outline 24px")
            copy(dir("24/solid"), "Solid 24px")
            copy(dir("20/solid"), "Mini 20px")
            copy(dir("16/solid"), "Micro 16px")
        case "Remix":
            let cats = (try? FileManager.default.contentsOfDirectory(at: dir("icons"), includingPropertiesForKeys: nil)) ?? []
            for c in cats where c.hasDirectoryPath { copy(c, c.lastPathComponent) }
        case "Brand Logos":
            copy(dir("icons"), "Black")
            var hexes: [String: String] = [:]
            for path in ["data/simple-icons.json", "_data/simple-icons.json"] {
                guard let data = try? Data(contentsOf: src.appendingPathComponent(path)),
                      let json = try? JSONSerialization.jsonObject(with: data) else { continue }
                let list = (json as? [[String: Any]]) ?? ((json as? [String: Any])?["icons"] as? [[String: Any]]) ?? []
                for entry in list {
                    if let slug = entry["slug"] as? String, let hex = entry["hex"] as? String { hexes[slug] = hex }
                }
                break
            }
            if !hexes.isEmpty {
                copy(dir("icons"), "Brand Color", keep: { hexes[$0] != nil }, edit: { s, stem in
                    s.replacingOccurrences(of: "<path ", with: "<path fill=\"#\(hexes[stem] ?? "000000")\" ",
                                           options: [], range: s.range(of: "<path "))
                })
            }
        default:
            break
        }

        // Drop empty folders left by a changed layout.
        if let subs = try? FileManager.default.contentsOfDirectory(at: out, includingPropertiesForKeys: nil) {
            for d in subs where d.hasDirectoryPath {
                if (try? FileManager.default.contentsOfDirectory(atPath: d.path))?.isEmpty ?? true {
                    try? FileManager.default.removeItem(at: d)
                }
            }
        }
        if copied == 0 { throw Failure.layout(set) }
    }

    nonisolated static func copyLicenses(from src: URL, set: String, into dir: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let files = (try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)) ?? []
        for f in files {
            let name = f.lastPathComponent.lowercased()
            guard name.hasPrefix("license") || name.hasPrefix("licence") || name.hasPrefix("disclaimer") else { continue }
            let ext = f.pathExtension.isEmpty ? "txt" : f.pathExtension
            let kind = name.hasPrefix("disclaimer") ? "DISCLAIMER" : "LICENSE"
            let target = dir.appendingPathComponent("\(set)-\(kind).\(ext)")
            try? fm.removeItem(at: target)
            try? fm.copyItem(at: f, to: target)
        }
    }
}
