import Metal
import Testing
@testable import ViVuRender

@Suite struct RendererTests {
    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
    func createsDeviceAndQueue() throws {
        let renderer = try Renderer()
        #expect(renderer.maxTextureSide >= 8192)
    }

    @Test func missingDeviceThrows() {
        #expect(throws: RendererError.noMetalDevice) {
            try Renderer(device: nil)
        }
    }
}
