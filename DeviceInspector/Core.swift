import SwiftUI
import Charts

enum L {
    static var isZH: Bool { Locale.preferredLanguages.first?.hasPrefix("zh") ?? false }
    static func t(_ zh: String, _ en: String) -> String { isZH ? zh : en }
    static var restricted: String { t("系统限制，无法读取", "Restricted by iOS — unavailable") }
}

enum DataKind {
    case measured, estimated, restricted
    var label: String {
        switch self {
        case .measured: return L.t("真实检测", "Measured")
        case .estimated: return L.t("估算/推断", "Estimated")
        case .restricted: return L.t("系统限制", "Restricted")
        }
    }
    var color: Color {
        switch self {
        case .measured: return .green
        case .estimated: return .orange
        case .restricted: return .gray
        }
    }
}

struct InfoItem: Identifiable {
    let id = UUID()
    let key: String
    let value: String
    let kind: DataKind
    /// value == nil means iOS does not expose it -> marked restricted.
    init(_ key: String, _ value: String?, _ kind: DataKind = .measured) {
        self.key = key
        if let v = value { self.value = v; self.kind = kind }
        else { self.value = L.restricted; self.kind = .restricted }
    }
}

enum Verdict {
    case normal, abnormal, unsupported, manual
    var label: String {
        switch self {
        case .normal: return L.t("正常", "Normal")
        case .abnormal: return L.t("异常", "Abnormal")
        case .unsupported: return L.t("不支持", "Unsupported")
        case .manual: return L.t("需手动测试", "Manual test")
        }
    }
    var color: Color {
        switch self {
        case .normal: return .green
        case .abnormal: return .red
        case .unsupported: return .gray
        case .manual: return .blue
        }
    }
    var icon: String {
        switch self {
        case .normal: return "checkmark.circle.fill"
        case .abnormal: return "exclamationmark.triangle.fill"
        case .unsupported: return "minus.circle.fill"
        case .manual: return "hand.tap.fill"
        }
    }
}

struct CheckResult: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let verdict: Verdict
    let detail: String
}

// MARK: - Liquid Glass helpers
extension View {
    @ViewBuilder func glassCard(radius: CGFloat = 22) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
        #else
        self.background(.ultraThinMaterial, in: shape)
        #endif
    }
}

struct Backdrop: View {
    var body: some View {
        LinearGradient(colors: [Color(.systemBackground), Color.blue.opacity(0.14), Color.purple.opacity(0.12)],
                       startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
    }
}

struct Page<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        ScrollView { VStack(spacing: 16) { content }.padding() }
            .background(Backdrop())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct ScoreRing: View {
    let score: Int?
    var size: CGFloat = 120
    var label: String = L.t("健康评分", "Health")
    var color: Color {
        guard let s = score else { return .gray }
        return s >= 85 ? .green : (s >= 60 ? .orange : .red)
    }
    var body: some View {
        ZStack {
            Circle().stroke(Color.gray.opacity(0.2), lineWidth: 12)
            Circle().trim(from: 0, to: CGFloat(score ?? 0) / 100)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: score)
            VStack(spacing: 0) {
                Text(score.map(String.init) ?? "--")
                    .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
        }.frame(width: size, height: size)
    }
}

struct StatusBadge: View {
    let verdict: Verdict
    var body: some View {
        Label(verdict.label, systemImage: verdict.icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(verdict.color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(verdict.color.opacity(0.15), in: Capsule())
    }
}

struct InfoList: View {
    let items: [InfoItem]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                HStack(alignment: .top) {
                    Text(it.key).foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(it.value).multilineTextAlignment(.trailing)
                            .foregroundStyle(it.kind == .restricted ? Color.secondary : Color.primary)
                        Text(it.kind.label).font(.caption2).foregroundStyle(it.kind.color)
                    }
                }.padding(.vertical, 10)
                if i < items.count - 1 { Divider() }
            }
        }.padding(.horizontal, 16).frame(maxWidth: .infinity).glassCard()
    }
}

struct LiveInfo: View {
    let every: Double
    let provider: () -> [InfoItem]
    var body: some View {
        TimelineView(.periodic(from: .now, by: every)) { _ in InfoList(items: provider()) }
    }
}

struct Legend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L.t("数据标识", "Data labels")).font(.caption.weight(.semibold))
            Text(L.t("绿色=真实检测；橙色=估算/推断（查表或启发式）；灰色=系统限制，无法读取。本 App 不虚构数据。",
                     "Green = measured; orange = estimated/inferred; gray = restricted by iOS. This app never fabricates data."))
                .font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).glassCard(radius: 16)
    }
}

struct LiveChart: View {
    struct Pt: Identifiable { let id = UUID(); let t: Date; let v: Double }
    let title: String
    let unit: String
    let provider: () -> Double?
    @State private var pts: [Pt] = []
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title).font(.headline); Spacer()
                Text(pts.last.map { String(format: "%.1f %@", $0.v, unit) } ?? "--").monospacedDigit()
            }
            Chart(pts) { p in
                LineMark(x: .value("t", p.t), y: .value("v", p.v)).interpolationMethod(.catmullRom)
                AreaMark(x: .value("t", p.t), y: .value("v", p.v)).opacity(0.15)
            }.frame(height: 140)
        }
        .padding().glassCard()
        .onReceive(timer) { _ in
            if let v = provider() { pts.append(Pt(t: Date(), v: v)); if pts.count > 60 { pts.removeFirst() } }
        }
    }
}
