import XCTest
import AppKit
@testable import LooseLeaf

/// URLProtocol 桩：统计每个稳定 URL 的请求次数，可注入延迟与响应字节。
final class ImageStubURLProtocol: URLProtocol {
    static let lock = NSLock()
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var delay: TimeInterval = 0
    nonisolated(unsafe) static var requestCounts: [String: Int] = [:]

    static func configure(payload: Data, delay: TimeInterval = 0) {
        lock.lock()
        responseData = payload
        Self.delay = delay
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        responseData = Data()
        delay = 0
        requestCounts = [:]
        lock.unlock()
    }

    static func resetCountsOnly() {
        lock.lock()
        requestCounts = [:]
        lock.unlock()
    }

    static func count(for url: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCounts[ImageRequestCoalescer.stableKey(for: url)] ?? 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let key = ImageRequestCoalescer.stableKey(for: url)
        Self.lock.lock()
        Self.requestCounts[key, default: 0] += 1
        let data = Self.responseData
        let delay = Self.delay
        Self.lock.unlock()

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "image/jpeg"]
            )!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

/// MAC-1 / MAC-2 / MAC-11：图片在途请求合并、后台解码、队列拆分与 per-key 单飞。
final class ImagePipelineTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        ImageStubURLProtocol.reset()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("looseleaf-image-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        PaperImageCache.overrideDirectory = tempDir
    }

    override func tearDown() {
        PaperImageCache.overrideDirectory = nil
        try? FileManager.default.removeItem(at: tempDir)
        ImageStubURLProtocol.reset()
        super.tearDown()
    }

    private func makeJPEGData(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!
    }

    private func makeStubSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ImageStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// 同一稳定 URL（签名参数不同）并发 8 次，只应发出 1 个网络请求。
    func test01_CoalescerMergesConcurrentRequestsForSameStableURL() async {
        let payload = makeJPEGData(width: 64, height: 64)
        ImageStubURLProtocol.configure(payload: payload, delay: 0.15)

        let base = "https://example.com/media/photo.jpg"
        let session = makeStubSession()
        let coalescer = ImageRequestCoalescer()

        let results = await withTaskGroup(of: Int?.self) { group -> [Int?] in
            for i in 0..<8 {
                group.addTask {
                    let url = URL(string: "\(base)?X-Amz-Signature=sig-\(i)")!
                    guard let data = try? await coalescer.data(for: url, session: session) else {
                        return nil
                    }
                    return data.count
                }
            }
            var values: [Int?] = []
            for await value in group { values.append(value) }
            return values
        }

        XCTAssertEqual(results.count, 8)
        XCTAssertTrue(results.allSatisfy { $0 == payload.count }, "所有并发消费者应拿到同一份字节")
        XCTAssertEqual(ImageStubURLProtocol.count(for: URL(string: base)!), 1, "同一稳定 URL 只允许一次下载")
    }

    /// 不同路径必须各自请求，不能被错误合并。
    func test02_CoalescerKeepsDifferentURLsSeparate() async {
        ImageStubURLProtocol.configure(payload: makeJPEGData(width: 32, height: 32))
        let session = makeStubSession()
        let coalescer = ImageRequestCoalescer()

        async let a = try? coalescer.data(for: URL(string: "https://example.com/a.jpg?t=1")!, session: session)
        async let b = try? coalescer.data(for: URL(string: "https://example.com/b.jpg?t=1")!, session: session)
        _ = await (a, b)

        XCTAssertEqual(ImageStubURLProtocol.count(for: URL(string: "https://example.com/a.jpg")!), 1)
        XCTAssertEqual(ImageStubURLProtocol.count(for: URL(string: "https://example.com/b.jpg")!), 1)
    }

    /// 下载后的解码在专用队列完成，且能按 maxPixel 从同一份 Data 派生不同缩略图。
    func test03_StoreDownloadedDerivesThumbnailAtRequestedPixelSize() async {
        let data = makeJPEGData(width: 1200, height: 800)
        let url = URL(string: "https://example.com/media/large.jpg")!

        let small = await PaperImageCache.storeDownloaded(rawData: data, for: url, maxPixel: 200)
        let large = await PaperImageCache.storeDownloaded(rawData: data, for: url, maxPixel: 900)

        XCTAssertNotNil(small)
        XCTAssertNotNil(large)
        XCTAssertLessThanOrEqual(small?.size.width ?? .greatestFiniteMagnitude, 200)
        XCTAssertGreaterThan(large?.size.width ?? 0, 800)
        XCTAssertNotNil(PaperImageCache.memoryImage(for: url, maxPixel: 200))
        XCTAssertNotNil(PaperImageCache.memoryImage(for: url, maxPixel: 900))
    }

    /// 同一 key 并发加载只允许一次真实解码（MAC-11 队列拆分后的 per-key 单飞）。
    func test04_ConcurrentLoadsDecodeSameKeyOnlyOnce() async throws {
        let data = makeJPEGData(width: 400, height: 300)
        let url = URL(string: "https://example.com/media/singleflight.jpg")!
        let fileURL = PaperImageCache.diskCacheFileURL(for: url)
        try data.write(to: fileURL, options: .atomic)

        let counter = LockedCounter()
        PaperImageCache.decodeObserverForTesting = { _, _ in counter.increment() }
        defer { PaperImageCache.decodeObserverForTesting = nil }

        let images = await withTaskGroup(of: Bool.self) { group -> [Bool] in
            for _ in 0..<8 {
                group.addTask {
                    await PaperImageCache.loadImage(for: url, maxPixel: 256) != nil
                }
            }
            var values: [Bool] = []
            for await value in group { values.append(value) }
            return values
        }

        XCTAssertTrue(images.allSatisfy { $0 }, "同一张磁盘图应能正常解码")
        XCTAssertEqual(counter.value, 1, "同一 (URL, maxPixel) 并发加载只应解码一次")
    }

    /// 缩略图接口的 key / w 是资源身份：不同 object key 或不同宽度不得合并。
    func test06_CoalescerKeepsThumbnailIdentityParams() async throws {
        ImageStubURLProtocol.configure(payload: makeJPEGData(width: 40, height: 40))
        let session = makeStubSession()
        let coalescer = ImageRequestCoalescer()

        let a = URL(string: "https://hub.example.com/api/v1/files/thumbnail?key=media/a.jpg&w=480&exp=1&sig=s1")!
        let b = URL(string: "https://hub.example.com/api/v1/files/thumbnail?key=media/b.jpg&w=480&exp=1&sig=s1")!
        let a2x = URL(string: "https://hub.example.com/api/v1/files/thumbnail?key=media/a.jpg&w=960&exp=1&sig=s1")!

        _ = try? await coalescer.data(for: a, session: session)
        ImageStubURLProtocol.resetCountsOnly()
        _ = try? await coalescer.data(for: b, session: session)
        XCTAssertEqual(ImageStubURLProtocol.count(for: b), 1, "不同 key 必须各自请求")
        ImageStubURLProtocol.resetCountsOnly()
        _ = try? await coalescer.data(for: a2x, session: session)
        XCTAssertEqual(ImageStubURLProtocol.count(for: a2x), 1, "同一 key 不同宽度必须各自请求")

        XCTAssertNotEqual(
            ImageRequestCoalescer.stableKey(for: a),
            ImageRequestCoalescer.stableKey(for: b)
        )
        XCTAssertNotEqual(
            ImageRequestCoalescer.stableKey(for: a),
            ImageRequestCoalescer.stableKey(for: a2x)
        )
    }

    /// 磁盘缓存只保留一份原始字节：并发 storeDownloaded 不会改写/膨胀成多份文件。
    func test05_StoreDownloadedWritesSingleOriginalFile() async throws {
        let data = makeJPEGData(width: 320, height: 200)
        let url = URL(string: "https://example.com/media/writeonce.jpg")!

        async let a = PaperImageCache.storeDownloaded(rawData: data, for: url, maxPixel: 160)
        async let b = PaperImageCache.storeDownloaded(rawData: data, for: url, maxPixel: 320)
        _ = await (a, b)

        let fileURL = PaperImageCache.diskCacheFileURL(for: url)
        let deadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: fileURL.path), Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let onDisk = try Data(contentsOf: fileURL)
        XCTAssertEqual(onDisk, data, "磁盘上应只有一份原始字节且内容一致")
    }
}

/// 线程安全计数器
final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
