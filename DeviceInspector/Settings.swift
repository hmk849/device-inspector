import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return L.t("跟随系统", "System")
        case .light: return L.t("浅色", "Light")
        case .dark: return L.t("深色", "Dark")
        }
    }
    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case blue, purple, teal, orange, pink, green
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .teal: return .teal
        case .orange: return .orange
        case .pink: return .pink
        case .green: return .green
        }
    }
}

final class AppSettings: ObservableObject {
    @AppStorage("appearanceMode") var appearance: AppearanceMode = .system
    @AppStorage("accentChoice") var accent: AccentChoice = .blue
    @AppStorage("keepAwakeDuringTests") var keepAwakeDuringTests: Bool = true
    @AppStorage("hapticFeedback") var hapticFeedback: Bool = true
    @AppStorage("autoRunHealthOnLaunch") var autoRunHealthOnLaunch: Bool = true
    @AppStorage("reduceMotion") var reduceMotion: Bool = false
}

private let developerGitHub = "https://github.com/hmk849"

struct SettingsPage: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var health: HealthRunner
    @EnvironmentObject var bench: BenchStore
    @State private var showResetAlert = false
    @State private var showClearedToast = false

    var body: some View {
        Page(L.t("设置", "Settings")) {
            appearanceSection
            generalSection
            dataSection
            developerSection
            aboutSection
        }
        .alert(L.t("重置所有设置？", "Reset all settings?"), isPresented: $showResetAlert) {
            Button(L.t("取消", "Cancel"), role: .cancel) {}
            Button(L.t("重置", "Reset"), role: .destructive) { resetAll() }
        } message: {
            Text(L.t("这会恢复外观、开关等设置为默认值，不会删除检测结果。", "This restores appearance and toggles to defaults; it does not delete scan results."))
        }
    }

    // MARK: Appearance
    var appearanceSection: some View {
        SettingsSection(title: L.t("外观", "Appearance"), icon: "paintbrush.fill", tint: .indigo) {
            HStack(spacing: 10) {
                ForEach(AppearanceMode.allCases) { m in
                    Button { withAnimation(.snappy) { settings.appearance = m } } label: {
                        VStack(spacing: 8) {
                            Image(systemName: m.icon).font(.title2)
                            Text(m.label).font(.caption.weight(.medium))
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .foregroundStyle(settings.appearance == m ? Color.white : Color.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(settings.appearance == m ? AnyShapeStyle(settings.accent.color.gradient) : AnyShapeStyle(Color.gray.opacity(0.14)))
                        )
                    }.buttonStyle(.plain)
                }
            }
            Divider().padding(.vertical, 4)
            Text(L.t("主题色", "Accent color")).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                ForEach(AccentChoice.allCases) { a in
                    Button { settings.accent = a } label: {
                        Circle().fill(a.color.gradient).frame(width: 30, height: 30)
                            .overlay(Circle().stroke(.primary, lineWidth: settings.accent == a ? 2 : 0).padding(-3))
                    }.buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    // MARK: General
    var generalSection: some View {
        SettingsSection(title: L.t("通用", "General"), icon: "slider.horizontal.3", tint: .blue) {
            SettingsToggleRow(icon: "bolt.badge.clock", title: L.t("测试期间保持屏幕常亮", "Keep screen awake during tests"),
                              subtitle: L.t("避免性能/传感器测试被锁屏打断", "Prevents screen lock from interrupting benchmarks"), isOn: $settings.keepAwakeDuringTests)
            Divider().padding(.leading, 44)
            SettingsToggleRow(icon: "hand.tap", title: L.t("操作触感反馈", "Haptic feedback"),
                              subtitle: L.t("点击按钮时轻微振动", "Light vibration on button taps"), isOn: $settings.hapticFeedback)
            Divider().padding(.leading, 44)
            SettingsToggleRow(icon: "play.circle", title: L.t("启动时自动快速检测", "Auto quick-scan on launch"),
                              subtitle: L.t("打开 App 自动跑一次健康检测", "Runs a health scan automatically on open"), isOn: $settings.autoRunHealthOnLaunch)
            Divider().padding(.leading, 44)
            SettingsToggleRow(icon: "tortoise", title: L.t("减少动画", "Reduce motion"),
                              subtitle: L.t("减少界面过渡与仪表盘动效", "Fewer UI transitions and gauge animations"), isOn: $settings.reduceMotion)
            Divider().padding(.leading, 44)
            NavigationLink { LanguageInfoPage() } label: {
                SettingsRow(icon: "globe", title: L.t("语言", "Language"), value: L.isZH ? "中文" : "English")
            }
        }
    }

    // MARK: Data & privacy
    var dataSection: some View {
        SettingsSection(title: L.t("数据与隐私", "Data & Privacy"), icon: "lock.shield.fill", tint: .green) {
            NavigationLink { PermissionsPage() } label: {
                SettingsRow(icon: "hand.raised", title: L.t("权限状态", "Permissions"), value: "")
            }
            Divider().padding(.leading, 44)
            Button {
                clearCaches()
            } label: {
                SettingsRow(icon: "trash", title: L.t("清除测试缓存文件", "Clear test cache files"), value: showClearedToast ? L.t("已清除 ✓", "Cleared ✓") : "", tint: .red)
            }.buttonStyle(.plain)
            Divider().padding(.leading, 44)
            Button(role: .destructive) { showResetAlert = true } label: {
                SettingsRow(icon: "arrow.counterclockwise", title: L.t("重置所有设置", "Reset all settings"), value: "", tint: .red)
            }.buttonStyle(.plain)
            Text(L.t("本 App 不收集、不上传任何设备数据或个人信息；网络测速仅发送测试字节到 apple.com / speed.cloudflare.com。", "This app collects or uploads no device or personal data; speed tests only send test bytes to apple.com / speed.cloudflare.com."))
                .font(.caption2).foregroundStyle(.secondary).padding(.top, 6)
        }
    }

    // MARK: Developer
    var developerSection: some View {
        SettingsSection(title: L.t("开发者", "Developer"), icon: "chevron.left.forwardslash.chevron.right", tint: .black) {
            Link(destination: URL(string: developerGitHub)!) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Color.primary.opacity(0.08))
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 30)).foregroundStyle(.secondary)
                    }.frame(width: 50, height: 50)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("hmk849").font(.headline).foregroundStyle(.primary)
                        Text("github.com/hmk849").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
                }
            }.buttonStyle(.plain)
            Divider().padding(.leading, 64)
            Link(destination: URL(string: developerGitHub + "?tab=repositories")!) {
                SettingsRow(icon: "shippingbox", title: L.t("查看更多项目", "View more projects"), value: "")
            }
            Divider().padding(.leading, 44)
            Link(destination: URL(string: developerGitHub + "/DeviceInspector/issues")!) {
                SettingsRow(icon: "ladybug", title: L.t("反馈问题 / 提建议", "Report an issue / suggest a feature"), value: "")
            }
        }
    }

    // MARK: About
    var aboutSection: some View {
        SettingsSection(title: L.t("关于", "About"), icon: "info.circle.fill", tint: .gray) {
            SettingsRow(icon: "app.badge", title: L.t("版本", "Version"), value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
            Divider().padding(.leading, 44)
            SettingsRow(icon: "checkmark.seal", title: L.t("数据来源", "Data policy"), value: L.t("仅 Apple 公开 API", "Apple public APIs only"))
            Divider().padding(.leading, 44)
            NavigationLink { LegendInfoPage() } label: {
                SettingsRow(icon: "tag", title: L.t("数据标识说明", "Data label legend"), value: "")
            }
            Text("Device Inspector · " + L.t("不越狱、不使用私有 API", "No jailbreak, no private APIs"))
                .font(.caption2).foregroundStyle(.secondary).padding(.top, 6)
        }
    }

    func resetAll() {
        settings.appearance = .system; settings.accent = .blue
        settings.keepAwakeDuringTests = true; settings.hapticFeedback = true
        settings.autoRunHealthOnLaunch = true; settings.reduceMotion = false
    }
    func clearCaches() {
        let tmp = FileManager.default.temporaryDirectory
        if let items = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
            for f in items where f.lastPathComponent.hasPrefix("di_") || f.pathExtension == "pdf" { try? FileManager.default.removeItem(at: f) }
        }
        withAnimation { showClearedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation { showClearedToast = false } }
    }
}

// MARK: - Reusable pieces
struct SettingsSection<Content: View>: View {
    let title: String; let icon: String; let tint: Color
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.footnote.weight(.semibold)).foregroundStyle(tint).padding(.leading, 8)
            VStack(alignment: .leading, spacing: 12) { content }.padding(16).glassCard(radius: 20)
        }
    }
}
struct SettingsRow: View {
    let icon: String; let title: String; let value: String
    var tint: Color = .primary
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.body).foregroundStyle(tint == .primary ? .secondary : tint).frame(width: 24)
            Text(title).foregroundStyle(tint == .primary ? Color.primary : tint)
            Spacer()
            if !value.isEmpty { Text(value).font(.subheadline).foregroundStyle(.secondary) }
            if tint == .primary { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
        }.contentShape(Rectangle())
    }
}
struct SettingsToggleRow: View {
    let icon: String; let title: String; var subtitle: String? = nil
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.body).foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let s = subtitle { Text(s).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden()
        }
    }
}
struct LanguageInfoPage: View {
    var body: some View {
        Page(L.t("语言", "Language")) {
            Text(L.t("本 App 跟随系统语言自动切换中英文，暂不支持单独设置。前往「设置 → App → Device Inspector → 语言」可更改。", "The app follows the system language automatically. To change it, go to Settings → Apps → Device Inspector → Language."))
                .font(.subheadline).foregroundStyle(.secondary).padding(16).glassCard()
            Button(L.t("打开系统设置", "Open Settings")) {
                if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
            }.buttonStyle(.borderedProminent)
        }
    }
}
struct LegendInfoPage: View {
    var body: some View {
        Page(L.t("数据标识说明", "Data label legend")) {
            ForEach([DataKind.measured, .estimated, .restricted], id: \.label) { k in
                HStack(alignment: .top, spacing: 12) {
                    Circle().fill(k.color).frame(width: 12, height: 12).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(k.label).font(.headline)
                        Text(desc(k)).font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard()
            }
        }
    }
    func desc(_ k: DataKind) -> String {
        switch k {
        case .measured: return L.t("直接来自系统 API 的实时读数。", "A live reading straight from a system API.")
        case .estimated: return L.t("基于查表（如型号名称）或启发式计算（如功率、VPN 判断、性能得分）得出，仅供参考。", "Derived from a lookup table (e.g. model name) or a heuristic (e.g. power, VPN, benchmark score) — for reference only.")
        case .restricted: return L.t("iOS 未向第三方 App 开放此数据，本 App 不会编造数值。", "iOS does not expose this to third-party apps; this app never fabricates a value.")
        }
    }
}
