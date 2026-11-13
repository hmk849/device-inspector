import SwiftUI

@main
struct DeviceInspectorApp: App {
    @StateObject private var store = InspectorStore()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
