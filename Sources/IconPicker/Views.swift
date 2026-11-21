import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(Library.self) private var lib
    @State private var selection: String? = "All"
    @State private var query = ""
    @State private var toast: String?
    @State private var toastID = 0
    @AppStorage("mode") private var mode: CopyMode = .vector
    @AppStorage("hex") private var hex = "#000000"
    @AppStorage("size") private var size = 128.0

    private let limit = 3000

    private var filtered: [Icon] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        let group = selection ?? "All"
        return lib.icons.filter { icon in
            (group == "All" || icon.group == group) && words.allSatisfy { icon.name.contains($0) }
        }
    }

    private var tops: [String] {
        var seen: [String] = []
        for g in lib.groups {
            let t = g.components(separatedBy: "/")[0]
            if !seen.contains(t) { seen.append(t) }
        }
        return seen
    }

    var body: some View {
        @Bindable var lib = lib
        NavigationSplitView {
            List(selection: $selection) {
                Label("All icons", systemImage: "square.grid.2x2").tag("All")
                ForEach(tops, id: \.self) { top in
                    Section(top) {
                        ForEach(lib.groups.filter { $0 == top || $0.hasPrefix(top + "/") }, id: \.self) { g in
                            HStack {
                                Text(g == top ? "All" : String(g.dropFirst(top.count + 1)))
                                Spacer()
                                Text("\(lib.counts[g] ?? 0)").foregroundStyle(.secondary).font(.caption)
                            }
                            .tag(g)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            detail
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search icons")
        .toolbar {
            ToolbarItemGroup {
                Picker("Copy as", selection: $mode) {
                    Text("Vector").tag(CopyMode.vector)
                    Text("PNG").tag(CopyMode.png)
                }
                .pickerStyle(.segmented)
                .help("Vector: Affinity, Figma, Keynote, Pages, Illustrator.  PNG: chat apps, Notes, Docs.")
                Picker("Size", selection: $size) {
                    ForEach([24.0, 48, 64, 128, 256, 512, 1024], id: \.self) { Text("\(Int($0)) px").tag($0) }
                }
                .help("Size of the copied icon")
                ColorPicker("Color", selection: Binding(get: { Color(hex: hex) }, set: { hex = $0.hex }),
                            supportsOpacity: false)
                    .help("Icon color (brand-color logos keep their own colors)")
                Button("Black") { hex = "#000000" }
                    .help("Reset color to black")
                    .disabled(hex == "#000000")
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.thickMaterial, in: Capsule())
                    .padding(.bottom, 18)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: toast)
        .frame(minWidth: 820, minHeight: 520)
        .sheet(isPresented: $lib.showDownloader) { DownloadSheet() }
        .onChange(of: lib.groups) { _, groups in
            if let s = selection, s != "All", !groups.contains(s) { selection = "All" }
        }
    }

    @ViewBuilder private var detail: some View {
        if lib.icons.isEmpty {
            if lib.isLoading {
                ProgressView("Loading icons…")
            } else {
                EmptyLibraryView()
            }
        } else {
            let results = filtered
            ScrollView {
                if results.count > limit {
                    Text("Showing \(limit) of \(results.count) icons. Type to narrow it down.")
                        .font(.callout).foregroundStyle(.secondary).padding(.top, 10)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 14) {
                    ForEach(results.prefix(limit)) { icon in
                        Cell(icon: icon, hex: hex, showGroup: selection == "All")
                            .onTapGesture { copy(icon, mode: mode) }
                            .onDrag { NSItemProvider(contentsOf: Render.file(icon, hex: hex)) ?? NSItemProvider() }
                            .contextMenu {
                                Button("Copy as Vector (PDF + SVG)") { copy(icon, mode: .vector) }
                                Button("Copy as PNG") { copy(icon, mode: .png) }
                                Button("Copy SVG Code") {
                                    Clip.copyCode(icon, hex: hex)
                                    flash("Copied SVG code: \(icon.name)")
                                }
                                Button("Copy File") {
                                    Clip.copyFile(icon, hex: hex)
                                    flash("Copied file: \(icon.name).svg")
                                }
                                Divider()
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([icon.url]) }
                            }
                            .help("\(icon.id)\nClick to copy · drag into any app · right-click for more")
                    }
                }
                .padding(16)
            }
            .overlay {
                if results.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .navigationSubtitle("\(results.count) icons · click to copy as \(mode == .vector ? "vector" : "PNG")")
        }
    }

    private func copy(_ icon: Icon, mode: CopyMode) {
        if Clip.copy(icon, mode: mode, hex: hex, size: size) {
            flash("Copied \(icon.name) as \(mode == .vector ? "vector" : "PNG") · \(Int(size)) px — now paste (⌘V)")
        } else {
            flash("Couldn't copy \(icon.name)")
        }
    }

    private func flash(_ message: String) {
        toast = message
        toastID += 1
        let id = toastID
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { if toastID == id { toast = nil } }
    }
}

struct Cell: View {
    let icon: Icon
    let hex: String
    let showGroup: Bool
    @State private var img: NSImage?
    @State private var hover = false

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.white)
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(hover ? Color.accentColor : Color.black.opacity(0.12), lineWidth: hover ? 2 : 1)
                if let img {
                    Image(nsImage: img).resizable().interpolation(.high).scaledToFit().frame(width: 32, height: 32)
                }
            }
            .frame(width: 68, height: 68)
            Text(icon.name).font(.caption).lineLimit(1).truncationMode(.middle)
            if showGroup {
                Text(icon.group).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: 92)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .task(id: hex) { img = Thumbs.shared.get(icon, hex: hex) }
    }
}

struct EmptyLibraryView: View {
    @Environment(Library.self) private var lib

    var body: some View {
        ContentUnavailableView {
            Label("No icons yet", systemImage: "square.grid.3x3.square")
        } description: {
            Text("Download a free library of about 29,000 SVG icons, or point Icon Picker at a folder of your own SVGs.")
        } actions: {
            Button("Download Icon Library…") { lib.showDownloader = true }
                .buttonStyle(.borderedProminent)
            Button("Choose Folder…") { lib.chooseFolder() }
        }
    }
}

struct DownloadSheet: View {
    @Environment(Library.self) private var lib
    @Environment(\.dismiss) private var dismiss
    @State private var target: URL?

    var body: some View {
        let d = lib.downloader
        let folder = target ?? lib.root ?? Library.defaultFolder
        VStack(alignment: .leading, spacing: 14) {
            Text("Download Icon Library").font(.title2.bold())
            Text("Gets the latest Lucide, Phosphor, Tabler, Heroicons, Remix Icon and Simple Icons sets from the npm registry (about 29,000 SVGs, 25 MB) and sorts them into folders. Sets already in the folder are replaced with the newest version.")
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
            HStack {
                Image(systemName: "folder")
                Text(folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Change…") { pick(from: folder) }.disabled(d.isRunning)
            }
            if d.isRunning || d.progress > 0 {
                ProgressView(value: d.progress) { Text(d.status).font(.callout) }
            }
            if let error = d.error {
                Text(error).foregroundStyle(.red).font(.callout)
            }
            Text("All sets are free for personal and commercial use (MIT, ISC, Apache 2.0, CC0).")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(d.progress >= 1 && !d.isRunning ? "Done" : "Cancel") { dismiss() }
                    .disabled(d.isRunning)
                Button("Download") {
                    d.run(into: folder) { lib.use(folder: folder) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(d.isRunning)
            }
        }
        .padding(22)
        .frame(width: 520)
    }

    private func pick(from folder: URL) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = folder
        if panel.runModal() == .OK, let url = panel.url { target = url }
    }
}
