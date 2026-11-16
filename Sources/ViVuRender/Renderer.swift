import Metal

public enum RendererError: Error, Equatable {
    case noMetalDevice
    case commandQueueUnavailable
}

/// Owns the Metal device and command queue shared by every drawing surface
/// (main window, filmstrip panel, transition overlay). See docs/TECH_SPEC.md §3.
public final class Renderer: @unchecked Sendable {
    // Sendable: both properties are immutable and Metal device/queue objects are thread-safe.
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue

    public init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let device else { throw RendererError.noMetalDevice }
        guard let queue = device.makeCommandQueue() else { throw RendererError.commandQueueUnavailable }
        self.device = device
        self.commandQueue = queue
    }

    /// Largest 2D texture side the GPU accepts. Read at runtime: Intel Macs differ (docs/TECH_SPEC.md §1).
    public var maxTextureSide: Int {
        device.supportsFamily(.apple3) || device.supportsFamily(.mac2) ? 16384 : 8192
    }
}
