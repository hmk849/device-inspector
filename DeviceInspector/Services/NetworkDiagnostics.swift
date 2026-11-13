import Foundation
import Network

enum NetworkDiagnostics {
    struct Result {
        let downloadMbps: Double
        let uploadMbps: Double
        let downloadBytes: Int
        let uploadBytes: Int
    }

    /// Uses Cloudflare's public speed-test endpoints. This transfers a small,
    /// fixed amount of data only after the user explicitly starts the test.
    static func run() async throws -> Result {
        let session = URLSession(configuration: .ephemeral)
        let downloadURL = URL(string: "https://speed.cloudflare.com/__down?bytes=1000000")!
        var downRequest = URLRequest(url: downloadURL)
        downRequest.timeoutInterval = 20
        downRequest.cachePolicy = .reloadIgnoringLocalCacheData

        let downStart = Date()
        let (downloadData, downResponse) = try await session.data(for: downRequest)
        guard (downResponse as? HTTPURLResponse)?.statusCode == 200, !downloadData.isEmpty else {
            throw URLError(.badServerResponse)
        }
        let downSeconds = max(Date().timeIntervalSince(downStart), 0.001)

        let uploadURL = URL(string: "https://speed.cloudflare.com/__up")!
        var upRequest = URLRequest(url: uploadURL)
        upRequest.httpMethod = "POST"
        upRequest.httpBody = Data(repeating: 0x44, count: 250_000)
        upRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        upRequest.timeoutInterval = 20
        let upStart = Date()
        let (_, upResponse) = try await session.data(for: upRequest)
        guard let code = (upResponse as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else {
            throw URLError(.badServerResponse)
        }
        let upSeconds = max(Date().timeIntervalSince(upStart), 0.001)
        return Result(
            downloadMbps: Double(downloadData.count) * 8 / downSeconds / 1_000_000,
            uploadMbps: 250_000 * 8 / upSeconds / 1_000_000,
            downloadBytes: downloadData.count,
            uploadBytes: 250_000
        )
    }
}
