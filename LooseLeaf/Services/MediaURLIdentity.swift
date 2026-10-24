// MediaURLIdentity.swift
// 媒体 URL 的稳定身份（网络合并与缓存共用）
//
// 背景：预签名 URL 每次下发都会变（X-Amz-Signature / exp / sig…），
// 若拿完整 URL 做请求合并或缓存键，命中率永远是 0。
// 但**不能把 query 全剥掉**：缩略图接口是
// `/api/v1/files/thumbnail?key=<object_key>&w=<width>` ——
// key 与 w 都是资源身份的一部分，全剥掉会让不同照片的缩略图被合并成同一份。

import Foundation

enum MediaURLIdentity {
    /// 仅这些「每次签发都会变」的参数不参与身份比较（小写）。
    static let volatileQueryNames: Set<String> = [
        "x-amz-signature", "x-amz-credential", "x-amz-date", "x-amz-expires",
        "x-amz-algorithm", "x-amz-security-token", "x-amz-signedheaders",
        "signature", "expires", "token", "exp", "sig",
        // 兼容旧缓存身份里被视作「时间戳噪声」的参数，避免升级后缓存全量失效。
        "t", "ts", "time"
    ]

    /// 保留协议 + 主机 + 路径 + 非签名查询参数。
    static func stableURL(for url: URL) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems else {
            return url
        }
        let kept = items.filter { !volatileQueryNames.contains($0.name.lowercased()) }
        guard kept.count != items.count else { return url }
        comps.queryItems = kept.isEmpty ? nil : kept
        return comps.url ?? url
    }

    static func stableKey(for url: URL) -> String {
        stableURL(for: url).absoluteString
    }
}
