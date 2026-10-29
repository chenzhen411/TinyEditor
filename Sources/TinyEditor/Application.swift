import AppKit

final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
  static let shared = AppController()
  var windows: [EditorWindowController] = []
  weak var lastWindow: EditorWindowController?
  var instance: SingleInstance?
  var initialRequest = LaunchRequest()
  var timer: Timer?
  var isTerminating = false
  var terminationApproved = false
  var recentMenu: NSMenu!
  var localKeyMonitor: Any?
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSWindow.allowsAutomaticWindowTabbing = false
    NSApp.setActivationPolicy(.regular)
    buildMenus()
    NSApp.disableRelaunchOnLogin()
    instance?.start { [weak self] in self?.handle($0) }
    if windows.isEmpty { handle(initialRequest) }
    let records = Settings.shared.pendingRecovery()
    if !records.isEmpty { recover(records) }
    UITestPreparation.prepare()
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      self?.windows.flatMap(\.documents).forEach { $0.checkExternal() }
    }
    localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
        ["+", "="].contains(event.charactersIgnoringModifiers ?? "")
      {
        AppController.shared.zoomIn(nil)
        return nil
      }
      return event
    }
    NSApp.activate(ignoringOtherApps: true)
    LaunchProbe.recordIfRequested()
    if let report = ProcessInfo.processInfo.environment["TINYEDITOR_INTEGRATION_REPORT"] {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        IntegrationCheck.run(report: URL(fileURLWithPath: report))
      }
    }
  }
  func application(_ application: NSApplication, openFiles filenames: [String]) {
    open(urls: filenames.map { URL(fileURLWithPath: $0) })
    application.reply(toOpenOrPrint: .success)
  }
  func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    if !flag { if let window = targetWindow() { window.showWindow(nil) } else { _ = newWindow() } }
    NSApp.activate(ignoringOtherApps: true)
    return true
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if terminationApproved { return .terminateNow }
    if isTerminating { return .terminateLater }
    let documents = windows.flatMap(\.documents)
    documents.forEach { $0.refreshDirty() }
    if documents.allSatisfy({ !$0.isDirty }) {
      documents.forEach { $0.resolveRecovery() }
      return .terminateNow
    }
    isTerminating = true
    confirmQuit(documents) { [weak self] ok in
      self?.isTerminating = false
      self?.terminationApproved = ok
      NSApp.reply(toApplicationShouldTerminate: ok)
    }
    return .terminateLater
  }
  func applicationWillTerminate(_ notification: Notification) {
    windows.flatMap(\.documents).forEach { $0.flushRecovery() }
    timer?.invalidate()
  }
  func confirmQuit(_ docs: [EditorDocument], completion: @escaping (Bool) -> Void) {
    guard let doc = docs.first else {
      completion(true)
      return
    }
    guard let owner = owner(of: doc) else {
      confirmQuit(Array(docs.dropFirst()), completion: completion)
      return
    }
    confirmClose(doc, in: owner) { ok in
      if ok {
        doc.resolveRecovery()
        RunLoop.main.perform(inModes: [.default, .modalPanel, .eventTracking]) {
          self.confirmQuit(Array(docs.dropFirst()), completion: completion)
        }
      } else {
        completion(false)
      }
    }
  }
  func targetWindow() -> EditorWindowController? {
    if let key = NSApp.keyWindow, let found = windows.first(where: { $0.window === key }) {
      return found
    }
    if let lastWindow, windows.contains(where: { $0 === lastWindow }) { return lastWindow }
    return windows.last
  }
  func owner(of doc: EditorDocument) -> EditorWindowController? {
    windows.first { $0.documents.contains(where: { $0 === doc }) }
  }
  @discardableResult func newWindow(
    with document: EditorDocument? = nil, inherit: EditorWindowController? = nil
  ) -> EditorWindowController {
    let controller = EditorWindowController(inheritSidebar: inherit)
    windows.append(controller)
    controller.add(document ?? EditorDocument())
    controller.showWindow(nil)
    controller.window?.makeKeyAndOrderFront(nil)
    lastWindow = controller
    return controller
  }
  func forget(_ controller: EditorWindowController) {
    windows.removeAll { $0 === controller }
    if lastWindow === controller { lastWindow = windows.last }
  }
  func handle(_ request: LaunchRequest) {
    var target = targetWindow()
    if request.newWindow {
      target = newWindow()
    } else if request.newTab {
      if let target {
        target.add(EditorDocument())
        target.showWindow(nil)
        target.window?.makeKeyAndOrderFront(nil)
      } else {
        target = newWindow()
      }
    }
    if !request.paths.isEmpty {
      open(urls: request.paths.map { URL(fileURLWithPath: $0) }, in: target)
    } else if target == nil {
      _ = newWindow()
    } else {
      target?.showWindow(nil)
      target?.window?.makeKeyAndOrderFront(nil)
    }
    NSApp.activate(ignoringOtherApps: true)
  }
  func open(urls: [URL], in preferred: EditorWindowController? = nil) {
    var target = preferred ?? targetWindow()
    for input in urls {
      let url = canonical(input)
      if let existing = windows.flatMap(\.documents).first(where: { $0.url == url }),
        let owner = owner(of: existing)
      {
        owner.activate(existing)
        owner.showWindow(nil)
        owner.window?.makeKeyAndOrderFront(nil)
        Settings.shared.touch(url)
        continue
      }
      do {
        let doc = try EditorDocument.open(url)
        if let target {
          if target.documents.count == 1, let blank = target.active, blank.url == nil,
            blank.text.isEmpty, !blank.isDirty
          {
            target.documents.removeAll()
            blank.editor?.removeFromSuperview()
            target.active = nil
          }
          target.add(doc)
          target.showWindow(nil)
          target.window?.makeKeyAndOrderFront(nil)
        } else {
          target = newWindow(with: doc)
        }
        Settings.shared.touch(url)
      } catch { showError(error, window: target?.window) }
    }
  }
  func move(
    _ doc: EditorDocument, from source: EditorWindowController, to target: EditorWindowController,
    index: Int
  ) {
    guard let old = source.documents.firstIndex(where: { $0 === doc }) else { return }
    if source === target {
      source.documents.remove(at: old)
      source.documents.insert(
        doc, at: max(0, min(source.documents.count, index > old ? index - 1 : index)))
      source.tabStrip.rebuild()
      source.activate(doc)
      return
    }
    // Destination is prepared before the source window can disappear.
    target.add(doc, index: index)
    target.window?.makeKeyAndOrderFront(nil)
    source.remove(doc)
  }
  func detach(_ doc: EditorDocument, from source: EditorWindowController, point: NSPoint? = nil) {
    let target = newWindow(with: doc, inherit: source)
    if let point, let window = target.window {
      window.setFrameTopLeftPoint(NSPoint(x: point.x - 140, y: point.y + 15))
    }
    source.remove(doc)
  }
  func save(
    _ doc: EditorDocument, in owner: EditorWindowController, asNew: Bool = false,
    completion: @escaping (Bool) -> Void
  ) {
    owner.activate(doc)
    guard let window = owner.window else {
      completion(false)
      return
    }
    if doc.url == nil || asNew {
      let panel = NSSavePanel()
      panel.title = "保存纯文本"
      panel.nameFieldStringValue = doc.name
      panel.canCreateDirectories = true
      panel.isExtensionHidden = false
      panel.allowsOtherFileTypes = true
      if let url = doc.url { panel.directoryURL = url.deletingLastPathComponent() }
      panel.beginSheetModal(for: window) { response in
        guard response == .OK, let url = panel.url else {
          completion(false)
          return
        }
        if self.windows.flatMap(\.documents).contains(where: {
          $0 !== doc && $0.url == canonical(url)
        }) {
          showError(TinyError("此文件已在其他标签打开，请选择其他路径。"), window: window)
          completion(false)
          return
        }
        do {
          try doc.write(to: url, saveAs: true)
          owner.activate(doc)
          completion(true)
        } catch {
          showError(error, window: window)
          completion(false)
        }
      }
    } else {
      do {
        try doc.write(to: doc.url!)
        owner.activate(doc)
        completion(true)
      } catch {
        showError(error, window: window)
        completion(false)
      }
    }
  }
  func confirmClose(
    _ doc: EditorDocument, in owner: EditorWindowController, completion: @escaping (Bool) -> Void
  ) {
    doc.refreshDirty()
    guard doc.isDirty else {
      completion(true)
      return
    }
    owner.activate(doc)
    owner.showWindow(nil)
    owner.window?.makeKeyAndOrderFront(nil)
    guard let window = owner.window, window.attachedSheet == nil else {
      completion(false)
      return
    }
    let alert = NSAlert()
    alert.messageText = "要保存对“\(doc.name)”的更改吗？"
    alert.informativeText = "未保存的更改会丢失。"
    alert.addButton(withTitle: "保存")
    alert.addButton(withTitle: "取消")
    alert.addButton(withTitle: "不保存")
    alert.beginSheetModal(for: window) { response in
      switch response {
      case .alertFirstButtonReturn:
        RunLoop.main.perform(inModes: [.default, .modalPanel, .eventTracking]) {
          self.save(doc, in: owner, completion: completion)
        }
      case .alertThirdButtonReturn: completion(true)
      default: completion(false)
      }
    }
  }
  func recover(_ records: [RecoveryRecord]) {
    guard let owner = targetWindow(), let window = owner.window else { return }
    let alert = NSAlert()
    alert.messageText = "发现 \(records.count) 份恢复草稿"
    alert.informativeText = "恢复为新文档，不覆盖磁盘文件。选择“稍后”会保留记录。"
    alert.addButton(withTitle: "恢复")
    alert.addButton(withTitle: "稍后")
    alert.beginSheetModal(for: window) { response in
      if response == .alertFirstButtonReturn {
        for record in records { owner.add(EditorDocument.restore(record)) }
      }
    }
  }
  func preferencesChanged() {
    NotificationCenter.default.post(name: .preferencesChanged, object: nil)
  }
  @objc func newWindowAction(_ sender: Any?) { _ = newWindow() }
  @objc func newTabAction(_ sender: Any?) {
    if let owner = targetWindow() { owner.add(EditorDocument()) } else { _ = newWindow() }
  }
  @objc func openAction(_ sender: Any?) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.title = "打开本地文本文件"
    if panel.runModal() == .OK { open(urls: panel.urls) }
  }
  @objc func closeAction(_ sender: Any?) {
    if let owner = targetWindow(), let doc = owner.active { owner.close(doc) }
  }
  @objc func saveAction(_ sender: Any?) {
    if let owner = targetWindow(), let doc = owner.active { save(doc, in: owner) { _ in } }
  }
  @objc func saveAsAction(_ sender: Any?) {
    if let owner = targetWindow(), let doc = owner.active {
      save(doc, in: owner, asNew: true) { _ in }
    }
  }
  @objc func renameAction(_ sender: Any?) {
    if let owner = targetWindow(), let doc = owner.active { owner.rename(doc) }
  }
  @objc func utf8Action(_ sender: Any?) { targetWindow()?.active?.convertUTF8() }
  @objc func togglePreviewAction(_ sender: Any?) { targetWindow()?.togglePreview() }
  @objc func toggleSidebarAction(_ sender: Any?) { targetWindow()?.toggleSidebar() }
  @objc func copySourceAction(_ sender: Any?) {
    if let doc = targetWindow()?.active { pureCopy(doc.text) }
  }
  @objc func zoomIn(_ sender: Any?) {
    Settings.shared.fontSize += 1
    preferencesChanged()
  }
  @objc func zoomOut(_ sender: Any?) {
    Settings.shared.fontSize -= 1
    preferencesChanged()
  }
  @objc func zoomReset(_ sender: Any?) {
    Settings.shared.fontSize = 14
    preferencesChanged()
  }
  @objc func toggleWrap(_ sender: Any?) {
    if let doc = targetWindow()?.active {
      doc.wrap.toggle()
      Settings.shared.wrap = doc.wrap
      doc.editor?.applyPreferences()
    }
  }
  @objc func themeAction(_ sender: NSMenuItem) {
    Settings.shared.theme = sender.representedObject as? String ?? "system"
    preferencesChanged()
  }
  @objc func toggleRemote(_ sender: Any?) {
    Settings.shared.remoteImages.toggle()
    preferencesChanged()
  }
  @objc func previousTab(_ sender: Any?) { cycleTab(-1) }
  @objc func nextTab(_ sender: Any?) { cycleTab(1) }
  func cycleTab(_ delta: Int) {
    guard let owner = targetWindow(), let doc = owner.active,
      let index = owner.documents.firstIndex(where: { $0 === doc }), !owner.documents.isEmpty
    else { return }
    owner.activate(owner.documents[(index + delta + owner.documents.count) % owner.documents.count])
  }
  @objc func detachAction(_ sender: Any?) {
    if let owner = targetWindow(), let doc = owner.active { detach(doc, from: owner) }
  }
  @objc func mergeWindows(_ sender: Any?) {
    guard let target = targetWindow() else { return }
    for source in windows.filter({ $0 !== target }) {
      for doc in source.documents {
        move(doc, from: source, to: target, index: target.documents.count)
      }
    }
  }
  @objc func recentAction(_ sender: NSMenuItem) {
    if let path = sender.representedObject as? String { open(urls: [URL(fileURLWithPath: path)]) }
  }
  @objc func findAction(_ sender: Any?) {
    guard let owner = targetWindow(), let doc = owner.active else { return }
    if doc.previewing {
      doc.previewing = false
      owner.activate(doc)
    }
    if doc.sourcePane().isPaged {
      doc.sourcePane().showPagedFind(replace: false)
      return
    }
    let item = NSMenuItem()
    item.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
    doc.sourcePane().textView.performFindPanelAction(item)
  }
  @objc func replaceAction(_ sender: Any?) {
    guard let owner = targetWindow(), let doc = owner.active else { return }
    if doc.previewing {
      doc.previewing = false
      owner.activate(doc)
    }
    if doc.sourcePane().isPaged {
      doc.sourcePane().showPagedFind(replace: true)
      return
    }
    let item = NSMenuItem()
    item.tag = Int(NSTextFinder.Action.showReplaceInterface.rawValue)
    doc.sourcePane().textView.performFindPanelAction(item)
  }
  @objc func aboutAction(_ sender: Any?) {
    NSApp.orderFrontStandardAboutPanel(options: [
      .applicationName: appName,
      .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        as? String ?? "1.0.1",
      .credits: NSAttributedString(string: "轻量原生文本编辑器\nSwift · AppKit · 离线 Markdown"),
    ])
  }
  func menuNeedsUpdate(_ menu: NSMenu) {
    if menu === recentMenu {
      menu.removeAllItems()
      for path in Settings.shared.recents {
        let item = NSMenuItem(
          title: URL(fileURLWithPath: path).lastPathComponent, action: #selector(recentAction(_:)),
          keyEquivalent: "")
        item.target = self
        item.representedObject = path
        item.toolTip = path
        menu.addItem(item)
      }
      if menu.items.isEmpty {
        let item = NSMenuItem(title: "没有最近文件", action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
      }
    }
  }
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    let doc = targetWindow()?.active
    if menuItem.action == #selector(togglePreviewAction(_:)) {
      return doc?.resolvedFormat == .markdown
    }
    if menuItem.action == #selector(themeAction(_:)) {
      menuItem.state = (menuItem.representedObject as? String) == Settings.shared.theme ? .on : .off
    }
    if menuItem.action == #selector(toggleWrap(_:)) {
      menuItem.state = doc?.wrap == true ? .on : .off
    }
    if menuItem.action == #selector(toggleRemote(_:)) {
      menuItem.state = Settings.shared.remoteImages ? .on : .off
    }
    let needsDoc: [Selector] = [
      #selector(closeAction(_:)), #selector(saveAction(_:)), #selector(saveAsAction(_:)),
      #selector(renameAction(_:)), #selector(utf8Action(_:)), #selector(copySourceAction(_:)),
      #selector(detachAction(_:)), #selector(findAction(_:)), #selector(replaceAction(_:)),
    ]
    return !needsDoc.contains(menuItem.action ?? #selector(aboutAction(_:))) || doc != nil
  }
  func buildMenus() {
    let bar = NSMenu()
    NSApp.mainMenu = bar
    func menu(_ title: String) -> NSMenu {
      let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      let sub = NSMenu(title: title)
      top.submenu = sub
      bar.addItem(top)
      return sub
    }
    func add(
      _ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "",
      _ mods: NSEvent.ModifierFlags = .command, _ target: AnyObject? = nil
    ) {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
      item.keyEquivalentModifierMask = mods
      item.target = target ?? self
      menu.addItem(item)
    }
    let app = menu(appName)
    add(app, "关于 TinyEditor", #selector(aboutAction(_:)))
    app.addItem(.separator())
    add(app, "隐藏 TinyEditor", #selector(NSApplication.hide(_:)), "h", .command, NSApp)
    add(
      app, "隐藏其他", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option],
      NSApp)
    add(app, "显示全部", #selector(NSApplication.unhideAllApplications(_:)), "", [], NSApp)
    app.addItem(.separator())
    add(app, "退出 TinyEditor", #selector(NSApplication.terminate(_:)), "q", .command, NSApp)
    let file = menu("文件")
    add(file, "新建窗口", #selector(newWindowAction(_:)), "n")
    add(file, "新建标签", #selector(newTabAction(_:)), "t")
    add(file, "打开…", #selector(openAction(_:)), "o")
    let recent = NSMenuItem(title: "最近打开", action: nil, keyEquivalent: "")
    recentMenu = NSMenu(title: "最近打开")
    recentMenu.delegate = self
    recent.submenu = recentMenu
    file.addItem(recent)
    file.addItem(.separator())
    add(file, "关闭标签", #selector(closeAction(_:)), "w")
    add(file, "保存", #selector(saveAction(_:)), "s")
    add(file, "另存为…", #selector(saveAsAction(_:)), "s", [.command, .shift])
    add(file, "重命名…", #selector(renameAction(_:)))
    add(file, "转为 UTF-8 编码", #selector(utf8Action(_:)))
    let edit = menu("编辑")
    add(edit, "撤销", Selector(("undo:")), "z", .command, nil)
    edit.items.last?.target = nil
    add(edit, "重做", Selector(("redo:")), "z", [.command, .shift])
    edit.items.last?.target = nil
    edit.addItem(.separator())
    for (title, sel, key) in [
      ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a"),
    ] {
      add(edit, title, Selector(sel), key)
      edit.items.last?.target = nil
    }
    add(edit, "复制整个文档 Markdown／源码", #selector(copySourceAction(_:)), "c", [.command, .shift])
    edit.addItem(.separator())
    add(edit, "查找…", #selector(findAction(_:)), "f")
    add(edit, "替换…", #selector(replaceAction(_:)), "f", [.command, .option])
    let view = menu("显示")
    add(view, "Markdown 预览／编辑", #selector(togglePreviewAction(_:)), "p", [.command, .shift])
    add(view, "最近文件侧边栏", #selector(toggleSidebarAction(_:)), "s", [.command, .control])
    add(view, "自动换行", #selector(toggleWrap(_:)))
    view.addItem(.separator())
    add(view, "放大", #selector(zoomIn(_:)), "+")
    add(view, "缩小", #selector(zoomOut(_:)), "-")
    add(view, "实际大小", #selector(zoomReset(_:)), "0")
    view.addItem(.separator())
    for (title, value) in [("跟随系统", "system"), ("浅色", "light"), ("深色", "dark")] {
      add(view, title, #selector(themeAction(_:)))
      view.items.last?.representedObject = value
    }
    view.addItem(.separator())
    add(view, "允许远程图片", #selector(toggleRemote(_:)))
    let window = menu("窗口")
    NSApp.windowsMenu = window
    add(window, "最小化", #selector(NSWindow.performMiniaturize(_:)), "m")
    window.items.last?.target = nil
    add(window, "上一个标签", #selector(previousTab(_:)), "[", [.command, .shift])
    add(window, "下一个标签", #selector(nextTab(_:)), "]", [.command, .shift])
    add(window, "将标签移到新窗口", #selector(detachAction(_:)))
    add(window, "合并所有窗口", #selector(mergeWindows(_:)))
    add(window, "进入全屏幕", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
    window.items.last?.target = nil
  }
}
