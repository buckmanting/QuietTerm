import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            HostLibraryView()
        } detail: {
            TerminalTabsView()
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppModel.bootstrap())
}
