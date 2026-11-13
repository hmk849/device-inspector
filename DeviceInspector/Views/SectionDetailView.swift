import SwiftUI

struct SectionDetailView: View {
    @EnvironmentObject private var store: InspectorStore
    let section: InspectorSection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(section.rawValue).font(.title3.bold())
                    Text(section.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if section == .sensors {
                    Button("停止") { store.stopSensors() }
                        .font(.caption.weight(.semibold))
                }
            }
            ForEach(store.items(for: section)) { item in
                CheckRow(item: item)
            }
            controls
        }
        .animation(.easeInOut(duration: 0.2), value: section.rawValue)
    }

    @ViewBuilder private var controls: some View {
        switch section {
        case .network:
            VStack(spacing: 8) {
                Button {
                    Task { await store.testLatency() }
                } label: {
                    Label("测试 HTTPS 网络延迟", systemImage: "network")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryActionStyle())
                Button {
                    Task { await store.runNetworkSpeedTest() }
                } label: {
                    Label("测试下载 / 上传速度", systemImage: "arrow.down.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryActionStyle())
            }
        case .performance:
            VStack(spacing: 8) {
                Button {
                    Task { await store.runBasicTest() }
                } label: {
                    Label(store.isTesting ? "测试中…" : "运行 CPU 基础测试", systemImage: "speedometer")
                        .frame(maxWidth: .infinity)
                }
                .disabled(store.isTesting)
                .buttonStyle(PrimaryActionStyle())
                Button {
                    Task { await store.runGPUtest() }
                } label: {
                    Label("运行 Metal GPU 测试", systemImage: "cube.transparent")
                        .frame(maxWidth: .infinity)
                }
                .disabled(store.isTesting)
                .buttonStyle(PrimaryActionStyle())
                Button {
                    Task { await store.runStorageTest() }
                } label: {
                    Label("运行存储读写测试", systemImage: "internaldrive")
                        .frame(maxWidth: .infinity)
                }
                .disabled(store.isTesting)
                .buttonStyle(PrimaryActionStyle())
            }
        case .sensors:
            VStack(spacing: 8) {
                Button {
                    store.startSensors()
                } label: {
                    Label("开始实时传感器测试", systemImage: "waveform.path")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryActionStyle())
                Button("停止传感器") { store.stopSensors() }
                    .font(.caption)
            }
        case .report:
            ReportActions()
        default:
            EmptyView()
        }
    }
}

struct CheckRow: View {
    let item: CheckItem
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(item.state.rawValue)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(color)
                }
                Text(item.value).font(.subheadline).foregroundStyle(.primary).textSelection(.enabled)
                Text(item.detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
    private var color: Color {
        switch item.state {
        case .normal: .green
        case .warning: .orange
        case .unsupported: .secondary
        case .estimate: .purple
        case .waiting: .cyan
        }
    }
    private var icon: String {
        switch item.state {
        case .normal: "checkmark"
        case .warning: "exclamationmark"
        case .unsupported: "minus"
        case .estimate: "chart.line.uptrend.xyaxis"
        case .waiting: "clock"
        }
    }
}

struct PrimaryActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 14)
            .background(Color.cyan.opacity(configuration.isPressed ? 0.18 : 0.28), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(.cyan.opacity(0.35)))
    }
}
