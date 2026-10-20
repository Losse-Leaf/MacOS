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

        // 声明系统活动：上传期间阻止 App Nap / 空闲休眠，
        // 否则大图在后台被系统 Nap 后上传会被中断，产物半途中断。
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .background],
            reason: "正在上传相纸至对象存储"
        )
        defer { ProcessInfo.processInfo.endActivity(activity) }

        do {
            return try await performDirectUpload(photo, onProgress: onProgress)
        } catch {
            // 仅在「后端明确未配置 R2 (503)」时回退到中枢本地统一上传通道。
            // 关键：网络抖动（.networkFailure）**不**回退 —— 否则同一张图会在两个存储后端各留一份，
            // 且 R2 上可能已有半成品对象，造成数据分散与孤儿对象。
            let shouldFallback: Bool
            if let apiError = error as? APIError {
                switch apiError {
                case .serverError(let code, _):
                    shouldFallback = (code == 503)
                case .storageError(_, _):
                    shouldFallback = false
                default:
                    shouldFallback = false
                }
            } else {
                shouldFallback = false
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
        // 1. presign：**不重试**。重试会生成新的 uploadId，导致旧对象成为孤儿。
        let presigned = try await APIClient.shared.presignUpload(presignReq)
        onProgress?(0.20)

        guard let putURL = URL(string: presigned.uploadUrl) else {
            throw APIError.invalidURL(presigned.uploadUrl)
        }

        var putRequest = URLRequest(url: putURL)
        putRequest.httpMethod = "PUT"
        putRequest.setValue(photo.mimeType, forHTTPHeaderField: "Content-Type")
        putRequest.setValue(String(photo.compressedSize), forHTTPHeaderField: "Content-Length")
        // 大图在弱网下可能上传数分钟，默认 60s 会误判超时
        putRequest.timeoutInterval = 300

        let delegate = UploadProgressDelegate { fraction in
            let mapped = 0.20 + (fraction * 0.68)
            onProgress?(mapped)
        }

        // 2. PUT：可重试（同一 uploadId，幂等）
        let response: URLResponse = try await withRetry {
            let (_, resp) = try await Self.uploadSession.upload(
                for: putRequest,
                from: photo.compressedData,
                delegate: delegate
            )
            return resp
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.storageError(statusCode: 0, message: "R2 存储桶直传响应无效")
        }
        guard (200..<300).contains(http.statusCode) else {
            // 关键：4xx（桶不存在 404 / 签名过期 403 / CORS 拒绝 400）属于**永久错误**，
            // 不得包装成可重试的 networkFailure —— 否则整张图会被白白重传 3 次。
            throw APIError.storageError(statusCode: http.statusCode, message: "R2 存储桶直传失败 (HTTP \(http.statusCode))")
        }

        onProgress?(0.92)

        // 3. complete：按 uploadId 幂等重试（服务端按 uploadId 去重，不会产生重复对象）
        let completeReq = CompleteUploadRequest(
            uploadId: presigned.uploadId,
            objectKey: presigned.objectKey,
            originalFilename: photo.filename,
            mimeType: photo.mimeType,
            size: photo.compressedSize,
            width: photo.width,
            height: photo.height
        )
        let attachment = try await withRetry {
            try await APIClient.shared.completeUpload(completeReq)
        }
        onProgress?(1.0)
        Self.logger.info("R2 direct upload finished: \(photo.filename, privacy: .public)")
        return attachment
    }

    /// 直传专用会话：长超时 + 等待网络恢复
    private static let uploadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    /// 网络类失败自动退避重试（最多 3 次尝试；4xx 业务错误不重试）
    /// 退避改为指数 + 抖动，避免多端同时失败时形成惊群；并尊重取消信号。
    private func withRetry<T>(_ operation: () async throws -> T) async throws -> T {
        let maxAttempts = 3
        var lastError: Error = APIError.networkFailure("未知上传错误")
        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                let retryable: Bool
                if let apiError = error as? APIError {
                    switch apiError {
                    case .networkFailure:
                        retryable = true
                    case .serverError(let code, _):
                        retryable = code >= 500
                    case .storageError(let statusCode, _):
                        // 存储桶 4xx 是永久错误（桶不存在 / 签名过期 / CORS 拒绝）
                        retryable = statusCode >= 500 || statusCode == 0
                    default:
                        retryable = false
                    }
                } else {
                    retryable = true
                }
                guard retryable, attempt < maxAttempts - 1 else { break }
                let delaySeconds = pow(2.0, Double(attempt)) * 0.8 + Double.random(in: 0...0.3)
                Self.logger.warning("Upload attempt \(attempt + 1) failed, retrying in \(delaySeconds) s")
                try await Task.sleep(for: .seconds(delaySeconds))
            }
        }
        throw lastError
    }
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let handler: @Sendable (Double) -> Void
    private let lock = NSLock()
    // 可变状态全部在 lock 保护下访问
    nonisolated(unsafe) private var lastFraction: Double = -1
    nonisolated(unsafe) private var lastEmittedAt: Date = .distantPast

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

        // URLSession 的回调频率可达每帧数次；这里在源头节流，避免为每个字节块派发一个 MainActor Task
        lock.lock()
        let now = Date()
        let shouldEmit = ratio >= 1.0
            || lastFraction < 0
            || ratio - lastFraction >= 0.02
            || now.timeIntervalSince(lastEmittedAt) >= 0.12
        if shouldEmit {
            lastFraction = ratio
            lastEmittedAt = now
        }
        lock.unlock()

        guard shouldEmit else { return }
        handler(ratio)
    }
}
