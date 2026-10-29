import AppKit

_ = processMainEntry
let instance = SingleInstance()
do {
  let request = LaunchRequest.arguments(CommandLine.arguments)
  if try !instance.acquireOrForward(request) { exit(0) }
  let app = NSApplication.shared
  let delegate = AppController.shared
  delegate.instance = instance
  delegate.initialRequest = request
  app.delegate = delegate
  app.run()
} catch {
  fputs("TinyEditor: \(error.localizedDescription)\n", stderr)
  exit(1)
}
