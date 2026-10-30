import AppKit

final class TabCell: NSView, NSDraggingSource {
  weak var owner: EditorWindowController?
  let document: EditorDocument
  let title = NSTextField(labelWithString: "")
  let icon = NSImageView()
  let closeButton = NSButton()
  var tracking: NSTrackingArea?
  var mouseOrigin = NSPoint.zero
  var hovering = false
  init(document: EditorDocument, owner: EditorWindowController) {
    self.document = document
    self.owner = owner
    super.init(frame: .zero)
    title.font = .systemFont(ofSize: 12)
    title.alignment = .left
    title.lineBreakMode = .byTruncatingMiddle
    title.maximumNumberOfLines = 1
    title.isSelectable = false
    addSubview(title)
    icon.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
    icon.imageScaling = .scaleProportionallyDown
    icon.setAccessibilityElement(false)
    addSubview(icon)
    closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭标签")?
      .withSymbolConfiguration(.init(pointSize: 10, weight: .regular))
    closeButton.imageScaling = .scaleProportionallyDown
    closeButton.isBordered = false
    closeButton.target = self
    closeButton.action = #selector(closeTab)
    closeButton.toolTip = "关闭标签"
    closeButton.setAccessibilityLabel("关闭 \(document.name)")
    addSubview(closeButton)
    refresh()
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel(document.name)
  }
  required init?(coder: NSCoder) { fatalError() }
  override var isFlipped: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? {
    let local = convert(point, from: superview)
    guard bounds.contains(local) else { return nil }
    if !closeButton.isHidden && closeButton.frame.contains(local) { return closeButton }
    return self
  }
  override func layout() {
    super.layout()
    let centerY = bounds.midY
    icon.frame = NSRect(x: 13, y: centerY - 7, width: 14, height: 14)
    closeButton.frame = NSRect(x: bounds.width - 31, y: centerY - 12, width: 24, height: 24)
    title.frame = NSRect(x: 34, y: centerY - 8, width: max(0, bounds.width - 70), height: 17)
  }
  func refresh() {
    let selected = owner?.active === document
    title.stringValue = (document.isDirty ? "• " : "") + document.name
    title.textColor = selected ? .labelColor : .secondaryLabelColor
    title.font = .systemFont(ofSize: 12, weight: selected ? .medium : .regular)
    closeButton.contentTintColor = .secondaryLabelColor
    icon.contentTintColor = selected ? .labelColor : .tertiaryLabelColor
    toolTip = document.url?.path ?? document.name
    closeButton.isHidden = !(hovering || owner?.active === document)
    needsDisplay = true
  }
  override func draw(_ rect: NSRect) {
    let selected = owner?.active === document
    let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 3), xRadius: 8, yRadius: 8)
    if selected || hovering {
      let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      let fill = dark
        ? NSColor.windowBackgroundColor.blended(withFraction: selected ? 0.10 : 0.045, of: .labelColor)!
        : NSColor.textBackgroundColor.withAlphaComponent(selected ? 1 : 0.45)
      NSGraphicsContext.saveGraphicsState()
      if selected {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.16 : 0.07)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
      }
      fill.setFill()
      pill.fill()
      NSGraphicsContext.restoreGraphicsState()
      if selected {
        NSColor.labelColor.withAlphaComponent(dark ? 0.07 : 0.055).setStroke()
        pill.lineWidth = 0.5
        pill.stroke()
      }
    }
    let nextIsSelected = owner?.tabStrip.cells.first(where: {
      abs($0.frame.minX - frame.maxX - TabStrip.gap) < 1
    })?.document === owner?.active
    if !selected && !hovering && !nextIsSelected {
      NSColor.separatorColor.withAlphaComponent(0.45).setFill()
      NSRect(x: bounds.maxX - 0.5, y: 11, width: 0.5, height: max(0, bounds.height - 22)).fill()
    }
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
    guard DragCoordinator.shared.token == nil else { return }
    let token = DragCoordinator.shared.begin(document, source: owner, cell: self)
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
  func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
    dragLog("moved \(screenPoint)")
  }
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
final class TabStrip: TabDropView {
  static let height: CGFloat = 36
  static let gap: CGFloat = 4
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
    addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "新建标签")?
      .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
    addButton.contentTintColor = .secondaryLabelColor
    addButton.isBordered = false
    addButton.target = self
    addButton.action = #selector(addTab)
    addButton.toolTip = "新建标签（⌘T）"
    addSubview(addButton)
  }
  required init?(coder: NSCoder) { fatalError() }
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    (NSColor.windowBackgroundColor.blended(withFraction: 0.025, of: .labelColor)
      ?? NSColor.windowBackgroundColor).setFill()
    bounds.fill()
  }
  func rebuild() {
    cells.forEach { $0.removeFromSuperview() }
    cells = (owner?.documents ?? []).map { TabCell(document: $0, owner: owner!) }
    cells.forEach { content.addSubview($0) }
    needsLayout = true
  }
  func refresh() { cells.forEach { $0.refresh() } }
  override func layout() {
    super.layout()
    let count = CGFloat(max(1, cells.count))
    let available = max(0, bounds.width - 44)
    let width = max(140, min(240, (available - Self.gap * (count - 1)) / count))
    let tabsWidth = (width + Self.gap) * CGFloat(cells.count) - Self.gap
    let visibleWidth = min(available, max(0, tabsWidth))
    scroll.frame = NSRect(x: 6, y: 0, width: visibleWidth, height: Self.height)
    addButton.frame = NSRect(x: scroll.frame.maxX + 4, y: 4, width: 28, height: 28)
    content.frame = NSRect(
      x: 0, y: 0, width: max(visibleWidth, tabsWidth), height: Self.height)
    for (i, cell) in cells.enumerated() {
      cell.frame = NSRect(x: CGFloat(i) * (width + Self.gap), y: 0, width: width, height: Self.height)
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

final class SidebarSplitView: NSSplitView {
  override var dividerColor: NSColor {
    arrangedSubviews.first?.isHidden == true ? .clear : super.dividerColor
  }
  override func drawDivider(in rect: NSRect) {
    if arrangedSubviews.first?.isHidden != true { super.drawDivider(in: rect) }
  }
}

final class EditorWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate,
  NSTableViewDataSource, NSTableViewDelegate, NSSplitViewDelegate
{
  var documents: [EditorDocument] = []
  var active: EditorDocument?
  let tabStrip = TabStrip(), split = SidebarSplitView(), sidebar = NSScrollView(),
    recentTable = NSTableView(), documentArea = TabDropView(), host = TabDropView(),
    status = NSVisualEffectView(), statusText = NSTextField(labelWithString: "")
  let sidebarButton = NSButton(), formatPopup = NSPopUpButton(), zoomMinus = NSButton(),
    zoomReset = NSButton(), zoomPlus = NSButton(),
    modeSwitch = NSSegmentedControl(
      labels: ["预览", "编辑"], trackingMode: .selectOne, target: nil, action: nil)
  var sidebarVisible = false, sidebarWidth: CGFloat = 220
  var dropOverlay: DropOverlay?
  private var isLayingOut = false
  var closingAll = false
  var conflictPrompted: Set<UUID> = []
  init(inheritSidebar: EditorWindowController? = nil) {
    let window = EditorWindow(
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
    window.editorOwner = self
    window.acceptsMouseMovedEvents = true
    window.registerForDraggedTypes([tabDragType])
    window.center()
    if let inheritSidebar {
      sidebarVisible = inheritSidebar.sidebarVisible
      sidebarWidth = inheritSidebar.sidebarWidth
    }
    let root = LayoutView()
    root.owner = self
    window.contentView = root
    tabStrip.owner = self
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
    documentArea.addSubview(tabStrip)
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
    // Register the transparent native drop destination before AppKit snapshots drag regions.
    // Its ordinary mouse hitTest always returns nil, including while a tab is being dragged.
    installDropOverlay()
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
    guard !isLayingOut, let root = window?.contentView else { return }
    isLayingOut = true
    defer { isLayingOut = false }
    let top = window?.contentLayoutRect.maxY ?? root.bounds.height
    split.frame = NSRect(x: 0, y: 0, width: root.bounds.width, height: max(0, top))
    if sidebarVisible {
      if abs(sidebar.frame.width - sidebarWidth) > 1 {
        split.setPosition(sidebarWidth, ofDividerAt: 0)
      }
    }
    tabStrip.frame = NSRect(
      x: 0, y: max(0, documentArea.bounds.height - TabStrip.height),
      width: documentArea.bounds.width, height: TabStrip.height)
    host.frame = NSRect(
      x: 0, y: 24, width: documentArea.bounds.width,
      height: max(0, documentArea.bounds.height - 24 - TabStrip.height)
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
    tabStrip.refresh()
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
    UITestPreparation.snapshot(event: "tab-activated")
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
    UITestPreparation.snapshot(event: "tab-removed")
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
    UITestPreparation.snapshot(event: "document-changed")
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
    let preferredWidth = sidebarWidth
    sidebar.isHidden = !sidebarVisible
    if !sidebarVisible {
      // Hidden arranged views retain their old frame; AppKit can still draw that divider.
      sidebar.setFrameSize(NSSize(width: 0, height: sidebar.frame.height))
    }
    split.adjustSubviews()
    split.needsDisplay = true
    sidebarWidth = preferredWidth
    layoutContent()
    window?.contentView?.needsLayout = true
    UITestPreparation.snapshot(event: "sidebar-toggled")
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
    guard !isLayingOut else { return }
    if sidebarVisible && sidebar.frame.width >= 170 { sidebarWidth = min(340, sidebar.frame.width) }
    layoutContent()
  }
  func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
    view !== sidebar
  }
  func splitView(_ splitView: NSSplitView, shouldHideDividerAt dividerIndex: Int) -> Bool {
    !sidebarVisible
  }
  func installDropOverlay() {
    guard dropOverlay == nil, let frame = window?.contentView?.superview else { return }
    let overlay = DropOverlay(frame: frame.bounds)
    overlay.autoresizingMask = [.width, .height]
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
final class LayoutView: TabDropView {
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
