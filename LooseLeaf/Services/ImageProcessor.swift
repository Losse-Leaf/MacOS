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
            if let fl = focalLength, fl > 0 {
                if fl.truncatingRemainder(dividingBy: 1) == 0 {
                    lensSpec.append("\(Int(fl))mm")
                } else {
                    lensSpec.append(String(format: "%.1fmm", fl))
                }
            }
            if let fn = fNumber, fn > 0 {
                lensSpec.append(String(format: "F%.1f", fn))
            }
            if !lensSpec.isEmpty {
                parts.append(lensSpec.joined(separator: " "))
            } else if !lensModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(lensModel.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            if let exp = exposureTime, exp > 0 {
                if exp < 1.0 {
                    let denom = Int(round(1.0 / exp))
                    if denom > 0 {
                        parts.append("1/\(denom)s")
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
        guard let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return EXIFSummary()
        }

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
        let rawData = try Data(contentsOf: fileURL)
        return try processImageData(
            rawData,
            originalFilename: fileURL.lastPathComponent,
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

        let exifSummary = extractEXIF(from: source)

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
                ?? CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw APIError.decodingFailure("无法解码图像像素: \(originalFilename)")
        }

        let width = cgImage.width
        let height = cgImage.height

        let mutableData = CFDataCreateMutable(nil, 0)!
        let destType = UTType.jpeg.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(mutableData, destType, 1, nil) else {
            throw APIError.decodingFailure("创建 JPEG 编码器失败")
        }

        var destProps: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        if let origProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            if let exif = origProps[kCGImagePropertyExifDictionary] {
                destProps[kCGImagePropertyExifDictionary] = exif
            }
            if let tiff = origProps[kCGImagePropertyTIFFDictionary] {
                destProps[kCGImagePropertyTIFFDictionary] = tiff
            }
        }

        CGImageDestinationAddImage(destination, cgImage, destProps as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw APIError.decodingFailure("图像压制输出失败")
        }

        let compressedData = mutableData as Data
        let baseName = (originalFilename as NSString).deletingPathExtension
        let cleanBase = baseName.isEmpty ? "darkroom-\(Int(Date().timeIntervalSince1970))" : baseName
        let outputFilename = "\(cleanBase).jpg"

        return ProcessedPhoto(
            compressedData: compressedData,
            filename: outputFilename,
            mimeType: "image/jpeg",
            originalSize: Int64(rawData.count),
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
        try await Task.detached(priority: .userInitiated) {
            try processImageFile(at: fileURL, maxPixelSize: maxPixelSize, quality: quality)
        }.value
    }

    /// 在后台线程处理内存中的图像数据（剪贴板粘贴等场景）
    public static func processImageDataInBackground(
        _ rawData: Data,
        originalFilename: String,
        maxPixelSize: Int = 3840,
        quality: Double = 0.85
    ) async throws -> ProcessedPhoto {
        try await Task.detached(priority: .userInitiated) {
            try processImageData(rawData, originalFilename: originalFilename, maxPixelSize: maxPixelSize, quality: quality)
        }.value
    }
}
