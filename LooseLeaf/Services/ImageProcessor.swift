import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// 端侧暗房相纸图像处理器 (ImageIO EXIF 提取与 4K 85% 智能压制)
/// 遵循 docs/macos.md §3.3 与 docs/ecosystem.md §6.2 规范
public enum ImageProcessor {

    public struct ProcessedPhoto: Sendable {
        public let compressedData: Data
        public let filename: String
        public let mimeType: String
        public let originalSize: Int64
        public let compressedSize: Int64
        public let width: Int
        public let height: Int
        public let exifMetadata: EXIFSummary
    }

    public struct EXIFSummary: Equatable, Sendable {
        public var cameraMake: String
        public var cameraModel: String
        public var lensModel: String
        public var focalLength: Double?
        public var fNumber: Double?
        public var exposureTime: Double?
        public var iso: Int?
        public var capturedAt: String?

        public init(
            cameraMake: String = "",
            cameraModel: String = "",
            lensModel: String = "",
            focalLength: Double? = nil,
            fNumber: Double? = nil,
            exposureTime: Double? = nil,
            iso: Int? = nil,
            capturedAt: String? = nil
        ) {
            self.cameraMake = cameraMake
            self.cameraModel = cameraModel
            self.lensModel = lensModel
            self.focalLength = focalLength
            self.fNumber = fNumber
            self.exposureTime = exposureTime
            self.iso = iso
            self.capturedAt = capturedAt
        }

        /// 拼装暗房相纸底款说明，如 "Fujifilm X100V · 23mm F2.0 · ISO 400"
        public var formattedCameraLine: String {
            var parts: [String] = []

            let cleanMake = cameraMake.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanModel = cameraModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanModel.isEmpty {
                if !cleanMake.isEmpty && !cleanModel.lowercased().hasPrefix(cleanMake.lowercased()) {
                    parts.append("\(cleanMake) \(cleanModel)")
                } else {
                    parts.append(cleanModel)
                }
            } else if !cleanMake.isEmpty {
                parts.append(cleanMake)
            }

            var lensSpec: [String] = []
            // EXIF 来自任意相机/损坏文件，必须先做有限性与范围校验：
            // Int(fl) / Int(1/exp) 对 infinity、NaN 或超大值会直接触发 Swift 运行时陷阱。
            if let fl = focalLength, fl.isFinite, fl > 0, fl < 100_000 {
                if fl.truncatingRemainder(dividingBy: 1) == 0 {
                    lensSpec.append("\(Int(fl))mm")
                } else {
                    lensSpec.append(String(format: "%.1fmm", fl))
                }
            }
            if let fn = fNumber, fn.isFinite, fn > 0, fn < 1_000 {
                lensSpec.append(String(format: "F%.1f", fn))
            }
            if !lensSpec.isEmpty {
                parts.append(lensSpec.joined(separator: " "))
            } else if !lensModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(lensModel.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            if let exp = exposureTime, exp.isFinite, exp > 0 {
                if exp < 1.0 {
                    let reciprocal = 1.0 / exp
                    if reciprocal.isFinite, reciprocal < 1_000_000 {
                        let denom = Int(reciprocal.rounded())
                        if denom > 0 {
                            parts.append("1/\(denom)s")
                        }
                    }
                } else {
                    parts.append(String(format: "%.1fs", exp))
                }
            }

            if let isoVal = iso, isoVal > 0 {
                parts.append("ISO \(isoVal)")
            }

            return parts.joined(separator: " · ")
        }
    }

    /// 提取图片文件中的 EXIF 与 TIFF 拍摄参数
    public static func extractEXIF(from fileURL: URL) -> EXIFSummary {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return EXIFSummary()
        }
        return extractEXIF(from: source)
    }

    public static func extractEXIF(from data: Data) -> EXIFSummary {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return EXIFSummary()
        }
        return extractEXIF(from: source)
    }

    private static func extractEXIF(from source: CGImageSource) -> EXIFSummary {
        guard let metadata = copyProperties(from: source) else {
            return EXIFSummary()
        }
        return exifSummary(from: metadata)
    }

    /// 读取并缓存 ImageIO 属性字典（同一份数据只读一次，避免重复拷贝）
    private static func copyProperties(from source: CGImageSource) -> [CFString: Any]? {
        CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    }

    private static func exifSummary(from metadata: [CFString: Any]) -> EXIFSummary {
        let exif = metadata[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = metadata[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]

        let make = (tiff[kCGImagePropertyTIFFMake] as? String) ?? ""
        let model = (tiff[kCGImagePropertyTIFFModel] as? String) ?? ""
        let lens = (exif[kCGImagePropertyExifLensModel] as? String) ?? ""
        let focalLength = exif[kCGImagePropertyExifFocalLength] as? Double
        let fNumber = exif[kCGImagePropertyExifFNumber] as? Double
        let exposureTime = exif[kCGImagePropertyExifExposureTime] as? Double
        let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first
        let dateTimeOriginal = exif[kCGImagePropertyExifDateTimeOriginal] as? String

        var isoDateStr: String?
        if let rawDate = dateTimeOriginal, let parsed = FormatUtils.parseFlexDate(rawDate) {
            isoDateStr = FormatUtils.beijingISOString(from: parsed)
        }

        return EXIFSummary(
            cameraMake: make,
            cameraModel: model,
            lensModel: lens,
            focalLength: focalLength,
            fNumber: fNumber,
            exposureTime: exposureTime,
            iso: iso,
            capturedAt: isoDateStr
        )
    }

    /// 执行端侧 4K (最长边 3840px) 缩放与 85% 质量 JPEG 压制
    public static func processImageFile(at fileURL: URL, maxPixelSize: Int = 3840, quality: Double = 0.85) throws -> ProcessedPhoto {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            throw APIError.decodingFailure("无法读取图像数据源: \(fileURL.lastPathComponent)")
        }
        // attributesOfItem 返回的是 NSNumber，直接 `as? Int64` 在部分路径会失败并静默变成 0；
        // 统一走 NSNumber.int64Value，压缩率统计才可信。
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize: Int64 = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        return try processImageSource(
            source,
            originalFilename: fileURL.lastPathComponent,
            originalSize: fileSize,
            maxPixelSize: maxPixelSize,
            quality: quality
        )
    }

    public static func processImageData(
        _ rawData: Data,
        originalFilename: String,
        maxPixelSize: Int = 3840,
        quality: Double = 0.85
    ) throws -> ProcessedPhoto {
        guard let source = CGImageSourceCreateWithData(rawData as CFData, nil) else {
            throw APIError.decodingFailure("无法读取图像数据源: \(originalFilename)")
        }
        return try processImageSource(
            source,
            originalFilename: originalFilename,
            originalSize: Int64(rawData.count),
            maxPixelSize: maxPixelSize,
            quality: quality
        )
    }

    private static func processImageSource(
        _ source: CGImageSource,
        originalFilename: String,
        originalSize: Int64,
        maxPixelSize: Int = 3840,
        quality: Double = 0.85
    ) throws -> ProcessedPhoto {
        // autoreleasepool：CGImageSource / CGImage / CFMutableData 等 CF 对象由 ARC 通过
        // Unmanaged 管理，不会在函数返回前释放。批量处理时中间产物会累积到批处理结束，
        // 峰值内存 = N 张图的中间产物之和。
        return try autoreleasepool {
            try ArchivePerformance.measure(.image, "processImage") {
                try processImageSourceImpl(
                source,
                originalFilename: originalFilename,
                originalSize: originalSize,
                    maxPixelSize: maxPixelSize,
                    quality: quality
                )
            }
        }
    }

    private static func processImageSourceImpl(
        _ source: CGImageSource,
        originalFilename: String,
        originalSize: Int64,
        maxPixelSize: Int = 3840,
        quality: Double = 0.85
    ) throws -> ProcessedPhoto {
        // 属性只读一次：既用于 EXIF 摘要，也用于写入 JPEG 的 EXIF/TIFF 字典
        let originalProperties = copyProperties(from: source)
        let exifSummary = originalProperties.map(exifSummary(from:)) ?? EXIFSummary()

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        // 关键：解码失败时**不得**回退到全分辨率解码。
        // 5000×4000 原图全量解码约 80MB，12000×9000 约 432MB —— 直接把应用推向 OOM。
        // 改为以更小尺寸重试一次，仍失败则明确报错。
        var cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
        if cgImage == nil {
            let retryOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(512, maxPixelSize / 4)
            ]
            cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, retryOptions as CFDictionary)
        }
        guard let cgImage else {
            throw APIError.decodingFailure("无法解码图像像素: \(originalFilename)")
        }

        let width = cgImage.width
        let height = cgImage.height

        // 关键：不要把 JPEG 编码结果写进内存 CFMutableData。
        // macOS 27 + 部分带 ICC 配置的 JPEG 在「内存目的端 + 压缩质量」组合下，
        // CGImageDestinationFinalize 会在 CoreFoundation 内部触发
        // 「Invalid length passed to CFDataReplaceBytes when newBytes == NULL」并 SIGTRAP。
        // 已用 47 张真实缓存图复现（其中 11 张必崩）；改为先写临时文件再读回，
        // 既绕开该崩溃，也保留原始色彩配置与 EXIF。
        let destType = UTType.jpeg.identifier as CFString
        let encodeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("looseleaf-encode-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: encodeURL) }
        guard let destination = CGImageDestinationCreateWithURL(encodeURL as CFURL, destType, 1, nil) else {
            throw APIError.decodingFailure("创建 JPEG 编码器失败")
        }

        var destProps: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        if let origProps = originalProperties {
            if let exif = origProps[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                var cleanExif = exif
                cleanExif.removeValue(forKey: kCGImagePropertyOrientation)
                destProps[kCGImagePropertyExifDictionary] = cleanExif
            }
            if var tiff = origProps[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                // 因像素数据已由 kCGImageSourceCreateThumbnailWithTransform 旋转正立，
                // TIFF 中的 Orientation 必须规范化为 1 (Normal / Top-Left)，
                // 否则下游看图器或浏览器会按旧 Orientation 产生二次翻转 (Double Rotation Bug)。
                tiff[kCGImagePropertyTIFFOrientation] = 1
                destProps[kCGImagePropertyTIFFDictionary] = tiff
            }
        }
        // 顶级方向属性显式声明为 1 (已正立)
        destProps[kCGImagePropertyOrientation] = 1

        CGImageDestinationAddImage(destination, cgImage, destProps as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw APIError.decodingFailure("图像压制输出失败")
        }

        guard let compressedData = try? Data(contentsOf: encodeURL) else {
            throw APIError.decodingFailure("读取 JPEG 编码结果失败")
        }
        let baseName = (originalFilename as NSString).deletingPathExtension
        // 文件名清洗：剔除路径分隔符与非法字符，避免生成 "../../etc/passwd.jpg" 这类名字
        let sanitized = baseName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBase = sanitized.isEmpty ? "photo-\(Int(Date().timeIntervalSince1970))" : sanitized
        let outputFilename = "\(cleanBase).jpg"

        return ProcessedPhoto(
            compressedData: compressedData,
            filename: outputFilename,
            mimeType: "image/jpeg",
            originalSize: originalSize,
            compressedSize: Int64(compressedData.count),
            width: width,
            height: height,
            exifMetadata: exifSummary
        )
    }

    // MARK: - 后台线程压制包装（避免阻塞主线程 UI）

    /// 在后台线程执行端侧 4K 压制（拖拽大图时保持 UI 顺滑）
    public static func processImageFileInBackground(
        at fileURL: URL,
        maxPixelSize: Int = 3840,
        quality: Double = 0.85
    ) async throws -> ProcessedPhoto {
        try await BackgroundExecutor.run {
            try processImageFile(at: fileURL, maxPixelSize: maxPixelSize, quality: quality)
        }
    }

    /// 在后台线程处理内存中的图像数据（剪贴板粘贴等场景）
    public static func processImageDataInBackground(
        _ rawData: Data,
        originalFilename: String,
        maxPixelSize: Int = 3840,
        quality: Double = 0.85
    ) async throws -> ProcessedPhoto {
        try await BackgroundExecutor.run {
            try processImageData(rawData, originalFilename: originalFilename, maxPixelSize: maxPixelSize, quality: quality)
        }
    }
}
