import SwiftUI

@main
struct DeviceInspectorApp: App {
    @StateObject private var health = HealthRunner()
    @StateObject private var bench = BenchStore()
    init() { UIDevice.current.isBatteryMonitoringEnabled = true }
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(health)
                .environmentObject(bench)
                .task { await health.run() }
        }
    }
}
