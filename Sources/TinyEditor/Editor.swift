import AppKit

final class SourceTextView: NSTextView {
  weak var owner: EditorPane?
  override var undoManager: UndoManager? { owner?.isPaged == true ? nil : owner?.document.undo }
  @objc func undo(_ sender: Any?) { owner?.document.undo.undo() }
  @objc func redo(_ sender: Any?) { owner?.document.undo.redo() }
  override func copy(_ sender: Any?) {
    let range = selectedRange()
    if owner?.wholeSelected == true, let doc = owner?.document {
      pureCopy(doc.text)
    } else if range.length > 0 {
      pureCopy((string as NSString).substring(with: range))
    }
  }
  override func selectAll(_ sender: Any?) {
    super.selectAll(sender)
    if let owner, owner.isPaged {
      owner.wholeSelected = true
      owner.document.selection = NSRange(location: 0, length: owner.document.storage.length)
    }
  }
  override func mouseDown(with event: NSEvent) {
    owner?.wholeSelected = false
    super.mouseDown(with: event)
  }
  override func cut(_ sender: Any?) {
    copy(sender)
    if isEditable { insertText("", replacementRange: selectedRange()) }
  }
  override func paste(_ sender: Any?) {
    if let text = NSPasteboard.general.string(forType: .string) {
      insertText(text, replacementRange: selectedRange())
    }
  }
  override func insertNewline(_ sender: Any?) {
    let ending = owner?.document.newline ?? "LF"
    insertText(
      ending == "CRLF" ? "\r\n" : ending == "CR" ? "\r" : "\n", replacementRange: selectedRange())
  }
  override func pasteAsPlainText(_ sender: Any?) { paste(sender) }
  override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool
  {
    guard let text = pboard.string(forType: .string) else { return false }
    insertText(text, replacementRange: selectedRange())
    return true
  }
  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    owner?.gutter.needsDisplay = true
  }
  override func keyDown(with event: NSEvent) {
    super.keyDown(with: event)
    owner?.selectionChanged()
  }
}

final class EditorPane: NSView, NSTextViewDelegate {
  unowned let document: EditorDocument
  let scroll = NSScrollView()
  let gutter = GutterView()
  let layoutManager = NSLayoutManager()
  let container = NSTextContainer(size: NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude))
  let textView: SourceTextView
  let displayStorage: NSTextStorage
  let isPaged: Bool
  let pageBar = NSStackView()
  let pageLabel = NSTextField(labelWithString: "")
  var sliceStart = 0
  var sliceEnd = 0
  var wholeSelected = false
  var projectionUpdating = false
  var projectionBefore = ""
  var replaceWholeDocument = false
  let pageSize = 32768
  private var lastFind = ""
  var highlightWork: DispatchWorkItem?
  private var gutterWidth: CGFloat = 28
  private var updating = false
  init(document: EditorDocument) {
    self.document = document
    let starts = document.lines.starts
    isPaged = starts.enumerated().contains { i, start in
      (i + 1 < starts.count ? starts[i + 1] : document.storage.length) - start > 100_000
    }
    if isPaged {
      displayStorage = NSTextStorage(
        string: (document.text as NSString).substring(to: min(32768, document.storage.length)))
      sliceEnd = displayStorage.length
    } else {
      displayStorage = document.storage
      sliceEnd = document.storage.length
    }
    layoutManager.allowsNonContiguousLayout = true
    layoutManager.backgroundLayoutEnabled = false
    container.lineFragmentPadding = 5
    layoutManager.addTextContainer(container)
    displayStorage.addLayoutManager(layoutManager)
    textView = SourceTextView(
      frame: NSRect(x: 0, y: 0, width: 800, height: 600), textContainer: container)
    super.init(frame: .zero)
    textView.owner = self
    textView.delegate = self
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = !isPaged
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.isContinuousSpellCheckingEnabled = false
    textView.isGrammarCheckingEnabled = false
    textView.isAutomaticLinkDetectionEnabled = false
    textView.isAutomaticDataDetectionEnabled = false
    textView.usesFindBar = true
    textView.isIncrementalSearchingEnabled = true
    textView.isVerticallyResizable = true
    textView.autoresizingMask = [.width]
    textView.minSize = NSSize(width: 0, height: 0)
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.textContainerInset = NSSize(width: 7, height: 8)
    textView.font = .monospacedSystemFont(ofSize: Settings.shared.fontSize, weight: .regular)
    textView.defaultParagraphStyle = {
      let p = NSMutableParagraphStyle()
      p.lineSpacing = 2
      return p
    }()
    scroll.documentView = textView
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.autohidesScrollers = true
    scroll.borderType = .noBorder
    scroll.contentView.postsBoundsChangedNotifications = true
    NotificationCenter.default.addObserver(
      self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification,
      object: scroll.contentView)
    gutter.pane = self
    addSubview(gutter)
    addSubview(scroll)
    if isPaged {
      pageBar.orientation = .horizontal
      pageBar.spacing = 8
      pageBar.alignment = .centerY
      let previous = NSButton(title: "上一段", target: self, action: #selector(previousPage))
      let next = NSButton(title: "下一段", target: self, action: #selector(nextPage))
      for button in [previous, next] {
        button.bezelStyle = .roundRect
        button.controlSize = .mini
        pageBar.addArrangedSubview(button)
      }
      pageLabel.font = .systemFont(ofSize: 10)
      pageLabel.textColor = .secondaryLabelColor
      pageBar.addArrangedSubview(pageLabel)
      addSubview(pageBar)
      updatePageLabel()
    }
    applyPreferences()
    if isPaged {
      refreshProjection(around: document.selection.location)
    } else {
      textView.setSelectedRange(document.selection)
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  deinit {
    NotificationCenter.default.removeObserver(self)
    layoutManager.textStorage?.removeLayoutManager(layoutManager)
  }
  override var isFlipped: Bool { true }
  override func layout() {
    super.layout()
    let inset: CGFloat = isPaged ? 24 : 0
    pageBar.frame = NSRect(x: 8, y: 0, width: max(0, bounds.width - 16), height: inset)
    gutter.frame = NSRect(x: 0, y: inset, width: gutterWidth, height: max(0, bounds.height - inset))
    scroll.frame = NSRect(
      x: gutterWidth, y: inset, width: max(0, bounds.width - gutterWidth),
      height: max(0, bounds.height - inset))
    if document.wrap {
      container.containerSize.width = scroll.contentSize.width
      textView.setFrameSize(
        NSSize(
          width: scroll.contentSize.width,
          height: max(textView.frame.height, scroll.contentSize.height)))
    }
  }
  func applyPreferences() {
    textView.font = .monospacedSystemFont(ofSize: Settings.shared.fontSize, weight: .regular)
    textView.textColor = .textColor
    textView.backgroundColor = .textBackgroundColor
    textView.insertionPointColor = .textColor
    textView.typingAttributes = [
      .font: textView.font!, .foregroundColor: NSColor.textColor,
      .paragraphStyle: textView.defaultParagraphStyle ?? NSParagraphStyle.default,
    ]
    textView.isHorizontallyResizable = !document.wrap
    container.widthTracksTextView = document.wrap
    container.containerSize = NSSize(
      width: document.wrap ? max(100, scroll.contentSize.width) : 10_000_000,
      height: CGFloat.greatestFiniteMagnitude)
    scroll.hasHorizontalScroller = !document.wrap
    needsLayout = true
    gutter.needsDisplay = true
    highlight()
  }
  func reload() {
    if isPaged {
      refreshProjection(around: document.selection.location)
    } else {
      textView.setSelectedRange(document.selection)
    }
    contentChanged()
  }
  func contentChanged() {
    if isPaged { updatePageLabel() }
    let digits = String(document.lines.starts.count).count
    let next = max(28, CGFloat(digits) * 6 + 12)
    if next != gutterWidth {
      gutterWidth = next
      needsLayout = true
    }
    gutter.needsDisplay = true
    highlightWork?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.highlight() }
    highlightWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
  }
  @objc private func scrolled() {
    document.sourceScroll = scroll.contentView.bounds.origin
    gutter.needsDisplay = true
    highlightWork?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.highlight() }
    highlightWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
  }
  func textViewDidChangeSelection(_ notification: Notification) { selectionChanged() }
  func selectionChanged() {
    guard !projectionUpdating else { return }
    let selected = textView.selectedRange()
    if wholeSelected && selected.location == 0 && selected.length == displayStorage.length {
      document.selection = NSRange(location: 0, length: document.storage.length)
    } else {
      wholeSelected = false
      document.selection = NSRange(
        location: sliceStart + selected.location, length: selected.length)
    }
    document.changed()
  }
  func textView(
    _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
    replacementString: String?
  ) -> Bool {
    if isPaged && wholeSelected { replaceWholeDocument = true }
    return true
  }
  private func synchronizeProjection() {
    guard isPaged, !projectionUpdating else { return }
    let old = projectionBefore as NSString
    let current = displayStorage.string as NSString
    if old.isEqual(to: current as String) { return }
    if replaceWholeDocument {
      document.replaceCanonical(
        range: NSRange(location: 0, length: document.storage.length), with: current as String,
        updateView: false)
      sliceStart = 0
      replaceWholeDocument = false
      wholeSelected = false
    } else {
      var prefix = 0
      var suffix = 0
      while prefix < min(old.length, current.length)
        && old.character(at: prefix) == current.character(at: prefix)
      { prefix += 1 }
      if prefix < old.length {
        prefix = min(prefix, old.rangeOfComposedCharacterSequence(at: prefix).location)
      }
      if prefix < current.length {
        prefix = min(prefix, current.rangeOfComposedCharacterSequence(at: prefix).location)
      }
      while suffix < min(old.length - prefix, current.length - prefix)
        && old.character(at: old.length - suffix - 1)
          == current.character(at: current.length - suffix - 1)
      { suffix += 1 }
      while suffix > 0 {
        let a = old.length - suffix
        let b = current.length - suffix
        if (a == old.length || old.rangeOfComposedCharacterSequence(at: a).location == a)
          && (b == current.length || current.rangeOfComposedCharacterSequence(at: b).location == b)
        {
          break
        }
        suffix -= 1
      }
      let range = NSRange(location: sliceStart + prefix, length: old.length - prefix - suffix)
      let replacement = current.substring(
        with: NSRange(location: prefix, length: current.length - prefix - suffix))
      document.replaceCanonical(range: range, with: replacement, updateView: false)
    }
    projectionBefore = current as String
    sliceEnd = sliceStart + current.length
    updatePageLabel()
  }
  @objc func previousPage() { refreshProjection(around: max(0, sliceStart - pageSize)) }
  @objc func nextPage() {
    if sliceEnd < document.storage.length {
      refreshProjection(around: sliceEnd, alignToStart: true)
    }
  }
  private func updatePageLabel() {
    pageLabel.stringValue =
      "超长行分段编辑 · UTF-16 位置 \(sliceStart+1)–\(sliceEnd) / \(document.storage.length)"
  }
  func refreshProjection(around offset: Int, alignToStart: Bool = false) {
    guard isPaged, !textView.hasMarkedText() else { return }
    let ns = document.text as NSString
    var start =
      alignToStart ? offset : max(0, min(offset - pageSize / 4, max(0, ns.length - pageSize)))
    start = min(ns.length, max(0, start))
    if start > 0 && start < ns.length {
      start = ns.rangeOfComposedCharacterSequence(at: start).location
    }
    var end = min(ns.length, start + pageSize)
    if end < ns.length { end = NSMaxRange(ns.rangeOfComposedCharacterSequence(at: end)) }
    projectionUpdating = true
    sliceStart = start
    sliceEnd = end
    wholeSelected = false
    projectionBefore = ns.substring(with: NSRange(location: start, length: end - start))
    displayStorage.replaceCharacters(
      in: NSRange(location: 0, length: displayStorage.length), with: projectionBefore)
    let caret = min(max(0, offset - start), displayStorage.length)
    textView.setSelectedRange(NSRange(location: caret, length: 0))
    projectionUpdating = false
    document.selection = NSRange(location: start + caret, length: 0)
    textView.scrollRangeToVisible(textView.selectedRange())
    updatePageLabel()
    contentChanged()
    document.changed()
  }
  func showPagedFind(replace: Bool) {
    guard let window, window.attachedSheet == nil else { return }
    let alert = NSAlert()
    alert.messageText = replace ? "在完整原文中查找与替换" : "在完整原文中查找"
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.spacing = 8
    let find = NSSearchField(string: lastFind)
    find.placeholderString = "查找文本"
    find.frame.size = NSSize(width: 320, height: 24)
    find.widthAnchor.constraint(equalToConstant: 320).isActive = true
    stack.addArrangedSubview(find)
    let replacement = NSTextField(string: "")
    replacement.placeholderString = "替换为"
    if replace { stack.addArrangedSubview(replacement) }
    alert.accessoryView = stack
    alert.addButton(withTitle: "查找下一个")
    if replace {
      alert.addButton(withTitle: "替换选中")
      alert.addButton(withTitle: "全部替换")
    }
    alert.addButton(withTitle: "取消")
    alert.beginSheetModal(for: window) { response in
      let query = find.stringValue
      self.lastFind = query
      guard !query.isEmpty, response != (replace ? .init(rawValue: 1003) : .alertSecondButtonReturn)
      else { return }
      let ns = self.document.text as NSString
      if replace && response == .alertThirdButtonReturn {
        let result = self.document.text.replacingOccurrences(
          of: query, with: replacement.stringValue)
        self.document.replaceCanonical(range: NSRange(location: 0, length: ns.length), with: result)
        return
      }
      if replace && response == .alertSecondButtonReturn, self.document.selection.length > 0,
        NSMaxRange(self.document.selection) <= ns.length,
        ns.substring(with: self.document.selection) == query
      {
        self.document.replaceCanonical(
          range: self.document.selection, with: replacement.stringValue)
        return
      }
      let start = min(ns.length, NSMaxRange(self.document.selection))
      var range = ns.range(of: query, range: NSRange(location: start, length: ns.length - start))
      if range.location == NSNotFound { range = ns.range(of: query) }
      if range.location != NSNotFound {
        self.refreshProjection(around: range.location)
        let length = min(
          range.length, self.displayStorage.length - (range.location - self.sliceStart))
        self.textView.setSelectedRange(
          NSRange(location: range.location - self.sliceStart, length: length))
        self.document.selection = range
        self.textView.scrollRangeToVisible(self.textView.selectedRange())
      } else {
        NSSound.beep()
      }
    }
    window.makeFirstResponder(find)
  }
  func textDidChange(_ notification: Notification) {
    synchronizeProjection()
    selectionChanged()
  }
  func visibleCharacters() -> NSRange {
    let glyphs = layoutManager.glyphRange(forBoundingRect: scroll.contentView.bounds, in: container)
    return layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
  }
  func highlight() {
    guard !textView.hasMarkedText(), document.storage.length > 0 else { return }
    let visible = visibleCharacters()
    let ns = displayStorage.string as NSString
    // Bound work even when a visible logical line is tens of megabytes long.
    let start = max(0, visible.location - 1500)
    let length = min(100_000, min(ns.length - start, visible.length + 3000))
    guard length > 0 else { return }
    let range = NSRange(location: start, length: length)
    layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
    let format = document.resolvedFormat
    guard format != .plain else { return }
    let text = ns.substring(with: range)
    if format == .shell || format == .sql {
      for span in ScriptHighlighting.spans(in: text, format: format) {
        layoutManager.addTemporaryAttribute(
          .foregroundColor, value: span.kind.color,
          forCharacterRange: NSRange(location: start + span.range.location, length: span.range.length))
      }
      return
    }
    let patterns: [(String, NSColor)]
    switch format {
    case .json:
      patterns = [
        ("\"(?:\\\\.|[^\"\\\\])*\"", .systemRed),
        (
          "\\b(?:true|false|null)\\b|(?<![\\w])[-+]?\\d+(?:\\.\\d+)?(?:[eE][-+]?\\d+)?",
          .systemPurple
        ), ("\"(?:\\\\.|[^\"\\\\])*\"(?=\\s*:)", .systemBlue),
      ]
    case .yaml:
      patterns = [
        ("(?m)#.*$", .secondaryLabelColor), ("(?m)^\\s*[^\\n:#]+(?=\\s*:)", .systemBlue),
        ("\"(?:\\\\.|[^\"\\\\])*\"|'[^']*'", .systemRed),
        ("\\b(?:true|false|null|yes|no|~|\\d+)\\b", .systemPurple),
      ]
    default:
      patterns = [
        ("(?m)^#{1,6} .*$", .systemBlue), ("`[^`\\n]+`|(?s)```.*?```", .systemBrown),
        ("\\*\\*[^*]+\\*\\*|__[^_]+__|\\*[^*\\n]+\\*", .systemPurple),
        ("!?\\[[^]\\n]+\\]\\([^\\n)]+\\)", .systemTeal),
        ("(?m)^\\s*(?:>|[-+*] |\\d+\\. ).*$", .systemGreen),
      ]
    }
    for (pattern, color) in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
      for match in regex.matches(
        in: text, range: NSRange(location: 0, length: (text as NSString).length))
      {
        layoutManager.addTemporaryAttribute(
          .foregroundColor, value: color,
          forCharacterRange: NSRange(
            location: start + match.range.location, length: match.range.length))
      }
    }
  }
}
final class GutterView: NSView {
  weak var pane: EditorPane?
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    NSColor.textBackgroundColor.setFill()
    bounds.fill()
    guard let pane else { return }
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: bounds).addClip()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let layoutManager = pane.layoutManager
    let doc = pane.document
    let origin = pane.scroll.contentView.bounds.origin
    guard doc.storage.length > 0 else {
      drawNumber(1, y: 8)
      return
    }
    let visible = pane.visibleCharacters()
    let first = doc.lines.line(at: pane.sliceStart + visible.location)
    let last = min(
      doc.lines.starts.count - 1,
      doc.lines.line(
        at: min(doc.storage.length, pane.sliceStart + visible.location + visible.length)) + 1)
    guard first <= last else { return }
    for line in first...last {
      let canonicalIndex = doc.lines.starts[line]
      let index = max(0, canonicalIndex - pane.sliceStart)
      if canonicalIndex < pane.sliceStart && (line != first || visible.location > 0) { continue }
      if index > pane.displayStorage.length { continue }
      var rect: NSRect
      if index == pane.displayStorage.length {
        rect = layoutManager.extraLineFragmentRect
        if rect.isEmpty { continue }
      } else {
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        rect = layoutManager.lineFragmentRect(
          forGlyphAt: glyph, effectiveRange: nil, withoutAdditionalLayout: true)
      }
      let y =
        rect.minY + pane.textView.textContainerOrigin.y - origin.y + (Settings.shared.fontSize - 10)
        / 2 + 1
      if y > -20 && y < bounds.height { drawNumber(line + 1, y: y) }
    }
  }
  private func drawNumber(_ number: Int, y: CGFloat) {
    let value = "\(number)" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
      .foregroundColor: NSColor.tertiaryLabelColor,
    ]
    let width = value.size(withAttributes: attrs).width
    value.draw(at: NSPoint(x: bounds.width - width - 7, y: y), withAttributes: attrs)
  }
}
