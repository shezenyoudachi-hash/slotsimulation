import SwiftUI
import WebKit

/// YouTube の URL から埋め込み用のパスを取り出す（動画・ライブ・ショート・再生リスト）
enum YouTubeLink {
    static func embedPath(from text: String) -> String? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: s), let host = comps.host?.lowercased() else { return nil }
        let items = comps.queryItems ?? []
        func q(_ name: String) -> String? { items.first { $0.name == name }?.value }
        let parts = comps.path.split(separator: "/").map(String.init)

        if host.hasSuffix("youtu.be"), let id = parts.first { return id }
        guard host.contains("youtube.com") else { return nil }
        if let v = q("v") { return v }
        if parts.count >= 2, ["live", "shorts", "embed"].contains(parts[0]) { return parts[1] }
        if let list = q("list") { return "videoseries?list=\(list)" }
        return nil
    }
}

/// YouTube の埋め込みプレーヤー（公式の埋め込み用ページを表示するだけ）
struct YouTubePlayerView: UIViewRepresentable {
    let embedPath: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.scrollView.isScrollEnabled = false
        web.isOpaque = false
        web.backgroundColor = .black
        load(web)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        if context.coordinator.loaded != embedPath { load(web) }
        context.coordinator.loaded = embedPath
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var loaded: String? }

    private func load(_ web: WKWebView) {
        let sep = embedPath.contains("?") ? "&" : "?"
        let src = "https://www.youtube-nocookie.com/embed/\(embedPath)\(sep)playsinline=1&rel=0"
        // 埋め込みプレーヤーは参照元が無いと再生できないことがあるので、ページとして読み込む
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:#000}iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style>
        </head><body><iframe src="\(src)" allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen
        referrerpolicy="strict-origin-when-cross-origin"></iframe></body></html>
        """
        web.loadHTMLString(html, baseURL: URL(string: "https://slotanalyzer.local/"))
    }
}
