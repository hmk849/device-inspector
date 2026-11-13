import SwiftUI
import UIKit
import Foundation
import Network
import CoreMotion
import CoreLocation
import AVFoundation
import LocalAuthentication
import Metal
import Darwin

enum CheckState: String {
    case normal = "正常"
    case warning = "异常"
    case unsupported = "不支持"
    case estimate = "估算"
    case waiting = "待检测"
}

struct CheckItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String
    let state: CheckState
}

enum InspectorSection: String, CaseIterable, Identifiable {
    case device = "设备信息"
    case hardware = "硬件检测"
    case network = "网络检测"
    case performance = "性能测试"
    case system = "系统检测"
    case sensors = "传感器"
    case report = "健康报告"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .device: "iphone"
        case .hardware: "cpu"
        case .network: "wifi"
        case .performance: "speedometer"
        case .system: "gearshape.2"
        case .sensors: "gyroscope"
        case .report: "doc.text"
        }
    }
    var subtitle: String {
        switch self {
        case .device: "型号、系统、芯片与存储"
        case .hardware: "电池、生物识别与多媒体能力"
        case .network: "连接状态与网络质量"
        case .performance: "运行环境与基础性能指标"
        case .system: "权限、系统能力与隐私边界"
        case .sensors: "运动、方向与气压传感器"
        case .report: "汇总当前可读取的检测结果"
        }
    }
}

@MainActor
final class InspectorStore: ObservableObject {
    @Published var networkDescription = "正在检测"
    @Published var isConnected = false
    @Published var motionText = "等待启动传感器"
    @Published var acceleration = "—"
    @Published var rotation = "—"
    @Published var pressure = "—"
    @Published var heading = "—"
    @Published var lastLatency = "未测试"
    @Published var batteryLevel: String = "系统未提供"
    @Published var batteryState: String = "未知"
    @Published var lastUpdated = Date()
    @Published var isTesting = false
    @Published var testResult = "尚未运行"
    @Published var gpuTestResult = "尚未运行"
    @Published var storageTestResult = "尚未运行"
    @Published var networkSpeedResult = "尚未测速"
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "DeviceInspector.NetworkMonitor")
    private let motion = CMMotionManager()
    private let altimeter = CMAltimeter()
    private let location = CLLocationManager()

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshBattery()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
                self?.networkDescription = Self.describe(path)
                self?.lastUpdated = Date()
            }
        }
        monitor.start(queue: queue)
        location.headingFilter = 5
        location.delegate = nil
    }

    func refreshBattery() {
        let device = UIDevice.current
        if device.batteryLevel >= 0 {
            batteryLevel = "\(Int(device.batteryLevel * 100))%"
        } else {
            batteryLevel = "系统未提供"
        }
        switch device.batteryState {
        case .charging: batteryState = "充电中"
        case .full: batteryState = "已充满"
        case .unplugged: batteryState = "未充电"
        default: batteryState = "未知"
        }
        lastUpdated = Date()
    }

    private static func describe(_ path: NWPath) -> String {
        guard path.status == .satisfied else { return "无网络连接" }
        var types: [String] = []
        if path.usesInterfaceType(.wifi) { types.append("Wi‑Fi") }
        if path.usesInterfaceType(.cellular) { types.append("蜂窝网络") }
        if path.usesInterfaceType(.wiredEthernet) { types.append("以太网") }
        if path.usesInterfaceType(.loopback) { types.append("本地回环") }
        if path.isExpensive { types.append("按流量计费") }
        if path.isConstrained { types.append("低数据模式") }
        return types.isEmpty ? "已连接" : types.joined(separator: " · ")
    }

    func startSensors() {
        guard motion.isAccelerometerAvailable || motion.isGyroAvailable else {
            motionText = "此设备未提供运动传感器"
            return
        }
        motion.deviceMotionUpdateInterval = 0.2
        if motion.isDeviceMotionAvailable {
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, error in
                guard let data else { return }
                Task { @MainActor in
                    self?.acceleration = String(format: "X %.3f  Y %.3f  Z %.3f", data.userAcceleration.x, data.userAcceleration.y, data.userAcceleration.z)
                    self?.rotation = String(format: "X %.3f  Y %.3f  Z %.3f", data.rotationRate.x, data.rotationRate.y, data.rotationRate.z)
                    self?.motionText = error == nil ? "实时采集中" : "传感器读取失败"
                }
            }
        } else {
            motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let v = data?.acceleration else { return }
                Task { @MainActor in
                    self?.acceleration = String(format: "X %.3f  Y %.3f  Z %.3f", v.x, v.y, v.z)
                    self?.motionText = "加速度计实时采集中"
                }
            }
        }
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
                guard let data else { return }
                Task { @MainActor in
                    self?.pressure = String(format: "相对高度 %.2f m · 气压 %.2f kPa", data.relativeAltitude.doubleValue, data.pressure.doubleValue)
                }
            }
        } else {
            pressure = "设备不支持或系统未开放"
        }
    }

    func stopSensors() {
        motion.stopDeviceMotionUpdates()
        motion.stopAccelerometerUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        motionText = "已停止"
    }

    func testLatency() async {
        guard isConnected else { lastLatency = "无网络"; return }
        let start = Date()
        guard let url = URL(string: "https://www.apple.com/library/test/success.html") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            lastLatency = status == 200 ? "\(ms) ms（HTTPS 往返时间）" : "\(ms) ms（HTTP \(status)）"
        } catch {
            lastLatency = "连接失败：\(error.localizedDescription)"
        }
    }

    func runBasicTest() async {
        isTesting = true
        testResult = "正在执行 CPU 与内存基础测试…"
        let start = Date()
        let count = 350_000
        var value = 0.0
        for i in 1...count { value += sin(Double(i)) * cos(Double(i) / 2) }
        let elapsed = Date().timeIntervalSince(start)
        let memory = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
        testResult = String(format: "完成 · %.3f 秒 · %llu GB 物理内存 · 校验 %.2f", elapsed, memory, value)
        isTesting = false
    }

    func runGPUtest() async {
        isTesting = true
        gpuTestResult = "GPU 测试中…"
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try MetalDiagnostics.run()
            }.value
            gpuTestResult = String(format: "%.2f ms · %@", result.milliseconds, result.device)
        } catch {
            gpuTestResult = "测试失败：\(error.localizedDescription)"
        }
        isTesting = false
    }

    func runStorageTest() async {
        isTesting = true
        storageTestResult = "存储测试中…"
        do {
            let result = try await Task.detached(priority: .utility) {
                try StorageDiagnostics.run()
            }.value
            storageTestResult = String(format: "写入 %.1f MB/s · 读取 %.1f MB/s（临时文件 8 MiB）", result.writeMBps, result.readMBps)
        } catch {
            storageTestResult = "测试失败：\(error.localizedDescription)"
        }
        isTesting = false
    }

    func runNetworkSpeedTest() async {
        networkSpeedResult = "测速中…（约传输 1.25 MB）"
        do {
            let result = try await NetworkDiagnostics.run()
            networkSpeedResult = String(format: "下载 %.1f Mbps · 上传 %.1f Mbps", result.downloadMbps, result.uploadMbps)
        } catch {
            networkSpeedResult = "测速失败：\(error.localizedDescription)"
        }
    }

    func items(for section: InspectorSection) -> [CheckItem] {
        let device = UIDevice.current
        let process = ProcessInfo.processInfo
        let screen = UIScreen.main
        let model = Self.machineIdentifier()
        let storage = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        let total = (storage?.volumeTotalCapacity).map { Self.bytes(Int64($0)) } ?? "系统未提供"
        let free = (storage?.volumeAvailableCapacity).map { Self.bytes(Int64($0)) } ?? "系统未提供"
        let gpu = MTLCreateSystemDefaultDevice()?.name ?? "Metal 不可用"
        switch section {
        case .device:
            return [
                .init(title:"设备名称", value:device.name, detail:"用户可修改的设备名称", state:.normal),
                .init(title:"设备型号", value:Self.friendlyModel(model), detail:"型号标识符：\(model)", state:.normal),
                .init(title:"系统版本", value:device.systemVersion, detail:process.operatingSystemVersionString, state:.normal),
                .init(title:"内核版本", value:Self.kernelVersion(), detail:"通过 uname 获取", state:.normal),
                .init(title:"CPU 架构", value:Self.architecture(), detail:"运行进程架构；具体芯片型号未公开", state:.normal),
                .init(title:"CPU 核心数", value:"\(process.processorCount)", detail:"逻辑处理器数量，不等于性能核心数量", state:.normal),
                .init(title:"GPU", value:gpu, detail:"Metal 默认设备名称", state:.normal),
                .init(title:"屏幕分辨率", value:"\(Int(screen.nativeBounds.width)) × \(Int(screen.nativeBounds.height))", detail:"原生像素尺寸", state:.normal),
                .init(title:"刷新率上限", value:"\(screen.maximumFramesPerSecond) Hz", detail:"设备支持的最大刷新率，实际帧率会变化", state:.normal),
                .init(title:"物理内存", value:Self.bytes(Int64(process.physicalMemory)), detail:"系统报告的设备物理内存", state:.normal),
                .init(title:"存储总容量", value:total, detail:"当前容器可见的卷容量", state:total == "系统未提供" ? .unsupported : .normal),
                .init(title:"可用存储", value:free, detail:"当前容器可见的可用容量", state:free == "系统未提供" ? .unsupported : .normal)
            ]
        case .hardware:
            let context = LAContext()
            var authError: NSError?
            let bio = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError)
            let biometricName: String
            switch context.biometryType {
            case .faceID: biometricName = "Face ID"
            case .touchID: biometricName = "Touch ID"
            case .opticID: biometricName = "Optic ID"
            case .none: biometricName = "未配置 / 不支持"
            @unknown default: biometricName = "未知"
            }
            let camera = AVCaptureDevice.authorizationStatus(for: .video)
            let mic = AVCaptureDevice.authorizationStatus(for: .audio)
            let bioText = bio ? "可用于认证" : "当前不可用"
            return [
                .init(title:"电池电量", value:batteryLevel, detail:"UIDevice 电量读数", state:batteryLevel == "系统未提供" ? .unsupported : .normal),
                .init(title:"充电状态", value:batteryState, detail:"不代表电池健康度", state:.normal),
                .init(title:"电池健康度", value:"系统限制，无法读取", detail:"公开 API 不提供最大容量、循环次数或健康百分比", state:.unsupported),
                .init(title:"电池温度", value:"系统限制，无法读取", detail:"iOS 不向普通 App 公开电池温度", state:.unsupported),
                .init(title:"生物识别", value:biometricName, detail:"\(bioText)；不读取面容/指纹数据", state:bio ? .normal : .warning),
                .init(title:"前后摄像头", value:AVCaptureDevice.default(for: .video) == nil ? "未发现可用摄像头" : "发现视频采集设备", detail:"实际使用前仍需用户授权", state:.normal),
                .init(title:"摄像头权限", value:Self.permission(camera), detail:"相机访问权限状态", state:camera == .denied ? .warning : .normal),
                .init(title:"麦克风权限", value:Self.permission(mic), detail:"麦克风访问权限状态", state:mic == .denied ? .warning : .normal),
                .init(title:"音频输出", value:AVAudioSession.sharedInstance().currentRoute.outputs.map { $0.portName }.joined(separator: "、").isEmpty ? "未检测到输出端口" : AVAudioSession.sharedInstance().currentRoute.outputs.map { $0.portName }.joined(separator: "、"), detail:"当前音频路由；不播放测试音", state:.normal),
                .init(title:"陀螺仪", value:CMMotionManager().isGyroAvailable ? "可用" : "不可用", detail:"Core Motion 能力检测", state:CMMotionManager().isGyroAvailable ? .normal : .unsupported),
                .init(title:"加速度计", value:CMMotionManager().isAccelerometerAvailable ? "可用" : "不可用", detail:"Core Motion 能力检测", state:CMMotionManager().isAccelerometerAvailable ? .normal : .unsupported),
                .init(title:"气压计", value:CMAltimeter.isRelativeAltitudeAvailable() ? "可用" : "不可用", detail:"相对高度/气压数据需启动传感器", state:CMAltimeter.isRelativeAltitudeAvailable() ? .normal : .unsupported),
                .init(title:"GPS / 定位", value:CLLocationManager.locationServicesEnabled() ? "系统定位服务已开启" : "系统定位服务已关闭", detail:"不会自动请求或上传位置", state:CLLocationManager.locationServicesEnabled() ? .normal : .warning),
                .init(title:"振动马达", value:"系统限制，无法独立验证", detail:"公开 API 无法确认马达物理状态", state:.unsupported),
                .init(title:"扬声器 / 触控 / 环境光", value:"无法进行完整硬件自检", detail:"需用户交互或系统未开放底层诊断接口", state:.unsupported)
            ]
        case .network:
            return [
                .init(title:"网络连接", value:isConnected ? "已连接" : "未连接", detail:networkDescription, state:isConnected ? .normal : .warning),
                .init(title:"网络类型", value:networkDescription, detail:"NWPathMonitor 提供的接口类型", state:.normal),
                .init(title:"HTTPS 延迟", value:lastLatency, detail:"对 Apple 测试地址发起一次 HTTPS 请求；不是 ICMP Ping", state:lastLatency == "未测试" ? .waiting : .normal),
                .init(title:"本机 IP / DNS", value:"部分信息不可读取", detail:"iOS 不提供通用、可靠的 DNS 配置枚举接口；未扫描局域网", state:.unsupported),
                .init(title:"下载 / 上传速度", value:networkSpeedResult, detail:"用户主动测速；经 Cloudflare 公共测速端点，结果受服务器和网络影响", state:networkSpeedResult == "尚未测速" ? .waiting : .estimate),
                .init(title:"蜂窝信号强度", value:"系统限制，无法读取", detail:"普通 App 无法读取精确蜂窝信号指标", state:.unsupported),
                .init(title:"VPN 状态", value:"未进行可靠判定", detail:"网络接口名称不能作为 VPN 状态的确定证据", state:.unsupported)
            ]
        case .performance:
            return [
                .init(title:"CPU 基础测试", value:testResult, detail:"本地数学运算微基准；非行业标准跑分", state:testResult == "尚未运行" ? .waiting : .normal),
                .init(title:"GPU 信息", value:gpu, detail:"Metal 设备标识", state:.normal),
                .init(title:"GPU 计算测试", value:gpuTestResult, detail:"Metal 向量加法微基准；不是行业标准 GPU 跑分", state:gpuTestResult == "尚未运行" ? .waiting : .estimate),
                .init(title:"物理内存", value:Self.bytes(Int64(process.physicalMemory)), detail:"系统报告的设备物理内存容量", state:.normal),
                .init(title:"系统内存概览", value:MemoryDiagnostics.read().map { "已用估算 \(Self.bytes(Int64($0.usedEstimateBytes))) · 空闲 \(Self.bytes(Int64($0.freeBytes)))" } ?? "读取失败", detail:"Mach VM 页统计；属于设备级汇总估算，不代表单个 App 占用", state:MemoryDiagnostics.read() == nil ? .unsupported : .estimate),
                .init(title:"本 App 内存占用", value:MemoryDiagnostics.read()?.appFootprintBytes.map { Self.bytes(Int64($0)) } ?? "暂不可用", detail:"仅统计 Device Inspector 自身物理内存 footprint", state:MemoryDiagnostics.read()?.appFootprintBytes == nil ? .unsupported : .normal),
                .init(title:"存储读写", value:storageTestResult, detail:"仅在 App 临时目录读写 8 MiB 测试文件，完成后删除", state:storageTestResult == "尚未运行" ? .waiting : .estimate),
                .init(title:"游戏帧率", value:"仅限本 App 可测场景", detail:"不能读取其他 App 或全系统游戏帧率", state:.unsupported),
                .init(title:"热状态", value:Self.thermal(process.thermalState), detail:"ProcessInfo 热状态等级，不是温度读数", state:process.thermalState == .critical ? .warning : .normal),
                .init(title:"综合性能评分", value:"暂不生成", detail:"不同设备与测试环境不可直接比较；避免伪造评分", state:.unsupported)
            ]
        case .system:
            let notif = UIApplication.shared.isRegisteredForRemoteNotifications ? "已注册远程通知" : "未注册远程通知"
            return [
                .init(title:"系统版本 / 构建", value:process.operatingSystemVersionString, detail:"公开系统版本信息；构建号可能不完整", state:.normal),
                .init(title:"低电量模式", value:process.isLowPowerModeEnabled ? "已开启" : "未开启", detail:"ProcessInfo", state:.normal),
                .init(title:"热状态", value:Self.thermal(process.thermalState), detail:"系统热状态等级", state:process.thermalState == .critical ? .warning : .normal),
                .init(title:"后台刷新 / 通知", value:notif, detail:"仅显示本 App 远程通知注册状态", state:.normal),
                .init(title:"低电量模式", value:process.isLowPowerModeEnabled ? "已开启" : "未开启", detail:"ProcessInfo", state:.normal),
                .init(title:"系统运行时长", value:String(format: "%.1f 小时", process.systemUptime / 3600), detail:"自上次启动以来的运行时间", state:.normal),
                .init(title:"已安装 App 列表", value:"系统限制，无法枚举", detail:"iOS 沙盒不允许普通 App 获取完整已安装应用列表", state:.unsupported),
                .init(title:"开发者模式", value:"系统限制，无法读取", detail:"无公开 API 可供普通 App 查询该状态", state:.unsupported),
                .init(title:"越狱状态", value:"无法可靠判定", detail:"不执行越狱探测或绕过安全机制", state:.unsupported),
                .init(title:"隐私权限", value:"进入各项目查看", detail:"权限状态由系统设置与用户授权决定", state:.normal)
            ]
        case .sensors:
            return [
                .init(title:"传感器状态", value:motionText, detail:"点击下方按钮开始实时采样", state:motionText == "实时采集中" ? .normal : .waiting),
                .init(title:"加速度", value:acceleration, detail:"单位：g；用户加速度数据", state:.normal),
                .init(title:"角速度", value:rotation, detail:"单位：rad/s；设备旋转速率", state:.normal),
                .init(title:"气压 / 相对高度", value:pressure, detail:"设备支持时由 CMAltimeter 提供", state:pressure == "—" ? .unsupported : .normal),
                .init(title:"指南针", value:"需用户授权并启动定位更新", detail:"方向读数会受环境磁场干扰", state:.waiting),
                .init(title:"环境光传感器", value:"系统限制，无法读取", detail:"iOS 不提供通用环境光传感器读数 API", state:.unsupported),
                .init(title:"传感器校准", value:"由 iOS 自动管理", detail:"App 无法直接执行底层硬件校准", state:.unsupported)
            ]
        case .report:
            return reportItems()
        }
    }

    func reportItems() -> [CheckItem] {
        let all = [InspectorSection.device, .hardware, .network, .performance, .system, .sensors]
            .flatMap { items(for: $0) }
        return all
    }

    var healthScore: Int {
        let items = reportItems().filter { $0.state != .unsupported && $0.state != .waiting && $0.state != .estimate }
        guard !items.isEmpty else { return 0 }
        let good = items.filter { $0.state == .normal }.count
        return Int(Double(good) / Double(items.count) * 100)
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
    static func permission(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: "已授权"
        case .denied: "已拒绝"
        case .restricted: "受限制"
        case .notDetermined: "尚未询问"
        @unknown default: "未知"
        }
    }
    static func thermal(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "正常"
        case .fair: "轻度升温"
        case .serious: "严重升温"
        case .critical: "临界"
        @unknown default: "未知"
        }
    }
    static func machineIdentifier() -> String {
        var system = utsname()
        uname(&system)
        return withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: system.machine)) {
                String(cString: $0)
            }
        }
    }
    static func friendlyModel(_ id: String) -> String {
        let map = ["iPhone15,4":"iPhone 15","iPhone15,5":"iPhone 15 Plus","iPhone16,1":"iPhone 15 Pro","iPhone16,2":"iPhone 15 Pro Max","iPhone17,3":"iPhone 16","iPhone17,4":"iPhone 16 Plus","iPhone17,1":"iPhone 16 Pro","iPhone17,2":"iPhone 16 Pro Max"]
        return map[id] ?? id
    }
    static func architecture() -> String {
        #if arch(arm64)
        return "ARM64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "未知"
        #endif
    }
    static func kernelVersion() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.release) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: info.release)) { String(cString: $0) }
        }
    }
}
