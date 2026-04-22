import SwiftUI

@main
struct QuietTermApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appModel = AppModel.bootstrap()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .preferredColorScheme(appModel.appearance.colorScheme)
                .onChange(of: scenePhase) { newPhase in
                    appModel.handleScenePhaseChange(newPhase)
                }
        }
    }
}
