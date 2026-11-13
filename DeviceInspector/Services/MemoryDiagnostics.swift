import Foundation

/// Best-effort memory diagnostics using Mach VM counters.
/// Device-wide figures are aggregate kernel page counters; they do not reveal
/// memory owned by other individual apps. App footprint is this process only.
enum MemoryDiagnostics {
    struct Snapshot {
        let totalBytes: UInt64
        let wiredBytes: UInt64
        let activeBytes: UInt64
        let inactiveBytes: UInt64
        let compressedBytes: UInt64
        let freeBytes: UInt64
        let appFootprintBytes: UInt64?

        var usedEstimateBytes: UInt64 {
            wiredBytes &+ activeBytes &+ compressedBytes
        }
    }

    static func read() -> Snapshot? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, raw, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let page = UInt64(pageSize)

        return Snapshot(
            totalBytes: ProcessInfo.processInfo.physicalMemory,
            wiredBytes: UInt64(stats.wire_count) &* page,
            activeBytes: UInt64(stats.active_count) &* page,
            inactiveBytes: UInt64(stats.inactive_count) &* page,
            compressedBytes: UInt64(stats.compressor_page_count) &* page,
            freeBytes: UInt64(stats.free_count) &* page,
            appFootprintBytes: appFootprint()
        )
    }

    private static func appFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), raw, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.phys_footprint)
    }
}
