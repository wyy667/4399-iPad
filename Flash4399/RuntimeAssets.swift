import Foundation
import WebKit

// The only native bridge is read-only access to the two bundled WASM files.
// No arbitrary file reads, network proxy, cookie access, or native code execution.
final class RuntimeAssets: NSObject, WKScriptMessageHandlerWithReply {
    static let names: Set<String> = [
        "ruffle_web_bg.QDRSAAAZ.wasm",
        "ruffle_web-wasm_mvp_bg.UMWKJ7EM.wasm"
    ]

    static func resource(_ name: String) throws -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "WebAssets") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any],
              let name = body["name"] as? String, Self.names.contains(name),
              let offset = body["offset"] as? Int, offset >= 0, offset <= 32 * 1024 * 1024,
              let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "WebAssets/Ruffle") else {
            replyHandler(nil, "Invalid bundled resource request")
            return
        }
        do {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            try file.seek(toOffset: UInt64(offset))
            let data = try file.read(upToCount: 256 * 1024) ?? Data()
            replyHandler(data.base64EncodedString(), nil)
        } catch {
            replyHandler(nil, "Unable to read bundled runtime")
        }
    }
}
