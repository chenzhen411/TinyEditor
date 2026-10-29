import AppKit

let tabDragType = NSPasteboard.PasteboardType("top.moriarty.TinyEditor.tab")

/// Owns the source view until AppKit has delivered the end-of-session callback. Rebuilding a
/// tab strip during a drop must not deallocate AppKit's draggingSource halfway through tracking.
final class DragCoordinator: NSObject {
  static let shared = DragCoordinator()
  private(set) var token: String?
  private(set) var document: EditorDocument?
  private(set) weak var source: EditorWindowController?
  private(set) var sourceCell: TabCell?
  private(set) var accepted = false
  var cancelled = false
  private var monitor: Any?

  func begin(_ doc: EditorDocument, source: EditorWindowController, cell: TabCell) -> String {
    reset()
    token = UUID().uuidString
    document = doc
    self.source = source
    sourceCell = cell
    accepted = false
    cancelled = false
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
      if event.keyCode == 53 { self?.cancelled = true }
      return event
    }
    dragLog("begin \(doc.name)")
    return token!
  }

  func valid(_ info: NSDraggingInfo) -> Bool {
    guard let token, let document, let source, let sourceCell,
      info.draggingSource as? TabCell === sourceCell,
      source.documents.contains(where: { $0 === document }) || accepted
    else { return false }
    return info.draggingPasteboard.string(forType: tabDragType) == token
  }

  func receive(_ info: NSDraggingInfo, in target: EditorWindowController) -> Bool {
    guard valid(info), let document, let source else { return false }
    let point = target.tabStrip.convert(info.draggingLocation, from: nil)
    let index =
      target.tabStrip.bounds.contains(point)
      ? target.tabStrip.insertionIndex(at: point) : target.documents.count
    // Set this before moving: closing the source window may synchronously end AppKit tracking.
    accepted = true
    hideHints()
    dragLog("perform \(document.name) -> \(target.active?.name ?? "?") index=\(index)")
    AppController.shared.move(document, from: source, to: target, index: index)
    UITestPreparation.snapshot(event: "drop-accepted")
    return true
  }

  func finish(at point: NSPoint, operation: NSDragOperation) {
    let event = NSApp.currentEvent
    let escapeKey = event.map { [.keyDown, .keyUp].contains($0.type) && $0.keyCode == 53 } ?? false
    let escape = cancelled || escapeKey
    let doc = document
    let original = source
    let wasAccepted = accepted
    dragLog("finish \(point) operation=\(operation.rawValue) accepted=\(accepted) escape=\(escape)")
    // Reset before any window/tab mutation. Hints are visual only even if AppKit aborts tracking.
    reset()
    if !wasAccepted && !escape && operation.isEmpty, let doc, let original,
      original.documents.contains(where: { $0 === doc }),
      !AppController.shared.windows.contains(where: { $0.window?.frame.contains(point) == true })
    {
      AppController.shared.detach(doc, from: original, point: point)
    }
    UITestPreparation.snapshot(event: escape ? "drag-cancelled" : "drag-ended")
  }

  func hideHints() { AppController.shared.windows.forEach { $0.dropOverlay?.hovering = false } }
  func reset() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    token = nil
    document = nil
    source = nil
    sourceCell = nil
    accepted = false
    cancelled = false
    hideHints()
  }
}

/// Forward authenticated private tab drops from native registered view regions to the window.
/// Mouse hit testing is independent of drag registration; the frame overlay always returns nil.
class TabDropView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    registerForDraggedTypes([tabDragType])
  }
  required init?(coder: NSCoder) { fatalError() }
  private var destination: EditorWindow? { window as? EditorWindow }
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    destination?.draggingEntered(sender) ?? []
  }
  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    destination?.draggingUpdated(sender) ?? []
  }
  override func draggingExited(_ sender: NSDraggingInfo?) { destination?.draggingExited(sender) }
  override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    destination?.prepareForDragOperation(sender) ?? false
  }
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    destination?.performDragOperation(sender) ?? false
  }
  override func concludeDragOperation(_ sender: NSDraggingInfo?) {
    destination?.concludeDragOperation(sender)
  }
}

/// The window receives titlebar/toolbar drops; registered content ancestors forward here too.
final class EditorWindow: NSWindow, NSDraggingDestination {
  weak var editorOwner: EditorWindowController?
  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    let valid = DragCoordinator.shared.valid(sender)
    dragLog(
      "candidate \(title) valid=\(valid) source=\(String(describing: sender.draggingSource)) types=\(sender.draggingPasteboard.types ?? [])"
    )
    if valid, let editorOwner {
      editorOwner.installDropOverlay()
      editorOwner.dropOverlay?.hovering = true
      dragLog(
        "entered \(editorOwner.active?.name ?? "?") zone=\(dropZone(sender.draggingLocation))")
    }
    return valid ? .move : []
  }
  func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    DragCoordinator.shared.valid(sender) ? .move : []
  }
  func draggingExited(_ sender: NSDraggingInfo?) { editorOwner?.dropOverlay?.hovering = false }
  func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    DragCoordinator.shared.valid(sender)
  }
  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard let editorOwner else { return false }
    dragLog("drop zone=\(dropZone(sender.draggingLocation))")
    return DragCoordinator.shared.receive(sender, in: editorOwner)
  }
  func concludeDragOperation(_ sender: NSDraggingInfo?) {
    editorOwner?.dropOverlay?.hovering = false
  }
  func draggingEnded(_ sender: NSDraggingInfo) { editorOwner?.dropOverlay?.hovering = false }
  override func sendEvent(_ event: NSEvent) {
    if event.type == .keyDown && event.keyCode == 53 { DragCoordinator.shared.cancelled = true }
    if event.type == .leftMouseDown {
      // Any new click after tracking is over must remain usable, even if AppKit skipped its end callback.
      if DragCoordinator.shared.token != nil { DragCoordinator.shared.reset() }
      if ProcessInfo.processInfo.environment["TINYEDITOR_UI_FIXTURES"] != nil {
        let view = contentView?.superview?.hitTest(event.locationInWindow)
        dragLog(
          "mouseDown \(title) at=\(event.locationInWindow) hit=\(String(describing: type(of: view)))"
        )
      }
    }
    super.sendEvent(event)
  }
  private func dropZone(_ point: NSPoint) -> String {
    guard let owner = editorOwner else { return "unknown" }
    if point.y > contentLayoutRect.maxY { return "toolbar" }
    if owner.tabStrip.bounds.contains(owner.tabStrip.convert(point, from: nil)) { return "tabs" }
    if owner.status.bounds.contains(owner.status.convert(point, from: nil)) { return "status" }
    if owner.sidebarVisible
      && owner.sidebar.bounds.contains(owner.sidebar.convert(point, from: nil))
    {
      return "sidebar"
    }
    return owner.active?.previewing == true ? "preview" : "editor"
  }
}

/// Native drop region plus visual hint. Stale drag state can never block ordinary controls.
final class DropOverlay: TabDropView {
  var hovering = false { didSet { needsDisplay = true } }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func draw(_ rect: NSRect) {
    guard hovering else { return }
    NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 8, yRadius: 8).fill()
    let value = "移到此窗口" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor,
    ]
    let size = value.size(withAttributes: attrs)
    value.draw(
      at: NSPoint(x: (bounds.width - size.width) / 2, y: bounds.height - 75), withAttributes: attrs)
  }
}

// NSWindow forwards destination messages to its delegate on supported AppKit versions.
// Implement both entry points so native titlebar and embedded content share the same receiver.
extension EditorWindowController: NSDraggingDestination {
  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    (window as? EditorWindow)?.draggingEntered(sender) ?? []
  }
  func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    (window as? EditorWindow)?.draggingUpdated(sender) ?? []
  }
  func draggingExited(_ sender: NSDraggingInfo?) {
    (window as? EditorWindow)?.draggingExited(sender)
  }
  func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    (window as? EditorWindow)?.prepareForDragOperation(sender) ?? false
  }
  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    (window as? EditorWindow)?.performDragOperation(sender) ?? false
  }
  func concludeDragOperation(_ sender: NSDraggingInfo?) {
    (window as? EditorWindow)?.concludeDragOperation(sender)
  }
}
