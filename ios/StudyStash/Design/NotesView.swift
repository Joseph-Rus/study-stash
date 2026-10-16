import SwiftUI
import WebKit

/// The library's rendered notes (safe HTML, no scripts of its own), in a page that reads like the app: formulas
/// through the bundled KaTeX, wide tables scrolling sideways, as tall as its content so it sits in a scroll view.
/// Links open in Safari, or as a search for a topic.
struct NotesView: View {
    var html: String
    var accent: Color
    var onLink: (URL) -> Void = { UIApplication.shared.open($0) }

    @State private var height: CGFloat = 120

    var body: some View {
        NotesWebView(html: html, accentCSS: accent.cssString, height: $height, onLink: onLink)
            .frame(height: height)
    }
}

private struct NotesWebView: UIViewRepresentable {
    var html: String
    var accentCSS: String
    @Binding var height: CGFloat
    var onLink: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "height")
        config.dataDetectorTypes = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.navigationDelegate = context.coordinator
        context.coordinator.load(web, html: html, accent: accentCSS)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.load(web, html: html, accent: accentCSS)
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "height")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: NotesWebView
        private var loaded: String?

        init(_ parent: NotesWebView) { self.parent = parent }

        func load(_ web: WKWebView, html: String, accent: String) {
            let page = Self.page(html, accent: accent)
            guard page != loaded else { return }
            loaded = page
            web.loadHTMLString(page, baseURL: Bundle.main.resourceURL?.appending(path: "Notes", directoryHint: .isDirectory))
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let h = message.body as? Double, h > 0 else { return }
            let new = CGFloat(h.rounded(.up))
            if abs(new - parent.height) > 1 { DispatchQueue.main.async { self.parent.height = new } }
        }

        func webView(_ web: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            if action.navigationType == .linkActivated, let url = action.request.url {
                await MainActor.run { parent.onLink(url) }
                return .cancel
            }
            return .allow
        }

        static func page(_ html: String, accent: String) -> String {
            """
            <!doctype html><html><head><meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
            <link rel="stylesheet" href="katex.min.css"><link rel="stylesheet" href="notes.css">
            <style>:root{--accent:\(accent)}</style>
            <script src="katex.min.js"></script>
            </head><body><div id="notes">\(html)</div>
            <script>
            (function(){
              var root = document.getElementById('notes');
              root.querySelectorAll('.math[data-tex]').forEach(function(el){
                try { katex.render(el.dataset.tex, el, {displayMode: el.classList.contains('display'), throwOnError: false}); } catch(e) {}
              });
              root.querySelectorAll('table').forEach(function(t){
                if (t.parentElement.classList.contains('table-scroll')) return;
                var box = document.createElement('div'); box.className = 'table-scroll'; t.replaceWith(box); box.append(t);
              });
              function send(){ window.webkit.messageHandlers.height.postMessage(document.documentElement.scrollHeight); }
              new ResizeObserver(send).observe(document.body);
              document.addEventListener('toggle', send, true);
              window.addEventListener('load', send);
              send();
            })();
            </script></body></html>
            """
        }
    }
}

extension Color {
    /// "rgb(12 140 150)", for a page's CSS.
    var cssString: String {
        let c = UIColor(self).resolvedColor(with: UITraitCollection.current)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return "rgb(\(Int(r * 255)) \(Int(g * 255)) \(Int(b * 255)))"
    }
}
