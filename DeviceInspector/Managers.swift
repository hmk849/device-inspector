import SwiftUI
import UIKit
import AVFoundation
import CoreMotion
import CoreLocation
import CoreHaptics
import LocalAuthentication
import Network
import os

// MARK: - Motion sensors
enum SensorKind: String, CaseIterable, Identifiable {
    case accel, gyro, mag, baro
    var id: String { rawValue }
    var title: String {
        switch self {
        case .accel: return L.t("加速度计", "Accelerometer")
        case .gyro: return L.t("陀螺仪", "Gyroscope")
        case .mag: return L.t("磁力计", "Magnetometer")
        case .baro: return L.t("气压计", "Barometer")
        }
    }
    var unit: String { switch self { case .accel: return "g"; case .gyro: return "rad/s"; case .mag: return "µT"; case .baro: return "hPa" } }
    var icon: String { switch self { case .accel: return "arrow.up.and.down.and.arrow.left.and.right"; case .gyro: return "gyroscope"; case .mag: return "scope"; case .baro: return "barometer" } }
}

struct CalibResult { let verdict: Verdict; let text: String }

final class SensorHub: ObservableObject {
    struct Sample: Identifiable { let id = UUID(); let t: Double; let x: Double; let y: Double; let z: Double }
    @Published var samples: [Sample] = []
    @Published var supported = true
    @Published var calibrating = false
    @Published var calibResult: CalibResult?
    private let mm = CMMotionManager()
    private let alt = CMAltimeter()
    private var kind: SensorKind = .accel
    private var t0 = Date()
    private var calib: [Sample] = []
    private var calibStart = Date()

    func start(_ k: SensorKind) {
        stop(); kind = k; samples = []; calibResult = nil; t0 = Date(); supported = true
        let q = OperationQueue.main
        switch k {
        case .accel:
            guard mm.isAccelerometerAvailable else { supported = false; return }
            mm.accelerometerUpdateInterval = 0.05
            mm.startAccelerometerUpdates(to: q) { [weak self] d, _ in if let a = d?.acceleration { self?.push(a.x, a.y, a.z) } }
        case .gyro:
            guard mm.isGyroAvailable else { supported = false; return }
            mm.gyroUpdateInterval = 0.05
            mm.startGyroUpdates(to: q) { [weak self] d, _ in if let a = d?.rotationRate { self?.push(a.x, a.y, a.z) } }
        case .mag:
            guard mm.isMagnetometerAvailable else { supported = false; return }
            mm.magnetometerUpdateInterval = 0.05
            mm.startMagnetometerUpdates(to: q) { [weak self] d, _ in if let a = d?.magneticField { self?.push(a.x, a.y, a.z) } }
        case .baro:
            guard CMAltimeter.isRelativeAltitudeAvailable() else { supported = false; return }
            alt.startRelativeAltitudeUpdates(to: q) { [weak self] d, _ in
                if let d = d { self?.push(d.pressure.doubleValue * 10, d.relativeAltitude.doubleValue, 0) }
            }
        }
    }
    func stop() {
        mm.stopAccelerometerUpdates(); mm.stopGyroUpdates(); mm.stopMagnetometerUpdates(); alt.stopRelativeAltitudeUpdates()
    }
    private func push(_ x: Double, _ y: Double, _ z: Double) {
        let s = Sample(t: Date().timeIntervalSince(t0), x: x, y: y, z: z)
        samples.append(s); if samples.count > 100 { samples.removeFirst() }
        if calibrating {
            calib.append(s)
            if Date().timeIntervalSince(calibStart) >= 3 { finishCalibration() }
        }
    }
    func calibrate() { calib = []; calibStart = Date(); calibrating = true; calibResult = nil }

    private func finishCalibration() {
        calibrating = false
        let n = Double(calib.count)
        guard n >= 10 else { calibResult = CalibResult(verdict: .abnormal, text: L.t("采样不足", "Too few samples")); return }
        func mean(_ f: (Sample) -> Double) -> Double { calib.map(f).reduce(0, +) / n }
        func sd(_ f: (Sample) -> Double) -> Double { let m = mean(f); return sqrt(calib.map { pow(f($0) - m, 2) }.reduce(0, +) / n) }
        let mag: (Sample) -> Double = { sqrt($0.x * $0.x + $0.y * $0.y + $0.z * $0.z) }
        let m = mean(mag), s = sd(mag)
        var ok = false; var text = ""
        switch kind {
        case .accel:
            ok = abs(m - 1) < 0.1 && s < 0.05
            text = String(format: L.t("静止合加速度均值 %.3f g（应≈1），噪声 %.4f", "Rest magnitude %.3f g (expect ≈1), noise %.4f"), m, s)
            if !ok { text += L.t("。请将设备平放静止后重试", ". Place the device flat and still, then retry") }
        case .gyro:
            ok = m < 0.05 && s < 0.03
            text = String(format: L.t("静止零偏 %.4f rad/s，噪声 %.4f", "Rest bias %.4f rad/s, noise %.4f"), m, s)
            if !ok { text += L.t("。请保持静止重试", ". Keep the device still and retry") }
        case .mag:
            ok = (15...100).contains(m) && s < 8
            text = String(format: L.t("磁场强度 %.1f µT（地磁约 25–65），波动 %.2f", "Field %.1f µT (Earth ≈ 25–65), jitter %.2f"), m, s)
            if !ok { text += L.t("。请远离磁铁/金属后重试", ". Move away from magnets/metal and retry") }
        case .baro:
            let p = mean { $0.x }, ps = sd { $0.x }
            ok = (300...1100).contains(p) && ps < 0.5
            text = String(format: L.t("气压 %.2f hPa，波动 %.3f", "Pressure %.2f hPa, jitter %.3f"), p, ps)
        }
        calibResult = CalibResult(verdict: ok ? .normal : .abnormal, text: text)
    }
}

// MARK: - Location / compass
final class LocationModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let m = CLLocationManager()
    @Published var status: CLAuthorizationStatus = .notDetermined
    @Published var loc: CLLocation?
    @Published var heading: CLHeading?
    @Published var running = false
    override init() {
        super.init(); status = m.authorizationStatus; m.delegate = self; m.desiredAccuracy = kCLLocationAccuracyBest
    }
    func startLocation() {
        if m.authorizationStatus == .notDetermined { m.requestWhenInUseAuthorization() }
        m.startUpdatingLocation(); running = true
    }
    func startHeading() { if CLLocationManager.headingAvailable() { m.startUpdatingHeading() } }
    func stop() { m.stopUpdatingLocation(); m.stopUpdatingHeading(); running = false }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { status = manager.authorizationStatus }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { loc = locations.last }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) { heading = newHeading }
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { true }
}

// MARK: - Camera
final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var pl: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView(); v.pl.session = session; v.pl.videoGravity = .resizeAspectFill; return v
    }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}
final class CameraController: ObservableObject {
    @Published var running = false
    @Published var message = ""
    let session = AVCaptureSession()
    func start(_ pos: AVCaptureDevice.Position) {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            DispatchQueue.main.async {
                guard ok else { self.message = L.t("未授权相机权限（请在设置中开启）", "Camera permission denied (enable in Settings)"); return }
                self.configure(pos)
            }
        }
    }
    private func configure(_ pos: AVCaptureDevice.Position) {
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: pos),
              let inp = try? AVCaptureDeviceInput(device: dev), session.canAddInput(inp) else {
            session.commitConfiguration(); running = false
            message = L.t("无法打开该摄像头（不支持或被占用）", "Cannot open this camera (unsupported or busy)"); return
        }
        session.addInput(inp); session.commitConfiguration()
        DispatchQueue.global().async {
            self.session.startRunning()
            DispatchQueue.main.async {
                self.running = self.session.isRunning
                self.message = self.running ? "" : L.t("摄像头启动失败", "Camera failed to start")
            }
        }
    }
    func stop() { DispatchQueue.global().async { self.session.stopRunning() }; running = false }
}

// MARK: - Audio
final class AudioTester: ObservableObject {
    @Published var level: Float = 0
    @Published var micRunning = false
    @Published var message = ""
    private let engine = AVAudioEngine()
    private var toneEngine: AVAudioEngine?

    func startMic() {
        AVAudioApplication.requestRecordPermission { ok in
            DispatchQueue.main.async {
                guard ok else { self.message = L.t("未授权麦克风权限", "Microphone permission denied"); return }
                do {
                    let s = AVAudioSession.sharedInstance()
                    try s.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
                    try s.setActive(true)
                    let input = self.engine.inputNode
                    let fmt = input.outputFormat(forBus: 0)
                    input.removeTap(onBus: 0)
                    input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buf, _ in
                        guard let ch = buf.floatChannelData?[0] else { return }
                        let n = Int(buf.frameLength); var sum: Float = 0
                        for i in 0..<n { sum += ch[i] * ch[i] }
                        let rms = sqrt(sum / Float(max(n, 1)))
                        DispatchQueue.main.async { self.level = rms }
                    }
                    try self.engine.start(); self.micRunning = true; self.message = ""
                } catch { self.message = error.localizedDescription }
            }
        }
    }
    func stopMic() { engine.inputNode.removeTap(onBus: 0); engine.stop(); micRunning = false; level = 0 }

    func playTone() {
        let e = AVAudioEngine(); let sr = 44100.0; var phase = 0.0
        let node = AVAudioSourceNode { _, _, frames, abl in
            let list = UnsafeMutableAudioBufferListPointer(abl)
            for f in 0..<Int(frames) {
                let v = Float(sin(phase)) * 0.3
                phase += 2 * .pi * 440 / sr; if phase > 2 * .pi { phase -= 2 * .pi }
                for b in list { b.mData?.assumingMemoryBound(to: Float.self)[f] = v }
            }
            return noErr
        }
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2) else { return }
        e.attach(node); e.connect(node, to: e.mainMixerNode, format: fmt)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            try e.start(); toneEngine = e; message = ""
        } catch { message = error.localizedDescription }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { e.stop(); self.toneEngine = nil }
    }
}

// MARK: - Haptics
final class HapticTester {
    private var engine: CHHapticEngine?
    func play() -> String? {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return L.t("设备不支持", "Not supported") }
        do {
            let e = try CHHapticEngine(); try e.start(); engine = e
            let ev = CHHapticEvent(eventType: .hapticContinuous,
                                   parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                                                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)],
                                   relativeTime: 0, duration: 0.6)
            let p = try e.makePlayer(with: CHHapticPattern(events: [ev], parameters: []))
            try p.start(atTime: 0); return nil
        } catch { return error.localizedDescription }
    }
}

// MARK: - Multi-touch pad
final class TouchPadView: UIView {
    var onUpdate: ((Int, Int) -> Void)?
    private var maxCount = 0
    private var dots: [UITouch: UIView] = [:]
    override init(frame: CGRect) {
        super.init(frame: frame); isMultipleTouchEnabled = true
        backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.5); layer.cornerRadius = 22
    }
    required init?(coder: NSCoder) { fatalError() }
    private func update(_ touches: Set<UITouch>, ended: Bool) {
        for t in touches {
            if ended { dots[t]?.removeFromSuperview(); dots[t] = nil; continue }
            var d = dots[t]
            if d == nil {
                let v = UIView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
                v.layer.cornerRadius = 32; v.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.6)
                addSubview(v); dots[t] = v; d = v
            }
            d?.center = t.location(in: self)
        }
        maxCount = max(maxCount, dots.count); onUpdate?(dots.count, maxCount)
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches, ended: false) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches, ended: false) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches, ended: true) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches, ended: true) }
}
struct TouchPad: UIViewRepresentable {
    let onUpdate: (Int, Int) -> Void
    func makeUIView(context: Context) -> TouchPadView { let v = TouchPadView(); v.onUpdate = onUpdate; return v }
    func updateUIView(_ uiView: TouchPadView, context: Context) {}
}

// MARK: - Network
final class NetMonitor: ObservableObject {
    @Published var path: NWPath?
    private let mon = NWPathMonitor()
    init() {
        mon.pathUpdateHandler = { [weak self] p in DispatchQueue.main.async { self?.path = p } }
        mon.start(queue: DispatchQueue(label: "net.monitor"))
    }
    deinit { mon.cancel() }
}

@MainActor final class NetTester: ObservableObject {
    @Published var pings: [Double?] = []
    @Published var down: Double?
    @Published var up: Double?
    @Published var status = ""
    @Published var running = false
    var valid: [Double] { pings.compactMap { $0 } }
    var avg: Double? { valid.isEmpty ? nil : valid.reduce(0, +) / Double(valid.count) }
    var jitter: Double? {
        guard let a = avg, valid.count > 1 else { return nil }
        return sqrt(valid.map { pow($0 - a, 2) }.reduce(0, +) / Double(valid.count))
    }
    var loss: Double? { pings.isEmpty ? nil : Double(pings.filter { $0 == nil }.count) / Double(pings.count) * 100 }

    func ping(count: Int, interval: Double = 0.3) async {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData; cfg.timeoutIntervalForRequest = 3
        let s = URLSession(configuration: cfg)
        var req = URLRequest(url: URL(string: "https://www.apple.com/library/test/success.html")!); req.httpMethod = "HEAD"
        _ = try? await s.data(for: req)   // warm-up (DNS/TLS) not counted
        for _ in 0..<count {
            let t = Sys.now()
            do { _ = try await s.data(for: req); pings.append((Sys.now() - t) * 1000) } catch { pings.append(nil) }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1e9))
        }
    }
    func runSpeed() async {
        running = true; pings = []; down = nil; up = nil
        status = L.t("测试延迟…", "Testing latency…"); await ping(count: 8)
        status = L.t("测试下载…", "Testing download…"); down = await downloadMbps()
        status = L.t("测试上传…", "Testing upload…"); up = await uploadMbps()
        status = ""; running = false
    }
    func runStability(seconds: Int) async {
        running = true; pings = []; down = nil; up = nil
        status = L.t("稳定性测试中…", "Stability test running…")
        await ping(count: seconds * 2, interval: 0.5)
        status = ""; running = false
    }
    private func downloadMbps() async -> Double? {
        let cfg = URLSessionConfiguration.ephemeral; cfg.timeoutIntervalForResource = 30
        let req = URLRequest(url: URL(string: "https://speed.cloudflare.com/__down?bytes=25000000")!)
        let t = Sys.now()
        guard let (url, _) = try? await URLSession(configuration: cfg).download(for: req) else { return nil }
        let dt = Sys.now() - t
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.doubleValue ?? 0
        try? FileManager.default.removeItem(at: url)
        return size > 0 ? size * 8 / dt / 1e6 : nil
    }
    private func uploadMbps() async -> Double? {
        let cfg = URLSessionConfiguration.ephemeral; cfg.timeoutIntervalForResource = 30
        var req = URLRequest(url: URL(string: "https://speed.cloudflare.com/__up")!); req.httpMethod = "POST"
        let bytes = 10_000_000
        let t = Sys.now()
        guard (try? await URLSession(configuration: cfg).upload(for: req, from: Data(count: bytes))) != nil else { return nil }
        return Double(bytes) * 8 / (Sys.now() - t) / 1e6
    }
}

// MARK: - FPS
final class FPSMeter: NSObject, ObservableObject {
    @Published var fps = 0.0
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var frames: [Double] = []
    func start(maxFPS: Int) {
        frames = []; last = 0
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: Float(maxFPS), preferred: Float(maxFPS))
        l.add(to: .main, forMode: .common); link = l
    }
    @objc private func tick(_ l: CADisplayLink) {
        if last > 0 {
            let dt = l.timestamp - last
            if dt > 0 { frames.append(dt); fps = fps == 0 ? 1 / dt : 0.9 * fps + 0.1 / dt }
        }
        last = l.timestamp
    }
    func stop(maxFPS: Int) -> (avg: Double, low1: Double, dropped: Int, frames: Int) {
        link?.invalidate(); link = nil
        guard !frames.isEmpty else { return (0, 0, 0, 0) }
        let avg = Double(frames.count) / frames.reduce(0, +)
        let worst = frames.sorted(by: >).prefix(max(1, frames.count / 100))
        let low = 1 / (worst.reduce(0, +) / Double(worst.count))
        let dropped = frames.filter { $0 > 1.5 / Double(maxFPS) }.count
        return (avg, low, dropped, frames.count)
    }
}
struct StressCanvas: View {
    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { gc, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                for i in 0..<500 {
                    let a = Double(i) * 0.157 + t * (1 + Double(i % 7) * 0.1)
                    let r = 20 + Double(i % 50) * 3
                    let x = size.width / 2 + cos(a) * (size.width / 2.3) * (0.3 + Double(i % 9) / 12)
                    let y = size.height / 2 + sin(a * 1.3) * (size.height / 2.3) * (0.3 + Double(i % 11) / 14)
                    gc.fill(Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)),
                            with: .color(Color(hue: Double(i % 36) / 36, saturation: 0.8, brightness: 1).opacity(0.35)))
                }
            }
        }
    }
}

// MARK: - Benchmarks store
enum BenchKind: String, CaseIterable, Identifiable {
    case cpu, gpu, memory, storage, fps
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cpu: return L.t("CPU 性能", "CPU")
        case .gpu: return L.t("GPU 图形性能", "GPU")
        case .memory: return L.t("内存压力测试", "Memory")
        case .storage: return L.t("存储读写", "Storage I/O")
        case .fps: return L.t("游戏帧率", "Frame rate")
        }
    }
    var icon: String { switch self { case .cpu: return "cpu"; case .gpu: return "cube.transparent"; case .memory: return "memorychip"; case .storage: return "internaldrive"; case .fps: return "speedometer" } }
    var desc: String {
        switch self {
        case .cpu: return L.t("单核与多核整数/浮点混合循环，实测迭代吞吐。", "Single/multi-core mixed integer+FP loop; measures real iteration throughput.")
        case .gpu: return L.t("Metal 计算着色器 FMA 吞吐，使用 GPU 硬件时间戳计时。", "Metal compute FMA throughput timed with GPU hardware timestamps.")
        case .memory: return L.t("内存拷贝带宽 + 在安全上限内逐块分配并写入，观察是否触发内存警告。", "Copy bandwidth + chunked allocation up to a safe cap; watches for memory warnings.")
        case .storage: return L.t("绕过缓存顺序写入/读取 128MB 临时文件（测试后自动删除）。", "Sequential 128MB write/read with caching disabled (temp file deleted afterwards).")
        case .fps: return L.t("全屏动画压力场景，用 CADisplayLink 统计平均帧率、1% Low 与掉帧。", "Full-screen animation stress; CADisplayLink gives avg fps, 1% low and dropped frames.")
        }
    }
}
struct BenchResult { var points: Int; var verdict: Verdict; var lines: [InfoItem] }

@MainActor final class BenchStore: ObservableObject {
    @Published var results: [BenchKind: BenchResult] = [:]
    @Published var running: BenchKind?
    private func pts(_ v: Double, _ ref: Double) -> Int { Int(max(0, v / ref * 1000)) }

    /// Composite 0-100 (relative to reference constants; estimated). Each component is capped at 1000 pts.
    var composite: Int? {
        guard !results.isEmpty else { return nil }
        let v = results.values.map { Double(min($0.points, 1000)) }
        return Int((v.reduce(0, +) / Double(v.count) / 10).rounded())
    }

    func runAll() async {
        let awake = UserDefaults.standard.bool(forKey: "keepAwakeDuringTests")
        if awake { UIApplication.shared.isIdleTimerDisabled = true }
        for k in [BenchKind.cpu, .gpu, .memory, .storage] { await run(k) }
        if awake { UIApplication.shared.isIdleTimerDisabled = false }
    }

    func run(_ k: BenchKind) async {
        guard running == nil else { return }
        running = k
        let awake = UserDefaults.standard.bool(forKey: "keepAwakeDuringTests")
        if awake { UIApplication.shared.isIdleTimerDisabled = true }
        defer { running = nil; if awake { UIApplication.shared.isIdleTimerDisabled = false } }
        let f1 = { (v: Double) in String(format: "%.1f", v) }
        switch k {
        case .cpu:
            let r = await Task.detached(priority: .userInitiated) { Bench.cpu() }.value
            let p = (pts(r.single, 120) + pts(r.multi, 600)) / 2
            results[.cpu] = BenchResult(points: p, verdict: .normal, lines: [
                InfoItem(L.t("单核吞吐", "Single-core"), "\(f1(r.single)) Miter/s"),
                InfoItem(L.t("多核吞吐", "Multi-core") + " (\(r.cores))", "\(f1(r.multi)) Miter/s"),
                InfoItem(L.t("多核/单核比", "Multi/single ratio"), String(format: "%.2fx", r.multi / max(r.single, 0.001))),
                InfoItem(L.t("相对得分（参考值归一）", "Relative points (reference-normalised)"), "\(p)", .estimated)])
        case .gpu:
            let r = await Task.detached(priority: .userInitiated) { Bench.gpu() }.value
            if let r = r {
                let p = pts(r.gflops, 1000)
                results[.gpu] = BenchResult(points: p, verdict: .normal, lines: [
                    InfoItem("GPU", r.name),
                    InfoItem(L.t("FMA 计算吞吐", "FMA throughput"), "\(f1(r.gflops)) GFLOPS"),
                    InfoItem(L.t("GPU 耗时", "GPU time"), "\(f1(r.ms)) ms"),
                    InfoItem(L.t("相对得分", "Relative points"), "\(p)", .estimated)])
            } else {
                results[.gpu] = BenchResult(points: 0, verdict: .unsupported, lines: [InfoItem("GPU", L.t("Metal 计算不可用", "Metal compute unavailable"))])
            }
        case .memory:
            var warnings = 0
            let tok = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in warnings += 1 }
            let r = await Task.detached(priority: .userInitiated) { (Bench.memBandwidth(), Bench.memoryPressure()) }.value
            NotificationCenter.default.removeObserver(tok)
            let p = pts(r.0, 40)
            let ok = warnings == 0 && r.1.allocated >= r.1.cap - (32 << 20)
            results[.memory] = BenchResult(points: p, verdict: ok ? .normal : .abnormal, lines: [
                InfoItem(L.t("拷贝带宽", "Copy bandwidth"), "\(f1(r.0)) GB/s"),
                InfoItem(L.t("压力测试分配量", "Allocated under test"), "\(Sys.fmt(Int64(r.1.allocated), binary: true)) / \(Sys.fmt(Int64(r.1.cap), binary: true))"),
                InfoItem(L.t("峰值占用", "Peak footprint"), Sys.fmt(Int64(r.1.peak), binary: true)),
                InfoItem(L.t("内存警告次数", "Memory warnings"), "\(warnings)"),
                InfoItem(L.t("相对得分", "Relative points"), "\(p)", .estimated)])
        case .storage:
            let r = await Task.detached(priority: .userInitiated) { Bench.storage() }.value
            if let r = r {
                let p = (pts(r.write, 800) + pts(r.read, 1500)) / 2
                results[.storage] = BenchResult(points: p, verdict: .normal, lines: [
                    InfoItem(L.t("顺序写入", "Seq. write"), "\(f1(r.write)) MB/s"),
                    InfoItem(L.t("顺序读取", "Seq. read"), "\(f1(r.read)) MB/s"),
                    InfoItem(L.t("相对得分", "Relative points"), "\(p)", .estimated)])
            } else {
                results[.storage] = BenchResult(points: 0, verdict: .abnormal, lines: [InfoItem(L.t("存储读写", "Storage I/O"), L.t("写入失败（空间不足或被拒绝）", "Write failed (no space or denied)"))])
            }
        case .fps: break
        }
    }
}

// MARK: - Health runner
final class ProbeBox: @unchecked Sendable { var n = 0; var mag = 0.0 }

@MainActor final class HealthRunner: ObservableObject {
    @Published var results: [CheckResult] = []
    @Published var score: Int?
    @Published var running = false
    @Published var date: Date?
    private let mon = NWPathMonitor()
    private var path: NWPath?
    init() {
        mon.pathUpdateHandler = { [weak self] p in Task { @MainActor in self?.path = p } }
        mon.start(queue: DispatchQueue(label: "health.net"))
    }

    func probe(_ k: SensorKind) async -> (n: Int, mag: Double) {
        let mm = CMMotionManager(); let alt = CMAltimeter(); let box = ProbeBox()
        switch k {
        case .accel:
            guard mm.isAccelerometerAvailable else { return (-1, 0) }
            mm.accelerometerUpdateInterval = 0.05
            mm.startAccelerometerUpdates(to: .main) { d, _ in if let a = d?.acceleration { box.n += 1; box.mag = sqrt(a.x * a.x + a.y * a.y + a.z * a.z) } }
        case .gyro:
            guard mm.isGyroAvailable else { return (-1, 0) }
            mm.gyroUpdateInterval = 0.05
            mm.startGyroUpdates(to: .main) { d, _ in if d != nil { box.n += 1 } }
        case .mag:
            guard mm.isMagnetometerAvailable else { return (-1, 0) }
            mm.magnetometerUpdateInterval = 0.05
            mm.startMagnetometerUpdates(to: .main) { d, _ in if let a = d?.magneticField { box.n += 1; box.mag = sqrt(a.x * a.x + a.y * a.y + a.z * a.z) } }
        case .baro:
            guard CMAltimeter.isRelativeAltitudeAvailable() else { return (-1, 0) }
            alt.startRelativeAltitudeUpdates(to: .main) { d, _ in if let d = d { box.n += 1; box.mag = d.pressure.doubleValue * 10 } }
        }
        try? await Task.sleep(nanoseconds: 1_800_000_000)
        mm.stopAccelerometerUpdates(); mm.stopGyroUpdates(); mm.stopMagnetometerUpdates(); alt.stopRelativeAltitudeUpdates()
        return (box.n, box.mag)
    }

    func run(bench: BenchStore? = nil) async {
        guard !running else { return }
        running = true
        var r: [CheckResult] = []
        func add(_ t: String, _ i: String, _ v: Verdict, _ d: String) { r.append(CheckResult(title: t, icon: i, verdict: v, detail: d)) }

        // Battery
        let dev = UIDevice.current; dev.isBatteryMonitoringEnabled = true
        if dev.batteryLevel < 0 { add(L.t("电池", "Battery"), "battery.100", .unsupported, L.t("无法读取电量（模拟器或系统限制）", "Level unavailable (simulator/restricted)")) }
        else { add(L.t("电池", "Battery"), "battery.100", .normal, String(format: "%.0f%% · 健康度/循环次数 %@", dev.batteryLevel * 100, L.restricted)) }
        // Motion sensors
        for k in SensorKind.allCases {
            let p = await probe(k)
            if p.n < 0 { add(k.title, k.icon, .unsupported, L.t("硬件不可用", "Hardware unavailable")) }
            else if p.n == 0 { add(k.title, k.icon, .abnormal, L.t("1.8 秒内无数据", "No data in 1.8 s")) }
            else if (k == .mag && !(5...150).contains(p.mag)) || p.mag.isNaN { add(k.title, k.icon, .abnormal, String(format: L.t("读数异常 %.1f", "Implausible reading %.1f"), p.mag)) }
            else { add(k.title, k.icon, .normal, String(format: L.t("约 %.0f Hz", "≈ %.0f Hz"), Double(p.n) / 1.8)) }
        }
        add(L.t("指南针", "Compass"), "location.north.line", CLLocationManager.headingAvailable() ? .normal : .unsupported, CLLocationManager.headingAvailable() ? L.t("航向可用", "Heading available") : L.t("不可用", "Unavailable"))
        add(L.t("光线传感器", "Light sensor"), "sun.max", .unsupported, L.restricted)
        // Cameras / audio
        let cams = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera, .builtInTrueDepthCamera], mediaType: .video, position: .unspecified).devices
        add(L.t("摄像头", "Cameras"), "camera", cams.isEmpty ? .unsupported : .normal, cams.isEmpty ? L.t("未检测到", "None found") : "\(cams.count) " + L.t("个", "found"))
        let hasFront = cams.contains { $0.position == .front }, hasBack = cams.contains { $0.position == .back }
        add(L.t("前/后置摄像头", "Front / back"), "camera.viewfinder", (hasFront || hasBack) ? .normal : .unsupported, "\(L.t("前置", "Front")) \(hasFront ? "✓" : "✗") · \(L.t("后置", "Back")) \(hasBack ? "✓" : "✗")")
        let s = AVAudioSession.sharedInstance()
        add(L.t("麦克风", "Microphone"), "mic", s.isInputAvailable ? .normal : .unsupported, s.isInputAvailable ? L.t("输入可用", "Input available") : L.t("无输入", "No input"))
        add(L.t("扬声器/输出", "Speaker / output"), "speaker.wave.2", s.currentRoute.outputs.isEmpty ? .unsupported : .normal, s.currentRoute.outputs.map { $0.portName }.joined(separator: ", "))
        add(L.t("多点触控", "Multi-touch"), "hand.tap", .manual, L.t("请在「触摸屏」页实测", "Run the touch pad test"))
        let bio = Info.biometry()
        add("Face ID / Touch ID", "faceid", bio.type == L.t("无", "None") ? .unsupported : .normal, bio.available ? bio.type : "\(bio.type) · \(bio.error ?? "")")
        add("GPS", "location", CLLocationManager.locationServicesEnabled() ? .normal : .abnormal, CLLocationManager.locationServicesEnabled() ? L.t("定位服务开启", "Location services on") : L.t("定位服务已关闭", "Location services off"))
        add(L.t("振动马达", "Haptics"), "waveform", CHHapticEngine.capabilitiesForHardware().supportsHaptics ? .normal : .unsupported, "Core Haptics")
        // Network
        if path == nil { try? await Task.sleep(nanoseconds: 400_000_000) }
        let online = path?.status == .satisfied
        add(L.t("网络连接", "Network"), "wifi", online ? .normal : .abnormal, online ? Info.network(path).prefix(2).map { $0.value }.joined(separator: " · ") : L.t("当前无网络", "Offline"))
        if online {
            let nt = NetTester(); await nt.ping(count: 4, interval: 0.1)
            if let a = nt.avg, (nt.loss ?? 100) < 50 { add(L.t("网络延迟", "Latency"), "timer", a < 500 ? .normal : .abnormal, String(format: "%.0f ms · %@ %.0f%%", a, L.t("丢包", "loss"), nt.loss ?? 0)) }
            else { add(L.t("网络延迟", "Latency"), "timer", .abnormal, L.t("请求失败或丢包严重", "Requests failed / heavy loss")) }
        }
        // Storage / memory / thermal / system
        if let st = Sys.storage(), st.total > 0 {
            let ratio = Double(st.free) / Double(st.total)
            add(L.t("存储空间", "Storage"), "internaldrive", ratio > 0.05 ? .normal : .abnormal, "\(Sys.fmt(st.free)) " + L.t("可用", "free"))
        }
        let avail = Int(os_proc_available_memory())
        add(L.t("内存", "Memory"), "memorychip", .normal, avail > 0 ? "\(Sys.fmt(Int64(avail), binary: true)) " + L.t("可再用", "available") : L.t("物理内存可读取", "RAM readable"))
        let th = ProcessInfo.processInfo.thermalState
        add(L.t("系统热状态", "Thermal state"), "thermometer.medium", (th == .serious || th == .critical) ? .abnormal : .normal, Info.thermalText(th))
        add(L.t("GPU / Metal", "GPU / Metal"), "cube.transparent", MTLCreateSystemDefaultDevice() != nil ? .normal : .unsupported, "Metal")
        add("VPN", "lock.shield", .normal, Info.vpnActive() ? L.t("检测到 VPN 接口（启发式）", "VPN interface found (heuristic)") : L.t("未检测到", "Not detected"))
        // Benchmarks (if executed)
        if let b = bench {
            for k in BenchKind.allCases { if let br = b.results[k] { add(k.title, k.icon, br.verdict, br.verdict == .normal ? "\(br.points) pts" : (br.lines.first?.value ?? "")) } }
        }
        results = r
        let normal = r.filter { $0.verdict == .normal }.count, bad = r.filter { $0.verdict == .abnormal }.count
        score = (normal + bad) == 0 ? nil : Int((Double(normal) / Double(normal + bad) * 100).rounded())
        date = Date(); running = false
    }
}

// MARK: - PDF
@MainActor enum ReportPDF {
    static func make(results: [CheckResult], score: Int?, bench: BenchStore, device: [InfoItem]) -> URL? {
        let rect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let f = UIGraphicsPDFRendererFormat(); f.documentInfo = [kCGPDFContextTitle as String: "Device Inspector Report"]
        let renderer = UIGraphicsPDFRenderer(bounds: rect, format: f)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DeviceInspector-\(stamp).pdf")
        do {
            try renderer.writePDF(to: url) { ctx in
                var y: CGFloat = 40
                func line(_ s: String, size: CGFloat = 11, bold: Bool = false, color: UIColor = .black, x: CGFloat = 40) {
                    let attrs: [NSAttributedString.Key: Any] = [.font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size), .foregroundColor: color]
                    let w: CGFloat = 515 - (x - 40)
                    let h = (s as NSString).boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, attributes: attrs, context: nil).height
                    if y + h > 800 { ctx.beginPage(); y = 40 }
                    (s as NSString).draw(in: CGRect(x: x, y: y, width: w, height: h), withAttributes: attrs)
                    y += h + 5
                }
                ctx.beginPage()
                line("Device Inspector — " + L.t("设备检测报告", "Device Report"), size: 22, bold: true)
                line(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium), color: .gray)
                y += 6
                line(L.t("设备健康评分: ", "Health score: ") + (score.map(String.init) ?? "--") + " / 100", size: 16, bold: true)
                if let c = bench.composite { line(L.t("综合性能评分（相对参考值，估算）: ", "Performance score (reference-relative, estimated): ") + "\(c) / 100", size: 13) }
                y += 8; line(L.t("设备信息", "Device"), size: 14, bold: true)
                for i in device { line("\(i.key): \(i.value)  [\(i.kind.label)]", size: 10) }
                y += 8; line(L.t("检测结果", "Check results"), size: 14, bold: true)
                for r in results {
                    let c: UIColor = r.verdict == .normal ? .systemGreen : (r.verdict == .abnormal ? .systemRed : .gray)
                    line("[\(r.verdict.label)] \(r.title)", bold: true, color: c)
                    line(r.detail, size: 10, color: .darkGray, x: 60)
                }
                y += 8; line(L.t("性能测试明细", "Benchmarks"), size: 14, bold: true)
                for k in BenchKind.allCases { if let br = bench.results[k] {
                    line(k.title, bold: true)
                    for i in br.lines { line("\(i.key): \(i.value)  [\(i.kind.label)]", size: 10, x: 60) }
                } }
                y += 10
                line(L.t("说明：仅使用 Apple 公开 API。标注「系统限制」的项目 iOS 不开放，未予虚构；「估算」项为查表或启发式推断。", "Notes: Apple public APIs only. Items marked Restricted are not exposed by iOS and are not fabricated; Estimated items are lookups or heuristics."), size: 9, color: .gray)
            }
            return url
        } catch { return nil }
    }
}
