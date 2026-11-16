import CoreGraphics
import Metal
import ViVuCore

public enum RendererError: Error, Equatable {
    case noMetalDevice
    case commandQueueUnavailable
    case pipeline(String)
    case texture
}

/// Owns the Metal device, command queue and the single quad pipeline shared by every drawing surface
/// (main window, filmstrip panel, transition overlay). See docs/TECH_SPEC.md §3.
public final class Renderer: @unchecked Sendable {
    // Sendable: every stored property is immutable after init, and Metal device, queue,
    // pipeline and sampler objects are thread-safe.
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    let smoothSampler: MTLSamplerState
    let sharpSampler: MTLSamplerState
    public static let pixelFormat = MTLPixelFormat.bgra8Unorm

    public init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let device else { throw RendererError.noMetalDevice }
        guard let queue = device.makeCommandQueue() else { throw RendererError.commandQueueUnavailable }
        self.device = device
        self.commandQueue = queue
        do {
            let library = try device.makeLibrary(source: Shaders.source, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "quad_vertex")
            descriptor.fragmentFunction = library.makeFunction(name: "quad_fragment")
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = Self.pixelFormat
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .one              // premultiplied alpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw RendererError.pipeline("\(error)")
        }
        let smooth = MTLSamplerDescriptor()
        smooth.minFilter = .linear
        smooth.magFilter = .linear
        smooth.mipFilter = .linear
        smooth.sAddressMode = .clampToEdge
        smooth.tAddressMode = .clampToEdge
        smoothSampler = device.makeSamplerState(descriptor: smooth)!
        let sharp = MTLSamplerDescriptor()
        sharp.minFilter = .linear
        sharp.magFilter = .nearest
        sharp.mipFilter = .linear
        sharp.sAddressMode = .clampToEdge
        sharp.tAddressMode = .clampToEdge
        sharpSampler = device.makeSamplerState(descriptor: sharp)!
    }

    /// Largest 2D texture side the GPU accepts. Read at runtime: Intel Macs differ (docs/TECH_SPEC.md §1).
    public var maxTextureSide: Int {
        device.supportsFamily(.apple3) || device.supportsFamily(.mac2) ? 16384 : 8192
    }

    /// Encodes `quads` into a render pass that clears to `clear` (premultiplied).
    public func encode(_ quads: [Quad], into buffer: MTLCommandBuffer, target: MTLTexture,
                       clear: SIMD4<Double> = SIMD4(0, 0, 0, 1)) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: clear.x, green: clear.y, blue: clear.z, alpha: clear.w)
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentSamplerState(smoothSampler, index: 0)
        encoder.setFragmentSamplerState(sharpSampler, index: 1)
        for quad in quads {
            var uniforms = QuadUniforms(quad)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<QuadUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<QuadUniforms>.stride, index: 0)
            encoder.setFragmentTexture(quad.texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        encoder.endEncoding()
    }

    /// Draws offscreen and reads the pixels back (tests, snapshots).
    public func renderOffscreen(_ quads: [Quad], size: PixelSize, clear: SIMD4<Double> = SIMD4(0, 0, 0, 1)) throws -> PixelBuffer {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.pixelFormat, width: size.width,
                                                                  height: size.height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .managedOrShared(device)
        guard let target = device.makeTexture(descriptor: descriptor),
              let buffer = commandQueue.makeCommandBuffer() else { throw RendererError.texture }
        encode(quads, into: buffer, target: target, clear: clear)
        if target.storageMode == .managed, let blit = buffer.makeBlitCommandEncoder() {
            blit.synchronize(resource: target)
            blit.endEncoding()
        }
        buffer.commit()
        buffer.waitUntilCompleted()
        let out = PixelBuffer(width: size.width, height: size.height)
        target.getBytes(out.data, bytesPerRow: out.bytesPerRow,
                        from: MTLRegionMake2D(0, 0, size.width, size.height), mipmapLevel: 0)
        return out
    }
}

extension MTLStorageMode {
    /// Shared on unified memory (Apple Silicon), managed on discrete GPUs (Intel Macs).
    static func managedOrShared(_ device: MTLDevice) -> MTLStorageMode {
        device.hasUnifiedMemory ? .shared : .managed
    }
}
