import UIKit
import Metal
import AVFoundation
import CoreMedia
import CoreMotion
import CoreLocation
import LocalAuthentication
import CoreHaptics
import CoreTelephony
import ARKit
import CoreNFC
import NearbyInteraction
import Network
import os

@MainActor enum Info {
    static var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    static func device() -> [InfoItem] {
        let d = UIDevice.current, id = Sys.identifier
        return [
            InfoItem(L.t("设备型号", "Model"), Sys.names[id] ?? L.t("未收录型号（见标识符）", "Unlisted model (see identifier)"), .estimated),
            InfoItem(L.t("型号标识符", "Model identifier"), id),
            InfoItem(L.t("设备名称", "Device name"), d.name),
            InfoItem(L.t("设备类型", "Idiom"), d.userInterfaceIdiom == .pad ? "iPad" : "iPhone"),
            InfoItem(L.t("运行环境", "Environment"), Sys.isSimulator ? L.t("模拟器（数据不代表真机）", "Simulator (not real hardware)") : L.t("真机", "Physical device")),
        ]
    }

    static func cpu() -> [InfoItem] {
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        func b(_ n: String) -> String? { Sys.int(n).map { Sys.fmt($0, binary: true) } }
        return [
            InfoItem(L.t("指令架构", "Architecture"), arch),
            InfoItem(L.t("芯片型号（按型号查表）", "Chip (model lookup)"), Sys.chips[Sys.identifier], .estimated),
            InfoItem(L.t("物理核心", "Physical cores"), Sys.int("hw.physicalcpu").map(String.init)),
            InfoItem(L.t("逻辑核心", "Logical cores"), Sys.int("hw.logicalcpu").map(String.init)),
            InfoItem(L.t("当前活动核心", "Active cores"), "\(ProcessInfo.processInfo.activeProcessorCount)"),
            InfoItem(L.t("CPU 频率", "CPU frequency"), Sys.int("hw.cpufrequency").map { "\($0 / 1_000_000) MHz" }),
            InfoItem("L1 D-Cache", b("hw.l1dcachesize")),
            InfoItem("L2 Cache", b("hw.l2cachesize")),
            InfoItem(L.t("缓存行大小", "Cache line"), Sys.int("hw.cachelinesize").map { "\($0) B" }),
        ]
    }

    static func gpu() -> [InfoItem] {
        guard let dev = MTLCreateSystemDefaultDevice() else { return [InfoItem("GPU", L.t("Metal 不可用", "Metal unavailable"))] }
        var fam: [String] = []
        let all: [(MTLGPUFamily, String)] = [(.apple5, "A12"), (.apple6, "A13"), (.apple7, "A14/M1"), (.apple8, "A15/A16"), (.apple9, "A17+")]
        for (f, n) in all where dev.supportsFamily(f) { fam.append(n) }
        return [
            InfoItem(L.t("GPU 名称（Metal）", "GPU name (Metal)"), dev.name),
            InfoItem(L.t("支持的 GPU 家族", "GPU families"), fam.isEmpty ? "—" : fam.joined(separator: ", ")),
            InfoItem(L.t("统一内存", "Unified memory"), dev.hasUnifiedMemory ? L.t("是", "Yes") : L.t("否", "No")),
            InfoItem(L.t("推荐工作集上限", "Recommended working set"), Sys.fmt(Int64(dev.recommendedMaxWorkingSetSize), binary: true)),
            InfoItem(L.t("最大线程组", "Max threads/group"), "\(dev.maxThreadsPerThreadgroup.width)"),
            InfoItem(L.t("硬件光线追踪", "Hardware ray tracing"), dev.supportsRaytracing ? L.t("支持", "Supported") : L.t("不支持", "Not supported")),
            InfoItem(L.t("GPU 核心数", "GPU core count"), nil),
        ]
    }

    static func display() -> [InfoItem] {
        guard let s = screen else { return [InfoItem(L.t("屏幕", "Screen"), nil)] }
        let nb = s.nativeBounds, fps = s.maximumFramesPerSecond
        return [
            InfoItem(L.t("逻辑分辨率", "Points"), "\(Int(s.bounds.width))×\(Int(s.bounds.height)) pt @\(Int(s.scale))x"),
            InfoItem(L.t("物理分辨率", "Native pixels"), "\(Int(nb.width))×\(Int(nb.height))"),
            InfoItem(L.t("最高刷新率", "Max refresh rate"), "\(fps) Hz" + (fps >= 120 ? " (ProMotion)" : "")),
            InfoItem(L.t("屏幕亮度设置", "Brightness setting"), String(format: "%.0f%%", s.brightness * 100)),
            InfoItem(L.t("广色域 P3", "Wide color P3"), s.traitCollection.displayGamut == .P3 ? L.t("支持", "Supported") : L.t("不支持", "Not supported")),
            InfoItem(L.t("EDR 余量", "EDR headroom"), String(format: "%.1fx", s.potentialEDRHeadroom)),
            InfoItem(L.t("屏幕尺寸(英寸)", "Diagonal (inches)"), nil),
        ]
    }

    static func memory() -> [InfoItem] {
        var r: [InfoItem] = [InfoItem(L.t("物理内存", "Physical RAM"), Sys.int("hw.memsize").map { Sys.fmt($0, binary: true) })]
        if let v = Sys.vm() {
            r += [InfoItem(L.t("空闲", "Free"), Sys.fmt(Int64(v.free), binary: true)),
                  InfoItem(L.t("活跃", "Active"), Sys.fmt(Int64(v.active), binary: true)),
                  InfoItem(L.t("非活跃", "Inactive"), Sys.fmt(Int64(v.inactive), binary: true)),
                  InfoItem(L.t("常驻(Wired)", "Wired"), Sys.fmt(Int64(v.wired), binary: true)),
                  InfoItem(L.t("压缩内存", "Compressed"), Sys.fmt(Int64(v.compressed), binary: true))]
        } else { r.append(InfoItem(L.t("系统内存分布", "System memory breakdown"), nil)) }
        r.append(InfoItem(L.t("本 App 占用", "This app footprint"), Sys.fmt(Int64(Sys.appFootprint()), binary: true)))
        let a = Int(os_proc_available_memory())
        r.append(InfoItem(L.t("本 App 可再用内存", "Available to this app"), a > 0 ? Sys.fmt(Int64(a), binary: true) : nil))
        return r
    }

    static func storage() -> [InfoItem] {
        guard let s = Sys.storage() else { return [InfoItem(L.t("存储", "Storage"), nil)] }
        return [
            InfoItem(L.t("总容量（数据卷）", "Total (data volume)"), Sys.fmt(s.total)),
            InfoItem(L.t("已用空间", "Used"), Sys.fmt(s.total - s.free)),
            InfoItem(L.t("可用空间", "Available"), Sys.fmt(s.free)),
            InfoItem(L.t("可用（含可清理）", "Available incl. purgeable"), Sys.fmt(s.important)),
        ]
    }

    static func battery() -> [InfoItem] {
        let d = UIDevice.current; d.isBatteryMonitoringEnabled = true
        let st: String
        switch d.batteryState {
        case .charging: st = L.t("充电中", "Charging")
        case .full: st = L.t("已充满", "Full")
        case .unplugged: st = L.t("未充电", "Unplugged")
        default: st = L.t("未知", "Unknown")
        }
        return [
            InfoItem(L.t("电量", "Level"), d.batteryLevel >= 0 ? String(format: "%.0f%%", d.batteryLevel * 100) : nil),
            InfoItem(L.t("充电状态", "State"), d.batteryState == .unknown ? nil : st),
            InfoItem(L.t("低电量模式", "Low Power Mode"), ProcessInfo.processInfo.isLowPowerModeEnabled ? L.t("开启", "On") : L.t("关闭", "Off")),
            InfoItem(L.t("电池最大容量（用户录入）", "Max capacity (user-entered)"), UserDefaults.standard.double(forKey: "manualHealth") > 0 ? "\(Int(UserDefaults.standard.double(forKey: "manualHealth")))%" : nil, .estimated),
            InfoItem(L.t("循环次数（用户录入）", "Cycle count (user-entered)"), UserDefaults.standard.integer(forKey: "manualCycles") > 0 ? "\(UserDefaults.standard.integer(forKey: "manualCycles"))" : nil, .estimated),
            InfoItem(L.t("电池温度", "Battery temperature"), nil),
            InfoItem(L.t("电压/电流", "Voltage / current"), nil),
        ]
    }

    static func thermal() -> [InfoItem] {
        [InfoItem(L.t("系统热状态", "Thermal state"), thermalText(ProcessInfo.processInfo.thermalState)),
         InfoItem(L.t("CPU/GPU 具体温度", "CPU/GPU temperature"), nil)]
    }
    static func thermalText(_ s: ProcessInfo.ThermalState) -> String {
        switch s {
        case .nominal: return L.t("正常 (Nominal)", "Nominal")
        case .fair: return L.t("轻微升温 (Fair)", "Fair")
        case .serious: return L.t("较热 (Serious)", "Serious")
        case .critical: return L.t("过热 (Critical)", "Critical")
        @unknown default: return "?"
        }
    }

    static func cameras() -> [InfoItem] {
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera, .builtInTrueDepthCamera]
        let devs = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified).devices
        if devs.isEmpty { return [InfoItem(L.t("摄像头", "Cameras"), L.t("未检测到（模拟器或不支持）", "None found (simulator or unsupported)"))] }
        return devs.map { d in
            let best = d.formats.map { CMVideoFormatDescriptionGetDimensions($0.formatDescription) }
                .max { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }
            let pos = d.position == .front ? L.t("前置", "Front") : (d.position == .back ? L.t("后置", "Back") : "—")
            let res = best.map { "\($0.width)×\($0.height)" } ?? "—"
            return InfoItem("\(pos) · \(d.localizedName)", "\(L.t("最大视频格式", "Max video format")) \(res)" + (d.hasTorch ? " · " + L.t("闪光灯", "Torch") : ""))
        }
    }

    static func audio() -> [InfoItem] {
        let s = AVAudioSession.sharedInstance()
        let ins = s.availableInputs?.map { $0.portName }.joined(separator: ", ")
        let outs = s.currentRoute.outputs.map { $0.portName }.joined(separator: ", ")
        let perm: String
        switch AVAudioApplication.shared.recordPermission {
        case .granted: perm = L.t("已授权", "Granted")
        case .denied: perm = L.t("已拒绝", "Denied")
        default: perm = L.t("未询问", "Not asked")
        }
        return [
            InfoItem(L.t("音频输入可用", "Input available"), s.isInputAvailable ? L.t("是", "Yes") : L.t("否", "No")),
            InfoItem(L.t("输入设备", "Input devices"), (ins?.isEmpty ?? true) ? "—" : ins),
            InfoItem(L.t("当前输出路由", "Output route"), outs.isEmpty ? "—" : outs),
            InfoItem(L.t("麦克风权限", "Microphone permission"), perm),
            InfoItem(L.t("采样率", "Sample rate"), String(format: "%.0f Hz", s.sampleRate)),
        ]
    }

    static func touch() -> [InfoItem] {
        let f = screen?.traitCollection.forceTouchCapability ?? .unknown
        return [
            InfoItem(L.t("触摸屏", "Touchscreen"), L.t("有", "Present")),
            InfoItem(L.t("压感(3D Touch)", "Force touch"), f == .available ? L.t("支持", "Supported") : L.t("不支持", "Not supported")),
            InfoItem(L.t("多点触控", "Multi-touch"), L.t("请在测试面板实测最大触点数", "Use the pad below to measure max touches"), .estimated),
        ]
    }

    static func biometry() -> (type: String, available: Bool, error: String?) {
        let c = LAContext(); var err: NSError?
        let ok = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
        let t: String
        switch c.biometryType {
        case .faceID: t = "Face ID"
        case .touchID: t = "Touch ID"
        case .opticID: t = "Optic ID"
        default: t = L.t("无", "None")
        }
        return (t, ok, err?.localizedDescription)
    }
    static func biometryItems() -> [InfoItem] {
        let b = biometry()
        return [InfoItem(L.t("生物识别硬件", "Biometric hardware"), b.type),
                InfoItem(L.t("当前可用", "Currently usable"), b.available ? L.t("可用", "Yes") : (b.error ?? L.t("不可用", "No")))]
    }

    static func haptics() -> [InfoItem] {
        [InfoItem(L.t("Core Haptics 振动马达", "Core Haptics engine"), CHHapticEngine.capabilitiesForHardware().supportsHaptics ? L.t("支持", "Supported") : L.t("不支持", "Not supported"))]
    }

    static func gpsItems() -> [InfoItem] {
        let m = CLLocationManager()
        let a: String
        switch m.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: a = L.t("已授权", "Authorized")
        case .denied: a = L.t("已拒绝", "Denied")
        case .restricted: a = L.t("受限制", "Restricted")
        default: a = L.t("未询问", "Not asked")
        }
        return [InfoItem(L.t("定位服务总开关", "Location services"), CLLocationManager.locationServicesEnabled() ? L.t("开启", "On") : L.t("关闭", "Off")),
                InfoItem(L.t("本 App 定位权限", "App permission"), a),
                InfoItem(L.t("指南针(航向)可用", "Heading available"), CLLocationManager.headingAvailable() ? L.t("是", "Yes") : L.t("否", "No")),
                InfoItem(L.t("精确定位", "Accuracy authorization"), m.accuracyAuthorization == .fullAccuracy ? L.t("精确", "Full") : L.t("模糊", "Reduced"))]
    }

    // MARK: network
    static func radio(_ s: String) -> String {
        switch s {
        case CTRadioAccessTechnologyNR, CTRadioAccessTechnologyNRNSA: return "5G"
        case CTRadioAccessTechnologyLTE: return "LTE (4G)"
        case CTRadioAccessTechnologyWCDMA, CTRadioAccessTechnologyHSDPA, CTRadioAccessTechnologyHSUPA: return "3G"
        case CTRadioAccessTechnologyGPRS, CTRadioAccessTechnologyEdge: return "2G"
        default: return s
        }
    }
    static func network(_ p: NWPath?) -> [InfoItem] {
        guard let p = p else { return [InfoItem(L.t("网络", "Network"), L.t("读取中…", "Loading…"))] }
        let st: String
        switch p.status {
        case .satisfied: st = L.t("已连接", "Connected")
        case .unsatisfied: st = L.t("未连接", "Disconnected")
        default: st = L.t("需要连接", "Requires connection")
        }
        let types: [(NWInterface.InterfaceType, String)] = [(.wifi, "Wi-Fi"), (.cellular, L.t("蜂窝", "Cellular")), (.wiredEthernet, L.t("有线", "Ethernet")), (.other, L.t("其他/VPN", "Other/VPN"))]
        let used = types.filter { p.usesInterfaceType($0.0) }.map { $0.1 }
        var r: [InfoItem] = [
            InfoItem(L.t("连接状态", "Status"), st),
            InfoItem(L.t("网络类型", "Network type"), used.isEmpty ? "—" : used.joined(separator: " + ")),
            InfoItem(L.t("Wi-Fi 已连接", "Wi-Fi connected"), p.usesInterfaceType(.wifi) ? L.t("是", "Yes") : L.t("否", "No")),
            InfoItem(L.t("计费网络(蜂窝/热点)", "Expensive (cellular/hotspot)"), p.isExpensive ? L.t("是", "Yes") : L.t("否", "No")),
            InfoItem(L.t("低数据模式", "Low Data Mode"), p.isConstrained ? L.t("开启", "On") : L.t("关闭", "Off")),
            InfoItem("IPv4 / IPv6", "\(p.supportsIPv4 ? "✓" : "✗") / \(p.supportsIPv6 ? "✓" : "✗")"),
            InfoItem(L.t("支持 DNS", "DNS usable"), p.supportsDNS ? L.t("是", "Yes") : L.t("否", "No")),
            InfoItem(L.t("Wi-Fi 名称 (SSID)", "Wi-Fi SSID"), nil),
            InfoItem(L.t("DNS 服务器地址", "DNS servers"), Sys.dnsServers()),
        ]
        for (n, ip) in Sys.localIPs() { r.append(InfoItem("\(L.t("本地地址", "Local IP")) · \(n)", ip)) }
        let ct = CTTelephonyNetworkInfo()
        let techs = ct.serviceCurrentRadioAccessTechnology?.values.map { radio($0) }
        r.append(InfoItem(L.t("蜂窝制式", "Cellular radio"), (techs?.isEmpty ?? true) ? L.t("无蜂窝服务/未检测到", "No cellular service detected") : techs!.joined(separator: ", ")))
        r.append(InfoItem(L.t("运营商名称/信号强度", "Carrier / signal strength"), nil))
        return r
    }

    // MARK: system
    static func vpnActive() -> Bool {
        guard let s = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
              let scoped = s["__SCOPED__"] as? [String: Any] else { return false }
        return scoped.keys.contains { k in ["tap", "tun", "ppp", "ipsec"].contains { k.contains($0) } }
    }
    static func uptime() -> String {
        let f = DateComponentsFormatter(); f.allowedUnits = [.day, .hour, .minute]; f.unitsStyle = .abbreviated
        return f.string(from: ProcessInfo.processInfo.systemUptime) ?? "—"
    }
    static func system() -> [InfoItem] {
        let d = UIDevice.current, b = Bundle.main
        return [
            InfoItem(L.t("系统版本", "OS"), "\(d.systemName) \(d.systemVersion)"),
            InfoItem(L.t("构建版本", "Build"), Sys.str("kern.osversion")),
            InfoItem(L.t("内核版本", "Kernel"), Sys.str("kern.version")),
            InfoItem(L.t("内核发行号", "Kernel release"), Sys.str("kern.osrelease")),
            InfoItem(L.t("开机时长", "Uptime"), uptime()),
            InfoItem(L.t("系统语言", "Language"), Locale.preferredLanguages.first),
            InfoItem(L.t("地区 / 时区", "Region / Time zone"), "\(Locale.current.region?.identifier ?? "—") / \(TimeZone.current.identifier)"),
            InfoItem(L.t("低电量模式", "Low Power Mode"), ProcessInfo.processInfo.isLowPowerModeEnabled ? L.t("开启", "On") : L.t("关闭", "Off")),
            InfoItem(L.t("热状态", "Thermal"), thermalText(ProcessInfo.processInfo.thermalState)),
            InfoItem(L.t("VPN 连接（启发式判断）", "VPN (heuristic)"), vpnActive() ? L.t("检测到 VPN 接口", "VPN interface found") : L.t("未检测到", "Not detected"), .estimated),
            InfoItem(L.t("开发者模式状态", "Developer Mode"), nil),
            installedApps(),
            InfoItem(L.t("本 App 版本", "This app"), "\(b.bundleIdentifier ?? "") \(b.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")"),
        ]
    }

    static let probeApps: [(String, String)] = [("weixin", "微信"), ("mqq", "QQ"), ("alipay", "支付宝"), ("sinaweibo", "微博"), ("snssdk1128", "抖音"), ("taobao", "淘宝"), ("bilibili", "哔哩哔哩"), ("twitter", "X/Twitter"), ("fb", "Facebook"), ("instagram", "Instagram"), ("whatsapp", "WhatsApp"), ("tg", "Telegram"), ("line", "LINE"), ("youtube", "YouTube"), ("comgooglemaps", "Google Maps"), ("spotify", "Spotify"), ("nflx", "Netflix"), ("uber", "Uber"), ("slack", "Slack"), ("zoommtg", "Zoom"), ("dingtalk", "钉钉"), ("orpheus", "网易云音乐"), ("iosamap", "高德地图"), ("baidumap", "百度地图"), ("imeituan", "美团"), ("openapp.jdmobile", "京东"), ("pinduoduo", "拼多多"), ("xhsdiscover", "小红书"), ("kwai", "快手"), ("openai", "ChatGPT")]
    static func installedApps() -> InfoItem {
        let found = probeApps.filter { a in URL(string: a.0 + "://").map { UIApplication.shared.canOpenURL($0) } ?? false }.map { $0.1 }
        return InfoItem(L.t("已安装 App（仅探测预设的 30 个）", "Installed apps (30 preset only)"),
                        found.isEmpty ? L.t("预设列表中未检测到", "None of the preset apps found") : found.joined(separator: "、"), .estimated)
    }
    static func features() -> [InfoItem] {
        func yn(_ v: Bool) -> String { v ? L.t("支持", "Supported") : L.t("不支持", "Not supported") }
        return [
            InfoItem("ARKit", yn(ARWorldTrackingConfiguration.isSupported)),
            InfoItem(L.t("LiDAR 场景重建", "LiDAR scene reconstruction"), yn(ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh))),
            InfoItem(L.t("NFC 读取", "NFC reading"), yn(NFCNDEFReaderSession.readingAvailable)),
            InfoItem(L.t("超宽带 UWB", "Ultra Wideband"), yn(NISession.deviceCapabilities.supportsPreciseDistanceMeasurement)),
            InfoItem("Core Haptics", yn(CHHapticEngine.capabilitiesForHardware().supportsHaptics)),
            InfoItem("Metal", yn(MTLCreateSystemDefaultDevice() != nil)),
            InfoItem(L.t("气压计", "Barometer"), yn(CMAltimeter.isRelativeAltitudeAvailable())),
            InfoItem(L.t("陀螺仪", "Gyroscope"), yn(CMMotionManager().isGyroAvailable)),
            InfoItem(L.t("磁力计", "Magnetometer"), yn(CMMotionManager().isMagnetometerAvailable)),
            InfoItem(L.t("生物识别", "Biometrics"), biometry().type),
        ]
    }
}
