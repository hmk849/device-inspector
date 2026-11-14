import Foundation
import Darwin
import Metal
import os

enum Sys {
    static func str(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
    static func int(_ name: String) -> Int64? {
        var v: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { return nil }
        return v
    }
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    static var identifier: String {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "Simulator"
        #else
        var u = utsname(); uname(&u)
        return withUnsafePointer(to: &u.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        #endif
    }
    /// Lookup table (estimated: Apple exposes only the identifier).
    static let names: [String: String] = [
        "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13", "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,6": "iPhone SE (3rd)", "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max", "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max", "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone17,5": "iPhone 16e",
        "iPhone18,1": "iPhone 17 Pro", "iPhone18,2": "iPhone 17 Pro Max", "iPhone18,3": "iPhone 17", "iPhone18,4": "iPhone Air",
        "iPad13,18": "iPad (10th)", "iPad14,3": "iPad Pro 11\" (4th)", "iPad14,5": "iPad Pro 12.9\" (6th)",
        "iPad16,3": "iPad Pro 11\" (M4)", "iPad16,5": "iPad Pro 13\" (M4)", "iPad14,8": "iPad Air 11\" (M2)", "iPad14,10": "iPad Air 13\" (M2)"
    ]
    /// Identifier -> SoC lookup (estimated: Apple does not expose the chip name).
    static let chips: [String: String] = [
        "iPhone13,1": "A14 Bionic", "iPhone13,2": "A14 Bionic", "iPhone13,3": "A14 Bionic", "iPhone13,4": "A14 Bionic",
        "iPhone14,4": "A15 Bionic", "iPhone14,5": "A15 Bionic", "iPhone14,2": "A15 Bionic", "iPhone14,3": "A15 Bionic",
        "iPhone14,6": "A15 Bionic", "iPhone14,7": "A15 Bionic", "iPhone14,8": "A15 Bionic",
        "iPhone15,2": "A16 Bionic", "iPhone15,3": "A16 Bionic", "iPhone15,4": "A16 Bionic", "iPhone15,5": "A16 Bionic",
        "iPhone16,1": "A17 Pro", "iPhone16,2": "A17 Pro",
        "iPhone17,1": "A18 Pro", "iPhone17,2": "A18 Pro", "iPhone17,3": "A18", "iPhone17,4": "A18", "iPhone17,5": "A18",
        "iPhone18,1": "A19 Pro", "iPhone18,2": "A19 Pro", "iPhone18,3": "A19", "iPhone18,4": "A19 Pro",
        "iPad14,3": "M2", "iPad14,5": "M2", "iPad16,3": "M4", "iPad16,5": "M4", "iPad14,8": "M2", "iPad14,10": "M2"
    ]
    static func dnsServers() -> String? {
        var state = __res_9_state()
        guard res_9_ninit(&state) == 0 else { return nil }
        defer { res_9_ndestroy(&state) }
        var servers = [res_9_sockaddr_union](repeating: res_9_sockaddr_union(), count: 5)
        let n = Int(res_9_getservers(&state, &servers, 5))
        var out: [String] = []
        for i in 0..<max(0, min(n, 5)) {
            var u = servers[i]
            let fam = u.sin.sin_family
            guard fam == sa_family_t(AF_INET) || fam == sa_family_t(AF_INET6) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let len = socklen_t(fam == sa_family_t(AF_INET) ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size)
            let rc = withUnsafePointer(to: &u) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getnameinfo($0, len, &host, socklen_t(NI_MAXHOST), nil, 0, NI_NUMERICHOST) }
            }
            if rc == 0 { out.append(String(cString: host)) }
        }
        return out.isEmpty ? nil : out.joined(separator: ", ")
    }
    static func fmt(_ v: Int64, binary: Bool = false) -> String {
        let f = ByteCountFormatter(); f.countStyle = binary ? .binary : .file
        return f.string(fromByteCount: v)
    }
    static func now() -> Double { CFAbsoluteTimeGetCurrent() }

    static func vm() -> (free: UInt64, active: UInt64, inactive: UInt64, wired: UInt64, compressed: UInt64)? {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var s = vm_statistics64_data_t()
        let r = withUnsafeMutablePointer(to: &s) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return nil }
        let p = UInt64(getpagesize())
        return (UInt64(s.free_count) * p, UInt64(s.active_count) * p, UInt64(s.inactive_count) * p,
                UInt64(s.wire_count) * p, UInt64(s.compressor_page_count) * p)
    }
    static func appFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return r == KERN_SUCCESS ? info.phys_footprint : 0
    }
    static func storage() -> (total: Int64, free: Int64, important: Int64)? {
        let u = URL(fileURLWithPath: NSHomeDirectory())
        guard let v = try? u.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) else { return nil }
        return (Int64(v.volumeTotalCapacity ?? 0), Int64(v.volumeAvailableCapacity ?? 0), v.volumeAvailableCapacityForImportantUsage ?? 0)
    }
    static func localIPs() -> [(String, String)] {
        var res: [(String, String)] = []
        var ifa: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifa) == 0, let first = ifa else { return [] }
        defer { freeifaddrs(ifa) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let i = p.pointee
            guard let sa = i.ifa_addr else { continue }
            let fam = sa.pointee.sa_family
            guard fam == UInt8(AF_INET) || fam == UInt8(AF_INET6) else { continue }
            guard (i.ifa_flags & UInt32(IFF_UP)) != 0, (i.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)
            if ip.hasPrefix("fe80") { continue }
            res.append((String(cString: i.ifa_name), ip))
        }
        return res
    }
}

// MARK: - Benchmarks (pure functions, run off the main thread)
var benchSink: UInt64 = 0

enum Bench {
    static func work(_ iters: Int) -> UInt64 {
        var x: UInt64 = 88172645463325252
        var f = 1.0
        for _ in 0..<iters {
            x ^= x << 13; x ^= x >> 7; x ^= x << 17
            f = (f * 1.0000001 + Double(x & 0xFF) * 1e-9).squareRoot() + 1.0
        }
        return x ^ f.bitPattern
    }
    /// returns Million iterations / second
    static func cpu() -> (single: Double, multi: Double, cores: Int) {
        let n = 30_000_000
        var t = Sys.now(); let a = work(n); let single = Double(n) / (Sys.now() - t) / 1e6
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let sinks = UnsafeMutablePointer<UInt64>.allocate(capacity: cores)
        t = Sys.now()
        DispatchQueue.concurrentPerform(iterations: cores) { i in sinks[i] = work(n) }
        let multi = Double(n * cores) / (Sys.now() - t) / 1e6
        benchSink = a ^ sinks[0]; sinks.deallocate()
        return (single, multi, cores)
    }
    static func gpu() -> (name: String, gflops: Double, ms: Double)? {
        guard let dev = MTLCreateSystemDefaultDevice(), let q = dev.makeCommandQueue() else { return nil }
        let src = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void work(device float *d [[buffer(0)]], uint i [[thread_position_in_grid]]) {
            float a = d[i];
            for (int k = 0; k < 1024; k++) { a = fma(a, 1.0001f, 0.5f); a = fma(a, 0.9999f, 0.25f); }
            d[i] = a;
        }
        """
        guard let lib = try? dev.makeLibrary(source: src, options: nil), let fn = lib.makeFunction(name: "work"),
              let pso = try? dev.makeComputePipelineState(function: fn) else { return nil }
        let n = 1 << 20, passes = 8
        guard let buf = dev.makeBuffer(length: n * 4, options: .storageModeShared), let cb = q.makeCommandBuffer() else { return nil }
        for _ in 0..<passes {
            guard let enc = cb.makeComputeCommandEncoder() else { return nil }
            enc.setComputePipelineState(pso); enc.setBuffer(buf, offset: 0, index: 0)
            enc.dispatchThreads(MTLSize(width: n, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: min(pso.maxTotalThreadsPerThreadgroup, 256), height: 1, depth: 1))
            enc.endEncoding()
        }
        cb.commit(); cb.waitUntilCompleted()
        guard cb.status == .completed else { return nil }
        var secs = cb.gpuEndTime - cb.gpuStartTime
        if secs <= 0 { secs = 0.001 }
        let flops = Double(n) * 1024 * 4 * Double(passes)
        return (dev.name, flops / secs / 1e9, secs * 1000)
    }
    static func memBandwidth() -> Double {
        let size = 96 << 20
        let a = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16384)
        let b = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16384)
        defer { a.deallocate(); b.deallocate() }
        memset(a, 1, size); memset(b, 0, size)
        let reps = 8, t = Sys.now()
        for _ in 0..<reps { memcpy(b, a, size) }
        return Double(size * reps * 2) / (Sys.now() - t) / 1e9
    }
    /// Allocates & touches memory up to a safe cap; returns bytes actually allocated and the cap.
    static func memoryPressure() -> (allocated: Int, cap: Int, peak: UInt64) {
        let avail = Int(os_proc_available_memory())
        var cap = avail > 0 ? avail / 2 : Int(ProcessInfo.processInfo.physicalMemory / 8)
        cap = min(cap, 1_500_000_000)
        let chunk = 32 << 20
        var blocks: [UnsafeMutableRawPointer] = []
        var total = 0, peak: UInt64 = 0
        while total + chunk <= cap {
            let p = UnsafeMutableRawPointer.allocate(byteCount: chunk, alignment: 16384)
            memset(p, 0x5A, chunk); blocks.append(p); total += chunk
            peak = max(peak, Sys.appFootprint())
        }
        blocks.forEach { $0.deallocate() }
        return (total, cap, peak)
    }
    static func storage(mb: Int = 128) -> (write: Double, read: Double)? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("di_bench.bin")
        let fd = open(url.path, O_CREAT | O_RDWR | O_TRUNC, 0o600)
        guard fd >= 0 else { return nil }
        defer { close(fd); unlink(url.path) }
        _ = fcntl(fd, F_NOCACHE, 1)
        let chunk = 4 << 20
        var buf = [UInt8](repeating: 0, count: chunk)
        for i in 0..<chunk { buf[i] = UInt8(truncatingIfNeeded: i &* 31 &+ 7) }
        var t = Sys.now()
        for _ in 0..<(mb * 1024 * 1024 / chunk) { if write(fd, buf, chunk) != chunk { return nil } }
        _ = fcntl(fd, F_FULLFSYNC)
        let w = Double(mb) / (Sys.now() - t)
        lseek(fd, 0, SEEK_SET)
        t = Sys.now()
        var total = 0
        while true { let r = read(fd, &buf, chunk); if r <= 0 { break }; total += r }
        let rd = Double(total) / 1_048_576 / (Sys.now() - t)
        return (w, rd)
    }
}
