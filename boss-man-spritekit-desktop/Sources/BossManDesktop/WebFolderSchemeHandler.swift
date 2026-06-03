import Foundation
import WebKit

// MARK: - Local web payload served over a custom scheme

final class WebFolderSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "bossman"

    private let root: URL

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }

        var relative = url.path
        if relative.hasPrefix("/") { relative.removeFirst() }
        if relative.isEmpty { relative = "server.html" }

        let fileURL = root.appendingPathComponent(relative).standardizedFileURL

        guard fileURL.path == root.path || fileURL.path.hasPrefix(root.path + "/") else {
            task.didFailWithError(URLError(.noPermissionsToReadFile))
            return
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            task.didReceive(response)
            task.didReceive(Data())
            task.didFinish()
            return
        }

        let headers = [
            "Content-Type": Self.mimeType(for: fileURL.pathExtension),
            "Content-Length": String(data.count),
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "no-store",
        ]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs":   return "text/javascript; charset=utf-8"
        case "wasm":        return "application/wasm"
        case "json":        return "application/json; charset=utf-8"
        case "css":         return "text/css; charset=utf-8"
        case "png":         return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif":         return "image/gif"
        case "svg":         return "image/svg+xml"
        case "ttf":         return "font/ttf"
        case "otf":         return "font/otf"
        case "woff":        return "font/woff"
        case "woff2":       return "font/woff2"
        case "wav":         return "audio/wav"
        case "mp3":         return "audio/mpeg"
        case "ogg":         return "audio/ogg"
        default:            return "application/octet-stream"
        }
    }
}
