import Foundation

enum StorageDiagnostics {
    struct Result {
        let writeMBps: Double
        let readMBps: Double
        let bytes: Int
    }

    /// Writes an 8 MiB temporary test file in the app container and deletes it.
    /// It never touches user documents or other apps' storage.
    static func run() throws -> Result {
        let size = 8 * 1024 * 1024
        let data = Data(repeating: 0xA5, count: size)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeviceInspector-Storage-Test-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: url) }

        let writeStart = Date()
        try data.write(to: url, options: .atomic)
        let writeSeconds = max(Date().timeIntervalSince(writeStart), 0.001)

        let readStart = Date()
        let readData = try Data(contentsOf: url, options: .mappedIfSafe)
        let readSeconds = max(Date().timeIntervalSince(readStart), 0.001)
        guard readData.count == size else { throw CocoaError(.fileReadCorruptFile) }

        return Result(
            writeMBps: Double(size) / 1_048_576 / writeSeconds,
            readMBps: Double(size) / 1_048_576 / readSeconds,
            bytes: size
        )
    }
}
