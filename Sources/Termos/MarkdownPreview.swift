import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit
import cmark_gfm
import cmark_gfm_extensions

/// Renders Markdown to HTML with cmark-gfm, the parser GitHub uses, with its
/// extensions for tables, strikethrough, autolinks and task lists.
enum MarkdownRenderer {
    static func html(for markdown: String) -> String {
        cmark_gfm_core_extensions_ensure_registered()

        // Raw HTML stays (READMEs use <img>, <kbd>, <details>…); the tag filter
        // neutralizes <script>, <iframe> and the like, and the preview runs no JavaScript.
        let options = CMARK_OPT_UNSAFE | CMARK_OPT_FOOTNOTES | CMARK_OPT_GITHUB_PRE_LANG
        guard let parser = cmark_parser_new(options) else { return "" }
        defer { cmark_parser_free(parser) }

        for name in ["table", "strikethrough", "autolink", "tasklist", "tagfilter"] {
            if let extension_ = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, extension_)
            }
        }

        let bytes = Array(markdown.utf8)
        bytes.withUnsafeBufferPointer { buffer in
            buffer.baseAddress?.withMemoryRebound(to: CChar.self, capacity: buffer.count) {
                cmark_parser_feed(parser, $0, buffer.count)
            }
        }
        guard let document = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(document) }

        guard let html = cmark_render_html(document, options, cmark_parser_get_syntax_extensions(parser)) else { return "" }
        defer { free(html) }
        return String(cString: html)
    }

    /// A full page around the rendered body, styled like GitHub and following light / dark mode.
    static func page(for markdown: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <style>\(stylesheet)</style>
        </head>
        <body><article>
        \(html(for: markdown))
        </article></body>
        </html>
        """
    }

    private static let stylesheet = """
    :root {
      --text: #1F1F24; --muted: #59636E; --background: #FFFFFF; --border: #D1D9E0;
      --subtle: #F6F8FA; --link: #0969DA; --code: rgba(129, 139, 152, 0.12);
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --text: #DFDFE0; --muted: #9198A1; --background: #1F1F24; --border: #3D444D;
        --subtle: #26262C; --link: #4493F8; --code: rgba(101, 108, 118, 0.2);
      }
    }
    html { background: var(--background); }
    body {
      margin: 0; color: var(--text); background: var(--background);
      font: 14px/1.6 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
      -webkit-font-smoothing: antialiased; word-wrap: break-word;
    }
    article { max-width: 880px; margin: 0 auto; padding: 24px 32px 48px; }
    a { color: var(--link); text-decoration: none; }
    a:hover { text-decoration: underline; }
    h1, h2, h3, h4, h5, h6 { margin: 24px 0 16px; font-weight: 600; line-height: 1.25; }
    h1 { font-size: 2em; padding-bottom: .3em; border-bottom: 1px solid var(--border); }
    h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid var(--border); }
    h3 { font-size: 1.25em; } h4 { font-size: 1em; } h5 { font-size: .875em; }
    h6 { font-size: .85em; color: var(--muted); }
    article > :first-child { margin-top: 0; }
    p, blockquote, ul, ol, dl, table, pre, details { margin: 0 0 16px; }
    ul, ol { padding-left: 2em; }
    li + li { margin-top: .25em; }
    li > ul, li > ol { margin-bottom: 0; }
    li > input[type=checkbox] { margin: 0 .3em 0 -1.3em; vertical-align: middle; }
    ul:has(> li > input[type=checkbox]) { list-style: none; }
    blockquote { margin-left: 0; padding: 0 1em; color: var(--muted); border-left: .25em solid var(--border); }
    hr { height: .25em; margin: 24px 0; padding: 0; border: 0; background: var(--border); }
    code, pre, kbd { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 85%; }
    code { padding: .2em .4em; border-radius: 6px; background: var(--code); }
    pre { padding: 16px; overflow: auto; line-height: 1.45; border-radius: 6px; background: var(--subtle); }
    pre code { padding: 0; font-size: 100%; background: transparent; }
    kbd {
      display: inline-block; padding: 2px 5px; line-height: 1; vertical-align: middle;
      border: 1px solid var(--border); border-bottom-width: 2px; border-radius: 6px; background: var(--subtle);
    }
    table { display: block; width: max-content; max-width: 100%; overflow: auto; border-collapse: collapse; }
    th, td { padding: 6px 13px; border: 1px solid var(--border); }
    th { font-weight: 600; }
    tr:nth-child(2n) { background: var(--subtle); }
    img { max-width: 100%; }
    del { color: var(--muted); }
    .footnotes { font-size: 12px; color: var(--muted); border-top: 1px solid var(--border); }
    """
}

/// The rendered Markdown of a document, read-only, in place of its editor.
struct MarkdownPreviewView: NSViewRepresentable {
    let document: EditorDocument
    let focusRequest: Int
    let onOpenFile: (URL) -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> MarkdownPreviewContainerView {
        MarkdownPreviewContainerView()
    }

    func updateNSView(_ container: MarkdownPreviewContainerView, context: Context) {
        container.onOpenFile = onOpenFile
        container.onEscape = onEscape
        // Read so SwiftUI updates the preview when the file is reloaded from disk.
        _ = document.textRevision
        container.show(markdown: document.controller.text, baseURL: document.url?.deletingLastPathComponent())
        container.handleFocusRequest(focusRequest)
    }
}

final class MarkdownPreviewContainerView: NSView, WKNavigationDelegate {
    var onOpenFile: ((URL) -> Void)?
    var onEscape: (() -> Void)?
    private let webView: WKWebView
    private var shownMarkdown: String?
    private var shownBaseURL: URL?
    private var lastFocusRequest: Int?

    override init(frame frameRect: NSRect) {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: frameRect)

        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]
        // No white flash before the page draws in dark mode.
        webView.underPageBackgroundColor = .textBackgroundColor
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        addSubview(webView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func show(markdown: String, baseURL: URL?) {
        guard markdown != shownMarkdown || baseURL != shownBaseURL else { return }
        shownMarkdown = markdown
        shownBaseURL = baseURL
        // The file's folder as base URL, so relative images and links resolve.
        webView.loadHTMLString(MarkdownRenderer.page(for: markdown), baseURL: baseURL)
    }

    func handleFocusRequest(_ request: Int) {
        defer { lastFocusRequest = request }
        guard let lastFocusRequest, lastFocusRequest != request else { return }
        focusPreview()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusPreview()
    }

    private func focusPreview() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window else { return }
            window.makeFirstResponder(webView)
        }
    }

    /// Esc goes back to the terminal, like in the editor. The web view passes keys
    /// it does not use on to its superview.
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    /// Links to other files open in the editor, web links in the browser, and
    /// links to headings on the page scroll there.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if let current = webView.url, url.fragment != nil,
           url.absoluteString.hasPrefix(current.absoluteString.components(separatedBy: "#")[0] + "#") {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        if url.isFileURL {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue,
               UTType(filenameExtension: url.pathExtension)?.conforms(to: .text) ?? url.pathExtension.isEmpty {
                onOpenFile?(url)
            } else {
                NSWorkspace.shared.open(url)
            }
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
