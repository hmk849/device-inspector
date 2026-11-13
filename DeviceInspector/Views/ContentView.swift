import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: InspectorStore
    @State private var selected: InspectorSection = .device
    @State private var showReport = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    dashboard
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(InspectorSection.allCases) { section in
                            Button { selected = section } label: {
                                SectionTile(section: section, selected: selected == section)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    SectionDetailView(section: selected)
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Device Inspector")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.refreshBattery() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("刷新数据")
                }
            }
        }
        .tint(.cyan)
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 4) {
                    Text(InspectorStore.friendlyModel(InspectorStore.machineIdentifier()))
                        .font(.title2.bold())
                    Text(UIDevice.current.systemVersion.isEmpty ? "iOS" : "iOS \(UIDevice.current.systemVersion)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Label(store.isConnected ? "网络已连接" : "网络未连接", systemImage: store.isConnected ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(store.isConnected ? .green : .orange)
                }
                Spacer()
                ZStack {
                    Circle().stroke(.white.opacity(0.12), lineWidth: 7)
                    Circle().trim(from: 0, to: CGFloat(store.healthScore)/100)
                        .stroke(AngularGradient(colors: [.cyan, .blue], center: .center), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(store.healthScore)").font(.title2.bold().monospacedDigit())
                        Text("评分").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 70, height: 70)
            }
            Divider().overlay(.white.opacity(0.1))
            HStack {
                MetricPill(title: "电池", value: store.batteryLevel, symbol: "battery.100")
                Spacer()
                MetricPill(title: "连接", value: store.isConnected ? "在线" : "离线", symbol: "wifi")
                Spacer()
                MetricPill(title: "刷新率", value: "\(UIScreen.main.maximumFramesPerSecond) Hz", symbol: "display")
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.12)))
    }
}

struct MetricPill: View {
    let title: String
    let value: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

struct SectionTile: View {
    let section: InspectorSection
    let selected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: section.symbol).font(.title2).foregroundStyle(.cyan)
            Text(section.rawValue).font(.headline)
            Text(section.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .padding(14)
        .background(selected ? Color.cyan.opacity(0.13) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(selected ? Color.cyan.opacity(0.55) : .white.opacity(0.07)))
    }
}
