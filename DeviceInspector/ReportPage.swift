import SwiftUI

struct ReportPage: View {
    @EnvironmentObject var health: HealthRunner
    @EnvironmentObject var bench: BenchStore
    @State private var pdf: URL?
    @State private var failed = false
    var busy: Bool { health.running || bench.running != nil }
    var body: some View {
        Page(L.t("设备健康报告", "Health report")) {
            ScoreRing(score: health.score, size: 150)
            if let d = health.date { Text(d.formatted(date: .abbreviated, time: .standard)).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button { Task { await health.run(bench: bench) } } label: {
                    Text(L.t("快速检测", "Quick scan")).frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
                Button { Task { await bench.runAll(); await health.run(bench: bench) } } label: {
                    Text(L.t("完整检测（含性能）", "Full scan (with perf)")).frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent)
            }.disabled(busy)
            if busy { ProgressView(bench.running.map { $0.title } ?? L.t("检测中…", "Inspecting…")) }
            VStack(spacing: 0) {
                ForEach(health.results) { r in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: r.icon).frame(width: 26).foregroundStyle(r.verdict.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(.subheadline.weight(.semibold))
                            Text(r.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        StatusBadge(verdict: r.verdict)
                    }.padding(.vertical, 9)
                    Divider()
                }
            }.padding(.horizontal, 16).glassCard()
            Button {
                pdf = ReportPDF.make(results: health.results, score: health.score, bench: bench, device: Info.device() + Info.system())
                failed = pdf == nil
            } label: { Label(L.t("生成 PDF 报告", "Generate PDF report"), systemImage: "doc.richtext").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).disabled(health.results.isEmpty || busy)
            if let pdf { ShareLink(item: pdf) { Label(L.t("保存 / 分享 PDF", "Save / share PDF"), systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }.buttonStyle(.bordered) }
            if failed { Text(L.t("PDF 生成失败", "PDF generation failed")).foregroundStyle(.red) }
            Text(L.t("评分 = 正常项 ÷（正常项 + 异常项）；「不支持」「系统限制」「需手动测试」不计分。", "Score = normal ÷ (normal + abnormal); unsupported / restricted / manual items are not scored."))
                .font(.caption2).foregroundStyle(.secondary)
            Legend()
        }
    }
}
