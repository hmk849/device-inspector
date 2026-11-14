import SwiftUI
import Charts
import CoreLocation

struct SensorPage: View {
    let kind: SensorKind
    @StateObject private var hub = SensorHub()
    var auto: (Verdict, String) {
        if !hub.supported { return (.unsupported, L.t("此设备不具备该传感器", "Sensor not present on this device")) }
        if hub.samples.count < 5 { return (.manual, L.t("等待数据…", "Waiting for data…")) }
        let dur = max(hub.samples.last!.t - hub.samples.first!.t, 0.001)
        let hz = Double(hub.samples.count - 1) / dur
        let vals = hub.samples.flatMap { [$0.x, $0.y, $0.z] }
        if vals.contains(where: { $0.isNaN || $0.isInfinite }) { return (.abnormal, L.t("读数包含无效值", "Invalid values")) }
        return (.normal, String(format: L.t("正在输出数据，约 %.0f Hz", "Streaming data, ≈ %.0f Hz"), hz))
    }
    var body: some View {
        Page(kind.title) {
            let a = auto
            HStack { StatusBadge(verdict: a.0); Text(a.1).font(.footnote).foregroundStyle(.secondary); Spacer() }
            if let s = hub.samples.last {
                VStack(spacing: 6) {
                    if kind == .baro {
                        Text(String(format: "%.2f hPa", s.x)).font(.system(size: 40, weight: .bold, design: .rounded))
                        Text(String(format: L.t("相对高度变化 %.2f m", "Relative altitude %.2f m"), s.y)).foregroundStyle(.secondary)
                    } else {
                        HStack {
                            ForEach([("X", s.x, Color.red), ("Y", s.y, Color.green), ("Z", s.z, Color.blue)], id: \.0) { n, v, c in
                                VStack { Text(n).font(.caption).foregroundStyle(c); Text(String(format: "%.3f", v)).font(.title3.monospacedDigit()) }.frame(maxWidth: .infinity)
                            }
                        }
                        Text(kind.unit).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding().frame(maxWidth: .infinity).glassCard()
            }
            Chart {
                ForEach(hub.samples) { s in
                    LineMark(x: .value("t", s.t), y: .value("X", s.x), series: .value("a", "X")).foregroundStyle(.red)
                    if kind != .baro {
                        LineMark(x: .value("t", s.t), y: .value("Y", s.y), series: .value("a", "Y")).foregroundStyle(.green)
                        LineMark(x: .value("t", s.t), y: .value("Z", s.z), series: .value("a", "Z")).foregroundStyle(.blue)
                    }
                }
            }.chartYScale(domain: .automatic(includesZero: false)).frame(height: 200).padding().glassCard()
            VStack(alignment: .leading, spacing: 8) {
                Text(L.t("校准/准确性测试", "Calibration / accuracy test")).font(.headline)
                Text(L.t("将设备平放静止，点击开始，采样 3 秒。", "Place the device flat and still, then start (3 s sampling).")).font(.caption).foregroundStyle(.secondary)
                Button(hub.calibrating ? L.t("采样中…", "Sampling…") : L.t("开始校准测试", "Start calibration test")) { hub.calibrate() }
                    .buttonStyle(.borderedProminent).disabled(hub.calibrating || !hub.supported)
                if let r = hub.calibResult { StatusBadge(verdict: r.verdict); Text(r.text).font(.footnote) }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard()
            Legend()
        }
        .onAppear { hub.start(kind) }
        .onDisappear { hub.stop() }
    }
}

struct CompassPage: View {
    @StateObject private var loc = LocationModel()
    var body: some View {
        Page(L.t("指南针", "Compass")) {
            if !CLLocationManager.headingAvailable() {
                HStack { StatusBadge(verdict: .unsupported); Text(L.t("此设备无指南针/航向数据", "No heading data on this device")) }
            } else if let h = loc.heading {
                ZStack {
                    Circle().stroke(Color.gray.opacity(0.3), lineWidth: 3)
                    ForEach(["N", "E", "S", "W"].indices, id: \.self) { i in
                        Text(["N", "E", "S", "W"][i]).font(.headline).foregroundStyle(i == 0 ? .red : .secondary)
                            .offset(y: -110).rotationEffect(.degrees(Double(i) * 90))
                    }
                    Image(systemName: "location.north.fill").font(.system(size: 70)).foregroundStyle(.red)
                }
                .frame(width: 260, height: 260)
                .rotationEffect(.degrees(-h.magneticHeading))
                .animation(.easeOut(duration: 0.15), value: h.magneticHeading)
                .padding(30)
                InfoList(items: [
                    InfoItem(L.t("磁航向", "Magnetic heading"), String(format: "%.1f°", h.magneticHeading)),
                    InfoItem(L.t("真北航向", "True heading"), h.trueHeading >= 0 ? String(format: "%.1f°", h.trueHeading) : nil),
                    InfoItem(L.t("航向精度", "Accuracy"), h.headingAccuracy >= 0 ? String(format: "±%.0f°", h.headingAccuracy) : L.t("需要校准", "Needs calibration")),
                ])
                StatusBadge(verdict: h.headingAccuracy >= 0 && h.headingAccuracy < 25 ? .normal : .abnormal)
            } else {
                Text(L.t("等待航向数据…（可能需要定位权限）", "Waiting for heading… (may need location permission)")).foregroundStyle(.secondary)
            }
            Legend()
        }
        .onAppear { loc.startHeading() }
        .onDisappear { loc.stop() }
    }
}
