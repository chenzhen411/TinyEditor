import AppKit
import ApplicationServices

// Explicitly authorized real input driver for TinyEditor acceptance, never linked into the app.
let driverApplication = NSApplication.shared
driverApplication.setActivationPolicy(.accessory)
driverApplication.finishLaunching()
RunLoop.main.run(until: Date().addingTimeInterval(0.1))
let arguments = Array(CommandLine.arguments.dropFirst())
func fail(_ message:String)->Never { fputs(message+"\n",stderr); exit(1) }
func ownWindow(at point:CGPoint)->Bool {
  let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
  for item in entries {
    guard (item[kCGWindowLayer as String] as? Int) == 0,
      let bounds = item[kCGWindowBounds as String] as? NSDictionary,
      let rect = CGRect(dictionaryRepresentation:bounds),rect.contains(point),
      let pid = item[kCGWindowOwnerPID as String] as? Int32 else { continue }
    return NSRunningApplication(processIdentifier:pid)?.bundleIdentifier == "top.moriarty.TinyEditor"
  }
  return false
}
func mouse(_ type:CGEventType,_ point:CGPoint) {
  guard let e = CGEvent(mouseEventSource:nil,mouseType:type,mouseCursorPosition:point,mouseButton:.left) else { fail("Cannot create event") }
  e.post(tap:.cghidEventTap)
}
func key(_ code:CGKeyCode,_ flags:CGEventFlags = []) {
  let down = CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:true)!
  down.flags = flags; down.post(tap:.cghidEventTap); usleep(60_000)
  let up = CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:false)!
  up.flags = flags; up.post(tap:.cghidEventTap)
}
if arguments.first == "request-access" { let granted = CGRequestPostEventAccess(); try? JSONSerialization.data(withJSONObject:["postAccess":granted]).write(to:URL(fileURLWithPath:"/tmp/TinyEditor-CG-permission.json"));exit(0) }
if arguments.first == "info" {
  let data:[String:Any] = ["trusted":AXIsProcessTrusted(),"postAccess":CGPreflightPostEventAccess(),"primaryHeight":CGDisplayBounds(CGMainDisplayID()).height,"frontmost":NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""]
  let output = try! JSONSerialization.data(withJSONObject:data,options:.sortedKeys); if arguments.count > 1 { try! output.write(to:URL(fileURLWithPath:arguments[1])) } else { print(String(data:output,encoding:.utf8)!) };exit(0)
}
guard CGPreflightPostEventAccess() else { fail("macOS has not granted event posting access to this execution context") }
if arguments.first == "click",arguments.count == 3 {
  let p = CGPoint(x:Double(arguments[1])!,y:Double(arguments[2])!)
  guard ownWindow(at:p) else { fail("Refusing click outside the topmost TinyEditor window") }
  mouse(.mouseMoved,p); usleep(120_000); mouse(.leftMouseDown,p); usleep(90_000);mouse(.leftMouseUp,p)
} else if arguments.first == "drag", arguments.count >= 5 {
  let a = CGPoint(x:Double(arguments[1])!,y:Double(arguments[2])!),b = CGPoint(x:Double(arguments[3])!,y:Double(arguments[4])!)
  guard ownWindow(at:a) else { fail("Refusing drag not originating in the topmost TinyEditor window") }
  mouse(.mouseMoved,a); usleep(150_000); mouse(.leftMouseDown,a);usleep(180_000)
  for i in 1...60 { let t = Double(i)/60; mouse(.leftMouseDragged,CGPoint(x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t)); usleep(22_000) }
  usleep(300_000)
  if arguments.last == "escape" { key(53);usleep(160_000) }
  mouse(.leftMouseUp,b)
} else if arguments.first == "key",arguments.count >= 2 {
  guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "top.moriarty.TinyEditor" else { fail("TinyEditor must be frontmost for keyboard input") }
  let flags:CGEventFlags = arguments.contains("command") ? .maskCommand:[]
  key(CGKeyCode(arguments[1])!,flags)
} else { fail("Usage: info | click x y | drag x1 y1 x2 y2 [escape] | key keycode [command]") }
usleep(250_000)
