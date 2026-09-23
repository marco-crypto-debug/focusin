import SwiftUI

@main
struct TeacherApp: App {
    @StateObject private var viewModel = TeacherViewModel()

    var body: some Scene {
        WindowGroup {
            DeviceListView()
                .environmentObject(viewModel)
                .frame(minWidth: 760, minHeight: 480)
        }
    }
}
