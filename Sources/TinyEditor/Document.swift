import AppKit

final class EditorDocument: NSObject, NSTextStorageDelegate {
  let id: UUID
  let storage: NSTextStorage
  let lines: LineIndex
  let undo = UndoManager()
  var url: URL?
  var suggestedName = "未命名.txt"
  var encoding: TextEncoding = .utf8
  var savedEncoding: TextEncoding = .utf8
  var format: Format = .auto {
    didSet {
      Settings.shared.setFormat(format, url: url)
      changed()
    }
  }
  var resolvedFormat: Format { format.resolved(url) }
  var previewing = false
  var selection = NSRange(location: 0, length: 0)
  var editor: EditorPane?
  var preview: PreviewPane?
  var sourceScroll = NSPoint.zero
  var previewScroll: Double = 0
  var wrap = Settings.shared.wrap
  private(set) var isDirty = false
  private(set) var conflict = false
  private(set) var missing = false
  var diskVersion: DiskVersion?
  private var savedDigest: Data
  private var editWork: DispatchWorkItem?
  private var recoveryWork: DispatchWorkItem?
  private var previewReleaseWork: DispatchWorkItem?
  private var suppress = false
  private var generation = 0
  private var lastStamp: String = ""
  var name: String { url?.lastPathComponent ?? suggestedName }
  var text: String { storage.string }
  var newline: String { lines.newlineTitle }
  init(text: String = "", url: URL? = nil, encoding: TextEncoding = .utf8, id: UUID = UUID()) {
    self.id = id
    self.url = url
    self.encoding = encoding
    savedEncoding = encoding
    storage = NSTextStorage(string: text)
    lines = LineIndex(text as NSString)
    savedDigest = contentDigest(text)
    super.init()
    storage.delegate = self
    format = Settings.shared.format(url)
    previewing = resolvedFormat == .markdown
    if let url {
      diskVersion = try? DiskVersion.read(url)
      lastStamp = stamp(url)
    }
    undo.groupsByEvent = true
    undo.levelsOfUndo = 500
  }
  static func open(_ url: URL) throws -> EditorDocument {
    let url = canonical(url)
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    let (text, encoding) = try TextCodec.decode(data)
    return EditorDocument(text: text, url: url, encoding: encoding)
  }
  func textStorage(
    _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
    range editedRange: NSRange, changeInLength delta: Int
  ) {
    guard editedMask.contains(.editedCharacters), !suppress else { return }
    lines.update(storage.string as NSString, editedRange: editedRange, delta: delta)
    generation += 1
    let current = generation
    isDirty = true
    editWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      let text = self.text
      let encoding = self.encoding
      let baseline = self.savedDigest
      DispatchQueue.global(qos: .utility).async { [weak self] in
        let digest = contentDigest(text)
        DispatchQueue.main.async { [weak self] in
          guard let self, self.generation == current else { return }
          self.isDirty = digest != baseline || encoding != self.savedEncoding
          self.changed()
          self.scheduleRecovery()
        }
      }
    }
    editWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    // Layout and gutter geometry must only change after NSTextStorage finishes its editing callback.
    DispatchQueue.main.async { [weak self] in
      self?.editor?.contentChanged()
      self?.changed()
    }
  }
  func changed() { NotificationCenter.default.post(name: .documentChanged, object: self) }
  func refreshDirty() { isDirty = contentDigest(text) != savedDigest || encoding != savedEncoding }
  func record(_ resolved: Bool = false) -> RecoveryRecord {
    RecoveryRecord(
      id: id, path: url?.path, name: name, text: text, encoding: encoding, format: format,
      updated: Date(), resolved: resolved)
  }
  func scheduleRecovery() {
    recoveryWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      let record = self.record(!self.isDirty)
      RecoveryWriter.queue.async { Settings.shared.writeRecovery(record) }
    }
    recoveryWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
  }
  func resolveRecovery() {
    recoveryWork?.cancel()
    guard isDirty || FileManager.default.fileExists(atPath: Settings.shared.recoveryURL(id).path)
    else { return }
    let record = record(true)
    RecoveryWriter.queue.sync { Settings.shared.writeRecovery(record) }
  }
  func flushRecovery() {
    refreshDirty()
    if isDirty {
      let record = record()
      RecoveryWriter.queue.sync { Settings.shared.writeRecovery(record) }
    }
  }
  static func restore(_ record: RecoveryRecord) -> EditorDocument {
    let doc = EditorDocument(text: record.text, encoding: record.encoding, id: record.id)
    doc.suggestedName = "恢复—" + record.name
    doc.format = record.format
    doc.savedDigest = contentDigest("")
    doc.isDirty = true
    doc.previewing = doc.resolvedFormat == .markdown
    return doc
  }
  private func stamp(_ url: URL) -> String {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
      return "missing"
    }
    return
      "\((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)|\(attrs[.size] ?? "")|\(attrs[.systemFileNumber] ?? "")"
  }
  func checkExternal() {
    guard let url else { return }
    let next = stamp(url)
    guard next != lastStamp else { return }
    lastStamp = next
    guard let version = try? DiskVersion.read(url) else {
      missing = true
      conflict = true
      changed()
      return
    }
    guard version != diskVersion else { return }
    refreshDirty()
    if !isDirty && !conflict {
      do { try reload() } catch {
        conflict = true
        changed()
      }
    } else {
      conflict = true
      changed()
    }
  }
  func reload() throws {
    guard let url else { return }
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    let (text, enc) = try TextCodec.decode(data)
    suppress = true
    storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
    suppress = false
    lines.rebuild(text as NSString)
    encoding = enc
    savedEncoding = enc
    savedDigest = contentDigest(text)
    diskVersion = try DiskVersion.read(url)
    lastStamp = stamp(url)
    conflict = false
    missing = false
    isDirty = false
    generation += 1
    undo.removeAllActions()
    selection = NSRange(location: min(selection.location, storage.length), length: 0)
    editor?.reload()
    preview?.invalidate()
    resolveRecovery()
    changed()
  }
  func write(to target: URL, saveAs: Bool = false) throws {
    let target = canonical(target)
    if saveAs && conflict && target == url { throw TinyError("冲突文件不能覆盖原路径。请选择其他位置另存为，或先重新载入。") }
    let targetVersion =
      saveAs && FileManager.default.fileExists(atPath: target.path)
      ? try DiskVersion.read(target) : nil
    if !saveAs, let original = url {
      guard !conflict, let version = diskVersion, (try? DiskVersion.read(original)) == version
      else {
        conflict = true
        changed()
        throw TinyError("磁盘文件已被外部修改或删除。直接保存已暂停，请重新载入，或使用“另存为”保留当前内容。")
      }
    }
    let data = try TextCodec.encode(text, encoding)
    var coordinatorError: NSError?
    var writeError: Error?
    let coordinator = NSFileCoordinator(filePresenter: nil)
    coordinator.coordinate(writingItemAt: target, options: .forReplacing, error: &coordinatorError)
    { coordinated in
      do {
        if saveAs, (try? DiskVersion.read(coordinated)) != targetVersion {
          throw TinyError("另存为目标在保存前已变化，已停止覆盖。")
        }
        if !saveAs, let version = self.diskVersion, (try? DiskVersion.read(coordinated)) != version
        {
          throw TinyError("保存前检测到新的外部修改，已停止写入。")
        }
        try data.write(to: coordinated, options: .atomic)
      } catch { writeError = error }
    }
    if let error = writeError ?? coordinatorError { throw error }
    generation += 1
    let old = url
    url = target
    savedDigest = contentDigest(text)
    savedEncoding = encoding
    diskVersion = try DiskVersion.read(target)
    lastStamp = stamp(target)
    conflict = false
    missing = false
    isDirty = false
    if let old, old != target {
      Settings.shared.setFormat(format, url: target)
    } else {
      Settings.shared.setFormat(format, url: target)
    }
    Settings.shared.touch(target)
    resolveRecovery()
    preview?.invalidate()
    changed()
  }
  func rename(_ name: String) throws {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":"),
      !name.contains("\0"), name.utf8.count <= 255
    else { throw TinyError("请输入有效的文件名，不含 /、: 或目录路径。") }
    guard let old = url else {
      suggestedName = name
      changed()
      scheduleRecovery()
      return
    }
    let target = old.deletingLastPathComponent().appendingPathComponent(name)
    if old == target { return }
    guard !FileManager.default.fileExists(atPath: target.path) else {
      throw TinyError("同名文件已存在，请换一个名字。")
    }
    guard !conflict, let diskVersion, (try? DiskVersion.read(old)) == diskVersion else {
      throw TinyError("文件已被外部修改，请先处理冲突再重命名。")
    }
    try FileManager.default.moveItem(at: old, to: target)
    url = target
    lastStamp = stamp(target)
    Settings.shared.moved(from: old, to: target)
    Settings.shared.setFormat(format, url: target)
    preview?.invalidate()
    scheduleRecovery()
    changed()
  }
  func replaceCanonical(range: NSRange, with replacement: String, updateView: Bool = true) {
    guard range.location >= 0, NSMaxRange(range) <= storage.length else { return }
    let old = (text as NSString).substring(with: range)
    let replacementLength = (replacement as NSString).length
    undo.registerUndo(withTarget: self) {
      $0.replaceCanonical(
        range: NSRange(location: range.location, length: replacementLength), with: old)
    }
    storage.replaceCharacters(in: range, with: replacement)
    selection = NSRange(location: range.location + replacementLength, length: 0)
    if updateView { editor?.refreshProjection(around: selection.location) }
  }
  func convertUTF8() {
    let old = encoding
    guard old != .utf8 else { return }
    undo.registerUndo(withTarget: self) { target in target.setEncoding(old) }
    setEncoding(.utf8, register: false)
  }
  private func setEncoding(_ value: TextEncoding, register: Bool = true) {
    if register {
      let old = encoding
      undo.registerUndo(withTarget: self) { $0.setEncoding(old) }
    }
    encoding = value
    refreshDirty()
    scheduleRecovery()
    changed()
  }
  func sourcePane() -> EditorPane {
    if let editor { return editor }
    let pane = EditorPane(document: self)
    editor = pane
    return pane
  }
  func previewPane() -> PreviewPane {
    previewReleaseWork?.cancel()
    if let preview { return preview }
    let pane = PreviewPane(document: self)
    preview = pane
    return pane
  }
  func schedulePreviewRelease() {
    previewReleaseWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.preview?.window == nil else { return }
      self.preview = nil
    }
    previewReleaseWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
  }
}
enum RecoveryWriter {
  static let queue = DispatchQueue(label: "TinyEditor.recovery", qos: .utility)

}
