import SwiftUI
import UIKit
import AVFoundation
import CoreLocation
import CoreMotion
import LocalAuthentication
import Photos
import UserNotifications
import Charts

struct InfoPage: View {
    let title: String
    var sections: [(String, () -> [InfoItem])]
    var every: Double? = nil
    var extra: AnyView? = nil
    var body: some View {
        Page(title) {
            if let extra { extra }
            ForEach(sections.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 8) {
                    if !sections[i].0.isEmpty {
                        Text(sections[i].0).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 8)
                    }
                    if let e = every { LiveInfo(every: e, provider: sections[i].1) } else { InfoList(items: sections[i].1()) }
                }
            }
            Legend()
        }
    }
}

struct StoragePage: View {
    var body: some View {
        Page(L.t("存储", "Storage")) {
            if let s = Sys.storage(), s.total > 0 {
                let used = Double(s.total - s.free) / Double(s.total)
                Gauge(value: used) { Text("") } currentValueLabel: { Text(String(format: "%.0f%%", used * 100)) }
                    .gaugeStyle(.accessoryCircularCapacity).scaleEffect(2.2).frame(height: 120).tint(used > 0.9 ? .red : .blue)
            }
            InfoList(items: Info.storage())
            Legend()
        }
    }
}

struct BatteryPage: View {
    var body: some View {
        Page(L.t("电池", "Battery")) {
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                let lvl = max(0, Double(UIDevice.current.batteryLevel))
                Gauge(value: lvl) { Text("") } currentValueLabel: { Text(String(format: "%.0f%%", lvl * 100)) }
                    .gaugeStyle(.accessoryCircularCapacity).scaleEffect(2.2).frame(height: 120)
                    .tint(UIDevice.current.batteryState == .charging ? .green : .blue)
            }
            LiveInfo(every: 2) { Info.battery() }
            LiveChart(title: L.t("电量", "Level"), unit: "%") { Double(max(0, UIDevice.current.batteryLevel)) * 100 }
            ManualBatteryCard()
            Legend()
        }
    }
}

struct CameraPage: View {
    @StateObject private var cam = CameraController()
    @State private var pos: AVCaptureDevice.Position = .back
    var body: some View {
        Page(L.t("摄像头", "Cameras")) {
            InfoList(items: Info.cameras())
            Picker("", selection: $pos) {
                Text(L.t("后置", "Back")).tag(AVCaptureDevice.Position.back)
                Text(L.t("前置", "Front")).tag(AVCaptureDevice.Position.front)
            }.pickerStyle(.segmented)
            ZStack {
                CameraPreview(session: cam.session).frame(height: 320).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                if !cam.running {
                    Text(cam.message.isEmpty ? L.t("点击下方按钮开始实时预览（不保存、不上传）", "Tap Start for a live preview (nothing saved or uploaded)") : cam.message)
                        .multilineTextAlignment(.center).padding().foregroundStyle(.secondary)
                }
            }.frame(height: 320).glassCard()
            HStack {
                Button(cam.running ? L.t("停止", "Stop") : L.t("开始测试", "Start")) {
                    if cam.running { cam.stop() } else { cam.start(pos) }
                }.buttonStyle(.borderedProminent)
                StatusBadge(verdict: cam.running ? .normal : .manual)
            }
            Legend()
        }
        .onChange(of: pos) { _, p in if cam.running { cam.start(p) } }
        .onDisappear { cam.stop() }
    }
}

struct AudioPage: View {
    @StateObject private var a = AudioTester()
    var body: some View {
        Page(L.t("麦克风与扬声器", "Mic & Speaker")) {
            InfoList(items: Info.audio())
            VStack(alignment: .leading, spacing: 10) {
                Text(L.t("麦克风实时电平", "Live mic level")).font(.headline)
                ProgressView(value: min(Double(a.level) * 8, 1)).tint(.green)
                HStack {
                    Button(a.micRunning ? L.t("停止", "Stop") : L.t("开始麦克风测试", "Start mic test")) { a.micRunning ? a.stopMic() : a.startMic() }
                        .buttonStyle(.borderedProminent)
                    StatusBadge(verdict: a.micRunning ? (a.level > 0.0005 ? .normal : .manual) : .manual)
                }
                Text(L.t("对着手机说话，电平条跳动即表示麦克风正常。", "Speak to the phone; a moving bar means the mic works.")).font(.caption).foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard()
            VStack(alignment: .leading, spacing: 10) {
                Text(L.t("扬声器测试", "Speaker test")).font(.headline)
                Button(L.t("播放 440Hz 测试音", "Play 440 Hz tone")) { a.playTone() }.buttonStyle(.borderedProminent)
                Text(L.t("需人工确认是否听到声音（请先取消静音）。", "Confirm by ear (make sure the phone isn't muted).")).font(.caption).foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard()
            if !a.message.isEmpty { Text(a.message).foregroundStyle(.red).font(.footnote) }
            Legend()
        }.onDisappear { a.stopMic() }
    }
}

struct TouchPage: View {
    @State private var cur = 0, maxT = 0
    var body: some View {
        Page(L.t("触摸屏 / 多点触控", "Touch / Multi-touch")) {
            InfoList(items: Info.touch())
            VStack(spacing: 8) {
                Text(L.t("用多根手指同时按压下方区域", "Press the pad below with several fingers")).font(.subheadline)
                TouchPad { c, m in cur = c; maxT = m }.frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                HStack { Text(L.t("当前触点", "Now") + ": \(cur)"); Spacer(); Text(L.t("最大触点", "Max") + ": \(maxT)").bold() }
                StatusBadge(verdict: maxT >= 2 ? .normal : .manual)
            }.padding(16).glassCard()
            Legend()
        }
    }
}

struct BiometricPage: View {
    @State private var result = ""
    var body: some View {
        Page("Face ID / Touch ID") {
            InfoList(items: Info.biometryItems())
            Button(L.t("测试验证（仅本机，不返回生物特征）", "Test authentication (on-device only)")) {
                let c = LAContext()
                c.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: L.t("验证生物识别硬件", "Verify biometric hardware")) { ok, err in
                    DispatchQueue.main.async { result = ok ? L.t("验证成功：硬件工作正常", "Success: hardware works") : (err?.localizedDescription ?? "—") }
                }
            }.buttonStyle(.borderedProminent)
            if !result.isEmpty { Text(result).font(.footnote) }
            Legend()
        }
    }
}

struct GPSPage: View {
    @StateObject private var loc = LocationModel()
    var body: some View {
        Page("GPS") {
            LiveInfo(every: 1) { Info.gpsItems() }
            VStack(alignment: .leading, spacing: 8) {
                Text(L.t("实时定位", "Live fix")).font(.headline)
                if let l = loc.loc {
                    Text(String(format: L.t("水平精度 ±%.0f m · 海拔 %.0f m · 速度 %.1f m/s", "H-accuracy ±%.0f m · alt %.0f m · speed %.1f m/s"), l.horizontalAccuracy, l.altitude, max(l.speed, 0)))
                    Text(String(format: "%.5f, %.5f", l.coordinate.latitude, l.coordinate.longitude)).font(.caption).foregroundStyle(.secondary)
                    StatusBadge(verdict: l.horizontalAccuracy >= 0 && l.horizontalAccuracy < 100 ? .normal : .abnormal)
                } else { Text(loc.running ? L.t("定位中…（室外效果更好）", "Locating… (better outdoors)") : L.t("未开始", "Not started")).foregroundStyle(.secondary) }
                Button(loc.running ? L.t("停止", "Stop") : L.t("开始定位测试", "Start GPS test")) { loc.running ? loc.stop() : loc.startLocation() }.buttonStyle(.borderedProminent)
                Text(L.t("坐标仅显示在本机，不会上传。", "Coordinates stay on this device.")).font(.caption2).foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard()
            Legend()
        }.onDisappear { loc.stop() }
    }
}

struct HapticPage: View {
    private let h = HapticTester()
    @State private var msg = ""
    var body: some View {
        Page(L.t("振动马达", "Haptics")) {
            InfoList(items: Info.haptics())
            Button(L.t("触发振动", "Trigger haptic")) { msg = h.play() ?? L.t("已触发，请确认是否感受到振动", "Triggered — confirm you felt it") }.buttonStyle(.borderedProminent)
            if !msg.isEmpty { Text(msg).font(.footnote) }
            Legend()
        }
    }
}

struct NetStatusPage: View {
    @StateObject private var mon = NetMonitor()
    var body: some View {
        Page(L.t("连接状态", "Connection")) {
            InfoList(items: Info.network(mon.path))
            WifiCard()
            Legend()
        }
    }
}

struct NetSpeedPage: View {
    let stability: Bool
    @StateObject private var t = NetTester()
    var body: some View {
        Page(stability ? L.t("网络稳定性", "Stability") : L.t("延迟与速度", "Latency & Speed")) {
            Button {
                Task { stability ? await t.runStability(seconds: 15) : await t.runSpeed() }
            } label: {
                HStack { if t.running { ProgressView() }; Text(t.running ? t.status : L.t("开始测试", "Start test")) }.frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).disabled(t.running)
            if !t.pings.isEmpty {
                Chart {
                    ForEach(Array(t.pings.enumerated()), id: \.offset) { i, p in
                        if let p { LineMark(x: .value("#", i), y: .value("ms", p)); PointMark(x: .value("#", i), y: .value("ms", p)) }
                    }
                }.frame(height: 160).padding().glassCard()
                InfoList(items: [
                    InfoItem(L.t("平均延迟 (HTTP RTT)", "Avg latency (HTTP RTT)"), t.avg.map { String(format: "%.0f ms", $0) }, .estimated),
                    InfoItem(L.t("抖动", "Jitter"), t.jitter.map { String(format: "%.1f ms", $0) }, .estimated),
                    InfoItem(L.t("丢包率", "Loss"), t.loss.map { String(format: "%.0f%%", $0) }, .estimated)])
            }
            if !stability && (t.down != nil || t.up != nil) {
                InfoList(items: [
                    InfoItem(L.t("下载速度", "Download"), t.down.map { String(format: "%.1f Mbps", $0) } ?? L.t("失败", "Failed"), .estimated),
                    InfoItem(L.t("上传速度", "Upload"), t.up.map { String(format: "%.1f Mbps", $0) } ?? L.t("失败", "Failed"), .estimated)])
            }
            Text(L.t("测试会访问 apple.com 与 speed.cloudflare.com，仅传输测试数据，不含个人信息。延迟为 HTTPS 往返时间，非 ICMP ping。", "Contacts apple.com and speed.cloudflare.com with test data only. Latency is HTTPS round-trip, not ICMP ping."))
                .font(.caption2).foregroundStyle(.secondary)
            Legend()
        }
    }
}

struct PermissionsPage: View {
    @State private var notif = L.t("读取中…", "Loading…")
    func txt(_ ok: Bool, _ denied: Bool, _ restricted: Bool = false) -> String {
        ok ? L.t("已授权", "Granted") : (denied ? L.t("已拒绝", "Denied") : (restricted ? L.t("受限制", "Restricted") : L.t("未询问", "Not asked")))
    }
    var items: [InfoItem] {
        let cam = AVCaptureDevice.authorizationStatus(for: .video)
        let mic = AVAudioApplication.shared.recordPermission
        let loc = CLLocationManager().authorizationStatus
        let ph = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let mo = CMMotionActivityManager.authorizationStatus()
        return [
            InfoItem(L.t("相机", "Camera"), txt(cam == .authorized, cam == .denied, cam == .restricted)),
            InfoItem(L.t("麦克风", "Microphone"), txt(mic == .granted, mic == .denied)),
            InfoItem(L.t("定位", "Location"), txt(loc == .authorizedAlways || loc == .authorizedWhenInUse, loc == .denied, loc == .restricted)),
            InfoItem(L.t("照片", "Photos"), txt(ph == .authorized || ph == .limited, ph == .denied, ph == .restricted)),
            InfoItem(L.t("运动与健身", "Motion & Fitness"), txt(mo == .authorized, mo == .denied, mo == .restricted)),
            InfoItem(L.t("通知", "Notifications"), notif),
        ]
    }
    var body: some View {
        Page(L.t("权限状态", "Permissions")) {
            LiveInfo(every: 2) { items }
            Button(L.t("打开系统设置", "Open Settings")) {
                if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
            }.buttonStyle(.borderedProminent)
            Legend()
        }.task {
            let s = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            switch s {
            case .authorized, .provisional, .ephemeral: notif = L.t("已授权", "Granted")
            case .denied: notif = L.t("已拒绝", "Denied")
            default: notif = L.t("未询问", "Not asked")
            }
        }
    }
}
