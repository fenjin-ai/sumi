import LeftBlankCore
import SwiftUI

@main
struct LeftBlankApp: App {
    @StateObject private var workspace = TabletWorkspace()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            TabletRoot(workspace: workspace)
                .task { await workspace.start() }
                .onOpenURL { url in Task { await workspace.importDocument(url) } }
                .onChange(of: phase) { _, phase in
                    if phase != .active {
                        workspace.saveInBackground()
                    }
                }
        }
    }
}
