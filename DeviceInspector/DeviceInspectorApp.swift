import SwiftUI

@main
struct DeviceInspectorApp: App {
    @StateObject private var health = HealthRunner()
    @StateObject private var bench = BenchStore()
    @StateObject private var settings = AppSettings()
    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        UserDefaults.standard.register(defaults: ["keepAwakeDuringTests": true, "hapticFeedback": true, "autoRunHealthOnLaunch": true])
    }
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(health)
                .environmentObject(bench)
                .environmentObject(settings)
                .tint(settings.accent.color)
                .preferredColorScheme(settings.appearance.colorScheme)
                .task { if settings.autoRunHealthOnLaunch { await health.run() } }
        }
    }
}
