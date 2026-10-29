import Foundation

var assertionCount = 0
var failures: [String] = []
typealias XCTestCase = NSObject
func fail(_ value: String, file: StaticString, line: UInt) {
  failures.append("\(file):\(line): \(value)")
  print("FAIL: \(value) at \(line)")
}
func XCTAssertEqual<T: Equatable>(
  _ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: String = "",
  file: StaticString = #filePath, line: UInt = #line
) {
  assertionCount += 1
  do {
    let av = try a()
    let bv = try b()
    if av != bv { fail("\(av) != \(bv) \(message)", file: file, line: line) }
  } catch { fail(error.localizedDescription, file: file, line: line) }
}
func XCTAssertTrue(
  _ value: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath,
  line: UInt = #line
) { XCTAssertEqual(try value(), true, message, file: file, line: line) }
func XCTAssertFalse(
  _ value: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath,
  line: UInt = #line
) { XCTAssertEqual(try value(), false, message, file: file, line: line) }
func XCTAssertNil<T>(
  _ value: @autoclosure () throws -> T?, _ message: String = "", file: StaticString = #filePath,
  line: UInt = #line
) {
  assertionCount += 1
  do { if try value() != nil { fail("Expected nil: \(message)", file: file, line: line) } } catch {
    fail(error.localizedDescription, file: file, line: line)
  }
}
func XCTAssertThrowsError<T>(
  _ value: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line
) {
  assertionCount += 1
  do {
    _ = try value()
    fail("Expected an error", file: file, line: line)
  } catch {}
}
func XCTUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
  guard let value else {
    fail("Expected nonnil", file: file, line: line)
    throw TinyError("Missing test value")
  }
  return value
}
