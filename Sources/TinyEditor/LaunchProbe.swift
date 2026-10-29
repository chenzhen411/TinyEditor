import AppKit
import Darwin

let processMainEntry = Date()

/// Measures a fresh process without changing normal launch behavior or clearing system caches.
enum LaunchProbe {
  static func recordIfRequested() {
    guard let path = ProcessInfo.processInfo.environment["TINYEDITOR_LAUNCH_REPORT"],
      ProcessInfo.processInfo.environment["TINYEDITOR_DATA_DIR"] != nil
    else { return }
    let firstDisplay = Date().timeIntervalSince(processMainEntry) * 1000
    DispatchQueue.main.async { record(path: path, firstDisplay: firstDisplay, attempts: 0) }
  }
  private static func record(path: String, firstDisplay: Double, attempts: Int) {
    let app = AppController.shared
    let previews = app.windows.flatMap(\.documents).compactMap(\.preview)
    if previews.contains(where: { $0.readyRevision == 0 }) && attempts < 200 {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        record(path: path, firstDisplay: firstDisplay, attempts: attempts + 1)
      }
      return
    }
    app.windows.forEach { $0.window?.displayIfNeeded() }
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
      MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }
    let values: [String: Any] = [
      "pid": getpid(), "mainToWindowMs": firstDisplay,
      "mainToReadyMs": Date().timeIntervalSince(processMainEntry) * 1000,
      "mainRSSMiB": result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1,
      "previewInstances": previews.count,
      "previewReady": previews.allSatisfy { $0.readyRevision > 0 },
    ]
    if let data = try? JSONSerialization.data(withJSONObject: values, options: .prettyPrinted) {
      try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { NSApp.terminate(nil) }
  }
}
