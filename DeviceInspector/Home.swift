import SwiftUI

struct Feature: Identifiable {
    let id: String; let title: String; let icon: String
    let make: () -> AnyView
}
struct Category: Identifiable {
    let id: String; let title: String; let icon: String; let tint: Color; let features: [Feature]
}

@MainActor enum Catalog {
    static func info(_ title: String, _ sections: [(String, () -> [InfoItem])], every: Double? = nil, extra: AnyView? = nil) -> AnyView {
        AnyView(InfoPage(title: title, sections: sections, every: every, extra: extra))
    }
    static var perfFeatures: [Feature] {
        var r: [Feature] = []
        for k in BenchKind.allCases {
            r.append(Feature(id: k.rawValue, title: k.title, icon: k.icon) { k == .fps ? AnyView(FPSPage()) : AnyView(BenchPage(kind: k)) })
        }
        r.append(Feature(id: "thermal", title: L.t("温度与热状态", "Thermal"), icon: "thermometer.medium") { AnyView(ThermalPage()) })
        r.append(Feature(id: "total", title: L.t("综合性能评分", "Overall score"), icon: "gauge.with.dots.needle.67percent") { AnyView(TotalPerfPage()) })
        return r
    }
    static var sensorFeatures: [Feature] {
        var r: [Feature] = []
        for k in [SensorKind.accel, .gyro, .mag] {
            r.append(Feature(id: k.rawValue, title: k.title, icon: k.icon) { AnyView(SensorPage(kind: k)) })
        }
        r.append(Feature(id: "compass", title: L.t("指南针", "Compass"), icon: "location.north.line") { AnyView(CompassPage()) })
        r.append(Feature(id: "baro", title: SensorKind.baro.title, icon: SensorKind.baro.icon) { AnyView(SensorPage(kind: .baro)) })
        r.append(Feature(id: "light", title: L.t("光线传感器", "Light sensor"), icon: "sun.max") { lightPage() })
        return r
    }
    static func lightPage() -> AnyView {
        let b = Info.screen.map { String(format: "%.0f%%", $0.brightness * 100) }
        return info(L.t("光线传感器", "Light sensor"), [("", {
            [InfoItem(L.t("环境光传感器读数", "Ambient light reading"), nil),
             InfoItem(L.t("屏幕亮度设置（用户设置，非传感器）", "Screen brightness setting (user value, not sensor)"), b)]
        })])
    }
    static var all: [Category] {
        [
        Category(id: "device", title: L.t("设备信息", "Device"), icon: "iphone", tint: .blue, features: [
            Feature(id: "overview", title: L.t("设备概览", "Overview"), icon: "iphone") { info(L.t("设备概览", "Overview"), [("", { Info.device() }), (L.t("系统", "System"), { Info.system() })]) },
            Feature(id: "cpu", title: "CPU", icon: "cpu") { info("CPU", [("", { Info.cpu() })]) },
            Feature(id: "gpu", title: L.t("GPU 与屏幕", "GPU & Display"), icon: "display") { info(L.t("GPU 与屏幕", "GPU & Display"), [("GPU", { Info.gpu() }), (L.t("屏幕", "Display"), { Info.display() })]) },
            Feature(id: "mem", title: L.t("内存", "Memory"), icon: "memorychip") {
                info(L.t("内存", "Memory"), [("", { Info.memory() })], every: 1,
                     extra: AnyView(LiveChart(title: L.t("本 App 内存占用", "App footprint"), unit: "MB") { Double(Sys.appFootprint()) / 1_048_576 }))
            },
            Feature(id: "storage", title: L.t("存储", "Storage"), icon: "internaldrive") { AnyView(StoragePage()) },
        ]),
        Category(id: "hardware", title: L.t("硬件检测", "Hardware"), icon: "wrench.and.screwdriver", tint: .orange, features: [
            Feature(id: "power", title: L.t("功率与温度监测", "Power & Thermal"), icon: "bolt.fill") { AnyView(PowerPage()) },
            Feature(id: "battery", title: L.t("电池", "Battery"), icon: "battery.100") { AnyView(BatteryPage()) },
            Feature(id: "camera", title: L.t("摄像头", "Cameras"), icon: "camera") { AnyView(CameraPage()) },
            Feature(id: "audio", title: L.t("麦克风与扬声器", "Mic & Speaker"), icon: "mic") { AnyView(AudioPage()) },
            Feature(id: "touch", title: L.t("触摸屏 / 多点触控", "Touch / Multi-touch"), icon: "hand.tap") { AnyView(TouchPage()) },
            Feature(id: "bio", title: "Face ID / Touch ID", icon: "faceid") { AnyView(BiometricPage()) },
            Feature(id: "gps", title: "GPS", icon: "location") { AnyView(GPSPage()) },
            Feature(id: "haptic", title: L.t("振动马达", "Haptics"), icon: "waveform") { AnyView(HapticPage()) },
        ]),
        Category(id: "network", title: L.t("网络检测", "Network"), icon: "wifi", tint: .green, features: [
            Feature(id: "status", title: L.t("连接状态", "Connection"), icon: "network") { AnyView(NetStatusPage()) },
            Feature(id: "speed", title: L.t("延迟与速度", "Latency & Speed"), icon: "speedometer") { AnyView(NetSpeedPage(stability: false)) },
            Feature(id: "stab", title: L.t("网络稳定性", "Stability"), icon: "chart.xyaxis.line") { AnyView(NetSpeedPage(stability: true)) },
        ]),
        Category(id: "perf", title: L.t("性能测试", "Performance"), icon: "bolt.fill", tint: .red, features: perfFeatures),
        Category(id: "system", title: L.t("系统检测", "System"), icon: "gearshape.2", tint: .purple, features: [
            Feature(id: "sys", title: L.t("系统与状态", "System & status"), icon: "info.circle") { info(L.t("系统与状态", "System & status"), [("", { Info.system() })], every: 5) },
            Feature(id: "perm", title: L.t("权限状态", "Permissions"), icon: "hand.raised") { AnyView(PermissionsPage()) },
            Feature(id: "feat", title: L.t("可用系统功能", "Capabilities"), icon: "checklist") { info(L.t("可用系统功能", "Capabilities"), [("", { Info.features() })]) },
        ]),
        Category(id: "sensors", title: L.t("传感器实时测试", "Sensors"), icon: "sensor.tag.radiowaves.forward", tint: .teal, features: sensorFeatures),
        ]
    }
}

struct CategoryPage: View {
    let cat: Category
    var body: some View {
        Page(cat.title) {
            VStack(spacing: 10) {
                ForEach(Array(cat.features.enumerated()), id: \.element.id) { i, f in
                    NavigationLink { f.make() } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(cat.tint.opacity(0.16)).frame(width: 38, height: 38)
                                Image(systemName: f.icon).font(.subheadline).foregroundStyle(cat.tint)
                            }
                            Text(f.title).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }.padding(14)
                    }.buttonStyle(.plain)
                    if i < cat.features.count - 1 { Divider().padding(.leading, 66) }
                }
            }.padding(.vertical, 2).glassCard(radius: 22)
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var health: HealthRunner
    @EnvironmentObject var bench: BenchStore
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.t("检测类别", "Categories")).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 6)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                            ForEach(Catalog.all) { c in
                                NavigationLink { CategoryPage(cat: c) } label: { CategoryCard(cat: c) }.buttonStyle(.plain)
                            }
                        }
                    }
                    Text(L.t("仅使用 Apple 公开 API · 不上传任何个人数据 · 无法读取的项目会明确标注", "Apple public APIs only · no personal data uploaded · unavailable items are clearly marked"))
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
                }.padding(.horizontal).padding(.top, 8).padding(.bottom, 28)
            }
            .background(Backdrop())
            .navigationTitle("Device Inspector")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsPage() } label: { Image(systemName: "gearshape.fill") }
                }
            }
        }
    }
    var header: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(settings.accent.color.gradient).frame(width: 56, height: 56)
                    Image(systemName: UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone.gen3")
                        .font(.system(size: 26)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(Sys.names[Sys.identifier] ?? Sys.identifier).font(.title3.weight(.bold)).lineLimit(1).minimumScaleFactor(0.8)
                    Text("\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)").font(.footnote).foregroundStyle(.secondary)
                    TimelineView(.periodic(from: .now, by: 3)) { _ in
                        HStack(spacing: 6) {
                            chip(Info.thermalText(ProcessInfo.processInfo.thermalState), "thermometer.medium")
                            chip(UIDevice.current.batteryLevel >= 0 ? String(format: "%.0f%%", UIDevice.current.batteryLevel * 100) : "—", "battery.100")
                        }
                    }
                }
                Spacer(minLength: 4)
                ScoreRing(score: health.score, size: 92)
            }
            if let s = Sys.storage() {
                HStack(spacing: 6) { chip(Sys.fmt(s.free) + " " + L.t("可用", "free"), "internaldrive"); Spacer() }
            }
            NavigationLink { ReportPage() } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(.white.opacity(0.18)).frame(width: 30, height: 30)
                        Image(systemName: health.running ? "hourglass" : "stethoscope").font(.subheadline)
                    }
                    Text(health.running ? L.t("检测中…", "Inspecting…") : L.t("查看设备健康报告", "View health report")).font(.subheadline.weight(.semibold))
                    Spacer(); Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                }
                .foregroundStyle(.white).padding(14)
                .background(settings.accent.color.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }.buttonStyle(.plain)
        }.padding(18).glassCard(radius: 30)
    }
    func chip(_ t: String, _ i: String) -> some View {
        Label(t, systemImage: i).font(.caption2.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.gray.opacity(0.15), in: Capsule())
    }
}

struct CategoryCard: View {
    let cat: Category
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(cat.tint.opacity(0.16)).frame(width: 46, height: 46)
                    Image(systemName: cat.icon).font(.title3).foregroundStyle(cat.tint)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 2)
            Text(cat.title).font(.headline).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.85)
            Text("\(cat.features.count) " + L.t("项检测", "tests")).font(.caption).foregroundStyle(.secondary)
        }
        .padding(16).frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .glassCard(radius: 22)
    }
}
