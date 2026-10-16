import SwiftUI
import WebKit

/// The library's rendered notes (safe HTML, no scripts of its own) in a page that reads as the desktop's notes do
/// (Resources/Notes/notes.css): Atkinson at a reading size that grows with the phone's text size, formulas through the
/// bundled KaTeX, diagrams in the app's own colours, wide tables scrolling sideways, light or dark as the app is. As tall
/// as its content, so it sits in a scroll view. Web links open in Safari.
///
/// A lecture's notes (`provenance`) also tell whose words are whose, as the desktop's do: what the student typed
/// (`==marked==` in the notes) in ink and heavier, what was written from the recording in the muted ink, and a
/// leading "Summary" heading dropped (the page above already says what this is). `onlyMine` shows the student's
/// words alone. An assignment's instructions leave both off: all one ink.
struct NotesView: View {
    var html: String
    /// Kept so callers from before still compile: the notes have no accent colour now (the tint is ink).
    var accent: Color = .ink
    var provenance = false
    var onlyMine = false
    var onLink: (URL) -> Void = { UIApplication.shared.open($0) }

    @State private var height: CGFloat = 120
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NotesWebView(html: html, provenance: provenance, onlyMine: onlyMine, dark: scheme == .dark, height: $height, onLink: onLink)
            .frame(height: height)
    }
}

private struct NotesWebView: UIViewRepresentable {
    var html: String
    var provenance: Bool
    var onlyMine: Bool
    var dark: Bool
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
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.showsVerticalScrollIndicator = false
        web.scrollView.showsHorizontalScrollIndicator = false
        web.allowsLinkPreview = false
        web.navigationDelegate = context.coordinator
        context.coordinator.load(web)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.load(web)
        context.coordinator.apply(web)
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "height")
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: NotesWebView
        private var loaded: String?
        private var ready = false
        private var shownDark: Bool?
        private var shownOnlyMine: Bool?

        init(_ parent: NotesWebView) { self.parent = parent }

        /// The page again only when the notes themselves changed; light or dark and "Only my notes" are switched in it.
        func load(_ web: WKWebView) {
            let key = "\(parent.provenance)\u{1}\(parent.html)"
            guard key != loaded else { return }
            loaded = key
            ready = false
            shownDark = parent.dark
            shownOnlyMine = parent.onlyMine
            // From the app's own folder: notes.css finds Atkinson there, and katex.min.css its fonts in Notes/fonts.
            web.loadHTMLString(Self.page(parent.html, provenance: parent.provenance, onlyMine: parent.onlyMine, dark: parent.dark),
                               baseURL: Bundle.main.resourceURL)
        }

        func apply(_ web: WKWebView) {
            guard ready else { return }
            if shownDark != parent.dark {
                shownDark = parent.dark
                web.evaluateJavaScript("notesDark(\(parent.dark))")
            }
            if shownOnlyMine != parent.onlyMine {
                shownOnlyMine = parent.onlyMine
                web.evaluateJavaScript("notesOnlyMine(\(parent.onlyMine))")
            }
        }

        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            // What changed while it loaded.
            shownDark = nil
            shownOnlyMine = nil
            apply(web)
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let h = message.body as? Double, h > 0 else { return }
            let new = CGFloat(h.rounded(.up))
            if abs(new - parent.height) > 1 { parent.height = new }
        }

        func webView(_ web: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard action.navigationType == .linkActivated, let url = action.request.url else { return .allow }
            // A web page or an email opens in its own app; anything else (a footnote's #mark, a file) stays put.
            if let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) { parent.onLink(url) }
            return .cancel
        }

        static func page(_ html: String, provenance: Bool, onlyMine: Bool, dark: Bool) -> String {
            let classes = [provenance ? "prov" : nil, provenance && onlyMine ? "only-mine" : nil].compactMap { $0 }.joined(separator: " ")
            return """
            <!doctype html><html\(dark ? " class=\"dark\"" : "")><head><meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
            <link rel="stylesheet" href="Notes/katex.min.css"><link rel="stylesheet" href="Notes/notes.css">
            <script src="Notes/katex.min.js"></script>
            </head><body class="\(classes)"><div id="notes">\(html)</div>
            <script>\(script)</script></body></html>
            """
        }

        /// Dresses the notes once they're on the page: tables in a box of their own that scrolls sideways, the
        /// student's ==marks== as their words (and, round them, what was written from the recording), a leading
        /// "Summary" heading dropped, the Definitions as two columns, formulas typeset; then says how tall it is.
        static let script = #"""
        (function(){
          var root = document.getElementById('notes'), body = document.body;
          var lecture = body.classList.contains('prov');

          root.querySelectorAll('table').forEach(function(t){
            if (t.parentElement.classList.contains('table-scroll')) return;
            var box = document.createElement('div'); box.className = 'table-scroll'; t.replaceWith(box); box.append(t);
          });

          // Blocks whose words are read a line at a time, and what inside one is a block of its own.
          var LEAF = 'p,li,h1,h2,h3,h4,h5,h6,td,th,dt,dd';
          var NESTED = {P:1,UL:1,OL:1,TABLE:1,PRE:1,FIGURE:1,BLOCKQUOTE:1,DL:1,DIV:1,DETAILS:1,H1:1,H2:1,H3:1,H4:1,H5:1,H6:1};
          function atom(n) {
            return (n.classList && n.classList.contains('math')) || n.tagName === 'CODE' || n.tagName === 'IMG' || n.tagName === 'BR'
              || n.namespaceURI === 'http://www.w3.org/2000/svg';
          }
          // A block's words as one run of text, each piece knowing where it came from (a formula is one character).
          function pieces(block) {
            var out = [], at = 0;
            (function walk(el) {
              for (var n = el.firstChild; n; n = n.nextSibling) {
                if (n.nodeType === 3) { out.push({n: n, s: at, t: n.data}); at += n.data.length; }
                else if (n.nodeType === 1) {
                  if (atom(n)) { out.push({n: n, s: at, t: '\uFFFC', atom: true}); at += 1; }
                  else if (!NESTED[n.tagName]) walk(n);
                }
              }
            })(block);
            return out;
          }
          function point(list, p, start) {
            for (var i = 0; i < list.length; i++) {
              var x = list[i], end = x.s + x.t.length;
              if (start ? (p >= x.s && p < end) : (p > x.s && p <= end)) return {x: x, off: p - x.s};
            }
            return null;
          }
          var MARK = /==(?=\S)([\s\S]+?)(?<=\S)==/g;
          // What the student typed (==like this==) becomes a span.mine, the marks gone.
          function markBlock(block) {
            var list = pieces(block);
            var text = list.map(function(x){ return x.t; }).join('');
            if (text.indexOf('==') < 0) return;
            var found = [], m;
            MARK.lastIndex = 0;
            while ((m = MARK.exec(text))) found.push([m.index, m.index + m[0].length]);
            for (var i = found.length - 1; i >= 0; i--) {
              var a = found[i][0], b = found[i][1];
              var open = point(list, a, true), close = point(list, b - 2, true);
              var from = point(list, a + 2, true), to = point(list, b - 2, false);
              if (!open || !close || !from || !to || open.x.atom || close.x.atom
                  || open.off + 2 > open.x.t.length || close.off + 2 > close.x.t.length) continue;
              close.x.n.deleteData(close.off, 2);
              var r = document.createRange();
              if (from.x.atom) r.setStartBefore(from.x.n); else r.setStart(from.x.n, from.off);
              if (to.x.atom) r.setEndAfter(to.x.n); else r.setEnd(to.x.n, to.off);
              var span = document.createElement('span');
              span.className = 'mine';
              span.appendChild(r.extractContents());
              r.insertNode(span);
              open.x.n.deleteData(open.off, 2);
            }
          }
          // Round the student's words in a block, the rest is what was written from the recording.
          function markAi(el) {
            Array.prototype.slice.call(el.childNodes).forEach(function(n){
              if (n.nodeType === 3) {
                if (!/\S/.test(n.data)) return;
                var s = document.createElement('span'); s.className = 'ai'; n.replaceWith(s); s.appendChild(n);
              } else if (n.nodeType === 1) {
                if (n.classList.contains('mine') || (NESTED[n.tagName] && !n.classList.contains('math'))) return;
                if (n.querySelector('.mine')) markAi(n); else n.classList.add('ai');
              }
            });
          }

          if (lecture) {
            root.querySelectorAll(LEAF).forEach(markBlock);
            var first = root.firstElementChild;
            if (first && /^H[1-6]$/.test(first.tagName) && /^\s*summary\s*$/i.test(first.textContent)) first.remove();
          }

          // The Definitions (or a list whose every item is "**term**: …"): term and meaning side by side.
          function term(li) {
            for (var n = li.firstChild; n; n = n.nextSibling) {
              if (n.nodeType === 3) { if (/\S/.test(n.data)) return null; continue; }
              if (n.nodeType !== 1) continue;
              if (n.tagName === 'STRONG') return n;
              if (n.classList.contains('mine') && n.firstElementChild && n.firstElementChild.tagName === 'STRONG'
                  && n.firstChild === n.firstElementChild) return n;
              return null;
            }
            return null;
          }
          function after(t) {
            var s = '';
            for (var n = t.nextSibling; n && s.length < 3; n = n.nextSibling) s += n.textContent;
            return /^\s*[:\u2014\u2013-]/.test(s);
          }
          var section = '';
          Array.prototype.slice.call(root.children).forEach(function(el){
            if (/^H[1-6]$/.test(el.tagName)) { section = el.textContent.trim().toLowerCase(); return; }
            if (el.tagName !== 'UL') return;
            var items = Array.prototype.slice.call(el.children).filter(function(li){ return li.tagName === 'LI'; });
            items.forEach(function(li){
              // A loose list's item is a paragraph: its words are the item's.
              if (li.children.length === 1 && li.firstElementChild.tagName === 'P') {
                var p = li.firstElementChild; while (p.firstChild) li.insertBefore(p.firstChild, p); p.remove();
              }
            });
            var terms = items.map(term);
            if (!items.length || terms.some(function(t){ return !t; })) return;
            if (section !== 'definitions' && !terms.every(after)) return;
            el.classList.add('defs');
            items.forEach(function(li, i){
              var t = document.createElement('span'); t.className = 'term';
              li.insertBefore(t, terms[i]); t.appendChild(terms[i]);
              var mean = document.createElement('span'); mean.className = 'meaning';
              while (t.nextSibling) mean.appendChild(t.nextSibling);
              li.appendChild(mean);
              var walk = document.createTreeWalker(mean, NodeFilter.SHOW_TEXT), n;
              while ((n = walk.nextNode())) {
                var trimmed = n.data.replace(/^[\s:\u2014\u2013-]+/, '');
                n.data = trimmed.charAt(0).toUpperCase() + trimmed.slice(1);
                if (trimmed.length) break;
              }
            });
          });

          if (lecture && root.querySelector('.mine')) {
            root.querySelectorAll(LEAF).forEach(function(b){ if (b.querySelector('.mine')) markAi(b); });
            root.querySelectorAll('p,li,ul,ol,h1,h2,h3,h4,h5,h6,.table-scroll,tr,figure,pre,blockquote,dl,dt,dd,hr,details,div.math,.footnotes')
              .forEach(function(el){ if (!el.querySelector('.mine') && !el.classList.contains('mine')) el.classList.add('no-mine'); });
          }

          root.querySelectorAll('.math[data-tex]').forEach(function(el){
            try { katex.render(el.dataset.tex, el, {displayMode: el.classList.contains('display'), throwOnError: false}); } catch (e) {}
          });

          function send() {
            var h = Math.ceil(root.getBoundingClientRect().bottom + window.scrollY);
            window.webkit.messageHandlers.height.postMessage(h);
          }
          window.notesDark = function(on){ document.documentElement.classList.toggle('dark', on); };
          window.notesOnlyMine = function(on){ body.classList.toggle('only-mine', on); send(); };
          new ResizeObserver(send).observe(root);
          document.addEventListener('toggle', send, true);
          if (document.fonts) document.fonts.ready.then(send);
          window.addEventListener('load', send);
          send();
        })();
        """#
    }
}
