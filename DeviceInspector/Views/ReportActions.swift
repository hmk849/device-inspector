import SwiftUI
import UIKit

struct ReportActions: View {
    @EnvironmentObject private var store: InspectorStore
    @State private var reportURL: URL?
    @State private var showShare = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                ReportCount(title: "正常", count: store.reportItems().filter{$0.state == .normal}.count, color: .green)
                ReportCount(title: "异常", count: store.reportItems().filter{$0.state == .warning}.count, color: .orange)
                ReportCount(title: "不支持", count: store.reportItems().filter{$0.state == .unsupported}.count, color: .secondary)
            }
            Button {
                do {
                    reportURL = try PDFReport.make(items: store.reportItems(), score: store.healthScore)
                    showShare = true
                } catch {
                    errorText = error.localizedDescription
                }
            } label: {
                Label("生成并分享 PDF 报告", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryActionStyle())
            Text("评分仅按可读取项目的状态比例计算，不代表 Apple 官方诊断或硬件寿命结论。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showShare) {
            if let reportURL { ShareSheet(items: [reportURL]) }
        }
        .alert("报告生成失败", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("确定", role: .cancel) { errorText = nil }
        } message: { Text(errorText ?? "") }
    }
}

struct ReportCount: View {
    let title: String
    let count: Int
    let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)").font(.title2.bold().monospacedDigit()).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

enum PDFReport {
    static func make(items: [CheckItem], score: Int) throws -> URL {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let data = renderer.pdfData { context in
            context.beginPage()
            let title = "Device Inspector 设备检测报告"
            title.draw(at: CGPoint(x: 36, y: 36), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20)])
            "生成时间：\(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))"
                .draw(at: CGPoint(x: 36, y: 68), withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.secondaryLabel])
            "参考评分：\(score)/100（非官方诊断）"
                .draw(at: CGPoint(x: 36, y: 91), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 13)])
            var y: CGFloat = 125
            for item in items {
                if y > 790 {
                    context.beginPage()
                    y = 36
                }
                let line = "\(item.title)  |  \(item.value)  |  \(item.state.rawValue)"
                (line as NSString).draw(in: CGRect(x: 36, y: y, width: 523, height: 22),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.label])
                y += 22
                if y < 790 {
                    (item.detail as NSString).draw(in: CGRect(x: 48, y: y-4, width: 510, height: 20),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.secondaryLabel])
                    y += 18
                }
            }
            let note = "说明：报告仅包含本 App 通过 iOS 公开 API 获取的信息。系统限制项目不代表硬件故障。"
            (note as NSString).draw(in: CGRect(x: 36, y: 810, width: 523, height: 18),
                withAttributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.secondaryLabel])
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DeviceInspector-Report.pdf")
        try data.write(to: url, options: .atomic)
        return url
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
