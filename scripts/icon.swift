import AppKit
let root = CommandLine.arguments[1]
let folder = URL(fileURLWithPath:root).appendingPathComponent("TinyEditor.iconset")
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
func color(_ r:CGFloat,_ g:CGFloat,_ b:CGFloat)->NSColor { NSColor(srgbRed:r/255,green:g/255,blue:b/255,alpha:1) }
for size in [16,32,64,128,256,512,1024] {
 let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 let context = NSGraphicsContext(bitmapImageRep:rep)!; NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
 let transform = NSAffineTransform(); transform.scale(by:CGFloat(size)/1024); transform.concat()
 let rect = NSRect(x:52,y:52,width:920,height:920); let path = NSBezierPath(roundedRect:rect,xRadius:205,yRadius:205)
 NSGraphicsContext.saveGraphicsState(); let shadow = NSShadow(); shadow.shadowBlurRadius = 20; shadow.shadowOffset = NSSize(width:0,height:-14); shadow.shadowColor = NSColor.black.withAlphaComponent(0.25); shadow.set(); color(17,26,36).setFill(); path.fill(); NSGraphicsContext.restoreGraphicsState()
 NSGradient(starting:color(17,26,36),ending:color(41,56,71))!.draw(in:path,angle:90)
 let strokes = NSBezierPath(); strokes.lineWidth = 76; strokes.lineCapStyle = .square; strokes.lineJoinStyle = .round
 strokes.move(to:NSPoint(x:224,y:720)); strokes.line(to:NSPoint(x:800,y:720)); strokes.move(to:NSPoint(x:356,y:720)); strokes.line(to:NSPoint(x:356,y:296)); strokes.move(to:NSPoint(x:604,y:720)); strokes.line(to:NSPoint(x:604,y:296)); strokes.line(to:NSPoint(x:800,y:296)); color(242,247,250).setStroke(); strokes.stroke()
 let mint = NSBezierPath(); mint.lineWidth = 76; mint.lineCapStyle = .square; mint.move(to:NSPoint(x:604,y:508)); mint.line(to:NSPoint(x:782,y:508)); color(122,222,194).setStroke(); mint.stroke()
 NSGraphicsContext.restoreGraphicsState()
 let data = rep.representation(using:.png,properties:[:])!
 if [16,32,128,256,512].contains(size) { try data.write(to:folder.appendingPathComponent("icon_\(size)x\(size).png")) }
 if [32,64,256,512,1024].contains(size) { try data.write(to:folder.appendingPathComponent("icon_\(size/2)x\(size/2)@2x.png")) }
 if size == 1024 { try data.write(to:URL(fileURLWithPath:root).appendingPathComponent("TinyEditor-1024.png")) }
}
