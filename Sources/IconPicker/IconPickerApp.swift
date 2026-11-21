import Combine
import Sparkle
import SwiftUI

@main
struct IconPickerApp: App {
    @State private var library = Library()
    private let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                       userDriverDelegate: nil)

    var body: some Scene {
        WindowGroup("Icon Picker") {
            ContentView()
                .environment(library)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updater.updater)
            }
            CommandGroup(after: .newItem) {
                Button("Choose Icons Folder…") { library.chooseFolder() }
                    .keyboardShortcut("o")
                Button("Download Icon Library…") { library.showDownloader = true }
                Button("Show Icons Folder in Finder") {
                    if let root = library.root { NSWorkspace.shared.activateFileViewerSelecting([root]) }
                }
                .disabled(library.root == nil)
                Divider()
                Button("Reload Icons") { library.load() }
                    .keyboardShortcut("r")
            }
        }
    }
}

/// Publishes Sparkle's `canCheckForUpdates` so the menu item enables and disables correctly.
final class UpdaterState: ObservableObject {
    @Published var canCheckForUpdates = false
    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var state: UpdaterState
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        state = UpdaterState(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!state.canCheckForUpdates)
    }
}
