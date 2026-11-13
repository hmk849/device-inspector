import Foundation
import Metal

enum MetalDiagnostics {
    static func run() throws -> (milliseconds: Double, device: String) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "DeviceInspector.Metal", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Metal 不可用"])
        }
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void vectorAdd(device const float *a [[buffer(0)]],
                              device const float *b [[buffer(1)]],
                              device float *out [[buffer(2)]],
                              uint id [[thread_position_in_grid]]) {
            out[id] = a[id] + b[id];
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        guard let function = library.makeFunction(name: "vectorAdd") else {
            throw NSError(domain: "DeviceInspector.Metal", code: 2)
        }
        let pipeline = try device.makeComputePipelineState(function: function)
        let count = 262_144
        let length = count * MemoryLayout<Float>.stride
        let a = device.makeBuffer(length: length, options: .storageModeShared)!
        let b = device.makeBuffer(length: length, options: .storageModeShared)!
        let out = device.makeBuffer(length: length, options: .storageModeShared)!
        let ap = a.contents().bindMemory(to: Float.self, capacity: count)
        let bp = b.contents().bindMemory(to: Float.self, capacity: count)
        for i in 0..<count { ap[i] = Float(i) * 0.25; bp[i] = Float(i) * 0.5 }

        guard let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder() else {
            throw NSError(domain: "DeviceInspector.Metal", code: 3)
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(a, offset: 0, index: 0)
        encoder.setBuffer(b, offset: 0, index: 1)
        encoder.setBuffer(out, offset: 0, index: 2)
        let width = pipeline.threadExecutionWidth
        encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1))
        encoder.endEncoding()
        let start = Date()
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else {
            throw command.error ?? NSError(domain: "DeviceInspector.Metal", code: 4)
        }
        let elapsed = Date().timeIntervalSince(start) * 1000
        return (elapsed, device.name)
    }
}
