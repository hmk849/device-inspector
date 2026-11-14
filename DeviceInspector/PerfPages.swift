import SwiftUI

struct BenchPage: View {
    let kind: BenchKind
    @EnvironmentObject var bench: BenchStore
    var body: some View {
        Page(kind.title) {
            Text(kind.desc).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task { await bench.run(kind) }
            } label: {
                HStack { if bench.running == kind { ProgressView() }; Text(bench.running == kind ? L.t("测试中…", "Running…") : L.t("开始测试", "Run test")) }.frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).disabled(bench.running != nil)
            if let r = bench.results[kind] {
                HStack { StatusBadge(verdict: r.verdict); Spacer(); Text("\(r.points) pts").font(.title2.bold().monospacedDigit()) }.padding().glassCard()
                InfoList(items: r.lines)
            }
            Text(L.t("得分为相对参考值的归一化结果（估算），仅用于本机纵向对比，不可与其他跑分 App 直接比较。", "Points are normalised to reference constants (estimated): useful for comparing this device over time, not across benchmark apps."))
                .font(.caption2).foregroundStyle(.secondary)
            Legend()
        }
    }
}

struct FPSPage: View {
    @EnvironmentObject var bench: BenchStore
    @StateObject private var meter = FPSMeter()
    @State private var running = false
    @State private var left = 8
    private var maxFPS: Int { Info.screen?.maximumFramesPerSecond ?? 60 }
    var body: some View {
        Page(BenchKind.fps.title) {
            Text(BenchKind.fps.desc).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            if running {
                StressCanvas().frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                HStack { Text(String(format: "%.0f fps", meter.fps)).font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit()); Spacer(); Text("\(left)s") }
                    .padding().glassCard()
            }
            Button {
                Task { await run() }
            } label: { Text(running ? L.t("测试中…", "Running…") : L.t("开始测试（8 秒）", "Run test (8 s)")).frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).disabled(running)
            if let r = bench.results[.fps] {
                HStack { StatusBadge(verdict: r.verdict); Spacer(); Text("\(r.points) pts").font(.title2.bold().monospacedDigit()) }.padding().glassCard()
                InfoList(items: r.lines)
            }
            Legend()
        }
    }
    func run() async {
        running = true; left = 8
        meter.start(maxFPS: maxFPS)
        for _ in 0..<8 { try? await Task.sleep(nanoseconds: 1_000_000_000); left -= 1 }
        let r = meter.stop(maxFPS: maxFPS)
        running = false
        let ratio = r.avg / Double(maxFPS)
        bench.results[.fps] = BenchResult(points: Int(ratio * 1000), verdict: ratio > 0.5 ? .normal : .abnormal, lines: [
            InfoItem(L.t("平均帧率", "Average FPS"), String(format: "%.1f fps", r.avg)),
            InfoItem(L.t("1% Low 帧率", "1% low"), String(format: "%.1f fps", r.low1)),
            InfoItem(L.t("屏幕最高刷新率", "Panel max refresh"), "\(maxFPS) Hz"),
            InfoItem(L.t("掉帧数 / 总帧数", "Dropped / total frames"), "\(r.dropped) / \(r.frames)"),
            InfoItem(L.t("相对得分（平均帧率/刷新率）", "Relative points (avg/refresh)"), "\(Int(ratio * 1000))", .estimated)])
    }
}

struct ThermalPage: View {
    @State private var state = ProcessInfo.processInfo.thermalState
    var body: some View {
        Page(L.t("温度与热状态", "Thermal")) {
            let lv = state.rawValue
            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 6).fill(i <= lv ? [Color.green, .yellow, .orange, .red][i] : Color.gray.opacity(0.2)).frame(height: 14)
                    }
                }
                Text(Info.thermalText(state)).font(.title3.bold())
            }.padding(16).glassCard()
            LiveInfo(every: 2) { Info.thermal() }
            LiveChart(title: L.t("热状态等级 (0–3)", "Thermal level (0–3)"), unit: "") { Double(ProcessInfo.processInfo.thermalState.rawValue) }
            Text(L.t("iOS 仅公开 4 档热状态，不提供 CPU/GPU/电池的具体摄氏温度。", "iOS exposes only four thermal levels, not actual °C readings.")).font(.caption2).foregroundStyle(.secondary)
            Legend()
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in state = ProcessInfo.processInfo.thermalState }
    }
}

struct TotalPerfPage: View {
    @EnvironmentObject var bench: BenchStore
    var body: some View {
        Page(L.t("综合性能评分", "Overall score")) {
            ScoreRing(score: bench.composite, size: 150, label: L.t("性能", "Perf"))
            Button {
                Task { await bench.runAll() }
            } label: {
                HStack { if bench.running != nil { ProgressView() }; Text(bench.running.map { L.t("正在测试：", "Running: ") + $0.title } ?? L.t("运行 CPU / GPU / 内存 / 存储", "Run CPU / GPU / Memory / Storage")) }.frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).disabled(bench.running != nil)
            InfoList(items: BenchKind.allCases.map { k in
                InfoItem(k.title, bench.results[k].map { "\($0.points) pts" } ?? L.t("未测试", "Not run"), .estimated)
            })
            Text(L.t("综合分 = 各项得分（单项上限 1000）平均值 ÷ 10，属估算；帧率测试需在其独立页面手动运行。", "Overall = mean of component points (each capped at 1000) ÷ 10 — an estimate. Run the FPS test on its own page."))
                .font(.caption2).foregroundStyle(.secondary)
            Legend()
        }
    }
}
