import SwiftUI
import Charts
import NetworkExtension
import CoreLocation

// MARK: - Charging / discharging power estimator (public APIs only)
@MainActor final class PowerMonitor: ObservableObject {
    struct Pt: Identifiable { let id = UUID(); let t: Date; let level: Double; let thermal: Int }
    @Published var pts: [Pt] = []
    @Published var running = false
    @Published var ratePerHour: Double?     // % per hour, positive = charging
    @Published var charging = false
    @Published var keepAwake = false { didSet { UIApplication.shared.isIdleTimerDisabled = keepAwake } }
    private var timer: Timer?
    private var events: [(Date, Double)] = []
    private var lastLevel: Double = -1

    func start() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        pts = []; events = []; lastLevel = -1; ratePerHour = nil; running = true
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    func stop() { timer?.invalidate(); timer = nil; running = false; keepAwake = false }

    private func tick() {
        let d = UIDevice.current
        let lvl = Double(d.batteryLevel) * 100
        guard lvl >= 0 else { return }
        charging = d.batteryState == .charging
        pts.append(Pt(t: Date(), level: lvl, thermal: ProcessInfo.processInfo.thermalState.rawValue))
        if pts.count > 720 { pts.removeFirst() }
        if lvl != lastLevel {
            if lastLevel >= 0 { events.append((Date(), lvl)); if events.count > 8 { events.removeFirst() } }
            lastLevel = lvl
        }
        if events.count >= 2, let f = events.first, let l = events.last {
            let hours = l.0.timeIntervalSince(f.0) / 3600
            if hours > 0 { ratePerHour = (l.1 - f.1) / hours }
        }
    }
    /// Estimated watts = |%/h| x capacity(Ah) x nominal voltage. Depends on the user-entered capacity.
    func watts(capacityMAh: Double, nominalV: Double = 3.85) -> Double? {
        guard let r = ratePerHour else { return nil }
        return abs(r) / 100 * capacityMAh / 1000 * nominalV
    }
}

struct PowerPage: View {
    @StateObject private var m = PowerMonitor()
    @AppStorage("capMAh") private var cap: Double = 3000
    var body: some View {
        Page(L.t("功率与温度监测", "Power & Thermal")) {
            VStack(spacing: 8) {
                if let w = m.watts(capacityMAh: cap) {
                    Text(String(format: "≈ %.1f W", w)).font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit())
                    Text((m.ratePerHour ?? 0) >= 0 ? L.t("充电功率（估算）", "Charging power (estimated)") : L.t("放电功率（估算）", "Discharge power (estimated)")).foregroundStyle(.orange)
                    Text(String(format: L.t("电量变化 %+.1f %%/小时", "Level change %+.1f %%/h"), m.ratePerHour ?? 0)).font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("— W").font(.system(size: 46, weight: .bold, design: .rounded))
                    Text(m.running ? L.t("采样中：需要电量至少变化 2 次（约数分钟，充电时更快）", "Sampling: needs ≥2 level changes (a few minutes, faster while charging)") : L.t("点击开始监测", "Tap Start")).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }.padding(18).frame(maxWidth: .infinity).glassCard()
            HStack {
                Button(m.running ? L.t("停止", "Stop") : L.t("开始监测", "Start")) { m.running ? m.stop() : m.start() }.buttonStyle(.borderedProminent)
                Toggle(L.t("保持亮屏", "Keep awake"), isOn: $m.keepAwake).disabled(!m.running)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L.t("电池容量 (mAh)", "Battery capacity (mAh)")).font(.headline)
                TextField("3000", value: $cap, format: .number).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                Text(L.t("iOS 不开放电池容量，请按你的机型规格填写，功率估算依赖这个值（标称电压按 3.85V）。", "iOS does not expose capacity; enter your model's spec. The estimate depends on it (nominal 3.85 V).")).font(.caption2).foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard()
            LiveInfo(every: 3) { [
                InfoItem(L.t("当前电量", "Level"), UIDevice.current.batteryLevel >= 0 ? String(format: "%.0f%%", UIDevice.current.batteryLevel * 100) : nil),
                InfoItem(L.t("系统热状态", "Thermal state"), Info.thermalText(ProcessInfo.processInfo.thermalState)),
                InfoItem(L.t("电池温度 (°C)", "Battery temperature (°C)"), nil),
                InfoItem(L.t("电流 / 电压（实时）", "Current / voltage (live)"), nil),
                InfoItem(L.t("功率（估算）", "Power"), m.watts(capacityMAh: cap).map { String(format: "%.1f W", $0) }, .estimated)] }
            if m.pts.count > 1 {
                VStack(alignment: .leading) {
                    Text(L.t("电量曲线 (%)", "Level (%)")).font(.headline)
                    Chart(m.pts) { LineMark(x: .value("t", $0.t), y: .value("%", $0.level)) }.chartYScale(domain: .automatic(includesZero: false)).frame(height: 140)
                }.padding().glassCard()
                VStack(alignment: .leading) {
                    Text(L.t("热状态等级 (0–3)", "Thermal level (0–3)")).font(.headline)
                    Chart(m.pts) { LineMark(x: .value("t", $0.t), y: .value("lv", $0.thermal)).foregroundStyle(.orange) }.chartYScale(domain: 0...3).frame(height: 110)
                }.padding().glassCard()
            }
            Text(L.t("说明：iOS 公开 API 不提供电池电流、电压、摄氏温度。这里的功率是用「电量变化速率 × 你填写的容量」推算，误差可能较大（电量只按 1% 步进、受屏幕与后台负载影响）；温度仅有系统 4 档热状态。想要精确瓦数需外接 USB 功率计。", "Note: public iOS APIs expose no battery current, voltage or °C. Power is inferred from level-change rate × your capacity and can be coarse (1 % steps, load-dependent). Temperature is only the 4-level thermal state. For exact watts use a USB power meter."))
                .font(.caption2).foregroundStyle(.secondary)
            Legend()
        }.onDisappear { m.stop() }
    }
}

// MARK: - Manual battery health entry (Settings > Battery > Battery Health)
struct ManualBatteryCard: View {
    @AppStorage("manualHealth") private var health: Double = 0
    @AppStorage("manualCycles") private var cycles: Int = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("电池健康（手动录入）", "Battery health (manual entry)")).font(.headline)
            Text(L.t("iOS 不允许 App 读取。请到「设置 → 电池 → 电池健康」查看后填入，仅保存在本机。", "Apps cannot read this. Enter values from Settings → Battery → Battery Health; stored on-device only.")).font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField(L.t("最大容量 %", "Max capacity %"), value: $health, format: .number).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                TextField(L.t("循环次数", "Cycles"), value: $cycles, format: .number).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
            }
            if health > 0 { StatusBadge(verdict: health >= 80 ? .normal : .abnormal) }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }
}

// MARK: - Wi-Fi SSID (needs the Access WiFi Information entitlement + location permission)
final class WifiInfo: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var ssid: String?
    @Published var message = ""
    private let lm = CLLocationManager()
    func fetch() {
        lm.delegate = self
        if lm.authorizationStatus == .notDetermined { lm.requestWhenInUseAuthorization(); return }
        NEHotspotNetwork.fetchCurrent { n in
            DispatchQueue.main.async {
                if let n = n { self.ssid = n.ssid; self.message = "" }
                else { self.message = L.t("无法读取：需连接 Wi-Fi、授予定位权限，且工程已启用 Access WiFi Information（见 README）", "Unavailable: needs Wi-Fi, location permission and the Access WiFi Information capability (see README)") }
            }
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { if manager.authorizationStatus != .notDetermined { fetch() } }
}
struct WifiCard: View {
    @StateObject private var w = WifiInfo()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("Wi-Fi 名称 (SSID)", "Wi-Fi name (SSID)")).font(.headline)
            if let s = w.ssid { Text(s).font(.title3) }
            Button(L.t("读取 Wi-Fi 名称", "Read Wi-Fi name")) { w.fetch() }.buttonStyle(.borderedProminent)
            if !w.message.isEmpty { Text(w.message).font(.caption).foregroundStyle(.secondary) }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }
}
