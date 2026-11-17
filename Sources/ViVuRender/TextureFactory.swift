import Metal
import ViVuCore

public extension Renderer {
    /// Uploads a PixelBuffer as a texture. Safe off the main thread.
    /// With `mipmapped`, the GPU builds the smaller levels so shrinking the image stays smooth.
    func makeTexture(_ buffer: PixelBuffer, mipmapped: Bool = true) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.pixelFormat, width: buffer.width,
                                                                  height: buffer.height, mipmapped: mipmapped)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managedOrShared(device)
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw RendererError.texture }
        texture.replace(region: MTLRegionMake2D(0, 0, buffer.width, buffer.height), mipmapLevel: 0,
                        withBytes: buffer.data, bytesPerRow: buffer.bytesPerRow)
        if mipmapped, texture.mipmapLevelCount > 1,
           let commands = commandQueue.makeCommandBuffer(), let blit = commands.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()
        }
        return texture
    }
}

public extension MTLTexture {
    /// Bytes the texture occupies, counting mip levels (×4/3).
    var estimatedBytes: Int {
        let base = width * height * 4
        return mipmapLevelCount > 1 ? base * 4 / 3 : base
    }
}
