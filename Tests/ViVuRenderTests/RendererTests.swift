import CoreGraphics
import Metal
import Testing
import ViVuCore
@testable import ViVuRender

let hasMetal = MTLCreateSystemDefaultDevice() != nil

@Suite(.enabled(if: hasMetal, "needs a Metal device")) struct RendererTests {
    let renderer = try! Renderer()

    func close(_ a: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), _ rgb: (Int, Int, Int), tolerance: Int = 3) -> Bool {
        abs(Int(a.r) - rgb.0) <= tolerance && abs(Int(a.g) - rgb.1) <= tolerance && abs(Int(a.b) - rgb.2) <= tolerance
    }

    @Test func createsDeviceAndQueue() {
        #expect(renderer.maxTextureSide >= 8192)
        #expect(MemoryLayout<QuadUniforms>.stride == 160)
    }

    @Test func missingDeviceThrows() {
        #expect(throws: RendererError.noMetalDevice) { try Renderer(device: nil) }
    }

    /// A texture drawn 1:1 over the whole target comes back unchanged.
    @Test func drawsTextureOneToOne() throws {
        let pattern = TestFixtures.orientationPattern()
        let texture = try renderer.makeTexture(pattern, mipmapped: false)
        let quad = Quad.placed(texture: texture, center: CGPoint(x: 150, y: 100), size: CGSize(width: 300, height: 200),
                               viewSize: CGSize(width: 300, height: 200), nearest: true)
        let out = try renderer.renderOffscreen([quad], size: PixelSize(width: 300, height: 200))
        for (x, y) in [(10, 10), (290, 10), (150, 190), (150, 100), (99, 79), (200, 0)] {
            let p = pattern.pixel(x: x, y: y)
            #expect(close(out.pixel(x: x, y: y), (Int(p.r), Int(p.g), Int(p.b)), tolerance: 1), "at \(x),\(y)")
        }
    }

    /// One clockwise quarter turn puts the stored top-left (red) block at the top-right.
    @Test func rotatesClockwise() throws {
        let texture = try renderer.makeTexture(TestFixtures.orientationPattern(), mipmapped: false)
        let view = CGSize(width: 200, height: 300)
        let quad = Quad.placed(texture: texture, center: CGPoint(x: 100, y: 150), size: CGSize(width: 300, height: 200),
                               rotation: .pi / 2, viewSize: view, nearest: true)
        let out = try renderer.renderOffscreen([quad], size: PixelSize(width: 200, height: 300))
        #expect(close(out.pixel(x: 190, y: 10), (220, 30, 30)), "red block should be top-right")
        #expect(close(out.pixel(x: 190, y: 290), (30, 200, 30)), "green block should be bottom-right")
        #expect(close(out.pixel(x: 10, y: 150), (30, 30, 220)), "blue band should be on the left")
    }

    @Test func roundedCornersAndBorder() throws {
        let quad = Quad.placed(texture: nil, center: CGPoint(x: 50, y: 50), size: CGSize(width: 100, height: 100),
                               viewSize: CGSize(width: 100, height: 100), color: SIMD4(1, 0, 0, 1), cornerRadius: 20,
                               borderWidth: 4, borderColor: SIMD4(1, 1, 1, 1))
        let out = try renderer.renderOffscreen([quad], size: PixelSize(width: 100, height: 100))
        #expect(close(out.pixel(x: 1, y: 1), (0, 0, 0)), "corner outside the radius stays background")
        #expect(close(out.pixel(x: 50, y: 50), (255, 0, 0)), "inside is the fill")
        #expect(close(out.pixel(x: 50, y: 1), (255, 255, 255), tolerance: 30), "edge is the border")
    }

    @Test func fadesWithAlpha() throws {
        let quad = Quad.placed(texture: nil, center: CGPoint(x: 5, y: 5), size: CGSize(width: 10, height: 10),
                               viewSize: CGSize(width: 10, height: 10), color: SIMD4(0.5, 0.5, 0.5, 0.5))
        let out = try renderer.renderOffscreen([quad], size: PixelSize(width: 10, height: 10))
        #expect(close(out.pixel(x: 5, y: 5), (128, 128, 128), tolerance: 2))
    }
}
