import AppKit
import CoreGraphics

// Vector-native artwork; iOS/watchOS apply their own icon masks.
let style = CommandLine.arguments.contains("--dark") ? "dark" : CommandLine.arguments.contains("--tinted") ? "tinted" : "light"
func color(_ hex: UInt32) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255,
            blue: CGFloat(hex & 255)/255, alpha: 1)
}
let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
let ink = color(style == "tinted" ? 0x242424 : 0x124C50)
let paper = color(style == "dark" ? 0xD6E6DF : 0xFFF7E7)
let sage = color(style == "tinted" ? 0xC8C8C8 : 0xB1D6C5)
let highlight = color(style == "tinted" ? 0xEEEEEE : 0xECCF86)
let top = color(style == "dark" ? 0x133236 : style == "tinted" ? 0x171717 : 0x0E444B)
let bottom = color(style == "dark" ? 0x1E615C : style == "tinted" ? 0x525252 : 0x218C7D)
NSGradient(starting: bottom, ending: top)!.draw(in: NSRect(x: 0,y: 0,width: size,height: size), angle: 70)
func roundRect(_ rect: NSRect, radius: CGFloat, fill: NSColor) {
    fill.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
func circle(_ rect: NSRect, fill: NSColor) { fill.setFill(); NSBezierPath(ovalIn: rect).fill() }
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow(); shadow.shadowColor = color(0x062C31).withAlphaComponent(0.3); shadow.shadowBlurRadius = 28; shadow.shadowOffset = NSSize(width: 0,height: -20); shadow.set()
roundRect(NSRect(x: 172,y: 214,width: 636,height: 580), radius: 76, fill: paper)
NSGraphicsContext.restoreGraphicsState()
roundRect(NSRect(x: 172,y: 650,width: 636,height: 144), radius: 76, fill: sage)
sage.setFill(); NSBezierPath(rect: NSRect(x: 172,y: 650,width: 636,height: 65)).fill()
for x in [302, 619] { roundRect(NSRect(x: x,y: 738,width: 54,height: 111),radius: 27,fill: paper) }
for (x,y) in [(264,494),(441,494),(618,494),(264,329),(441,329)] {
    roundRect(NSRect(x: x,y: y,width: 98,height: 98),radius: 25,fill: x == 264 && y == 494 ? highlight : ink.withAlphaComponent(0.85))
}
// Clock badge is legible at the Watch app's smallest icon size.
NSGraphicsContext.saveGraphicsState()
shadow.shadowOffset = NSSize(width: 0,height: -9); shadow.shadowBlurRadius = 19; shadow.set()
circle(NSRect(x: 533,y: 131,width: 340,height: 340),fill: paper)
NSGraphicsContext.restoreGraphicsState()
circle(NSRect(x: 552,y: 150,width: 302,height: 302),fill: ink)
let hands = NSBezierPath(); hands.lineWidth = 23; hands.lineCapStyle = .round
hands.move(to: NSPoint(x: 703,y: 388)); hands.line(to: NSPoint(x: 703,y: 301)); hands.line(to: NSPoint(x: 771,y: 262))
paper.setStroke(); hands.stroke()
circle(NSRect(x: 687,y: 285,width: 32,height: 32),fill: highlight)
NSGraphicsContext.restoreGraphicsState()
let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
let png = bitmap.representation(using: .png, properties: [:])!
for path in CommandLine.arguments.dropFirst() where !path.hasPrefix("--") { try png.write(to: URL(fileURLWithPath: path)) }
