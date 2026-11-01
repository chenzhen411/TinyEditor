import AppKit
import CoreFoundation
import CryptoKit

let appName = "TinyEditor"
let defaultFontSize: CGFloat = 14

struct TinyError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
  init(_ message: String) { self.message = message }
}

enum Format: String, CaseIterable, Codable {
  case auto, plain, markdown, json, yaml, shell, sql
  var title: String {
    switch self {
    case .auto: return "自动识别"
    case .plain: return "纯文本"
    case .markdown: return "Markdown"
    case .json: return "JSON"
    case .yaml: return "YAML"
    case .shell: return "Shell"
    case .sql: return "SQL"
    }
  }
  func resolved(_ url: URL?) -> Format {
    guard self == .auto else { return self }
    switch url?.pathExtension.lowercased() {
    case "md", "markdown": return .markdown
    case "json": return .json
    case "yaml", "yml": return .yaml
    case "sh": return .shell
    case "sql": return .sql
    default: return .plain
    }
  }
}
enum TextEncoding: String, Codable, CaseIterable {
  case utf8, utf8BOM, utf16LE, utf16BE, gb18030
  var title: String {
    switch self {
    case .utf8: return "UTF-8"
    case .utf8BOM: return "UTF-8 BOM"
    case .utf16LE: return "UTF-16 LE BOM"
    case .utf16BE: return "UTF-16 BE BOM"
    case .gb18030: return "GB18030"
    }
  }
  var foundation: String.Encoding {
    switch self {
    case .utf8, .utf8BOM: return .utf8
    case .utf16LE: return .utf16LittleEndian
    case .utf16BE: return .utf16BigEndian
    case .gb18030:
      return String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
          CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    }
  }
  var prefix: Data {
    switch self {
    case .utf8BOM: return Data([0xef, 0xbb, 0xbf])
    case .utf16LE: return Data([0xff, 0xfe])
    case .utf16BE: return Data([0xfe, 0xff])
    default: return Data()
    }
  }
}
struct TextCodec {
  static func decode(_ data: Data) throws -> (String, TextEncoding) {
    if data.starts(with: [0x50, 0x4b, 0x03, 0x04]) || data.starts(with: [0x89, 0x50, 0x4e, 0x47])
      || data.starts(with: [0x25, 0x50, 0x44, 0x46])
    {
      throw TinyError("这是二进制文件，无法作为文本打开。")
    }
    let enc: TextEncoding
    let body: Data
    if data.starts(with: [0xef, 0xbb, 0xbf]) {
      enc = .utf8BOM
      body = data.dropFirst(3)
    } else if data.starts(with: [0xff, 0xfe]) {
      enc = .utf16LE
      body = data.dropFirst(2)
    } else if data.starts(with: [0xfe, 0xff]) {
      enc = .utf16BE
      body = data.dropFirst(2)
    } else if String(data: data, encoding: .utf8) != nil {
      enc = .utf8
      body = data
    } else {
      enc = .gb18030
      body = data
    }
    guard let value = String(data: body, encoding: enc.foundation) else {
      throw TinyError("无法识别文本编码。支持 UTF-8、带 BOM 的 UTF-16 和 GB18030。")
    }
    let sample = value.unicodeScalars.prefix(8192)
    if sample.contains(where: { $0.value == 0 })
      || sample.filter({ $0.value < 32 && ![9, 10, 12, 13].contains($0.value) }).count
        > max(2, sample.count / 100)
    {
      throw TinyError("内容包含二进制控制字符，已拒绝打开以保护原文件。")
    }
    guard value.data(using: enc.foundation, allowLossyConversion: false) == body else {
      throw TinyError("内容不能以原编码无损往返，已拒绝打开。")
    }
    return (value, enc)
  }
  static func encode(_ text: String, _ encoding: TextEncoding) throws -> Data {
    guard let body = text.data(using: encoding.foundation, allowLossyConversion: false),
      String(data: body, encoding: encoding.foundation)?.utf16.elementsEqual(text.utf16) == true
    else { throw TinyError("当前字符无法以 \(encoding.title) 无损保存。请在“文件”菜单选择“转为 UTF-8 编码”后保存。") }
    return encoding.prefix + body
  }
  static func newline(_ text: NSString) -> String {
    var lf = 0
    var cr = 0
    var crlf = 0
    var i = 0
    while i < text.length {
      let c = text.character(at: i)
      if c == 13 {
        if i + 1 < text.length && text.character(at: i + 1) == 10 {
          crlf += 1
          i += 1
        } else {
          cr += 1
        }
      } else if c == 10 {
        lf += 1
      }
      i += 1
    }
    let kinds = [(lf, "LF"), (crlf, "CRLF"), (cr, "CR")].filter { $0.0 > 0 }
    return kinds.count > 1 ? "混合换行" : (kinds.first?.1 ?? "LF")
  }
}

final class LineIndex {
  private(set) var starts: [Int] = [0]
  private var breakKinds: [UInt8] = []
  private var scannedKinds: [UInt8] = []
  private var breakCounts = [0, 0, 0, 0]
  var newlineTitle: String {
    let kinds = (1...3).filter { breakCounts[$0] > 0 }
    if kinds.count > 1 { return "混合换行" }
    switch kinds.first {
    case 2: return "CRLF"
    case 3: return "CR"
    default: return "LF"
    }
  }
  init(_ text: NSString = "") { rebuild(text) }
  private func scan(_ text: NSString, from: Int, to: Int) -> [Int] {
    var result = [from]
    var i = from
    scannedKinds = []
    while i < to {
      let c = text.character(at: i)
      if c == 13 {
        if i + 1 < to && text.character(at: i + 1) == 10 {
          i += 1
          scannedKinds.append(2)
        } else {
          scannedKinds.append(3)
        }
        result.append(i + 1)
      } else if c == 10 {
        result.append(i + 1)
        scannedKinds.append(1)
      }
      i += 1
    }
    return result
  }
  func rebuild(_ text: NSString) {
    starts = scan(text, from: 0, to: text.length)
    breakKinds = scannedKinds
    breakCounts = [0, 0, 0, 0]
    for kind in breakKinds { breakCounts[Int(kind)] += 1 }
  }

  func line(at offset: Int) -> Int {
    var low = 0
    var high = starts.count
    while low < high {
      let mid = (low + high) / 2
      if starts[mid] <= offset { low = mid + 1 } else { high = mid }
    }
    return max(0, low - 1)
  }
  func update(_ text: NSString, editedRange: NSRange, delta: Int) {
    let oldEnd = editedRange.location + editedRange.length - delta
    let first = max(0, line(at: max(0, editedRange.location - 1)) - 1)
    let last = min(starts.count, line(at: oldEnd) + 2)
    let beginning = starts[first]
    let boundary = last < starts.count ? starts[last] + delta : text.length
    var replacement = scan(text, from: beginning, to: max(beginning, boundary))
    if last < starts.count && replacement.last == boundary { replacement.removeLast() }
    let tail = starts[last...].map { $0 + delta }
    for kind in breakKinds[min(first, breakKinds.count)..<min(last, breakKinds.count)] {
      breakCounts[Int(kind)] -= 1
    }
    for kind in scannedKinds { breakCounts[Int(kind)] += 1 }
    let kindsTail = last < breakKinds.count ? Array(breakKinds[last...]) : []
    breakKinds.replaceSubrange(min(first, breakKinds.count)..., with: scannedKinds + kindsTail)
    starts.replaceSubrange(first..., with: replacement + tail)
  }
}
struct DiskVersion: Equatable {
  let digest: Data
  static func read(_ url: URL) throws -> DiskVersion {
    DiskVersion(digest: Data(SHA256.hash(data: try Data(contentsOf: url, options: .mappedIfSafe))))
  }
}
func contentDigest(_ text: String) -> Data { Data(SHA256.hash(data: Data(text.utf8))) }
func canonical(_ url: URL) -> URL {
  var ancestor = url.standardizedFileURL
  var tail: [String] = []
  while !FileManager.default.fileExists(atPath: ancestor.path) && ancestor.path != "/" {
    tail.insert(ancestor.lastPathComponent, at: 0)
    ancestor.deleteLastPathComponent()
  }
  return tail.reduce(ancestor.resolvingSymlinksInPath()) { $0.appendingPathComponent($1) }
}

struct RecoveryRecord: Codable {
  var id: UUID
  var path: String?
  var name: String
  var text: String
  var encoding: TextEncoding
  var format: Format
  var updated: Date
  var resolved: Bool
}
final class PreferenceStore {
  private let native: UserDefaults?
  private let file: URL?
  private var values: [String: Any] = [:]
  init(file: URL? = nil) {
    self.file = file
    native = file == nil ? .standard : nil
    if let file, let data = try? Data(contentsOf: file),
      let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
      values = stored
    }
  }
  func object(forKey key: String) -> Any? { native?.object(forKey: key) ?? values[key] }
  func string(forKey key: String) -> String? { object(forKey: key) as? String }
  func double(forKey key: String) -> Double { (object(forKey: key) as? NSNumber)?.doubleValue ?? 0 }
  func bool(forKey key: String) -> Bool { (object(forKey: key) as? NSNumber)?.boolValue ?? false }
  func stringArray(forKey key: String) -> [String]? { object(forKey: key) as? [String] }
  func dictionary(forKey key: String) -> [String: Any]? { object(forKey: key) as? [String: Any] }
  func set(_ value: Any, forKey key: String) {
    if let native {
      native.set(value, forKey: key)
    } else {
      values[key] = value
      if let file,
        let data = try? JSONSerialization.data(withJSONObject: values, options: .sortedKeys)
      {
        try? data.write(to: file, options: .atomic)
      }
    }
  }
}
final class Settings {
  static let shared = Settings()
  let root: URL
  let defaults: PreferenceStore
  private init() {
    if let isolated = ProcessInfo.processInfo.environment["TINYEDITOR_DATA_DIR"] {
      root = URL(fileURLWithPath: isolated)
      try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      defaults = PreferenceStore(file: root.appendingPathComponent("Preferences.json"))
    } else {
      root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TinyEditor")
      defaults = PreferenceStore()
    }
    try? FileManager.default.createDirectory(
      at: root.appendingPathComponent("Recovery"), withIntermediateDirectories: true)
  }
  var fontSize: CGFloat {
    get {
      let value = defaults.double(forKey: "fontSize")
      return value == 0 ? 14 : min(32, max(10, value))
    }
    set { defaults.set(newValue, forKey: "fontSize") }
  }
  var theme: String {
    get { defaults.string(forKey: "theme") ?? "system" }
    set { defaults.set(newValue, forKey: "theme") }
  }
  var remoteImages: Bool {
    get { defaults.bool(forKey: "remoteImages") }
    set { defaults.set(newValue, forKey: "remoteImages") }
  }
  var wrap: Bool {
    get { defaults.object(forKey: "wrap") as? Bool ?? true }
    set { defaults.set(newValue, forKey: "wrap") }
  }
  var recents: [String] {
    get { defaults.stringArray(forKey: "recents") ?? [] }
    set {
      defaults.set(Array(newValue.prefix(100)), forKey: "recents")
      NotificationCenter.default.post(name: .recentsChanged, object: nil)
    }
  }
  func touch(_ url: URL) {
    let path = canonical(url).path
    var all = recents
    all.removeAll { $0 == path }
    all.insert(path, at: 0)
    recents = all
  }
  func format(_ url: URL?) -> Format {
    guard let url else { return .auto }
    return Format(rawValue: formats[url.path] ?? "auto") ?? .auto
  }
  private var formats: [String: String] {
    get { defaults.dictionary(forKey: "formats") as? [String: String] ?? [:] }
    set { defaults.set(newValue, forKey: "formats") }
  }
  func setFormat(_ value: Format, url: URL?) {
    guard let url else { return }
    var all = formats
    all[url.path] = value.rawValue
    formats = all
  }
  func moved(from: URL, to: URL) {
    var all = formats
    all[to.path] = all.removeValue(forKey: from.path)
    formats = all
    var paths = recents
    paths.removeAll { $0 == from.path || $0 == to.path }
    paths.insert(to.path, at: 0)
    recents = paths
  }
  func recoveryURL(_ id: UUID) -> URL {
    root.appendingPathComponent("Recovery/\(id.uuidString).json")
  }
  func writeRecovery(_ record: RecoveryRecord) {
    do {
      let data = try JSONEncoder().encode(record)
      try data.write(to: recoveryURL(record.id), options: .atomic)
    } catch { NSLog("Recovery failed: %@", error.localizedDescription) }
  }
  func pendingRecovery() -> [RecoveryRecord] {
    ((try? FileManager.default.contentsOfDirectory(
      at: root.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil)) ?? [])
      .compactMap {
        guard let data = try? Data(contentsOf: $0) else { return nil }
        return try? JSONDecoder().decode(RecoveryRecord.self, from: data)
      }.filter { !$0.resolved }.sorted { $0.updated < $1.updated }
  }
}
extension Notification.Name {
  static let documentChanged = Notification.Name("TinyEditor.documentChanged")
  static let recentsChanged = Notification.Name("TinyEditor.recentsChanged")
  static let preferencesChanged = Notification.Name("TinyEditor.preferencesChanged")
}
func showError(_ error: Error, window: NSWindow? = nil) {
  let alert = NSAlert(error: error)
  if let window, window.attachedSheet == nil {
    alert.beginSheetModal(for: window)
  } else {
    alert.runModal()
  }
}
func pureCopy(_ value: String) {
  NSPasteboard.general.clearContents()
  NSPasteboard.general.setString(value, forType: .string)
}
