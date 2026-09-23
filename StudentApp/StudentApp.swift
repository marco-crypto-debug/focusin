import SwiftUI

@main
struct StudentApp: App {
    @StateObject private var listener = CommandListener()

    var body: some Scene {
        WindowGroup {
            StatusView()
                .environmentObject(listener)
                .frame(minWidth: 460, minHeight: 360)
        }
    }
}
