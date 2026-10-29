import AppKit
import WebKit

final class PreviewWebView: WKWebView {
  weak var pane: PreviewPane?
  @objc func copy(_ sender: Any?) {
    evaluateJavaScript("window.copySelection && window.copySelection()", completionHandler: nil)
  }
  override func selectAll(_ sender: Any?) {
    evaluateJavaScript("window.selectSourceAll && window.selectSourceAll()", completionHandler: nil)
  }
  override func keyDown(with event: NSEvent) {
    if event.modifierFlags.contains(.command),
      event.charactersIgnoringModifiers?.lowercased() == "c"
    {
      if event.modifierFlags.contains(.shift) {
        if let doc = pane?.document { pureCopy(doc.text) }
      } else {
        copy(nil)
      }
      return
    }
    super.keyDown(with: event)
  }
}
final class LocalResourceHandler: NSObject, WKURLSchemeHandler {
  weak var document: EditorDocument?
  func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
    guard let url = urlSchemeTask.request.url,
      let base = document?.url?.deletingLastPathComponent(), url.host == "image",
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let relative = components.queryItems?.first(where: { $0.name == "path" })?.value,
      let local = safeLocalURL(relative, base: base)
    else {
      urlSchemeTask.didFailWithError(TinyError("资源路径无效"))
      return
    }
    do {
      let attrs = try FileManager.default.attributesOfItem(atPath: local.path)
      guard (attrs[.size] as? NSNumber)?.intValue ?? Int.max < 20_000_000 else {
        throw TinyError("图片过大")
      }
      // SVG can reference external/local subresources; only decode raster images here.
      guard
        ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"].contains(
          local.pathExtension.lowercased())
      else { throw TinyError("仅允许文档目录内的位图图片") }
      let data = try Data(contentsOf: local)
      let mime =
        [
          "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp",
          "heic": "image/heic", "tiff": "image/tiff", "bmp": "image/bmp",
        ][local.pathExtension.lowercased()] ?? "image/png"
      urlSchemeTask.didReceive(
        URLResponse(
          url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
      urlSchemeTask.didReceive(data)
      urlSchemeTask.didFinish()
    } catch { urlSchemeTask.didFailWithError(error) }
  }
  func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
func safeLocalURL(_ href: String, base: URL) -> URL? {
  guard !href.hasPrefix("/"), !href.hasPrefix("~"), !href.hasPrefix("\\"),
    let parsed = URL(string: href), parsed.scheme == nil, parsed.host == nil
  else { return nil }
  let relative = parsed.path.removingPercentEncoding ?? parsed.path
  let root = canonical(base)
  let result = canonical(root.appendingPathComponent(relative))
  guard result.path.hasPrefix(root.path + "/") else { return nil }
  return result
}
final class PreviewPane: NSView, WKScriptMessageHandler, WKNavigationDelegate {
  unowned let document: EditorDocument
  let web: PreviewWebView
  let resources = LocalResourceHandler()
  var loaded = false
  var revision = 0
  var lastDark: Bool?
  var renderedText: String?
  var readyRevision = 0
  var renderError: String?
  init(document: EditorDocument) {
    self.document = document
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    config.preferences.javaScriptCanOpenWindowsAutomatically = false
    config.setURLSchemeHandler(resources, forURLScheme: "tiny-resource")
    web = PreviewWebView(frame: .zero, configuration: config)
    super.init(frame: .zero)
    resources.document = document
    web.pane = self
    web.navigationDelegate = self
    web.allowsBackForwardNavigationGestures = false
    web.configuration.userContentController.add(WeakScriptHandler(self), name: "tiny")
    addSubview(web)
    web.underPageBackgroundColor = .clear
    let resourceRoot =
      Bundle.main.resourceURL?.appendingPathComponent("Preview")
      ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(
        "Resources/Preview")
    web.loadFileURL(
      resourceRoot.appendingPathComponent("index.html"), allowingReadAccessTo: resourceRoot)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layout() {
    super.layout()
    web.frame = bounds
  }
  func invalidate() {
    renderedText = nil
    if document.previewing { render() }
  }
  func dark() -> Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
  func preferencesChanged() {
    guard loaded else { return }
    let isDark = dark()
    if lastDark == isDark {
      web.evaluateJavaScript(
        "window.applyTheme(\(isDark),\(Settings.shared.fontSize)); void 0", completionHandler: nil)
    } else {
      rememberScroll { [weak self] in self?.invalidate() }
    }
  }
  func render() {
    guard loaded else { return }
    let text = document.text
    guard renderedText != text else { return }
    renderedText = text
    lastDark = dark()
    revision += 1
    let args: [Any] = [
      text, revision, dark(), Double(Settings.shared.fontSize), document.previewScroll,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: args),
      let json = String(data: data, encoding: .utf8)
    else { return }
    web.evaluateJavaScript("window.renderDocument(...\(json)); void 0") { [weak self] _, error in
      if let error {
        self?.renderError = error.localizedDescription
        NSLog("Preview: %@", error.localizedDescription)
      }
    }
  }
  func rememberScroll(_ completion: @escaping () -> Void) {
    web.evaluateJavaScript("window.scrollY") { [weak self] result, _ in
      if let value = result as? Double { self?.document.previewScroll = value }
      completion()
    }
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    loaded = true
    render()
  }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    loaded = false
    renderedText = nil
    web.reload()
  }
  func webView(
    _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    if action.navigationType == .linkActivated {
      if let url = action.request.url { openLink(url.absoluteString) }
      decisionHandler(.cancel)
    } else if action.request.url?.isFileURL == true {
      decisionHandler(.allow)
    } else {
      decisionHandler(.cancel)
    }
  }
  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any],
      let kind = body["kind"] as? String
    else { return }
    switch kind {
    case "copy":
      guard let start = body["start"] as? Int, let end = body["end"] as? Int,
        body["revision"] as? Int == revision, let renderedText
      else { return }
      let raw = renderedText as NSString
      guard start >= 0, end >= start, end <= raw.length else { return }
      pureCopy(raw.substring(with: NSRange(location: start, length: end - start)))
    case "contextMenu":
      guard body["revision"] as? Int == revision else { return }
      let menu = NSMenu()
      menu.autoenablesItems = false
      let item = NSMenuItem(
        title: "复制 Markdown", action: #selector(copyContext(_:)), keyEquivalent: "")
      item.target = self
      let start = body["start"] as? Int ?? -1
      let end = body["end"] as? Int ?? -1
      item.representedObject = [start, end, revision]
      item.isEnabled = start >= 0 && end >= start
      menu.addItem(item)
      let all = NSMenuItem(
        title: "复制整个文档 Markdown／源码", action: #selector(copyAllContext(_:)), keyEquivalent: "")
      all.target = self
      menu.addItem(all)
      let select = NSMenuItem(
        title: "全选", action: #selector(PreviewWebView.selectAll(_:)), keyEquivalent: "")
      select.target = web
      menu.addItem(select)
      let point = web.convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
      menu.popUp(positioning: nil, at: point, in: web)
    case "link": if let href = body["href"] as? String { openLink(href) }
    case "image":
      guard let href = body["href"] as? String, let id = body["id"] as? String,
        let rev = body["revision"] as? Int, rev == revision
      else { return }
      var result: String?
      if let url = URL(string: href), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
        if Settings.shared.remoteImages { result = href }
      } else if let base = document.url?.deletingLastPathComponent(),
        safeLocalURL(href, base: base) != nil
      {
        var parts = URLComponents()
        parts.scheme = "tiny-resource"
        parts.host = "image"
        parts.queryItems = [URLQueryItem(name: "path", value: href)]
        result = parts.url?.absoluteString
      }
      let args: [Any] = [id, result as Any? ?? NSNull(), rev]
      if let data = try? JSONSerialization.data(withJSONObject: args),
        let json = String(data: data, encoding: .utf8)
      {
        web.evaluateJavaScript("window.setLocalImage(...\(json))", completionHandler: nil)
      }
    case "ready":
      readyRevision = body["revision"] as? Int ?? 0
      document.changed()
    case "error": renderError = body["message"] as? String
    default: break
    }
  }
  @objc private func copyContext(_ sender: NSMenuItem) {
    guard let values = sender.representedObject as? [Int], values.count == 3, values[2] == revision,
      let renderedText
    else { return }
    let raw = renderedText as NSString
    let start = values[0]
    let end = values[1]
    guard start >= 0, end >= start, end <= raw.length else { return }
    pureCopy(raw.substring(with: NSRange(location: start, length: end - start)))
  }
  @objc private func copyAllContext(_ sender: NSMenuItem) { pureCopy(document.text) }
  private func openLink(_ href: String) {
    if let url = URL(string: href),
      ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "")
    {
      NSWorkspace.shared.open(url)
      return
    }
    guard let base = document.url?.deletingLastPathComponent(),
      let url = safeLocalURL(href, base: base)
    else {
      showError(TinyError("相对链接需要已保存的文档，且目标必须位于该文档目录内。"), window: window)
      return
    }
    AppController.shared.open(urls: [url], in: AppController.shared.owner(of: document))
  }
}
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
  weak var target: WKScriptMessageHandler?
  init(_ target: WKScriptMessageHandler) { self.target = target }
  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) { target?.userContentController(userContentController, didReceive: message) }
}
