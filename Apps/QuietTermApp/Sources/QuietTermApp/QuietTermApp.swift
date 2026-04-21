import SwiftUI

@main
struct QuietTermApp: App {
    @StateObject private var appModel = AppModel.bootstrap()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .preferredColorScheme(appModel.appearance.colorScheme)
        }
    }
}
