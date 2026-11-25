import Foundation
import WebKit

// Read-only game asset transport for legacy Flash CDN resources lacking CORS.
// This does not proxy account requests, send cookies, or expose arbitrary URLs.
final class GameAssets: NSObject, WKScriptMessageHandlerWithReply, URLSessionTaskDelegate {
    static let maximumAssetBytes = 256 * 1024 * 1024
    var onFailure: ((String) -> Void)?
    private let queue = DispatchQueue(label: "Flash4399.gameAssets")
    private var files: [URL: (URL, String)] = [:]
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    static func allowed(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              let host = url.host?.lowercased(),
              ["4399.com", "5054399.com"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return false }
        let path = url.path.lowercased()
        return path.hasPrefix("/4399swf/") || path.hasPrefix("/upload_swf/")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(Self.allowed) == true ? request : nil)
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        let origin = message.frameInfo.securityOrigin.host.lowercased()
        guard ["4399.com", "5054399.com"].contains(where: { origin == $0 || origin.hasSuffix("." + $0) }),
              let body = message.body as? [String: Any], let raw = body["url"] as? String,
              let url = URL(string: raw), Self.allowed(url),
              let offset = body["offset"] as? Int, offset >= 0, offset <= Self.maximumAssetBytes else {
            fail("素材地址或读取范围不受支持", reply: replyHandler)
            return
        }
        queue.async { [self] in
            if let cached = files[url] {
                read(cached, offset: offset, reply: replyHandler)
                return
            }
            guard offset == 0 else { fail("素材缓存已过期，请重新加载游戏", url: url, reply: replyHandler); return }
            var request = URLRequest(url: url)
            request.setValue("https://www.4399.com/", forHTTPHeaderField: "Referer")
            session.downloadTask(with: request) { [self] temp, response, error in
                guard error == nil, let temp, let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode), let finalURL = response.url, Self.allowed(finalURL) else {
                    let detail = error.map { "\(($0 as NSError).code)：\($0.localizedDescription)" }
                        ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)，或素材重定向不受支持"
                    fail("下载失败：\(detail)", url: url, reply: replyHandler)
                    return
                }
                do {
                    let size = try temp.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= Self.maximumAssetBytes else {
                        fail("素材为 \(size) 字节，超过 256 MiB 上限", url: url, reply: replyHandler)
                        return
                    }
                    let destination = FileManager.default.temporaryDirectory.appendingPathComponent("4399-" + UUID().uuidString)
                    try FileManager.default.moveItem(at: temp, to: destination)
                    let entry = (destination, response.mimeType ?? "application/octet-stream")
                    queue.async { [self] in
                        // Keep disk cache bounded; already-running readers finish one chunk at a time.
                        if files.count >= 8, let old = files.keys.first, let value = files.removeValue(forKey: old) {
                            try? FileManager.default.removeItem(at: value.0)
                        }
                        files[url] = entry
                        read(entry, offset: offset, reply: replyHandler)
                    }
                } catch { fail("无法缓存素材：\(error.localizedDescription)", url: url, reply: replyHandler) }
            }.resume()
        }
    }

    private func read(_ entry: (URL, String), offset: Int, reply: @escaping (Any?, String?) -> Void) {
        do {
            let bytes = try Self.readChunk(file: entry.0, offset: offset)
            reply(["data": bytes.base64EncodedString(), "mime": entry.1], nil)
        } catch { fail("无法读取素材：\(error.localizedDescription)", reply: reply) }
    }

    static func readChunk(file url: URL, offset: Int) throws -> Data {
        guard offset >= 0, offset <= maximumAssetBytes else { throw CocoaError(.fileReadTooLarge) }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        try file.seek(toOffset: UInt64(offset))
        return try file.read(upToCount: 256 * 1024) ?? Data()
    }

    private func fail(_ message: String, url: URL? = nil, reply: @escaping (Any?, String?) -> Void) {
        let detail = "游戏素材加载失败：\(message)" + (url.map { "\n\($0.absoluteString)" } ?? "")
        DispatchQueue.main.async { [weak self] in self?.onFailure?(detail) }
        reply(nil, message)
    }
}
