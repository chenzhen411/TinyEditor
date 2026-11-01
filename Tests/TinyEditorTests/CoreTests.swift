import XCTest

@testable import TinyEditor

final class CoreTests: XCTestCase {
  func testEncodingRoundTrips() throws {
    for encoding in TextEncoding.allCases {
      let text = "中文 Unicode\r\nline\r末行\n" + (encoding == .gb18030 ? "" : "😀")
      let bytes = try TextCodec.encode(text, encoding)
      let (decoded, detected) = try TextCodec.decode(bytes)
      XCTAssertEqual(decoded, text)
      XCTAssertEqual(detected, encoding)
      XCTAssertEqual(try TextCodec.encode(decoded, detected), bytes)
    }
  }
  func testBinaryIsRejected() {
    for data in [
      Data([0, 1, 2, 3]), Data([0x50, 0x4b, 0x03, 0x04]), Data([0xff]),
      Data([0x89, 0x50, 0x4e, 0x47]),
    ] { XCTAssertThrowsError(try TextCodec.decode(data)) }
  }
  func testNoLossyEncoding() throws {
    let text = "中文与组合 e\u{301}"
    let data = try TextCodec.encode(text, .gb18030)
    XCTAssertEqual(try TextCodec.decode(data).0, text)
  }
  func testLogicalLinesAndUTF16() {
    let text = "一😀\r\n二\r三\n" as NSString
    let index = LineIndex(text)
    XCTAssertEqual(index.starts, [0, 5, 7, 9])
    XCTAssertEqual(index.line(at: 4), 0)
    XCTAssertEqual(index.line(at: 5), 1)
    XCTAssertEqual(index.line(at: 9), 3)
  }
  func testIncrementalLineIndexMatchesFullScan() {
    let text = NSMutableString(string: "a\r\nb\rc\nlast")
    let index = LineIndex(text)
    var seed: UInt64 = 9_817_281
    func random(_ limit: Int) -> Int {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1
      return Int((seed >> 32) % UInt64(max(1, limit)))
    }
    for _ in 0..<1500 {
      let location = random(text.length + 1)
      let oldLength = random(min(5, text.length - location) + 1)
      let replacements = ["", "\r", "\n", "\r\n", "abc", "x\rY\nZ"]
      let replacement = replacements[random(replacements.count)]
      text.replaceCharacters(in: NSRange(location: location, length: oldLength), with: replacement)
      index.update(
        text, editedRange: NSRange(location: location, length: (replacement as NSString).length),
        delta: (replacement as NSString).length - oldLength)
      XCTAssertEqual(index.newlineTitle, TextCodec.newline(text))
      XCTAssertEqual(
        index.starts, LineIndex(text).starts,
        "at \(location) replacing \(oldLength) with \(replacement.debugDescription)")
    }
  }
  func testFormatResolution() {
    XCTAssertEqual(Format.auto.resolved(URL(fileURLWithPath: "/a.JSON")), .json)
    XCTAssertEqual(Format.auto.resolved(URL(fileURLWithPath: "/no-extension")), .plain)
    XCTAssertEqual(Format.markdown.resolved(URL(fileURLWithPath: "/a.txt")), .markdown)
    XCTAssertEqual(Format.auto.resolved(URL(fileURLWithPath: "/script.SH")), .shell)
    XCTAssertEqual(Format.auto.resolved(URL(fileURLWithPath: "/query.SQL")), .sql)
    XCTAssertEqual(Format.shell.resolved(URL(fileURLWithPath: "/script.txt")), .shell)
    XCTAssertEqual(Format.sql.resolved(URL(fileURLWithPath: "/query.sh")), .sql)
  }
  func testScriptLexicalHighlighting() {
    let shell = "😀\r\n# echo $USER\r\nif test 42; then printf '%s\\n' \"# fi $USER\" $USER ${name:-x}; fi\r\nfile#name"
    let shellSpans = ScriptHighlighting.spans(in: shell, format: .shell)
    let shellText = shell as NSString
    XCTAssertEqual(shellSpans.map { shellText.substring(with: $0.range) }, [
      "# echo $USER", "if", "test", "42", "then", "printf", "'%s\\n'", "\"# fi $USER\"",
      "$USER", "${name:-x}", "fi",
    ])
    XCTAssertEqual(shellSpans.first?.kind, .comment)
    XCTAssertEqual(shellSpans[6].kind, .string)
    XCTAssertEqual(shellSpans[8].kind, .variable)
    let sql = "😀\r\n-- SELECT 1\r\nselect \"from\", 'it''s -- text', 42 FROM t /* WHERE 'x' */ WHERE id = :id;"
    let sqlText = sql as NSString
    let sqlSpans = ScriptHighlighting.spans(in: sql, format: .sql)
    XCTAssertEqual(sqlSpans.map { sqlText.substring(with: $0.range) }, [
      "-- SELECT 1", "select", "\"from\"", "'it''s -- text'", "42", "FROM", "/* WHERE 'x' */", "WHERE", ":id",
    ])
    XCTAssertEqual(sqlSpans[2].kind, .identifier)
    XCTAssertEqual(sqlSpans[3].kind, .string)
    XCTAssertEqual(sqlSpans[6].kind, .comment)
    XCTAssertEqual(sqlSpans[8].kind, .variable)
    XCTAssertEqual(ScriptHighlighting.spans(in: "/* unclosed\nSELECT", format: .sql).first?.kind, .comment)
  }
  func testScriptFormatPreferencePersistence() throws {
    for mode in [Format.shell, .sql] {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: root) }
      let url = root.appendingPathComponent("wrong.txt")
      try Data("source\r\n😀".utf8).write(to: url)
      let doc = try EditorDocument.open(url)
      doc.format = mode
      XCTAssertFalse(doc.isDirty)
      try doc.rename("renamed.txt")
      let reopened = try EditorDocument.open(doc.url!)
      XCTAssertEqual(reopened.resolvedFormat, mode)
      XCTAssertEqual(reopened.text, "source\r\n😀")
      XCTAssertEqual(Settings.shared.format(doc.url), mode)
      let store = PreferenceStore(file: Settings.shared.root.appendingPathComponent("Preferences.json"))
      let saved = store.dictionary(forKey: "formats")
      XCTAssertEqual(saved?[canonical(doc.url!).path] as? String, mode.rawValue)
    }
  }
  func testShellSavePreservesExecutableMode() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("executable.sh")
    let original = "#!/bin/sh\r\nprintf '%s\\n' \"中文 😀\"\r\n"
    try Data(original.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    let doc = try EditorDocument.open(url)
    doc.storage.append(NSAttributedString(string: "# edited\r\n"))
    try doc.write(to: url)
    XCTAssertEqual(doc.resolvedFormat, .shell)
    XCTAssertEqual(doc.newline, "CRLF")
    XCTAssertEqual(try Data(contentsOf: url), Data((original + "# edited\r\n").utf8))
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o755)
  }
  func testResourceBoundary() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    XCTAssertEqual(
      safeLocalURL("images/a.png", base: root)?.path,
      canonical(root).appendingPathComponent("images/a.png").path)
    for path in [
      "../secret.png", "%2e%2e/secret.png", "/etc/passwd", "file:///etc/passwd",
      "https://example.com/x.png", "//host/x", "~/.ssh/a",
    ] { XCTAssertNil(safeLocalURL(path, base: root), path) }
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("escape"), withDestinationURL: URL(fileURLWithPath: "/tmp"))
    XCTAssertNil(safeLocalURL("escape/a.png", base: root))
  }
  func testSaveConflictRenameAndUndoIdentity() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("old.txt")
    try Data("original\r\n".utf8).write(to: url)
    let doc = try EditorDocument.open(url)
    let identity = doc.id
    let manager = doc.undo
    doc.storage.replaceCharacters(in: NSRange(location: 0, length: 8), with: "edited")
    doc.refreshDirty()
    XCTAssertTrue(doc.isDirty)
    doc.format = .json
    try doc.rename("new.txt")
    XCTAssertEqual(doc.id, identity)
    XCTAssertTrue(doc.undo === manager)
    XCTAssertEqual(doc.text, "edited\r\n")
    XCTAssertEqual(try String(contentsOf: doc.url!), "original\r\n")
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    XCTAssertEqual(Settings.shared.format(doc.url), .json)
    try doc.write(to: doc.url!)
    XCTAssertFalse(doc.isDirty)
    XCTAssertEqual(try String(contentsOf: doc.url!), "edited\r\n")
    try Data("external".utf8).write(to: doc.url!, options: .atomic)
    XCTAssertThrowsError(try doc.write(to: doc.url!))
    XCTAssertEqual(try String(contentsOf: doc.url!), "external")
    try doc.reload()
    XCTAssertEqual(doc.text, "external")
    XCTAssertFalse(doc.isDirty)
    let occupied = root.appendingPathComponent("exists.txt")
    try Data("keep".utf8).write(to: occupied)
    XCTAssertThrowsError(try doc.rename("exists.txt"))
    XCTAssertEqual(try String(contentsOf: occupied), "keep")
    for name in ["", "../bad", "a/b", ".", "a:b"] { XCTAssertThrowsError(try doc.rename(name)) }
    doc.resolveRecovery()
  }
  func testNewDocumentNameAndRecovery() throws {
    let doc = EditorDocument()
    try doc.rename("notes.md")
    XCTAssertNil(doc.url)
    XCTAssertEqual(doc.name, "notes.md")
    doc.storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "unsaved 😀")
    doc.flushRecovery()
    let record = try XCTUnwrap(Settings.shared.pendingRecovery().first(where: { $0.id == doc.id }))
    let restored = EditorDocument.restore(record)
    XCTAssertEqual(restored.text, doc.text)
    XCTAssertNil(restored.url)
    XCTAssertTrue(restored.isDirty)
    restored.resolveRecovery()
  }
}
