import Foundation
import WebKit

// Read-only game asset transport for legacy Flash CDN resources lacking CORS.
// This does not proxy account requests, send cookies, or expose arbitrary URLs.
final class GameAssets: NSObject, WKScriptMessageHandlerWithReply, URLSessionTaskDelegate {
    private let queue = DispatchQueue(label: "Flash4399.gameAssets")
    private var files: [URL: (URL, String)] = [:]
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 120
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
              let offset = body["offset"] as? Int, offset >= 0, offset <= 64 * 1024 * 1024 else {
            replyHandler(nil, "Game asset request not allowed")
            return
        }
        queue.async { [self] in
            if let cached = files[url] {
                read(cached, offset: offset, reply: replyHandler)
                return
            }
            guard offset == 0 else { replyHandler(nil, "Asset expired; reload the game"); return }
            var request = URLRequest(url: url)
            request.setValue("https://www.4399.com/", forHTTPHeaderField: "Referer")
            session.downloadTask(with: request) { [self] temp, response, error in
                guard error == nil, let temp, let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode), let finalURL = response.url, Self.allowed(finalURL) else {
                    replyHandler(nil, "Game asset download failed")
                    return
                }
                do {
                    let size = try temp.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 64 * 1024 * 1024 else { replyHandler(nil, "Game asset exceeds 64 MB"); return }
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
                } catch { replyHandler(nil, "Unable to cache game asset") }
            }.resume()
        }
    }

    private func read(_ entry: (URL, String), offset: Int, reply: @escaping (Any?, String?) -> Void) {
        do {
            let file = try FileHandle(forReadingFrom: entry.0)
            defer { try? file.close() }
            try file.seek(toOffset: UInt64(offset))
            let bytes = try file.read(upToCount: 256 * 1024) ?? Data()
            reply(["data": bytes.base64EncodedString(), "mime": entry.1], nil)
        } catch { reply(nil, "Unable to read game asset") }
    }
}
