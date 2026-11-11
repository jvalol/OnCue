import Cocoa

// MenuBarIcon.swift only needs the arm states to exist; the real class lives in the app.
class RecordingManager { enum ArmState { case unarmed, arming, armed, recording } }

// A template image is tinted by macOS to suit the menu bar; on a dark one that means white.
func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
  return NSImage(size: image.size, flipped: false) { rect in
    image.draw(in: rect)
    color.set()
    rect.fill(using: .sourceAtop)
    return true
  }
}

let states: [(String, MenuBarIcon.Appearance)] = [
  ("Unarmed",   MenuBarIcon.appearance(for: .unarmed)),
  ("Arming",    MenuBarIcon.appearance(for: .arming)),
  ("Armed",     MenuBarIcon.appearance(for: .armed)),
  ("Recording", MenuBarIcon.appearance(for: .recording)),
  ("Recording failed", MenuBarIcon.appearance(for: .armed, recordingFailed: true)),
]

let cell: CGFloat = 104, barHeight: CGFloat = 26, labelHeight: CGFloat = 18, gap: CGFloat = 8
let width = cell * CGFloat(states.count), height = barHeight + gap + labelHeight
let scale: CGFloat = 2

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: width, height: height)

NSAppearance.current = NSAppearance(named: .darkAqua)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// The bar: the look of a dark menu bar, rounded so it reads as a strip on the page.
let bar = NSRect(x: 0, y: labelHeight + gap, width: width, height: barHeight)
NSColor(white: 0.17, alpha: 1).setFill()
NSBezierPath(roundedRect: bar, xRadius: 6, yRadius: 6).fill()

let font = NSFont.systemFont(ofSize: 11, weight: .medium)
let style = NSMutableParagraphStyle(); style.alignment = .center
let labelAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(white: 0.35, alpha: 1), .paragraphStyle: style]

for (i, (label, appearance)) in states.enumerated() {
  var image = MenuBarIcon.image(for: appearance)
  if appearance.isTemplate { image = tinted(image, .white) }
  let x = CGFloat(i) * cell + (cell - 18) / 2
  let y = bar.minY + (barHeight - 18) / 2
  image.draw(in: NSRect(x: x, y: y, width: 18, height: 18))
  NSAttributedString(string: label, attributes: labelAttributes)
    .draw(in: NSRect(x: CGFloat(i) * cell, y: 0, width: cell, height: labelHeight))
}

NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(CommandLine.arguments[1]) at \(Int(width * scale))x\(Int(height * scale)) px (\(Int(width))x\(Int(height)) pt)")
