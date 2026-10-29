import AppKit

let tabDragType = NSPasteboard.PasteboardType("top.moriarty.TinyEditor.tab")
final class DragCoordinator: NSObject {
  static let shared = DragCoordinator()
  var token: String?
  var document: EditorDocument?
  weak var source: EditorWindowController?
  var accepted = false
  var cancelled = false
  var monitor: Any?
  func begin(_ doc: EditorDocument, source: EditorWindowController) -> String {
    dragLog("begin \(doc.name)")
    token = UUID().uuidString
    document = doc
    self.source = source
    accepted = false
    cancelled = false
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if event.keyCode == 53 { self?.cancelled = true }
      return event
    }
    AppController.shared.windows.forEach { $0.installDropOverlay() }
    return token!
  }
  func valid(_ info: NSDraggingInfo) -> Bool {
    guard let token, document != nil, info.draggingSource is TabCell else { return false }
    return info.draggingPasteboard.string(forType: tabDragType) == token
  }
  func finish(at point: NSPoint, operation: NSDragOperation) {
    dragLog(
      "finish \(point) operation=\(operation.rawValue) accepted=\(accepted) cancelled=\(cancelled)")
    defer {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
      token = nil
      document = nil
      source = nil
      AppController.shared.windows.forEach {
        $0.dropOverlay?.removeFromSuperview()
        $0.dropOverlay = nil
      }
    }
    let escape =
      cancelled || (NSApp.currentEvent?.keyCode == 53 && NSApp.currentEvent?.type == .keyDown)
    if !accepted && !escape && operation.isEmpty, let doc = document, let source,
      !source.window!.frame.contains(point)
    {
      AppController.shared.detach(doc, from: source, point: point)
    }
  }
}
final class DropOverlay: NSView {
  weak var owner: EditorWindowController?
  var hovering = false { didSet { needsDisplay = true } }
  init(owner: EditorWindowController, frame: NSRect) {
    self.owner = owner
    super.init(frame: frame)
    registerForDraggedTypes([tabDragType])
    autoresizingMask = [.width, .height]
  }
  required init?(coder: NSCoder) { fatalError() }
  override func hitTest(_ point: NSPoint) -> NSView? {
    DragCoordinator.shared.token == nil ? nil : super.hitTest(point)
  }
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    hovering = DragCoordinator.shared.valid(sender)
    if hovering { dragLog("entered \(owner?.active?.name ?? "?")") }
    return hovering ? .move : []
  }
  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    draggingEntered(sender)
  }
  override func draggingExited(_ sender: NSDraggingInfo?) { hovering = false }
  override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    DragCoordinator.shared.valid(sender)
  }
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard DragCoordinator.shared.valid(sender), let owner,
      let doc = DragCoordinator.shared.document, let source = DragCoordinator.shared.source
    else { return false }
    let point = owner.tabStrip.convert(sender.draggingLocation, from: nil)
    let index = owner.tabStrip.insertionIndex(at: point)
    dragLog("perform \(doc.name) -> \(owner.active?.name ?? "?") index=\(index)")
    AppController.shared.move(doc, from: source, to: owner, index: index)
    DragCoordinator.shared.accepted = true
    hovering = false
    return true
  }
  override func concludeDragOperation(_ sender: NSDraggingInfo?) { hovering = false }
  override func draw(_ rect: NSRect) {
    if hovering {
      let box = bounds.insetBy(dx: 4, dy: 4)
      NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
      NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
      let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor,
      ]
      let value = "移到此窗口" as NSString
      let size = value.size(withAttributes: attrs)
      value.draw(
        at: NSPoint(x: (bounds.width - size.width) / 2, y: bounds.height - 75),
        withAttributes: attrs)
    }
  }
}
final class TabCell: NSView, NSDraggingSource {
  weak var owner: EditorWindowController?
  let document: EditorDocument
  let title = NSTextField(labelWithString: "")
  let closeButton = NSButton()
  var tracking: NSTrackingArea?
  var mouseOrigin = NSPoint.zero
  var hovering = false
  init(document: EditorDocument, owner: EditorWindowController) {
    self.document = document
    self.owner = owner
    super.init(frame: .zero)
    title.font = .systemFont(ofSize: 12)
    title.alignment = .center
    title.lineBreakMode = .byTruncatingMiddle
    title.maximumNumberOfLines = 1
    title.isSelectable = false
    addSubview(title)
    closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭标签")
    closeButton.imageScaling = .scaleProportionallyDown
    closeButton.isBordered = false
    closeButton.target = self
    closeButton.action = #selector(closeTab)
    closeButton.toolTip = "关闭标签"
    closeButton.setAccessibilityLabel("关闭 \(document.name)")
    addSubview(closeButton)
    refresh()
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityLabel(document.name)
  }
  required init?(coder: NSCoder) { fatalError() }
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? {
    let hit = super.hitTest(point)
    return hit === closeButton ? hit : (hit == nil ? nil : self)
  }
  override func layout() {
    super.layout()
    closeButton.frame = NSRect(x: 5, y: 6, width: 16, height: 16)
    title.frame = NSRect(x: 24, y: 6, width: max(0, bounds.width - 48), height: 18)
  }
  func refresh() {
    title.stringValue = (document.isDirty ? "• " : "") + document.name
    toolTip = document.url?.path ?? document.name
    closeButton.isHidden = !hovering
    needsDisplay = true
  }
  override func draw(_ rect: NSRect) {
    (owner?.active === document
      ? NSColor.controlBackgroundColor : NSColor.windowBackgroundColor.withAlphaComponent(0.55))
      .setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).fill()
  }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(
      rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
    addTrackingArea(area)
    tracking = area
  }
  override func mouseEntered(with event: NSEvent) {
    hovering = true
    refresh()
  }
  override func mouseExited(with event: NSEvent) {
    hovering = false
    refresh()
  }
  override func mouseDown(with event: NSEvent) {
    mouseOrigin = convert(event.locationInWindow, from: nil)
    owner?.activate(document)
  }
  override func mouseDragged(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    guard hypot(point.x - mouseOrigin.x, point.y - mouseOrigin.y) > 4, let owner else { return }
    let token = DragCoordinator.shared.begin(document, source: owner)
    let item = NSPasteboardItem()
    item.setString(token, forType: tabDragType)
    let drag = NSDraggingItem(pasteboardWriter: item)
    let image = NSImage(size: bounds.size)
    image.lockFocus()
    NSColor.windowBackgroundColor.setFill()
    NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    document.name.draw(
      at: NSPoint(x: 24, y: 8),
      withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor])
    image.unlockFocus()
    drag.setDraggingFrame(bounds, contents: image)
    let session = beginDraggingSession(with: [drag], event: event, source: self)
    session.animatesToStartingPositionsOnCancelOrFail = false
  }
  func draggingSession(
    _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation { .move }
  func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
  func draggingSession(
    _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
  ) { DragCoordinator.shared.finish(at: screenPoint, operation: operation) }
  @objc func closeTab() { owner?.close(document) }
  override func menu(for event: NSEvent) -> NSMenu? {
    let menu = NSMenu()
    for (name, action) in [
      ("关闭", #selector(menuClose(_:))), ("保存", #selector(menuSave(_:))),
      ("另存为…", #selector(menuSaveAs(_:))), ("重命名…", #selector(menuRename(_:))),
      ("关闭其他", #selector(menuCloseOthers(_:))),
    ] {
      let item = NSMenuItem(title: name, action: action, keyEquivalent: "")
      item.target = self
      if name == "关闭其他" { item.isEnabled = (owner?.documents.count ?? 0) > 1 }
      menu.addItem(item)
    }
    menu.autoenablesItems = false
    return menu
  }
  @objc func menuClose(_ sender: Any?) { owner?.close(document) }
  @objc func menuSave(_ sender: Any?) {
    if let owner { AppController.shared.save(document, in: owner) { _ in } }
  }
  @objc func menuSaveAs(_ sender: Any?) {
    if let owner { AppController.shared.save(document, in: owner, asNew: true) { _ in } }
  }
  @objc func menuRename(_ sender: Any?) { owner?.rename(document) }
  @objc func menuCloseOthers(_ sender: Any?) { owner?.closeOthers(keeping: document) }
}
final class TabStrip: NSView {
  weak var owner: EditorWindowController?
  let scroll = NSScrollView(), content = NSView(), addButton = NSButton()
  var cells: [TabCell] = []
  init() {
    super.init(frame: .zero)
    scroll.documentView = content
    scroll.hasHorizontalScroller = false
    scroll.drawsBackground = false
    scroll.horizontalScrollElasticity = .allowed
    addSubview(scroll)
    addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "新建标签")
    addButton.isBordered = false
    addButton.target = self
    addButton.action = #selector(addTab)
    addButton.toolTip = "新建标签（⌘T）"
    addSubview(addButton)
  }
  required init?(coder: NSCoder) { fatalError() }
  override var isFlipped: Bool { true }
  func rebuild() {
    cells.forEach { $0.removeFromSuperview() }
    cells = (owner?.documents ?? []).map { TabCell(document: $0, owner: owner!) }
    cells.forEach { content.addSubview($0) }
    needsLayout = true
  }
  func refresh() { cells.forEach { $0.refresh() } }
  override func layout() {
    super.layout()
    scroll.frame = NSRect(x: 0, y: 0, width: max(0, bounds.width - 30), height: 28)
    addButton.frame = NSRect(x: bounds.width - 29, y: 2, width: 26, height: 24)
    let width = max(115, min(230, scroll.bounds.width / CGFloat(max(1, cells.count))))
    content.frame = NSRect(
      x: 0, y: 0, width: max(scroll.bounds.width, width * CGFloat(cells.count)), height: 28)
    for (i, cell) in cells.enumerated() {
      cell.frame = NSRect(x: CGFloat(i) * width, y: 0, width: width, height: 28)
    }
  }
  func insertionIndex(at point: NSPoint) -> Int {
    let converted = content.convert(point, from: self)
    for (i, cell) in cells.enumerated() { if converted.x < cell.frame.midX { return i } }
    return cells.count
  }
  func reveal(_ document: EditorDocument) {
    guard let index = cells.firstIndex(where: { $0.document === document }) else { return }
    content.scrollToVisible(cells[index].frame)
  }
  @objc func addTab() { owner?.add(EditorDocument()) }
}

final class EditorWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate,
  NSTableViewDataSource, NSTableViewDelegate, NSSplitViewDelegate
{
  var documents: [EditorDocument] = []
  var active: EditorDocument?
  let tabStrip = TabStrip(), split = NSSplitView(), sidebar = NSScrollView(),
    recentTable = NSTableView(), documentArea = NSView(), host = NSView(),
    status = NSVisualEffectView(), statusText = NSTextField(labelWithString: "")
  let sidebarButton = NSButton(), formatPopup = NSPopUpButton(), zoomMinus = NSButton(),
    zoomReset = NSButton(), zoomPlus = NSButton(),
    modeSwitch = NSSegmentedControl(
      labels: ["预览", "编辑"], trackingMode: .selectOne, target: nil, action: nil)
  var sidebarVisible = false, sidebarWidth: CGFloat = 220
  var dropOverlay: DropOverlay?
  var closingAll = false
  var conflictPrompted: Set<UUID> = []
  init(inheritSidebar: EditorWindowController? = nil) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.title = appName
    window.minSize = NSSize(width: 520, height: 360)
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.animationBehavior = .none
    window.titleVisibility = .visible
    window.toolbarStyle = .unifiedCompact
    if ProcessInfo.processInfo.environment["TINYEDITOR_DATA_DIR"] == nil {
      window.setFrameAutosaveName("TinyEditor.window")
    }
    window.isRestorable = false
    super.init(window: window)
    window.delegate = self
    window.center()
    if let inheritSidebar {
      sidebarVisible = inheritSidebar.sidebarVisible
      sidebarWidth = inheritSidebar.sidebarWidth
    }
    let root = LayoutView()
    root.owner = self
    window.contentView = root
    tabStrip.owner = self
    root.addSubview(tabStrip)
    root.addSubview(split)
    split.isVertical = true
    split.dividerStyle = .thin
    split.delegate = self
    split.addArrangedSubview(sidebar)
    split.addArrangedSubview(documentArea)
    sidebar.documentView = recentTable
    sidebar.hasVerticalScroller = true
    sidebar.autohidesScrollers = true
    sidebar.borderType = .noBorder
    sidebar.drawsBackground = false
    let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("recent"))
    col.title = "最近文件"
    recentTable.addTableColumn(col)
    recentTable.headerView = nil
    recentTable.rowHeight = 26
    recentTable.intercellSpacing = NSSize(width: 0, height: 1)
    recentTable.style = .sourceList
    recentTable.dataSource = self
    recentTable.delegate = self
    recentTable.target = self
    recentTable.doubleAction = #selector(openRecent)
    recentTable.action = #selector(openRecent)
    recentTable.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    documentArea.addSubview(host)
    documentArea.addSubview(status)
    status.material = .underWindowBackground
    status.blendingMode = .withinWindow
    status.state = .active
    status.alphaValue = 0.85
    status.addSubview(statusText)
    statusText.font = .systemFont(ofSize: 11)
    statusText.textColor = .secondaryLabelColor
    statusText.lineBreakMode = .byTruncatingMiddle
    sidebar.isHidden = !sidebarVisible
    let toolbar = NSToolbar(identifier: "TinyEditor.toolbar")
    toolbar.delegate = self
    toolbar.displayMode = .iconOnly
    toolbar.sizeMode = .small
    toolbar.allowsUserCustomization = false
    window.toolbar = toolbar
    NotificationCenter.default.addObserver(
      self, selector: #selector(documentChanged(_:)), name: .documentChanged, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(recentChanged), name: .recentsChanged, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(preferencesChanged), name: .preferencesChanged, object: nil)
    preferencesChanged()
  }
  required init?(coder: NSCoder) { fatalError() }
  deinit { NotificationCenter.default.removeObserver(self) }
  func layoutContent() {
    guard let root = window?.contentView else { return }
    let top = window?.contentLayoutRect.maxY ?? root.bounds.height
    tabStrip.frame = NSRect(x: 0, y: top - 28, width: root.bounds.width, height: 28)
    split.frame = NSRect(x: 0, y: 0, width: root.bounds.width, height: max(0, top - 28))
    if sidebarVisible {
      if abs(sidebar.frame.width - sidebarWidth) > 1 {
        split.setPosition(sidebarWidth, ofDividerAt: 0)
      }
    }
    host.frame = NSRect(
      x: 0, y: 24, width: documentArea.bounds.width, height: max(0, documentArea.bounds.height - 24)
    )
    status.frame = NSRect(x: 0, y: 0, width: documentArea.bounds.width, height: 24)
    statusText.frame = NSRect(x: 10, y: 5, width: max(0, status.bounds.width - 20), height: 16)
    host.subviews.forEach { $0.frame = host.bounds }
  }
  func add(_ document: EditorDocument, index: Int? = nil) {
    documents.insert(document, at: min(index ?? documents.count, documents.count))
    tabStrip.rebuild()
    activate(document)
  }
  func activate(_ document: EditorDocument) {
    guard documents.contains(where: { $0 === document }) else { return }
    if let old = active, old !== document {
      old.selection = old.editor?.textView.selectedRange() ?? old.selection
      old.sourceScroll = old.editor?.scroll.contentView.bounds.origin ?? old.sourceScroll
      old.preview?.rememberScroll({ old.schedulePreviewRelease() })
    }
    active = document
    // Insert and size the prepared new view before detaching the old one.
    let view: NSView =
      document.previewing && document.resolvedFormat == .markdown
      ? document.previewPane() : document.sourcePane()
    view.frame = host.bounds
    if view.superview !== host { host.addSubview(view) }
    host.subviews.filter { $0 !== view }.forEach { $0.removeFromSuperview() }
    view.autoresizingMask = [.width, .height]
    view.layoutSubtreeIfNeeded()
    if let pane = view as? PreviewPane {
      pane.render()
      window?.makeFirstResponder(pane.web)
    } else if let pane = view as? EditorPane {
      window?.makeFirstResponder(pane.textView)
    }
    if document.preview?.superview !== host { document.schedulePreviewRelease() }
    updateChrome()
    tabStrip.reveal(document)
  }
  func remove(_ document: EditorDocument) {
    guard let index = documents.firstIndex(where: { $0 === document }) else { return }
    if active === document {
      window?.makeFirstResponder(nil)
      if document.editor?.superview === host { document.editor?.removeFromSuperview() }
      if document.preview?.superview === host { document.preview?.removeFromSuperview() }
    }
    documents.remove(at: index)
    if active === document {
      active = nil
      if let next = documents.isEmpty
        ? nil : (documents.dropFirst(min(index, documents.count - 1)).first ?? documents.first)
      {
        activate(next)
      }
    }
    tabStrip.rebuild()
    if documents.isEmpty {
      closingAll = true
      window?.close()
      AppController.shared.forget(self)
    }
  }
  @objc func documentChanged(_ notification: Notification) {
    guard let doc = notification.object as? EditorDocument,
      documents.contains(where: { $0 === doc })
    else { return }
    tabStrip.refresh()
    if active === doc { updateChrome() }
    if doc.conflict && !conflictPrompted.contains(doc.id) && window?.attachedSheet == nil {
      conflictPrompted.insert(doc.id)
      promptConflict(doc)
    }
  }
  func updateChrome() {
    guard let doc = active else { return }
    window?.title = doc.name
    window?.subtitle = doc.url?.deletingLastPathComponent().path ?? "本地文本"
    window?.representedURL = doc.url
    window?.isDocumentEdited = doc.isDirty
    if let toolbar = window?.toolbar {
      let modeID = NSToolbarItem.Identifier("mode")
      let index = toolbar.items.firstIndex(where: { $0.itemIdentifier == modeID })
      if doc.resolvedFormat == .markdown && index == nil {
        toolbar.insertItem(withItemIdentifier: modeID, at: toolbar.items.count)
      } else if doc.resolvedFormat != .markdown, let index {
        toolbar.removeItem(at: index)
      }
    }
    formatPopup.selectItem(withTag: Format.allCases.firstIndex(of: doc.format) ?? 0)
    modeSwitch.isHidden = doc.resolvedFormat != .markdown
    modeSwitch.selectedSegment = doc.previewing ? 0 : 1
    zoomReset.title = "\(Int((Settings.shared.fontSize/14*100).rounded()))%"
    var cursor = ""
    if !doc.previewing || doc.resolvedFormat != .markdown {
      let offset = min(doc.selection.location, doc.storage.length)
      let line = doc.lines.line(at: offset)
      let start = doc.lines.starts[line]
      cursor = "行 \(line+1)，列 \(offset-start+1)     "
    }
    statusText.stringValue =
      cursor + doc.encoding.title + "     " + doc.newline + "     " + doc.resolvedFormat.title
      + (doc.conflict ? "     ⚠ 外部修改：请重新载入或另存为" : "")
    statusText.toolTip = doc.url?.path
  }
  func togglePreview() {
    guard let doc = active, doc.resolvedFormat == .markdown else { return }
    if doc.previewing {
      doc.preview?.rememberScroll({})
      doc.previewing = false
      activate(doc)
    } else {
      doc.previewing = true
      doc.previewPane().invalidate()
      activate(doc)
    }
  }
  @objc func modeChanged() {
    guard let doc = active else { return }
    let next = modeSwitch.selectedSegment == 0
    if next != doc.previewing { togglePreview() }
  }
  @objc func formatChanged() {
    guard let doc = active else { return }
    let was = doc.resolvedFormat
    doc.format = Format.allCases[formatPopup.selectedTag()]
    if doc.resolvedFormat == .markdown && was != .markdown { doc.previewing = true }
    if doc.resolvedFormat != .markdown { doc.previewing = false }
    doc.editor?.highlight()
    activate(doc)
  }
  @objc func toggleSidebar() {
    sidebarVisible.toggle()
    sidebar.isHidden = !sidebarVisible
    window?.contentView?.needsLayout = true
    if sidebarVisible { split.setPosition(sidebarWidth, ofDividerAt: 0) }
    layoutContent()
  }
  @objc func preferencesChanged() {
    let theme = Settings.shared.theme
    window?.appearance =
      theme == "system" ? nil : NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)
    documents.forEach {
      $0.editor?.applyPreferences()
      $0.preview?.preferencesChanged()
    }
    updateChrome()
    tabStrip.refresh()
  }
  @objc func recentChanged() { recentTable.reloadData() }
  func numberOfRows(in tableView: NSTableView) -> Int { Settings.shared.recents.count }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    let cell = NSTableCellView()
    let label = NSTextField(
      labelWithString: URL(fileURLWithPath: Settings.shared.recents[row]).lastPathComponent)
    label.font = .systemFont(ofSize: 12)
    label.lineBreakMode = .byTruncatingMiddle
    label.frame = NSRect(x: 10, y: 4, width: max(0, tableView.bounds.width - 20), height: 18)
    label.autoresizingMask = [.width]
    cell.addSubview(label)
    cell.textField = label
    cell.toolTip = Settings.shared.recents[row]
    return cell
  }
  @objc func openRecent() {
    let row = recentTable.clickedRow
    guard row >= 0, row < Settings.shared.recents.count else { return }
    AppController.shared.open(urls: [URL(fileURLWithPath: Settings.shared.recents[row])], in: self)
  }
  func splitView(
    _ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat,
    ofSubviewAt dividerIndex: Int
  ) -> CGFloat { 170 }
  func splitView(
    _ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat,
    ofSubviewAt dividerIndex: Int
  ) -> CGFloat { min(340, splitView.bounds.width - 300) }
  func splitViewDidResizeSubviews(_ notification: Notification) {
    if sidebarVisible && sidebar.frame.width >= 170 { sidebarWidth = min(340, sidebar.frame.width) }
    layoutContent()
  }
  func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
    view !== sidebar
  }
  func installDropOverlay() {
    guard dropOverlay == nil, let frame = window?.contentView?.superview else { return }
    let overlay = DropOverlay(owner: self, frame: frame.bounds)
    frame.addSubview(overlay, positioned: .above, relativeTo: nil)
    dropOverlay = overlay
  }
  func close(_ doc: EditorDocument, completion: @escaping (Bool) -> Void = { _ in }) {
    activate(doc)
    AppController.shared.confirmClose(doc, in: self) { [weak self] ok in
      if ok {
        doc.resolveRecovery()
        doc.undo.removeAllActions()
        self?.remove(doc)
      }
      completion(ok)
    }
  }
  func closeOthers(keeping doc: EditorDocument) {
    activate(doc)
    closeSequential(documents.filter { $0 !== doc })
  }
  func closeSequential(_ docs: [EditorDocument], completion: @escaping (Bool) -> Void = { _ in }) {
    guard let first = docs.first else {
      completion(true)
      return
    }
    close(first) { [weak self] ok in
      if ok {
        DispatchQueue.main.async {
          self?.closeSequential(Array(docs.dropFirst()), completion: completion)
        }
      } else {
        completion(false)
      }
    }
  }
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if closingAll { return true }
    closeSequential(documents)
    return false
  }
  func windowWillClose(_ notification: Notification) {
    if documents.isEmpty { AppController.shared.forget(self) }
  }
  func windowDidBecomeKey(_ notification: Notification) { AppController.shared.lastWindow = self }
  func rename(_ doc: EditorDocument) {
    activate(doc)
    guard let window, window.attachedSheet == nil else { return }
    let alert = NSAlert()
    alert.messageText = "重命名"
    alert.informativeText = doc.url == nil ? "设置首次保存时使用的文件名。" : "移动磁盘文件；当前未保存的编辑保持不变。"
    let input = NSTextField(string: doc.name)
    input.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
    alert.accessoryView = input
    alert.addButton(withTitle: "重命名")
    alert.addButton(withTitle: "取消")
    alert.beginSheetModal(for: window) { response in
      if response == .alertFirstButtonReturn {
        do {
          try doc.rename(input.stringValue)
          self.activate(doc)
        } catch { showError(error, window: window) }
      }
    }
    window.makeFirstResponder(input)
  }
  func promptConflict(_ doc: EditorDocument) {
    activate(doc)
    guard let window else { return }
    let alert = NSAlert()
    alert.messageText = "文件在外部发生了变化"
    alert.informativeText = "“\(doc.name)”的磁盘版本已改变。保留当前内容后仍可编辑和另存为；重新载入会放弃当前未保存编辑。"
    alert.addButton(withTitle: "保留当前内容")
    alert.addButton(withTitle: "重新载入")
    alert.beginSheetModal(for: window) { response in
      if response == .alertSecondButtonReturn {
        do {
          try doc.reload()
          self.conflictPrompted.remove(doc.id)
        } catch { showError(error, window: window) }
      }
    }
  }
  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarDefaultItemIdentifiers(toolbar) + [NSToolbarItem.Identifier("mode")]
  }
  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [
      NSToolbarItem.Identifier("sidebar"), .flexibleSpace, NSToolbarItem.Identifier("format"),
      NSToolbarItem.Identifier("zoom"),
    ]
  }
  func toolbar(
    _ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    let item = NSToolbarItem(itemIdentifier: id)
    switch id.rawValue {
    case "sidebar":
      sidebarButton.image = NSImage(
        systemSymbolName: "sidebar.left", accessibilityDescription: "最近文件侧边栏")
      sidebarButton.target = self
      sidebarButton.action = #selector(toggleSidebar)
      sidebarButton.isBordered = false
      sidebarButton.toolTip = "展开／收起最近文件（⌃⌘S）"
      sidebarButton.setAccessibilityLabel("最近文件侧边栏")
      item.view = sidebarButton
      item.label = "最近文件"
    case "format":
      for (i, format) in Format.allCases.enumerated() {
        formatPopup.addItem(withTitle: format.title)
        formatPopup.lastItem?.tag = i
      }
      formatPopup.target = self
      formatPopup.action = #selector(formatChanged)
      formatPopup.toolTip = "内容格式：覆盖扩展名识别，不改变原文"
      formatPopup.setAccessibilityLabel("内容格式")
      formatPopup.controlSize = .small
      item.view = formatPopup
      item.label = "内容格式"
    case "zoom":
      let stack = NSStackView()
      stack.spacing = 1
      stack.orientation = .horizontal
      for (button, title, action, tip) in [
        (zoomMinus, "−", #selector(AppController.zoomOut(_:)), "缩小（⌘−）"),
        (zoomReset, "100%", #selector(AppController.zoomReset(_:)), "重置字号（⌘0）"),
        (zoomPlus, "+", #selector(AppController.zoomIn(_:)), "放大（⌘+）"),
      ] {
        button.title = title
        button.target = AppController.shared
        button.action = action
        button.isBordered = false
        button.font = .systemFont(ofSize: 12)
        button.toolTip = tip
        button.setAccessibilityLabel(tip)
        button.widthAnchor.constraint(equalToConstant: button === zoomReset ? 43 : 22).isActive =
          true
        stack.addArrangedSubview(button)
      }
      item.view = stack
      item.label = "字号"
    case "mode":
      modeSwitch.controlSize = .small
      modeSwitch.target = self
      modeSwitch.action = #selector(modeChanged)
      modeSwitch.toolTip = "Markdown 预览／编辑（⌘⇧P）"
      modeSwitch.setAccessibilityLabel("Markdown 显示模式")
      item.view = modeSwitch
      item.label = "预览／编辑"
    default: return nil
    }
    return item
  }
}
final class LayoutView: NSView {
  weak var owner: EditorWindowController?
  override func layout() {
    super.layout()
    owner?.layoutContent()
  }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    owner?.documents.forEach {
      $0.editor?.applyPreferences()
      $0.preview?.preferencesChanged()
    }
    owner?.tabStrip.refresh()
  }
}

func dragLog(_ message: String) {
  if ProcessInfo.processInfo.environment["TINYEDITOR_UI_FIXTURES"] != nil {
    NSLog("Drag: %@", message)
  }
}
