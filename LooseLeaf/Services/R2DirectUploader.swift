import Foundation
import os

/// 预签名 Cloudflare R2 直传执行引擎（支持进度回调、网络退避重试与本地未配 R2 自动平滑回退）
/// 严格遵循 docs/macos.md §3.3 与 docs/backend.md §4.4 规范
public final class R2DirectUploader: NSObject, Sendable {
    public static let shared = R2DirectUploader()

    private static let logger = Logger(subsystem: "com.looseleaf.mac", category: "upload")

    private override init() {
        super.init()
    }

    /// 执行完整图片压制后直传流水线：
    /// 1. 请求 POST /api/v1/uploads/presign
    /// 2. 执行 HTTP PUT 直传 R2 存储桶（实时回调进度）
    /// 3. 请求 POST /api/v1/uploads/complete 确认落库
    /// 网络类失败自动退避重试（最多 3 次尝试）；若后端未配置 R2 (HTTP 503)，自动回退至 POST /api/v1/files/upload 本地存储通道
    public func uploadProcessedPhoto(
        _ photo: ImageProcessor.ProcessedPhoto,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Attachment {
        onProgress?(0.08)

        do {
            return try await withRetry {
                try await performDirectUpload(photo, onProgress: onProgress)
            }
        } catch {
            // 当后端未配置 R2 (503) 或直传存储桶出现网络阻断时，平滑降级至中枢本地统一上传通道 (/api/v1/files/upload)
            let shouldFallback: Bool
            if let apiError = error as? APIError {
                switch apiError {
                case .serverError(let code, _):
                    shouldFallback = (code == 503)
                case .networkFailure:
                    shouldFallback = true
                default:
                    shouldFallback = false
                }
            } else {
                shouldFallback = true
            }

            if shouldFallback {
                Self.logger.warning("R2 direct upload unavailable (\(error.localizedDescription)), falling back to unified multipart upload")
                onProgress?(0.45)
                let attachment = try await APIClient.shared.uploadUnifiedMultipart(
                    fileData: photo.compressedData,
                    filename: photo.filename,
                    mimeType: photo.mimeType,
                    folder: "entries"
                )
                onProgress?(1.0)
                Self.logger.info("Unified multipart fallback upload finished: \(photo.filename, privacy: .public)")
                return attachment
            }
            throw error
        }
    }

    /// 预签名 → PUT 直传 → complete 的完整直传链路（不含 503 回退）
    private func performDirectUpload(
        _ photo: ImageProcessor.ProcessedPhoto,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> Attachment {
        let presignReq = PresignUploadRequest(
            filename: photo.filename,
            contentType: photo.mimeType,
            size: photo.compressedSize
        )
        let presigned = try await APIClient.shared.presignUpload(presignReq)
        onProgress?(0.20)

        guard let putURL = URL(string: presigned.uploadUrl) else {
            throw APIError.invalidURL(presigned.uploadUrl)
        }

        var putRequest = URLRequest(url: putURL)
        putRequest.httpMethod = "PUT"
        putRequest.setValue(photo.mimeType, forHTTPHeaderField: "Content-Type")
        putRequest.setValue(String(photo.compressedSize), forHTTPHeaderField: "Content-Length")

        let delegate = UploadProgressDelegate { fraction in
            let mapped = 0.20 + (fraction * 0.68)
            onProgress?(mapped)
        }

        let (_, response) = try await URLSession.shared.upload(
            for: putRequest,
            from: photo.compressedData,
            delegate: delegate
        )

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.networkFailure("R2 存储桶直传响应状态异常")
        }

        onProgress?(0.92)

        let completeReq = CompleteUploadRequest(
            uploadId: presigned.uploadId,
            objectKey: presigned.objectKey,
            originalFilename: photo.filename,
            mimeType: photo.mimeType,
            size: photo.compressedSize,
            width: photo.width,
            height: photo.height
        )
        let attachment = try await APIClient.shared.completeUpload(completeReq)
        onProgress?(1.0)
        Self.logger.info("R2 direct upload finished: \(photo.filename, privacy: .public)")
        return attachment
    }

    /// 网络类失败自动退避重试（最多 3 次尝试；4xx 业务错误不重试）
    private func withRetry<T>(_ operation: () async throws -> T) async throws -> T {
        let maxAttempts = 3
        var lastError: Error = APIError.networkFailure("未知上传错误")
        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                let retryable: Bool
                if let apiError = error as? APIError {
                    switch apiError {
                    case .networkFailure:
                        retryable = true
                    case .serverError(let code, _):
                        retryable = code >= 500
                    default:
                        retryable = false
                    }
                } else {
                    retryable = true
                }
                guard retryable, attempt < maxAttempts - 1 else { break }
                let delaySeconds = Double(attempt + 1) * 0.8
                Self.logger.warning("Upload attempt \(attempt + 1) failed, retrying in \(delaySeconds) s")
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            }
        }
        throw lastError
    }
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let handler: @Sendable (Double) -> Void

    init(handler: @escaping @Sendable (Double) -> Void) {
        self.handler = handler
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let ratio = min(1.0, max(0.0, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
        handler(ratio)
    }
}
