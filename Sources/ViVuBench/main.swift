import Foundation
import UniformTypeIdentifiers
import ViVuCore

// vivu-bench: windowless timing of the decode paths (docs/TECH_SPEC.md §11.2).

let usage = """
usage: vivu-bench <command> [args]

commands:
  version                         print the bench version
  decode <file>...                time meta / embedded preview / screen decode / full decode (ImageIO)
  thumbs <dir>                    make the gallery/filmstrip thumbnail of every image in a folder; list failures
  huge <file> [--fit N] [--imageio]  own reader for a huge TIFF/PSB: fit + zoom source, region and tile reads
  test-fixtures [dir]             write the small committed fixtures (default Tests/Fixtures)
  doc-types                       print CFBundleDocumentTypes (used by Scripts/bundle.sh)
  make-fixtures <dir> [--huge]    write test pictures (folder of JPEGs, 200 MP JPEG; --huge adds multi-GB PSB/TIFF)
"""

let args = Array(CommandLine.arguments.dropFirst())

/// Same path as the app's thumbnails (ThumbnailStore.make). SVG needs the app's renderer and is skipped here.
func thumbsCommand(_ args: [String]) throws {
    guard let path = args.first else { fail(usage) }
    let dir = URL(fileURLWithPath: path)
    let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        .filter { FormatCatalog.isImage($0) && !VectorImage.isVector($0) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    var failed = 0
    for url in files {
        let start = Date()
        do {
            let (thumb, _) = try ThumbnailStore.make(url)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            if ms > 500 { print("slow \(ms) ms  \(url.lastPathComponent) \(thumb.size.width)x\(thumb.size.height)") }
        } catch {
            failed += 1
            print("FAIL \(url.lastPathComponent): \(error)")
        }
    }
    print("\(files.count) images, \(failed) failed")
}
let screenLongSide = 3024   // a 14" MacBook Pro display at 2x

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

func ms(_ seconds: Double) -> String { String(format: "%7.1f ms", seconds * 1000) }

@discardableResult
func timed<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
    let start = DispatchTime.now().uptimeNanoseconds
    let value = try body()
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
    print("  \(label.padding(toLength: 34, withPad: " ", startingAt: 0)) \(ms(elapsed))")
    return value
}

/// Samples the footprint every 5 ms to catch the peak of a call.
final class PeakSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peak = 0
    private var running = true
    func start() {
        Thread.detachNewThread { [self] in
            while lock.withLock({ running }) {
                let now = MemoryFootprint.current()
                lock.withLock { peak = max(peak, now) }
                usleep(5_000)
            }
        }
    }
    func stop() -> Int { lock.withLock { running = false; return peak } }
}

func measurePeak<T>(_ body: () throws -> T) rethrows -> (T, Int) {
    let sampler = PeakSampler()
    sampler.start()
    let value = try body()
    return (value, sampler.stop())
}

/// Drops the file from the page cache so the next read is cold (best effort, no sudo needed).
func evict(_ url: URL) {
    let fd = open(url.path, O_RDONLY)
    guard fd >= 0 else { return }
    _ = fcntl(fd, F_NOCACHE, 1)
    // Reading with F_NOCACHE does not evict; this is a hint only. Real cold numbers need `sudo purge`.
    close(fd)
}

func decodeCommand(_ paths: [String]) throws {
    for path in paths {
        let url = URL(fileURLWithPath: path)
        print("\(url.lastPathComponent)")
        let meta = try timed("meta") { try ImageIODecoder.meta(url) }
        print("  size \(meta.storedSize) (\(String(format: "%.1f", meta.storedSize.megapixels)) MP), \(meta.uti), orientation \(meta.orientation)")
        let thumb = try timed("thumbnail 640 (stage 0 source)") { try ImageIODecoder.thumbnail(url, maxPixel: 640) }
        print("  thumbnail: \(thumb.size)")
        let (screen, _) = try timed("stage 1: screen decode (\(screenLongSide))") {
            try ImageIODecoder.screenDecode(url, screenLongSide: screenLongSide)
        }
        print("  screen decode: \(screen.size)")
        let (full, peak) = try measurePeak {
            try timed("stage 2: full decode") { try ImageIODecoder.fullDecode(url) }
        }
        print("  full decode: \(full.size), peak footprint \(MemoryFootprint.megabytes(peak))")
    }
}

func hugeCommand(_ args: [String]) throws {
    guard let path = args.first else { fail(usage) }
    let fit = args.firstIndex(of: "--fit").flatMap { Int(args[$0 + 1]) } ?? screenLongSide
    let withImageIO = args.contains("--imageio")
    let url = URL(fileURLWithPath: path)
    print(url.lastPathComponent)
    guard let base = timed("own reader: open", { SourceFactory.openOwnReader(url) }) else {
        fail("  no own reader for this file (not a TIFF/PSB over 64 MP, or declined)")
    }
    let kind = base is TIFFRegionSource ? "TIFF, \((base as! TIFFRegionSource).levels.count) level(s)" : "PSD/PSB"
    print("  \(base.fullSize) (\(String(format: "%.0f", base.fullSize.megapixels)) MP), \(kind)")
    var source: RegionSource = base
    for pass in ["first", "again"] {
        let ((pixels, prepared), peak) = try measurePeak {
            try timed("fit \(fit) + zoom source (\(pass))") { try SourceFactory.prepareHuge(base, fitLongSide: fit) }
        }
        source = prepared
        print("    → \(pixels.size), \(prepared is HybridSource ? "RAM level built" : "from overviews"), peak footprint \(MemoryFootprint.megabytes(peak))")
    }
    let full = source.fullSize
    let center = PixelRect(x: full.width / 2 - 1512, y: full.height / 2 - 1000, width: 3024, height: 2000)
    try timed("100% region 3024×2000") { _ = try source.read(rect: center, level: 0) }
    let tile = PixelRect(x: full.width / 3, y: full.height / 3, width: 514, height: 514)
    try timed("one 512 tile at 100%") { _ = try source.read(rect: tile, level: 0) }
    try timed("one 512 tile at level 2") {
        _ = try source.read(rect: PixelRect(x: tile.x, y: tile.y, width: 2056, height: 2056), level: 2)
    }
    if withImageIO {
        let (buffer, peak) = try measurePeak { try timed("ImageIO screen decode \(fit)") { try ImageIODecoder.screenDecode(url, screenLongSide: fit).0 } }
        print("    → \(buffer.size), peak footprint \(MemoryFootprint.megabytes(peak))")
    }
}

func makeFixtures(_ args: [String]) throws {
    guard let dirPath = args.first else { fail(usage) }
    let dir = URL(fileURLWithPath: dirPath)
    let fm = FileManager.default
    let folder = dir.appendingPathComponent("folder-jpeg")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    let count = Int(ProcessInfo.processInfo.environment["FIXTURE_COUNT"] ?? "") ?? 500
    try timed("\(count) JPEG 4000×3000 in folder-jpeg") {
        let base = ImageWriter.pattern(size: PixelSize(width: 4000, height: 3000), seed: 1)
        for i in 0..<count {
            let name = String(format: "IMG_%05d.jpg", i)
            let target = folder.appendingPathComponent(name)
            if fm.fileExists(atPath: target.path) { continue }
            try ImageWriter.write(i % 10 == 0 ? ImageWriter.pattern(size: PixelSize(width: 4000, height: 3000), seed: i) : base,
                                  to: target, type: .jpeg, orientation: UInt8(i % 8 + 1))
        }
    }
    let big = dir.appendingPathComponent("jpeg-200mp.jpg")
    if !fm.fileExists(atPath: big.path) {
        try timed("JPEG 200 MP") {
            try ImageWriter.write(ImageWriter.pattern(size: PixelSize(width: 17320, height: 11547), seed: 7), to: big, type: .jpeg)
        }
    }
    let small = dir.appendingPathComponent("psd-rle-small.psd")
    try timed("PSD RLE 3000×2000") {
        try PSBWriter.write(to: small, width: 3000, height: 2000, large: false, compression: .rle) { y, rgb in
            FixtureContent.fillRow(y: y, x0: 0, count: 3000, width: 3000, height: 2000, into: rgb)
        }
    }
    guard args.contains("--huge") else { return }
    let (pw, ph) = (40_000, 12_000)
    try timed("PSB RLE \(pw)×\(ph) (~1.4 GB)") {
        try PSBWriter.write(to: dir.appendingPathComponent("psb-rle-huge.psb"), width: pw, height: ph, large: true,
                            compression: .rle) { y, rgb in
            FixtureContent.fillRow(y: y, x0: 0, count: pw, width: pw, height: ph, into: rgb)
        }
    }
    let (tw, th) = (36_000, 20_000)
    try timed("BigTIFF tiled \(tw)×\(th) + 5 overviews (~2.2 GB)") {
        try TIFFWriter.write(to: dir.appendingPathComponent("bigtiff-tiled-overviews.tif"), width: tw, height: th,
                             bigTIFF: true, overviews: 5) { level, y, lw, rgb in
            FixtureContent.fillRow(y: y << level, x0: 0, count: lw, width: lw, height: th >> level, into: rgb)
        }
    }
    try timed("TIFF tiled \(tw)×\(th), no overviews (~2.2 GB)") {
        try TIFFWriter.write(to: dir.appendingPathComponent("tiff-tiled-plain.tif"), width: tw, height: th,
                             bigTIFF: false, overviews: 0) { _, y, lw, rgb in
            FixtureContent.fillRow(y: y, x0: 0, count: lw, width: tw, height: th, into: rgb)
        }
    }
}

do {
    switch args.first {
    case "version":
        print("vivu-bench 0.2.0 (\(Tuning.bundleID))")
    case "decode":
        try decodeCommand(Array(args.dropFirst()))
    case "thumbs":
        try thumbsCommand(Array(args.dropFirst()))
    case "huge":
        try hugeCommand(Array(args.dropFirst()))
    case "test-fixtures":
        try TestFixtures.write(to: URL(fileURLWithPath: args.count > 1 ? args[1] : "Tests/Fixtures"))
    case "doc-types":
        print(FormatCatalog.documentTypesPlistXML())
    case "make-fixtures":
        try makeFixtures(Array(args.dropFirst()))
    case nil, "help", "-h", "--help":
        print(usage)
    default:
        fail("unknown command: \(args[0])\n\n\(usage)")
    }
} catch {
    fail("error: \(error)")
}
