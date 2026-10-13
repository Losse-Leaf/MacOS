import Foundation

/// 预签名 Cloudflare R2 直传执行引擎（支持进度回调与本地未配 R2 自动平滑回退）
/// 严格遵循 docs/macos.md §3.3 与 docs/backend.md §4.4 规范
public final class R2DirectUploader: NSObject, Sendable {
    public static let shared = R2DirectUploader()

    private override init() {
        super.init()
    }

    /// 执行完整图片压制后直传流水线：
    /// 1. 请求 POST /api/v1/uploads/presign
    /// 2. 执行 HTTP PUT 直传 R2 存储桶（实时回调进度）
    /// 3. 请求 POST /api/v1/uploads/complete 确认落库
    /// 若后端未配置 R2 (HTTP 503)，自动回退至 POST /api/v1/files/upload 本地存储通道
    public func uploadProcessedPhoto(
        _ photo: ImageProcessor.ProcessedPhoto,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Attachment {
        onProgress?(0.08)

        do {
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
            return attachment
        } catch let apiError as APIError {
            // 当本地后端未配置 R2 环境变量返回 503 时，自动通过统一上传接口写入 data/uploads/
            if case .serverError(let code, _) = apiError, code == 503 {
                onProgress?(0.45)
                let attachment = try await APIClient.shared.uploadUnifiedMultipart(
                    fileData: photo.compressedData,
                    filename: photo.filename,
                    mimeType: photo.mimeType,
                    folder: "entries"
                )
                onProgress?(1.0)
                return attachment
            }
            throw apiError
        }
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
