import AppKit
import Darwin
import WebKit

/// Opt-in validation only. Refuses to run against the user's normal data directory.
enum IntegrationCheck {
  @MainActor static func run(report: URL) {
    guard ProcessInfo.processInfo.environment["TINYEDITOR_DATA_DIR"] != nil else { return }
    Task { @MainActor in
      let runner = IntegrationRunner(report: report)
      await runner.run()
    }
  }
}
@MainActor final class IntegrationRunner {
  let report: URL
  var results: [[String: Any]] = []
  var performance: [[String: Any]] = []
  let root: URL
  init(report: URL) {
    self.report = report
    root = Settings.shared.root.appendingPathComponent("Fixtures")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }
  func check(_ name: String, _ pass: Bool, _ detail: String = "") {
    results.append(["name": name, "passed": pass, "detail": detail])
    persist()
  }
  func persist() {
    let data: [String: Any] = [
      "date": ISO8601DateFormatter().string(from: Date()),
      "os": ProcessInfo.processInfo.operatingSystemVersionString, "architecture": "arm64",
      "pid": ProcessInfo.processInfo.processIdentifier, "results": results,
      "performance": performance, "status": "running",
    ]
    if let bytes = try? JSONSerialization.data(
      withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
    {
      try? bytes.write(to: report, options: .atomic)
    }
  }
  func pause(_ seconds: Double = 0.1) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
  }
  func js(_ pane: PreviewPane, _ source: String) async -> Any? {
    await withCheckedContinuation { continuation in
      pane.web.evaluateJavaScript(source) { value, error in
        if let error { NSLog("Validation JS: %@", error.localizedDescription) }
        continuation.resume(returning: value)
      }
    }
  }
  func residentMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
      MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }
    return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
  }
  func edit(_ doc: EditorDocument, _ text: String, at range: NSRange? = nil) {
    let pane = doc.sourcePane()
    doc.undo.beginUndoGrouping()
    pane.textView.insertText(
      text, replacementRange: range ?? NSRange(location: pane.displayStorage.length, length: 0))
    doc.undo.endUndoGrouping()
  }
  func run() async {
    let app = AppController.shared
    do {
      for format in [Format.plain, .markdown, .json, .yaml, .shell, .sql] {
        let suffix: [Format: String] = [
          .plain: "txt", .markdown: "md", .json: "json", .yaml: "yaml", .shell: "sh", .sql: "sql",
        ]
        let url = root.appendingPathComponent("native.\(suffix[format]!)")
        let original: String
        switch format {
        case .shell: original = "#!/bin/sh\r\nprintf '%s\\n' \"中文 😀\"\r\n"
        case .sql: original = "-- 中文 😀\r\nSELECT id FROM demo WHERE active = true;\r\n"
        default: original = "first\r\n中文 😀\r\n"
        }
        try Data(original.utf8).write(to: url, options: .atomic)
        let doc = try EditorDocument.open(url)
        doc.previewing = false
        let owner = app.newWindow(with: doc)
        await pause()
        if format == .shell || format == .sql {
          let editor = doc.sourcePane()
          editor.highlight()
          let token = (original as NSString).range(of: format == .shell ? "printf" : "SELECT")
          let color = editor.layoutManager.temporaryAttribute(.foregroundColor, atCharacterIndex: token.location, effectiveRange: nil) as? NSColor
          check("native-\(format.rawValue)-highlight", color == .systemBlue && doc.text == original && !doc.isDirty && !doc.undo.canUndo)
          check("native-\(format.rawValue)-format-selector", owner.formatPopup.itemTitles.contains(format.title) && !doc.previewing && owner.modeSwitch.isHidden)
        }
        edit(doc, "added")
        doc.refreshDirty()
        check("native-\(format.rawValue)-edit", doc.text == original + "added" && doc.isDirty)
        doc.undo.undo()
        doc.refreshDirty()
        check("native-\(format.rawValue)-undo-clean", doc.text == original && !doc.isDirty)
        doc.undo.redo()
        doc.refreshDirty()
        check("native-\(format.rawValue)-redo", doc.text == original + "added" && doc.isDirty)
        try doc.write(to: url)
        let reopened = try EditorDocument.open(url)
        check(
          "native-\(format.rawValue)-save-reopen",
          reopened.text == doc.text && reopened.resolvedFormat == format)
        let lineCount = doc.lines.starts.count
        check(
          "native-\(format.rawValue)-gutter", !doc.sourcePane().gutter.isHidden && lineCount == 3)
        owner.remove(doc)
      }
      let composition = EditorDocument(text: "原文")
      let compositionWindow = app.newWindow(with: composition)
      let input = composition.sourcePane().textView
      input.setSelectedRange(NSRange(location: 0, length: 0))
      input.setMarkedText(
        "zhong", selectedRange: NSRange(location: 5, length: 0),
        replacementRange: NSRange(location: NSNotFound, length: 0))
      check("native-marked-text-start", input.hasMarkedText())
      input.insertText("中文😀", replacementRange: NSRange(location: NSNotFound, length: 0))
      check("native-marked-text-commit", !input.hasMarkedText() && composition.text == "中文😀原文")
      composition.resolveRecovery()
      composition.undo.removeAllActions()
      compositionWindow.remove(composition)
      let doc = EditorDocument(text: "original\n")
      let first = app.newWindow(with: doc)
      edit(doc, "unsaved")
      doc.refreshDirty()
      let manager = doc.undo
      let second = app.newWindow(with: EditorDocument(text: "target"))
      first.toggleSidebar()
      let width = first.sidebarWidth
      app.move(doc, from: first, to: second, index: 1)
      check(
        "tab-transfer-identity",
        second.documents.last === doc && doc.undo === manager && doc.isDirty
          && doc.text == "original\nunsaved")
      doc.undo.undo()
      check("tab-transfer-undo", doc.text == "original\n")
      doc.undo.redo()
      second.toggleSidebar()
      second.sidebarWidth = 250
      second.activate(second.documents[0])
      second.activate(doc)
      check(
        "sidebar-window-state", second.sidebarVisible && second.sidebarWidth == 250 && width >= 170)
      let cells = second.tabStrip.cells
      second.tabStrip.layoutSubtreeIfNeeded()
      check("second-tab-hit", cells.count == 2 && cells[1].frame.minX >= cells[0].frame.maxX)
      // Exercise every source/target tab-count combination by moving stable document instances.
      for sourceCount in [1, 2] {
        for targetCount in [1, 2] {
          let moving = EditorDocument(text: "move \(sourceCount) \(targetCount)")
          let s = app.newWindow(with: moving)
          if sourceCount == 2 { s.add(EditorDocument()) }
          let t = app.newWindow()
          if targetCount == 2 { t.add(EditorDocument()) }
          edit(moving, "!")
          let text = moving.text
          let undo = moving.undo
          app.move(moving, from: s, to: t, index: targetCount)
          check(
            "move-\(sourceCount)-to-\(targetCount)",
            t.documents.contains(where: { $0 === moving }) && moving.text == text
              && moving.undo === undo)
          moving.undo.undo()
          check("move-\(sourceCount)-to-\(targetCount)-undo", !moving.text.hasSuffix("!"))
          for d in Array(t.documents) {
            d.resolveRecovery()
            t.remove(d)
          }
          for d in Array(s.documents) { s.remove(d) }
        }
      }
      doc.resolveRecovery()
      for d in Array(second.documents) { second.remove(d) }
      await interactionRegressions()
      let fixture =
        "# 验证\r\n\r\n普通原文\r\n\r\n**粗体** 与 [链接](https://example.com) 及 &amp; 和 \\*转义\\*\r\n\r\n- 列表\r\n- [x] 任务\r\n\r\n> 引用\r\n\r\n| A | B |\r\n|---|---|\r\n| 一 | 二 |\r\n\r\n```json\r\n{\"key\": true}\r\n```\r\n\r\n```mermaid\r\ngraph TD\r\n A[开始] --> B[结束]\r\n```\r\n\r\n行内 $x^2$\r\n\r\n$$\r\n\\frac{a}{b}\r\n$$\r\n\r\n<div>HTML <em>斜体</em></div>\r\n\r\n<script>window.UNSAFE=1</script>\r\n<img src=\"https://example.com/no.png\" onerror=\"window.UNSAFE=1\">\r\n"
      let mdURL = root.appendingPathComponent("preview.md")
      try Data(fixture.utf8).write(to: mdURL)
      let mdDoc = try EditorDocument.open(mdURL)
      let mdWindow = app.newWindow(with: mdDoc)
      let pane = mdDoc.previewPane()
      for _ in 0..<300 {
        if pane.readyRevision > 0 || pane.renderError != nil { break }
        await pause(0.05)
      }
      check("markdown-default-preview", mdDoc.previewing && mdDoc.editor == nil)
      check("offline-preview-ready", pane.readyRevision > 0, pane.renderError ?? "")
      let renderState =
        await js(
          pane,
          "JSON.stringify({mermaid:document.querySelectorAll('.mermaid svg').length,math:document.querySelectorAll('.katex').length,table:document.querySelectorAll('table').length,unsafe:!!window.UNSAFE,scripts:document.querySelectorAll('#document script').length,remote:[...document.querySelectorAll('#document img')].filter(x=>/^https?:/.test(x.src)).length,errors:[...document.querySelectorAll('.render-error')].map(x=>x.textContent).join(' / '),svgLabels:document.querySelector('.mermaid svg')?.textContent.includes('开始'),mathLayout:document.querySelectorAll('.katex [style]').length,highlight:document.querySelectorAll('.hljs-attr').length})"
        ) as? String ?? "{}"
      if let data = renderState.data(using: .utf8),
        let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      {
        check(
          "mermaid-offline", state["mermaid"] as? Int == 1 && state["svgLabels"] as? Bool == true,
          renderState)
        check("math-offline", state["math"] as? Int == 2 && (state["mathLayout"] as? Int ?? 0) > 0)
        check(
          "table-and-code-highlight",
          state["table"] as? Int == 1 && (state["highlight"] as? Int ?? 0) > 0)
        check(
          "html-sanitized-and-remote-disabled",
          state["unsafe"] as? Bool == false && state["scripts"] as? Int == 0
            && state["remote"] as? Int == 0)
      }
      for selector in [
        "strong", "a", "li", "blockquote", "pre", "table", ".mermaid", ".math", ".math-unit",
        "section em",
      ] {
        let literal = String(
          data: try JSONSerialization.data(withJSONObject: [selector]), encoding: .utf8)!
        let expected =
          await js(
            pane,
            "(()=>{const e=document.querySelector((\(literal))[0]);if(!e)return null;const r=document.createRange();r.selectNodeContents(e);const s=getSelection();s.removeAllRanges();s.addRange(r);selectedAll=false;const unit=nearest(e);window.copySelection();return unit?source.slice(+unit.dataset.sourceStart,+unit.dataset.sourceEnd):null})()"
          ) as? String
        await pause(0.05)
        check(
          "preview-copy-\(selector)",
          expected != nil && NSPasteboard.general.string(forType: .string) == expected
            && NSPasteboardboardTypesPlain())
      }
      _ = await js(pane, "window.selectSourceAll();window.copySelection()")
      await pause()
      check(
        "preview-copy-all-crlf",
        NSPasteboard.general.string(forType: .string) == fixture && NSPasteboardboardTypesPlain())
      _ = await js(
        pane,
        "(()=>{const e=[...document.querySelectorAll('p')].find(x=>x.textContent==='普通原文');const r=document.createRange();r.setStart(e.firstChild,1);r.setEnd(e.firstChild,3);getSelection().removeAllRanges();getSelection().addRange(r);selectedAll=false;window.copySelection()})()"
      )
      await pause()
      check("preview-exact-literal-copy", NSPasteboard.general.string(forType: .string) == "通原")
      mdDoc.previewing = false
      mdWindow.activate(mdDoc)
      edit(mdDoc, "\r\n新编辑")
      mdDoc.previewing = true
      mdWindow.activate(mdDoc)
      pane.invalidate()
      for _ in 0..<100 {
        if pane.readyRevision == pane.revision { break }
        await pause(0.05)
      }
      check("markdown-memory-latest", pane.renderedText == fixture + "\r\n新编辑" && mdDoc.isDirty)
      pureCopy(mdDoc.text)
      check(
        "copy-whole-source-plain-only", NSPasteboardboardTypesPlain(),
        "types: \(NSPasteboard.general.types ?? [])")
      mdDoc.resolveRecovery()
      mdWindow.remove(mdDoc)
      // File version watcher: atomic replacement and dirty conflict protection.
      let external = root.appendingPathComponent("external.txt")
      try Data("base".utf8).write(to: external)
      let externalDoc = try EditorDocument.open(external)
      try Data("reload".utf8).write(to: external, options: .atomic)
      externalDoc.checkExternal()
      check("external-clean-reload", externalDoc.text == "reload" && !externalDoc.isDirty)
      externalDoc.storage.replaceCharacters(in: NSRange(location: 0, length: 6), with: "local")
      try Data("remote".utf8).write(to: external, options: .atomic)
      externalDoc.checkExternal()
      var refused = false
      do { try externalDoc.write(to: external) } catch { refused = true }
      let externalDisk = try String(contentsOf: external)
      check(
        "external-dirty-conflict",
        externalDoc.text == "local" && externalDoc.conflict && refused && externalDisk == "remote")
      externalDoc.resolveRecovery()
      // Actual native layout timings, from disk read through visible display, then editing and undo.
      if ProcessInfo.processInfo.environment["TINYEDITOR_SKIP_PERFORMANCE"] == nil {
        for mb in [1, 10, 30] { await benchmark(mb: mb, single: false) }
        await benchmark(mb: 10, single: true)
      }
      // Paged editor: Unicode, page navigation, canonical full copy and undo after reprojecting.
      let giant =
        String(repeating: "a", count: 150_000) + "😀中文" + String(repeating: "b", count: 150_000)
      let paged = EditorDocument(text: giant)
      let pagedWindow = app.newWindow(with: paged)
      let pagedPane = paged.sourcePane()
      pagedPane.refreshProjection(around: 150_000)
      let local = 150_000 - pagedPane.sliceStart
      edit(paged, "🙂", at: NSRange(location: local, length: 2))
      let replaced = paged.text
      pagedPane.nextPage()
      paged.undo.undo()
      check("paged-unicode-cross-page-undo", paged.text == giant)
      paged.undo.redo()
      check("paged-unicode-redo", paged.text == replaced)
      pagedPane.textView.selectAll(nil)
      pagedPane.textView.copy(nil)
      check(
        "paged-full-copy",
        NSPasteboard.general.string(forType: .string) == paged.text && NSPasteboardboardTypesPlain()
      )
      paged.resolveRecovery()
      pagedWindow.remove(paged)
      // Authenticated IPC real secondary executable, no second NSApplication created.
      let countBefore = app.windows.count
      let tabsBefore = app.windows.flatMap(\.documents).count
      var children: [Process] = []
      for _ in 0..<8 {
        let p = Process()
        p.executableURL = Bundle.main.executableURL
        p.arguments = ["--new-tab"]
        try p.run()
        children.append(p)
      }
      while children.contains(where: { $0.isRunning }) { await pause(0.02) }
      await pause()
      check(
        "single-instance-concurrent-handoff",
        children.allSatisfy { $0.terminationStatus == 0 } && app.windows.count == countBefore
          && app.windows.flatMap(\.documents).count == tabsBefore + 8)
      let copy = root.appendingPathComponent("AnotherLocation/TinyEditor.app")
      try FileManager.default.createDirectory(
        at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.copyItem(at: Bundle.main.bundleURL, to: copy)
      let p = Process()
      p.executableURL = copy.appendingPathComponent("Contents/MacOS/TinyEditor")
      p.arguments = ["--new-window"]
      try p.run()
      while p.isRunning { await pause(0.02) }
      await pause()
      check(
        "single-instance-different-install-path",
        p.terminationStatus == 0 && app.windows.count == countBefore + 1)

    } catch { check("integration-error", false, error.localizedDescription) }
    persist()
    if let data = try? Data(contentsOf: report),
      var all = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    {
      all["status"] = "complete"
      all["passed"] = results.allSatisfy { $0["passed"] as? Bool == true }
      if let encoded = try? JSONSerialization.data(
        withJSONObject: all, options: [.prettyPrinted, .sortedKeys])
      {
        try? encoded.write(to: report, options: .atomic)
      }
    }
    for doc in app.windows.flatMap(\.documents) { doc.resolveRecovery() }
    NSApp.terminate(nil)
  }
  func NSPasteboardboardTypesPlain() -> Bool {
    guard let types = NSPasteboard.general.types else { return false }
    return !types.isEmpty
      && types.allSatisfy { $0 == .string || $0.rawValue == "NSStringPboardType" }
  }
  func interactionRegressions() async {
    let app = AppController.shared
    let moving = EditorDocument(text: "drag identity 😀")
    let source = app.newWindow(with: moving)
    source.window?.contentView?.layoutSubtreeIfNeeded()
    source.tabStrip.layoutSubtreeIfNeeded()
    check(
      "drop-region-registered-before-session",
      source.dropOverlay?.registeredDraggedTypes.contains(tabDragType) == true)
    weak var originalCell = source.tabStrip.cells.first
    guard !source.tabStrip.cells.isEmpty else {
      check("drag-source-fixture", false)
      return
    }
    _ = DragCoordinator.shared.begin(moving, source: source, cell: source.tabStrip.cells[0])
    source.installDropOverlay()
    source.dropOverlay?.hovering = true
    source.tabStrip.rebuild()
    source.tabStrip.layoutSubtreeIfNeeded()
    await pause(0.05)
    check(
      "drag-source-retained-after-strip-rebuild",
      originalCell != nil && DragCoordinator.shared.sourceCell === originalCell
    )
    if let frame = source.window?.contentView?.superview,
      let close = source.tabStrip.cells.first?.closeButton
    {
      let point = close.convert(NSPoint(x: close.bounds.midX, y: close.bounds.midY), to: frame)
      let hit = frame.hitTest(point)
      check("drag-hint-does-not-block-close", hit === close || hit?.isDescendant(of: close) == true)
      let button = source.sidebarButton
      let p = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: frame)
      let toolbarHit = frame.hitTest(p)
      check(
        "drag-hint-does-not-block-toolbar",
        toolbarHit === button || toolbarHit?.isDescendant(of: button) == true)
    }
    source.sidebarButton.performClick(nil)
    check(
      "sidebar-native-button-opens",
      source.sidebarVisible && !source.sidebar.isHidden && source.sidebar.frame.width >= 170)
    let root = source.window!.contentView!
    func alignedDocumentHeader() -> Bool {
      let tabs = source.tabStrip.convert(source.tabStrip.bounds, to: root)
      let body = source.host.convert(source.host.bounds, to: root)
      let side = source.sidebar.convert(source.sidebar.bounds, to: root)
      return abs(tabs.minX - body.minX) < 1 && abs(tabs.width - body.width) < 1
        && abs(tabs.minY - body.maxY) < 1
        && (source.sidebarVisible
          ? (tabs.minX >= side.maxX && abs(tabs.maxY - side.maxY) < 1)
          : (abs(tabs.minX - root.bounds.minX) < 1 && abs(tabs.width - root.bounds.width) < 1))
    }
    source.window?.contentView?.layoutSubtreeIfNeeded()
    check("sidebar-tabs-align-with-document", alignedDocumentHeader())
    source.split.setPosition(300, ofDividerAt: 0)
    source.layoutContent()
    source.tabStrip.layoutSubtreeIfNeeded()
    check("sidebar-resize-moves-tabs-with-body", alignedDocumentHeader() && source.sidebarWidth >= 299)
    let extra = EditorDocument()
    source.add(extra)
    source.tabStrip.layoutSubtreeIfNeeded()
    let secondCell = source.tabStrip.cells[1]
    let tabPoint = secondCell.convert(NSPoint(x: secondCell.bounds.midX, y: secondCell.bounds.midY), to: nil)
    let converted = source.tabStrip.convert(tabPoint, from: nil)
    check("sidebar-offset-tab-drop-index", source.tabStrip.insertionIndex(at: converted) == 2)
    if let frame = source.window?.contentView?.superview {
      let p = secondCell.convert(NSPoint(x: secondCell.bounds.midX, y: secondCell.bounds.midY), to: frame)
      check("sidebar-offset-second-tab-hit", frame.hitTest(p) === secondCell)
    }
    source.remove(extra)
    source.sidebarButton.performClick(nil)
    check("sidebar-native-button-closes", !source.sidebarVisible && source.sidebar.isHidden)
    check("collapsed-tabs-align-with-document", alignedDocumentHeader())
    check("collapsed-sidebar-has-no-divider-offset", source.sidebar.frame.width < 1)
    check("collapsed-sidebar-divider-transparent", source.split.dividerColor.alphaComponent == 0)
    let blank = EditorDocument()
    source.add(blank)
    source.tabStrip.layoutSubtreeIfNeeded()
    check("new-active-tab-close-visible", source.tabStrip.cells.last?.closeButton.isHidden == false)
    source.activate(moving)
    check(
      "tab-switch-refreshes-close-target",
      source.tabStrip.cells.first?.closeButton.isHidden == false
        && source.tabStrip.cells.last?.closeButton.isHidden == true)
    source.activate(blank)
    source.tabStrip.cells.last?.closeButton.performClick(nil)
    check(
      "close-native-button-removes-only-tab",
      source.documents.count == 1 && source.active === moving)
    let target = app.newWindow()
    app.move(moving, from: source, to: target, index: 1)
    check(
      "drag-source-retained-after-source-window-closes",
      originalCell != nil && DragCoordinator.shared.sourceCell === originalCell)
    DragCoordinator.shared.finish(at: target.window!.frame.origin, operation: .move)
    check(
      "drag-end-releases-context",
      DragCoordinator.shared.token == nil && DragCoordinator.shared.sourceCell == nil)
    for doc in Array(target.documents) { target.remove(doc) }
  }
  func benchmark(mb: Int, single: Bool) async {
    do {
      let bytes = mb * 1_000_000
      let unit = single ? "abcdef0123456789 " : "0123456789 abcdef 中文 😀\n"
      let repeats = bytes / unit.utf8.count
      let text = String(repeating: unit, count: repeats)
      let url = root.appendingPathComponent("\(mb)MB-\(single ? "single":"lines").txt")
      try Data(text.utf8).write(to: url)
      let before = residentMB()
      let start = Date()
      let doc = try EditorDocument.open(url)
      let decoded = Date()
      let window = AppController.shared.newWindow(with: doc)
      window.window?.displayIfNeeded()
      let displayed = Date()
      await pause(0.1)
      let editStart = Date()
      edit(doc, "X", at: NSRange(location: 0, length: 0))
      window.window?.displayIfNeeded()
      let editEnd = Date()
      let undoAvailable = doc.undo.canUndo
      let editedPrefix = String(doc.text.prefix(25))
      let editedLength = doc.storage.length
      doc.undo.undo()
      let ok = doc.text == text
      performance.append([
        "name": "\(mb)MB-\(single ? "single":"multiline")", "bytes": text.utf8.count,
        "decodeAndModelMs": decoded.timeIntervalSince(start) * 1000,
        "openToDisplayMs": displayed.timeIntervalSince(start) * 1000,
        "editToDisplayMs": editEnd.timeIntervalSince(editStart) * 1000, "rssBeforeMB": before,
        "rssAfterMB": residentMB(), "undoPreserved": ok, "undoAvailable": undoAvailable,
        "editedPrefix": editedPrefix, "undoPrefix": String(doc.text.prefix(25)),
        "editedLength": editedLength, "undoLength": doc.storage.length,
      ])
      check("performance-\(mb)-\(single ? "single":"multiline")", ok)
      doc.resolveRecovery()
      doc.undo.removeAllActions()
      window.remove(doc)
      await pause(0.2)
    } catch { check("benchmark-error", false, error.localizedDescription) }
  }
}
