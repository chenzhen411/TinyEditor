import AppKit

/// Isolated fixture layout for human/real-input validation. Never enabled in a normal launch.
enum UITestPreparation {
  static func prepare() {
    guard let folder = ProcessInfo.processInfo.environment["TINYEDITOR_UI_FIXTURES"],
      ProcessInfo.processInfo.environment["TINYEDITOR_DATA_DIR"] != nil
    else { return }
    let root = URL(fileURLWithPath: folder)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("source.txt")
    let preview = root.appendingPathComponent("preview.md")
    try? Data("原生编辑验证\n中文、Unicode 😀\n第三行\n".utf8).write(to: source)
    try? Data(
      "# TinyEditor\n\n轻量、原生、离线。\n\n**Markdown 原文复制** 与 [本地文档](source.txt)。\n\n- [x] 原生编辑\n- [x] 离线预览\n\n```mermaid\ngraph LR\n A[原文] --> B[预览]\n```\n\n公式：$E=mc^2$\n"
        .utf8
    ).write(to: preview)
    let app = AppController.shared
    for owner in Array(app.windows) {
      for doc in Array(owner.documents) where !doc.isDirty { owner.remove(doc) }
    }
    guard let leftDoc = try? EditorDocument.open(source),
      let rightDoc = try? EditorDocument.open(preview)
    else { return }
    let left = app.newWindow(with: leftDoc)
    let right = app.newWindow(with: rightDoc)
    let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let width = max(520, (screen.width - 60) / 2)
    let height = min(660, screen.height - 80)
    left.window?.setFrame(
      NSRect(x: screen.minX + 20, y: screen.minY + 40, width: width, height: height), display: true)
    right.window?.setFrame(
      NSRect(x: screen.minX + 40 + width, y: screen.minY + 40, width: width, height: height),
      display: true)
    left.window?.makeKeyAndOrderFront(nil)
    left.window?.contentView?.layoutSubtreeIfNeeded()
    right.window?.contentView?.layoutSubtreeIfNeeded()
    Settings.shared.touch(source)
    Settings.shared.touch(preview)
    let sourceFrame = left.window!.frame
    let targetFrame = right.window!.frame
    let scale = left.window!.backingScaleFactor
    // CUA uses screenshot pixels from the source window's top-left.
    func point(_ owner: EditorWindowController, _ view: NSView, _ local: NSPoint) -> [Double] {
      let global = owner.window!.convertPoint(toScreen: view.convert(local, to: nil))
      return [
        Double((global.x - sourceFrame.minX) * scale),
        Double((sourceFrame.maxY - global.y) * scale),
      ]
    }
    let cells = left.tabStrip.cells
    left.tabStrip.layoutSubtreeIfNeeded()
    let data: [String: Any] = [
      "sourceFrame": NSStringFromRect(sourceFrame), "targetFrame": NSStringFromRect(targetFrame),
      "scale": scale,
      "dragFrom": point(left, cells[0], NSPoint(x: cells[0].bounds.midX, y: cells[0].bounds.midY)),
      "dropBody": point(right, right.host, NSPoint(x: 150, y: 150)),
      "dropToolbar": point(
        right, right.window!.contentView!,
        NSPoint(x: 150, y: right.window!.contentView!.bounds.height - 20)),
      "dropStatus": point(right, right.status, NSPoint(x: 150, y: 12)),
    ]
    if let json = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted) {
      try? json.write(to: root.appendingPathComponent("ui-layout.json"))
    }
  }
}
